import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/env.dart';
import '../core/identity.dart';
import '../data/db.dart';
import '../network/client.dart';
import '../network/discovery.dart';
import '../network/protocol.dart';
import '../network/server.dart';

/// Korzeń aplikacji: łączy bazę, tożsamość, serwer wiadomości i discovery.
/// Testy E2E tworzą dwie instancje AppServices w jednym procesie i każą im
/// rozmawiać ze sobą jak dwóm osobnym urządzeniom.
class AppServices {
  final ChattDb db;
  final PeerClient client;
  final ChattServer server;
  final DiscoveryResponder responder;

  DeviceIdentity _identity;
  DeviceIdentity get identity => _identity;

  static const _uuid = Uuid();

  AppServices._(this.db, this.client, this.server, this.responder, this._identity);

  /// Uruchamia kompletny stos. Parametry służą testom (baza w pamięci,
  /// port 0 = dowolny wolny, wyłączone discovery przy testach izolowanych).
  static Future<AppServices> start({
    QueryExecutor? executor,
    int? portOverride,
    String? nameOverride,
    bool enableDiscovery = true,
  }) async {
    final db = ChattDb(executor ?? _defaultExecutor());

    final settings = await db.ensureSettings(
      guidFactory: _uuid.v4,
      defaultNickname:
          nameOverride ?? ChattEnv.instanceName ?? Platform.localHostname,
      defaultPort: portOverride ?? ChattEnv.tcpPort ?? defaultTcpPort,
    );

    var identity = DeviceIdentity(
      guid: settings.deviceGuid,
      name: settings.nickname,
      welcomeMessage: settings.welcomeMessage,
      tcpPort: settings.tcpPort,
    );

    late final AppServices services;
    final server = ChattServer(
      identity: () => services.identity,
      onMessage: (message, fromHost) => services._handleIncoming(message, fromHost),
    );
    final preferred = portOverride ?? ChattEnv.tcpPort ?? settings.tcpPort;
    final actualPort = await server.start(preferredPort: preferred);
    identity = identity.copyWith(tcpPort: actualPort);

    final responder = DiscoveryResponder(
      identity: () => services.identity,
      onPeerSeen: (peer) => services._rememberPeer(peer),
    );

    services = AppServices._(db, PeerClient(), server, responder, identity);

    if (enableDiscovery) {
      try {
        await responder.start();
      } on SocketException {
        // Port discovery zajęty bez możliwości współdzielenia (Windows z inną
        // aplikacją na 47777). Aplikacja działa dalej: będzie widzieć innych
        // po skanie, sama zostanie znaleziona dopiero po ręcznym dodaniu.
      }
    }
    return services;
  }

  static QueryExecutor _defaultExecutor() {
    final dir = ChattEnv.dataDir;
    if (dir != null) {
      Directory(dir).createSync(recursive: true);
      return NativeDatabase.createInBackground(File(p.join(dir, 'chatt.db')));
    }
    return driftDatabase(name: 'chatt');
  }

  // --- Discovery / rozmówcy -------------------------------------------------

  /// Skanuje sieć; znalezieni od razu trafiają do bazy (lista "w pobliżu"
  /// i lista konwersacji aktualizują się strumieniami z bazy).
  Future<List<DiscoveredPeer>> scan({void Function(DiscoveredPeer)? onFound}) async {
    final found = await DiscoveryScanner.scan(identity, onFound: onFound);
    for (final peer in found) {
      await _rememberPeer(peer);
    }
    return found;
  }

  /// Ręczne dodanie urządzenia po adresie — fallback, gdy broadcast nie
  /// przechodzi (izolacja AP, emulator Androida za NAT-em).
  Future<Peer?> addPeerByAddress(String host, int port) async {
    final info = await client.fetchInfo(host, port);
    if (info == null || info.guid == identity.guid) return null;
    return db.upsertPeer(
      guid: info.guid,
      name: info.name,
      welcomeMessage: info.welcomeMessage,
      host: host,
      port: info.tcpPort,
    );
  }

