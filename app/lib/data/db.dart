import 'package:drift/drift.dart';

import '../network/protocol.dart';

part 'db.g.dart';

/// Wybór motywu. `system` idzie za ustawieniem systemu.
enum AppTheme { system, light, dark }

/// Język interfejsu. `system` idzie za ustawieniem systemu.
enum AppLanguage { system, polish, english }

/// Ustawienia lokalnej instancji — zawsze dokładnie jeden wiersz (id = 1).
class Settings extends Table {
  IntColumn get id => integer()();

  /// Identyfikator urządzenia. Od schematu v6 nie jest losowany, tylko liczony
  /// z klucza publicznego (patrz `ChattCrypto.guidFromPublicKey`).
  TextColumn get deviceGuid => text()();

  /// Klucz prywatny tożsamości (base64, X25519). To on jest urządzeniem:
  /// z niego wychodzi klucz publiczny, a z niego identyfikator.
  TextColumn get identityKey => text().withDefault(const Constant(''))();
  TextColumn get nickname => text()();
  TextColumn get welcomeMessage => text().withDefault(const Constant(''))();

  IntColumn get theme =>
      intEnum<AppTheme>().withDefault(Constant(AppTheme.system.index))();

  IntColumn get language =>
      intEnum<AppLanguage>().withDefault(Constant(AppLanguage.system.index))();

  /// Preferowany port serwera. Faktyczny port może być inny, gdy ten jest
  /// zajęty — patrz DeviceIdentity.tcpPort.
  IntColumn get tcpPort =>
      integer().withDefault(const Constant(defaultTcpPort))();

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

  /// Klucz publiczny rozmówcy (base64), przypięty przy pierwszym kontakcie.
  /// Jego zmiana znaczy albo reinstalację po drugiej stronie, albo próbę
  /// podszycia się — w obu przypadkach użytkownik ma to zobaczyć.
  TextColumn get publicKey => text().nullable()();

