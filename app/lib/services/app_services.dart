import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto.dart';
import '../core/env.dart';
import '../core/file_actions.dart';
import '../core/identity.dart';
import '../core/pair_link.dart';
import '../core/received_paths.dart';
import '../data/db.dart';
import '../data/db_open.dart';
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
  /// w środku rozmowy. Przy [fromScan] jest to odcisk klucza tego, kto
  /// zeskanował — do porównania z jego ekranem, gdyby ktoś chciał sprawdzić.
  final String code;

  /// Druga strona zeskanowała nasz kod QR i prosi o potwierdzenie z tej
  /// strony. Karta wygląda wtedy inaczej: nie ma czego porównywać, jest
  /// pytanie „czy to ty właśnie skanowałeś".
  final bool fromScan;

  /// To urządzenie jest już potwierdzone, więc zgoda **odnowi** to
  /// potwierdzenie.
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
    this.fromScan = false,
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
    this.code,
  });

  bool get expired => DateTime.now().isAfter(expiresAt);
}

/// Sesja z jednym rozmówcą: numer, klucz i moment ostatniego użycia.
/// **Nic z tego nie trafia na dysk.** To jest cała mechanika forward secrecy:
/// po restarcie albo po godzinie bezczynności sesja przestaje istnieć i nie
/// ma czego wykraść, żeby odszyfrować nagrany wcześniej ruch.
class _Session {
  final String id;
  final String peerGuid;
  final List<int> key;
  DateTime lastUsed;

  _Session({required this.id, required this.peerGuid, required this.key})
      : lastUsed = DateTime.now();

  bool get expired => DateTime.now().difference(lastUsed) > sessionLifetime;

  void touch() => lastUsed = DateTime.now();
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

  /// Sesja, w której przyszła zapowiedź. Treść pliku musi przyjść w tej
  /// samej — inaczej ktoś inny skonsumowałby cudzą zgodę.
  final String session;

  const _AcceptedOffer(this.offer, this.conversationId, this.session);
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

  /// Sesje wychodzące (guid rozmówcy -> sesja) i wszystkie sesje po numerze.
  /// Ta druga mapa obsługuje ruch przychodzący: koperta niesie tylko numer.
  final Map<String, _Session> _sessionsByPeer = {};
  final Map<String, _Session> _sessionsById = {};

  /// Uściski dłoni w locie. Dwie wysyłki naraz do tego samego rozmówcy mają
  /// dostać tę samą sesję, a nie zrobić dwa uzgodnienia obok siebie.
  final Map<String, Future<_Session?>> _handshakesInFlight = {};

  /// Para kluczy tożsamości tego urządzenia (patrz [DeviceIdentity]).
  late final SimpleKeyPair _identityKeys;

  /// sha256 wysyłanych plików — liczone raz na sesję, żeby ponowienie
  /// dużego transferu nie czytało pliku drugi raz tylko po to.
  final Map<String, String> _sentFileHashes = {};

  /// Czy klucz zaszyfrowanej bazy leży na dysku owinięty przez system
  /// (Android Keystore, Windows DPAPI). `false` znaczy, że schowek systemowy
  /// odmówił i klucz leży obok bazy jawnie — patrz [DatabaseKey].
  bool keyProtected = true;

  /// Czy responder discovery nasłuchuje. `false` znaczy, że to urządzenie nie
  /// odpowie na cudzy skan: samo znajdzie innych, ale samo zostanie znalezione
  /// dopiero po ręcznym dodaniu po adresie.
  bool discoveryListening = false;

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
    // Testy podają własny executor (baza w pamięci) i wtedy nie ma czego
    // szyfrować ani przepisywać.
    final opened = executor == null ? await openAppDatabase() : null;
    final db = ChattDb(executor ?? opened!.executor);
    final receivedDir = receivedDirOverride ?? await _defaultReceivedDir();
    Directory(receivedDir).createSync(recursive: true);
    Directory(p.join(receivedDir, incompleteSubdir)).createSync(recursive: true);

    // Tożsamość to para kluczy: identyfikator jest liczony z klucza
    // publicznego, więc losowanie GUID-a zniknęło.
    final settings = await db.ensureSettings(
      identityFactory: () async {
        final para = await ChattCrypto.newKeyPair();
        final publiczny = await ChattCrypto.publicKeyOf(para);
        return (
          base64.encode(await ChattCrypto.privateKeyOf(para)),
          ChattCrypto.guidFromPublicKey(publiczny),
        );
      },
      defaultNickname:
          nameOverride ?? ChattEnv.instanceName ?? _defaultDeviceName(),
      defaultPort: portOverride ?? ChattEnv.tcpPort ?? defaultTcpPort,
    );

