import 'package:drift/drift.dart';

import '../network/protocol.dart';

part 'db.g.dart';

/// Ustawienia lokalnej instancji — zawsze dokładnie jeden wiersz (id = 1).
class Settings extends Table {
  IntColumn get id => integer()();
  TextColumn get deviceGuid => text()();
  TextColumn get nickname => text()();
  TextColumn get welcomeMessage => text().withDefault(const Constant(''))();

  /// Preferowany port serwera. Faktyczny port może być inny, gdy ten jest
  /// zajęty — patrz DeviceIdentity.tcpPort.
  IntColumn get tcpPort => integer().withDefault(const Constant(defaultTcpPort))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Znane urządzenia (rozmówcy). Klucz logiczny to [guid] — host i port są
/// tylko ostatnim znanym adresem i są nadpisywane przy każdym kontakcie.
class Peers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get guid => text().unique()();
  TextColumn get name => text()();
  TextColumn get welcomeMessage => text().withDefault(const Constant(''))();
  TextColumn get host => text()();
  IntColumn get port => integer()();
  BoolColumn get verified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get firstSeen => dateTime()();
  DateTimeColumn get lastSeen => dateTime()();
}

/// Jedna konwersacja na rozmówcę (MVP; grupy kiedyś wymuszą zmianę).
class Conversations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get peerId => integer().references(Peers, #id).unique()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

enum MessageDirection { outgoing, incoming }

enum MessageStatus { pending, delivered, failed }

enum MessageKind { text, file }

class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Globalny identyfikator wiadomości — dzięki UNIQUE ponowne dostarczenie
  /// tej samej wiadomości (retry po zgubionym ACK-u) nie tworzy duplikatu.
  TextColumn get messageGuid => text().unique()();
  IntColumn get conversationId => integer().references(Conversations, #id)();
  IntColumn get direction => intEnum<MessageDirection>()();
  IntColumn get status => intEnum<MessageStatus>()();
  IntColumn get kind =>
      intEnum<MessageKind>().withDefault(Constant(MessageKind.text.index))();
  TextColumn get body => text()();

  /// Pola pliku (kind == file). [filePath]: u nadawcy ścieżka źródłowa,
  /// u odbiorcy miejsce zapisu.
  TextColumn get fileName => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  TextColumn get filePath => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();
}

/// Wiersz listy konwersacji: rozmówca + ostatnia wiadomość + nieprzeczytane.
class ConversationSummary {
  final int conversationId;
  final Peer peer;
  final String? lastBody;
  final DateTime? lastAt;
  final int unreadCount;

  const ConversationSummary({
    required this.conversationId,
    required this.peer,
    required this.lastBody,
    required this.lastAt,
    required this.unreadCount,
  });
}

@DriftDatabase(tables: [Settings, Peers, Conversations, Messages])
class ChattDb extends _$ChattDb {
  ChattDb(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: wiadomości-pliki
            await m.addColumn(messages, messages.kind);
            await m.addColumn(messages, messages.fileName);
            await m.addColumn(messages, messages.fileSize);
            await m.addColumn(messages, messages.filePath);
          }
        },
      );

  // --- Ustawienia -----------------------------------------------------------

  Future<Setting?> getSettings() =>
      (select(settings)..where((s) => s.id.equals(1))).getSingleOrNull();

  Stream<Setting> watchSettings() =>
      (select(settings)..where((s) => s.id.equals(1))).watchSingle();

  /// Tworzy wiersz ustawień przy pierwszym uruchomieniu.
  Future<Setting> ensureSettings({
    required String Function() guidFactory,
    required String defaultNickname,
    required int defaultPort,
  }) async {
    final existing = await getSettings();
    if (existing != null) return existing;
    await into(settings).insert(
      SettingsCompanion.insert(
        id: const Value(1),
        deviceGuid: guidFactory(),
        nickname: defaultNickname,
        tcpPort: Value(defaultPort),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    return (await getSettings())!;
  }

  Future<void> saveSettings({
    required String nickname,
    required String welcomeMessage,
    required int tcpPort,
  }) =>
      (update(settings)..where((s) => s.id.equals(1))).write(SettingsCompanion(
        nickname: Value(nickname),
        welcomeMessage: Value(welcomeMessage),
        tcpPort: Value(tcpPort),
      ));

  // --- Rozmówcy -------------------------------------------------------------

  Future<Peer?> peerByGuid(String guid) =>
      (select(peers)..where((p) => p.guid.equals(guid))).getSingleOrNull();

  Future<Peer?> peerById(int id) =>
      (select(peers)..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Efekt parowania kodem PIN: od teraz wiadomo, że pod tym GUID-em siedzi
  /// urządzenie, które użytkownik świadomie potwierdził.
  Future<void> setPeerVerified(int id, bool verified) =>
      (update(peers)..where((p) => p.id.equals(id)))
          .write(PeersCompanion(verified: Value(verified)));

  Stream<List<Peer>> watchPeers() => (select(peers)
        ..orderBy([(p) => OrderingTerm.desc(p.lastSeen)]))
      .watch();

  /// Wstawia lub aktualizuje rozmówcę po [guid], zawsze odświeżając ostatni
  /// znany adres i czas kontaktu. Pojedynczy atomowy UPSERT — discovery
  /// potrafi zgłosić to samo urządzenie kilka razy równolegle (powtórzone
  /// broadcasty) i sprawdź-i-wstaw kończyłoby się wyścigiem na UNIQUE(guid).
  Future<Peer> upsertPeer({
    required String guid,
    required String name,
    required String welcomeMessage,
    required String host,
    required int port,
  }) async {
    final now = DateTime.now();
    await into(peers).insert(
      PeersCompanion.insert(
        guid: guid,
        name: name,
        welcomeMessage: Value(welcomeMessage),
        host: host,
        port: port,
        firstSeen: now,
        lastSeen: now,
      ),
      onConflict: DoUpdate(
        (old) => PeersCompanion(
          name: Value(name),
          welcomeMessage: Value(welcomeMessage),
          // Pusty host (nieznany adres źródła) nie nadpisuje ostatniego dobrego.
          host: host.isEmpty ? const Value.absent() : Value(host),
          port: Value(port),
          lastSeen: Value(now),
        ),
        target: [peers.guid],
      ),
    );
    return (await peerByGuid(guid))!;
  }

  // --- Konwersacje ----------------------------------------------------------

  Future<int> ensureConversation(int peerId) async {
    final existing = await (select(conversations)
          ..where((c) => c.peerId.equals(peerId)))
        .getSingleOrNull();
    if (existing != null) return existing.id;
    final now = DateTime.now();
    return into(conversations).insert(
        ConversationsCompanion.insert(peerId: peerId, createdAt: now, updatedAt: now));
  }

  Future<Peer?> peerForConversation(int conversationId) async {
    final conv = await (select(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .getSingleOrNull();
    if (conv == null) return null;
    return peerById(conv.peerId);
  }

  Future<void> touchConversation(int conversationId) =>
      (update(conversations)..where((c) => c.id.equals(conversationId)))
          .write(ConversationsCompanion(updatedAt: Value(DateTime.now())));

  /// Lista konwersacji do ekranu głównego, na żywo. Podzapytania liczą
  /// ostatnią wiadomość i nieprzeczytane; `readsFrom` mówi driftowi, po
  /// zmianach których tabel odświeżyć strumień.
  Stream<List<ConversationSummary>> watchConversationSummaries() {
    final query = customSelect(
      '''
      SELECT c.id AS conversation_id,
             p.id AS p_id,
             (SELECT m.body FROM messages m WHERE m.conversation_id = c.id
                ORDER BY m.created_at DESC, m.id DESC LIMIT 1) AS last_body,
             (SELECT m.created_at FROM messages m WHERE m.conversation_id = c.id
                ORDER BY m.created_at DESC, m.id DESC LIMIT 1) AS last_at,
             (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id
                AND m.direction = ${MessageDirection.incoming.index}
                AND m.read_at IS NULL) AS unread
      FROM conversations c
      JOIN peers p ON p.id = c.peer_id
      ORDER BY COALESCE(last_at, c.updated_at) DESC
      ''',
      readsFrom: {conversations, peers, messages},
    );
    return query.watch().asyncMap((rows) async {
      final result = <ConversationSummary>[];
      for (final row in rows) {
        final peer = await peerById(row.read<int>('p_id'));
        if (peer == null) continue;
        final lastAtMillis = row.readNullable<int>('last_at');
        result.add(ConversationSummary(
          conversationId: row.read<int>('conversation_id'),
          peer: peer,
          lastBody: row.readNullable<String>('last_body'),
          lastAt: lastAtMillis == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(lastAtMillis * 1000),
          unreadCount: row.read<int>('unread'),
        ));
      }
      return result;
    });
  }

  // --- Wiadomości -----------------------------------------------------------

  Stream<List<Message>> watchMessages(int conversationId) => (select(messages)
        ..where((m) => m.conversationId.equals(conversationId))
        ..orderBy([
          (m) => OrderingTerm.asc(m.createdAt),
          (m) => OrderingTerm.asc(m.id),
        ]))
      .watch();

  Future<Message?> messageById(int id) =>
      (select(messages)..where((m) => m.id.equals(id))).getSingleOrNull();

  Future<Message?> messageByGuid(String guid) =>
      (select(messages)..where((m) => m.messageGuid.equals(guid))).getSingleOrNull();

  Future<int> insertOutgoing({
    required int conversationId,
    required String messageGuid,
    required String body,
    MessageKind kind = MessageKind.text,
    String? fileName,
    int? fileSize,
    String? filePath,
  }) async {
    final id = await into(messages).insert(MessagesCompanion.insert(
      messageGuid: messageGuid,
      conversationId: conversationId,
      direction: MessageDirection.outgoing,
      status: MessageStatus.pending,
      kind: Value(kind),
      body: body,
      fileName: Value(fileName),
      fileSize: Value(fileSize),
      filePath: Value(filePath),
      createdAt: DateTime.now(),
    ));
    await touchConversation(conversationId);
    return id;
  }

  /// Zwraca false, gdy wiadomość o tym [messageGuid] już była (duplikat po
  /// ponowieniu) — wtedy niczego nie dopisujemy, ale nadawca i tak dostaje ACK.
  Future<bool> insertIncoming({
    required int conversationId,
    required String messageGuid,
    required String body,
    required DateTime sentAt,
    MessageKind kind = MessageKind.text,
    String? fileName,
    int? fileSize,
    String? filePath,
  }) async {
    final duplicate = await (select(messages)
          ..where((m) => m.messageGuid.equals(messageGuid)))
        .getSingleOrNull();
    if (duplicate != null) return false;
    await into(messages).insert(
      MessagesCompanion.insert(
        messageGuid: messageGuid,
        conversationId: conversationId,
        direction: MessageDirection.incoming,
        status: MessageStatus.delivered,
        kind: Value(kind),
        body: body,
        fileName: Value(fileName),
        fileSize: Value(fileSize),
        filePath: Value(filePath),
        createdAt: sentAt.toLocal(),
        deliveredAt: Value(DateTime.now()),
      ),
      // Zabezpieczenie przed wyścigiem dwóch równoczesnych dostarczeń tego
      // samego GUID-a między powyższym sprawdzeniem a insertem.
      mode: InsertMode.insertOrIgnore,
    );
    await touchConversation(conversationId);
    return true;
  }

  Future<void> setMessageStatus(int id, MessageStatus status) =>
      (update(messages)..where((m) => m.id.equals(id))).write(MessagesCompanion(
        status: Value(status),
        deliveredAt: status == MessageStatus.delivered
            ? Value(DateTime.now())
            : const Value.absent(),
      ));

  Future<void> markConversationRead(int conversationId) => (update(messages)
        ..where((m) =>
            m.conversationId.equals(conversationId) &
            m.direction.equalsValue(MessageDirection.incoming) &
            m.readAt.isNull()))
      .write(MessagesCompanion(readAt: Value(DateTime.now())));
}
