import 'package:drift/drift.dart';

import '../network/protocol.dart';

part 'db.g.dart';

/// Wybór motywu. `system` idzie za ustawieniem systemu.
enum AppTheme { system, light, dark }

/// Język interfejsu. `system` idzie za ustawieniem systemu.
enum AppLanguage { system, polish, english }

/// Ustawienia lokalnej instancji: zawsze dokładnie jeden wiersz (id = 1).
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

  /// Domyślnie angielski, a nie język systemu: aplikacja jest wydawana
  /// międzynarodowo, więc pierwsze uruchomienie ma być zrozumiałe wszędzie.
  /// Polski i „za systemem" są o jedno dotknięcie w Ustawieniach.
  IntColumn get language =>
      intEnum<AppLanguage>().withDefault(Constant(AppLanguage.english.index))();

  /// Preferowany port serwera. Faktyczny port może być inny, gdy ten jest
  /// zajęty (patrz DeviceIdentity.tcpPort).
  IntColumn get tcpPort =>
      integer().withDefault(const Constant(defaultTcpPort))();

  /// Numer wybranego tła (patrz `ui/backgrounds.dart`). 0 znaczy „bez tła".
  IntColumn get background => integer().withDefault(const Constant(0))();

  /// Po ilu dniach kasować wiadomości. 0 znaczy „trzymaj bez końca".
  /// Kasowanie dotyczy wpisów w bazie; odebrane pliki zostają na dysku.
  IntColumn get retentionDays => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Znane urządzenia (rozmówcy). Klucz logiczny to [guid], host i port są
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
  /// podszycia się, w obu przypadkach użytkownik ma to zobaczyć.
  TextColumn get publicKey => text().nullable()();

  /// Ślad po parowaniu z protokołu 4 (klucz sesji na zawsze). Od protokołu 5
  /// klucz sesji jest efemeryczny i nie trafia do bazy; kolumna zostaje na
  /// czas migracji i zniknie w kolejnym schemacie.
  TextColumn get sessionKey => text().nullable()();

  /// Własna nazwa rozmówcy, nadana lokalnie. [name] jest tym, co urządzenie
  /// samo o sobie rozgłasza, więc zmienia się bez pytania i każdy może wpisać
  /// tam cokolwiek. Alias zostaje po naszej stronie i nigdzie nie jedzie.
  /// Pusty i null znaczą to samo: idziemy za nazwą rozgłaszaną.
  TextColumn get alias => text().nullable()();

  /// Przyjmuj pliki od tego rozmówcy bez pytania. Ma sens wyłącznie przy
  /// potwierdzonej tożsamości, więc [setPeerVerified] gasi tę flagę razem
  /// z tarczą: inaczej przetrwałaby unieważnienie potwierdzenia.
  BoolColumn get autoAccept => boolean().withDefault(const Constant(false))();

  DateTimeColumn get firstSeen => dateTime()();
  DateTimeColumn get lastSeen => dateTime()();
}

/// Nazwa do pokazania: własna, jeśli jest, inaczej ta rozgłaszana przez
/// urządzenie. Jedno miejsce, bo UI pyta o nią w kilkunastu.
extension PeerDisplay on Peer {
  String get displayName {
    final own = alias;
    return (own == null || own.trim().isEmpty) ? name : own;
  }

  /// Czy nazwa jest nasza. Panel bezpieczeństwa pokazuje wtedy obie.
  bool get hasAlias => displayName != name;
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

