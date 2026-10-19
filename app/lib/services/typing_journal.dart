import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../data/db.dart';
import '../network/protocol.dart';

// Historia pisania zdalną klawiaturą (issue #50). Obie strony zapisują to
// samo zdarzenie każda u siebie: nadawca to, co wysłał, i to, co odbiorca
// odpowiedział, odbiorca to, co przyszło, i to, co ujście wpisało. Wiersze
// leżą w zaszyfrowanej bazie. Tekst wpisany w pole hasła albo pole
// nieznanego rodzaju nie trafia tu wcale: zostaje po nim liczba znaków.

/// Jak skończyła się prośba o sesję pisania. Napisy, bo leżą w bazie
/// i trafiają do eksportu: nowe tylko dopisywać.
abstract final class TypingResult {
  /// Zgoda z karty.
  static const accepted = 'accepted';

  /// Zgoda z karty razem z „Nie pytaj więcej".
  static const acceptedAlways = 'acceptedAlways';

  /// Bez karty: rozmówca miał już „Nie pytaj więcej".
  static const automatic = 'automatic';
  static const rejected = 'rejected';
  static const noAnswer = 'noAnswer';
  static const busy = 'busy';
  static const notEnabled = 'notEnabled';
  static const cancelled = 'cancelled';
  static const unreachable = 'unreachable';
  static const olderPeer = 'olderPeer';

  /// Czy prośba skończyła się sesją.
  static bool started(String result) =>
      result == accepted || result == acceptedAlways || result == automatic;
}

/// Dlaczego sesja pisania się skończyła. Napisy jak w [TypingResult].
abstract final class TypingEnd {
  /// Stop na tym urządzeniu (pasek, zasobnik, ekran pisania).
  static const stoppedHere = 'stoppedHere';

  /// Druga strona zakończyła sesję.
  static const stoppedByPeer = 'stoppedByPeer';

  /// Zgoda wygasła: pół godziny bez pisania albo osiem godzin od zgody.
  static const expired = 'expired';

  /// Zgaszony przełącznik „Pozwól pisać na tym urządzeniu".
  static const receiveOff = 'receiveOff';

  /// Wyłączony dodatek klawiatury.
  static const addonOff = 'addonOff';

  /// Ta sama strona zaczęła nową sesję w miejsce tej.
  static const replaced = 'replaced';

  /// Rozmówca usunięty z listy urządzeń.
  static const peerRemoved = 'peerRemoved';

  /// Tarcza rozmówcy zdjęta albo odbiór zgaszony w trakcie sesji.
  static const notAllowed = 'notAllowed';

  /// Łącze padło: nadawca nie dostał odpowiedzi.
  static const linkLost = 'linkLost';

  /// Aplikacja zamknięta w trakcie sesji.
  static const appClosed = 'appClosed';
}

/// Co stało się z kawałkiem pisania. W bazie jako [name].
enum TypingStatus {
  /// Wpisane do pola.
  typed,

  /// Ujście nie wpisało całości: pole zniknęło, ekran się zablokował albo
  /// przyszedł Stop. Część mogła się wpisać.
  notTyped,

  /// U odbiorcy wisiała karta z pytaniem, więc nic się nie wpisało.
  paused,

  /// Odbiorca odmówił paczki, bo zgody już nie było.
  refused,

  /// Nadawca nie dostał odpowiedzi: nie wiadomo, czy dotarło.
  unconfirmed,

  /// Zostało w kolejce nadawcy, gdy sesja się skończyła. Nie wyszło.
  unsent;

  static TypingStatus parse(String name) => TypingStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => TypingStatus.notTyped);
}

/// Jedna operacja w historii pisania: tekst, tekst ukryty (sama liczba
/// znaków), kasowanie przed albo za kursorem, Enter.
class TypingOp {
  final RemoteInputOpKind kind;

  /// Tekst dla jawnego wpisania, pusty dla reszty.
  final String text;

  /// Dla `bs` i `del` liczba punktów kodowych, dla ukrytego wpisania
  /// liczba znaków, zero dla reszty.
  final int count;

  /// Wpisanie bez tekstu: pole hasła albo pole nieznanego rodzaju.
  final bool hidden;

  const TypingOp._(this.kind,
      {this.text = '', this.count = 0, this.hidden = false});

