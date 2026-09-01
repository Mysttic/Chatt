import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;

import 'package:crypto/crypto.dart' show sha256;
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/env.dart';
import '../core/file_actions.dart';
import '../core/identity.dart';
import '../data/db.dart';
import '../network/client.dart';
import '../network/discovery.dart';
import '../network/protocol.dart';
import '../network/server.dart';

/// Prośba o zgodę na odbiór pliku — czeka na decyzję użytkownika.
class PendingFileOffer {
  final String messageGuid;
  final String peerName;
  final String fileName;
  final int fileSize;

  /// Ile bajtów mamy już z przerwanego wcześniej transferu (0 = od zera).
  final int resumeFrom;
  final int conversationId;

  /// Czy nadawca jest sparowany kodem. Nazwa urządzenia to tylko napis,
  /// który każdy może sobie ustawić — przy niesparowanym warto ostrzec.
  final bool fromVerifiedPeer;

  const PendingFileOffer({
    required this.messageGuid,
    required this.peerName,
    required this.fileName,
    required this.fileSize,
    required this.resumeFrom,
    required this.conversationId,
    this.fromVerifiedPeer = false,
  });
}

/// Decyzja o odbiorze pliku. Domyślnie pyta użytkownika (patrz
/// [AppServices.pendingOffers]); testy i skrypty podstawiają własną.
typedef FileOfferPolicy = Future<bool> Function(PendingFileOffer offer);

/// Wołane po zapisaniu wiadomości od rozmówcy (bez duplikatów). Warstwa UI
/// decyduje, co z tym zrobić — np. powiadomienie, gdy okno jest zamknięte.
typedef IncomingMessageHook = void Function(
    Peer peer, String preview, int conversationId);

/// Zgoda przyjmuje wszystko bez pytania — dla testów i trybu bezobsługowego.
Future<bool> acceptAllFileOffers(PendingFileOffer offer) async => true;

/// Odmowa dla wszystkiego — dla testów.
Future<bool> rejectAllFileOffers(PendingFileOffer offer) async => false;

/// Prośba o sparowanie czekająca na przepisanie kodu z drugiego urządzenia.
class PendingPairing {
  final String peerGuid;
  final String peerName;

  const PendingPairing({required this.peerGuid, required this.peerName});
}

/// Kod parowania pokazany na ekranie tego urządzenia i moment jego wygaśnięcia.
class _PairingCode {
  final String pin;
  final DateTime expiresAt;

  const _PairingCode(this.pin, this.expiresAt);

  bool get expired => DateTime.now().isAfter(expiresAt);
}

/// Trwający odbiór pliku (po akceptacji) — do paska postępu w czacie.
class IncomingTransfer {
  final String messageGuid;
  final int conversationId;
  final String peerName;
  final String fileName;
  final int fileSize;
  final ValueNotifier<int> receivedBytes;

  IncomingTransfer({
    required this.messageGuid,
    required this.conversationId,
    required this.peerName,
    required this.fileName,
    required this.fileSize,
    required int received,
  }) : receivedBytes = ValueNotifier(received);
}

/// Zaakceptowana zapowiedź czekająca na bajty (POST /file zaraz po zgodzie).
class _AcceptedOffer {
  final FileOffer offer;
  final int conversationId;

  const _AcceptedOffer(this.offer, this.conversationId);
}

/// Korzeń aplikacji: łączy bazę, tożsamość, serwer wiadomości i discovery.
/// Testy E2E tworzą dwie instancje AppServices w jednym procesie i każą im
/// rozmawiać ze sobą jak dwóm osobnym urządzeniom.
class AppServices {
  final ChattDb db;
  final PeerClient client;
  final ChattServer server;
  final DiscoveryResponder responder;

  /// Katalog na pliki odebrane od innych urządzeń.
  final String receivedDir;

  DeviceIdentity _identity;
  DeviceIdentity get identity => _identity;

  /// Postęp trwających wysyłek plików: id wiadomości -> 0..1. UI podpina się
  /// przez [progressOf]; wpis znika po zakończeniu transferu.
  final Map<int, ValueNotifier<double>> _transferProgress = {};
  ValueListenable<double>? progressOf(int messageId) => _transferProgress[messageId];

  /// Zmienia się przy każdym starcie i końcu wysyłki. UI czatu się tym
  /// odświeża — bez tego pasek postępu potrafił się nie pojawić, bo dymek
  /// zbudował się chwilę przed rejestracją transferu.
  final ValueNotifier<int> transfersRevision = ValueNotifier(0);

