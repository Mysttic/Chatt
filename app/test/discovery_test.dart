import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/services/app_services.dart';

Future<void> eventually(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String reason = 'warunek niespełniony w czasie',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail(reason);
}

/// Dwie instancje z włączonym discovery na wspólnym porcie UDP (reusePort).
/// Jeden skan Alicji ma nauczyć OBIE strony nawzajem o swoim istnieniu.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('skan znajduje drugą instancję i uczy ją o skanującym', () async {
    final alice = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Alicja',
    );
    final bob = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Bartek',
    );
    addTearDown(() async {
      await alice.dispose();
      await bob.dispose();
    });

    // W kontenerze CI mogą chodzić równolegle inne testy na tym samym porcie
    // discovery — dlatego filtrujemy wyniki po GUID-ach, nie po liczbie.
    final found = await alice.scan();
    expect(found.map((p) => p.guid), contains(bob.identity.guid));
    expect(found.map((p) => p.guid), isNot(contains(alice.identity.guid)),
        reason: 'własne odpowiedzi są ignorowane');

    final bobAtAlice = await alice.db.peerByGuid(bob.identity.guid);
    expect(bobAtAlice, isNotNull, reason: 'znaleziony trafia do bazy');
    expect(bobAtAlice!.port, bob.server.port);

    // Zapytanie discovery niosło tożsamość Alicji -> Bartek też ją zna.
    await eventually(
      () async => (await bob.db.peerByGuid(alice.identity.guid)) != null,
      reason: 'responder Bartka powinien zapisać skanującą Alicję',
    );
    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    expect(aliceAtBob!.name, 'Alicja');
    expect(aliceAtBob.port, alice.server.port);

    // Adres z discovery jest od razu użyteczny: Alicja pisze do Bartka.
    final conversation = await alice.openConversationWith(bobAtAlice);
    await alice.sendText(conversation, 'Znalazłam Cię!');
    await eventually(() async {
      final peers = await bob.db.watchPeers().first;
      if (peers.isEmpty) return false;
      final conv = await bob.db.ensureConversation(aliceAtBob.id);
      final messages = await bob.db.watchMessages(conv).first;
      return messages.any((m) => m.body == 'Znalazłam Cię!');
    }, reason: 'wiadomość po discovery powinna dojść');
  });

  test('od sparowanego przyjmujemy tylko podpisaną odpowiedź', () async {
    final alice = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Alicja',
    );
    final bob = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Bartek',
    );
    addTearDown(() async {
      await alice.dispose();
      await bob.dispose();
    });

    // Sam kontakt wystarczy: klucz rozmówcy przypinamy przy pierwszej sesji,
    // a od tej chwili wymagamy podpisanych odpowiedzi.
    final bobAtAlice = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final rozmowa = await alice.openConversationWith(bobAtAlice!);
    await alice.sendText(rozmowa, 'cześć');

    expect((await alice.scan()).map((p) => p.guid), contains(bob.identity.guid),
        reason: 'znajomy podpisuje odpowiedź kluczem z uzgodnienia statycznych');

    // Podmieniamy u Alicji przypięty klucz Bartka. Od tej chwili jego podpis
    // przestaje pasować — dokładnie tak wygląda ktoś, kto zna sam GUID
    // i odpowiada spod swojego adresu, nie mając klucza prywatnego.
    await alice.db.setPeerKey(
      (await alice.db.peerByGuid(bob.identity.guid))!.id,
      base64Encode(List<int>.filled(32, 7)),
    );

    expect((await alice.scan()).map((p) => p.guid),
        isNot(contains(bob.identity.guid)),
        reason: 'odpowiedź bez pasującego podpisu wypada z wyniku skanu');
  });

  test('rozmówca ze zmienionym adresem jest odnajdywany po GUID', () async {
    final alice = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Alicja',
    );
    final bob = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Bartek',
    );
    addTearDown(() async {
      await alice.dispose();
      await bob.dispose();
    });

    // Alicja ma zapisany nieaktualny adres Bartka — tak wygląda sytuacja po
    // restarcie routera, gdy DHCP rozda adresy na nowo. GUID się nie zmienia.
    await alice.db.upsertPeer(
      guid: bob.identity.guid,
      name: 'Bartek',
      welcomeMessage: '',
      host: '127.0.0.1',
      port: 9, // port, na którym na pewno nikt nie słucha
    );
    final stale = (await alice.db.peerByGuid(bob.identity.guid))!;
    final conversation = await alice.openConversationWith(stale);

    await alice.sendText(conversation, 'Zmieniłeś adres?');

    final message = (await alice.db.watchMessages(conversation).first).single;
    expect(message.status, MessageStatus.delivered,
        reason: 'po nieudanej próbie skan po GUID powinien znaleźć nowy adres');

    final updated = (await alice.db.peerByGuid(bob.identity.guid))!;
    expect(updated.port, bob.server.port, reason: 'adres zaktualizowany w bazie');
  });
}
