import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/core/identity.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/network/client.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';

/// Próba obejścia szyfrowania: napastnik zna publiczny GUID sparowanego
/// urządzenia (leci w discovery i w nagłówkach), ale nie zna klucza sesji.
/// Od sparowanego rozmówcy wolno przyjmować wyłącznie zaszyfrowaną treść —
/// inaczej zielona tarcza obiecywałaby coś, czego nie ma.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory work;
  late AppServices alice;
  late AppServices bob;
  late PeerClient napastnik;
  late DeviceIdentity podszytaAlicja;

  setUp(() async {
    work = Directory.systemTemp.createTempSync('chatt_downgrade');
    alice = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Alicja',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'alice'),
      fileOfferPolicy: acceptAllFileOffers,
    );
    bob = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Bartek',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'bob'),
      fileOfferPolicy: acceptAllFileOffers,
    );

    // Alicja i Bartek parują się kodem.
    final bobAtAlice = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    expect(await alice.startPairing(bobAtAlice!), isNotNull);
    expect(await alice.confirmPairing(bob.identity.guid),
        PairOutcome.accepted);
    expect(await bob.confirmPairing(alice.identity.guid),
        PairOutcome.accepted);

    napastnik = PeerClient();
    // Napastnik podaje się za Alicję: zna jej GUID, nie zna klucza.
    podszytaAlicja = DeviceIdentity(
      guid: alice.identity.guid,
      name: 'Alicja',
      welcomeMessage: '',
      tcpPort: 31337,
    );
  });

  tearDown(() async {
    napastnik.dispose();
    await alice.dispose();
    await bob.dispose();
    work.deleteSync(recursive: true);
  });

  Future<int> messagesAtBob() async {
    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final conversation = await bob.db.ensureConversation(aliceAtBob!.id);
    return (await bob.db.watchMessages(conversation).first).length;
  }

  test('jawna wiadomość podszyta pod sparowanego rozmówcę jest odrzucana',
      () async {
    final before = await messagesAtBob();

    final accepted = await napastnik.sendMessage(
      host: '127.0.0.1',
      port: bob.server.port!,
      payload: messagePacket(
        messageGuid: 'podszycie-1',
        from: podszytaAlicja,
        text: 'PRZELEJ-1000-ZL',
        sentAt: DateTime.now(),
      ),
    );

    expect(accepted.delivered, isFalse, reason: 'serwer ma odmówić');
    expect(await messagesAtBob(), before, reason: 'nic nie doszło do bazy');

    // Adres prawdziwej Alicji nie mógł zostać podmieniony na adres napastnika.
    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    expect(aliceAtBob!.port, isNot(31337));
    expect(aliceAtBob.verified, isTrue);
  });

  test('jawna zapowiedź pliku od sparowanego rozmówcy jest odrzucana',
      () async {
    final reply = await napastnik.offerFile(
      host: '127.0.0.1',
      port: bob.server.port!,
      payload: FileOffer(
        messageGuid: 'podszycie-2',
        from: podszytaAlicja,
        fileName: 'faktura-napastnika.pdf',
        fileSize: 1024,
        sentAt: DateTime.now(),
      ).toJson(),
    );

    expect(reply?.accepted, isNot(true));
  });

  test('jawny transfer nie podmieni pliku zapowiedzianego szyfrem', () async {
    // Alicja zapowiada plik po szyfrowanym kanale i dostaje zgodę.
    final source = File(p.join(work.path, 'umowa.pdf'));
    source.writeAsStringSync('PRAWDZIWA-UMOWA');
    final conversation = await alice.openConversationWith(
        (await alice.db.peerByGuid(bob.identity.guid))!);

    // Napastnik podrzuca swoją treść pod tym samym guid-em wiadomości,
    // jawnym transferem (bez nagłówka o szyfrowaniu).
    final podmiana = File(p.join(work.path, 'podmiana.pdf'));
    podmiana.writeAsStringSync('PODMIENIONA-UMOWA');
    final wciete = await napastnik.sendFile(
      host: '127.0.0.1',
      port: bob.server.port!,
      headers: {
        headerMessageGuid: 'podszycie-3',
        headerFrom: encodeIdentityHeader(podszytaAlicja),
        headerFileName: Uri.encodeComponent('podmiana.pdf'),
        headerFileSize: '${podmiana.lengthSync()}',
        headerSentAt: DateTime.now().toUtc().toIso8601String(),
        headerFileOffset: '0',
      },
      file: podmiana,
    );

    expect(wciete.delivered, isFalse,
        reason: 'jawny transfer od sparowanego = odmowa');
    expect(
      Directory(p.join(work.path, 'bob')).listSync().whereType<File>(),
      isEmpty,
      reason: 'nic nie wylądowało w odebranych',
    );

    // A prawdziwa Alicja dalej wysyła bez przeszkód.
    await alice.sendFile(conversation, source.path);
    final atAlice = (await alice.db.watchMessages(conversation).first).last;
    expect(atAlice.status, MessageStatus.delivered);
  });
}