  /// Prośby o zgodę na odbiór pliku czekające na decyzję użytkownika.
  /// UI (overlay w app.dart) słucha i odpowiada przez [respondToOffer].
  final ValueNotifier<List<PendingFileOffer>> pendingOffers =
      ValueNotifier(const []);

  /// Trwające odbiory plików: guid wiadomości -> postęp. Wpis znika po
  /// zakończeniu (wtedy plik jest już zwykłą wiadomością w bazie).
  final ValueNotifier<Map<String, IncomingTransfer>> incomingTransfers =
      ValueNotifier(const {});

  /// Jak odpowiadamy na zapowiedzi plików. Ustawiane raz, w [start].
  late final FileOfferPolicy _offerPolicy;

  /// Powiadomienie o nowej wiadomości (opcjonalne, ustawiane w [start]).
  IncomingMessageHook? _onIncoming;

  final Map<String, Completer<bool>> _offerDecisions = {};
  final Map<String, _AcceptedOffer> _acceptedOffers = {};

  /// Pliki właśnie odbierane — po jednym transferze na guid.
  final Set<String> _receivingFiles = {};

  /// Prośby o sparowanie, na które czeka użytkownik tego urządzenia.
  final ValueNotifier<List<PendingPairing>> pendingPairings =
      ValueNotifier(const []);

  /// Kody parowania, które sami pokazujemy na ekranie: guid rozmówcy -> kod.
  final Map<String, _PairingCode> _pairingCodes = {};

  /// sha256 wysyłanych plików — liczone raz na sesję, żeby ponowienie
  /// dużego transferu nie czytało pliku drugi raz tylko po to.
  final Map<String, String> _sentFileHashes = {};

  static const _uuid = Uuid();

  AppServices._(this.db, this.client, this.server, this.responder,
      this.receivedDir, this._identity);

