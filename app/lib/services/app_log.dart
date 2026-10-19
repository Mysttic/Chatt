import 'dart:async';
import 'dart:io' show FileSystemException;
import 'dart:ui' show PlatformDispatcher;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart'
    show FlutterError, FlutterErrorDetails, debugPrint;

import '../data/db.dart';

// Dziennik aplikacji do diagnostyki (issue #50). Leży w zaszyfrowanej
// bazie, obok historii rozmów, i wychodzi z urządzenia tylko eksportem.
//
// Czego tu nie ma i być nie może: treści wiadomości, tekstu z klawiatury,
// kodów parowania, kluczy (tożsamości, sesji, plików, bazy) i tokenów zgód.
// Nazwy urządzeń, adresy i rozmiary plików są, bo bez nich dziennik nie
// powie, z kim i którędy coś się nie udało.

/// Jak długo trzymamy wpisy dziennika.
const Duration appLogRetention = Duration(days: 30);

/// Ile wpisów najwyżej trzymamy, niezależnie od wieku.
const int appLogMaxEntries = 20000;

/// Okno zwijania powtórek: ten sam wpis (poziom, obszar, treść) powtórzony
/// w tym czasie jest tylko liczony.
const Duration appLogFloodWindow = Duration(seconds: 10);

/// Obszary dziennika. Napisy, bo trafiają do eksportu.
abstract final class LogArea {
  static const app = 'app';
  static const net = 'net';
  static const pair = 'pair';
  static const file = 'file';
  static const history = 'history';
  static const bt = 'bt';
  static const keyboard = 'keyboard';
  static const update = 'update';
  static const error = 'error';
}

