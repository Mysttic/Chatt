import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';

/// Szyfrowanie ruchu między sparowanymi urządzeniami. Cały ruch od Alicji do
/// Bartka przechodzi przez podsłuchiwane łącze, więc testy patrzą dokładnie
/// na to, co widzi ktoś siedzący w sieci.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory work;
  late AppServices alice;
  late AppServices bob;
  late ServerSocket wire;
  late List<int> sniffed;

  /// Po ilu bajtach łącze ma paść (0 = przepuszcza wszystko).
  late int cutAfter;

  setUp(() async {
    work = Directory.systemTemp.createTempSync('chatt_enc');
    sniffed = [];
    cutAfter = 0;
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

    // Łącze Alicja -> Bartek z kopią wszystkiego, co przez nie leci.
    wire = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    wire.listen((client) async {
      final Socket target;
      try {
        target = await Socket.connect('127.0.0.1', bob.server.port!);
      } catch (_) {
        client.destroy(); // Bartek nie zyje: nie trzymamy Alicji w zawieszeniu
        return;
      }
      var forwarded = 0;
      client.listen(
        (chunk) {
          sniffed.addAll(chunk);
          forwarded += chunk.length;
          if (cutAfter > 0 && forwarded > cutAfter) {
            client.destroy();
            target.destroy();
            return;
          }
          target.add(chunk);
        },
        onDone: () => target.close(),
        onError: (Object _) => target.destroy(),
      );
      target.listen(client.add,
          onDone: () => client.close(), onError: (Object _) => client.destroy());
    });
  });

  tearDown(() async {
    await wire.close();
    await alice.dispose();
    await bob.dispose();
    work.deleteSync(recursive: true);
  });

  String podsluch() => utf8.decode(sniffed, allowMalformed: true);

  /// Parowanie po podsłuchiwanym łączu. Zwraca rozmówcę Alicji.
  Future<Peer> pair() async {
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', wire.port);
    final pin = await alice.startPairing(bobAsPeer!);
    expect(pin, isNotNull);
    expect(podsluch().contains(pin!), isFalse,
        reason: 'kod parowania nie ma prawa iść przez sieć');
    expect(await bob.confirmPairing(alice.identity.guid, pin),
        PairOutcome.accepted);

    // Bartek odpowiada wprost do Alicji, wiec ta zapisuje sobie jego
    // prawdziwy adres. Do testu wracamy na podsluchiwane lacze.
    await alice.db.upsertPeer(
      guid: bob.identity.guid,
      name: 'Bartek',
      welcomeMessage: '',
      host: '127.0.0.1',
      port: wire.port,
    );
    return (await alice.db.peerByGuid(bob.identity.guid))!;
  }

  test('sparowani: treść wiadomości nie leci jawnym tekstem', () async {
    final bobAsPeer = await pair();
    expect(bobAsPeer.sessionKey, isNotNull, reason: 'klucz zapisany po parowaniu');

    sniffed.clear();
    final conversation = await alice.openConversationWith(bobAsPeer);
    await alice.sendText(conversation, 'TAJNE-HASLO-DO-SEJFU');

    expect(podsluch().contains('TAJNE-HASLO-DO-SEJFU'), isFalse,
        reason: 'w sieci ma być szyfrogram');
    expect(podsluch().contains('"enc":1'), isTrue, reason: 'koperta');

    // A u Bartka wiadomość jest normalnie czytelna.
    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    final atBob = await bob.db.watchMessages(convAtBob).first;
    expect(atBob.last.body, 'TAJNE-HASLO-DO-SEJFU');
    expect((await alice.db.watchMessages(conversation).first).last.status,
        MessageStatus.delivered);
  });

  test('niesparowani: ruch leci po staremu, jawnym tekstem', () async {
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', wire.port);
    final conversation = await alice.openConversationWith(bobAsPeer!);
    await alice.sendText(conversation, 'JAWNA-TRESC');

    expect(podsluch().contains('JAWNA-TRESC'), isTrue,
        reason: 'bez parowania nie ma czym szyfrować — i tak ma dojść');
    expect((await alice.db.watchMessages(conversation).first).last.status,
        MessageStatus.delivered);
  });

  test('sparowani: plik jedzie zaszyfrowany i składa się bajt w bajt',
      () async {
    final bobAsPeer = await pair();
    final conversation = await alice.openConversationWith(bobAsPeer);

    // Rozpoznawalny wzorzec: gdyby plik szedł jawnie, znajdziemy go w podsłuchu.
    final source = File(p.join(work.path, 'tajny-raport.txt'));
    source.writeAsStringSync('ZAWARTOSC-PLIKU-DO-ZNALEZIENIA\n' * 4000);
    sniffed.clear();

    await alice.sendFile(conversation, source.path);

    expect(podsluch().contains('ZAWARTOSC-PLIKU-DO-ZNALEZIENIA'), isFalse,
        reason: 'treść pliku ma być zaszyfrowana');
    expect(podsluch().contains('tajny-raport.txt'), isFalse,
        reason: 'nazwa pliku siedzi w zaszyfrowanej zapowiedzi, nie w nagłówku');

    final atAlice = (await alice.db.watchMessages(conversation).first).last;
    expect(atAlice.status, MessageStatus.delivered);

    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    final atBob = (await bob.db.watchMessages(convAtBob).first).last;
    expect(atBob.fileName, 'tajny-raport.txt',
        reason: 'prawdziwa nazwa przyszła w zapowiedzi');
    expect(File(atBob.filePath!).readAsBytesSync(), source.readAsBytesSync(),
        reason: 'po odszyfrowaniu plik musi być identyczny');
  });

  test('sparowani: wznowienie zaszyfrowanego pliku dosyła tylko resztę',
      () async {
    final bobAsPeer = await pair();
    final conversation = await alice.openConversationWith(bobAsPeer);

    final source = File(p.join(work.path, 'duzy.bin'));
    source.writeAsBytesSync(
        List<int>.generate(900 * 1024, (i) => (i * 7 + 11) % 256));

    // Łącze pada w połowie transferu.
    cutAfter = 300 * 1024;
    await alice.sendFile(conversation, source.path);
    var message = (await alice.db.watchMessages(conversation).first).last;
    expect(message.status, MessageStatus.failed);

    // U Bartka została zaszyfrowana część pliku.
    final parts = Directory(p.join(work.path, 'bob', '.incomplete'))
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.part'))
        .toList();
    expect(parts, hasLength(1));
    final partial = parts.single.lengthSync();
    expect(partial, greaterThan(0));
    expect(partial, lessThan(source.lengthSync()));

    // Sieć wraca: ponowienie ma dołożyć resztę, nie wysłać wszystkiego od nowa.
    cutAfter = 0;
    await alice.retryMessage(message.id);

    message = (await alice.db.watchMessages(conversation).first).last;
    expect(message.status, MessageStatus.delivered);

    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    final atBob = (await bob.db.watchMessages(convAtBob).first).last;
    expect(File(atBob.filePath!).readAsBytesSync(), source.readAsBytesSync(),
        reason: 'po odszyfrowaniu i sklejeniu plik musi być identyczny');
  });
}
