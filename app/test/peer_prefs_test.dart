import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/data/db.dart';
import 'package:chatt/services/app_services.dart';

/// Ustawienia trzymane per rozmówca: własna nazwa i przyjmowanie plików bez
/// pytania. Oba są granicą zgody użytkownika, więc pilnujemy ich w bazie,
/// a nie w UI, i sprawdzamy to na żywym transferze.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('własna nazwa i zgoda w bazie', () {
    late ChattDb db;

    setUp(() => db = ChattDb(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<Peer> dodaj() => db.upsertPeer(
          guid: 'g1',
          name: 'DESKTOP-8F2A1C',
          welcomeMessage: '',
          host: '10.0.0.1',
          port: 47780,
        );

    Future<Peer> odczyt() async => (await db.peerByGuid('g1'))!;

    test('bez własnej nazwy pokazujemy tę rozgłaszaną', () async {
      final peer = await dodaj();
      expect(peer.displayName, 'DESKTOP-8F2A1C');
      expect(peer.hasAlias, isFalse);
    });

    test('własna nazwa przykrywa rozgłaszaną, ale jej nie kasuje', () async {
      final peer = await dodaj();
      await db.setPeerAlias(peer.id, 'Laptop Ani');

      final po = await odczyt();
      expect(po.displayName, 'Laptop Ani');
      expect(po.name, 'DESKTOP-8F2A1C',
          reason: 'rozgłaszana zostaje, panel bezpieczeństwa ją pokazuje');
      expect(po.hasAlias, isTrue);
    });

    test('rozmówca może się przemianować, własna nazwa zostaje', () async {
      final peer = await dodaj();
      await db.setPeerAlias(peer.id, 'Laptop Ani');
      // To samo urządzenie odzywa się pod inną nazwą rozgłaszaną.
      await db.upsertPeer(
        guid: 'g1',
        name: 'Coś Zupełnie Innego',
        welcomeMessage: '',
        host: '10.0.0.1',
        port: 47780,
      );

      final po = await odczyt();
      expect(po.displayName, 'Laptop Ani');
      expect(po.name, 'Coś Zupełnie Innego');
    });

    test('pusta i sama spacja kasują własną nazwę', () async {
      final peer = await dodaj();
      await db.setPeerAlias(peer.id, 'Laptop Ani');
      await db.setPeerAlias(peer.id, '   ');

      final po = await odczyt();
      expect(po.alias, isNull);
      expect(po.displayName, 'DESKTOP-8F2A1C');
    });

    test('bez potwierdzonej tożsamości nie da się włączyć zgody na pliki',
        () async {
      final peer = await dodaj();
      final wynik = await db.setPeerAutoAccept(peer.id, true);

      expect(wynik, isFalse, reason: 'baza pilnuje tego, nie ekran');
      expect((await odczyt()).autoAccept, isFalse);
    });

    test('po potwierdzeniu zgoda się włącza', () async {
      final peer = await dodaj();
      await db.setPeerVerified(peer.id, true);

      expect(await db.setPeerAutoAccept(peer.id, true), isTrue);
      expect((await odczyt()).autoAccept, isTrue);
    });

    test('zdjęcie potwierdzenia gasi zgodę na pliki', () async {
      final peer = await dodaj();
      await db.setPeerVerified(peer.id, true);
      await db.setPeerAutoAccept(peer.id, true);

      await db.setPeerVerified(peer.id, false);

      expect((await odczyt()).autoAccept, isFalse,
          reason: 'zgoda dotyczyła potwierdzonej tożsamości, nie nazwy');
    });
  });

  group('przyjmowanie pliku bez pytania', () {
    late Directory work;
    late AppServices alice;
    late AppServices bob;
    late List<PendingFileOffer> pytania;

    setUp(() async {
      work = Directory.systemTemp.createTempSync('chatt_prefs');
      pytania = [];
      alice = await AppServices.start(
        executor: NativeDatabase.memory(),
        portOverride: 0,
        nameOverride: 'Alicja',
        enableDiscovery: false,
        receivedDirOverride: p.join(work.path, 'alice_received'),
        fileOfferPolicy: acceptAllFileOffers,
      );
      bob = await AppServices.start(
        executor: NativeDatabase.memory(),
        portOverride: 0,
        nameOverride: 'Bartek',
        enableDiscovery: false,
        receivedDirOverride: p.join(work.path, 'bob_received'),
        fileOfferPolicy: (offer) async {
          pytania.add(offer);
          return OfferDecision.accept;
        },
      );
    });

    tearDown(() async {
      await alice.dispose();
      await bob.dispose();
      work.deleteSync(recursive: true);
    });

    File plik(String name, int bytes) {
      final random = Random(7);
      final file = File(p.join(work.path, name));
      file.writeAsBytesSync(
          List<int>.generate(bytes, (_) => random.nextInt(256)));
      return file;
    }

    /// Alicja jest u Bartka wpisem w bazie dopiero po pierwszym kontakcie,
    /// więc najpierw wymieniamy wiadomość, a dopiero potem ustawiamy flagi.
    Future<Peer> alicjaUBartka() async {
      final bobAsPeer =
          await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
      final rozmowa = await alice.openConversationWith(bobAsPeer!);
      await alice.sendText(rozmowa, 'cześć');
      return (await bob.db.peerByGuid(alice.identity.guid))!;
    }

    Future<void> wyslijPlik() async {
      final bobAsPeer =
          await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
      final rozmowa = await alice.openConversationWith(bobAsPeer!);
      await alice.sendFile(rozmowa, plik('zdjecie.bin', 32 * 1024).path);
    }

    test('potwierdzony rozmówca ze zgodą: plik wchodzi bez pytania', () async {
      final alicja = await alicjaUBartka();
      await bob.db.setPeerVerified(alicja.id, true);
      await bob.db.setPeerAutoAccept(alicja.id, true);

      await wyslijPlik();

      expect(pytania, isEmpty, reason: 'o to właśnie chodzi w tej zgodzie');
      final rozmowa = await bob.db.ensureConversation(alicja.id);
      final odebrane = (await bob.db.watchMessages(rozmowa).first)
          .where((m) => m.kind == MessageKind.file)
          .toList();
      expect(odebrane, hasLength(1));
      expect(File(odebrane.single.filePath!).lengthSync(), 32 * 1024);
    });

    test('potwierdzony bez zgody: pytanie leci jak zawsze', () async {
      final alicja = await alicjaUBartka();
      await bob.db.setPeerVerified(alicja.id, true);

      await wyslijPlik();

      expect(pytania.map((o) => o.fileName), ['zdjecie.bin']);
    });

    test('sama flaga bez potwierdzenia nie otwiera furtki', () async {
      final alicja = await alicjaUBartka();
      // Flaga wpisana z pominięciem `setPeerAutoAccept`, czyli stan, który
      // mógłby zostać po cofnięciu potwierdzenia jakąś inną drogą.
      await bob.db.setPeerVerified(alicja.id, true);
      await bob.db.setPeerAutoAccept(alicja.id, true);
      await bob.db.setPeerVerified(alicja.id, false);

      await wyslijPlik();

      expect(pytania.map((o) => o.fileName), ['zdjecie.bin'],
          reason: 'bez zielonej tarczy zgoda dotyczyłaby samej nazwy');
    });
  });
}
