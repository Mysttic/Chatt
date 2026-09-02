import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto.dart';
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

/// Parowanie czekające na to, aż użytkownik porówna kod z drugim ekranem.
class PendingPairing {
  final String peerGuid;
  final String peerName;

  /// Kod do porównania. Ten sam po obu stronach, o ile nikt nie siedzi
  /// w środku rozmowy.
  final String code;

  /// To urządzenie jest już sparowane, więc zgoda **podmieni** klucz sesji.
  /// `POST /pair` nie jest niczym uwierzytelniony: prośbę z cudzym guid-em
  /// i cudzą nazwą może przysłać każdy z tej sieci. Kluczem to nie grozi
  /// (kody muszą się zgodzić na obu ekranach), ale użytkownik musi zobaczyć,
  /// że nie jest to pierwsze parowanie.
  final bool alreadyPaired;

  const PendingPairing({
    required this.peerGuid,
    required this.peerName,
    required this.code,
    this.alreadyPaired = false,
  });
}

/// Parowanie w toku. Po stronie odpowiadającej wypełnia się etapami
/// ([keyPair] i [theirCommitment] przy zobowiązaniu, reszta przy odsłonięciu
/// klucza); po stronie inicjatora od razu w komplecie.
class _Pairing {
  final SimpleKeyPair? keyPair;
  final List<int>? myPublicKey;
  final String? theirCommitment;
  final DateTime expiresAt;

  List<int>? sessionKey;
  String? code;

  /// Użytkownik tego urządzenia powiedział, że kody się zgadzają.
  bool mineConfirmed = false;

  /// To samo powiedziała druga strona (przyszedł [pairConfirm]).
  bool theirsConfirmed = false;

  _Pairing({
    required this.expiresAt,
    this.keyPair,
    this.myPublicKey,
    this.theirCommitment,
    this.sessionKey,
    this.code,
  });

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

  /// Czy zapowiedź przyszła zaszyfrowana — treść musi przyjść tak samo.
  final bool sealed;

  const _AcceptedOffer(this.offer, this.conversationId, this.sealed);
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

  /// Klucz zgody na plik: nadawca + guid wiadomości.
  static String _offerKey(String senderGuid, String messageGuid) =>
      '$senderGuid|$messageGuid';

  /// Pliki właśnie odbierane — po jednym transferze na guid.
  final Set<String> _receivingFiles = {};

  /// Prośby o sparowanie, na które czeka użytkownik tego urządzenia.
  final ValueNotifier<List<PendingPairing>> pendingPairings =
      ValueNotifier(const []);