    final identityKeyPair =
        await ChattCrypto.identityKeyPair(base64.decode(settings.identityKey));
    var identity = DeviceIdentity(
      guid: settings.deviceGuid,
      name: settings.nickname,
      welcomeMessage: settings.welcomeMessage,
      tcpPort: settings.tcpPort,
      publicKey: await ChattCrypto.publicKeyOf(identityKeyPair),
    );

    late final AppServices services;
    final server = ChattServer(
      identity: () => services.identity,
      onMessage: (message, fromHost, session) =>
          services._handleIncoming(message, fromHost, session),
      onPair: (message, fromHost) => services._handlePair(message, fromHost),
      onHandshake: (request, fromHost) =>
          services._handleHandshake(request, fromHost),
      onEnvelope: (session, envelope) =>
          services._openEnvelope(session, envelope),
      onFileOffer: (offer, fromHost, session) =>
          services._handleFileOffer(offer, fromHost, session),
      onFile: (meta, data, fromHost, session) =>
          services._handleIncomingFile(meta, data, fromHost, session),
    );
    final preferred = portOverride ?? ChattEnv.tcpPort ?? settings.tcpPort;
    final actualPort = await server.start(preferredPort: preferred);
    identity = identity.copyWith(tcpPort: actualPort);

    final responder = DiscoveryResponder(
      identity: () => services.identity,
      onPeerSeen: (peer) => services._rememberPeer(peer),
      sign: (pytajacy, nonce) => services._signDiscovery(pytajacy, nonce),
    );

    services =
        AppServices._(db, PeerClient(), server, responder, receivedDir, identity);
    services._identityKeys = identityKeyPair;
    services.keyProtected = opened?.keyProtected ?? true;
    services._offerPolicy = fileOfferPolicy ?? services._askUserAboutOffer;
    services._onIncoming = onIncomingMessage;
    services._sweepStaleParts();
    services._startRetention();
    // Urządzenia, które przewinęły się przez sieć i nigdy nic nie napisały,
    // nie mają po co zaśmiecać listy w nieskończoność.
    await db.sweepStalePeers();

