import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/core/identity.dart';
import 'package:chatt/core/remote_input.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/network/client.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/network/transport.dart';
import 'package:chatt/services/app_services.dart';

/// Próba obejścia szyfrowania: napastnik zna publiczny GUID sparowanego
/// urządzenia (leci w discovery i w nagłówkach), ale nie zna klucza sesji.
/// Od sparowanego rozmówcy wolno przyjmować wyłącznie zaszyfrowaną treść:
/// inaczej zielona tarcza obiecywałaby coś, czego nie ma.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory work;
  late AppServices alice;
  late AppServices bob;
  late PeerClient napastnik;
  late DeviceIdentity podszytaAlicja;
  late _Ujscie ujscie;
  late List<PendingRemoteInput> pytaniaOPisanie;

  setUp(() async {
    work = Directory.systemTemp.createTempSync('chatt_downgrade');
    ujscie = _Ujscie();
    pytaniaOPisanie = [];
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
      // Bartek zgodziłby się na każdą prośbę o pisanie: jedyne, co może
      // zatrzymać napastnika, to brak klucza sesji.
      remoteInputPolicy: (prosba) {
        pytaniaOPisanie.add(prosba);
        return acceptAllRemoteInput(prosba);
      },
      remoteInputSink: ujscie,
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
      route: IpRoute('127.0.0.1', bob.server.port!),
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
      route: IpRoute('127.0.0.1', bob.server.port!),
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
      route: IpRoute('127.0.0.1', bob.server.port!),
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

  test('jawna prośba o pisanie i jawna paczka operacji dostają 409',
      () async {
    // U Bartka wszystko otwarte: dodatek, odbiór i zgoda na każdą prośbę.
    await bob.setKeyboardAddon(true);
    expect(await bob.setRemoteInputReceive(true), isTrue);
    final trasa = IpRoute('127.0.0.1', bob.server.port!);

    final prosba = await napastnik.requestInputSession(
      route: trasa,
      payload: InputSessionRequest(
        from: podszytaAlicja,
        op: inputSessionRequest,
        input: 'podszycie-4',
        platform: 'windows',
      ).toJson(),
    );
    expect(prosba.status, 409, reason: 'jawny JSON to brak sesji');
    expect(tryDecodeJsonMap(prosba.body)?['error'], errorNoSession,
        reason: 'jawna odpowiedź mówi wyłącznie „zrób uścisk dłoni"');

    final paczka = await napastnik.sendInput(
      route: trasa,
      payload: RemoteInputPacket(
        from: podszytaAlicja,
        input: 'podszycie-4',
        token: 'dG9rZW4tbmFwYXN0bmlrYQ==',
        seq: 1,
        ops: const [
          RemoteInputOp.insert('PRZELEJ-1000-ZL\n'),
          RemoteInputOp.action(),
        ],
      ).toJson(),
    );
    expect(paczka.status, 409);
    expect(tryDecodeJsonMap(paczka.body)?['error'], errorNoSession);

    expect(pytaniaOPisanie, isEmpty, reason: 'żadna karta zgody');
    expect(bob.pendingRemoteInput.value, isEmpty);
    expect(bob.incomingRemoteInput.value, isNull, reason: 'żadnej zgody');
    expect(ujscie.ops, isEmpty, reason: 'nic nie wpisane');
    expect(ujscie.wywolania, ['setImeEnabled:true'],
        reason: 'ujście słyszało tylko przełącznik dodatku');
  });
}

/// Ujście w pamięci: zapisuje, co by wpisało, i odpowiada stałym celem.
class _Ujscie implements RemoteInputSink {
  final ops = <RemoteInputOp>[];
  final wywolania = <String>[];
  final RemoteInputTarget cel = const RemoteInputTarget(
      active: true,
      field: RemoteInputField.text,
      app: 'com.example.notes',
      appLabel: 'Notatki');

  @override
  bool supported = true;

  @override
  Future<RemoteInputTarget> status() async {
    wywolania.add('status');
    return cel;
  }

  @override
  Future<RemoteInputApplied> apply(List<RemoteInputOp> nowe) async {
    wywolania.add('apply');
    ops.addAll(nowe);
    return (applied: true, target: cel);
  }

  @override
  Future<void> setSession({required bool active, String peerName = ''}) async =>
      wywolania.add('setSession:$active');

  @override
  Future<bool> setImeEnabled(bool on) async {
    wywolania.add('setImeEnabled:$on');
    return true;
  }
}