  /// Sprawdzenie obecności: czy rozmówca wciąż odpowiada pod znanym adresem.
  Future<bool> isPeerOnline(Peer peer) async =>
      (await client.fetchInfo(peer.host, peer.port,
          timeout: const Duration(seconds: 2))) != null;

  Future<Peer> _rememberPeer(DiscoveredPeer peer) => db.upsertPeer(
        guid: peer.guid,
        name: peer.name,
        welcomeMessage: peer.welcomeMessage,
        host: peer.host,
        port: peer.tcpPort,
      );

  // --- Konwersacje i wiadomości --------------------------------------------

  Future<int> openConversationWith(Peer peer) => db.ensureConversation(peer.id);

  /// Wysyłka: najpierw zapis lokalny (pending), potem dostarczenie i zmiana
  /// statusu. Dzięki temu wiadomość nigdy nie ginie — najwyżej zostaje
  /// oznaczona jako niedostarczona, z możliwością ponowienia.
  Future<void> sendText(int conversationId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final peer = await db.peerForConversation(conversationId);
    if (peer == null) return;

    final messageId = await db.insertOutgoing(
      conversationId: conversationId,
      messageGuid: _uuid.v4(),
      body: trimmed,
    );
    await _deliver(messageId, peer);
  }

  /// Ponowna próba dostarczenia wiadomości oznaczonej jako niedostarczona.
  Future<void> retryMessage(int messageId) async {
    final message = await db.messageById(messageId);
    if (message == null || message.direction != MessageDirection.outgoing) return;
    final peer = await db.peerForConversation(message.conversationId);
    if (peer == null) return;
    await db.setMessageStatus(messageId, MessageStatus.pending);
    await _deliver(messageId, peer);
  }

  Future<void> _deliver(int messageId, Peer peer) async {
    final message = await db.messageById(messageId);
    if (message == null) return;
    final delivered = await client.sendMessage(
      host: peer.host,
      port: peer.port,
      payload: messagePacket(
        messageGuid: message.messageGuid,
        from: identity,
        text: message.body,
        sentAt: message.createdAt,
      ),
    );
    await db.setMessageStatus(
        messageId, delivered ? MessageStatus.delivered : MessageStatus.failed);
  }

  /// Wiadomość przychodząca: nadawca zawsze najpierw ląduje w bazie (znamy
  /// jego IP z połączenia i port serwera z payloadu), potem sama wiadomość.
  Future<void> _handleIncoming(IncomingMessage message, String fromHost) async {
    final peer = await db.upsertPeer(
      guid: message.from.guid,
      name: message.from.name,
      welcomeMessage: message.from.welcomeMessage,
      host: fromHost,
      port: message.from.tcpPort,
    );
    final conversationId = await db.ensureConversation(peer.id);
    await db.insertIncoming(
      conversationId: conversationId,
      messageGuid: message.messageGuid,
      body: message.text,
      sentAt: message.sentAt,
    );
  }

  // --- Ustawienia -----------------------------------------------------------

  /// Zapis ustawień. Nick i powitanie działają od razu; nowy port zadziała
  /// po restarcie aplikacji (zwracamy true, żeby UI o tym powiedział).
  Future<bool> saveSettings({
    required String nickname,
    required String welcomeMessage,
    required int tcpPort,
  }) async {
    await db.saveSettings(
      nickname: nickname,
      welcomeMessage: welcomeMessage,
      tcpPort: tcpPort,
    );
    final portChanged = tcpPort != identity.tcpPort;
    _identity = _identity.copyWith(name: nickname, welcomeMessage: welcomeMessage);
    return portChanged;
  }

  /// Lokalne adresy IPv4 — pokazywane w ustawieniach, żeby dało się ręcznie
  /// sparować urządzenia, gdy discovery nie działa.
  Future<List<String>> localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return [
        for (final iface in interfaces)
          for (final addr in iface.addresses) addr.address,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> dispose() async {
    responder.stop();
    await server.stop();
    client.dispose();
    await db.close();
  }
}
