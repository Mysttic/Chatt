import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/crypto.dart';
import 'package:chatt/core/identity.dart';
import 'package:chatt/core/pair_link.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';

/// Parowanie przez porównanie kodu: uzgodnienie leci pod spodem, a obie
/// strony dostają ten sam sześciocyfrowy kod do pokazania na ekranie.
/// Klucz zapisujemy dopiero, gdy oba końce powiedzą „zgadza się".
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

  test('obie strony widzą ten sam kod, zgoda obu weryfikuje', () async {
    final bobAtAlice = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    expect(bobAtAlice!.verified, isFalse,
        reason: 'domyślnie nikt nie jest zweryfikowany');

    final code = await alice.startPairing(bobAtAlice);
    expect(code, isNotNull);
    expect(code!.length, pairingCodeDigits);
    expect(int.tryParse(code), isNotNull, reason: 'same cyfry do porównania');

    // Kod widać po obu stronach i jest ten sam — to jest cały dowód, że
    // nikt nie siedzi w środku uzgodnienia.
    expect(alice.pendingPairings.value.single.code, code);
    expect(bob.pendingPairings.value.single.code, code,
        reason: 'obie strony liczą kod z tego samego sekretu');
    expect(bob.pendingPairings.value.single.peerName, 'Alicja');

    // Jedna zgoda nie wystarcza.
    expect(await alice.confirmPairing(bob.identity.guid), PairOutcome.accepted);
    expect((await alice.db.peerByGuid(bob.identity.guid))!.verified, isFalse,
        reason: 'druga strona jeszcze nie potwierdziła');
    expect((await bob.db.peerByGuid(alice.identity.guid))!.verified, isFalse);

    // Druga zgoda domyka parowanie po obu stronach.
    expect(await bob.confirmPairing(alice.identity.guid), PairOutcome.accepted);
    expect((await bob.db.peerByGuid(alice.identity.guid))!.verified, isTrue);
    expect((await alice.db.peerByGuid(bob.identity.guid))!.verified, isTrue);
    expect(bob.pendingPairings.value, isEmpty);
    expect(alice.pendingPairings.value, isEmpty);

    // Klucz sesji też musi być ten sam, inaczej ruch by się nie odszyfrował.
    expect((await alice.db.peerByGuid(bob.identity.guid))!.sessionKey,
        (await bob.db.peerByGuid(alice.identity.guid))!.sessionKey);
  });

  test('„nie zgadza się" po jednej stronie zrywa parowanie po obu', () async {
    final bobAtAlice = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    expect(await alice.startPairing(bobAtAlice!), isNotNull);

    await bob.cancelPairing(alice.identity.guid);
    expect(bob.pendingPairings.value, isEmpty);
    expect(alice.pendingPairings.value, isEmpty,
        reason: 'inicjator nie może zostać z wiszącą kartą');

    expect(await alice.confirmPairing(bob.identity.guid),
        PairOutcome.unreachable,
        reason: 'nie ma już czego potwierdzać');
    expect((await alice.db.peerByGuid(bob.identity.guid))!.verified, isFalse);
    expect((await bob.db.peerByGuid(alice.identity.guid))!.verified, isFalse);
  });

  test('klucz niezgodny ze zobowiązaniem jest odrzucany', () async {
    final bobAtAlice = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);

    // Ręcznie odgrywamy inicjatora: zobowiązujemy się do jednego klucza,
    // a odsłaniamy inny. Tak wyglądałby napastnik dobierający klucze pod kod.
    final uczciwy = await ChattCrypto.newKeyPair();
    final podmieniony = await ChattCrypto.newKeyPair();

    final commit = await alice.client.pair(
      host: '127.0.0.1',
      port: bob.server.port!,
      payload: PairMessage(
        action: pairCommit,
        from: alice.identity,
        commit: ChattCrypto.commitment(
            await ChattCrypto.publicKeyOf(uczciwy)),
      ).toJson(),
    );
    expect(commit.accepted, isTrue);

    final reveal = await alice.client.pair(
      host: '127.0.0.1',
      port: bob.server.port!,
      payload: PairMessage(
        action: pairReveal,
        from: alice.identity,
        publicKey: base64Encode(await ChattCrypto.publicKeyOf(podmieniony)),
      ).toJson(),
    );
    expect(reveal.outcome, PairOutcome.rejected);
    expect(bob.pendingPairings.value, isEmpty,
        reason: 'użytkownikowi nie pokazujemy kodu z podmienionego klucza');
    expect((await bob.db.peerByGuid(alice.identity.guid))!.verified, isFalse);
    expect(bobAtAlice, isNotNull);
  });

  test('ponowne parowanie jest oznaczone jako podmiana klucza', () async {
    final bobAtAlice = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    expect(await alice.startPairing(bobAtAlice!), isNotNull);
    await alice.confirmPairing(bob.identity.guid);
    await bob.confirmPairing(alice.identity.guid);
    expect((await bob.db.peerByGuid(alice.identity.guid))!.verified, isTrue);

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

  test('zeskanowanie kodu potwierdza od razu u skanującego', () async {
    final kod = PairLink.encode(
        identity: bob.identity, address: '127.0.0.1');

    final peer = await alice.pairByScan(PairLink.decode(kod)!);
    expect(peer, isNotNull);
    expect(peer!.verified, isTrue,
        reason: 'skanujący widział tamten ekran, więc ma pewność');
    expect(peer.publicKey, isNotNull, reason: 'klucz przypięty z kodu');

    // U Bartka pojawia się pytanie, bo kod z ekranu mógł zobaczyć ktoś inny.
    expect(bob.pendingPairings.value.single.fromScan, isTrue);
    expect((await bob.db.peerByGuid(alice.identity.guid))!.verified, isFalse,
        reason: 'dopóki nie potwierdzi, tarcza u niego jest szara');

    expect(await bob.confirmPairing(alice.identity.guid), PairOutcome.accepted);
    expect((await bob.db.peerByGuid(alice.identity.guid))!.verified, isTrue);
    expect(bob.pendingPairings.value, isEmpty);
  });

  test('kod z cudzym kluczem pod tym adresem jest odrzucany', () async {
    // Napastnik pokazuje kod ze swoim kluczem, ale adresem Bartka: liczy na
    // to, że skanujący przypnie jego klucz do rozmowy z Bartkiem.
    final obcy = await ChattCrypto.newKeyPair();
    final podszyty = DeviceIdentity(
      guid: ChattCrypto.guidFromPublicKey(await ChattCrypto.publicKeyOf(obcy)),
      name: 'Bartek',
      welcomeMessage: '',
      tcpPort: bob.server.port!,
      publicKey: await ChattCrypto.publicKeyOf(obcy),
    );
    final kod = PairLink.encode(identity: podszyty, address: '127.0.0.1');

    expect(await alice.pairByScan(PairLink.decode(kod)!), isNull,
        reason: 'pod tym adresem odpowiada urządzenie z innym kluczem');
    expect(await alice.db.peerByGuid(podszyty.guid), isNull);
  });

  test('parowanie z niedostępnym urządzeniem zwraca null', () async {
    final bobAtAlice = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    await bob.server.stop();

    expect(await alice.startPairing(bobAtAlice!), isNull);
    expect((await alice.db.peerByGuid(bob.identity.guid))!.verified, isFalse);
  });
}