/// Dziennik aplikacji jednej instancji [AppServices]. Testy stawiają po kilka
/// instancji w jednym procesie, więc dziennik nie jest globalny.
///
/// Wpisy zbierają się w pamięci i trafiają do bazy paczką po [flushDelay]:
/// zamknięcie aplikacji nie daje żadnego sygnału, więc dłużej nic nie czeka.
///
/// Zalew tych samych wpisów (pętla odpytywania, która co pół sekundy trafia
/// w ten sam błąd) zwija się: pierwszy wpis idzie do bazy od razu, kolejne
/// identyczne w ciągu [floodWindow] są tylko liczone, a po zamknięciu okna
/// (albo przy [flush] i [close]) trafia jeden wpis z dopiskiem
/// „(repeated N times)”.
class AppLog {
  AppLog(
    this._db, {
    this.flushDelay = const Duration(seconds: 1),
    this.floodWindow = appLogFloodWindow,
    this.retention = appLogRetention,
    this.maxEntries = appLogMaxEntries,
    this.echo = false,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final ChattDb _db;
  final DateTime Function() _now;
  final Duration flushDelay;

  /// Domyślne okno zwijania powtórek (patrz [add]).
  final Duration floodWindow;

  /// Wiek i liczba wpisów, ponad które [trim] przycina dziennik.
  final Duration retention;
  final int maxEntries;

  /// Czy każdy zapisany wpis idzie też na konsolę przez `debugPrint`. Włącza
  /// to wyłącznie wejście aplikacji w buildzie debug; testy i narzędzia
  /// zostają ciche.
  final bool echo;

  /// Najwyżej tyle otwartych okien powtórek naraz. Zalew jednego błędu
  /// mieści się w jednym oknie; limit chroni pamięć przed tysiącem różnych
  /// wpisów w ciągu kilku sekund.
  static const int _maxWindows = 256;

  final List<AppLogEntriesCompanion> _pending = [];
  final Map<String, _Okno> _okna = {};
  Timer? _timer;
  Timer? _floodTimer;
  DateTime? _floodDue;
  Future<void> _writes = Future.value();
  bool _closed = false;

  /// Czy dziennik przestał przyjmować wpisy (po [close]).
  bool get isClosed => _closed;

  void info(String area, String message) =>
      add(LogLevel.info, area, message);

  void warning(String area, String message,
          {Object? error, StackTrace? stack}) =>
      add(LogLevel.warning, area, message,
          details: describeError(error, stack));

  void error(String area, String message, {Object? error, StackTrace? stack}) =>
      add(LogLevel.error, area, message, details: describeError(error, stack));

  /// Dopisuje wpis. Nic nie czeka i nic nie rzuca.
  ///
  /// Ten sam (poziom, obszar, treść) w ciągu [collapseWithin] od pierwszego
  /// zapisanego wystąpienia jest tylko liczony; bez [collapseWithin] okno ma
  /// długość [floodWindow]. Szczegóły nie wchodzą do porównania: liczy się
  /// to, co się stało, a ślad stosu zostaje przy pierwszym wpisie.
  void add(
    LogLevel level,
    String area,
    String message, {
    String? details,
    Duration? collapseWithin,
  }) {
    if (_closed) return;
    try {
      final teraz = _now();
      _zamknijMinione(teraz);
      final klucz = '${level.index}|$area|$message';
      final okno = _okna[klucz];
      if (okno != null) {
        okno.count++;
        _planujZamkniecie(okno.end);
        return;
      }
      if (_okna.length >= _maxWindows) _zamknijNajstarsze(teraz);
      _okna[klucz] = _Okno(
          level, area, message, teraz, collapseWithin ?? floodWindow);
      _zapisz(level, area, message, details, teraz);
    } catch (_) {
      // Dziennik nie ma prawa wywrócić tego, co go woła.
    }
  }

  /// Zapisuje to, co czeka, razem z licznikami otwartych okien powtórek,
  /// i czeka na koniec zapisu.
  ///
  /// Okna zostają otwarte z wyzerowanym licznikiem: zapis (eksport, ekran
  /// dziennika) ma pokazać to, co się nazbierało, a zalew, który trwa dalej,
  /// ma dalej być zwijany. Zamyka je dopiero ich czas albo [close].
  Future<void> flush() {
    try {
      final teraz = _now();
      for (final okno in _okna.values) {
        _wypiszPowtorki(okno, teraz);
        okno.count = 0;
      }
      if (_closed) _okna.clear();
      _floodTimer?.cancel();
      _floodTimer = null;
      _floodDue = null;
    } catch (_) {
      // Zegar albo zapis w pamięci nie ma tu czym się wywrócić, ale gdyby,
      // to zapis paczki niżej i tak ma się odbyć.
    }
    return _zapiszPaczke();
  }

  /// Usuwa wpisy starsze niż [retention] i ponad [maxEntries] najnowszych.
  Future<int> trim() async {
    if (_closed) return 0;
    try {
      return await _db.trimLog(
        olderThan: _now().subtract(retention),
        keepAtMost: maxEntries,
      );
    } catch (_) {
      return 0;
    }
  }

  /// Zapisuje resztę (także liczniki powtórek) i przestaje przyjmować wpisy.
  Future<void> close() {
    _closed = true;
    return flush();
  }

  // --- Środek ---------------------------------------------------------------

  void _zapisz(LogLevel level, String area, String message, String? details,
      DateTime at) {
    _pending.add(AppLogEntriesCompanion.insert(
      atMs: at.millisecondsSinceEpoch,
      level: level,
      area: area,
      message: message,
      details: Value(details),
    ));
    if (echo) _naKonsole(level, area, message, details);
    _timer ??= Timer(flushDelay, () => unawaited(_zapiszPaczke()));
  }

  Future<void> _zapiszPaczke() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isNotEmpty) {
      final paczka = List.of(_pending);
      _pending.clear();
      _writes = _writes
          .then((_) => _db.insertLogEntries(paczka))
          .catchError((Object _) {
        // Baza zamknięta albo pełny dysk: dziennik nie ma gdzie zapisać
        // własnej porażki, a aplikacja ma działać dalej.
      });
    }
    return _writes;
  }

  static void _naKonsole(
      LogLevel level, String area, String message, String? details) {
    try {
      debugPrint('[chatt ${level.name}] $area: $message');
      if (details != null) debugPrint(details);
    } catch (_) {
      // Konsola jest dodatkiem: wpis i tak leży w bazie.
    }
  }

