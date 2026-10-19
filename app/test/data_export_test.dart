import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/core/file_actions.dart';
import 'package:chatt/core/received_paths.dart';
import 'package:chatt/core/version.dart';
import 'package:chatt/core/zip_writer.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/network/transport.dart' show PeerProtocol;
import 'package:chatt/services/app_log.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/data_export.dart';
import 'package:chatt/services/typing_journal.dart';

/// Eksport danych do ZIP (issue #50) na prawdziwej instancji [AppServices]:
/// baza w pamięci, prawdziwe pliki w katalogu tymczasowym, archiwum
/// czytane z powrotem czytnikiem z testu. Pilnuje układu archiwum, treści
/// JSON i tekstów, odebranych plików oraz tego, że do eksportu nie trafia
/// żaden klucz.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory katalog;
  late AppServices s;
  late _Dane dane;

  /// Chwila eksportu w testach.
  final teraz = DateTime(2026, 10, 18, 16, 45, 30);

  setUp(() async {
    katalog = Directory.systemTemp.createTempSync('chatt_eksport_');
    s = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Eksporter',
      enableDiscovery: false,
      receivedDirOverride: p.join(katalog.path, 'received'),
    );
    dane = await _zasiej(s, katalog.path);
  });

  tearDown(() async {
    await s.dispose();
    katalog.deleteSync(recursive: true);
  });

  Future<({ExportResult wynik, Map<String, Uint8List> wpisy})> eksportuj(
    ExportParts czesci, {
    int maxBytes = zipMaxBytes,
  }) async {
    final sciezka = p.join(katalog.path, 'eksport.zip');
    final wynik = await writeExport(s, sciezka, czesci,
        now: teraz, maxBytes: maxBytes);
    final bajty = File(sciezka).readAsBytesSync();
    expect(wynik.path, sciezka);
    expect(wynik.bytes, bajty.length);
    return (wynik: wynik, wpisy: _czytajZip(bajty));
  }

  Object? json(Map<String, Uint8List> wpisy, String nazwa) =>
      jsonDecode(utf8.decode(wpisy[nazwa]!));

  String tekst(Map<String, Uint8List> wpisy, String nazwa) =>
      utf8.decode(wpisy[nazwa]!);

  Map<String, Object?> wiadomosc(Map<String, Uint8List> wpisy, String guid) {
    final rozmowy = json(wpisy, 'conversations.json')! as List;
    return [
      for (final r in rozmowy)
        for (final m in (r as Map)['messages'] as List) m as Map<String, Object?>,
    ].singleWhere((m) => m['guid'] == guid);
  }

  final isoZPrzesunieciem =
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$');
  final isoZMilisekundami =
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}$');

  void tenSamMoment(Object? napis, DateTime kiedy) {
    expect(napis, isA<String>());
    expect(DateTime.parse(napis! as String).isAtSameMomentAs(kiedy), isTrue,
        reason: '$napis i $kiedy');
  }

  test('nazwa pliku eksportu', () {
    expect(exportFileName(DateTime(2026, 10, 18, 15, 30, 59)),
        'chatt-export-2026-10-18-1530.zip');
    expect(exportFileName(DateTime(2027, 1, 2, 3, 4)),
        'chatt-export-2027-01-02-0304.zip');
  });

  test('estimateExport liczy dane i odebrane pliki, które są na dysku',
      () async {
    final szacunek = await estimateExport(s);
    expect(szacunek.peers, 2);
    expect(szacunek.conversations, 1);
    expect(szacunek.messages, 6);
    expect(szacunek.typingSessions, 2);
    expect(szacunek.logEntries, (await s.db.allLogEntries()).length);
    expect(szacunek.logEntries, greaterThanOrEqualTo(2));
    // Tylko zdjęcie: skasowany plik zniknął, klucz leży poza katalogiem
    // odebranych, a wysłany plik nie jest odebrany.
    expect(szacunek.files, 1);
    expect(szacunek.fileBytes, dane.zdjecie.length);
  });

  test('wszystkie części: układ archiwum, manifest, README', () async {
    final (:wynik, :wpisy) = await eksportuj(const ExportParts(files: true));

    expect(wpisy.keys, [
      'README.txt',
      'settings.json',
      'devices.json',
      'typing-history.json',
      'typing-history.txt',
      'app-log.json',
      'app-log.txt',
      dane.zdjecieWArchiwum,
      'conversations.json',
      'manifest.json',
    ]);
    expect(dane.zdjecieWArchiwum,
        'files/${diskToken(_guid(3)).substring(0, 8)}_zdjęcie z wakacji.jpg');
    expect(wpisy[dane.zdjecieWArchiwum], dane.zdjecie);
    expect(wynik.files, 1);
    expect(wynik.skippedFiles, ['skasowany.pdf', 'chatt.key']);

    final manifest = json(wpisy, 'manifest.json')! as Map<String, Object?>;
    expect(manifest['format'], 'chatt-export');
    expect(manifest['formatVersion'], 1);
    expect(manifest['appVersion'], appVersion);
    expect(manifest['exportedAt'], matches(isoZPrzesunieciem));
    tenSamMoment(manifest['exportedAt'], teraz);
    expect(manifest['device'], {'guid': s.identity.guid, 'name': 'Eksporter'});
    expect(manifest['parts'], {
      'conversations': true,
      'typing': true,
      'appLog': true,
      'files': true,
    });
    final log = json(wpisy, 'app-log.json')! as List;
    expect(manifest['counts'], {
      'devices': 2,
      'conversations': 1,
      'messages': 6,
      'typingSessions': 2,
      'typingEntries': 3,
      'logEntries': log.length,
      'files': 1,
      'fileBytes': dane.zdjecie.length,
    });
    expect(manifest['skippedFiles'], [
      {'name': 'skasowany.pdf', 'reason': 'missing'},
      {'name': 'chatt.key', 'reason': 'outsideReceivedDir'},
    ]);

    final readme = tekst(wpisy, 'README.txt');
    expect(readme, contains('THIS FILE IS NOT ENCRYPTED'));
    expect(readme, contains('TEN PLIK NIE JEST ZASZYFROWANY'));
    expect(readme, contains('App version: $appVersion'));
    expect(readme, contains('Device: Eksporter (${s.identity.guid})'));
    expect(readme, contains('Exported: 2026-10-18 16:45:30'));
    for (final nazwa in ['conversations.json', 'typing-history.json',
        'app-log.txt', 'files/']) {
      expect(readme, contains(nazwa));
    }
  });

  test('JSON: ustawienia, urządzenia i rozmowy', () async {
    final (:wynik, :wpisy) = await eksportuj(const ExportParts(files: true));

    final ustawienia = json(wpisy, 'settings.json')! as Map<String, Object?>;
    expect(ustawienia.containsKey('identityKey'), isFalse);
    expect(ustawienia['deviceGuid'], s.identity.guid);
    expect(ustawienia['nickname'], 'Eksporter');
    expect(ustawienia['theme'], AppTheme.system.name);
    expect(ustawienia['style'], AppStyle.cisza.name);
    expect(ustawienia['language'], isA<String>());
    expect(AppLanguage.values.map((j) => j.name), contains(ustawienia['language']));
    expect(ustawienia['typingHistory'], isTrue);
    expect(ustawienia['lastUpdateCheck'], isNull);

    final urzadzenia = (json(wpisy, 'devices.json')! as List)
        .cast<Map<String, Object?>>();
    expect(urzadzenia, hasLength(2));
    for (final u in urzadzenia) {
      expect(u.containsKey('sessionKey'), isFalse);
      expect(u['firstSeen'], matches(isoZPrzesunieciem));
      expect(u['lastSeen'], matches(isoZPrzesunieciem));
    }
    final ania = urzadzenia.singleWhere((u) => u['guid'] == 'guid-ani');
    expect(ania['name'], 'Laptop Ani');
    expect(ania['alias'], 'Ania');
    expect(ania['verified'], isTrue);
    expect(ania['lastProtocol'], 'wifi');
    expect(ania['host'], '192.168.1.20');
    expect(ania['port'], 45321);
    final bartek = urzadzenia.singleWhere((u) => u['guid'] == 'guid-bartka');
    expect(bartek['lastProtocol'], 'bluetooth');
    expect(bartek['btAddress'], 'AA:BB:CC:DD:EE:FF');
    expect(bartek['verified'], isFalse);

    final rozmowy = (json(wpisy, 'conversations.json')! as List)
        .cast<Map<String, Object?>>();
    final rozmowa = rozmowy.single;
    expect(rozmowa['peer'],
        {'guid': 'guid-ani', 'name': 'Laptop Ani', 'alias': 'Ania'});
    expect(rozmowa['createdAt'], matches(isoZPrzesunieciem));
    expect(rozmowa['updatedAt'], matches(isoZPrzesunieciem));
    expect(rozmowa['messages'] as List, hasLength(6));

    final wyslana = wiadomosc(wpisy, _guid(1));
    expect(wyslana['direction'], 'outgoing');
    expect(wyslana['status'], 'pending');
    expect(wyslana['kind'], 'text');
    expect(wyslana['body'], 'Cześć, co słychać?');
    expect(wyslana.containsKey('file'), isFalse);
    expect(wyslana['deliveredAt'], isNull);

    final odebrana = wiadomosc(wpisy, _guid(2));
    expect(odebrana['direction'], 'incoming');
    expect(odebrana['status'], 'delivered');
    tenSamMoment(odebrana['createdAt'], dane.t0.add(const Duration(minutes: 1)));
    expect(odebrana['deliveredAt'], matches(isoZPrzesunieciem));
    expect(odebrana['readAt'], isNull);
    expect(odebrana['restoredAt'], isNull);

    final zdjecie = wiadomosc(wpisy, _guid(3));
    expect(zdjecie['kind'], 'file');
    expect(zdjecie['file'], {
      'name': 'zdjęcie z wakacji.jpg',
      'size': dane.zdjecie.length,
      'path': dane.zdjeciePath,
      'archivePath': dane.zdjecieWArchiwum,
    });
    for (final guid in [_guid(4), _guid(5), _guid(6)]) {
      final plik = wiadomosc(wpisy, guid)['file']! as Map;
      expect(plik.containsKey('archivePath'), isFalse, reason: guid);
      expect(plik['name'], isNotNull);
    }
  });

  test('historia pisania: sesje, kawałki, ukryty tekst, odtworzony tekst',
      () async {
    final (:wynik, :wpisy) = await eksportuj(const ExportParts());

    final sesje = (json(wpisy, 'typing-history.json')! as List)
        .cast<Map<String, Object?>>();
    expect(sesje, hasLength(2));

    final pierwsza = sesje[0];
    expect(pierwsza['inputId'], 'wejscie-1');
    expect(pierwsza['direction'], 'outgoing');
    expect(pierwsza['peer'], {'guid': 'guid-ani', 'name': 'Laptop Ani'});
    tenSamMoment(pierwsza['startedAt'], dane.t0);
    tenSamMoment(pierwsza['endedAt'], dane.t0.add(const Duration(minutes: 1)));
    expect(pierwsza['result'], TypingResult.accepted);
    expect(pierwsza['endReason'], TypingEnd.stoppedHere);
    final kawalki = (pierwsza['entries']! as List).cast<Map<String, Object?>>();
    expect(kawalki, hasLength(3));
    expect(kawalki[0], {
      'at': kawalki[0]['at'],
      'app': 'com.example.notes',
      'appLabel': 'Notatki',
      'field': 'text',
      'status': 'typed',
      'chars': 14,
      'hidden': false,
      'ops': [
        {'t': 'insert', 's': 'Ala ma kota'},
        {'t': 'bs', 'n': 4},
        {'t': 'insert', 's': 'psa'},
        {'t': 'action'},
      ],
      'text': 'Ala ma kota[Backspace x4]psa[Enter]',
    });
    tenSamMoment(kawalki[0]['at'], dane.t0.add(const Duration(seconds: 5)));
    expect(kawalki[1]['field'], 'password');
    expect(kawalki[1]['hidden'], isTrue);
    expect(kawalki[1]['chars'], 8);
    expect(kawalki[1]['ops'], [
      {'t': 'insert', 'hidden': 8},
    ]);
    expect(kawalki[1]['text'], '[hidden: 8 chars]');
    expect(kawalki[2]['status'], 'paused');
    // Wstrzymany kawałek się nie wpisał, więc nie wchodzi do tekstu.
    expect(pierwsza['transcript'], 'Ala ma psa\n••••••••');

    final druga = sesje[1];
    expect(druga['direction'], 'incoming');
    expect(druga['result'], TypingResult.rejected);
    expect(druga['endReason'], isNull);
    expect(druga['endedAt'], matches(isoZPrzesunieciem));
    expect(druga['entries'], isEmpty);
    expect(druga['transcript'], '');

    final czytelna = tekst(wpisy, 'typing-history.txt');
    expect(czytelna, contains('Sessions: 2'));
    expect(czytelna, contains('outgoing: this device typed on Laptop Ani'));
    expect(czytelna, contains('incoming: Telefon Bartka typed on this device'));
    expect(czytelna, contains('Notatki (com.example.notes)'));
    expect(czytelna, contains('Ala ma kota[Backspace x4]psa[Enter]'));
    expect(czytelna, contains('[hidden: 8 chars]'));
    expect(czytelna, contains('    Ala ma psa\n    ••••••••'));
  });

  test('dziennik aplikacji: JSON z milisekundami i wiersze tekstu', () async {
    final (:wynik, :wpisy) = await eksportuj(const ExportParts());
    final wpisyDziennika = (json(wpisy, 'app-log.json')! as List)
        .cast<Map<String, Object?>>();
    await s.log.flush();
    // Wpis o samym eksporcie powstaje już po nim.
    final zBazy = (await s.db.allLogEntries())
        .where((e) => !e.message.startsWith('Data export written'));
    expect(wpisyDziennika, hasLength(zBazy.length));
    for (final e in wpisyDziennika) {
      expect(e['at'], matches(isoZMilisekundami));
      expect(LogLevel.values.map((l) => l.name), contains(e['level']));
    }
    final ostrzezenie =
        wpisyDziennika.singleWhere((e) => e['message'] == 'Transfer failed');
    expect(ostrzezenie['level'], 'warning');
    expect(ostrzezenie['area'], LogArea.file);
    expect(ostrzezenie['details'], 'Bad state: disk full');
    final informacja =
        wpisyDziennika.singleWhere((e) => e['message'] == 'Peer reachable');
    expect(informacja.containsKey('details'), isFalse);

    final wiersze = tekst(wpisy, 'app-log.txt');
    expect(
        wiersze,
        matches(RegExp(
            r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} WARN  file  '
            r'Transfer failed\n    Bad state: disk full$',
            multiLine: true)));
    expect(
        wiersze,
        matches(RegExp(
            r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} INFO  net  '
            r'Peer reachable$',
            multiLine: true)));
  });

  test('każda część osobno daje tylko swoje wpisy', () async {
    const zawsze = ['README.txt', 'manifest.json'];
    for (final (czesci, oczekiwane) in [
      (
        const ExportParts(typing: false, appLog: false),
        ['settings.json', 'devices.json', 'conversations.json'],
      ),
      (
        const ExportParts(conversations: false, appLog: false),
        ['typing-history.json', 'typing-history.txt'],
      ),
      (
        const ExportParts(conversations: false, typing: false),
        ['app-log.json', 'app-log.txt'],
      ),
      (
        const ExportParts(
            conversations: false, typing: false, appLog: false, files: true),
        [dane.zdjecieWArchiwum],
      ),
      (
        const ExportParts(conversations: false, typing: false, appLog: false),
        <String>[],
      ),
    ]) {
      final (:wynik, :wpisy) = await eksportuj(czesci);
      expect(wpisy.keys.toSet(), {...zawsze, ...oczekiwane},
          reason: '${czesci.conversations} ${czesci.typing} '
              '${czesci.appLog} ${czesci.files}');
      final manifest = json(wpisy, 'manifest.json')! as Map<String, Object?>;
      expect(manifest['parts'], {
        'conversations': czesci.conversations,
        'typing': czesci.typing,
        'appLog': czesci.appLog,
        'files': czesci.files,
      });
      expect(wynik.files, czesci.files ? 1 : 0);
    }
  });

  test('bez odebranych plików: brak files/, archivePath i pominiętych',
      () async {
    final (:wynik, :wpisy) = await eksportuj(const ExportParts());
    expect(wpisy.keys.where((n) => n.startsWith('files/')), isEmpty);
    expect(tekst(wpisy, 'conversations.json'), isNot(contains('archivePath')));
    final manifest = json(wpisy, 'manifest.json')! as Map<String, Object?>;
    expect(manifest['skippedFiles'], isEmpty);
    expect((manifest['counts']! as Map).containsKey('files'), isFalse);
    expect(wynik.files, 0);
    expect(wynik.skippedFiles, isEmpty);
  });

  test('żaden wpis nie niesie klucza tożsamości, klucza sesji ani hasła bazy',
      () async {
    final ustawienia = (await s.db.getSettings())!;
    final peer = (await s.db.peerByGuid('guid-ani'))!;
    // Dane do sprawdzenia naprawdę leżą w bazie i na dysku.
    expect(ustawienia.identityKey, isNotEmpty);
    expect(peer.sessionKey, _kluczSesji);
    expect(File(p.join(katalog.path, 'chatt.key')).readAsStringSync(),
        _hasloBazy);

    final sekrety = {
      'klucz tożsamości': utf8.encode(ustawienia.identityKey),
      'klucz sesji': utf8.encode(_kluczSesji),
      'hasło bazy': utf8.encode(_hasloBazy),
    };
    final (:wynik, :wpisy) = await eksportuj(const ExportParts(files: true));
    final archiwum = File(wynik.path).readAsBytesSync();
    for (final MapEntry(key: co, value: sekret) in sekrety.entries) {
      expect(_zawiera(archiwum, sekret), isFalse, reason: '$co w archiwum');
      for (final MapEntry(key: nazwa, value: bajty) in wpisy.entries) {
        expect(_zawiera(utf8.encode(nazwa), sekret), isFalse,
            reason: '$co w nazwie $nazwa');
        expect(_zawiera(bajty, sekret), isFalse, reason: '$co w $nazwa');
      }
    }
  });

  test('plik ponad granicę archiwum zostaje pominięty jako tooLarge',
      () async {
    final (:wynik, :wpisy) = await eksportuj(const ExportParts(files: true),
        maxBytes: dane.zdjecie.length - 1000);
    expect(wynik.bytes, lessThanOrEqualTo(dane.zdjecie.length - 1000));
    expect(wpisy.keys.where((n) => n.startsWith('files/')), isEmpty);
    expect(wynik.files, 0);
    expect(wynik.skippedFiles,
        ['skasowany.pdf', 'chatt.key', 'zdjęcie z wakacji.jpg']);
    final manifest = json(wpisy, 'manifest.json')! as Map<String, Object?>;
    expect(manifest['skippedFiles'], [
      {'name': 'skasowany.pdf', 'reason': 'missing'},
      {'name': 'chatt.key', 'reason': 'outsideReceivedDir'},
      {'name': 'zdjęcie z wakacji.jpg', 'reason': 'tooLarge'},
    ]);
    expect((manifest['counts']! as Map)['files'], 0);
    expect((wiadomosc(wpisy, _guid(3))['file']! as Map).containsKey('archivePath'),
        isFalse);
  });

  test('granica tuż przy pełnym rozmiarze: archiwum zawsze całe i w granicy',
      () async {
    // Bez dziennika: każdy eksport dopisuje do niego wpis, a tu rozmiar
    // archiwum ma stać w miejscu.
    const czesci = ExportParts(appLog: false, files: true);
    final pelny = (await eksportuj(czesci)).wynik.bytes;
    for (final zapas in [10000, 0, -1, -50, -200, -1000, -20000]) {
      final granica = pelny + zapas;
      final (:wynik, :wpisy) = await eksportuj(czesci, maxBytes: granica);
      expect(wynik.bytes, lessThanOrEqualTo(granica), reason: '$zapas');
      final weszlo = wpisy.containsKey(dane.zdjecieWArchiwum);
      if (zapas > 0) expect(weszlo, isTrue);
      if (zapas < 0) expect(weszlo, isFalse);
      expect(wynik.files, weszlo ? 1 : 0);
      expect(wynik.skippedFiles.contains('zdjęcie z wakacji.jpg'), !weszlo);
      final zdjecie = wiadomosc(wpisy, _guid(3))['file']! as Map;
      expect(zdjecie['archivePath'], weszlo ? dane.zdjecieWArchiwum : isNull);
    }
  });

  test('eksport zapisuje to, co czekało w pamięci, i trafia do dziennika',
      () async {
    // Historia pisania liczy się tylko przy włączonym dodatku klawiatury.
    s.keyboardAddon.value = true;
    const pole = RemoteInputTarget(
      active: true,
      field: RemoteInputField.text,
      app: 'com.example.notes',
      appLabel: 'Notatki',
    );
    final sesja = s.typingJournal.begin(
      direction: MessageDirection.incoming,
      inputId: 'wejscie-3',
      peerGuid: 'guid-ani',
      peerName: 'Laptop Ani',
      result: TypingResult.automatic,
    );
    expect(sesja, isNotNull);
    s.typingJournal.record(sesja, const [RemoteInputOp.insert('świeże')],
        status: TypingStatus.typed, before: pole, after: pole);
    s.log.info(LogArea.app, 'Right before export');

    final (:wynik, :wpisy) = await eksportuj(const ExportParts(files: true));

    final sesje = (json(wpisy, 'typing-history.json')! as List)
        .cast<Map<String, Object?>>();
    final swieza = sesje.singleWhere((x) => x['inputId'] == 'wejscie-3');
    expect(swieza['endedAt'], isNull);
    expect(swieza['transcript'], 'świeże');
    expect((json(wpisy, 'app-log.json')! as List).map((e) => (e as Map)['message']),
        contains('Right before export'));

    await s.log.flush();
    final ostatni = (await s.db.allLogEntries()).last;
    expect(ostatni.level, LogLevel.info);
    expect(ostatni.area, LogArea.app);
    expect(
        ostatni.message,
        'Data export written: parts=conversations,typing,appLog,files '
        'devices=2 conversations=1 messages=6 typingSessions=3 '
        'typingEntries=4 logEntries=${(json(wpisy, 'app-log.json')! as List).length} '
        'files=1 fileBytes=${dane.zdjecie.length} skippedFiles=2 '
        'bytes=${wynik.bytes}');
    expect(ostatni.message, isNot(contains(katalog.path)));
  });

  group('exportAndSave', () {
    test('pulpit: okno zapisu z podpowiedzianą nazwą, dopisane .zip',
        () async {
      String? podpowiedz;
      final wynik = await exportAndSave(
        s,
        const ExportParts(files: true),
        now: DateTime(2026, 10, 18, 15, 30),
        android: false,
        chooseLocation: (nazwa) async {
          podpowiedz = nazwa;
          return p.join(katalog.path, 'mój eksport');
        },
      );
      expect(podpowiedz, 'chatt-export-2026-10-18-1530.zip');
      expect(wynik.result, SaveResult.saved);
      expect(wynik.where, p.join(katalog.path, 'mój eksport.zip'));
      expect(wynik.export!.path, wynik.where);
      expect(wynik.export!.files, 1);
      final wpisy = _czytajZip(File(wynik.where!).readAsBytesSync());
      expect(wpisy.keys, contains('manifest.json'));

      final zRozszerzeniem = await exportAndSave(
        s,
        const ExportParts(),
        android: false,
        chooseLocation: (_) async => p.join(katalog.path, 'DRUGI.ZIP'),
      );
      expect(zRozszerzeniem.where, p.join(katalog.path, 'DRUGI.ZIP'));
      expect(File(p.join(katalog.path, 'DRUGI.ZIP')).existsSync(), isTrue);
    });

    test('pulpit: zamknięte okno zapisu niczego nie zapisuje', () async {
      final przed = katalog.listSync().length;
      final wynik = await exportAndSave(
        s,
        const ExportParts(),
        android: false,
        chooseLocation: (_) async => null,
      );
      expect(wynik.result, SaveResult.cancelled);
      expect(wynik.export, isNull);
      expect(katalog.listSync(), hasLength(przed));
    });

    test('pulpit: zapis w miejscu bez dostępu kończy się failed', () async {
      final wynik = await exportAndSave(
        s,
        const ExportParts(),
        android: false,
        chooseLocation: (_) async =>
            p.join(katalog.path, 'nie ma takiego katalogu', 'eksport.zip'),
      );
      expect(wynik.result, SaveResult.failed);
      expect(wynik.export, isNull);
      await s.log.flush();
      expect((await s.db.allLogEntries()).last.message, 'Data export failed');
    });

    group('Android', () {
      late Directory cache;
      late File stary;

      setUp(() {
        cache = Directory(p.join(katalog.path, 'cache'));
        final eksport = Directory(p.join(cache.path, 'eksport'))
          ..createSync(recursive: true);
        stary = File(p.join(eksport.path, 'chatt-export-2026-10-01-0900.zip'))
          ..writeAsStringSync('poprzedni eksport');
      });

      String oczekiwana() =>
          p.join(cache.path, 'eksport', 'chatt-export-2026-10-18-1530.zip');

      test('kopia do Pobranych, potem sprzątanie pamięci podręcznej',
          () async {
        String? kopiowany;
        final wynik = await exportAndSave(
          s,
          const ExportParts(files: true),
          now: DateTime(2026, 10, 18, 15, 30),
          android: true,
          temporaryDirectory: () async => cache,
          saveCopy: (sciezka) async {
            kopiowany = sciezka;
            expect(stary.existsSync(), isFalse,
                reason: 'poprzednie archiwum znika przed nowym');
            final wpisy = _czytajZip(File(sciezka).readAsBytesSync());
            expect(wpisy.keys.where((n) => n.startsWith('files/')),
                hasLength(1));
            return (result: SaveResult.saved, where: 'Download');
          },
          share: (_) async => fail('Kopia się udała, bez udostępniania'),
        );
        expect(kopiowany, oczekiwana());
        expect(wynik.result, SaveResult.saved);
        expect(wynik.where, 'Download');
        expect(wynik.export!.files, 1);
        expect(File(oczekiwana()).existsSync(), isFalse);
      });

      test('bez zapisu do Pobranych archiwum idzie do „Udostępnij"',
          () async {
        String? udostepniony;
        final wynik = await exportAndSave(
          s,
          const ExportParts(),
          now: DateTime(2026, 10, 18, 15, 30),
          android: true,
          temporaryDirectory: () async => cache,
          saveCopy: (_) async =>
              (result: SaveResult.unsupported, where: null),
          share: (sciezka) async {
            udostepniony = sciezka;
            return FileActionResult.ok;
          },
        );
        expect(udostepniony, oczekiwana());
        expect(wynik.result, SaveResult.saved);
        expect(wynik.where, isNull);
        expect(wynik.export, isNotNull);
        // Aplikacja, która przyjmie archiwum, czyta je po wyborze.
        expect(File(oczekiwana()).existsSync(), isTrue);
      });

      test('nieudane udostępnienie i nieudana kopia kasują archiwum',
          () async {
        final bezUdostepnienia = await exportAndSave(
          s,
          const ExportParts(),
          now: DateTime(2026, 10, 18, 15, 30),
          android: true,
          temporaryDirectory: () async => cache,
          saveCopy: (_) async =>
              (result: SaveResult.unsupported, where: null),
          share: (_) async => FileActionResult.failed,
        );
        expect(bezUdostepnienia.result, SaveResult.failed);
        expect(bezUdostepnienia.export, isNull);
        expect(File(oczekiwana()).existsSync(), isFalse);

        final bezKopii = await exportAndSave(
          s,
          const ExportParts(),
          now: DateTime(2026, 10, 18, 15, 30),
          android: true,
          temporaryDirectory: () async => cache,
          saveCopy: (_) async => (result: SaveResult.failed, where: null),
          share: (_) async => fail('Po nieudanej kopii nic nie udostępniamy'),
        );
        expect(bezKopii.result, SaveResult.failed);
        expect(File(oczekiwana()).existsSync(), isFalse);

        await s.log.flush();
        final ostrzezenia = (await s.db.allLogEntries())
            .where((e) => e.level == LogLevel.warning)
            .map((e) => e.message);
        expect(ostrzezenia, containsAll(
            ['Export share failed: failed', 'Export copy failed: failed']));
      });
    });
  });
}