  /// Uruchamia kompletny stos. Parametry służą testom (baza w pamięci,
  /// port 0 = dowolny wolny, wyłączone discovery przy testach izolowanych).
  static Future<AppServices> start({
    QueryExecutor? executor,
    int? portOverride,
    String? nameOverride,
    bool enableDiscovery = true,
    String? receivedDirOverride,
    FileOfferPolicy? fileOfferPolicy,
    IncomingMessageHook? onIncomingMessage,
  }) async {
    final db = ChattDb(executor ?? _defaultExecutor());
    final receivedDir = receivedDirOverride ?? await _defaultReceivedDir();
    Directory(receivedDir).createSync(recursive: true);
    Directory(p.join(receivedDir, _incompleteSubdir)).createSync(recursive: true);

    final settings = await db.ensureSettings(
      guidFactory: _uuid.v4,
      defaultNickname:
          nameOverride ?? ChattEnv.instanceName ?? _defaultDeviceName(),
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
      onPair: (message, fromHost) => services._handlePair(message, fromHost),
      onFileOffer: (offer, fromHost) => services._handleFileOffer(offer, fromHost),
      onFile: (meta, data, fromHost) =>
          services._handleIncomingFile(meta, data, fromHost),
    );
    final preferred = portOverride ?? ChattEnv.tcpPort ?? settings.tcpPort;
    final actualPort = await server.start(preferredPort: preferred);
    identity = identity.copyWith(tcpPort: actualPort);

    final responder = DiscoveryResponder(
      identity: () => services.identity,
      onPeerSeen: (peer) => services._rememberPeer(peer),
    );

    services =
        AppServices._(db, PeerClient(), server, responder, receivedDir, identity);
    services._offerPolicy = fileOfferPolicy ?? services._askUserAboutOffer;
    services._onIncoming = onIncomingMessage;
    services._sweepStaleParts();

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

  /// Nick przy pierwszym starcie. Android zwraca z `localHostname` po prostu
  /// "localhost", co na liście urządzeń wygląda jak błąd — tam lepszy jest
  /// czytelny domyślny nick (użytkownik i tak zmieni go w ustawieniach).
  static String _defaultDeviceName() {
    if (Platform.isAndroid || Platform.isIOS) return 'Telefon';
    final host = Platform.localHostname;
    return (host.isEmpty || host == 'localhost') ? 'Moje urządzenie' : host;
  }

  static QueryExecutor _defaultExecutor() {
    final dir = ChattEnv.dataDir;
    if (dir != null) {
      Directory(dir).createSync(recursive: true);
      return NativeDatabase.createInBackground(File(p.join(dir, 'chatt.db')));
    }
    return driftDatabase(name: 'chatt');
  }

  static Future<String> _defaultReceivedDir() async {
    final envDir = ChattEnv.dataDir;
    if (envDir != null) return p.join(envDir, 'received');
    try {
      // Android: katalog `files/` aplikacji — to jedyne miejsce, które
      // FileProvider potrafi wypuścić na zewnątrz jako content:// (patrz
      // android/app/src/main/res/xml/file_paths.xml), więc odebrany plik da
      // się otworzyć w innej aplikacji. Desktop: katalog dokumentów, bo tam
      // użytkownik sam go znajdzie.
      final base = (Platform.isAndroid || Platform.isIOS)
          ? await getApplicationSupportDirectory()
          : await getApplicationDocumentsDirectory();
      return p.join(base.path, 'Chatt', 'received');
    } catch (_) {
      // path_provider wymaga kanału platformy; w testach bez bindingu rzuca
      // Error (nie Exception) — tam wystarczy katalog tymczasowy.
      return p.join(Directory.systemTemp.path, 'chatt', 'received');
    }
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
  ///
  /// Zapisujemy adres, pod którym urządzenie FAKTYCZNIE odpowiedziało, a nie
  /// port, którym się przedstawia. Przy tunelu (emulator za NAT-em, adb
  /// forward, przekierowanie portu na routerze) to są dwie różne rzeczy
  /// i tylko ten pierwszy da się połączyć.
  Future<Peer?> addPeerByAddress(String host, int port) async {
    final info = await client.fetchInfo(host, port);
    if (info == null || info.guid == identity.guid) return null;
    return db.upsertPeer(
      guid: info.guid,
      name: info.name,
      welcomeMessage: info.welcomeMessage,
      host: host,
      port: port,
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

  // --- Parowanie kodem PIN --------------------------------------------------

  /// Zaczyna parowanie: losuje kod, wysyła rozmówcy prośbę i zwraca kod do
  /// pokazania na ekranie. Użytkownik przepisuje go na drugim urządzeniu.
  /// null = rozmówca nie odpowiedział (albo odmówił).
  Future<String?> startPairing(Peer peer) async {
    final pin = _randomPin();
    _pairingCodes[peer.guid] =
        _PairingCode(pin, DateTime.now().add(const Duration(minutes: 2)));

    final accepted = await client.pair(
      host: peer.host,
      port: peer.port,
      payload: PairMessage(action: pairStart, from: identity).toJson(),
    );
    if (!accepted) {
      _pairingCodes.remove(peer.guid);
      return null;
    }
    return pin;
  }

  /// Odpowiedź na prośbę z [pendingPairings]: przepisany kod wraca do
  /// inicjatora. true = kod się zgadzał i obie strony są już zweryfikowane.
  Future<bool> confirmPairing(String peerGuid, String pin) async {
    final peer = await db.peerByGuid(peerGuid);
    if (peer == null) return false;

    final accepted = await client.pair(
      host: peer.host,
      port: peer.port,
      payload:
          PairMessage(action: pairConfirm, from: identity, pin: pin.trim())
              .toJson(),
    );
    if (accepted) {
      await db.setPeerVerified(peer.id, true);
      _removePendingPairing(peerGuid);
    }
    return accepted;
  }

  /// Rezygnacja z parowania po tej stronie, która została poproszona.
  void cancelPairing(String peerGuid) => _removePendingPairing(peerGuid);

  Future<bool> _handlePair(PairMessage message, String fromHost) async {
    final peer = await db.upsertPeer(
      guid: message.from.guid,
      name: message.from.name,
      welcomeMessage: message.from.welcomeMessage,
      host: fromHost,
      port: message.from.tcpPort,
    );

    switch (message.action) {
      case pairStart:
        // Druga strona pokazuje u siebie kod; my prosimy użytkownika,
        // żeby go przepisał.
        pendingPairings.value = [
          ...pendingPairings.value.where((p) => p.peerGuid != peer.guid),
          PendingPairing(peerGuid: peer.guid, peerName: peer.name),
        ];
        return true;

      case pairConfirm:
        final code = _pairingCodes[peer.guid];
        if (code == null || code.expired || message.pin != code.pin) {
          // Zły albo przeterminowany kod nie kasuje próby: użytkownik może
          // się pomylić przy przepisywaniu.
          if (code != null && code.expired) _pairingCodes.remove(peer.guid);
          return false;
        }
        _pairingCodes.remove(peer.guid);
        await db.setPeerVerified(peer.id, true);
        return true;

      default: // pairCancel
        _pairingCodes.remove(peer.guid);
        _removePendingPairing(peer.guid);
        return true;
    }
  }

  void _removePendingPairing(String peerGuid) {
    pendingPairings.value = pendingPairings.value
        .where((pairing) => pairing.peerGuid != peerGuid)
        .toList(growable: false);
  }

  static String _randomPin() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

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

  /// Wysyłka pliku: wiadomość-plik ląduje w bazie (pending), potem streaming
  /// do odbiorcy z raportowaniem postępu przez [progressOf].
  Future<void> sendFile(int conversationId, String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) return;
    final peer = await db.peerForConversation(conversationId);
    if (peer == null) return;

    final name = p.basename(sourcePath);
    final messageId = await db.insertOutgoing(
      conversationId: conversationId,
      messageGuid: _uuid.v4(),
      kind: MessageKind.file,
      body: '📎 $name', // podgląd na liście konwersacji
      fileName: name,
      fileSize: await file.length(),
      filePath: sourcePath,
    );
    await _deliverFile(messageId, peer);
  }

  /// Ponowna próba dostarczenia wiadomości oznaczonej jako niedostarczona.
  Future<void> retryMessage(int messageId) async {
    final message = await db.messageById(messageId);
    if (message == null || message.direction != MessageDirection.outgoing) return;
    final peer = await db.peerForConversation(message.conversationId);
    if (peer == null) return;
    await db.setMessageStatus(messageId, MessageStatus.pending);
    if (message.kind == MessageKind.file) {
      await _deliverFile(messageId, peer);
    } else {
      await _deliver(messageId, peer);
    }
  }

  Future<void> _deliver(int messageId, Peer peer) async {
    final message = await db.messageById(messageId);
    if (message == null) return;
    final payload = messagePacket(
      messageGuid: message.messageGuid,
      from: identity,
      text: message.body,
      sentAt: message.createdAt,
    );

    var delivered = await client.sendMessage(
        host: peer.host, port: peer.port, payload: payload);

    if (!delivered) {
      // Rozmówca mógł dostać nowy adres z DHCP — szukamy go po GUID.
      final moved = await _relocate(peer);
      if (moved != null) {
        delivered = await client.sendMessage(
            host: moved.host, port: moved.port, payload: payload);
      }
    }

    await db.setMessageStatus(
        messageId, delivered ? MessageStatus.delivered : MessageStatus.failed);
  }

  /// Rozmówca pod zapisanym adresem nie odpowiada. Adres IP w sieci domowej
  /// zmienia się po restarcie routera, GUID nie — więc skanujemy sieć i jeśli
  /// znajdziemy to samo urządzenie gdzie indziej, zapisujemy nowy adres.
  /// Zwraca rozmówcę z aktualnym adresem albo null, gdy naprawdę go nie ma.
  Future<Peer?> _relocate(Peer peer) async {
    final List<DiscoveredPeer> found;
    try {
      found = await DiscoveryScanner.scan(identity);
    } catch (_) {
      return null; // brak sieci, zablokowany broadcast
    }
    for (final device in found) {
      if (device.guid != peer.guid) continue;
      if (device.host == peer.host && device.tcpPort == peer.port) {
        return null; // ten sam adres, czyli problem jest gdzie indziej
      }
      return db.upsertPeer(
        guid: device.guid,
        name: device.name,
        welcomeMessage: device.welcomeMessage,
        host: device.host,
        port: device.tcpPort,
      );
    }
    return null;
  }

  /// Wysyłka pliku: najpierw zapowiedź (odbiorca decyduje, czy chce go
  /// przyjąć i od którego bajtu), potem dopiero bajty. Odmowa i zerwany
  /// transfer kończą się statusem "niedostarczone" z możliwością ponowienia
  /// — wznowienie dokłada tylko brakującą część.
  Future<void> _deliverFile(int messageId, Peer peer) async {
    final message = await db.messageById(messageId);
    final path = message?.filePath;
    if (message == null || path == null) return;
    final file = File(path);
    if (!await file.exists()) {
      await db.setMessageStatus(messageId, MessageStatus.failed);
      return;
    }

    final total = await file.length();
    final name = message.fileName ?? p.basename(path);
    final progress = _transferProgress[messageId] ??= ValueNotifier(0);
    transfersRevision.value++;
    try {
      final hash = await _hashOfSentFile(message.messageGuid, file);
      final offerPayload = FileOffer(
        messageGuid: message.messageGuid,
        from: identity,
        fileName: name,
        fileSize: total,
        sha256: hash,
        sentAt: message.createdAt,
      ).toJson();

      var target = peer;
      var reply = await client.offerFile(
          host: target.host, port: target.port, payload: offerPayload);

      if (reply == null) {
        // Cisza pod znanym adresem: może rozmówca dostał nowy z DHCP.
        final moved = await _relocate(target);
        if (moved != null) {
          target = moved;
          reply = await client.offerFile(
              host: target.host, port: target.port, payload: offerPayload);
        }
      }

      if (reply != null && !reply.accepted) {
        await db.setMessageStatus(messageId, MessageStatus.failed);
        return;
      }
      if (reply != null && reply.alreadyHave) {
        // Odbiorca ma już ten plik (zgubiony ACK) — nic nie wysyłamy.
        await db.setMessageStatus(messageId, MessageStatus.delivered);
        return;
      }

      var resumeFrom =
          (reply == null || reply.resumeFrom >= total) ? 0 : reply.resumeFrom;
      progress.value = total == 0 ? 1 : resumeFrom / total;

      var delivered = await _streamFile(
          message, file, target, name, total, hash, resumeFrom, progress);

      if (!delivered && resumeFrom > 0) {
        // Wznowienie nie weszło (odbiorca ma inną część, niż sądziliśmy).
        // Pytamy go jeszcze raz, ile faktycznie ma — sama zapowiedź odtwarza
        // też jego zgodę. Ślepe wysłanie całości od zera skończyłoby się
        // drugim monitem u odbiorcy i skasowaniem tego, co już dostał.
        reply = await client.offerFile(
            host: target.host, port: target.port, payload: offerPayload);
        if (reply != null && reply.alreadyHave) {
          delivered = true;
        } else if (reply == null || reply.accepted) {
          resumeFrom =
              (reply == null || reply.resumeFrom >= total) ? 0 : reply.resumeFrom;
          delivered = await _streamFile(
              message, file, target, name, total, hash, resumeFrom, progress);
        }
      }
      await db.setMessageStatus(
          messageId, delivered ? MessageStatus.delivered : MessageStatus.failed);
    } finally {
      _transferProgress.remove(messageId);
      transfersRevision.value++;
      progress.dispose();
    }
  }

  Future<bool> _streamFile(
    Message message,
    File file,
    Peer peer,
    String name,
    int total,
    String hash,
    int offset,
    ValueNotifier<double> progress,
  ) =>
      client.sendFile(
        host: peer.host,
        port: peer.port,
        headers: {
          headerMessageGuid: message.messageGuid,
          headerFrom: encodeIdentityHeader(identity),
          headerFileName: Uri.encodeComponent(name),
          headerFileSize: '$total',
          headerSentAt: message.createdAt.toUtc().toIso8601String(),
          headerFileSha256: hash,
          headerFileOffset: '$offset',
        },
        file: file,
        offset: offset,
        onProgress: (sent, bytes) =>
            progress.value = bytes == 0 ? 1 : sent / bytes,
      );

  /// Cache po (guid, rozmiar, czas modyfikacji): podmiana pliku pod tą samą
  /// ścieżką między ponowieniami musi dać nową sumę, inaczej odbiorca do
  /// końca świata odrzucałby transfer jako uszkodzony.
  Future<String> _hashOfSentFile(String messageGuid, File file) async {
    final stat = await file.stat();
    final key = '$messageGuid:${stat.size}:'
        '${stat.modified.millisecondsSinceEpoch}';
    return _sentFileHashes[key] ??= await _sha256OfFile(file);
  }

  /// sha256 liczone strumieniowo — plik nigdy nie ląduje w pamięci w całości.
  static Future<String> _sha256OfFile(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

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
    final inserted = await db.insertIncoming(
      conversationId: conversationId,
      messageGuid: message.messageGuid,
      body: message.text,
      sentAt: message.sentAt,
    );
    // Duplikat (ponowienie po zgubionym ACK-u) nie ma prawa zawołać
    // powiadomienia drugi raz.
    if (inserted) _onIncoming?.call(peer, message.text, conversationId);
  }

  // --- Odbiór plików --------------------------------------------------------

  /// Zapowiedź pliku: zapamiętujemy nadawcę, sprawdzamy czy tego pliku
  /// przypadkiem już nie mamy (albo nie mamy jego części), pytamy użytkownika
  /// i dopiero wtedy pozwalamy przysłać bajty.
  Future<FileOfferReply> _handleFileOffer(FileOffer offer, String fromHost) async {
    final peer = await db.upsertPeer(
      guid: offer.from.guid,
      name: offer.from.name,
      welcomeMessage: offer.from.welcomeMessage,
      host: fromHost,
      port: offer.from.tcpPort,
    );
    final conversationId = await db.ensureConversation(peer.id);

    if (await db.messageByGuid(offer.messageGuid) != null) {
      // Ten plik już mamy — nadawca nie musi przesyłać ani bajtu.
      return const FileOfferReply(accepted: true, alreadyHave: true);
    }

    final resumeFrom = _resumableBytes(offer);
    final accepted = await _offerPolicy(PendingFileOffer(
      messageGuid: offer.messageGuid,
      peerName: peer.name,
      fileName: offer.fileName,
      fileSize: offer.fileSize,
      resumeFrom: resumeFrom,
      conversationId: conversationId,
      fromVerifiedPeer: peer.verified,
    ));
    if (!accepted) {
      _discardPart(offer.messageGuid);
      return const FileOfferReply(accepted: false, reason: 'rejected');
    }

    _acceptedOffers[offer.messageGuid] = _AcceptedOffer(offer, conversationId);
    _writePartMeta(offer);
    return FileOfferReply(accepted: true, resumeFrom: resumeFrom);
  }

  /// Plik przychodzący: streaming na dysk do pliku częściowego (dopisywanie
  /// przy wznowieniu), po komplecie weryfikacja rozmiaru i sumy kontrolnej,
  /// dopiero potem rename do [receivedDir] i wpis w bazie — w katalogu
  /// odebranych nigdy nie leży połowa pliku. Zerwany transfer zostawia część
  /// do dokończenia; duplikat (retry po zgubionym ACK-u) kwitujemy bez zapisu.
  Future<FileReceiveResult> _handleIncomingFile(
      IncomingFileMeta meta, Stream<List<int>> data, String fromHost) async {
    final peer = await db.upsertPeer(
      guid: meta.from.guid,
      name: meta.from.name,
      welcomeMessage: meta.from.welcomeMessage,
      host: fromHost,
      port: meta.from.tcpPort,
    );
    final conversationId = await db.ensureConversation(peer.id);

    if (await db.messageByGuid(meta.messageGuid) != null) {
      return FileReceiveResult.ok;
    }

    // Dwa równoległe transfery tego samego pliku pisałyby do jednego pliku
    // częściowego naraz — drugi odsyłamy z 409, nadawca ponowi.
    if (!_receivingFiles.add(meta.messageGuid)) {
      return FileReceiveResult.offsetMismatch;
    }
    try {
      return await _receiveFile(meta, data, peer, conversationId);
    } finally {
      _receivingFiles.remove(meta.messageGuid);
    }
  }

  Future<FileReceiveResult> _receiveFile(IncomingFileMeta meta,
      Stream<List<int>> data, Peer peer, int conversationId) async {
    final part = _partFile(meta.messageGuid);
    var alreadyOnDisk = part.existsSync() ? part.lengthSync() : 0;

    // Stan uzgadniamy PRZED pytaniem użytkownika — inaczej pytalibyśmy
    // o plik, którego i tak nie przyjmiemy w tym zapytaniu.
    if (meta.offset != alreadyOnDisk) {
      // Nadawca chce dopisać od innego miejsca, niż mamy: część zostaje na
      // dysku (kolejna zapowiedź powie mu, ile jej jest).
      if (meta.offset != 0) return FileReceiveResult.offsetMismatch;
      // Nadawca leci od zera — nadpisujemy to, co było.
      alreadyOnDisk = 0;
    }

    var accepted = _acceptedOffers.remove(meta.messageGuid);
    if (accepted == null) {
      // Nadawca bez zapowiedzi (protokół 1) albo zgoda wygasła — pytamy
      // teraz, zanim cokolwiek zapiszemy. Odmowa = 403 bez czytania treści.
      final offer = FileOffer(
        messageGuid: meta.messageGuid,
        from: meta.from,
        fileName: meta.fileName,
        fileSize: meta.fileSize,
        sha256: meta.sha256,
        sentAt: meta.sentAt,
      );
      final ok = await _offerPolicy(PendingFileOffer(
        messageGuid: meta.messageGuid,
        peerName: peer.name,
        fileName: meta.fileName,
        fileSize: meta.fileSize,
        resumeFrom: alreadyOnDisk,
        conversationId: conversationId,
        fromVerifiedPeer: peer.verified,
      ));
      if (!ok) return FileReceiveResult.rejected;
      accepted = _AcceptedOffer(offer, conversationId);
    }

    final transfer = IncomingTransfer(
      messageGuid: meta.messageGuid,
      conversationId: conversationId,
      peerName: peer.name,
      fileName: meta.fileName,
      fileSize: meta.fileSize,
      received: alreadyOnDisk,
    );
    incomingTransfers.value = {...incomingTransfers.value, meta.messageGuid: transfer};

    final sink = part.openWrite(
        mode: meta.offset == 0 ? FileMode.write : FileMode.writeOnlyAppend);
    var received = alreadyOnDisk;
    try {
      await for (final chunk in data) {
        sink.add(chunk);
        received += chunk.length;
        transfer.receivedBytes.value = received;
      }
      await sink.flush();
    } catch (_) {
      // Zerwane połączenie — to, co doszło, zostaje na dysku do wznowienia.
      return FileReceiveResult.incomplete;
    } finally {
      try {
        await sink.close();
      } catch (_) {}
      // Notifikatora postępu świadomie nie zwalniamy: UI może go jeszcze
      // trzymać w budowanej właśnie klatce, a zwolniony rzuciłby wyjątkiem.
      incomingTransfers.value = {...incomingTransfers.value}
        ..remove(meta.messageGuid);
    }

    if (received != meta.fileSize) {
      // Więcej, niż zapowiedziano = plik do wyrzucenia; mniej = do dokończenia.
      if (received > meta.fileSize) _discardPart(meta.messageGuid);
      return FileReceiveResult.incomplete;
    }

    final expectedHash = meta.sha256 ?? accepted.offer.sha256;
    if (expectedHash != null && await _sha256OfFile(part) != expectedHash) {
      _discardPart(meta.messageGuid);
      return FileReceiveResult.checksumMismatch;
    }

    // Najpierw plik na swoim miejscu, dopiero potem wpis w bazie: gdyby
    // rename padł (brak miejsca, blokada AV), zostalibyśmy z dymkiem
    // wskazującym na nieistniejący plik.
    final targetPath = _receivedPathFor(meta.messageGuid, meta.fileName);
    try {
      part.renameSync(targetPath);
    } catch (_) {
      return FileReceiveResult.incomplete;
    }
    // Duplikat (ten sam guid) trafia w tę samą ścieżkę, więc rename tylko
    // podmienia identyczny plik — wtedy zostaje sam wpis z bazy.
    final inserted = await db.insertIncoming(
      conversationId: conversationId,
      messageGuid: meta.messageGuid,
      kind: MessageKind.file,
      body: '📎 ${meta.fileName}',
      fileName: meta.fileName,
      fileSize: received,
      filePath: targetPath,
      sentAt: meta.sentAt,
    );
    _deletePartMeta(meta.messageGuid);
    if (inserted) {
      _onIncoming?.call(peer, '📎 ${meta.fileName}', conversationId);
    }
    return FileReceiveResult.ok;
  }

  /// Decyzja użytkownika: prośba ląduje w [pendingOffers], a my czekamy na
  /// [respondToOffer]. Bez odpowiedzi w 2 minuty traktujemy to jak odmowę
  /// (nadawca zobaczy "nie dostarczono" i będzie mógł ponowić).
  Future<bool> _askUserAboutOffer(PendingFileOffer offer) {
    final decision = Completer<bool>();
    _offerDecisions[offer.messageGuid] = decision;
    pendingOffers.value = [...pendingOffers.value, offer];
    return decision.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        _resolveOffer(offer.messageGuid, false);
        return false;
      },
    );
  }

  /// Odpowiedź UI na prośbę z [pendingOffers].
  void respondToOffer(String messageGuid, {required bool accept}) =>
      _resolveOffer(messageGuid, accept);

  void _resolveOffer(String messageGuid, bool accept) {
    pendingOffers.value = pendingOffers.value
        .where((offer) => offer.messageGuid != messageGuid)
        .toList(growable: false);
    final decision = _offerDecisions.remove(messageGuid);
    if (decision != null && !decision.isCompleted) decision.complete(accept);
  }

  // --- Pliki częściowe (wznawianie) ----------------------------------------

  /// Podkatalog na transfery w trakcie — dzięki temu w katalogu odebranych
  /// leżą wyłącznie kompletne pliki.
  static const String _incompleteSubdir = '.incomplete';

  File _partFile(String messageGuid) =>
      File(p.join(receivedDir, _incompleteSubdir, '$messageGuid.part'));

  File _partMetaFile(String messageGuid) =>
      File(p.join(receivedDir, _incompleteSubdir, '$messageGuid.json'));

  String _receivedPathFor(String messageGuid, String fileName) {
    final safeName =
        p.basename(fileName).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final shortGuid =
        messageGuid.length > 8 ? messageGuid.substring(0, 8) : messageGuid;
    return p.join(receivedDir, '${shortGuid}_$safeName');
  }

  /// Ile bajtów tego pliku mamy już z poprzedniej próby. Część liczy się
  /// tylko wtedy, gdy opis obok niej zgadza się co do nazwy, rozmiaru i sumy
  /// kontrolnej — inaczej to inny plik pod tym samym guid-em i idzie do kosza.
  int _resumableBytes(FileOffer offer) {
    final part = _partFile(offer.messageGuid);
    if (!part.existsSync()) return 0;
    final meta = _readPartMeta(offer.messageGuid);
    final length = part.lengthSync();
    final matches = meta != null &&
        meta['fileName'] == offer.fileName &&
        meta['fileSize'] == offer.fileSize &&
        meta['sha256'] == offer.sha256;
    if (!matches || length > offer.fileSize) {
      _discardPart(offer.messageGuid);
      return 0;
    }
    return length;
  }

  void _writePartMeta(FileOffer offer) {
    try {
      _partMetaFile(offer.messageGuid).writeAsStringSync(jsonEncode({
        'fileName': offer.fileName,
        'fileSize': offer.fileSize,
        'sha256': offer.sha256,
        'fromGuid': offer.from.guid,
      }));
    } catch (_) {
      // Brak opisu tylko tyle, że nie wznowimy po restarcie aplikacji.
    }
  }

  Map<String, Object?>? _readPartMeta(String messageGuid) {
    try {
      final file = _partMetaFile(messageGuid);
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void _discardPart(String messageGuid) {
    try {
      final part = _partFile(messageGuid);
      if (part.existsSync()) part.deleteSync();
    } catch (_) {}
    _deletePartMeta(messageGuid);
  }

  void _deletePartMeta(String messageGuid) {
    try {
      final meta = _partMetaFile(messageGuid);
      if (meta.existsSync()) meta.deleteSync();
    } catch (_) {}
  }

  /// Porzucone kawałki (nadawca już nie wróci) nie mogą puchnąć w nieskończoność.
  void _sweepStaleParts({Duration keepFor = const Duration(days: 7)}) {
    try {
      final dir = Directory(p.join(receivedDir, _incompleteSubdir));
      if (!dir.existsSync()) return;
      final deadline = DateTime.now().subtract(keepFor);
      for (final entry in dir.listSync().whereType<File>()) {
        if (entry.statSync().modified.isBefore(deadline)) entry.deleteSync();
      }
    } catch (_) {}
  }

  // --- Odebrane pliki -------------------------------------------------------

  /// Otwiera odebrany (albo wysłany) plik systemowym skojarzeniem.
  Future<FileActionResult> openFileFromMessage(Message message) async {
    final path = message.filePath;
    if (path == null) return FileActionResult.missing;
    return FileActions.open(path);
  }

  /// Pokazuje plik w menedżerze plików (katalog, w którym leży).
  Future<FileActionResult> revealFileFromMessage(Message message) async {
    final path = message.filePath;
    if (path == null) return FileActionResult.missing;
    return FileActions.revealInFolder(path);
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
    // Nikt już nie odpowie na wiszące prośby o zgodę — odmawiamy, żeby
    // nadawcy nie czekali do timeoutu.
    for (final guid in _offerDecisions.keys.toList()) {
      _resolveOffer(guid, false);
    }
    responder.stop();
    await server.stop();
    client.dispose();
    await db.close();
  }
}