  /// Globalny identyfikator wiadomości, dzięki UNIQUE ponowne dostarczenie
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
  int get schemaVersion => 9;

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
        // ma, kasujemy je i prosimy o sparowanie jeszcze raz.
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
        // wpisów, do których nie da się już napisać, czyścimy je razem
        // z historią i prosimy o znalezienie się od nowa.
        await m.addColumn(settings, settings.identityKey);
        await m.addColumn(peers, peers.publicKey);
        await m.database.customStatement('DELETE FROM messages');
        await m.database.customStatement('DELETE FROM conversations');
        await m.database.customStatement('DELETE FROM peers');
      }
      if (from < 7) {
        // v7: samoczynne kasowanie starych wiadomości. Domyślnie wyłączone:
        // włączenie go za kogoś skasowałoby historię bez pytania.
        await m.addColumn(settings, settings.retentionDays);
      }
      if (from < 8) {
        // v8: tło do wyboru. Domyślnie zero, czyli wygląd sprzed zmiany.
        await m.addColumn(settings, settings.background);
      }
      if (from < 9) {
        // v9: własna nazwa rozmówcy i przyjmowanie plików bez pytania.
        // Obie puste na starcie: nikt nie nadał jeszcze żadnej nazwy, a zgoda
        // na pliki bez pytania musi być świadoma, nie odziedziczona.
        await m.addColumn(peers, peers.alias);
        await m.addColumn(peers, peers.autoAccept);
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
  /// Wiersz sprzed schematu v6 ma pusty klucz i losowy identyfikator,
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
  /// Przypięcie klucza publicznego rozmówcy. Robimy to przy pierwszym
  /// kontakcie, od tej chwili wiadomo, z czyim kluczem rozmawiamy.
  Future<void> setPeerKey(int peerId, String publicKey) =>
      (update(peers)..where((p) => p.id.equals(peerId)))
          .write(PeersCompanion(publicKey: Value(publicKey)));

  Future<void> saveTheme(AppTheme theme) =>
      (update(settings)..where((s) => s.id.equals(1)))
          .write(SettingsCompanion(theme: Value(theme)));

  Future<void> saveLanguage(AppLanguage language) =>
      (update(settings)..where((s) => s.id.equals(1)))
          .write(SettingsCompanion(language: Value(language)));

  Future<void> saveBackground(int background) =>
      (update(settings)..where((s) => s.id.equals(1)))
          .write(SettingsCompanion(background: Value(background)));

  Future<void> saveRetentionDays(int days) =>
      (update(settings)..where((s) => s.id.equals(1)))
          .write(SettingsCompanion(retentionDays: Value(days)));

  // --- Historia -------------------------------------------------------------

  /// Kasuje całą historię rozmów: wiadomości i same rozmowy. Urządzenia
  /// zostają razem z potwierdzoną tożsamością: inaczej trzeba by parować
  /// wszystko od nowa tylko dlatego, że ktoś chciał wyczyścić treści.
  /// Odebrane pliki zostają na dysku. Zwraca liczbę usuniętych wiadomości.
  Future<int> clearHistory() => transaction(() async {
    final removed = await delete(messages).go();
    await delete(conversations).go();
    return removed;
  });

  /// Kasuje wiadomości starsze niż [age]. Rozmowy zostają, bo pusta rozmowa
  /// to nadal rozmowa, po prostu bez treści sprzed granicy.
  /// Zwraca liczbę usuniętych wiadomości.
  Future<int> deleteMessagesOlderThan(Duration age) {
    final cutoff = DateTime.now().subtract(age);
    return (delete(messages)..where((m) => m.createdAt.isSmallerThanValue(cutoff)))
        .go();
  }

  // --- Rozmówcy -------------------------------------------------------------

  Future<Peer?> peerByGuid(String guid) =>
      (select(peers)..where((p) => p.guid.equals(guid))).getSingleOrNull();

  Future<Peer?> peerById(int id) =>
      (select(peers)..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Usuwa rozmówcę razem z rozmową i jej wiadomościami. Odebrane pliki
  /// zostają na dysku: kasujemy własne wpisy, nie cudzą zawartość.
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
  /// widać. Sparowanych nie ruszamy, te użytkownik potwierdził świadomie.
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
  ///
  /// Zdjęcie potwierdzenia gasi też przyjmowanie plików bez pytania. Zgoda
  /// dotyczyła konkretnej, potwierdzonej tożsamości; gdy tarcza gaśnie,
  /// zostawienie otwartej furtki byłoby cichym rozszerzeniem tej zgody.
  Future<void> setPeerVerified(int id, bool verified) =>
      (update(peers)..where((p) => p.id.equals(id))).write(
        verified
            ? const PeersCompanion(verified: Value(true))
            : const PeersCompanion(
                verified: Value(false),
                autoAccept: Value(false),
              ),
      );

  /// Własna nazwa rozmówcy. Pusty napis kasuje ją i wraca do rozgłaszanej.
  Future<void> setPeerAlias(int id, String? alias) {
    final trimmed = alias?.trim();
    return (update(peers)..where((p) => p.id.equals(id))).write(
      PeersCompanion(
        alias: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
      ),
    );
  }

  /// Przyjmowanie plików bez pytania. Włączyć da się tylko przy potwierdzonej
  /// tożsamości, sprawdzamy to tutaj, a nie w UI, bo to jest granica zgody
  /// użytkownika, a nie kwestia wyglądu ekranu. Zwraca stan po zapisie.
  Future<bool> setPeerAutoAccept(int id, bool value) async {
    final peer =
        await (select(peers)..where((p) => p.id.equals(id))).getSingleOrNull();
    if (peer == null) return false;
    final allowed = value && peer.verified;
    await (update(peers)..where((p) => p.id.equals(id)))
        .write(PeersCompanion(autoAccept: Value(allowed)));
    return allowed;
  }

  /// Sparowanie zakończone: zapisujemy klucz sesji i oznaczamy urządzenie
  /// jako zweryfikowane. Od tej pory ruch z nim jest szyfrowany.
  Future<void> setPeerPaired(int id, String sessionKey) =>
      (update(peers)..where((p) => p.id.equals(id))).write(
        PeersCompanion(
          verified: const Value(true),
          sessionKey: Value(sessionKey),
        ),
      );

  Stream<List<Peer>> watchPeers() => _peersByLastSeen().watch();

  /// To samo, ale raz: sprawdzanie obecności pyta o listę co pół minuty
  /// i nie potrzebuje strumienia.
  Future<List<Peer>> allPeers() => _peersByLastSeen().get();

  SimpleSelectStatement<$PeersTable, Peer> _peersByLastSeen() =>
      select(peers)..orderBy([(p) => OrderingTerm.desc(p.lastSeen)]);

  /// Wstawia lub aktualizuje rozmówcę po [guid], zawsze odświeżając ostatni
  /// znany adres i czas kontaktu. Pojedynczy atomowy UPSERT, bo discovery
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
  /// ponowieniu), wtedy niczego nie dopisujemy, ale nadawca i tak dostaje ACK.
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

  /// Kasuje jedną wiadomość. Tylko u siebie: protokół nie ma jak kazać
  /// drugiej stronie zapomnieć czegoś, co już dostała. Plik na dysku zostaje.
  Future<void> deleteMessage(int id) =>
      (delete(messages)..where((m) => m.id.equals(id))).go();

  Future<void> markConversationRead(int conversationId) =>
      (update(messages)..where(
            (m) =>
                m.conversationId.equals(conversationId) &
                m.direction.equalsValue(MessageDirection.incoming) &
                m.readAt.isNull(),
          ))
          .write(MessagesCompanion(readAt: Value(DateTime.now())));
}