  /// Wpis z licznikiem powtórek, jeśli okno coś zliczyło. Chwila wpisu to
  /// koniec okna, a przy wcześniejszym zamknięciu (zapis, zamknięcie
  /// dziennika) chwila zamknięcia: kolejność wpisów zgadza się wtedy z ich
  /// czasem.
  void _wypiszPowtorki(_Okno okno, DateTime teraz) {
    if (okno.count == 0) return;
    final koniec = okno.end;
    _zapisz(
      okno.level,
      okno.area,
      '${okno.message} (repeated ${okno.count} times)',
      null,
      teraz.isBefore(koniec) ? teraz : koniec,
    );
  }

  void _zamknijMinione(DateTime teraz) {
    if (_okna.isEmpty) return;
    final minione = [
      for (final wpis in _okna.entries)
        if (!wpis.value.end.isAfter(teraz)) wpis.key,
    ];
    for (final klucz in minione) {
      _wypiszPowtorki(_okna.remove(klucz)!, teraz);
    }
  }

  void _zamknijNajstarsze(DateTime teraz) {
    final kolejnosc = _okna.entries.toList()
      ..sort((a, b) => a.value.start.compareTo(b.value.start));
    for (final wpis in kolejnosc.take(_okna.length - _maxWindows + 1)) {
      _wypiszPowtorki(_okna.remove(wpis.key)!, teraz);
    }
  }

  /// Budzik na koniec najbliższego okna, które coś zliczyło. Bez niego
  /// licznik czekałby na następny wpis, a ten może nie przyjść nigdy.
  void _planujZamkniecie(DateTime koniec) {
    final termin = _floodDue;
    if (termin != null && !koniec.isBefore(termin)) return;
    _floodTimer?.cancel();
    _floodDue = koniec;
    final za = koniec.difference(_now());
    _floodTimer = Timer(za.isNegative ? Duration.zero : za, _poTerminie);
  }

  void _poTerminie() {
    _floodTimer = null;
    _floodDue = null;
    if (_closed) return;
    try {
      _zamknijMinione(_now());
      DateTime? najblizszy;
      for (final okno in _okna.values) {
        if (okno.count == 0) continue;
        if (najblizszy == null || okno.end.isBefore(najblizszy)) {
          najblizszy = okno.end;
        }
      }
      if (najblizszy != null) _planujZamkniecie(najblizszy);
    } catch (_) {
      // Następny wpis albo zapis i tak zamknie to, co zostało.
    }
  }
}

/// Okno powtórek jednego wpisu.
class _Okno {
  final LogLevel level;
  final String area;
  final String message;
  final DateTime start;
  final Duration length;

  /// Ile razy wpis powtórzył się po pierwszym zapisanym wystąpieniu.
  int count = 0;

  _Okno(this.level, this.area, this.message, this.start, this.length);

  DateTime get end => start.add(length);
}

/// Podpina dziennik pod błędy, których nikt nie złapał: błędy ramówki
/// (budowanie, układ, rysowanie, gesty) i błędy asynchroniczne ze strefy
/// głównej. Woła to `main.dart` zaraz po starcie [AppServices]; błąd sprzed
/// tej chwili ląduje w `chatt-startup-error.txt`.
///
/// Obie obsługi dopisują wpis na poziomie [LogLevel.error] w obszarze
/// [LogArea.error] (typ wyjątku w treści, opis i ślad stosu w szczegółach)
/// i oddają błąd dalej temu, kto obsługiwał go wcześniej: w buildzie debug
/// czerwony ekran i wydruk na konsoli zostają, jakie były.
///
/// `PlatformDispatcher.onError` zwraca `true`, gdy wcześniej nikt go nie
/// obsługiwał: błąd jest wtedy obsłużony, bo leży w dzienniku (a w buildzie
/// debug także na konsoli, przez echo dziennika), więc silnik nie powtarza
/// go na stderr. Działanie aplikacji to nie zmienia: nieobsłużony błąd
/// asynchroniczny nie zamyka procesu i z tą obsługą też go nie zamyka.
/// Wcześniejsza obsługa, jeśli była, decyduje sama.
void logUncaughtErrors(AppLog log) {
  final poprzedniFluttera = FlutterError.onError;
  FlutterError.onError = (details) {
    try {
      final biblioteka = details.library;
      log.add(
        LogLevel.error,
        LogArea.error,
        'Uncaught Flutter error: ${details.exception.runtimeType}'
        '${biblioteka == null ? '' : ' (${logText(biblioteka)})'}',
        details: _szczegolyFluttera(details),
      );
    } catch (_) {
      // Dziennik nie ma prawa zasłonić błędu, który właśnie opisuje.
    }
    poprzedniFluttera?.call(details);
  };

  final poprzedniPlatformy = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (blad, slad) {
    try {
      log.add(
        LogLevel.error,
        LogArea.error,
        'Uncaught error: ${blad.runtimeType}',
        details: describeError(blad, slad),
      );
    } catch (_) {
      // Jak wyżej: wpis jest dodatkiem do obsługi błędu.
    }
    return poprzedniPlatformy?.call(blad, slad) ?? true;
  };
}

