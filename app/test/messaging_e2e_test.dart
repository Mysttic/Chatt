import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/network/transport.dart';
import 'package:chatt/services/app_services.dart';

/// E2E logiki: dwie pełne instancje aplikacji (bez UI) w jednym procesie,
/// każda z własną bazą i serwerem na osobnym porcie, jak dwa urządzenia.
/// Discovery jest tu wyłączone (ma własny test), parujemy ręcznie po adresie.
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

  test('parowanie po adresie, wymiana wiadomości w obie strony, dedupe', () async {
    // Alicja dodaje Bartka ręcznie (fallback "dodaj po IP").
    final bobAsPeer =
        await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    expect(bobAsPeer, isNotNull);
    expect(bobAsPeer!.name, 'Bartek');

    // Alicja -> Bartek
    final conversationAtAlice = await alice.openConversationWith(bobAsPeer);
    await alice.sendText(conversationAtAlice, 'Cześć Bartek!');

    final atAlice = await alice.db.watchMessages(conversationAtAlice).first;
    expect(atAlice.single.status, MessageStatus.delivered,
        reason: 'ACK od Bartka powinien ustawić delivered');

    // U Bartka: Alicja pojawiła się jako peer, konwersacja i wiadomość istnieją.
    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    expect(aliceAtBob, isNotNull);
    expect(aliceAtBob!.name, 'Alicja');
    expect(aliceAtBob.port, alice.server.port,
        reason: 'port serwera nadawcy przyjeżdża w payloadzie');

    final conversationAtBob = await bob.db.ensureConversation(aliceAtBob.id);
    final atBob = await bob.db.watchMessages(conversationAtBob).first;
    expect(atBob.single.body, 'Cześć Bartek!');
    expect(atBob.single.direction, MessageDirection.incoming);

    // Bartek odpisuje, adres Alicji zna już z jej wiadomości.
    await bob.sendText(conversationAtBob, 'No cześć!');
    final aliceInbox = await alice.db.watchMessages(conversationAtAlice).first;
    expect(aliceInbox, hasLength(2));
    expect(aliceInbox.last.body, 'No cześć!');
    expect(aliceInbox.last.direction, MessageDirection.incoming);

    // Nieprzeczytane u Alicji: dokładnie ta jedna odpowiedź.
    final summary = await alice.db.watchConversationSummaries().first;
    expect(summary.single.unreadCount, 1);

    // Duplikat dostarczenia (retry po zgubionym ACK-u) nie tworzy kopii.
    final bobOutgoing = (await bob.db.watchMessages(conversationAtBob).first)
        .firstWhere((m) => m.direction == MessageDirection.outgoing);
    await bob.retryMessage(bobOutgoing.id);
    final aliceAfterRetry =
        await alice.db.watchMessages(conversationAtAlice).first;
    expect(aliceAfterRetry, hasLength(2), reason: 'dedupe po messageGuid');
  });

  test('odbiorca offline: failed, po powrocie retry dostarcza', () async {
    final bobAsPeer =
        await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final conversation = await alice.openConversationWith(bobAsPeer!);

    // Bartek znika z sieci.
    await bob.server.stop();
    await alice.sendText(conversation, 'Jesteś tam?');
    var messages = await alice.db.watchMessages(conversation).first;
    expect(messages.single.status, MessageStatus.failed);
    expect(await alice.isPeerOnline(bobAsPeer), isFalse);

    // Bartek wraca na TYM SAMYM porcie (u Alicji zapisany jest stary adres).
    final port = await bob.server.start(preferredPort: bobAsPeer.port);
    expect(port, bobAsPeer.port);
    expect(await alice.isPeerOnline(bobAsPeer), isTrue);

    await alice.retryMessage(messages.single.id);
    messages = await alice.db.watchMessages(conversation).first;
    expect(messages.single.status, MessageStatus.delivered);
  });

  test('pod starym adresem odpowiada inny Chatt: to nie jest nasz rozmówca',
      () async {
    final bobAsPeer =
        await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final conversation = await alice.openConversationWith(bobAsPeer!);
    await alice.sendText(conversation, 'Cześć');
    expect((await alice.db.watchMessages(conversation).first).single.status,
        MessageStatus.delivered);

    // Adresy w sieci się przetasowały: pod adresem, który Alicja ma zapisany
    // dla Bartka, stoi teraz Celina.
    final celina = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Celina',
      enableDiscovery: false,
    );
    addTearDown(celina.dispose);
    final przesuniety = await alice.db.upsertPeer(
      guid: bobAsPeer.guid,
      name: bobAsPeer.name,
      welcomeMessage: bobAsPeer.welcomeMessage,
      host: '127.0.0.1',
      port: celina.server.port!,
    );

    expect(await alice.isPeerOnline(przesuniety), isFalse,
        reason: 'odpowiedź Celiny nie jest obecnością Bartka');
    await alice.sendText(conversation, 'Dalej tu jesteś?');
    final messages = await alice.db.watchMessages(conversation).first;
    expect(messages.last.status, MessageStatus.failed,
        reason: 'Celina nie przejmuje rozmowy z Bartkiem');
  });

  test('ręczne dodanie zapisuje adres, pod którym urządzenie odpowiedziało',
      () async {
    // Tunel (emulator za NAT-em, przekierowanie portu na routerze): Bartek
    // jest osiągalny pod innym portem, niż sam rozgłasza. Zapisać trzeba ten
    // osiągalny: inaczej wiadomości polecą w próżnię (albo do nas samych).
    final tunnel = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    tunnel.listen((incoming) async {
      final target = await Socket.connect('127.0.0.1', bob.server.port!);
      target.addStream(incoming).then((_) => target.close()).ignore();
      incoming.addStream(target).then((_) => incoming.close()).ignore();
    });
    addTearDown(() => tunnel.close());

    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', tunnel.port);
    expect(bobAsPeer, isNotNull);
    expect(bobAsPeer!.port, tunnel.port,
        reason: 'liczy się adres, pod którym faktycznie odpowiedział');
    expect(bobAsPeer.port, isNot(bob.server.port));

    final conversation = await alice.openConversationWith(bobAsPeer);
    await alice.sendText(conversation, 'Idzie przez tunel?');
    final sent = (await alice.db.watchMessages(conversation).first).single;
    expect(sent.status, MessageStatus.delivered);
  });

  test('nie rozmawiamy sami ze sobą (pętla na własny adres)', () async {
    // Dodanie własnego adresu nie tworzy rozmówcy...
    expect(await alice.addPeerByAddress('127.0.0.1', alice.server.port!), isNull);

    // ...a wiadomość z własną tożsamością jest odrzucana przez serwer.
    final accepted = await alice.client.sendMessage(
      route: IpRoute('127.0.0.1', alice.server.port!),
      payload: messagePacket(
        messageGuid: 'petla',
        from: alice.identity,
        text: 'sam do siebie',
        sentAt: DateTime.now(),
      ),
    );
    expect(accepted.delivered, isFalse);
    expect(await alice.db.watchPeers().first, isEmpty);
  });

  test('serwer odrzuca śmieci bez wywracania się', () async {
    final ok = await alice.client.sendMessage(
      route: IpRoute('127.0.0.1', bob.server.port!),
      payload: {'nie': 'to co trzeba'},
    );
    expect(ok.delivered, isFalse);
    // Serwer dalej żyje i obsługuje poprawne zapytania.
    expect(await alice.client.fetchInfo(IpRoute('127.0.0.1', bob.server.port!)), isNotNull);
  });
}
