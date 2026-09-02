import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';

/// Parowanie kodem PIN: Alicja pokazuje kod u siebie, Bartek go przepisuje.
/// Zgodny kod oznacza obie strony jako zweryfikowane.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppServices alice;
  late AppServices bob;

  setUp(() async {
    alice = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Alicja',
      enableDiscovery: false,
    );
    bob = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Bartek',
      enableDiscovery: false,
    );
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
  });

  test('zgodny kod weryfikuje obie strony, zły nie zmienia niczego', () async {
    final bobAtAlice = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    expect(bobAtAlice!.verified, isFalse, reason: 'domyślnie nikt nie jest zweryfikowany');

    final pin = await alice.startPairing(bobAtAlice);
    expect(pin, isNotNull);
    expect(pin!.length, 6);
    expect(int.tryParse(pin), isNotNull, reason: 'sześć cyfr do przepisania');

    // U Bartka pojawia się prośba o przepisanie kodu.
    expect(bob.pendingPairings.value, hasLength(1));
    expect(bob.pendingPairings.value.single.peerName, 'Alicja');

    // Pomyłka przy przepisywaniu niczego nie psuje i nie weryfikuje.
    final wrongPin = pin == '000000' ? '111111' : '000000';
    expect(await bob.confirmPairing(alice.identity.guid, wrongPin),
        PairOutcome.wrongCode);
    expect((await bob.db.peerByGuid(alice.identity.guid))!.verified, isFalse);
    expect((await alice.db.peerByGuid(bob.identity.guid))!.verified, isFalse);
    expect(bob.pendingPairings.value, hasLength(1),
        reason: 'prośba zostaje, można spróbować jeszcze raz');

    // Dobry kod: obie strony wiedzą, z kim rozmawiają.
    expect(await bob.confirmPairing(alice.identity.guid, pin),
        PairOutcome.accepted);
    expect((await bob.db.peerByGuid(alice.identity.guid))!.verified, isTrue);
    expect((await alice.db.peerByGuid(bob.identity.guid))!.verified, isTrue,
        reason: 'inicjator też oznacza rozmówcę jako zweryfikowanego');
    expect(bob.pendingPairings.value, isEmpty);
  });

  test('kod działa tylko raz', () async {
    final bobAtAlice = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final pin = (await alice.startPairing(bobAtAlice!))!;
    expect(await bob.confirmPairing(alice.identity.guid, pin),
        PairOutcome.accepted);

    // Powtórka tego samego kodu (np. podsłuchanego) już nie przechodzi.
    await bob.db.setPeerVerified(
        (await bob.db.peerByGuid(alice.identity.guid))!.id, false);
    expect(await bob.confirmPairing(alice.identity.guid, pin),
        isNot(PairOutcome.accepted));
  });

  test('ponowne parowanie jest oznaczone jako podmiana klucza', () async {
    final bobAtAlice = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final pin = (await alice.startPairing(bobAtAlice!))!;
    expect(await bob.confirmPairing(alice.identity.guid, pin),
        PairOutcome.accepted);
    expect(bob.pendingPairings.value, isEmpty);

    // Druga prośba o parowanie z tego samego guid-a. `POST /pair` nie jest
    // uwierzytelniony, więc mógł ją przysłać ktokolwiek pod tą nazwą —
    // użytkownik musi zobaczyć, że to nie jest pierwsze parowanie.
    expect(await alice.startPairing(bobAtAlice), isNotNull);
    expect(bob.pendingPairings.value.single.alreadyPaired, isTrue,
        reason: 'zgoda podmieni klucz sesji, a nie założy nowy');
  });

  test('pierwsze parowanie nie straszy podmianą klucza', () async {
    final bobAtAlice = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    expect(await alice.startPairing(bobAtAlice!), isNotNull);
    expect(bob.pendingPairings.value.single.alreadyPaired, isFalse);
  });

  test('parowanie z niedostępnym urządzeniem zwraca null', () async {
    final bobAtAlice = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    await bob.server.stop();

    expect(await alice.startPairing(bobAtAlice!), isNull);
    expect((await alice.db.peerByGuid(bob.identity.guid))!.verified, isFalse);
  });
}