  /// Parowania w toku: guid rozmówcy -> stan uzgodnienia.
  final Map<String, _Pairing> _pairings = {};

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
      onMessage: (message, fromHost, sealed) =>
          services._handleIncoming(message, fromHost, sealed),
      onPair: (message, fromHost) => services._handlePair(message, fromHost),
      onEnvelope: (envelope) => services._openEnvelope(envelope),
      onFileOffer: (offer, fromHost, sealed) =>
          services._handleFileOffer(offer, fromHost, sealed),
      onFile: (meta, data, fromHost) =>
          services._handleIncomingFile(meta, data, fromHost),
    );
    final preferred = portOverride ?? ChattEnv.tcpPort ?? settings.tcpPort;
    final actualPort = await server.start(preferredPort: preferred);
    identity = identity.copyWith(tcpPort: actualPort);

    final responder = DiscoveryResponder(
      identity: () => services.identity,
      onPeerSeen: (peer) => services._rememberPeer(peer),
      sign: (peerGuid, nonce) => services._signDiscovery(peerGuid, nonce),
    );

    services =
        AppServices._(db, PeerClient(), server, responder, receivedDir, identity);
    services._offerPolicy = fileOfferPolicy ?? services._askUserAboutOffer;
    services._onIncoming = onIncomingMessage;
    services._sweepStaleParts();
    // Urządzenia, które przewinęły się przez sieć i nigdy nic nie napisały,
    // nie mają po co zaśmiecać listy w nieskończoność.
    await db.sweepStalePeers();

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
    final found = await DiscoveryScanner.scan(
      identity,
      onFound: onFound,
      accept: _trustDiscovered,
    );
    for (final peer in found) {
      await _rememberPeer(peer);
    }
    return found;
  }

  /// Podpis odpowiedzi discovery dla pytającego. null = nie jest z nami
  /// sparowany, więc nie mamy czym podpisać (i nie ma czego udowadniać).
  Future<String?> _signDiscovery(String peerGuid, String nonce) async {
    final peer = await db.peerByGuid(peerGuid);
    final key = peer == null ? null : await _keyForPeer(peer);
    if (key == null) return null;
    return ChattCrypto.discoveryTag(
      sessionKey: key,
      guid: identity.guid,
      tcpPort: identity.tcpPort,
      nonce: nonce,
    );
  }

  /// Czy wierzymy w tę odpowiedź. Od sparowanego urządzenia wymagamy podpisu:
  /// bez tego ktoś mógłby odpowiedzieć jego guid-em spod swojego adresu
  /// i przejąć jego miejsce w naszej liście (a stamtąd bierzemy adres, gdy
  /// rozmówcy zmieni się IP). Nieznajomych przyjmujemy jak dotąd — z nimi nie
  /// mamy wspólnego sekretu i sama obecność na liście niczego nie obiecuje.
  Future<bool> _trustDiscovered(
      DiscoveredPeer found, String? tag, String nonce) async {
    final peer = await db.peerByGuid(found.guid);
    final key = peer == null ? null : await _keyForPeer(peer);
    if (key == null) return true;
    if (tag == null) return false;
    final expected = await ChattCrypto.discoveryTag(
      sessionKey: key,
      guid: found.guid,
      tcpPort: found.tcpPort,
      nonce: nonce,
    );
    return ChattCrypto.sameTag(expected, tag);
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

  /// Ręczne usunięcie urządzenia z listy (razem z rozmową).
  Future<void> forgetPeer(Peer peer) => db.deletePeer(peer.id);

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

  // --- Parowanie przez porównanie kodu -------------------------------------

  /// Zaczyna parowanie: wysyłamy zobowiązanie do własnego klucza publicznego,
  /// dostajemy w odpowiedzi klucz drugiej strony, dopiero wtedy odsłaniamy
  /// swój. Na koniec obie strony mają ten sam kod do porównania — nasz ląduje
  /// w [pendingPairings], żeby pokazać go na ekranie.
  /// Zwraca null, gdy druga strona nie odpowiada albo zerwała rozmowę.
  Future<String?> startPairing(Peer peer) async {
    final keyPair = await ChattCrypto.newKeyPair();
    final myKey = await ChattCrypto.publicKeyOf(keyPair);

    final commit = await client.pair(
      host: peer.host,
      port: peer.port,
      payload: PairMessage(
        action: pairCommit,
        from: identity,
        commit: ChattCrypto.commitment(myKey),
      ).toJson(),
    );
    final theirKey = _decodeKey(commit.publicKey);
    if (!commit.accepted || theirKey == null) return null;

    final agreed = await ChattCrypto.agree(
      mine: keyPair,
      theirPublicKey: theirKey,
      initiatorPublicKey: myKey,
      responderPublicKey: theirKey,
    );

    final reveal = await client.pair(
      host: peer.host,
      port: peer.port,
      payload: PairMessage(
        action: pairReveal,
        from: identity,
        publicKey: base64.encode(myKey),
      ).toJson(),
    );
    if (!reveal.accepted) return null;

    _pairings[peer.guid] = _Pairing(
      sessionKey: agreed.sessionKey,
      code: agreed.code,
      expiresAt: DateTime.now().add(pairingCodeLifetime),
    );
    _showPairing(peer, agreed.code);
    return agreed.code;
  }

  /// „Kody się zgadzają" na tym urządzeniu. Klucz zapisujemy dopiero, gdy
  /// potwierdzą oba końce — inaczej jedna strona uznałaby się za sparowaną,
  /// a druga nie i cały ruch by się odbijał.
  Future<PairOutcome> confirmPairing(String peerGuid) async {
    final peer = await db.peerByGuid(peerGuid);
    final pairing = _pairings[peerGuid];
    if (peer == null || pairing == null) return PairOutcome.unreachable;
    if (pairing.expired) {
      _dropPairing(peerGuid);
      return PairOutcome.expired;
    }

    pairing.mineConfirmed = true;
    final reply = await client.pair(
      host: peer.host,
      port: peer.port,
      payload: PairMessage(action: pairConfirm, from: identity).toJson(),
    );
    if (!reply.accepted) {
      _dropPairing(peerGuid);
      return reply.outcome;
    }
    await _finishIfBothConfirmed(peer);
    return PairOutcome.accepted;
  }

  /// „Kody się nie zgadzają" albo zwykła rezygnacja. Mówimy o tym drugiej
  /// stronie, żeby nie została z wiszącą kartą.
  Future<void> cancelPairing(String peerGuid) async {
    final peer = await db.peerByGuid(peerGuid);
    _dropPairing(peerGuid);
    if (peer == null) return;
    await client.pair(
      host: peer.host,
      port: peer.port,
      payload: PairMessage(action: pairCancel, from: identity).toJson(),
    );
  }

  Future<PairReply> _handlePair(PairMessage message, String fromHost) async {
    final peer = await db.upsertPeer(
      guid: message.from.guid,
      name: message.from.name,
      welcomeMessage: message.from.welcomeMessage,
      host: fromHost,
      port: message.from.tcpPort,
    );

    switch (message.action) {
      case pairCommit:
        // Zobowiązanie inicjatora. Losujemy własną parę kluczy i odsyłamy
        // klucz publiczny; swojego klucza inicjator jeszcze nie pokazał,
        // więc nie może go dobrać pod nasz.
        if (message.commit == null) {
          return const PairReply(PairOutcome.rejected);
        }
        final keyPair = await ChattCrypto.newKeyPair();
        final myKey = await ChattCrypto.publicKeyOf(keyPair);
        _pairings[peer.guid] = _Pairing(
          keyPair: keyPair,
          myPublicKey: myKey,
          theirCommitment: message.commit,
          expiresAt: DateTime.now().add(pairingCodeLifetime),
        );
        return PairReply(PairOutcome.accepted, publicKey: base64.encode(myKey));

      case pairReveal:
        final pairing = _pairings[peer.guid];
        final theirKey = _decodeKey(message.publicKey);
        if (pairing == null || pairing.keyPair == null) {
          return const PairReply(PairOutcome.expired);
        }
        if (pairing.expired) {
          _dropPairing(peer.guid);
          return const PairReply(PairOutcome.expired);
        }
        // Klucz musi pasować do zobowiązania z pierwszego kroku.
        if (theirKey == null ||
            !ChattCrypto.sameTag(pairing.theirCommitment ?? '',
                ChattCrypto.commitment(theirKey))) {
          _dropPairing(peer.guid);
          return const PairReply(PairOutcome.rejected);
        }

        final agreed = await ChattCrypto.agree(
          mine: pairing.keyPair!,
          theirPublicKey: theirKey,
          initiatorPublicKey: theirKey,
          responderPublicKey: pairing.myPublicKey!,
        );
        pairing.sessionKey = agreed.sessionKey;
        pairing.code = agreed.code;
        _showPairing(peer, agreed.code);
        return const PairReply(PairOutcome.accepted);

      case pairConfirm:
        final pairing = _pairings[peer.guid];
        if (pairing == null || pairing.sessionKey == null) {
          return const PairReply(PairOutcome.expired);
        }
        if (pairing.expired) {
          _dropPairing(peer.guid);
          return const PairReply(PairOutcome.expired);
        }
        pairing.theirsConfirmed = true;
        await _finishIfBothConfirmed(peer);
        return const PairReply(PairOutcome.accepted);

      default: // pairCancel
        _dropPairing(peer.guid);
        return const PairReply(PairOutcome.accepted);
    }
  }

  /// Klucz zapisujemy dopiero, gdy obie strony powiedziały „zgadza się".
  Future<void> _finishIfBothConfirmed(Peer peer) async {
    final pairing = _pairings[peer.guid];
    final key = pairing?.sessionKey;
    if (pairing == null || key == null) return;
    if (!pairing.mineConfirmed || !pairing.theirsConfirmed) return;
    await db.setPeerPaired(peer.id, base64.encode(key));
    _dropPairing(peer.guid);
  }

  void _showPairing(Peer peer, String code) {
    pendingPairings.value = [
      ...pendingPairings.value.where((p) => p.peerGuid != peer.guid),
      PendingPairing(
        peerGuid: peer.guid,
        peerName: peer.name,
        code: code,
        alreadyPaired: peer.sessionKey != null,
      ),
    ];
  }

  void _dropPairing(String peerGuid) {
    _pairings.remove(peerGuid);
    _removePendingPairing(peerGuid);
  }

  // --- Szyfrowanie ruchu ----------------------------------------------------

  /// Klucz sesji do rozmowy z tym urządzeniem (null = niesparowane, ruch
  /// leci jawnym tekstem).
  Future<List<int>?> _keyForPeer(Peer peer) async {
    final key = peer.sessionKey;
    if (key == null) return null;
    try {
      return base64.decode(key);
    } catch (_) {
      return null;
    }
  }

  /// Koperta od sparowanego urządzenia: szukamy klucza po jawnym guid-zie
  /// nadawcy i odszyfrowujemy. Nie nasza albo podmieniona = null i 400.
  Future<Map<String, Object?>?> _openEnvelope(
      Map<String, Object?> envelope) async {
    final senderGuid = ChattCrypto.senderOf(envelope);
    if (senderGuid == null) return null;
    final peer = await db.peerByGuid(senderGuid);
    if (peer == null) return null;
    final key = await _keyForPeer(peer);
    if (key == null) return null;

    final opened = await ChattCrypto.open(envelope: envelope, key: key);
    if (opened == null) return null;

    // Kluczem wybieramy po jawnym "from", ale treść musi mówić to samo —
    // inaczej sparowany rozmówca mógłby pisać w cudzym imieniu.
    final inner = DeviceIdentity.fromJson(opened['from']);
    if (inner == null || inner.guid != senderGuid) return null;
    return opened;
  }

  /// Pakuje treść dla sparowanego rozmówcy; dla pozostałych zwraca ją bez
  /// zmian (zgodność ze starszymi wersjami i niesparowanymi urządzeniami).
  Future<Map<String, Object?>> _sealFor(
      Peer peer, Map<String, Object?> payload) async {
    final key = await _keyForPeer(peer);
    if (key == null) return payload;
    return ChattCrypto.seal(
        payload: payload, key: key, senderGuid: identity.guid);
  }

  static List<int>? _decodeKey(String? base64Key) {
    if (base64Key == null) return null;
    try {
      final bytes = base64.decode(base64Key);
      return bytes.length == 32 ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  void _removePendingPairing(String peerGuid) {
    pendingPairings.value = pendingPairings.value
        .where((pairing) => pairing.peerGuid != peerGuid)
        .toList(growable: false);
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
    final payload = await _sealFor(
      peer,
      messagePacket(
        messageGuid: message.messageGuid,
        from: identity,
        text: message.body,
        sentAt: message.createdAt,
      ),
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
      // Z podpisem: to jest właśnie ta ścieżka, w której podszycie się pod
      // sparowanego rozmówcę przekierowałoby do napastnika cały nasz ruch.
      found = await DiscoveryScanner.scan(identity, accept: _trustDiscovered);
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
      final sessionKey = await _keyForPeer(peer);
      final offerPayload = await _sealFor(
        peer,
        FileOffer(
          messageGuid: message.messageGuid,
          from: identity,
          fileName: name,
          fileSize: total,
          sha256: hash,
          sentAt: message.createdAt,
        ).toJson(),
      );

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

      var delivered = await _streamFile(message, file, target, name, total,
          hash, resumeFrom, progress, sessionKey);

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
              message, file, target, name, total, hash, resumeFrom, progress,
              sessionKey);
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
    List<int>? sessionKey,
  ) =>
      client.sendFile(
        host: peer.host,
        port: peer.port,
        headers: {
          headerMessageGuid: message.messageGuid,
          headerFrom: encodeIdentityHeader(identity),
          // Przy szyfrowaniu nazwa i suma kontrolna nie idą w nagłówkach —
          // odbiorca ma je z zaszyfrowanej zapowiedzi.
          headerFileName: Uri.encodeComponent(
              sessionKey == null ? name : encryptedFilePlaceholder),
          headerFileSize: '$total',
          headerSentAt: message.createdAt.toUtc().toIso8601String(),
          if (sessionKey == null) headerFileSha256: hash,
          headerFileOffset: '$offset',
          if (sessionKey != null) headerEncrypted: '1',
        },
        file: file,
        offset: offset,
        transform: sessionKey == null
            ? null
            : (data, start) => ChattCrypto.crypt(
                  data,
                  key: sessionKey,
                  nonce: ChattCrypto.fileNonce(message.messageGuid, hash),
                  startOffset: start,
                ),
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
  Future<bool> _handleIncoming(
      IncomingMessage message, String fromHost, bool sealed) async {
    if (!await _authenticated(message.from.guid, sealed)) return false;

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
    return true;
  }

  /// Ruch "od" sparowanego urządzenia musi przyjść zaszyfrowany. Inaczej
  /// ktokolwiek w sieci, znając publiczny GUID (leci w discovery), mógłby
  /// wstrzykiwać wiadomości do rozmowy oznaczonej zieloną tarczą — i przy
  /// okazji podmienić zapisany adres rozmówcy na swój.
  Future<bool> _authenticated(String senderGuid, bool sealed) async {
    if (sealed) return true;
    final peer = await db.peerByGuid(senderGuid);
    return peer?.sessionKey == null;
  }

  // --- Odbiór plików --------------------------------------------------------

  /// Zapowiedź pliku: zapamiętujemy nadawcę, sprawdzamy czy tego pliku
  /// przypadkiem już nie mamy (albo nie mamy jego części), pytamy użytkownika
  /// i dopiero wtedy pozwalamy przysłać bajty.
  Future<FileOfferReply> _handleFileOffer(
      FileOffer offer, String fromHost, bool sealed) async {
    if (!await _authenticated(offer.from.guid, sealed)) {
      return const FileOfferReply(accepted: false, reason: 'unauthenticated');
    }

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

    _acceptedOffers[_offerKey(offer.from.guid, offer.messageGuid)] =
        _AcceptedOffer(offer, conversationId, sealed);
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
    // Ten sam wymóg co przy wiadomościach: od sparowanego rozmówcy przyjmujemy
    // wyłącznie zaszyfrowaną treść. Bez tego wystarczyło pominąć nagłówek
    // x-chatt-encrypted, żeby podszyć się pod niego jawnym transferem.
    if (!await _authenticated(meta.from.guid, meta.encrypted)) {
      return FileReceiveResult.rejected;
    }

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

    // Zgoda jest związana z nadawcą, nie z samym guid-em wiadomości.
    var accepted =
        _acceptedOffers.remove(_offerKey(meta.from.guid, meta.messageGuid));
    final hadOffer = accepted != null;
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
      accepted = _AcceptedOffer(offer, conversationId, false);
    }

    // Zaszyfrowany transfer wymaga zapowiedzi: to z niej bierzemy prawdziwą
    // nazwę i sumę kontrolną (w nagłówkach ich nie ma) oraz klucz.
    // Tryb transferu musi się zgadzać z tym, na co użytkownik wyraził zgodę:
    // jawny POST /file nie może skonsumować zgody wydanej na zaszyfrowaną
    // zapowiedź (ani odwrotnie).
    if (hadOffer && accepted.sealed != meta.encrypted) {
      return FileReceiveResult.rejected;
    }

    List<int>? sessionKey;
    if (meta.encrypted) {
      sessionKey = await _keyForPeer(peer);
      if (sessionKey == null || !hadOffer) return FileReceiveResult.rejected;
    }
    final fileName = meta.encrypted ? accepted.offer.fileName : meta.fileName;

    final transfer = IncomingTransfer(
      messageGuid: meta.messageGuid,
      conversationId: conversationId,
      peerName: peer.name,
      fileName: fileName,
      fileSize: meta.fileSize,
      received: alreadyOnDisk,
    );
    incomingTransfers.value = {...incomingTransfers.value, meta.messageGuid: transfer};

    // Odszyfrowanie leci strumieniowo, od bajtu, na którym stanęliśmy.
    final content = sessionKey == null
        ? data
        : ChattCrypto.crypt(
            data,
            key: sessionKey,
            nonce: ChattCrypto.fileNonce(
                meta.messageGuid, accepted.offer.sha256 ?? ''),
            startOffset: alreadyOnDisk,
          );

    final sink = part.openWrite(
        mode: meta.offset == 0 ? FileMode.write : FileMode.writeOnlyAppend);
    var received = alreadyOnDisk;
    var sinceFlush = 0;
    try {
      await for (final chunk in content) {
        sink.add(chunk);
        received += chunk.length;
        sinceFlush += chunk.length;
        transfer.receivedBytes.value = received;
        // Bez tego cała treść potrafiła się zebrać w buforze IOSink-a, bo
        // pętla nie czekała ani chwili na dysk.
        if (sinceFlush >= 4 * 1024 * 1024) {
          await sink.flush();
          sinceFlush = 0;
        }
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

    // Przy zaszyfrowanym transferze nagłówki są nieuwierzytelnione, więc suma
    // kontrolna liczy się tylko ta z zapowiedzi (ta przyszła pod GCM).
    final expectedHash =
        meta.encrypted ? accepted.offer.sha256 : (meta.sha256 ?? accepted.offer.sha256);
    if (expectedHash != null && await _sha256OfFile(part) != expectedHash) {
      _discardPart(meta.messageGuid);
      return FileReceiveResult.checksumMismatch;
    }

    // Najpierw plik na swoim miejscu, dopiero potem wpis w bazie: gdyby
    // rename padł (brak miejsca, blokada AV), zostalibyśmy z dymkiem
    // wskazującym na nieistniejący plik.
    final targetPath = _receivedPathFor(meta.messageGuid, fileName);
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
      body: '📎 $fileName',
      fileName: fileName,
      fileSize: received,
      filePath: targetPath,
      sentAt: meta.sentAt,
    );
    _deletePartMeta(meta.messageGuid);
    if (inserted) {
      _onIncoming?.call(peer, '📎 $fileName', conversationId);
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
