import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';

import '../network/protocol.dart';

/// Wynik wpisania paczki: czy operacje trafiły do pola i jak wygląda cel
/// zaraz potem.
typedef RemoteInputApplied = ({bool applied, RemoteInputTarget target});

/// Ujście zdalnej klawiatury po stronie odbiorcy: to tu operacje z sieci
/// zamieniają się w znaki w polu z fokusem.
///
/// Domyślnie [RemoteInputChannel], czyli kod natywny (IME na Androidzie,
/// `SendInput` na Windows). Testy podstawiają własne, które zapisuje
/// operacje w pamięci i odpowiada sztucznym celem.
abstract class RemoteInputSink {
  /// Czy na tej platformie w ogóle jest dokąd pisać.
  bool get supported;

  /// Stan pola z fokusem, bez wpisywania czegokolwiek.
  Future<RemoteInputTarget> status();

  /// Wpisuje operacje po kolei. Dostaje wyłącznie `insert`, `bs`, `del`
  /// i `action`; ping i stop załatwia serwis. Ujście samo odmawia (zwraca
  /// `applied: false`), gdy fokus jest w Chatcie, ekran jest zablokowany
  /// albo okno jest poza zasięgiem.
  Future<RemoteInputApplied> apply(List<RemoteInputOp> ops);

  /// Zgoda wydana albo zakończona. Strona natywna pokazuje wtedy swój
  /// wskaźnik (pasek klawiatury Chatt, pływający pasek na Windows) albo go
  /// chowa.
  Future<void> setSession({required bool active, String peerName = ''});

  /// Włącza albo wyłącza komponent klawiatury w systemie (Android). Woła to
  /// wyłącznie przełącznik dodatku.
  Future<bool> setImeEnabled(bool on);
}

/// Dart-owa strona kanału `chatt/remoteinput`.
///
/// Nigdy nie rzuca: brak kodu natywnego, błąd po drugiej stronie i brak
/// wiązania w testach kończą się odpowiedzią „nie ma dokąd pisać".
class RemoteInputChannel implements RemoteInputSink {
  const RemoteInputChannel();

  static const _channel = MethodChannel('chatt/remoteinput');

  /// Kod natywny jest na Androidzie i Windows.
  static bool get isSupported =>
      debugSupported ?? (Platform.isAndroid || Platform.isWindows);

  /// Podmiana dla testów, jak `BtChannel.debugSupported`: CI stoi na
  /// Linuksie, a test ma sprawdzić, że kanał milczy z powodu wyłączonego
  /// dodatku.
  @visibleForTesting
  static bool? debugSupported;

  @override
  bool get supported => isSupported;

  /// Strona natywna ma odpowiadać od razu. Wywołanie, które utknęło (okno,
  /// które nie odpowiada, zerwane połączenie z klawiaturą), kończy się po
  /// tym czasie jak brak ujścia: inaczej wstrzymałoby wszystkie następne
  /// paczki.
  static const Duration _callTimeout = Duration(seconds: 5);

  static Future<Map<String, Object?>?> _call(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (!isSupported) return null;
    try {
      return await _channel
          .invokeMapMethod<String, Object?>(method, args)
          .timeout(_callTimeout);
    } on PlatformException catch (error) {
      debugPrint('chatt/remoteinput $method: ${error.code}');
      return null;
    } catch (_) {
      // MissingPluginException, przekroczony czas, brak wiązania w teście
      // bez Fluttera.
      return null;
    }
  }

  @override
  Future<RemoteInputTarget> status() async =>
      RemoteInputTarget.fromJson(await _call('status'));

  @override
  Future<RemoteInputApplied> apply(List<RemoteInputOp> ops) async {
    final json = await _call('apply', {
      'ops': [for (final op in ops) op.toJson()],
    });
    return (
      applied: json?['applied'] == true,
      target: RemoteInputTarget.fromJson(json),
    );
  }

  @override
  Future<void> setSession({required bool active, String peerName = ''}) =>
      _call('setSession', {'active': active, 'peerName': peerName});

  @override
  Future<bool> setImeEnabled(bool on) async =>
      (await _call('setImeEnabled', {'on': on}))?['ok'] == true;
}
