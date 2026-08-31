import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late ChattDb db;

  setUp(() => db = ChattDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('ensureSettings tworzy wiersz raz i zachowuje GUID', () async {
    var factoryCalls = 0;
    Future<Setting> ensure() => db.ensureSettings(
          guidFactory: () {
            factoryCalls++;
            return 'guid-test';
          },
          defaultNickname: 'Tester',
          defaultPort: 50000,
        );

    final first = await ensure();
    final second = await ensure();

    expect(first.deviceGuid, 'guid-test');
    expect(second.deviceGuid, 'guid-test');
    expect(factoryCalls, 1);
    expect(second.nickname, 'Tester');
    expect(second.tcpPort, 50000);
  });

  test('upsertPeer aktualizuje adres po guid, pusty host nie nadpisuje', () async {
    final created = await db.upsertPeer(
        guid: 'g1', name: 'Ala', welcomeMessage: 'hej', host: '10.0.0.1', port: 1111);
    final updated = await db.upsertPeer(
        guid: 'g1', name: 'Alicja', welcomeMessage: '', host: '10.0.0.9', port: 2222);
    final blankHost = await db.upsertPeer(
        guid: 'g1', name: 'Alicja', welcomeMessage: '', host: '', port: 2222);

    expect(updated.id, created.id);
    expect(updated.name, 'Alicja');
    expect(updated.host, '10.0.0.9');
    expect(blankHost.host, '10.0.0.9');
  });

  test('wiadomości: dedupe po messageGuid i liczenie nieprzeczytanych', () async {
    final peer = await db.upsertPeer(
        guid: 'g2', name: 'Bartek', welcomeMessage: '', host: '10.0.0.2', port: 1);
    final conv = await db.ensureConversation(peer.id);

    expect(await db.ensureConversation(peer.id), conv,
        reason: 'jedna konwersacja na rozmówcę');

    final inserted = await db.insertIncoming(
        conversationId: conv, messageGuid: 'm1', body: 'siema', sentAt: DateTime.now());
    final duplicate = await db.insertIncoming(
        conversationId: conv, messageGuid: 'm1', body: 'siema', sentAt: DateTime.now());
    await db.insertOutgoing(conversationId: conv, messageGuid: 'm2', body: 'no hej');

    expect(inserted, isTrue);
    expect(duplicate, isFalse);

    final summaries = await db.watchConversationSummaries().first;
    expect(summaries, hasLength(1));
    expect(summaries.single.unreadCount, 1, reason: 'tylko przychodzące liczą się jako nieprzeczytane');
    expect(summaries.single.lastBody, 'no hej');
    expect(summaries.single.peer.name, 'Bartek');

    await db.markConversationRead(conv);
    final afterRead = await db.watchConversationSummaries().first;
    expect(afterRead.single.unreadCount, 0);

    final messages = await db.watchMessages(conv).first;
    expect(messages, hasLength(2));
    expect(messages.first.body, 'siema');
  });

  test('status wiadomości: pending -> failed -> delivered', () async {
    final peer = await db.upsertPeer(
        guid: 'g3', name: 'C', welcomeMessage: '', host: 'x', port: 1);
    final conv = await db.ensureConversation(peer.id);
    final id = await db.insertOutgoing(
        conversationId: conv, messageGuid: 'm3', body: 'test');

    expect((await db.messageById(id))!.status, MessageStatus.pending);

    await db.setMessageStatus(id, MessageStatus.failed);
    expect((await db.messageById(id))!.status, MessageStatus.failed);
    expect((await db.messageById(id))!.deliveredAt, isNull);

    await db.setMessageStatus(id, MessageStatus.delivered);
    final delivered = await db.messageById(id);
    expect(delivered!.status, MessageStatus.delivered);
    expect(delivered.deliveredAt, isNotNull);
  });
}