/// Szczegóły błędu ramówki: w czym się zdarzył („while building …") oraz
/// opis wyjątku ze śladem stosu, przez to samo sito co [describeError].
/// Reszty raportu (drzewa widżetów) nie bierzemy: widżet tekstu wypisuje
/// w nim swoją treść, a to bywa treść wiadomości.
String? _szczegolyFluttera(FlutterErrorDetails details) {
  String? kontekst;
  try {
    kontekst = details.context?.toDescription();
  } catch (_) {
    kontekst = null;
  }
  final opis = describeError(details.exception, details.stack);
  final czesci = [
    if (kontekst != null && kontekst.trim().isNotEmpty)
      'context: ${logText(kontekst, maxLength: 200)}',
    ?opis,
  ];
  return czesci.isEmpty ? null : czesci.join('\n');
}

/// Wyjątek i ślad stosu jako tekst do pola szczegółów. `null`, gdy nie ma
/// ani jednego, ani drugiego.
///
/// Opis wyjątku przechodzi przez sito: błąd pliku traci ścieżkę (w niej
/// siedzi nazwa użytkownika i nazwa pliku), błąd formatu traci cytat
/// z wejścia (to mogła być treść wiadomości), a błąd SQLite traci wartości
/// parametrów zapytania (tam bywa treść wiadomości).
String? describeError(Object? error, StackTrace? stack) {
  if (error == null && stack == null) return null;
  return [
    if (error != null) _opisBledu(error),
    if (stack != null) '$stack',
  ].join('\n');
}

String _opisBledu(Object error) {
  try {
    if (error is FileSystemException) {
      final os = error.osError;
      return '${error.runtimeType}: ${error.message}'
          '${os == null ? '' : ' ($os)'}';
    }
    if (error is FormatException) return 'FormatException: ${error.message}';
    return '$error'.replaceAll(_parametrySql, '');
  } catch (_) {
    return '${error.runtimeType}';
  }
}

/// Dopisek `SqliteException.toString()` z wartościami parametrów zapytania.
final RegExp _parametrySql = RegExp(r', parameters: .*$', multiLine: true);

/// Rozmówca w dzienniku: nazwa i początek guid-a. Nazwa przychodzi z sieci,
/// więc traci znaki sterujące (nowa linia udawałaby osobny wpis) i nadmiar
/// długości.
String peerLabel(String name, String guid) {
  final krotki = guid.length > 8 ? guid.substring(0, 8) : guid;
  final czysta = logText(name);
  return czysta.isEmpty ? '($krotki)' : '$czysta ($krotki)';
}

/// Napis z zewnątrz (nazwa urządzenia, powód z odpowiedzi drugiej strony)
/// w postaci bezpiecznej dla dziennika: bez znaków sterujących i najwyżej
/// [maxLength] znaków.
String logText(String text, {int maxLength = 64}) {
  final czysty = text.replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ').trim();
  return czysty.length > maxLength
      ? '${czysty.substring(0, maxLength)}…'
      : czysty;
}

/// Zasłania adresy sprzętowe (Bluetooth, MAC). Komunikaty strony natywnej
/// potrafią nieść adres urządzenia, z którym właśnie próbowało się radio,
/// a przy szukaniu to bywa cudzy sprzęt z sąsiedztwa.
String maskHardwareAddresses(String text) =>
    text.replaceAll(_adresSprzetowy, '<address>');

final RegExp _adresSprzetowy =
    RegExp(r'\b[0-9A-Fa-f]{2}(?:[:-][0-9A-Fa-f]{2}){5}\b');