const _kluczSesji = 'KLUCZ-SESJI-z-dawnego-parowania-0123456789abcdef';
const _hasloBazy = 'HASLO-BAZY-z-pliku-chatt-key-fedcba9876543210';

String _guid(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

/// Co zasiewa [_zasiej], do sprawdzania w testach.
class _Dane {
  final DateTime t0;
  final Uint8List zdjecie;
  final String zdjeciePath;
  final String zdjecieWArchiwum;

  _Dane(this.t0, this.zdjecie, this.zdjeciePath, this.zdjecieWArchiwum);
}

/// Dwa urządzenia (jedno z kluczem sesji z dawnego parowania), rozmowa
/// z tekstami i plikami (odebrany na dysku, odebrany i skasowany, odebrany
/// spoza katalogu odebranych, wysłany), dwie sesje pisania (jedna z ukrytym
/// kawałkiem) i wpisy dziennika.
Future<_Dane> _zasiej(AppServices s, String katalog) async {
  final db = s.db;
  final t0 = DateTime(2026, 10, 18, 15);

  final ania = await db.upsertPeer(
    guid: 'guid-ani',
    name: 'Laptop Ani',
    welcomeMessage: 'Cześć!',
    host: '192.168.1.20',
    port: 45321,
    protocol: PeerProtocol.wifi.index,
  );
  await db.setPeerPaired(ania.id, _kluczSesji);
  await db.setPeerAlias(ania.id, 'Ania');
  await db.upsertPeer(
    guid: 'guid-bartka',
    name: 'Telefon Bartka',
    welcomeMessage: '',
    host: '',
    port: 0,
    btAddress: 'AA:BB:CC:DD:EE:FF',
    protocol: PeerProtocol.bluetooth.index,
  );

  final rozmowa = await db.ensureConversation(ania.id);
  await db.insertOutgoing(
      conversationId: rozmowa,
      messageGuid: _guid(1),
      body: 'Cześć, co słychać?');
  await db.insertIncoming(
      conversationId: rozmowa,
      messageGuid: _guid(2),
      body: 'Dobrze! Wysyłam zdjęcie.',
      sentAt: t0.add(const Duration(minutes: 1)));

  final los = Random(5);
  final zdjecie =
      Uint8List.fromList(List.generate(50000, (_) => los.nextInt(256)));
  final zdjeciePath =
      receivedFilePath(s.receivedDir, _guid(3), 'zdjęcie z wakacji.jpg');
  File(zdjeciePath).writeAsBytesSync(zdjecie);
  await db.insertIncoming(
      conversationId: rozmowa,
      messageGuid: _guid(3),
      body: '',
      sentAt: t0.add(const Duration(minutes: 2)),
      kind: MessageKind.file,
      fileName: 'zdjęcie z wakacji.jpg',
      fileSize: zdjecie.length,
      filePath: zdjeciePath);

  await db.insertIncoming(
      conversationId: rozmowa,
      messageGuid: _guid(4),
      body: '',
      sentAt: t0.add(const Duration(minutes: 3)),
      kind: MessageKind.file,
      fileName: 'skasowany.pdf',
      fileSize: 1234,
      filePath: receivedFilePath(s.receivedDir, _guid(4), 'skasowany.pdf'));

  // Wiersz wskazujący plik z kluczem bazy, który leży obok katalogu
  // odebranych: eksport bierze pliki wyłącznie z tego katalogu.
  final klucz = p.join(katalog, 'chatt.key');
  File(klucz).writeAsStringSync(_hasloBazy);
  await db.insertIncoming(
      conversationId: rozmowa,
      messageGuid: _guid(5),
      body: '',
      sentAt: t0.add(const Duration(minutes: 4)),
      kind: MessageKind.file,
      fileName: 'chatt.key',
      fileSize: _hasloBazy.length,
      filePath: klucz);

  final wyslany = p.join(katalog, 'wysłany.txt');
  File(wyslany).writeAsStringSync('wysłany plik');
  await db.insertOutgoing(
      conversationId: rozmowa,
      messageGuid: _guid(6),
      body: '',
      kind: MessageKind.file,
      fileName: 'wysłany.txt',
      fileSize: File(wyslany).lengthSync(),
      filePath: wyslany);

  final sesja = await db.insertTypingSession(TypingSessionsCompanion.insert(
    inputId: 'wejscie-1',
    direction: MessageDirection.outgoing,
    peerGuid: 'guid-ani',
    peerName: 'Laptop Ani',
    startedAt: t0,
    result: TypingResult.accepted,
  ));
  await db.insertTypingEntries([
    TypingEntriesCompanion.insert(
      sessionId: sesja,
      at: t0.add(const Duration(seconds: 5)),
      app: const Value('com.example.notes'),
      appLabel: const Value('Notatki'),
      field: RemoteInputField.text.name,
      status: TypingStatus.typed.name,
      ops: TypingOp.encode(const [
        TypingOp.insert('Ala ma kota'),
        TypingOp.backspace(4),
        TypingOp.insert('psa'),
        TypingOp.action(),
      ]),
      chars: const Value(14),
    ),
    TypingEntriesCompanion.insert(
      sessionId: sesja,
      at: t0.add(const Duration(seconds: 10)),
      app: const Value('com.example.bank'),
      appLabel: const Value('Bank'),
      field: RemoteInputField.password.name,
      status: TypingStatus.typed.name,
      ops: TypingOp.encode(const [TypingOp.hidden(8)]),
      chars: const Value(8),
      masked: const Value(true),
    ),
    TypingEntriesCompanion.insert(
      sessionId: sesja,
      at: t0.add(const Duration(seconds: 15)),
      app: const Value('com.example.notes'),
      appLabel: const Value('Notatki'),
      field: RemoteInputField.text.name,
      status: TypingStatus.paused.name,
      ops: TypingOp.encode(const [TypingOp.insert('czekało')]),
      chars: const Value(7),
    ),
  ]);
  await db.endTypingSession(
      sesja, t0.add(const Duration(minutes: 1)), TypingEnd.stoppedHere);
  await db.insertTypingSession(TypingSessionsCompanion.insert(
    inputId: 'wejscie-2',
    direction: MessageDirection.incoming,
    peerGuid: 'guid-bartka',
    peerName: 'Telefon Bartka',
    startedAt: t0.add(const Duration(minutes: 2)),
    endedAt: Value(t0.add(const Duration(minutes: 2))),
    result: TypingResult.rejected,
  ));

  s.log.info(LogArea.net, 'Peer reachable');
  s.log.warning(LogArea.file, 'Transfer failed',
      error: StateError('disk full'));
  await s.log.flush();

  return _Dane(
    t0,
    zdjecie,
    zdjeciePath,
    'files/${diskToken(_guid(3)).substring(0, 8)}_zdjęcie z wakacji.jpg',
  );
}

bool _zawiera(List<int> stog, List<int> igla) {
  if (igla.isEmpty) return true;
  outer:
  for (var i = 0; i + igla.length <= stog.length; i++) {
    for (var j = 0; j < igla.length; j++) {
      if (stog[i + j] != igla[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// Wpisy archiwum po nazwie, w kolejności z katalogu centralnego. Czytnik
/// ten sam co w `zip_writer_test.dart`, skrócony: sprawdza zgodność
/// nagłówków, ciągłość wpisów, rozmiary i CRC.
Map<String, Uint8List> _czytajZip(Uint8List zip) {
  final b = ByteData.sublistView(zip);
  int u16(int o) => b.getUint16(o, Endian.little);
  int u32(int o) => b.getUint32(o, Endian.little);

  final koniec = zip.length - 22;
  expect(u32(koniec), 0x06054b50);
  final ile = u16(koniec + 10);
  final poczatekKatalogu = u32(koniec + 16);
  expect(poczatekKatalogu + u32(koniec + 12), koniec);

  final wynik = <String, Uint8List>{};
  var o = poczatekKatalogu;
  var nastepny = 0;
  for (var i = 0; i < ile; i++) {
    expect(u32(o), 0x02014b50);
    final flagi = u16(o + 8);
    final metoda = u16(o + 10);
    final crc = u32(o + 16);
    final spakowane = u32(o + 20);
    final surowe = u32(o + 24);
    final n = u16(o + 28);
    final lokalny = u32(o + 42);
    expect(flagi & 0x0800, 0x0800);
    final nazwa = utf8.decode(Uint8List.sublistView(zip, o + 46, o + 46 + n));
    o += 46 + n + u16(o + 30) + u16(o + 32);

    expect(lokalny, nastepny, reason: nazwa);
    expect(u32(lokalny), 0x04034b50);
    expect(u32(lokalny + 14), crc, reason: nazwa);
    expect(u32(lokalny + 18), spakowane, reason: nazwa);
    expect(u32(lokalny + 22), surowe, reason: nazwa);
    final start = lokalny + 30 + u16(lokalny + 26) + u16(lokalny + 28);
    final spak = Uint8List.sublistView(zip, start, start + spakowane);
    nastepny = start + spakowane;
    final dane = Uint8List.fromList(switch (metoda) {
      0 => spak,
      8 => ZLibDecoder(raw: true).convert(spak),
      _ => fail('Nieznana metoda $metoda: $nazwa'),
    });
    expect(dane.length, surowe, reason: nazwa);
    expect(Crc32.of(dane), crc, reason: nazwa);
    expect(wynik.containsKey(nazwa), isFalse, reason: 'powtórka: $nazwa');
    wynik[nazwa] = dane;
  }
  expect(nastepny, poczatekKatalogu);
  return wynik;
}
