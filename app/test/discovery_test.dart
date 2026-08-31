import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
