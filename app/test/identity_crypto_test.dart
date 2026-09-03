import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/crypto.dart';
import 'package:chatt/services/app_services.dart';

/// Fundament wydania 0.2.0: tożsamość liczona z klucza i uścisk dłoni,
/// z którego wychodzi klucz ważny tylko na jedną sesję.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('guid liczy się z klucza publicznego i jest powtarzalny', () async {
    final para = await ChattCrypto.newKeyPair();
    final klucz = await ChattCrypto.publicKeyOf(para);

    final guid = ChattCrypto.guidFromPublicKey(klucz);
    expect(ChattCrypto.guidFromPublicKey(klucz), guid,
        reason: 'ten sam klucz zawsze daje ten sam identyfikator');
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(guid),
      isTrue,
      reason: 'kształt zostaje UUID-owy, żeby nic w bazie nie pękło',
    );

    final inny = await ChattCrypto.publicKeyOf(await ChattCrypto.newKeyPair());
    expect(ChattCrypto.guidFromPublicKey(inny), isNot(guid));
  });

  test('tożsamość przeżywa zapis i odczyt klucza prywatnego', () async {
    final para = await ChattCrypto.newKeyPair();
    final prywatny = await ChattCrypto.privateKeyOf(para);
    final publiczny = await ChattCrypto.publicKeyOf(para);

    final odtworzona = await ChattCrypto.identityKeyPair(prywatny);
    expect(await ChattCrypto.publicKeyOf(odtworzona), publiczny,
        reason: 'po restarcie aplikacji urządzenie ma być tym samym urządzeniem');
  });

  test('odcisk klucza to pięć grup po cztery cyfry', () async {
    final klucz = await ChattCrypto.publicKeyOf(await ChattCrypto.newKeyPair());
    final odcisk = ChattCrypto.fingerprint(klucz);
    expect(RegExp(r'^(\d{4} ){4}\d{4}$').hasMatch(odcisk), isTrue);
    expect(ChattCrypto.fingerprint(klucz), odcisk);
  });

  test('obie strony wyliczają ten sam klucz sesji', () async {
    final statyczneA = await ChattCrypto.newKeyPair();
    final statyczneB = await ChattCrypto.newKeyPair();
    final efemeryczneA = await ChattCrypto.newKeyPair();
    final efemeryczneB = await ChattCrypto.newKeyPair();

    final pubStatA = await ChattCrypto.publicKeyOf(statyczneA);
    final pubStatB = await ChattCrypto.publicKeyOf(statyczneB);
    final pubEfeA = await ChattCrypto.publicKeyOf(efemeryczneA);
    final pubEfeB = await ChattCrypto.publicKeyOf(efemeryczneB);

    Future<List<int>> policz({required bool inicjator}) =>
        ChattCrypto.sessionKey(
          myStatic: inicjator ? statyczneA : statyczneB,
          myEphemeral: inicjator ? efemeryczneA : efemeryczneB,
          theirStatic: inicjator ? pubStatB : pubStatA,
          theirEphemeral: inicjator ? pubEfeB : pubEfeA,
          initiator: inicjator,
          initiatorStatic: pubStatA,
          responderStatic: pubStatB,
          initiatorEphemeral: pubEfeA,
          responderEphemeral: pubEfeB,
        );

    final uA = await policz(inicjator: true);
    final uB = await policz(inicjator: false);
    expect(uA, uB, reason: 'inaczej nic by się nie odszyfrowało');
    expect(uA.length, 32);
  });

  test('inne klucze efemeryczne dają inny klucz sesji', () async {
    final statyczneA = await ChattCrypto.newKeyPair();
    final statyczneB = await ChattCrypto.newKeyPair();
    final pubStatA = await ChattCrypto.publicKeyOf(statyczneA);
    final pubStatB = await ChattCrypto.publicKeyOf(statyczneB);

    Future<List<int>> sesja() async {
      final efeA = await ChattCrypto.newKeyPair();
      final efeB = await ChattCrypto.newKeyPair();
      return ChattCrypto.sessionKey(
        myStatic: statyczneA,
        myEphemeral: efeA,
        theirStatic: pubStatB,
        theirEphemeral: await ChattCrypto.publicKeyOf(efeB),
        initiator: true,
        initiatorStatic: pubStatA,
        responderStatic: pubStatB,
        initiatorEphemeral: await ChattCrypto.publicKeyOf(efeA),
        responderEphemeral: await ChattCrypto.publicKeyOf(efeB),
      );
    }

    // To jest właśnie forward secrecy: klucze statyczne te same, a klucz
    // sesji inny — po skasowaniu efemerycznych nagranej sesji nie da się
    // odtworzyć nawet znając tożsamości obu stron.
    expect(await sesja(), isNot(await sesja()));
  });

  test('podmieniony klucz statyczny psuje uzgodnienie', () async {
    final statyczneA = await ChattCrypto.newKeyPair();
    final statyczneB = await ChattCrypto.newKeyPair();
    final napastnik = await ChattCrypto.newKeyPair();
    final efeA = await ChattCrypto.newKeyPair();
    final efeB = await ChattCrypto.newKeyPair();

    final pubStatA = await ChattCrypto.publicKeyOf(statyczneA);
    final pubStatB = await ChattCrypto.publicKeyOf(statyczneB);
    final pubEfeA = await ChattCrypto.publicKeyOf(efeA);
    final pubEfeB = await ChattCrypto.publicKeyOf(efeB);

    final uczciwy = await ChattCrypto.sessionKey(
      myStatic: statyczneA,
      myEphemeral: efeA,
      theirStatic: pubStatB,
      theirEphemeral: pubEfeB,
      initiator: true,
      initiatorStatic: pubStatA,
      responderStatic: pubStatB,
      initiatorEphemeral: pubEfeA,
      responderEphemeral: pubEfeB,
    );

    // Napastnik zna klucze publiczne, ale nie ma klucza prywatnego Bartka.
    final podszyty = await ChattCrypto.sessionKey(
      myStatic: napastnik,
      myEphemeral: efeB,
      theirStatic: pubStatA,
      theirEphemeral: pubEfeA,
      initiator: false,
      initiatorStatic: pubStatA,
      responderStatic: pubStatB,
      initiatorEphemeral: pubEfeA,
      responderEphemeral: pubEfeB,
    );
    expect(podszyty, isNot(uczciwy));
  });

  test('klucz pliku wisi na kluczu sesji i guidzie wiadomości', () async {
    final sesja = List<int>.generate(32, (i) => i);
    final a = await ChattCrypto.fileKey(sessionKey: sesja, messageGuid: 'm-1');
    final b = await ChattCrypto.fileKey(sessionKey: sesja, messageGuid: 'm-2');
    final c = await ChattCrypto.fileKey(
        sessionKey: List<int>.generate(32, (i) => i + 1), messageGuid: 'm-1');

    expect(a.length, 32);
    expect(a, isNot(b), reason: 'dwa pliki w tej samej sesji, dwa klucze');
    expect(a, isNot(c), reason: 'inna sesja, inny klucz');
    expect(await ChattCrypto.fileKey(sessionKey: sesja, messageGuid: 'm-1'), a,
        reason: 'wznowienie musi odtworzyć ten sam klucz');
  });

  test('urządzenie rozgłasza klucz, a jego guid z niego wynika', () async {
    final alice = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Alicja',
      enableDiscovery: false,
    );
    final bob = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Bartek',
      enableDiscovery: false,
    );
    addTearDown(() async {
      await alice.dispose();
      await bob.dispose();
    });

    expect(alice.identity.hasKey, isTrue);
    expect(alice.identity.guid,
        ChattCrypto.guidFromPublicKey(alice.identity.publicKey));

    // Klucz musi dojść przez sieć, bo z niego liczy się pierwsza sesja.
    final bobUAlicji =
        await alice.client.fetchInfo('127.0.0.1', bob.server.port!);
    expect(bobUAlicji, isNotNull);
    expect(bobUAlicji!.publicKey, bob.identity.publicKey);
    expect(ChattCrypto.guidFromPublicKey(bobUAlicji.publicKey),
        bobUAlicji.guid,
        reason: 'identyfikator ma wynikać z klucza, a nie być obok niego');
  });
}