  /// Ślad po parowaniu z protokołu 4 (klucz sesji na zawsze). Od protokołu 5
  /// klucz sesji jest efemeryczny i nie trafia do bazy; kolumna zostaje na
  /// czas migracji i zniknie w kolejnym schemacie.
  TextColumn get sessionKey => text().nullable()();

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
  int get schemaVersion => 6;

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
      if (from < 3) {
        // v3: klucz sesji z parowania. Wcześniejsze parowania nie miały
        // klucza, więc zielona tarcza obiecywałaby szyfrowanie, którego nie
        // ma — kasujemy je i prosimy o sparowanie jeszcze raz.
        await m.addColumn(peers, peers.sessionKey);
        await m.database.customStatement('UPDATE peers SET verified = 0');
      }
      if (from < 4) {
        // v4: wybór motywu
        await m.addColumn(settings, settings.theme);
      }
      if (from < 5) {
        // v5: wybór języka
        await m.addColumn(settings, settings.language);
      }
      if (from < 6) {
        // v6: tożsamość urządzenia przestaje być losowym GUID-em i zaczyna
        // być liczona z klucza publicznego. Wszystkie urządzenia dostają
        // przez to nowe identyfikatory, więc zapisani rozmówcy przestają
        // pasować do czegokolwiek w sieci. Zostawienie ich znaczyłoby listę
        // wpisów, do których nie da się już napisać — czyścimy je razem
        // z historią i prosimy o znalezienie się od nowa.
        await m.addColumn(settings, settings.identityKey);
        await m.addColumn(peers, peers.publicKey);
        await m.database.customStatement('DELETE FROM messages');
        await m.database.customStatement('DELETE FROM conversations');
        await m.database.customStatement('DELETE FROM peers');
      }
    },
  );

  // --- Ustawienia -----------------------------------------------------------

  Future<Setting?> getSettings() =>
      (select(settings)..where((s) => s.id.equals(1))).getSingleOrNull();

  Stream<Setting> watchSettings() =>
      (select(settings)..where((s) => s.id.equals(1))).watchSingle();

  /// Tworzy wiersz ustawień przy pierwszym uruchomieniu.
  /// [identityFactory] daje parę (klucz prywatny base64, identyfikator z niego
  /// policzony). Wołamy je leniwie, bo losowanie klucza kosztuje, a przy
  /// kolejnych startach nie ma czego losować.
  ///
  /// Wiersz sprzed schematu v6 ma pusty klucz i losowy identyfikator —
  /// dorabiamy mu tożsamość tutaj, przy pierwszym starcie po aktualizacji.
  Future<Setting> ensureSettings({
    required Future<(String, String)> Function() identityFactory,
    required String defaultNickname,
    required int defaultPort,
  }) async {
    final existing = await getSettings();
    if (existing != null && existing.identityKey.isNotEmpty) return existing;

    final (klucz, guid) = await identityFactory();
    if (existing == null) {
      await into(settings).insert(
        SettingsCompanion.insert(
          id: const Value(1),
          deviceGuid: guid,
          identityKey: Value(klucz),
          nickname: defaultNickname,
          tcpPort: Value(defaultPort),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    } else {
      await (update(settings)..where((s) => s.id.equals(1))).write(
        SettingsCompanion(
          deviceGuid: Value(guid),
          identityKey: Value(klucz),
        ),
      );
    }
    return (await getSettings())!;
  }

  Future<void> saveSettings({
    required String nickname,
    required String welcomeMessage,
    required int tcpPort,
  }) => (update(settings)..where((s) => s.id.equals(1))).write(
    SettingsCompanion(
      nickname: Value(nickname),
      welcomeMessage: Value(welcomeMessage),
      tcpPort: Value(tcpPort),
    ),
  );

  /// Motyw i język zapisujemy osobno: zmieniają się jednym kliknięciem,
  /// bez formularza i bez przycisku „zapisz".
  Future<void> saveTheme(AppTheme theme) =>
      (update(settings)..where((s) => s.id.equals(1)))
          .write(SettingsCompanion(theme: Value(theme)));

  Future<void> saveLanguage(AppLanguage language) =>
      (update(settings)..where((s) => s.id.equals(1)))
          .write(SettingsCompanion(language: Value(language)));

  // --- Rozmówcy -------------------------------------------------------------

  Future<Peer?> peerByGuid(String guid) =>
      (select(peers)..where((p) => p.guid.equals(guid))).getSingleOrNull();

  Future<Peer?> peerById(int id) =>
      (select(peers)..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Usuwa rozmówcę razem z rozmową i jej wiadomościami. Odebrane pliki
  /// zostają na dysku — kasujemy własne wpisy, nie cudzą zawartość.
  Future<void> deletePeer(int peerId) => transaction(() async {
    final conversation = await (select(
      conversations,
    )..where((c) => c.peerId.equals(peerId))).getSingleOrNull();
    if (conversation != null) {
      await (delete(
        messages,
      )..where((m) => m.conversationId.equals(conversation.id))).go();
      await (delete(
        conversations,
      )..where((c) => c.id.equals(conversation.id))).go();
    }
    await (delete(peers)..where((p) => p.id.equals(peerId))).go();
  });

  /// Sprząta po urządzeniach, które przewinęły się przez sieć i zniknęły:
  /// takich, z którymi nie ma ani jednej wiadomości i których dawno nie
  /// widać. Sparowanych nie ruszamy — te użytkownik potwierdził świadomie.
  /// Zwraca liczbę usuniętych wpisów.
  Future<int> sweepStalePeers({
    Duration keepFor = const Duration(days: 7),
  }) async {
    final stale = await customSelect(
      '''
      SELECT p.id AS id FROM peers p
      WHERE p.last_seen < ?
        AND p.verified = 0
        AND NOT EXISTS (
          SELECT 1 FROM conversations c
          JOIN messages m ON m.conversation_id = c.id
          WHERE c.peer_id = p.id)
      ''',
      variables: [Variable.withDateTime(DateTime.now().subtract(keepFor))],
      readsFrom: {peers, conversations, messages},
    ).get();

    for (final row in stale) {
      await deletePeer(row.read<int>('id'));
    }
    return stale.length;
  }

  /// Efekt parowania kodem PIN: od teraz wiadomo, że pod tym GUID-em siedzi
  /// urządzenie, które użytkownik świadomie potwierdził.
  Future<void> setPeerVerified(int id, bool verified) =>
      (update(peers)..where((p) => p.id.equals(id))).write(
        PeersCompanion(verified: Value(verified)),
      );

  /// Sparowanie zakończone: zapisujemy klucz sesji i oznaczamy urządzenie
  /// jako zweryfikowane. Od tej pory ruch z nim jest szyfrowany.
  Future<void> setPeerPaired(int id, String sessionKey) =>
      (update(peers)..where((p) => p.id.equals(id))).write(
        PeersCompanion(
          verified: const Value(true),
          sessionKey: Value(sessionKey),
        ),
      );

  Stream<List<Peer>> watchPeers() =>
      (select(peers)..orderBy([(p) => OrderingTerm.desc(p.lastSeen)])).watch();

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
    final existing = await (select(
      conversations,
    )..where((c) => c.peerId.equals(peerId))).getSingleOrNull();
    if (existing != null) return existing.id;
    final now = DateTime.now();
    return into(conversations).insert(
      ConversationsCompanion.insert(
        peerId: peerId,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<Peer?> peerForConversation(int conversationId) async {
    final conv = await (select(
      conversations,
    )..where((c) => c.id.equals(conversationId))).getSingleOrNull();
    if (conv == null) return null;
    return peerById(conv.peerId);
  }

  Future<void> touchConversation(int conversationId) =>
      (update(conversations)..where((c) => c.id.equals(conversationId))).write(
        ConversationsCompanion(updatedAt: Value(DateTime.now())),
      );

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
        result.add(
          ConversationSummary(
            conversationId: row.read<int>('conversation_id'),
            peer: peer,
            lastBody: row.readNullable<String>('last_body'),
            lastAt: lastAtMillis == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(lastAtMillis * 1000),
            unreadCount: row.read<int>('unread'),
          ),
        );
      }
      return result;
    });
  }

  // --- Wiadomości -----------------------------------------------------------

  Stream<List<Message>> watchMessages(int conversationId) =>
      (select(messages)
            ..where((m) => m.conversationId.equals(conversationId))
            ..orderBy([
              (m) => OrderingTerm.asc(m.createdAt),
              (m) => OrderingTerm.asc(m.id),
            ]))
          .watch();

  Future<Message?> messageById(int id) =>
      (select(messages)..where((m) => m.id.equals(id))).getSingleOrNull();

  Future<Message?> messageByGuid(String guid) => (select(
    messages,
  )..where((m) => m.messageGuid.equals(guid))).getSingleOrNull();

  Future<int> insertOutgoing({
    required int conversationId,
    required String messageGuid,
    required String body,
    MessageKind kind = MessageKind.text,
    String? fileName,
    int? fileSize,
    String? filePath,
  }) async {
    final id = await into(messages).insert(
      MessagesCompanion.insert(
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
      ),
    );
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
    final duplicate = await (select(
      messages,
    )..where((m) => m.messageGuid.equals(messageGuid))).getSingleOrNull();
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
      (update(messages)..where((m) => m.id.equals(id))).write(
        MessagesCompanion(
          status: Value(status),
          deliveredAt: status == MessageStatus.delivered
              ? Value(DateTime.now())
              : const Value.absent(),
        ),
      );

  Future<void> markConversationRead(int conversationId) =>
      (update(messages)..where(
            (m) =>
                m.conversationId.equals(conversationId) &
                m.direction.equalsValue(MessageDirection.incoming) &
                m.readAt.isNull(),
          ))
          .write(MessagesCompanion(readAt: Value(DateTime.now())));
}