    if (enableDiscovery) {
      try {
        await responder.start();
        services.discoveryListening = true;
      } on SocketException {
        // Port discovery zajęty albo niedostępny. Aplikacja działa dalej:
        // będzie widzieć innych po skanie, ale sama zostanie znaleziona
        // dopiero po ręcznym dodaniu po adresie.
        //
        // Ten wyjątek był tu połykany bez śladu i dzięki temu przeżył długo:
        // na Androidzie `reusePort` wywracał bind, telefon przestawał
        // odpowiadać na cudze skany, a użytkownik nie miał tego skąd
        // zobaczyć. Teraz stan wychodzi na ekran Ustawień.
        services.discoveryListening = false;
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
  Future<String?> _signDiscovery(DiscoveredPeer pytajacy, String nonce) async {
    final peer = await db.peerByGuid(pytajacy.guid);
    final ichKlucz = _peerStaticKey(peer);
    if (ichKlucz == null) return null;
    // Klucz podpisowy wychodzi z samych kluczy statycznych, więc liczy się
    // bez żywej sesji — discovery dzieje się, zanim jakakolwiek powstanie.
    final podpisowy = await ChattCrypto.discoveryKey(
        myStatic: _identityKeys, theirStatic: ichKlucz);
    return ChattCrypto.discoveryTag(
      sessionKey: podpisowy,
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
    final ichKlucz = _peerStaticKey(peer);
    if (ichKlucz == null) return true; // nieznajomy, nie ma czego sprawdzać
    if (tag == null) return false;
    final podpisowy = await ChattCrypto.discoveryKey(
        myStatic: _identityKeys, theirStatic: ichKlucz);
    final expected = await ChattCrypto.discoveryTag(
      sessionKey: podpisowy,
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

    final ichStatyczny = await _staticKeyOf(peer);
    if (ichStatyczny == null) return null;
    final kod = await ChattCrypto.agreeCode(
      mine: keyPair,
      theirPublicKey: theirKey,
      initiatorPublicKey: myKey,
      responderPublicKey: theirKey,
      initiatorStatic: identity.publicKey,
      responderStatic: ichStatyczny,
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
      code: kod,
      expiresAt: DateTime.now().add(pairingCodeLifetime),
    );
    _showPairing(peer, kod);
    return kod;
  }

  /// „Kody się zgadzają" na tym urządzeniu. Klucz zapisujemy dopiero, gdy
  /// potwierdzą oba końce — inaczej jedna strona uznałaby się za sparowaną,
  /// a druga nie i cały ruch by się odbijał.
  Future<PairOutcome> confirmPairing(String peerGuid) async {
    final peer = await db.peerByGuid(peerGuid);
    final oczekujace =
        pendingPairings.value.where((p) => p.peerGuid == peerGuid);
    // Potwierdzenie po zeskanowaniu: druga strona jest już pewna swojego
    // (widziała nasz ekran), więc tu wystarczy nasza zgoda.
    if (peer != null && oczekujace.isNotEmpty && oczekujace.first.fromScan) {
      await db.setPeerVerified(peer.id, true);
      _removePendingPairing(peerGuid);
      return PairOutcome.accepted;
    }

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
      case pairScanned:
        // Ktoś twierdzi, że zeskanował nasz kod. Sam fakt niczego nie
        // dowodzi (kod z ekranu jest jawny), więc pytamy użytkownika —
        // to on wie, czy właśnie patrzył, jak jego telefon skanuje.
        if (!_identityMatchesKey(message.from)) {
          return const PairReply(PairOutcome.rejected);
        }
        _showPairing(
          peer,
          ChattCrypto.fingerprint(message.from.publicKey),
          fromScan: true,
        );
        return const PairReply(PairOutcome.accepted);

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

        final kod = await ChattCrypto.agreeCode(
          mine: pairing.keyPair!,
          theirPublicKey: theirKey,
          initiatorPublicKey: theirKey,
          responderPublicKey: pairing.myPublicKey!,
          initiatorStatic: message.from.publicKey,
          responderStatic: identity.publicKey,
        );
        pairing.code = kod;
        _showPairing(peer, kod);
        return const PairReply(PairOutcome.accepted);

      case pairConfirm:
        final pairing = _pairings[peer.guid];
        if (pairing == null || pairing.code == null) {
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

  /// Od protokołu 5 parowanie nie ustala klucza do szyfrowania — ten bierze
  /// się z sesji i zmienia co godzinę. Parowanie odpowiada wyłącznie na
  /// pytanie „czy ten klucz należy do osoby, o której myślę", więc jego
  /// wynikiem jest sama zielona tarcza.
  Future<void> _finishIfBothConfirmed(Peer peer) async {
    final pairing = _pairings[peer.guid];
    if (pairing == null || pairing.code == null) return;
    if (!pairing.mineConfirmed || !pairing.theirsConfirmed) return;
    await db.setPeerVerified(peer.id, true);
    _dropPairing(peer.guid);
  }

  void _showPairing(Peer peer, String code, {bool fromScan = false}) {
    pendingPairings.value = [
      ...pendingPairings.value.where((p) => p.peerGuid != peer.guid),
      PendingPairing(
        peerGuid: peer.guid,
        peerName: peer.displayName,
        code: code,
        alreadyPaired: peer.verified,
        fromScan: fromScan,
      ),
    ];
  }

  /// Zeskanowano kod QR drugiego urządzenia.
  ///
  /// Skanujący widział jego ekran, więc **z jego strony** sprawa jest
  /// zamknięta: klucz na pewno pochodzi od tamtego urządzenia i tarcza robi
  /// się zielona od razu. Drugiej stronie wysyłamy tylko powiadomienie —
  /// tam potwierdza człowiek, bo kod z ekranu mógł zobaczyć ktoś jeszcze.
  ///
  /// Zwraca rozmówcę albo null, gdy pod adresem z kodu nikt nie odpowiada
  /// albo odpowiada ktoś z innym kluczem.
  Future<Peer?> pairByScan(PairLink link) async {
    if (link.guid == identity.guid) return null; // własny kod

    final info = await client.fetchInfo(link.host, link.port);
    if (info == null || !_identityMatchesKey(info) || info.guid != link.guid) {
      // Pod tym adresem nie ma urządzenia z tym kluczem — kod jest stary
      // (zmienił się adres) albo ktoś podstawił swój ekran.
      return null;
    }

    final peer = await db.upsertPeer(
      guid: link.guid,
      name: info.name,
      welcomeMessage: info.welcomeMessage,
      host: link.host,
      port: link.port,
    );
    await db.setPeerKey(peer.id, base64.encode(link.publicKey));
    await db.setPeerVerified(peer.id, true);
    _dropPairing(peer.guid);

    await client.pair(
      host: link.host,
      port: link.port,
      payload: PairMessage(action: pairScanned, from: identity).toJson(),
    );
    return db.peerByGuid(link.guid);
  }

  void _dropPairing(String peerGuid) {
    _pairings.remove(peerGuid);
    _removePendingPairing(peerGuid);
  }

  // --- Szyfrowanie ruchu ----------------------------------------------------

  /// Tożsamość musi się zgadzać ze swoim kluczem. Guid jest skrótem klucza
  /// publicznego, więc ogłoszenie cudzego identyfikatora ze swoim kluczem
  /// odpada tutaj, zanim cokolwiek policzymy.
  static bool _identityMatchesKey(DeviceIdentity who) =>
      who.hasKey && ChattCrypto.guidFromPublicKey(who.publicKey) == who.guid;

  static List<int>? _peerStaticKey(Peer? peer) {
    final key = peer?.publicKey;
    if (key == null) return null;
    final bytes = DeviceIdentity.decodeKey(key);
    return bytes.isEmpty ? null : bytes;
  }

  /// Klucz statyczny rozmówcy: z bazy, a jak go tam nie ma, to z `GET /info`.
  /// Przy okazji przypinamy go do wpisu — od tej chwili wiadomo, z czyim
  /// kluczem rozmawiamy.
  Future<List<int>?> _staticKeyOf(Peer peer) async {
    final zapisany = _peerStaticKey(peer);
    if (zapisany != null) return zapisany;

    final info = await client.fetchInfo(peer.host, peer.port);
    if (info == null || !_identityMatchesKey(info)) return null;
    if (info.guid != peer.guid) return null;
    await db.setPeerKey(peer.id, base64.encode(info.publicKey));
    return info.publicKey;
  }

  /// Sesja do rozmowy z tym urządzeniem. Żywą oddajemy od ręki, brakującą
  /// nawiązujemy — jeden uścisk dłoni na rozmówcę, nawet gdy w tej samej
  /// chwili leci kilka wiadomości.
  Future<_Session?> _sessionFor(Peer peer) {
    final istniejaca = _sessionsByPeer[peer.guid];
    if (istniejaca != null && !istniejaca.expired) {
      istniejaca.touch();
      return Future.value(istniejaca);
    }
    _dropSession(peer.guid);
    // Nawias klamrowy, nie strzałka: `Map.remove` zwraca usuwaną wartość,
    // czyli dokładnie ten future. Zwrócenie go z `whenComplete` znaczyłoby
    // „poczekaj na siebie samego" i wieszało wysyłkę na zawsze.
    return _handshakesInFlight[peer.guid] ??= _handshake(peer).whenComplete(() {
      _handshakesInFlight.remove(peer.guid);
    });
  }

  Future<_Session?> _handshake(Peer peer) async {
    final ichStatyczny = await _staticKeyOf(peer);
    if (ichStatyczny == null) return null;

    final efemeryczne = await ChattCrypto.newKeyPair();
    final mojEfemeryczny = await ChattCrypto.publicKeyOf(efemeryczne);
    final odpowiedz = await client.handshake(
      host: peer.host,
      port: peer.port,
      payload: handshakeRequest(from: identity, ephemeral: mojEfemeryczny),
    );
    if (odpowiedz == null) return null;
    // Odpowiedzieć musi ten, do kogo pisaliśmy, i to swoim kluczem.
    if (!_identityMatchesKey(odpowiedz.peer) ||
        odpowiedz.peer.guid != peer.guid) {
      return null;
    }

    final klucz = await ChattCrypto.sessionKey(
      myStatic: _identityKeys,
      myEphemeral: efemeryczne,
      theirStatic: odpowiedz.peer.publicKey,
      theirEphemeral: odpowiedz.ephemeral,
      initiator: true,
      initiatorStatic: identity.publicKey,
      responderStatic: odpowiedz.peer.publicKey,
      initiatorEphemeral: mojEfemeryczny,
      responderEphemeral: odpowiedz.ephemeral,
    );
    final sesja = _Session(
        id: odpowiedz.sessionId, peerGuid: peer.guid, key: klucz);
    _sessionsByPeer[peer.guid] = sesja;
    _sessionsById[sesja.id] = sesja;
    return sesja;
  }

  /// Druga strona prosi o sesję: sprawdzamy jej tożsamość, liczymy klucz
  /// i odsyłamy numer nowej sesji razem ze swoim kluczem efemerycznym.
  Future<Map<String, Object?>?> _handleHandshake(
      Map<String, Object?> request, String fromHost) async {
    final from = DeviceIdentity.fromJson(request['from']);
    final ichEfemeryczny = DeviceIdentity.decodeKey(request['e']);
    if (from == null ||
        ichEfemeryczny.isEmpty ||
        !_identityMatchesKey(from) ||
        from.guid == identity.guid) {
      return null;
    }

    final efemeryczne = await ChattCrypto.newKeyPair();
    final mojEfemeryczny = await ChattCrypto.publicKeyOf(efemeryczne);
    final klucz = await ChattCrypto.sessionKey(
      myStatic: _identityKeys,
      myEphemeral: efemeryczne,
      theirStatic: from.publicKey,
      theirEphemeral: ichEfemeryczny,
      initiator: false,
      initiatorStatic: from.publicKey,
      responderStatic: identity.publicKey,
      initiatorEphemeral: ichEfemeryczny,
      responderEphemeral: mojEfemeryczny,
    );

    final peer = await db.upsertPeer(
      guid: from.guid,
      name: from.name,
      welcomeMessage: from.welcomeMessage,
      host: fromHost,
      port: from.tcpPort,
    );
    await db.setPeerKey(peer.id, base64.encode(from.publicKey));

    final sesja = _Session(
        id: newSessionId(), peerGuid: from.guid, key: klucz);
    _sessionsById[sesja.id] = sesja;
    return handshakeReply(
        sessionId: sesja.id, from: identity, ephemeral: mojEfemeryczny);
  }

  void _dropSession(String peerGuid) {
    final sesja = _sessionsByPeer.remove(peerGuid);
    if (sesja != null) _sessionsById.remove(sesja.id);
  }

  /// Koperta: klucz znajdujemy po numerze sesji. Treść musi jeszcze mówić, że
  /// pisze właściciel tej sesji — inaczej rozmówca mógłby podszyć się pod
  /// kogoś innego w swojej własnej, poprawnie zaszyfrowanej wiadomości.
  Future<Map<String, Object?>?> _openEnvelope(
      String sessionId, Map<String, Object?> envelope) async {
    final sesja = _sessionsById[sessionId];
    if (sesja == null) return null;
    if (sesja.expired) {
      _sessionsById.remove(sessionId);
      _sessionsByPeer.remove(sesja.peerGuid);
      return null;
    }

    final opened = await ChattCrypto.open(envelope: envelope, key: sesja.key);
    if (opened == null) return null;

    final inner = DeviceIdentity.fromJson(opened['from']);
    if (inner == null || inner.guid != sesja.peerGuid) return null;
    sesja.touch();
    return opened;
  }

  /// Pakuje treść do koperty tej sesji. null = nie ma jak nawiązać sesji
  /// (rozmówca offline albo bez klucza, czyli w starszej wersji) — a jawnym
  /// tekstem od protokołu 5 nie wysyłamy niczego.
  Future<Map<String, Object?>?> _sealFor(
      Peer peer, Map<String, Object?> payload) async {
    final sesja = await _sessionFor(peer);
    if (sesja == null) return null;
    return ChattCrypto.seal(
        payload: payload, key: sesja.key, sessionId: sesja.id);
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

  /// Wysyłka wielu plików naraz (wybór z okna albo przeciągnięcie na okno).
  /// Idą po kolei, bo każdy z osobna pyta odbiorcę o zgodę — równoległe
  /// zapowiedzi znaczyłyby kilka pytań naraz i kilka strumieni w tej samej
  /// sesji. Katalogi odpadają same, bo [sendFile] sprawdza, czy to plik.
  Future<void> sendFiles(int conversationId, Iterable<String> paths) async {
    for (final path in paths) {
      await sendFile(conversationId, path);
    }
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

    var wynik = await _sendSealed(peer, payload);

    if (!wynik.delivered) {
      // Rozmówca mógł dostać nowy adres z DHCP — szukamy go po GUID.
      final moved = await _relocate(peer);
      if (moved != null) wynik = await _sendSealed(moved, payload);
    }

    await db.setMessageStatus(messageId,
        wynik.delivered ? MessageStatus.delivered : MessageStatus.failed);
  }

  /// Wysyłka w kopercie. Gdy odbiorca odpowie, że nie zna tej sesji (restart
  /// albo wygasła), kasujemy ją u siebie i próbujemy raz jeszcze — z punktu
  /// widzenia użytkownika nic się nie wydarzyło.
  Future<Delivery> _sendSealed(Peer peer, Map<String, Object?> payload) async {
    for (var proba = 0; proba < 2; proba++) {
      final koperta = await _sealFor(peer, payload);
      if (koperta == null) return Delivery.failed;
      final wynik = await client.sendMessage(
          host: peer.host, port: peer.port, payload: koperta);
      if (wynik != Delivery.noSession) return wynik;
      _dropSession(peer.guid);
    }
    return Delivery.failed;
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
      var target = peer;
      var sesja = await _sessionFor(target);
      if (sesja == null) {
        // Bez sesji nie ma jak wysłać — może rozmówca dostał nowy adres.
        final moved = await _relocate(target);
        if (moved == null) {
          await db.setMessageStatus(messageId, MessageStatus.failed);
          return;
        }
        target = moved;
        sesja = await _sessionFor(target);
        if (sesja == null) {
          await db.setMessageStatus(messageId, MessageStatus.failed);
          return;
        }
      }

      // Klucz pliku wychodzi z klucza sesji, a ta wygasa — stąd znacznik
      // w zapowiedzi, po którym odbiorca pozna, czy jego część transferu
      // pasuje jeszcze do tego, czym teraz szyfrujemy.
      var fileKey = await ChattCrypto.fileKey(
          sessionKey: sesja.key, messageGuid: message.messageGuid);
      Map<String, Object?> zapowiedz() => FileOffer(
            messageGuid: message.messageGuid,
            from: identity,
            fileName: name,
            fileSize: total,
            sha256: hash,
            keyEpoch: ChattCrypto.keyEpoch(fileKey),
            sentAt: message.createdAt,
          ).toJson();

      var offerPayload = await _sealFor(target, zapowiedz());
      if (offerPayload == null) {
        await db.setMessageStatus(messageId, MessageStatus.failed);
        return;
      }
      var reply = await client.offerFile(
          host: target.host, port: target.port, payload: offerPayload);

      if (reply == null) {
        // Cisza pod znanym adresem: albo sesja do odnowienia, albo rozmówca
        // dostał nowy adres z DHCP. Jedno i drugie załatwia nowa sesja.
        _dropSession(target.guid);
        final moved = await _relocate(target) ?? target;
        target = moved;
        final swieza = await _sessionFor(target);
        if (swieza != null) {
          sesja = swieza;
          fileKey = await ChattCrypto.fileKey(
              sessionKey: sesja.key, messageGuid: message.messageGuid);
          offerPayload = await _sealFor(target, zapowiedz());
          if (offerPayload != null) {
            reply = await client.offerFile(
                host: target.host, port: target.port, payload: offerPayload);
          }
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

      var wynik = await _streamFile(message, file, target, name, total, hash,
          resumeFrom, progress, fileKey, sesja.id);
      var delivered = wynik.delivered;

      if (!delivered && resumeFrom > 0) {
        // Wznowienie nie weszło (odbiorca ma inną część, niż sądziliśmy).
        // Pytamy go jeszcze raz, ile faktycznie ma — sama zapowiedź odtwarza
        // też jego zgodę. Ślepe wysłanie całości od zera skończyłoby się
        // drugim monitem u odbiorcy i skasowaniem tego, co już dostał.
        offerPayload = await _sealFor(target, zapowiedz());
        if (offerPayload == null) {
          await db.setMessageStatus(messageId, MessageStatus.failed);
          return;
        }
        reply = await client.offerFile(
            host: target.host, port: target.port, payload: offerPayload);
        if (reply != null && reply.alreadyHave) {
          delivered = true;
        } else if (reply == null || reply.accepted) {
          resumeFrom =
              (reply == null || reply.resumeFrom >= total) ? 0 : reply.resumeFrom;
          wynik = await _streamFile(message, file, target, name, total, hash,
              resumeFrom, progress, fileKey, sesja.id);
          delivered = wynik.delivered;
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

  Future<Delivery> _streamFile(
    Message message,
    File file,
    Peer peer,
    String name,
    int total,
    String hash,
    int offset,
    ValueNotifier<double> progress,
    List<int> fileKey,
    String sessionId,
  ) =>
      client.sendFile(
        host: peer.host,
        port: peer.port,
        headers: {
          headerMessageGuid: message.messageGuid,
          headerFrom: encodeIdentityHeader(identity),
          // Nazwa i suma kontrolna nie idą w nagłówkach — odbiorca ma je
          // z zaszyfrowanej zapowiedzi, więc nikt ich po drodze nie podmieni.
          headerFileName: Uri.encodeComponent(encryptedFilePlaceholder),
          headerFileSize: '$total',
          headerSentAt: message.createdAt.toUtc().toIso8601String(),
          headerFileOffset: '$offset',
          headerEncrypted: '1',
          headerSession: sessionId,
        },
        file: file,
        offset: offset,
        transform: (data, start) => ChattCrypto.crypt(
          data,
          key: fileKey,
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
      IncomingMessage message, String fromHost, String session) async {
    // Uwierzytelnienie zrobiła już koperta: treść przyszła kluczem sesji,
    // a `_openEnvelope` sprawdziło, że nadawca zgadza się z jej właścicielem.
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

  // --- Odbiór plików --------------------------------------------------------

  /// Zapowiedź pliku: zapamiętujemy nadawcę, sprawdzamy czy tego pliku
  /// przypadkiem już nie mamy (albo nie mamy jego części), pytamy użytkownika
  /// i dopiero wtedy pozwalamy przysłać bajty.
  Future<FileOfferReply> _handleFileOffer(
      FileOffer offer, String fromHost, String session) async {
    // Koperta już potwierdziła, kto pisze; tu pilnujemy tylko, żeby zapowiedź
    // nie przyszła w cudzej sesji.
    if (_sessionsById[session]?.peerGuid != offer.from.guid) {
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
    // Przyjmowanie bez pytania wymaga **obu** warunków naraz. Sama flaga bez
    // zielonej tarczy znaczyłaby „bierz pliki od każdego, kto poda się za tego
    // rozmówcę", a nazwę urządzenia każdy może sobie ustawić dowolnie.
    // Potwierdzenia nie da się podrobić bez klucza prywatnego.
    final accepted = (peer.verified && peer.autoAccept) ||
        await _offerPolicy(PendingFileOffer(
          messageGuid: offer.messageGuid,
          peerName: peer.displayName,
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
        _AcceptedOffer(offer, conversationId, session);
    _writePartMeta(offer);
    return FileOfferReply(accepted: true, resumeFrom: resumeFrom);
  }

  /// Plik przychodzący: streaming na dysk do pliku częściowego (dopisywanie
  /// przy wznowieniu), po komplecie weryfikacja rozmiaru i sumy kontrolnej,
  /// dopiero potem rename do [receivedDir] i wpis w bazie — w katalogu
  /// odebranych nigdy nie leży połowa pliku. Zerwany transfer zostawia część
  /// do dokończenia; duplikat (retry po zgubionym ACK-u) kwitujemy bez zapisu.
  Future<FileReceiveResult> _handleIncomingFile(IncomingFileMeta meta,
      Stream<List<int>> data, String fromHost, String session) async {
    // Treść pliku to surowe bajty, więc nadawcę rozpoznajemy po sesji
    // z nagłówka. Nie nasza sesja albo cudza — nie ma czego przyjmować.
    final sesja = _sessionsById[session];
    if (sesja == null || sesja.peerGuid != meta.from.guid || !meta.encrypted) {
      return FileReceiveResult.rejected;
    }
    sesja.touch();

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
      return await _receiveFile(meta, data, peer, conversationId, sesja);
    } finally {
      _receivingFiles.remove(meta.messageGuid);
    }
  }

  Future<FileReceiveResult> _receiveFile(IncomingFileMeta meta,
      Stream<List<int>> data, Peer peer, int conversationId,
      _Session sesja) async {
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
    final accepted =
        _acceptedOffers.remove(_offerKey(meta.from.guid, meta.messageGuid));
    // Od protokołu 5 każdy transfer poprzedza zapowiedź: to z niej bierzemy
    // prawdziwą nazwę, sumę kontrolną i zgodę użytkownika. Bajty bez
    // zapowiedzi albo w innej sesji niż ta zgoda nie mają czego skonsumować.
    if (accepted == null || accepted.session != sesja.id) {
      return FileReceiveResult.rejected;
    }
    final fileKey = await ChattCrypto.fileKey(
        sessionKey: sesja.key, messageGuid: meta.messageGuid);
    final fileName = accepted.offer.fileName;

    final transfer = IncomingTransfer(
      messageGuid: meta.messageGuid,
      conversationId: conversationId,
      peerName: peer.displayName,
      fileName: fileName,
      fileSize: meta.fileSize,
      received: alreadyOnDisk,
    );
    incomingTransfers.value = {...incomingTransfers.value, meta.messageGuid: transfer};

    // Odszyfrowanie leci strumieniowo, od bajtu, na którym stanęliśmy.
    final content = ChattCrypto.crypt(
      data,
      key: fileKey,
      nonce:
          ChattCrypto.fileNonce(meta.messageGuid, accepted.offer.sha256 ?? ''),
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
        // Nadawca leje więcej, niż zapowiedział. Przerywamy w locie, a nie po
        // stronie sprawdzenia na końcu: czekanie do końca strumienia znaczyło
        // pozwolenie na zapisanie całego dysku plikiem, na który zgoda
        // dotyczyła paru megabajtów.
        if (received > meta.fileSize) break;
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
    final expectedHash = accepted.offer.sha256;
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

  File _partFile(String messageGuid) =>
      File(partPath(receivedDir, messageGuid));

  File _partMetaFile(String messageGuid) =>
      File(partMetaPath(receivedDir, messageGuid));

  String _receivedPathFor(String messageGuid, String fileName) =>
      receivedFilePath(receivedDir, messageGuid, fileName);

  /// Ile bajtów tego pliku mamy już z poprzedniej próby. Część liczy się
  /// tylko wtedy, gdy opis obok niej zgadza się co do nazwy, rozmiaru i sumy
  /// kontrolnej — inaczej to inny plik pod tym samym guid-em i idzie do kosza.
  int _resumableBytes(FileOffer offer) {
    final part = _partFile(offer.messageGuid);
    if (!part.existsSync()) return 0;
    final meta = _readPartMeta(offer.messageGuid);
    final length = part.lengthSync();
    // Znacznik klucza musi się zgadzać: część zapisana w poprzedniej sesji
    // jest zaszyfrowana innym kluczem i dopisanie do niej dałoby plik, którego
    // nie da się odszyfrować w całości.
    final matches = meta != null &&
        meta['fileName'] == offer.fileName &&
        meta['fileSize'] == offer.fileSize &&
        meta['sha256'] == offer.sha256 &&
        meta['keyEpoch'] == offer.keyEpoch;
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
        'keyEpoch': offer.keyEpoch,
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
      final dir = Directory(p.join(receivedDir, incompleteSubdir));
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

  /// Zapisuje kopię odebranego pliku poza katalogiem aplikacji: w Zdjęciach
  /// albo Pobranych na Androidzie, a na pulpicie tam, gdzie wskaże użytkownik.
  Future<({SaveResult result, String? where})> saveFileFromMessage(
      Message message) async {
    final path = message.filePath;
    if (path == null) return (result: SaveResult.missing, where: null);
    return FileActions.saveCopy(path);
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

  // --- Kasowanie starych wiadomości -----------------------------------------

  Timer? _retentionTimer;
  StreamSubscription<Setting>? _retentionWatch;

  /// Pilnuje ustawionej granicy wieku wiadomości: raz przy starcie, potem po
  /// każdej zmianie ustawienia i co sześć godzin, gdyby aplikacja chodziła
  /// tygodniami bez restartu.
  void _startRetention() {
    _retentionWatch = db.watchSettings().listen(
      (settings) => applyRetention(settings.retentionDays),
      onError: (_) {},
    );
    _retentionTimer = Timer.periodic(const Duration(hours: 6), (_) async {
      final settings = await db.getSettings();
      if (settings != null) await applyRetention(settings.retentionDays);
    });
  }

  /// Kasuje wiadomości starsze niż [days] dni. Zero znaczy „nie kasuj".
  /// Zwraca liczbę usuniętych wpisów.
  Future<int> applyRetention(int days) =>
      days <= 0 ? Future.value(0) : db.deleteMessagesOlderThan(Duration(days: days));

  Future<void> dispose() async {
    // Nikt już nie odpowie na wiszące prośby o zgodę — odmawiamy, żeby
    // nadawcy nie czekali do timeoutu.
    for (final guid in _offerDecisions.keys.toList()) {
      _resolveOffer(guid, false);
    }
    _retentionTimer?.cancel();
    await _retentionWatch?.cancel();
    responder.stop();
    await server.stop();
    client.dispose();
    await db.close();
  }
}
