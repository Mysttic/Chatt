import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
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
  /// `applied: false`), gdy ekran jest zablokowany albo okno jest poza
  /// zasięgiem.
  Future<RemoteInputApplied> apply(List<RemoteInputOp> ops);

  /// Zgoda wydana albo zakończona. Strona natywna pokazuje wtedy swój
  /// wskaźnik (pasek klawiatury Chatt, pływający pasek na Windows) albo go
  /// chowa.
  Future<void> setSession({required bool active, String peerName = ''});

  /// Pola samego Chatta chwilowo bez pisania: wisi karta z pytaniem albo to
  /// urządzenie samo pisze na innym (jego ekran pisania odesłałby wpisany
  /// tekst dalej). Strona natywna zgłasza wtedy własne okno jako nieaktywne,
  /// a na Windows urywa paczkę, która właśnie się tam wpisuje.
  Future<void> holdOwnApp(bool on);

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

  /// Rodzaj pola z fokusem we własnym oknie Chatta (Windows). Kod natywny
  /// nie pyta wtedy UI Automation, bo odpowiadałby na to wątek platformy,
  /// który czeka na wynik, i zgłasza tylko `ownWindow`. Drzewo widżetów zna
  /// aplikacja, więc to ona to ustawia (`RemoteInputDesktop`).
  static RemoteInputField Function()? ownWindowField;

  static RemoteInputTarget _target(Map<String, Object?>? json) {
    final cel = RemoteInputTarget.fromJson(json);
    final pole = ownWindowField;
    if (json?['ownWindow'] != true || pole == null || !cel.active) return cel;
    return RemoteInputTarget(
      active: cel.active,
      field: pole(),
      action: cel.action,
      app: cel.app,
      appLabel: cel.appLabel,
      ownApp: cel.ownApp,
      locked: cel.locked,
      elevated: cel.elevated,
    );
  }

  /// Strona natywna ma odpowiadać od razu. Wywołanie, które utknęło (okno,
  /// które nie odpowiada, zerwane połączenie z klawiaturą), kończy się po
  /// tym czasie jak brak ujścia: inaczej wstrzymałoby wszystkie następne
  /// paczki.
  static const Duration _callTimeout = Duration(seconds: 5);

  /// Nieudane wywołanie strony natywnej: nazwa metody i kod błędu
  /// (`timeout` przy przekroczonym czasie). Opisu błędu nie ma celowo: przy
  /// wpisywaniu strona natywna widzi cudze okna i pola, a dziennik ma o nich
  /// milczeć. Kanał jest jeden na proces, więc i ten hak: ustawia go
  /// `AppServices` przy starcie i to on pilnuje, żeby powtarzający się błąd
  /// nie zalał dziennika.
  static void Function(String method, String code)? onCallError;

  static void _zglos(String method, String code) {
    try {
      onCallError?.call(method, code);
    } catch (_) {
      // Zgłoszenie jest dodatkiem: wywołanie i tak kończy się „nie wyszło”.
    }
  }

  static Future<Map<String, Object?>?> _call(
    String method, [
    Map<String, Object?>? args,
    Duration timeout = _callTimeout,
  ]) async {
    if (!isSupported) return null;
    try {
      return await _channel
          .invokeMapMethod<String, Object?>(method, args)
          .timeout(timeout);
    } on PlatformException catch (error) {
      _zglos(method, error.code);
      return null;
    } on TimeoutException {
      // Strona natywna utknęła (okno, które nie odpowiada).
      _zglos(method, 'timeout');
      return null;
    } catch (_) {
      // MissingPluginException, brak wiązania w teście bez Fluttera.
      return null;
    }
  }

  @override
  Future<RemoteInputTarget> status() async => _target(await _call('status'));

  @override
  Future<RemoteInputApplied> apply(List<RemoteInputOp> ops) async {
    final json = await _call(
      'apply',
      {
        'ops': [for (final op in ops) op.toJson()],
      },
      _callTimeout + remoteInputTypingTime(ops),
    );
    return (
      applied: json?['applied'] == true,
      target: _target(json),
    );
  }

  @override
  Future<void> setSession({required bool active, String peerName = ''}) =>
      _call('setSession', {'active': active, 'peerName': peerName});

  @override
  Future<void> holdOwnApp(bool on) => _call('holdOwnApp', {'on': on});

  @override
  Future<bool> setImeEnabled(bool on) async =>
      (await _call('setImeEnabled', {'on': on}))?['ok'] == true;

  /// Wskaźnik trwającej zgody poza oknem aplikacji: na Windows pływający
  /// pasek „Pisze: …" ze Stopem, widoczny także przy oknie schowanym
  /// w zasobniku. Teksty idą z Darta, bo tylko tu jest wybrany język.
  static Future<bool> showIndicator({
    required String text,
    required String stop,
  }) async =>
      (await _call('showIndicator', {'text': text, 'stop': stop}))?['ok'] ==
      true;

  static Future<bool> hideIndicator() async =>
      (await _call('hideIndicator'))?['ok'] == true;

  /// Android: czy klawiatura Chatt jest włączona w systemie i czy jest
  /// bieżącą klawiaturą. Na innych platformach obie odpowiedzi to `false`.
  static Future<({bool enabled, bool selected})> imeState() async {
    final json = await _call('status');
    return (
      enabled: json?['imeEnabled'] == true,
      selected: json?['imeSelected'] == true,
    );
  }

  /// Android: ekran klawiatur w ustawieniach systemu.
  static Future<bool> openImeSettings() async =>
      (await _call('openImeSettings'))?['ok'] == true;

  /// Android: systemowe okno wyboru klawiatury.
  static Future<bool> showImePicker() async =>
      (await _call('showImePicker'))?['ok'] == true;

  /// Android: zgoda kliknięta na karcie. Okno wyboru klawiatury, gdy Chatt
  /// nie jest bieżącą, a potem zejście aplikacji na dół.
  static Future<bool> afterAccept() async =>
      (await _call('afterAccept'))?['ok'] == true;

  /// Android: zgoda bez karty, a klawiatura Chatt nie jest bieżąca.
  static Future<bool> notifySwitchKeyboard({
    required String title,
    required String body,
  }) async =>
      (await _call('notifySwitchKeyboard', {'title': title, 'body': body}))?[
          'ok'] ==
      true;

  /// Wywołania od strony natywnej: Stop stuknięty na pasku i (Android)
  /// klawiatura Chatt, która po ekranie blokady nie jest już bieżąca.
  /// Rejestracja niczego po drugiej stronie nie woła.
  static void listen({
    required void Function() onStop,
    void Function()? onKeyboardLost,
  }) {
    if (!isSupported) return;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'stopRequested') onStop();
        if (call.method == 'keyboardLost') onKeyboardLost?.call();
        return null;
      });
    } catch (_) {
      // Brak wiązania (test bez Fluttera): nie ma skąd przyjść Stopowi.
    }
  }
}