  const TypingOp.insert(String text)
      : this._(RemoteInputOpKind.insert, text: text);
  const TypingOp.hidden(int chars)
      : this._(RemoteInputOpKind.insert, count: chars, hidden: true);
  const TypingOp.backspace(int count)
      : this._(RemoteInputOpKind.backspace, count: count);
  const TypingOp.delete(int count)
      : this._(RemoteInputOpKind.delete, count: count);
  const TypingOp.action() : this._(RemoteInputOpKind.action);

  /// Ile znaków wpisuje ta operacja.
  int get chars => kind != RemoteInputOpKind.insert
      ? 0
      : (hidden ? count : text.runes.length);

  Map<String, Object?> toJson() => switch (kind) {
        RemoteInputOpKind.insert =>
          hidden ? {'t': 'insert', 'hidden': count} : {'t': 'insert', 's': text},
        RemoteInputOpKind.backspace => {'t': 'bs', 'n': count},
        RemoteInputOpKind.delete => {'t': 'del', 'n': count},
        _ => {'t': kind.wire},
      };

  /// Wyrozumiale: wiersz mógł zapisać starszy Chatt. Nieznane znaczy `null`.
  static TypingOp? fromJson(Object? json) {
    if (json is! Map) return null;
    final n = json['n'];
    switch (RemoteInputOpKind.fromWire(json['t'])) {
      case RemoteInputOpKind.insert:
        final ukryte = json['hidden'];
        if (ukryte is int) return TypingOp.hidden(ukryte);
        final s = json['s'];
        return s is String ? TypingOp.insert(s) : null;
      case RemoteInputOpKind.backspace:
        return n is int ? TypingOp.backspace(n) : null;
      case RemoteInputOpKind.delete:
        return n is int ? TypingOp.delete(n) : null;
      case RemoteInputOpKind.action:
        return const TypingOp.action();
      default:
        return null;
    }
  }

  static String encode(Iterable<TypingOp> ops) =>
      jsonEncode([for (final op in ops) op.toJson()]);

