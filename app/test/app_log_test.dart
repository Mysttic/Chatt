import 'dart:io';
import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/services/app_log.dart';

/// Zegar, który stoi, dopóki test go nie przesunie.
class _Zegar {
  DateTime teraz = DateTime(2026, 10, 18, 15, 30, 12, 345);

  DateTime call() => teraz;

  void przesun(Duration o) => teraz = teraz.add(o);
}

/// Wyjątek, który opisuje się jak `SqliteException` z wartościami
/// parametrów zapytania (tam bywa treść wiadomości).
class _BladSql implements Exception {
  @override
  String toString() =>
      'SqliteException(2067): while executing, UNIQUE constraint failed\n'
      '  Causing statement: INSERT INTO messages (body) VALUES (?), '
      'parameters: Tajna treść wiadomości';
}

/// Jak [_BladSql], z parametrem na kilka linii: treść wiadomości niesie
/// własne nowe linie, a po niej idą kolejne parametry.
class _BladSqlWielolinijkowy implements Exception {
  @override
  String toString() =>
      'SqliteException(13): while executing, database or disk is full\n'
      '  Causing statement: INSERT INTO messages (guid, body, n) '
      'VALUES (?, ?, ?), parameters: abc, pierwsza linia\n'
      'Tajna druga linia\r\ntrzecia, 42';
}

/// Wyjątek, którego opis sam się wywraca.
class _ZlyOpis implements Exception {
  @override
  String toString() => throw StateError('opis');
}

