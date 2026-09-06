import 'dart:io';

import 'package:chatt/core/secret_store.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/data/db_open.dart';
import 'package:chatt/services/app_services.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

const _sekret = 'TAJNA-TRESC-DO-SZUKANIA';

Future<(String, String)> _fakeIdentity() async => ('a2x1Y3o=', 'guid-testowy');

/// Czy w pliku widać dany napis. Szyfrowana baza ma go nie pokazywać nawet
/// wtedy, gdy leży w niej całą historię.
bool _zawiera(File file, String napis) =>
    String.fromCharCodes(file.readAsBytesSync()).contains(napis);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('build ma SQLite3MultipleCiphers i PRAGMA key naprawdę szyfruje', () {
    final dir = Directory.systemTemp.createTempSync('chatt-szyfr');
    final path = p.join(dir.path, 'proba.db');

    final db = raw.sqlite3.open(path);
    expect(db.select('PRAGMA cipher;'), isNotEmpty,
        reason: 'build bez sqlite3mc, PRAGMA key nic by nie robił');
    db.execute("PRAGMA key = 'haslo';");
    db.execute('CREATE TABLE t (v TEXT);');
    db.execute("INSERT INTO t VALUES ('$_sekret');");
    db.close();

    expect(_zawiera(File(path), _sekret), isFalse);

    final bezKlucza = raw.sqlite3.open(path);
    expect(() => bezKlucza.select('SELECT * FROM t'), throwsA(anything));
    bezKlucza.close();

    final zKluczem = raw.sqlite3.open(path);
    zKluczem.execute("PRAGMA key = 'haslo';");
    expect(zKluczem.select('SELECT v FROM t').single['v'], _sekret);
    zKluczem.close();

    dir.deleteSync(recursive: true);
  });

  test('jawna baza po starszej wersji przepisuje się z historią', () async {
    final dir = Directory.systemTemp.createTempSync('chatt-migracja');
    final file = File(p.join(dir.path, 'chatt.db'));

    final jawna = ChattDb(NativeDatabase(file));
    await jawna.ensureSettings(
      identityFactory: _fakeIdentity,
      defaultNickname: 'Nick sprzed migracji',
      defaultPort: 47780,
    );
    final peer = await jawna.upsertPeer(
      guid: 'guid-rozmowcy',
      name: 'Rozmówca',
      welcomeMessage: '',
      host: '192.168.1.10',
      port: 47780,
    );
    await jawna.setPeerVerified(peer.id, true);
    final rozmowa = await jawna.ensureConversation(peer.id);
    await jawna.insertOutgoing(
      conversationId: rozmowa,
      messageGuid: 'wiadomosc-1',
      body: _sekret,
    );
    await jawna.close();

    expect(_zawiera(file, _sekret), isTrue, reason: 'stara baza jest jawna');

    final klucz = const DatabaseKey(passphrase: 'haslo-testowe', protected: false);
    expect(await migrateToEncrypted(file, klucz), isTrue);
    expect(_zawiera(file, _sekret), isFalse);
    expect(File('${file.path}.enc').existsSync(), isFalse);

    final zaszyfrowana = ChattDb(NativeDatabase(file, setup: setupKey(klucz)));
    final wiadomosci = await zaszyfrowana.select(zaszyfrowana.messages).get();
    expect(wiadomosci.single.body, _sekret);
    final rozmowcy = await zaszyfrowana.select(zaszyfrowana.peers).get();
    expect(rozmowcy.single.guid, 'guid-rozmowcy');
    expect(rozmowcy.single.verified, isTrue,
        reason: 'potwierdzona tożsamość ma przetrwać migrację');
    expect((await zaszyfrowana.getSettings())!.nickname, 'Nick sprzed migracji');
    await zaszyfrowana.close();

    // Drugi start nie ma już czego przepisywać.
    expect(await migrateToEncrypted(file, klucz), isFalse);

    dir.deleteSync(recursive: true);
  });

  test('bez hasła zaszyfrowanej bazy nie da się otworzyć', () async {
    final dir = Directory.systemTemp.createTempSync('chatt-bez-hasla');
    final file = File(p.join(dir.path, 'chatt.db'));

    final klucz = const DatabaseKey(passphrase: 'inne-haslo', protected: false);
    final db = ChattDb(NativeDatabase(file, setup: setupKey(klucz)));
    await db.ensureSettings(
      identityFactory: _fakeIdentity,
      defaultNickname: 'Ja',
      defaultPort: 47780,
    );
    await db.close();

    final bezKlucza = raw.sqlite3.open(file.path);
    expect(() => bezKlucza.select('SELECT * FROM settings'), throwsA(anything));
    bezKlucza.close();

    dir.deleteSync(recursive: true);
  });

  group('klucz bazy', () {
    test('bez schowka systemowego zapisuje się jawnie, ale się nie zmienia',
        () async {
      final dir = Directory.systemTemp.createTempSync('chatt-klucz');
      final pierwszy = await DatabaseKey.load(dir.path);
      expect(pierwszy.protected, isFalse,
          reason: 'w testach nie ma kanału platformy');

      final drugi = await DatabaseKey.load(dir.path);
      expect(drugi.passphrase, pierwszy.passphrase);
      expect(File(DatabaseKey.fileFor(dir.path)).existsSync(), isTrue);

      dir.deleteSync(recursive: true);
    });

    test('ze schowkiem klucz leży na dysku owinięty', () async {
      const kanal = MethodChannel('chatt/sekrety');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      // Udawany schowek: odwracalne przekształcenie wystarczy, żeby sprawdzić,
      // że na dysk trafia co innego niż hasło.
      messenger.setMockMethodCallHandler(kanal, (call) async {
        final dane = (call.arguments as Map)['data'] as Uint8List;
        return Uint8List.fromList(dane.map((b) => b ^ 0x5a).toList());
      });

      final dir = Directory.systemTemp.createTempSync('chatt-klucz-schowek');
      final klucz = await DatabaseKey.load(dir.path);
      expect(klucz.protected, isTrue);

      final naDysku = File(DatabaseKey.fileFor(dir.path)).readAsBytesSync();
      expect(String.fromCharCodes(naDysku).contains(klucz.passphrase), isFalse);

      final ponownie = await DatabaseKey.load(dir.path);
      expect(ponownie.passphrase, klucz.passphrase);
      expect(ponownie.protected, isTrue);

      messenger.setMockMethodCallHandler(kanal, null);
      dir.deleteSync(recursive: true);
    });

    test('schowek, który nie odwija klucza, to błąd, a nie pusta baza',
        () async {
      const kanal = MethodChannel('chatt/sekrety');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(kanal, (call) async {
        final dane = (call.arguments as Map)['data'] as Uint8List;
        return Uint8List.fromList(dane.map((b) => b ^ 0x5a).toList());
      });

      final dir = Directory.systemTemp.createTempSync('chatt-klucz-utracony');
      await DatabaseKey.load(dir.path);

      // Klucz systemowy zniknął (reinstalacja, kopia na inne urządzenie).
      messenger.setMockMethodCallHandler(kanal, (_) async => null);
      // Osobny typ, bo ekran awarii startu tylko przy nim proponuje zaczęcie
      // od nowa: przy każdym innym błędzie historia jest jeszcze do odczytania.
      expect(() => DatabaseKey.load(dir.path),
          throwsA(isA<DatabaseKeyUnavailable>()));

      messenger.setMockMethodCallHandler(kanal, null);
      dir.deleteSync(recursive: true);
    });
  });

  group('historia', () {
    late ChattDb db;
    late int rozmowa;
    late Peer rozmowca;

    setUp(() async {
      db = ChattDb(NativeDatabase.memory());
      rozmowca = await db.upsertPeer(
        guid: 'guid-rozmowcy',
        name: 'Rozmówca',
        welcomeMessage: '',
        host: '192.168.1.10',
        port: 47780,
      );
      await db.setPeerVerified(rozmowca.id, true);
      rozmowa = await db.ensureConversation(rozmowca.id);
    });

    tearDown(() => db.close());

    Future<void> dodaj(String guid, {required Duration temu}) =>
        db.into(db.messages).insert(MessagesCompanion.insert(
              messageGuid: guid,
              conversationId: rozmowa,
              direction: MessageDirection.outgoing,
              status: MessageStatus.delivered,
              body: guid,
              createdAt: DateTime.now().subtract(temu),
            ));

    test('„wyczyść historię" zostawia urządzenia i ich potwierdzenie',
        () async {
      await dodaj('a', temu: Duration.zero);
      await dodaj('b', temu: const Duration(days: 1));

      expect(await db.clearHistory(), 2);
      expect(await db.select(db.messages).get(), isEmpty);
      expect(await db.select(db.conversations).get(), isEmpty);

      final zostali = await db.select(db.peers).get();
      expect(zostali.single.guid, 'guid-rozmowcy');
      expect(zostali.single.verified, isTrue);
    });

    test('kasowanie po czasie zabiera tylko wiadomości sprzed granicy',
        () async {
      await dodaj('swieza', temu: const Duration(days: 2));
      await dodaj('stara', temu: const Duration(days: 40));

      expect(await db.deleteMessagesOlderThan(const Duration(days: 30)), 1);
      final zostaly = await db.select(db.messages).get();
      expect(zostaly.single.messageGuid, 'swieza');
      // Rozmowa zostaje: to nadal rozmowa, tylko bez starych treści.
      expect(await db.select(db.conversations).get(), hasLength(1));
    });

  });

  test('granica wyłączona (0 dni) nie kasuje niczego', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final services = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Ja',
      enableDiscovery: false,
    );
    final rozmowca = await services.db.upsertPeer(
      guid: 'guid-rozmowcy',
      name: 'Rozmówca',
      welcomeMessage: '',
      host: '192.168.1.10',
      port: 47780,
    );
    final rozmowa = await services.db.ensureConversation(rozmowca.id);
    await services.db.into(services.db.messages).insert(
          MessagesCompanion.insert(
            messageGuid: 'bardzo-stara',
            conversationId: rozmowa,
            direction: MessageDirection.outgoing,
            status: MessageStatus.delivered,
            body: 'bardzo stara',
            createdAt: DateTime.now().subtract(const Duration(days: 4000)),
          ),
        );

    expect(await services.applyRetention(0), 0);
    expect(await services.db.select(services.db.messages).get(), hasLength(1));

    expect(await services.applyRetention(30), 1);
    expect(await services.db.select(services.db.messages).get(), isEmpty);

    await services.dispose();
  });
}