  static List<TypingOp> decode(String json) {
    try {
      final lista = jsonDecode(json);
      if (lista is! List) return const [];
      return [
        for (final element in lista) ?fromJson(element),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Operacje protokołu w historii. [hide] zamienia tekst na liczbę znaków.
  /// Ping i stop nic nie wpisują, więc odpadają.
  static List<TypingOp> fromRemote(Iterable<RemoteInputOp> ops,
      {required bool hide}) {
    final wynik = <TypingOp>[];
    for (final op in ops) {
      final TypingOp? nowa = switch (op.kind) {
        RemoteInputOpKind.insert => hide
            ? TypingOp.hidden(op.text.runes.length)
            : TypingOp.insert(op.text),
        RemoteInputOpKind.backspace => TypingOp.backspace(op.count),
        RemoteInputOpKind.delete => TypingOp.delete(op.count),
        RemoteInputOpKind.action => const TypingOp.action(),
        _ => null,
      };
      if (nowa != null) appendTypingOp(wynik, nowa);
    }
    return wynik;
  }

  @override
  bool operator ==(Object other) =>
      other is TypingOp &&
      other.kind == kind &&
      other.text == text &&
      other.count == count &&
      other.hidden == hidden;

  @override
  int get hashCode => Object.hash(kind, text, count, hidden);

  /// Bez tekstu, jak `RemoteInputOp.toString`.
  @override
  String toString() => switch (kind) {
        RemoteInputOpKind.insert =>
          hidden ? 'hidden($count)' : 'insert(${text.length})',
        RemoteInputOpKind.backspace => 'bs($count)',
        RemoteInputOpKind.delete => 'del($count)',
        _ => kind.wire,
      };
}

/// Dokleja [op] do [ops], sklejając z ostatnią operację tego samego rodzaju:
/// tekst z tekstem, ukryte z ukrytym, kasowanie z kasowaniem.
void appendTypingOp(List<TypingOp> ops, TypingOp op) {
  final ostatnia = ops.isEmpty ? null : ops.last;
  if (ostatnia != null &&
      ostatnia.kind == op.kind &&
      ostatnia.hidden == op.hidden &&
      op.kind != RemoteInputOpKind.action) {
    ops[ops.length - 1] = switch (op.kind) {
      RemoteInputOpKind.insert => op.hidden
          ? TypingOp.hidden(ostatnia.count + op.count)
          : TypingOp.insert(ostatnia.text + op.text),
      RemoteInputOpKind.backspace =>
        TypingOp.backspace(ostatnia.count + op.count),
      _ => TypingOp.delete(ostatnia.count + op.count),
    };
    return;
  }
  ops.add(op);
}

/// Czy tekst z paczki ma być ukryty. Rodzaj pola znamy dopiero po wpisaniu
/// (cel przychodzi z odpowiedzią ujścia), więc liczy się i cel sprzed
/// paczki, i ten po niej: pierwsza paczka w świeżo kliknięte pole hasła
/// też zostaje ukryta. Pole nieznanego rodzaju (`none`) traktujemy jak
/// hasło, tak jak ekran pisania zasłania jego echo.
bool hideTyping(RemoteInputTarget before, RemoteInputTarget after) =>
    before.field != RemoteInputField.text ||
    after.field != RemoteInputField.text;

/// Tekst odtworzony z operacji, na ile się da: wpisanie dokleja, `bs`
/// zabiera znaki z końca, Enter to nowa linia, ukryte wpisanie to [hiddenChar]
/// tyle razy, ile było znaków. `del` kasuje za kursorem odbiorcy, którego
/// położenia nie znamy, więc nie zmienia tekstu. Pole mogło mieć treść
/// sprzed sesji, a kursor mógł się przesunąć: to przybliżenie, a dokładny
/// zapis to same operacje.
String reconstructTyping(Iterable<TypingOp> ops, {String hiddenChar = '•'}) {
  final znaki = <int>[];
  for (final op in ops) {
    switch (op.kind) {
      case RemoteInputOpKind.insert:
        if (op.hidden) {
          if (op.count > 0 && hiddenChar.isNotEmpty) {
            znaki.addAll(List.filled(op.count, hiddenChar.runes.first));
          }
        } else {
          znaki.addAll(op.text.runes);
        }
      case RemoteInputOpKind.backspace:
        final ile = op.count < znaki.length ? op.count : znaki.length;
        znaki.removeRange(znaki.length - ile, znaki.length);
      case RemoteInputOpKind.action:
        znaki.add(0x0A);
      default:
        break;
    }
  }
  return String.fromCharCodes(znaki);
}

/// Operacje jednym napisem do eksportu tekstowego, bez zależności od języka
/// aplikacji: tekst dosłownie, klawisze w nawiasach kwadratowych.
String describeTypingOps(Iterable<TypingOp> ops) {
  final opis = StringBuffer();
  for (final op in ops) {
    switch (op.kind) {
      case RemoteInputOpKind.insert:
        opis.write(op.hidden ? '[hidden: ${op.count} chars]' : op.text);
      case RemoteInputOpKind.backspace:
        opis.write(op.count == 1 ? '[Backspace]' : '[Backspace x${op.count}]');
      case RemoteInputOpKind.delete:
        opis.write(op.count == 1 ? '[Delete]' : '[Delete x${op.count}]');
      case RemoteInputOpKind.action:
        opis.write('[Enter]');
      default:
        break;
    }
  }
  return opis.toString();
}

/// Uchwyt sesji w historii pisania, trzymany przez stronę, która ją
/// prowadzi. `null` z [TypingJournal.begin] znaczy, że historia jest
/// wyłączona: wszystkie wywołania z takim uchwytem nic nie robią.
class TypingSessionLog {
  final MessageDirection direction;
  final String inputId;
  final String peerGuid;
  final String peerName;
  final DateTime startedAt;

  /// Pokolenie historii z chwili [TypingJournal.begin] (patrz
  /// [TypingJournal.detachAll]).
  final int _epoch;

  /// Numer wiersza w bazie, gdy już jest. `null` po nieudanym zapisie
  /// i po wyczyszczeniu historii przed zapisem.
  late final Future<int?> _row;
  _OpenEntry? _entry;
  Timer? _idle;
  bool _ended = false;

  TypingSessionLog._(this.direction, this.inputId, this.peerGuid,
      this.peerName, this.startedAt, this._epoch);

  bool get ended => _ended;
}

/// Kawałek pisania zbierany w pamięci, zanim trafi do bazy.
class _OpenEntry {
  final DateTime at;
  final String app;
  final String appLabel;
  final RemoteInputField field;
  final TypingStatus status;
  final bool hidden;
  final List<TypingOp> ops = [];

  _OpenEntry(this.at, this.app, this.appLabel, this.field, this.status,
      this.hidden);

  bool sameAs(String app, String appLabel, RemoteInputField field,
          TypingStatus status, bool hidden) =>
      this.app == app &&
      this.appLabel == appLabel &&
      this.field == field &&
      this.status == status &&
      this.hidden == hidden;

  int get chars => ops.fold(0, (suma, op) => suma + op.chars);

  TypingEntriesCompanion toCompanion(int sessionId) =>
      TypingEntriesCompanion.insert(
        sessionId: sessionId,
        at: at,
        app: Value(app),
        appLabel: Value(appLabel),
        field: field.name,
        status: status.name,
        ops: TypingOp.encode(ops),
        chars: Value(chars),
        masked: Value(hidden),
      );
}

/// Zapis historii pisania. Wszystkie wywołania są natychmiastowe: zapis do
/// bazy idzie w tle, po kolei, więc ścieżka paczki nie czeka na dysk.
///
/// Kolejne paczki do tego samego pola, z tym samym skutkiem, sklejają się
/// w jeden kawałek, który trafia do bazy po [flushDelay] ciszy, przy
/// zmianie pola albo skutku, na końcu sesji i z pierwszą paczką po
/// [maxEntryAge] od początku kawałka (ciągłe pisanie bez przerwy). Zamknięcie
/// aplikacji nie daje pewnego sygnału (Android potrafi zabić proces), więc
/// dłużej w pamięci nic nie czeka.
class TypingJournal {
  TypingJournal(
    this._db, {
    required this._enabled,
    bool Function()? recording,
    this.flushDelay = const Duration(seconds: 1),
    this.maxEntryAge = const Duration(seconds: 5),
    DateTime Function()? clock,
    this._onError,
  })  : _recording = recording ?? _enabled,
        _now = clock ?? DateTime.now;

  final ChattDb _db;
  final bool Function() _enabled;

  /// Czy sesja już otwarta zapisuje dalsze kawałki. Domyślnie to samo co
  /// [enabled]; serwis podaje tu sam przełącznik historii, żeby paczka
  /// wpisywana w chwili wyłączenia dodatku jeszcze trafiła do sesji, którą
  /// wyłączenie zaraz zamknie.
  final bool Function() _recording;
  final DateTime Function() _now;
  final void Function(Object error, StackTrace stack)? _onError;
  final Duration flushDelay;

  /// Najdłużej tyle kawałek zbiera paczki, zanim pójdzie do bazy przy
  /// następnej z nich.
  final Duration maxEntryAge;

  final Set<TypingSessionLog> _open = {};
  Future<void> _writes = Future.value();
  bool _closed = false;

  /// Pokolenie historii: rośnie przy każdym [detachAll]. Zapis sesji ze
  /// starszego pokolenia, który jeszcze czekał w kolejce, przepada: po
  /// wyczyszczeniu historii jej wiersza już nie ma, a wiersz założony po
  /// czyszczeniu wskrzesiłby skasowaną sesję.
  int _epoch = 0;

  /// Czy historia teraz zapisuje (dodatek i przełącznik włączone).
  bool get enabled => !_closed && _enabled();

  /// Zaczyna sesję w historii. [result] mówi, jak skończyła się prośba
  /// (patrz [TypingResult]); prośba bez sesji idzie przez [refused].
  /// `null`, gdy historia jest wyłączona.
  TypingSessionLog? begin({
    required MessageDirection direction,
    required String inputId,
    required String peerGuid,
    required String peerName,
    required String result,
  }) {
    if (!enabled) return null;
    final teraz = _now();
    final sesja = TypingSessionLog._(
        direction, inputId, peerGuid, peerName, teraz, _epoch);
    sesja._row = _enqueue<int?>(() async {
      if (sesja._epoch != _epoch) return null;
      return _db.insertTypingSession(
        TypingSessionsCompanion.insert(
          inputId: inputId,
          direction: direction,
          peerGuid: peerGuid,
          peerName: peerName,
          startedAt: teraz,
          result: result,
          endedAt: TypingResult.started(result)
              ? const Value.absent()
              : Value(teraz),
        ),
      );
    });
    if (TypingResult.started(result)) {
      _open.add(sesja);
    } else {
      sesja._ended = true;
    }
    return sesja;
  }

  /// Prośba, z której nie wyszła sesja (odmowa, cisza na karcie, zajęte):
  /// wiersz od razu zakończony.
  void refused({
    required MessageDirection direction,
    required String inputId,
    required String peerGuid,
    required String peerName,
    required String result,
  }) {
    assert(!TypingResult.started(result));
    begin(
      direction: direction,
      inputId: inputId,
      peerGuid: peerGuid,
      peerName: peerName,
      result: result,
    );
  }

  /// Zapisuje operacje z paczki. [before] to cel znany przed paczką,
  /// [after] cel z odpowiedzi na nią; z obu wynika ukrycie tekstu (patrz
  /// [hideTyping]). Operacje, które niczego nie wpisują, odpadają.
  void record(
    TypingSessionLog? sesja,
    Iterable<RemoteInputOp> ops, {
    required TypingStatus status,
    required RemoteInputTarget before,
    required RemoteInputTarget after,
  }) {
    if (sesja == null || sesja._ended || _closed || !_recording()) return;
    final ukryj = hideTyping(before, after);
    final nowe = TypingOp.fromRemote(ops, hide: ukryj);
    if (nowe.isEmpty) return;
    final cel = (after.app.isNotEmpty || after.appLabel.isNotEmpty)
        ? after
        : before;
    final pole = !ukryj
        ? RemoteInputField.text
        : (after.field != RemoteInputField.text ? after.field : before.field);
    final otwarty = sesja._entry;
    if (otwarty == null ||
        !otwarty.sameAs(cel.app, cel.appLabel, pole, status, ukryj) ||
        _now().difference(otwarty.at) >= maxEntryAge) {
      _flushEntry(sesja);
      sesja._entry =
          _OpenEntry(_now(), cel.app, cel.appLabel, pole, status, ukryj);
    }
    for (final op in nowe) {
      appendTypingOp(sesja._entry!.ops, op);
    }
    sesja._idle?.cancel();
    // Zegar ciszy też w strefie głównej, jak kolejka zapisów.
    sesja._idle =
        Zone.root.createTimer(flushDelay, () => _flushEntry(sesja));
  }

  /// Kończy sesję z powodem z [TypingEnd]. Drugie wywołanie nic nie robi.
  void end(TypingSessionLog? sesja, String reason) {
    if (sesja == null || sesja._ended) return;
    sesja._ended = true;
    _flushEntry(sesja);
    _open.remove(sesja);
    final teraz = _now();
    unawaited(_enqueue(() async {
      final id = await sesja._row;
      if (id == null || sesja._epoch != _epoch) return;
      await _db.endTypingSession(id, teraz, reason);
    }));
  }

  void _flushEntry(TypingSessionLog sesja) {
    sesja._idle?.cancel();
    sesja._idle = null;
    final kawalek = sesja._entry;
    sesja._entry = null;
    if (kawalek == null || kawalek.ops.isEmpty) return;
    unawaited(_enqueue(() async {
      final id = await sesja._row;
      if (id == null || sesja._epoch != _epoch) return;
      await _db.insertTypingEntries([kawalek.toCompanion(id)]);
    }));
  }

  /// Dokłada krok do kolejki zapisów. Kolejka żyje w strefie głównej:
  /// wywołanie potrafi przyjść ze strefy, której nikt dalej nie obsłuży
  /// (stuknięcie w Stop w teście widżetu idzie w fałszywym czasie), a zapis
  /// raz wpuszczony do kolejki ma dojść do bazy sam, w prawdziwym czasie.
  Future<T?> _enqueue<T>(Future<T> Function() krok) => Zone.root.run(() {
        final wynik = _writes.then((_) => krok()).then<T?>(
          (wartosc) => wartosc,
          onError: (Object blad, StackTrace slad) {
            _onError?.call(blad, slad);
            return null;
          },
        );
        _writes = wynik.then((_) {});
        return wynik;
      });

  /// Zapisuje wszystko, co czeka w pamięci, i czeka na koniec zapisu.
  Future<void> flush() async {
    for (final sesja in _open.toList()) {
      _flushEntry(sesja);
    }
    await _writes;
  }

  /// Odcina trwające sesje od bazy: po wyczyszczeniu historii ich wierszy
  /// już nie ma, więc dalsze pisanie w nich nie zostawia śladu. Zapisy
  /// wcześniejszych sesji, które jeszcze czekają w kolejce, też przepadają.
  void detachAll() {
    _epoch++;
    for (final sesja in _open) {
      sesja._idle?.cancel();
      sesja._entry = null;
      sesja._ended = true;
    }
    _open.clear();
  }

  /// Przestaje przyjmować nowe sesje i kawałki, kończy trwające sesje
  /// powodem [TypingEnd.appClosed] i czeka, aż wszystko trafi do bazy.
  /// Zakończenia sesji ([end]) przechodzą jeszcze przed zamknięciem.
  Future<void> close() async {
    _closed = true;
    // Sesji otwartej w chwili zamknięcia nikt już nie zakończy: w historii
    // wisiałaby jako trwająca także po następnym starcie.
    for (final sesja in _open.toList()) {
      end(sesja, TypingEnd.appClosed);
    }
    await flush();
  }
}