/// Dziennik aplikacji (issue #50): paczki zapisu, przycinanie, zwijanie
/// powtórek, zamykanie, opis błędów i ciche echo.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late ChattDb db;
  late _Zegar zegar;
  final otwarte = <AppLog>[];

  setUp(() {
    db = ChattDb(NativeDatabase.memory());
    zegar = _Zegar();
    otwarte.clear();
  });

  tearDown(() async {
    for (final log in otwarte) {
      await log.close();
    }
    await db.close();
  });

  AppLog dziennik({
    Duration flushDelay = const Duration(milliseconds: 20),
    Duration floodWindow = appLogFloodWindow,
    Duration retention = appLogRetention,
    int maxEntries = appLogMaxEntries,
    bool echo = false,
    bool prawdziwyZegar = false,
  }) {
    final log = AppLog(
      db,
      flushDelay: flushDelay,
      floodWindow: floodWindow,
      retention: retention,
      maxEntries: maxEntries,
      echo: echo,
      clock: prawdziwyZegar ? null : zegar.call,
    );
    otwarte.add(log);
    return log;
  }

  Future<List<String>> tresci() async =>
      [for (final w in await db.allLogEntries()) w.message];

  group('zapis paczkami', () {
    test('wpisy czekają w pamięci i trafiają do bazy po flushDelay', () async {
      final log = dziennik(flushDelay: const Duration(milliseconds: 300));
      log.info(LogArea.app, 'pierwszy');
      zegar.przesun(const Duration(milliseconds: 5));
      log.warning(LogArea.net, 'drugi', error: StateError('zła sieć'));

      expect(await db.allLogEntries(), isEmpty,
          reason: 'add nie czeka na bazę, zapis idzie paczką później');

      await Future<void>.delayed(const Duration(milliseconds: 600));
      final wpisy = await db.allLogEntries();
      expect(wpisy.map((w) => w.message), ['pierwszy', 'drugi']);
      expect(wpisy[0].level, LogLevel.info);
      expect(wpisy[0].area, LogArea.app);
      expect(wpisy[0].details, isNull);
      expect(wpisy[0].atMs,
          DateTime(2026, 10, 18, 15, 30, 12, 345).millisecondsSinceEpoch,
          reason: 'chwila wpisu z zegara dziennika, z milisekundami');
      expect(wpisy[1].level, LogLevel.warning);
      expect(wpisy[1].atMs - wpisy[0].atMs, 5);
      expect(wpisy[1].details, contains('zła sieć'));
    });

    test('flush zapisuje od razu i czeka na koniec zapisu', () async {
      final log = dziennik(flushDelay: const Duration(hours: 1));
      log.error(LogArea.file, 'zapis', error: StateError('x'));
      await log.flush();
      expect(await tresci(), ['zapis']);
    });

    test('add po zamknięciu bazy nie rzuca', () async {
      final log = dziennik();
      await db.close();
      log.info(LogArea.app, 'po zamknięciu bazy');
      await log.flush();
      db = ChattDb(NativeDatabase.memory());
    });
  });

  group('przycinanie', () {
    test('domyślnie 30 dni i 20 000 wpisów', () {
      expect(appLogRetention, const Duration(days: 30));
      expect(appLogMaxEntries, 20000);
    });

    test('po wieku i po liczbie, z liczbą usuniętych', () async {
      final log = dziennik(maxEntries: 3);
      for (var i = 0; i < 6; i++) {
        log.info(LogArea.app, 'wpis $i');
        zegar.przesun(const Duration(days: 7));
      }
      await log.flush();
      // Teraz jest dzień 42: dzień 0 i 7 są starsze niż 30 dni, a z reszty
      // (14, 21, 28, 35) zostają trzy najnowsze.
      expect(await log.trim(), 3);
      expect(await tresci(), ['wpis 3', 'wpis 4', 'wpis 5']);
      expect(await log.trim(), 0, reason: 'nic więcej do przycięcia');
    });
  });

  group('zwijanie powtórek', () {
    test('ten sam wpis w oknie jest liczony, licznik idzie przy flush',
        () async {
      final log = dziennik();
      for (var i = 0; i < 5; i++) {
        log.error(LogArea.bt, 'Radio padło', error: StateError('ślad $i'));
        zegar.przesun(const Duration(seconds: 1));
      }
      log.info(LogArea.bt, 'Inny wpis');
      await log.flush();

      final wpisy = await db.allLogEntries();
      expect(wpisy.map((w) => w.message), [
        'Radio padło',
        'Inny wpis',
        'Radio padło (repeated 4 times)',
      ]);
      expect(wpisy.first.details, contains('ślad 0'),
          reason: 'szczegóły zostają przy pierwszym wpisie');
      expect(wpisy.last.details, isNull);
      expect(wpisy.last.level, LogLevel.error);
      expect(wpisy.last.area, LogArea.bt);
    });

    test('po upływie okna licznik ląduje na jego końcu, a wpis znowu idzie',
        () async {
      final start = zegar.teraz;
      final log = dziennik();
      log.warning(LogArea.net, 'Brak sieci');
      zegar.przesun(const Duration(seconds: 2));
      log.warning(LogArea.net, 'Brak sieci');
      zegar.przesun(const Duration(seconds: 2));
      log.warning(LogArea.net, 'Brak sieci');
      zegar.przesun(const Duration(seconds: 10));
      log.warning(LogArea.net, 'Brak sieci');
      await log.flush();

      final wpisy = await db.allLogEntries();
      expect(wpisy.map((w) => w.message), [
        'Brak sieci',
        'Brak sieci (repeated 2 times)',
        'Brak sieci',
      ]);
      expect(wpisy[1].atMs,
          start.add(appLogFloodWindow).millisecondsSinceEpoch,
          reason: 'licznik nosi chwilę zamknięcia okna');
      expect(wpisy[2].atMs,
          start.add(const Duration(seconds: 14)).millisecondsSinceEpoch);
    });

    test('flush pokazuje licznik, a trwający zalew dalej jest zwijany',
        () async {
      final log = dziennik();
      log.warning(LogArea.bt, 'Kanał milczy');
      log.warning(LogArea.bt, 'Kanał milczy');
      await log.flush();
      expect(await tresci(), ['Kanał milczy', 'Kanał milczy (repeated 1 times)']);

      zegar.przesun(const Duration(seconds: 3));
      log.warning(LogArea.bt, 'Kanał milczy');
      log.warning(LogArea.bt, 'Kanał milczy');
      await log.flush();
      await log.flush();
      expect(await tresci(), [
        'Kanał milczy',
        'Kanał milczy (repeated 1 times)',
        'Kanał milczy (repeated 2 times)',
      ], reason: 'to samo okno: bez nowego pierwszego wpisu, bez pustych liczników');
    });

    test('inny poziom albo obszar to inny wpis', () async {
      final log = dziennik();
      log.warning(LogArea.net, 'To samo');
      log.error(LogArea.net, 'To samo');
      log.warning(LogArea.bt, 'To samo');
      log.warning(LogArea.net, 'To samo');
      await log.flush();
      expect(await tresci(), [
        'To samo',
        'To samo',
        'To samo',
        'To samo (repeated 1 times)',
      ]);
    });

    test('dłuższe okno na prośbę wołającego', () async {
      final log = dziennik();
      void kanal() => log.add(LogLevel.warning, LogArea.bt, 'Kanał',
          collapseWithin: const Duration(minutes: 10));
      kanal();
      for (var i = 0; i < 1200; i++) {
        zegar.przesun(const Duration(milliseconds: 400));
        kanal();
      }
      // 8 minut odpytywania: dalej jedno okno.
      zegar.przesun(const Duration(minutes: 3));
      kanal();
      await log.flush();
      expect(await tresci(),
          ['Kanał', 'Kanał (repeated 1200 times)', 'Kanał']);
    });

    test('licznik trafia do bazy sam, gdy okno się zamknie', () async {
      final log = dziennik(
        floodWindow: const Duration(milliseconds: 150),
        prawdziwyZegar: true,
      );
      log.info(LogArea.update, 'Pytanie');
      log.info(LogArea.update, 'Pytanie');
      log.info(LogArea.update, 'Pytanie');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(await tresci(), ['Pytanie', 'Pytanie (repeated 2 times)'],
          reason: 'bez kolejnego wpisu i bez flush');
    });
  });

  test('clear kasuje bazę, paczkę w pamięci i okna powtórek', () async {
    final log = dziennik(flushDelay: const Duration(hours: 1));
    log.add(LogLevel.warning, LogArea.bt, 'Radio padło',
        details: 'stare szczegóły',
        collapseWithin: const Duration(minutes: 10));
    await log.flush();
    log.add(LogLevel.warning, LogArea.bt, 'Radio padło',
        collapseWithin: const Duration(minutes: 10));
    log.info(LogArea.app, 'czeka w pamięci');

    expect(await log.clear(), 1);
    await log.flush();
    expect(await tresci(), isEmpty,
        reason: 'ani paczka z pamięci, ani licznik nie wracają');

    log.add(LogLevel.warning, LogArea.bt, 'Radio padło',
        details: 'nowe szczegóły',
        collapseWithin: const Duration(minutes: 10));
    await log.flush();
    final wpisy = await db.allLogEntries();
    expect(wpisy.map((w) => w.message), ['Radio padło']);
    expect(wpisy.single.details, 'nowe szczegóły');
  });

  test('close zapisuje liczniki i przestaje przyjmować wpisy', () async {
    final log = dziennik(flushDelay: const Duration(hours: 1));
    log.info(LogArea.app, 'przed');
    log.info(LogArea.app, 'przed');
    expect(log.isClosed, isFalse);
    await log.close();
    expect(log.isClosed, isTrue);

    log.info(LogArea.app, 'po');
    log.error(LogArea.error, 'po', error: StateError('x'));
    await log.flush();
    expect(await tresci(), ['przed', 'przed (repeated 1 times)']);
    expect(await log.trim(), 0, reason: 'zamknięty dziennik nie tnie bazy');
  });

  group('describeError', () {
    test('bez wyjątku i stosu nie ma szczegółów', () {
      expect(describeError(null, null), isNull);
    });

    test('opis i ślad stosu', () {
      final opis = describeError(StateError('zepsute'), StackTrace.current)!;
      expect(opis, startsWith('Bad state: zepsute\n'));
      expect(opis, contains('#0'));
      expect(describeError(null, StackTrace.current), contains('#0'));
    });

    test('błąd pliku traci ścieżkę', () {
      final opis = describeError(
        const FileSystemException(
          'Cannot open file',
          r'C:\Users\Jan Kowalski\Documents\tajny-plan.pdf',
          OSError('Access is denied', 5),
        ),
        null,
      )!;
      expect(opis, contains('Cannot open file'));
      expect(opis, contains('Access is denied'));
      expect(opis, isNot(contains('Kowalski')));
      expect(opis, isNot(contains('tajny-plan')));
    });

    test('błąd pliku traci też ścieżkę wpisaną w komunikat', () {
      final opis = describeError(
        const FileSystemException(
          r"Cannot rename file to 'C:\Users\Jan Kowalski\Documents\Chatt"
          r"\received\1a2b3c4d_Jana's tajny-plan.pdf'",
          r'C:\x\.incomplete\abc.part',
          OSError('The filename syntax is incorrect.', 123),
        ),
        StackTrace.current,
      )!;
      expect(opis, contains('Cannot rename file to'));
      expect(opis, contains('The filename syntax is incorrect.'));
      expect(opis, isNot(contains('Kowalski')));
      expect(opis, isNot(contains('tajny-plan')));
      expect(opis, contains('#0'), reason: 'ślad stosu zostaje');
    });

    test('błąd formatu traci cytat z wejścia', () {
      final opis = describeError(
          const FormatException('Unexpected character', 'Tajna treść', 3),
          null)!;
      expect(opis, 'FormatException: Unexpected character');
    });

    test('błąd SQLite traci wartości parametrów', () {
      final opis = describeError(_BladSql(), null)!;
      expect(opis, contains('UNIQUE constraint failed'));
      expect(opis, contains('Causing statement'));
      expect(opis, isNot(contains('Tajna treść')));
    });

    test('błąd SQLite traci wszystkie linie parametrów', () {
      final opis =
          describeError(_BladSqlWielolinijkowy(), StackTrace.current)!;
      expect(opis, contains('database or disk is full'));
      expect(opis, contains('Causing statement'));
      for (final tajne in ['pierwsza linia', 'Tajna', 'trzecia', '42']) {
        expect(opis, isNot(contains(tajne)), reason: tajne);
      }
      expect(opis, contains('#0'), reason: 'cięcie kończy się na opisie');
    });

    test('opis, który się wywraca, zostaje nazwą typu', () {
      expect(describeError(_ZlyOpis(), null), '_ZlyOpis');
    });
  });

  group('echo na konsolę', () {
    late List<String> wydruki;
    late DebugPrintCallback poprzedni;

    setUp(() {
      wydruki = [];
      poprzedni = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) =>
          wydruki.add(message ?? '');
    });

    tearDown(() => debugPrint = poprzedni);

    test('domyślnie wyłączone', () async {
      final log = AppLog(db, clock: zegar.call);
      otwarte.add(log);
      expect(log.echo, isFalse);
      log.info(LogArea.app, 'cicho');
      log.error(LogArea.error, 'też cicho', error: StateError('x'));
      await log.close();
      expect(wydruki, isEmpty);
    });

    test('włączone pisze zapisane wpisy, bez powtórek', () async {
      final log = dziennik(echo: true);
      log.warning(LogArea.net, 'Brak sieci', error: StateError('zła sieć'));
      log.warning(LogArea.net, 'Brak sieci');
      await log.close();
      expect(wydruki.first, '[chatt warning] net: Brak sieci');
      expect(wydruki[1], contains('zła sieć'));
      expect(wydruki.last,
          '[chatt warning] net: Brak sieci (repeated 1 times)');
      expect(wydruki, hasLength(3));
    });
  });

  group('błędy bez obsługi', () {
    late FlutterExceptionHandler? poprzedniFluttera;
    late ErrorCallback? poprzedniPlatformy;
    late List<FlutterErrorDetails> przekazane;

    setUp(() {
      poprzedniFluttera = FlutterError.onError;
      poprzedniPlatformy = PlatformDispatcher.instance.onError;
      przekazane = [];
      FlutterError.onError = przekazane.add;
      PlatformDispatcher.instance.onError = null;
    });

    tearDown(() {
      FlutterError.onError = poprzedniFluttera;
      PlatformDispatcher.instance.onError = poprzedniPlatformy;
    });

    test('trafiają do dziennika jako error i idą dalej', () async {
      final log = dziennik();
      logUncaughtErrors(log);

      final details = FlutterErrorDetails(
        exception: StateError('zepsute'),
        stack: StackTrace.current,
        library: 'widgets library',
        context: ErrorDescription('while building EkranRozmowy'),
      );
      FlutterError.reportError(details);
      expect(przekazane, [details],
          reason: 'poprzednia obsługa dostaje błąd jak dawniej');

      final obsluzony = PlatformDispatcher.instance.onError!(
          ArgumentError('zły argument'), StackTrace.current);
      expect(obsluzony, isTrue,
          reason: 'bez wcześniejszej obsługi błąd jest obsłużony wpisem');

      await log.flush();
      final wpisy = await db.allLogEntries();
      expect(wpisy.map((w) => w.message), [
        'Uncaught Flutter error: StateError (widgets library)',
        'Uncaught error: ArgumentError',
      ]);
      for (final wpis in wpisy) {
        expect(wpis.level, LogLevel.error);
        expect(wpis.area, LogArea.error);
        expect(wpis.details, contains('#0'), reason: 'ślad stosu');
      }
      expect(wpisy.first.details,
          startsWith('context: while building EkranRozmowy\n'));
      expect(wpisy.first.details, contains('zepsute'));
      expect(wpisy.last.details, contains('zły argument'));
    });

    test('wcześniejsza obsługa błędów asynchronicznych decyduje sama',
        () async {
      final widziane = <Object>[];
      PlatformDispatcher.instance.onError = (blad, _) {
        widziane.add(blad);
        return false;
      };
      final log = dziennik();
      logUncaughtErrors(log);

      final blad = StateError('w tle');
      expect(PlatformDispatcher.instance.onError!(blad, StackTrace.current),
          isFalse);
      expect(widziane, [blad]);
      await log.flush();
      expect(await tresci(), ['Uncaught error: StateError']);
    });
  });

  group('napisy z zewnątrz', () {
    test('rozmówca: nazwa bez znaków sterujących i początek guid-a', () {
      expect(peerLabel('Jan\nError: fałszywy wpis', 'abcdef0123456789'),
          'Jan Error: fałszywy wpis (abcdef01)');
      expect(peerLabel('', 'abc'), '(abc)');
    });

    test('długi napis jest przycięty', () {
      final dlugi = 'x' * 100;
      expect(logText(dlugi), '${'x' * 64}…');
      expect(logText(dlugi, maxLength: 10), '${'x' * 10}…');
      expect(logText('  krótki\t'), 'krótki');
    });

    test('adresy sprzętowe są zasłonięte', () {
      expect(
          maskHardwareAddresses(
              'connect to AA:BB:CC:DD:EE:0F failed, then 11-22-33-44-55-66'),
          'connect to <address> failed, then <address>');
      expect(maskHardwareAddresses('port 5000 wsa=10060'),
          'port 5000 wsa=10060');
    });
  });
}
