import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto.dart';
import '../core/env.dart';
import '../core/file_actions.dart';
import '../core/identity.dart';
import '../core/link_preview.dart';
import '../core/pair_link.dart';
import '../core/received_paths.dart';
import '../core/remote_input.dart';
import '../core/updates.dart';
import '../core/version.dart';
import '../data/db.dart';
import '../data/db_open.dart';
import '../network/bt_transport.dart';
import '../network/client.dart';
import '../network/discovery.dart';
import '../network/protocol.dart';
import '../network/server.dart';
import '../network/transport.dart';
import 'app_log.dart';
import 'typing_journal.dart';

part 'history.dart';
part 'remote_input.dart';

/// Prośba o zgodę na odbiór pliku: czeka na decyzję użytkownika.
class PendingFileOffer {
  final String messageGuid;
  final String peerName;
  final String fileName;
  final int fileSize;

  /// Ile bajtów mamy już z przerwanego wcześniej transferu (0 = od zera).
  final int resumeFrom;
  final int conversationId;

  /// Czy nadawca jest sparowany kodem. Nazwa urządzenia to tylko napis,
  /// który każdy może sobie ustawić, więc przy niesparowanym warto ostrzec.
  final bool fromVerifiedPeer;

  /// Reszta paczki, gdy pytanie dotyczy kilku plików naraz. `null` znaczy
  /// „jeden plik", czyli tyle, co było zawsze. Zgoda obejmuje wtedy wszystkie
  /// wymienione pliki i nie da się jej potem cofnąć, więc karta z pytaniem
  /// musi je wymienić.
  final FileBatch? batch;

  const PendingFileOffer({
    required this.messageGuid,
    required this.peerName,
    required this.fileName,
    required this.fileSize,
    required this.resumeFrom,
    required this.conversationId,
    this.fromVerifiedPeer = false,
    this.batch,
  });

  /// Ile plików obejmuje ta prośba: paczka tyle, ile zapowiedziała, a pytanie
  /// o pojedynczy plik jeden.
  int get fileCount => batch?.count ?? 1;

  /// Łączny rozmiar tego, o co pyta prośba.
  int get totalBytes => batch?.bytes ?? fileSize;
}

/// Co zapowiedź pliku załatwiła u odbiorcy.
///
/// [answered] mówi, że odbiorca w ogóle się odezwał, więc opis paczki do niego
/// dotarł i nie trzeba go powtarzać przy następnym pliku. [batchRejected] to
/// odmowa całej paczki: reszty nie ma po co zapowiadać.
typedef OfferOutcome = ({bool answered, bool batchRejected});

const OfferOutcome _bezOdpowiedzi = (answered: false, batchRejected: false);
const OfferOutcome _odpowiedziano = (answered: true, batchRejected: false);
const OfferOutcome _paczkaOdrzucona = (answered: true, batchRejected: true);

/// Odpowiedź na prośbę o plik.
///
/// „Brak odpowiedzi" to nie to samo co odmowa, choć jedno i drugie kończy się
/// nieprzyjęciem pliku: odmowa jest decyzją o całej paczce i zamyka ją na
/// resztę plików, a cisza znaczy tylko tyle, że nikt nie patrzył na ekran,
/// więc przy następnym pliku pytamy jeszcze raz.
enum OfferDecision { accept, reject, noAnswer }

/// Decyzja o odbiorze pliku. Domyślnie pyta użytkownika (patrz
/// [AppServices.pendingOffers]); testy i skrypty podstawiają własną.
typedef FileOfferPolicy = Future<OfferDecision> Function(PendingFileOffer offer);

/// Wołane po zapisaniu wiadomości od rozmówcy (bez duplikatów). Warstwa UI
/// decyduje, co z tym zrobić, np. powiadomienie, gdy okno jest zamknięte.
typedef IncomingMessageHook = void Function(
    Peer peer, String preview, int conversationId);

/// Zgoda przyjmuje wszystko bez pytania (dla testów i trybu bezobsługowego).
Future<OfferDecision> acceptAllFileOffers(PendingFileOffer offer) async =>
    OfferDecision.accept;

/// Odmowa dla wszystkiego (dla testów).
Future<OfferDecision> rejectAllFileOffers(PendingFileOffer offer) async =>
    OfferDecision.reject;

/// Parowanie czekające na to, aż użytkownik porówna kod z drugim ekranem.
class PendingPairing {
  final String peerGuid;
  final String peerName;

  /// Kod do porównania. Ten sam po obu stronach, o ile nikt nie siedzi
  /// w środku rozmowy. Przy [fromScan] jest to odcisk klucza tego, kto
  /// zeskanował, do porównania z jego ekranem, gdyby ktoś chciał sprawdzić.
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

/// Trwający odbiór pliku (po akceptacji), do paska postępu w czacie.
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
  /// samej: inaczej ktoś inny skonsumowałby cudzą zgodę.
  final String session;

  const _AcceptedOffer(this.offer, this.conversationId, this.session);
}

/// Jak długo zapamiętana decyzja o paczce jest jeszcze coś warta.
///
/// Zegar chodzi od ostatniego pliku tej paczki, bo pliki idą po kolei i jeden
/// duży potrafi lecieć kwadrans. Trzydzieści minut ciszy znaczy, że nadawca
/// dawno skończył albo odpadł, a zgoda nie ma wisieć otwarta do końca życia
/// procesu.
const Duration batchGrantLifetime = Duration(minutes: 30);

/// Dokąd sięga zgoda, choćby pliki szły bez przerwy. Sto plików po gigabajcie
/// zmieści się w tym z zapasem nawet na słabym Wi-Fi, a zgoda sprzed pół dnia
/// nie jest już odpowiedzią na żadne pytanie, które ktoś pamięta.
const Duration batchGrantMaxLife = Duration(hours: 6);

/// Ile decyzji o paczkach trzymamy naraz. Sufit, nie pojemność: uczciwy
/// nadawca ma jedną, a ktoś nieuczciwy nie ma jak zapchać nam pamięci.
const int _maxBatchGrants = 64;

/// Decyzja użytkownika o całej paczce plików.
///
/// Zgoda jest **z góry**, więc musi być ograniczona tym, co zapowiedziano:
/// tyle plików, tyle bajtów i te nazwy, co na karcie z pytaniem. Plik poza tym
/// spisem nie jest tym, na co ktoś się zgodził, więc wraca do zwykłego pytania.
class _BatchGrant {
  final bool accepted;

  /// Nazwy z zapowiedzi. Plik spoza spisu nie korzysta z tej zgody.
  final Set<String> names;

  /// Ile jeszcze plików i bajtów mieści się w tym, co zapowiedziano.
  int filesLeft;
  int bytesLeft;

  /// Pliki już wpuszczone tą zgodą, razem z tym, czym były. Ponowiona
  /// zapowiedź (wznowienie transferu) nie ma płacić drugi raz za to samo,
  /// ale też nie ma pod tym identyfikatorem przemycić innego pliku.
  final Map<String, ({String name, int size})> admitted = {};

  final DateTime createdAt = DateTime.now();
  DateTime lastSeen = DateTime.now();

  _BatchGrant({
    required this.accepted,
    required this.names,
    required this.filesLeft,
    required this.bytesLeft,
  });

  /// Dwa zegary. Bezczynność liczy się od ostatniego **wpuszczonego** pliku,
  /// bo paczka idzie po kolei i jeden duży leci kwadrans. Twardy kres liczy
  /// się od wydania zgody i nie da się go przesunąć niczym: zgoda sprzed
  /// pół dnia nie jest już odpowiedzią na nic.
  bool get expired {
    final teraz = DateTime.now();
    return teraz.difference(lastSeen) > batchGrantLifetime ||
        teraz.difference(createdAt) > batchGrantMaxLife;
  }
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
  /// odświeża. Bez tego pasek postępu potrafił się nie pojawić, bo dymek
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

  final Map<String, Completer<OfferDecision>> _offerDecisions = {};
  final Map<String, _AcceptedOffer> _acceptedOffers = {};

  /// Zapamiętane decyzje o paczkach, po jednej na (nadawca, paczka).
  final Map<String, _BatchGrant> _batchGrants = {};

  /// Klucz zgody na plik: nadawca + guid wiadomości.
  static String _offerKey(String senderGuid, String messageGuid) =>
      '$senderGuid|$messageGuid';

  /// Pliki właśnie odbierane: po jednym transferze na guid.
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

  /// sha256 wysyłanych plików, liczone raz na sesję, żeby ponowienie
  /// dużego transferu nie czytało pliku drugi raz tylko po to.
  final Map<String, String> _sentFileHashes = {};

  /// Czy klucz zaszyfrowanej bazy leży na dysku owinięty przez system
  /// (Android Keystore, Windows DPAPI). `false` znaczy, że schowek systemowy
  /// odmówił i klucz leży obok bazy jawnie (patrz [DatabaseKey]).
  bool keyProtected = true;

  /// Czy responder discovery nasłuchuje. `false` znaczy, że to urządzenie nie
  /// odpowie na cudzy skan: samo znajdzie innych, ale samo zostanie znalezione
  /// dopiero po ręcznym dodaniu po adresie.
  bool discoveryListening = false;

  static const _uuid = Uuid();

  /// Czy dziennik aplikacji pisze też na konsolę (patrz [start]).
  final bool _logToConsole;

  AppServices._(this.db, this.client, this.server, this.responder,
      this.receivedDir, this._identity,
      {bool logToConsole = false})
      : _logToConsole = logToConsole;

  /// Uruchamia kompletny stos. Parametry służą testom (baza w pamięci,
  /// port 0 = dowolny wolny, wyłączone discovery przy testach izolowanych).
  ///
  /// [logToConsole] kopiuje wpisy dziennika aplikacji na konsolę. Włącza to
  /// `main.dart` w buildzie debug; testy i narzędzia go nie podają, więc
  /// zostają ciche.
  static Future<AppServices> start({
    QueryExecutor? executor,
    int? portOverride,
    String? nameOverride,
    bool enableDiscovery = true,
    String? receivedDirOverride,
    FileOfferPolicy? fileOfferPolicy,
    IncomingMessageHook? onIncomingMessage,
    RemoteInputPolicy? remoteInputPolicy,
    RemoteInputSink? remoteInputSink,
    HistoryPolicy? historyPolicy,
    bool logToConsole = false,
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
      onInputSession: (request, fromHost, session) =>
          services._remoteInput.handleSession(request, fromHost, session),
      onInput: (packet, fromHost, session) =>
          services._remoteInput.handlePacket(packet, fromHost, session),
      onHistoryOffer: (message, fromHost, session) =>
          services._history.handleOffer(message, fromHost, session),
      onHistoryChunk: (chunk, fromHost, session) =>
          services._history.handleChunk(chunk, fromHost, session),
      // Zapytanie, które przyszło przed końcem startu, trafia tu, zanim
      // `services` istnieje. Wtedy rzuca samo zgłoszenie i serwer je połyka.
      onHandlerError: (path, blad, slad) => services.log.error(
          LogArea.net, 'Request handler failed: $path',
          error: blad, stack: slad),
    );
    final preferred = portOverride ?? ChattEnv.tcpPort ?? settings.tcpPort;
    final actualPort = await server.start(preferredPort: preferred);
    identity = identity.copyWith(tcpPort: actualPort);

    final responder = DiscoveryResponder(
      identity: () => services.identity,
      onPeerSeen: (peer) => services._rememberPeer(peer),
      sign: (pytajacy, nonce) => services._signDiscovery(pytajacy, nonce),
      onSocketError: (blad) => services.log.add(
        LogLevel.warning,
        LogArea.net,
        'Discovery responder socket error',
        details: describeError(blad, null),
        collapseWithin: _rzadkieZdarzenia,
      ),
    );

    services = AppServices._(
        db, PeerClient(), server, responder, receivedDir, identity,
        logToConsole: logToConsole);
    services._identityKeys = identityKeyPair;
    services.keyProtected = opened?.keyProtected ?? true;
    services._offerPolicy = fileOfferPolicy ?? services._askUserAboutOffer;
    services._onIncoming = onIncomingMessage;
    final klawiatura = services._remoteInput;
    if (remoteInputPolicy != null) klawiatura._policy = remoteInputPolicy;
    if (remoteInputSink != null) klawiatura._sink = remoteInputSink;
    if (historyPolicy != null) services._history._policy = historyPolicy;
    // Kanały natywne są jedne na proces, więc ich błędy trafiają do
    // dziennika instancji, która wstała ostatnia.
    BtChannel.onCallError = services._btCallFailed;
    RemoteInputChannel.onCallError = services._keyboardCallFailed;
    // Dodatek klawiatury wstaje z bazy bez żadnego wywołania kanału: przy
    // starcie nie ma czego podnosić, a wyłączony ma milczeć.
    klawiatura.keyboardAddon.value = settings.keyboardEnabled;
    services.typingHistory.value = settings.typingHistory;
    unawaited(services._trimLog());
    services._sweepStaleParts();
    services._startRetention();
    services._startLinkPreviews();
    await services._startTransports();
    // Pytanie o wydanie tylko wtedy, gdy discovery też jest włączone: testy
    // stawiają po kilka instancji naraz i żadna nie ma po co wychodzić w sieć.
    if (enableDiscovery) services._startUpdateChecks();
    // Urządzenia, które przewinęły się przez sieć i nigdy nic nie napisały,
    // nie mają po co zaśmiecać listy w nieskończoność.
    await db.sweepStalePeers();

    if (enableDiscovery) {
      try {
        await responder.start();
        services.discoveryListening = true;
      } on SocketException catch (blad) {
        // Port discovery zajęty albo niedostępny. Aplikacja działa dalej:
        // będzie widzieć innych po skanie, ale sama zostanie znaleziona
        // dopiero po ręcznym dodaniu po adresie.
        //
        // Ten wyjątek był tu połykany bez śladu i dzięki temu przeżył długo:
        // na Androidzie `reusePort` wywracał bind, telefon przestawał
        // odpowiadać na cudze skany, a użytkownik nie miał tego skąd
        // zobaczyć. Teraz stan wychodzi na ekran Ustawień i do dziennika.
        services.discoveryListening = false;
        services.log.warning(LogArea.net,
            'Discovery responder could not bind UDP port $discoveryPort',
            error: blad);
      }
    }
    await services._logStart(
      migrated: opened?.migrated ?? false,
      discovery: enableDiscovery,
    );
    return services;
  }

  /// Jeden wpis o tym, z czym aplikacja wstała. Bez ścieżek (w nich siedzi
  /// nazwa użytkownika) i bez kluczy.
  Future<void> _logStart({
    required bool migrated,
    required bool discovery,
  }) async {
    try {
      final ustawienia = await db.getSettings();
      String tak(bool value) => value ? 'yes' : 'no';
      String wl(bool value) => value ? 'on' : 'off';
      log.add(
        LogLevel.info,
        LogArea.app,
        'App started: Chatt $appVersion',
        details: [
          'os: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          'port: ${identity.tcpPort}',
          'discovery listening: '
              '${discovery ? tak(discoveryListening) : 'disabled'}',
          'database key protected: ${tak(keyProtected)}',
          'migrated to encrypted: ${tak(migrated)}',
          'wifi: ${wl(client.wifiOn)}',
          'bluetooth add-on: ${wl(bluetoothAddon.value)}'
              '${bluetoothAddon.value ? ', running: ${tak(bluetoothRunning.value)}' : ''}',
          'keyboard add-on: ${wl(keyboardAddon.value)}',
          'typing on this device allowed: '
              '${wl(ustawienia?.remoteInputReceive ?? false)}',
          'typing history: ${wl(typingHistory.value)}',
        ].join('\n'),
      );
    } catch (blad, slad) {
      log.error(LogArea.app, 'App started (summary unavailable)',
          error: blad, stack: slad);
    }
  }

  /// Nick przy pierwszym starcie. Android zwraca z `localHostname` po prostu
  /// "localhost", co na liście urządzeń wygląda jak błąd, więc tam lepszy jest
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
      // Android: katalog `files/` aplikacji: to jedyne miejsce, które
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
      // Error (nie Exception), a tam wystarczy katalog tymczasowy.
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
    // bez żywej sesji: discovery dzieje się, zanim jakakolwiek powstanie.
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
  /// rozmówcy zmieni się IP). Nieznajomych przyjmujemy jak dotąd, z nimi nie
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

  /// Droga, która zadziałała ostatnio. Bez tej pamięci każda wiadomość do
  /// rozmówcy osiągalnego wyłącznie przez Bluetooth czekałaby najpierw na
  /// limit czasu nieistniejącego połączenia IP.
  ///
  /// Pamiętamy sam protokół. Adres bierze się zawsze z bieżącego wiersza
  /// rozmówcy, który odświeża każdy kontakt i każde szukanie po sieci:
  /// zapamiętany adres IP po zmianie adresów w sieci prowadziłby do innego
  /// urządzenia.
  final _lastGoodProtocol = <String, PeerProtocol>{};

  /// Wszystkie drogi do rozmówcy, w kolejności próbowania: najpierw ta, która
  /// zadziałała ostatnio, potem sieć lokalna, na końcu Bluetooth. Sieć przed
  /// radiem, bo jest kilkadziesiąt razy szybsza.
  ///
  /// Trasy wyłączonego transportu w ogóle się tu nie pojawiają, więc przy
  /// wyłączonym dodatku Bluetooth radio nie jest ruszane, choćby baza
  /// pamiętała adres radia rozmówcy.
  List<PeerRoute> routesOf(Peer peer) {
    final radio = peer.btAddress;
    final candidates = <PeerRoute>[
      IpRoute(peer.host, peer.port),
      if (radio != null && radio.isNotEmpty) BluetoothRoute(radio),
    ];
    final last = _lastGoodProtocol[peer.guid];
    final ordered = last == null
        ? candidates
        : [
            ...candidates.where((route) => route.protocol == last),
            ...candidates.where((route) => route.protocol != last),
          ];
    return [
      for (final route in ordered)
        if (client.transportFor(route) != null) route,
    ];
  }

  /// Którą drogą przyszło żądanie od [guid]. Trafia do bazy, żeby rozmowa
  /// pokazywała, czym idzie, i do pamięci tras, żeby odpowiedź (potwierdzenie
  /// parowania, odpis, zgoda na plik) poszła tą samą drogą. Bez tego po
  /// parowaniu przez radio odpowiedź szłaby najpierw na stary adres IP.
  int _drogaPrzychodzaca(String guid, String fromHost) {
    final protokol = btAddressOf(fromHost) == null
        ? PeerProtocol.wifi
        : PeerProtocol.bluetooth;
    _lastGoodProtocol[guid] = protokol;
    return protokol.index;
  }

  /// Jedna trasa do rozmówcy: ta, od której zaczynamy.
  PeerRoute routeOf(Peer peer) {
    final routes = routesOf(peer);
    return routes.isEmpty ? IpRoute(peer.host, peer.port) : routes.first;
  }

  /// Robi [operacja] po kolei każdą trasą, aż któraś zadziała. Udana trasa
  /// zostaje zapamiętana i trafia do bazy, żeby interfejs mógł pokazać,
  /// którędy idzie ta rozmowa.
  Future<T> _overRoutes<T>(
    Peer peer,
    Future<T> Function(PeerRoute route) operacja,
    bool Function(T wynik) udane,
  ) async {
    final routes = routesOf(peer);
    if (routes.isEmpty) return operacja(IpRoute(peer.host, peer.port));
    late T ostatni;
    for (final route in routes) {
      ostatni = await operacja(route);
      if (!udane(ostatni)) continue;
      _lastGoodProtocol[peer.guid] = route.protocol;
      if (peer.lastProtocol != route.protocol.index) {
        unawaited(db.setPeerProtocol(peer.id, route.protocol.index));
      }
      return ostatni;
    }
    return ostatni;
  }

  /// Ręczne dodanie urządzenia po adresie: fallback, gdy broadcast nie
  /// przechodzi (izolacja AP, emulator Androida za NAT-em).
  ///
  /// Zapisujemy adres, pod którym urządzenie FAKTYCZNIE odpowiedziało, a nie
  /// port, którym się przedstawia. Przy tunelu (emulator za NAT-em, adb
  /// forward, przekierowanie portu na routerze) to są dwie różne rzeczy
  /// i tylko ten pierwszy da się połączyć.
  Future<Peer?> addPeerByAddress(String host, int port) async {
    final info = await client.fetchInfo(IpRoute(host, port));
    if (info == null || info.guid == identity.guid) return null;
    final peer = await db.upsertPeer(
      guid: info.guid,
      name: info.name,
      welcomeMessage: info.welcomeMessage,
      host: host,
      port: port,
    );
    return _przypnijKlucz(peer, info);
  }

  /// Klucz publiczny znamy już z `/info`, więc przypinamy go od razu. Bez
  /// tego świeżo dodany rozmówca straszy w panelu bezpieczeństwa brakiem
  /// szyfrowania aż do pierwszej wiadomości, choć klucz był w ręku.
  ///
  /// Przypinamy tylko wtedy, gdy tożsamość zgadza się ze swoim kluczem, i tylko
  /// gdy żadnego jeszcze nie mamy: podmianę przypiętego klucza ma zobaczyć
  /// użytkownik.
  Future<Peer> _przypnijKlucz(Peer peer, DeviceIdentity info) async {
    if (peer.publicKey != null || !_identityMatchesKey(info)) return peer;
    await db.setPeerKey(peer.id, base64.encode(info.publicKey));
    return await db.peerByGuid(peer.guid) ?? peer;
  }

  /// Ręczne usunięcie urządzenia z listy (razem z rozmową). Zgoda na pisanie,
  /// prośba o nią i własna sesja pisania do niego znikają razem z nim.
  Future<void> forgetPeer(Peer peer) {
    _remoteInput.forgetPeer(peer.guid);
    _history.forgetPeer(peer.guid);
    return db.deletePeer(peer.id);
  }

  /// Sprawdzenie obecności: czy rozmówca wciąż odpowiada pod znanym adresem.
  /// Liczy się odpowiedź od niego samego: pod starym adresem po zmianie
  /// adresów w sieci potrafi odpowiedzieć inne urządzenie.
  Future<bool> isPeerOnline(Peer peer) async {
    bool on(DeviceIdentity? info) => info != null && info.guid == peer.guid;
    return on(await _overRoutes(
      peer,
      (route) => client.fetchInfo(route, timeout: const Duration(seconds: 2)),
      on,
    ));
  }

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
  /// swój. Na koniec obie strony mają ten sam kod do porównania, nasz ląduje
  /// w [pendingPairings], żeby pokazać go na ekranie.
  /// Zwraca null, gdy druga strona nie odpowiada albo zerwała rozmowę.
  Future<String?> startPairing(Peer peer) async {
    final kto = _kto(peer);
    log.info(LogArea.pair, 'Pairing started with $kto');
    final keyPair = await ChattCrypto.newKeyPair();
    final myKey = await ChattCrypto.publicKeyOf(keyPair);

    // Jedna sprawdzona trasa na cały przebieg: zobowiązanie i odsłonięcie
    // muszą trafić do tego samego urządzenia, a odpowiedź na parowanie nie
    // mówi, kto odpowiada. Pod starym adresem potrafi stać inny Chatt.
    PeerRoute? trasa;
    for (final route in routesOf(peer)) {
      final info = await client.fetchInfo(route);
      if (info != null && info.guid == peer.guid) {
        trasa = route;
        break;
      }
    }
    if (trasa == null) {
      log.warning(LogArea.pair, 'Pairing failed: $kto unreachable');
      return null;
    }
    _lastGoodProtocol[peer.guid] = trasa.protocol;

    final commit = await client.pair(
      route: trasa,
      payload: PairMessage(
        action: pairCommit,
        from: identity,
        commit: ChattCrypto.commitment(myKey),
      ).toJson(),
    );
    final theirKey = _decodeKey(commit.publicKey);
    if (!commit.accepted || theirKey == null) {
      log.warning(LogArea.pair,
          'Pairing failed: $kto answered the commitment with ${commit.outcome.name}');
      return null;
    }

    final ichStatyczny = await _staticKeyOf(peer);
    if (ichStatyczny == null) {
      log.warning(LogArea.pair, 'Pairing failed: no public key of $kto');
      return null;
    }
    final kod = await ChattCrypto.agreeCode(
      mine: keyPair,
      theirPublicKey: theirKey,
      initiatorPublicKey: myKey,
      responderPublicKey: theirKey,
      initiatorStatic: identity.publicKey,
      responderStatic: ichStatyczny,
    );

    final reveal = await client.pair(
      route: trasa,
      payload: PairMessage(
        action: pairReveal,
        from: identity,
        publicKey: base64.encode(myKey),
      ).toJson(),
    );
    if (!reveal.accepted) {
      log.warning(LogArea.pair,
          'Pairing failed: $kto answered the key with ${reveal.outcome.name}');
      return null;
    }

    _pairings[peer.guid] = _Pairing(
      code: kod,
      expiresAt: DateTime.now().add(pairingCodeLifetime),
    );
    _showPairing(peer, kod);
    log.info(LogArea.pair, 'Pairing code shown for $kto');
    return kod;
  }

  /// „Kody się zgadzają" na tym urządzeniu. Klucz zapisujemy dopiero, gdy
  /// potwierdzą oba końce: inaczej jedna strona uznałaby się za sparowaną,
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
      log.info(LogArea.pair, 'Pairing confirmed after a scan by ${_kto(peer)}');
      return PairOutcome.accepted;
    }

    final pairing = _pairings[peerGuid];
    if (peer == null || pairing == null) {
      log.warning(LogArea.pair,
          'Pairing confirmation for ${peerLabel('', peerGuid)}: nothing to confirm');
      return PairOutcome.unreachable;
    }
    final kto = _kto(peer);
    if (pairing.expired) {
      _dropPairing(peerGuid);
      log.warning(LogArea.pair, 'Pairing with $kto expired');
      return PairOutcome.expired;
    }

    pairing.mineConfirmed = true;
    log.info(LogArea.pair, 'Pairing confirmed on this device for $kto');
    final reply = await client.pair(
      route: routeOf(peer),
      payload: PairMessage(action: pairConfirm, from: identity).toJson(),
    );
    if (!reply.accepted) {
      _dropPairing(peerGuid);
      log.warning(LogArea.pair,
          'Pairing confirmation not accepted by $kto: ${reply.outcome.name}');
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
    log.info(LogArea.pair, 'Pairing rejected on this device for ${_kto(peer)}');
    await client.pair(
      route: routeOf(peer),
      payload: PairMessage(action: pairCancel, from: identity).toJson(),
    );
  }

  Future<PairReply> _handlePair(PairMessage message, String fromHost) async {
    final peer = await db.upsertPeer(
      guid: message.from.guid,
      name: message.from.name,
      welcomeMessage: message.from.welcomeMessage,
      // „Skąd przyszło" niesie raz adres IP, a raz adres radia. Jedno nie ma
      // prawa trafić tam, gdzie spodziewane jest drugie.
      host: ipAddressOf(fromHost),
      btAddress: btAddressOf(fromHost),
      protocol: _drogaPrzychodzaca(message.from.guid, fromHost),
      port: message.from.tcpPort,
    );

    final kto = _kto(peer);
    switch (message.action) {
      case pairScanned:
        // Ktoś twierdzi, że zeskanował nasz kod. Sam fakt niczego nie
        // dowodzi (kod z ekranu jest jawny), więc pytamy użytkownika:
        // to on wie, czy właśnie patrzył, jak jego telefon skanuje.
        if (!_identityMatchesKey(message.from)) {
          log.warning(LogArea.pair,
              'Pairing by scan from $kto rejected: identity does not match its key');
          return const PairReply(PairOutcome.rejected);
        }
        _showPairing(
          peer,
          ChattCrypto.fingerprint(message.from.publicKey),
          fromScan: true,
        );
        log.info(LogArea.pair, 'Pairing by scan requested by $kto');
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
        log.info(LogArea.pair, 'Pairing started by $kto');
        return PairReply(PairOutcome.accepted, publicKey: base64.encode(myKey));

      case pairReveal:
        final pairing = _pairings[peer.guid];
        final theirKey = _decodeKey(message.publicKey);
        if (pairing == null || pairing.keyPair == null) {
          log.warning(LogArea.pair, 'Pairing key from $kto came too late');
          return const PairReply(PairOutcome.expired);
        }
        if (pairing.expired) {
          _dropPairing(peer.guid);
          log.warning(LogArea.pair, 'Pairing with $kto expired');
          return const PairReply(PairOutcome.expired);
        }
        // Klucz musi pasować do zobowiązania z pierwszego kroku.
        if (theirKey == null ||
            !ChattCrypto.sameTag(pairing.theirCommitment ?? '',
                ChattCrypto.commitment(theirKey))) {
          _dropPairing(peer.guid);
          log.warning(LogArea.pair,
              'Pairing with $kto rejected: key does not match the commitment');
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
        log.info(LogArea.pair, 'Pairing code shown for $kto');
        return const PairReply(PairOutcome.accepted);

      case pairConfirm:
        final pairing = _pairings[peer.guid];
        if (pairing == null || pairing.code == null) {
          log.warning(LogArea.pair,
              'Pairing confirmation from $kto: nothing to confirm');
          return const PairReply(PairOutcome.expired);
        }
        if (pairing.expired) {
          _dropPairing(peer.guid);
          log.warning(LogArea.pair, 'Pairing with $kto expired');
          return const PairReply(PairOutcome.expired);
        }
        pairing.theirsConfirmed = true;
        log.info(LogArea.pair, 'Pairing confirmed by $kto');
        await _finishIfBothConfirmed(peer);
        return const PairReply(PairOutcome.accepted);

      default: // pairCancel
        // Rezygnacja po drugiej stronie albo jej „kody się nie zgadzają".
        // Wpis tylko wtedy, gdy było co przerywać.
        if (_pairings.containsKey(peer.guid) ||
            pendingPairings.value.any((p) => p.peerGuid == peer.guid)) {
          log.info(LogArea.pair, 'Pairing rejected by $kto');
        }
        _dropPairing(peer.guid);
        return const PairReply(PairOutcome.accepted);
    }
  }

  /// Od protokołu 5 parowanie nie ustala klucza do szyfrowania: ten bierze
  /// się z sesji i zmienia co godzinę. Parowanie odpowiada wyłącznie na
  /// pytanie „czy ten klucz należy do osoby, o której myślę", więc jego
  /// wynikiem jest sama zielona tarcza.
  Future<void> _finishIfBothConfirmed(Peer peer) async {
    final pairing = _pairings[peer.guid];
    if (pairing == null || pairing.code == null) return;
    if (!pairing.mineConfirmed || !pairing.theirsConfirmed) return;
    await db.setPeerVerified(peer.id, true);
    _dropPairing(peer.guid);
    log.info(LogArea.pair, 'Pairing completed with ${_kto(peer)}');
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
  /// się zielona od razu. Drugiej stronie wysyłamy tylko powiadomienie:
  /// tam potwierdza człowiek, bo kod z ekranu mógł zobaczyć ktoś jeszcze.
  ///
  /// Zwraca rozmówcę albo null, gdy pod adresem z kodu nikt nie odpowiada
  /// albo odpowiada ktoś z innym kluczem.
  Future<Peer?> pairByScan(PairLink link) async {
    if (link.guid == identity.guid) return null; // własny kod

    final info = await client.fetchInfo(IpRoute(link.host, link.port));
    if (info == null || !_identityMatchesKey(info) || info.guid != link.guid) {
      // Pod tym adresem nie ma urządzenia z tym kluczem: kod jest stary
      // (zmienił się adres) albo ktoś podstawił swój ekran.
      log.warning(
          LogArea.pair,
          'Scanned pairing code of ${peerLabel('', link.guid)} did not match '
          'the device at ${link.host}:${link.port}');
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
    log.info(LogArea.pair, 'Paired by scanning the code of ${_kto(peer)}');

    await client.pair(
      route: IpRoute(link.host, link.port),
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
  /// Przy okazji przypinamy go do wpisu, od tej chwili wiadomo, z czyim
  /// kluczem rozmawiamy.
  Future<List<int>?> _staticKeyOf(Peer peer) async {
    final zapisany = _peerStaticKey(peer);
    if (zapisany != null) return zapisany;

    final info = await _overRoutes(
      peer,
      (route) => client.fetchInfo(route),
      (found) => found != null && found.guid == peer.guid,
    );
    if (info == null || !_identityMatchesKey(info)) return null;
    if (info.guid != peer.guid) return null;
    await db.setPeerKey(peer.id, base64.encode(info.publicKey));
    return info.publicKey;
  }

  /// Sesja do rozmowy z tym urządzeniem. Żywą oddajemy od ręki, brakującą
  /// nawiązujemy: jeden uścisk dłoni na rozmówcę, nawet gdy w tej samej
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
    final kto = _kto(peer);
    final ichStatyczny = await _staticKeyOf(peer);
    if (ichStatyczny == null) {
      log.warning(LogArea.net,
          'Handshake with $kto not possible: public key unavailable');
      return null;
    }

    final efemeryczne = await ChattCrypto.newKeyPair();
    final mojEfemeryczny = await ChattCrypto.publicKeyOf(efemeryczne);
    final odpowiedz = await _overRoutes(
      peer,
      (route) => client.handshake(
        route: route,
        payload: handshakeRequest(from: identity, ephemeral: mojEfemeryczny),
      ),
      // Odpowiedź innego urządzenia spod tej samej trasy to trasa nieudana:
      // pętla idzie do następnej i niczego nie zapamiętuje.
      (reply) => reply != null && reply.peer.guid == peer.guid,
    );
    if (odpowiedz == null) {
      log.warning(LogArea.net, 'Handshake with $kto failed: no reply');
      return null;
    }
    // Odpowiedzieć musi ten, do kogo pisaliśmy, i to swoim kluczem.
    if (!_identityMatchesKey(odpowiedz.peer) ||
        odpowiedz.peer.guid != peer.guid) {
      log.warning(LogArea.net,
          'Handshake with $kto rejected: reply from another identity');
      return null;
    }
    // Numer sesji wybiera odpowiadający, a numery cudzych sesji są jawne
    // w każdej kopercie. Numer, który już coś u nas znaczy, zająłby miejsce
    // cudzej sesji przychodzącej i jej ruch otwierałby się nie tym kluczem.
    if (_sessionsById.containsKey(odpowiedz.sessionId)) {
      log.warning(LogArea.net,
          'Handshake with $kto rejected: session id already in use');
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
    final droga = _lastGoodProtocol[peer.guid];
    log.info(LogArea.net,
        'Session established with $kto${droga == null ? '' : ' via ${droga.name}'}');
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
      log.warning(LogArea.net,
          'Incoming handshake rejected: invalid identity from ${logText(fromHost)}');
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
      // „Skąd przyszło" niesie raz adres IP, a raz adres radia. Jedno nie ma
      // prawa trafić tam, gdzie spodziewane jest drugie.
      host: ipAddressOf(fromHost),
      btAddress: btAddressOf(fromHost),
      protocol: _drogaPrzychodzaca(from.guid, fromHost),
      port: from.tcpPort,
    );
    await db.setPeerKey(peer.id, base64.encode(from.publicKey));

    final sesja = _Session(
        id: newSessionId(), peerGuid: from.guid, key: klucz);
    _sessionsById[sesja.id] = sesja;
    log.info(LogArea.net, 'Session accepted from ${_kto(peer)}');
    return handshakeReply(
        sessionId: sesja.id, from: identity, ephemeral: mojEfemeryczny);
  }

  void _dropSession(String peerGuid) {
    final sesja = _sessionsByPeer.remove(peerGuid);
    if (sesja != null) _sessionsById.remove(sesja.id);
  }

  /// Koperta: klucz znajdujemy po numerze sesji. Treść musi jeszcze mówić, że
  /// pisze właściciel tej sesji: inaczej rozmówca mógłby podszyć się pod
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
  /// (rozmówca offline albo bez klucza, czyli w starszej wersji), a jawnym
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
  /// statusu. Dzięki temu wiadomość nigdy nie ginie, najwyżej zostaje
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
    await _sendOneFile(conversationId, sourcePath);
  }

  Future<OfferOutcome> _sendOneFile(int conversationId, String sourcePath,
      {String? batchId, FileBatch? batch}) async {
    final file = File(sourcePath);
    if (!await file.exists()) return _bezOdpowiedzi;
    final peer = await db.peerForConversation(conversationId);
    if (peer == null) return _bezOdpowiedzi;

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
    return _deliverFile(messageId, peer, batchId: batchId, batch: batch);
  }

  /// Wysyłka wielu plików naraz (wybór z okna, przeciągnięcie na okno albo
  /// wklejenie ze schowka).
  ///
  /// Pliki idą po kolei, bo równoległe strumienie w jednej sesji tylko
  /// odbierałyby sobie pasmo. Pytanie do odbiorcy idzie za to **raz na
  /// paczkę**: pierwsza zapowiedź niesie spis nazw i łączny rozmiar, kolejne
  /// powołują się na jej identyfikator. Odmowa dotyczy całej paczki, więc
  /// reszty nawet nie zapowiadamy: każda zapowiedź to przeliczenie sumy
  /// kontrolnej całego pliku, a to przy stu filmach z telefonu są minuty
  /// czytania dysku na darmo.
  ///
  /// Paczka ma górną granicę ([maxBatchFiles]), bo spis nazw jedzie
  /// w zapowiedzi, a jedna zgoda nie ma obejmować nie wiadomo czego. Większy
  /// wybór idzie kolejnymi paczkami, każda z własnym pytaniem.
  ///
  /// Katalogi i ścieżki donikąd odpadają **przed** zapowiedzią, a nie w jej
  /// trakcie: inaczej paczka obiecałaby pliki, których nigdy nie wyśle.
  Future<void> sendFiles(int conversationId, Iterable<String> paths) async {
    final pliki = <File>[];
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) pliki.add(file);
    }

    for (var od = 0; od < pliki.length; od += maxBatchFiles) {
      final czesc = pliki.sublist(
          od, math.min(od + maxBatchFiles, pliki.length));
      // Jeden plik to nie paczka: pytanie o niego wygląda jak zawsze.
      if (czesc.length == 1) {
        await _sendOneFile(conversationId, czesc.single.path);
        continue;
      }

      final rozmiary = <int>[];
      for (final file in czesc) {
        rozmiary.add(await file.length());
      }
      final batchId = _uuid.v4();
      final batch = FileBatch(
        count: czesc.length,
        bytes: rozmiary.fold(0, (suma, rozmiar) => suma + rozmiar),
        names: czesc.map((f) => p.basename(f.path)).toList(growable: false),
      );

      // Opis paczki powtarzamy, dopóki odbiorca się nie odezwie: bez niego
      // druga zapowiedź powołuje się na paczkę, o której tamten nic nie wie.
      var opisDotarl = false;
      for (final file in czesc) {
        final wynik = await _sendOneFile(conversationId, file.path,
            batchId: batchId, batch: opisDotarl ? null : batch);
        if (wynik.batchRejected) return;
        if (wynik.answered) opisDotarl = true;
      }
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
      // Rozmówca mógł dostać nowy adres z DHCP, więc szukamy go po GUID.
      final moved = await _relocate(peer);
      if (moved != null) wynik = await _sendSealed(moved, payload);
    }

    await db.setMessageStatus(messageId,
        wynik.delivered ? MessageStatus.delivered : MessageStatus.failed);
    // Sam identyfikator wiadomości: treść nie ma prawa trafić do dziennika.
    if (wynik.delivered) {
      log.info(LogArea.net,
          'Message ${message.messageGuid} delivered to ${_kto(peer)}');
    } else {
      log.warning(LogArea.net,
          'Message ${message.messageGuid} not delivered to ${_kto(peer)}');
    }
  }

  /// Wysyłka w kopercie. Gdy odbiorca odpowie, że nie zna tej sesji (restart
  /// albo wygasła), kasujemy ją u siebie i próbujemy raz jeszcze, z punktu
  /// widzenia użytkownika nic się nie wydarzyło.
  Future<Delivery> _sendSealed(Peer peer, Map<String, Object?> payload) async {
    for (var proba = 0; proba < 2; proba++) {
      final koperta = await _sealFor(peer, payload);
      if (koperta == null) return Delivery.failed;
      final wynik = await _overRoutes(
        peer,
        (route) => client.sendMessage(route: route, payload: koperta),
        (result) => result != Delivery.failed,
      );
      if (wynik != Delivery.noSession) return wynik;
      _logStaleSession(peer);
      _dropSession(peer.guid);
    }
    return Delivery.failed;
  }

  /// Odbiorca odpowiedział 409: nie zna naszej sesji (restart, wygasła).
  void _logStaleSession(Peer peer) => log.info(LogArea.net,
      'Session unknown at ${_kto(peer)} (409), handshaking again');

  /// Zapytanie w kopercie, na które druga strona odpowiada też kopertą
  /// (zdalna klawiatura). Odpowiedź otwiera klucz sesji, w której poszło
  /// zapytanie; [reply] jest null, gdy nie przyszła albo się nie otwiera.
  /// [alive] pozwala przerwać chodzenie po trasach, gdy wynik przestał
  /// kogokolwiek obchodzić.
  ///
  /// Bez [route] zapytanie chodzi po trasach jak każde inne, a [route]
  /// w wyniku to ta, która odpowiedziała kopertą. Odmowa (403) też jest
  /// odpowiedzią: przez Wi-Fi odmówione nie idzie drugi raz radiem. Z [route]
  /// zapytanie jedzie tylko nią. 409 kończy się nowym uściskiem dłoni i jedną
  /// powtórką, z tą samą treścią.
  Future<({PeerRoute? route, int status, Map<String, Object?>? reply})>
      _exchangeSealed(
    Peer peer,
    Map<String, Object?> payload,
    Future<TransportReply> Function(
            PeerRoute route, Map<String, Object?> koperta)
        wyslij, {
    PeerRoute? route,
    bool Function()? alive,
  }) async {
    var status = -1;
    for (var proba = 0; proba < 2; proba++) {
      if (alive != null && !alive()) break;
      final sesja = await _sessionFor(peer);
      if (sesja == null) return (route: null, status: status, reply: null);
      final koperta = await ChattCrypto.seal(
          payload: payload, key: sesja.key, sessionId: sesja.id);
      PeerRoute? trasa;
      Future<({int status, Map<String, Object?>? reply})> raz(
          PeerRoute r) async {
        // Zapytanie, którego wysyłający już nie chce (wycofana prośba), nie
        // idzie następną drogą.
        if (alive != null && !alive()) return (status: -1, reply: null);
        final odp = await wyslij(r, koperta);
        final otwarta = await _openSealedReply(odp, sesja);
        if (otwarta != null) trasa = r;
        return (status: odp.status, reply: otwarta);
      }

      final wynik = route != null
          ? await raz(route)
          : await _overRoutes(
              peer,
              raz,
              // 409 i 404 też kończą chodzenie po trasach: odpowiedział
              // Chatt, a radio dałoby tę samą odpowiedź, wolniej.
              (w) => w.reply != null || w.status == 409 || w.status == 404,
            );
      status = wynik.status;
      if (wynik.status == 409) {
        _logStaleSession(peer);
        _dropSession(peer.guid);
        continue;
      }
      return (route: trasa, status: wynik.status, reply: wynik.reply);
    }
    return (route: null, status: status, reply: null);
  }

  /// Zapieczętowana odpowiedź z sesji [sesja] albo null. Odpowiedź nie może
  /// nieść `from`: tak wygląda zapytanie, i tylko po tym odbita koperta nie
  /// przejdzie za odpowiedź ani za zapytanie.
  static Future<Map<String, Object?>?> _openSealedReply(
      TransportReply odp, _Session sesja) async {
    if (odp.status != 200 && odp.status != 403) return null;
    final json = tryDecodeJsonMap(odp.body);
    if (json == null ||
        !isEncryptedEnvelope(json) ||
        sessionOfEnvelope(json) != sesja.id) {
      return null;
    }
    final opened = await ChattCrypto.open(envelope: json, key: sesja.key);
    if (opened == null || opened.containsKey('from')) return null;
    return opened;
  }

  /// Rozmówca pod zapisanym adresem nie odpowiada. Adres IP w sieci domowej
  /// zmienia się po restarcie routera, GUID nie, więc skanujemy sieć i jeśli
  /// znajdziemy to samo urządzenie gdzie indziej, zapisujemy nowy adres.
  /// Zwraca rozmówcę z aktualnym adresem albo null, gdy naprawdę go nie ma.
  Future<Peer?> _relocate(Peer peer) async {
    // Szukanie po UDP ma sens tylko wtedy, gdy w ogóle rozmawiamy przez sieć.
    // Urządzenie na samym Bluetoothcie nie ma gdzie wysłać broadcastu, a jego
    // nieudana próba kosztowała wcześniej całą wysyłkę. Liczy się przełącznik
    // sieci: rozmówca poznany przez radio ma pusty adres IP i właśnie jego
    // trzeba w sieci znaleźć.
    if (!client.wifiOn) return null;

    final kto = _kto(peer);
    final List<DiscoveredPeer> found;
    try {
      // Z podpisem: to jest właśnie ta ścieżka, w której podszycie się pod
      // sparowanego rozmówcę przekierowałoby do napastnika cały nasz ruch.
      found = await DiscoveryScanner.scan(identity, accept: _trustDiscovered);
    } catch (blad) {
      // Brak sieci, zablokowany broadcast.
      log.warning(LogArea.net, 'Looking for $kto on the network failed',
          error: blad);
      return null;
    }
    for (final device in found) {
      if (device.guid != peer.guid) continue;
      if (device.host == peer.host && device.tcpPort == peer.port) {
        // Ten sam adres, czyli problem jest gdzie indziej.
        log.info(LogArea.net,
            '$kto answers discovery at the known address ${peer.host}:${peer.port}');
        return null;
      }
      log.info(
          LogArea.net,
          '$kto moved from ${peer.host}:${peer.port} '
          'to ${device.host}:${device.tcpPort}');
      return db.upsertPeer(
        guid: device.guid,
        name: device.name,
        welcomeMessage: device.welcomeMessage,
        host: device.host,
        port: device.tcpPort,
      );
    }
    log.info(LogArea.net, '$kto not found on the network');
    return null;
  }

  /// Wysyłka pliku: najpierw zapowiedź (odbiorca decyduje, czy chce go
  /// przyjąć i od którego bajtu), potem dopiero bajty. Odmowa i zerwany
  /// transfer kończą się statusem "niedostarczone" z możliwością ponowienia:
  /// wznowienie dokłada tylko brakującą część.
  /// Zapowiedź i wysyłka jednego pliku. [batchId] i [batch] są niepuste tylko
  /// wtedy, gdy plik idzie w paczce (patrz [sendFiles]); opis paczki niesie
  /// pierwsza zapowiedź, która do odbiorcy dotarła.
  ///
  /// Z [historyId] plik jedzie jako część udostępnianej historii: zapowiedź
  /// niesie jej identyfikator, a status naszego wiersza zostaje, jaki był
  /// (ta wiadomość dawno dotarła albo przyszła od rozmówcy).
  Future<OfferOutcome> _deliverFile(int messageId, Peer peer,
      {String? batchId, FileBatch? batch, String? historyId}) async {
    final message = await db.messageById(messageId);
    final path = message?.filePath;
    if (message == null || path == null) return _bezOdpowiedzi;
    Future<void> status(MessageStatus value) async {
      if (historyId == null) await db.setMessageStatus(messageId, value);
    }

    // Do dziennika idą kierunek, rozmiar i wynik. Nazwa pliku nigdy: ona
    // potrafi powiedzieć więcej niż treść wiadomości.
    final kto = _kto(peer);
    final ktora = '(message ${message.messageGuid}'
        '${historyId == null ? '' : ', shared history'})';

    final file = File(path);
    if (!await file.exists()) {
      await status(MessageStatus.failed);
      log.warning(LogArea.file,
          'Outgoing file to $kto failed: file no longer on disk $ktora');
      return _bezOdpowiedzi;
    }

    final total = await file.length();
    final name = message.fileName ?? p.basename(path);
    final progress = _transferProgress[messageId] ??= ValueNotifier(0);
    transfersRevision.value++;
    log.info(LogArea.file, 'Outgoing file to $kto: $total bytes $ktora');
    void nieWyszlo(String powod) => log.warning(
        LogArea.file, 'Outgoing file to $kto failed: $powod $ktora');
    try {
      final hash = await _hashOfSentFile(message.messageGuid, file);
      var target = peer;
      var sesja = await _sessionFor(target);
      if (sesja == null) {
        // Bez sesji nie ma jak wysłać, może rozmówca dostał nowy adres.
        final moved = await _relocate(target);
        if (moved == null) {
          await status(MessageStatus.failed);
          nieWyszlo('no session');
          return _bezOdpowiedzi;
        }
        target = moved;
        sesja = await _sessionFor(target);
        if (sesja == null) {
          await status(MessageStatus.failed);
          nieWyszlo('no session');
          return _bezOdpowiedzi;
        }
      }

      // Klucz pliku wychodzi z klucza sesji, a ta wygasa, stąd znacznik
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
            batchId: batchId,
            batch: batch,
            history: historyId,
          ).toJson();

      var offerPayload = await _sealFor(target, zapowiedz());
      if (offerPayload == null) {
        await status(MessageStatus.failed);
        nieWyszlo('no session');
        return _bezOdpowiedzi;
      }
      var reply = await client.offerFile(
          route: routeOf(target), payload: offerPayload);

      if (reply == null) {
        // Cisza pod znanym adresem: albo sesja do odnowienia, albo rozmówca
        // dostał nowy adres z DHCP. Jedno i drugie załatwia nowa sesja.
        log.info(LogArea.file,
            'Outgoing file offer to $kto got no answer, trying a new session $ktora');
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
                route: routeOf(target), payload: offerPayload);
          }
        }
      }

      if (reply != null && !reply.accepted) {
        await status(MessageStatus.failed);
        log.info(
            LogArea.file,
            'Outgoing file declined by $kto: '
            '${logText(reply.reason ?? 'rejected')} $ktora');
        // Odmowa całej paczki, a nie tego jednego pliku: nadawca kończy
        // wysyłkę, zamiast zapowiadać po kolei resztę, której i tak nikt nie
        // przyjmie (a każda zapowiedź kosztuje przeliczenie sumy kontrolnej).
        if (reply.reason == offerRejectedBatch) return _paczkaOdrzucona;
        // Cisza na karcie: opis paczki do nikogo nie dotarł, bo nikt nie
        // podjął decyzji. Gdyby liczyła się jak odpowiedź, jedna chwila
        // nieuwagi rozbijała paczkę na tyle pytań, ile plików.
        return reply.reason == offerNoAnswer ? _bezOdpowiedzi : _odpowiedziano;
      }
      if (reply != null && reply.alreadyHave) {
        // Odbiorca ma już ten plik (zgubiony ACK), nic nie wysyłamy. Opisu
        // paczki przy tym nie zapisał (wyszedł wcześniej), więc następna
        // zapowiedź ma go powtórzyć.
        await status(MessageStatus.delivered);
        log.info(LogArea.file, 'Outgoing file already at $kto $ktora');
        return _bezOdpowiedzi;
      }

      var resumeFrom =
          (reply == null || reply.resumeFrom >= total) ? 0 : reply.resumeFrom;
      progress.value = total == 0 ? 1 : resumeFrom / total;
      if (resumeFrom > 0) {
        log.info(LogArea.file,
            'Outgoing file to $kto resumes at $resumeFrom of $total bytes $ktora');
      }

      var wynik = await _streamFile(message, file, target, name, total, hash,
          resumeFrom, progress, fileKey, sesja.id);
      var delivered = wynik.delivered;

      if (!delivered && resumeFrom > 0) {
        // Wznowienie nie weszło (odbiorca ma inną część, niż sądziliśmy).
        // Pytamy go jeszcze raz, ile faktycznie ma: sama zapowiedź odtwarza
        // też jego zgodę. Ślepe wysłanie całości od zera skończyłoby się
        // drugim monitem u odbiorcy i skasowaniem tego, co już dostał.
        log.info(LogArea.file,
            'Outgoing file to $kto: resume refused, asking again $ktora');
        offerPayload = await _sealFor(target, zapowiedz());
        if (offerPayload == null) {
          await status(MessageStatus.failed);
          nieWyszlo('no session');
          return _bezOdpowiedzi;
        }
        reply = await client.offerFile(
            route: routeOf(target), payload: offerPayload);
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
      await status(
          delivered ? MessageStatus.delivered : MessageStatus.failed);
      if (delivered) {
        log.info(LogArea.file, 'Outgoing file delivered to $kto: $total bytes $ktora');
      } else {
        nieWyszlo('transfer ${wynik.name}');
      }
      // „Opis dotarł" znaczy: odbiorca go zapisał, czyli zgodził się na tę
      // zapowiedź. Wszystko inne każe powtórzyć opis przy następnym pliku.
      return reply != null && reply.accepted
          ? _odpowiedziano
          : _bezOdpowiedzi;
    } catch (blad, slad) {
      log.error(LogArea.file, 'Outgoing file to $kto failed with an error $ktora',
          error: blad, stack: slad);
      rethrow;
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
        route: routeOf(peer),
        headers: {
          headerMessageGuid: message.messageGuid,
          headerFrom: encodeIdentityHeader(identity),
          // Nazwa i suma kontrolna nie idą w nagłówkach, odbiorca ma je
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

  /// sha256 liczone strumieniowo, plik nigdy nie ląduje w pamięci w całości.
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
      // „Skąd przyszło" niesie raz adres IP, a raz adres radia. Jedno nie ma
      // prawa trafić tam, gdzie spodziewane jest drugie.
      host: ipAddressOf(fromHost),
      btAddress: btAddressOf(fromHost),
      protocol: _drogaPrzychodzaca(message.from.guid, fromHost),
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
    log.info(
        LogArea.net,
        inserted
            ? 'Message ${message.messageGuid} received from ${_kto(peer)}'
            : 'Message ${message.messageGuid} from ${_kto(peer)} '
                'already received');
    return true;
  }

  /// Ruch "od" sparowanego urządzenia musi przyjść zaszyfrowany. Inaczej
  /// ktokolwiek w sieci, znając publiczny GUID (leci w discovery), mógłby
  /// wstrzykiwać wiadomości do rozmowy oznaczonej zieloną tarczą, i przy
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
      log.warning(
          LogArea.file,
          'Incoming file offer from ${peerLabel(offer.from.name, offer.from.guid)} '
          'refused: wrong session (message ${offer.messageGuid})');
      return const FileOfferReply(accepted: false, reason: 'unauthenticated');
    }

    final peer = await db.upsertPeer(
      guid: offer.from.guid,
      name: offer.from.name,
      welcomeMessage: offer.from.welcomeMessage,
      // „Skąd przyszło" niesie raz adres IP, a raz adres radia. Jedno nie ma
      // prawa trafić tam, gdzie spodziewane jest drugie.
      host: ipAddressOf(fromHost),
      btAddress: btAddressOf(fromHost),
      protocol: _drogaPrzychodzaca(offer.from.guid, fromHost),
      port: offer.from.tcpPort,
    );
    final conversationId = await db.ensureConversation(peer.id);

    // Kierunek, rozmiar i decyzja; nazwy pliku dziennik nie dostaje nigdy.
    void zapisz(String wynik, {bool ostrzezenie = false}) => log.add(
          ostrzezenie ? LogLevel.warning : LogLevel.info,
          LogArea.file,
          'Incoming file offer from ${_kto(peer)}: ${offer.fileSize} bytes, '
          '$wynik (message ${offer.messageGuid}'
          '${offer.history == null ? '' : ', shared history'})',
        );

    // Plik z udostępnianej historii: jego wpis już jest (przyszedł w paczce
    // wiadomości) i czeka na bajty. Zgoda na historię objęła go z góry.
    // Nie pasuje do zgody: odmowa, nigdy zwykła karta.
    if (offer.history != null) {
      final zHistorii = await _history.fileOffer(offer);
      if (zHistorii.accepted && !zHistorii.alreadyHave) {
        _acceptedOffers[_offerKey(offer.from.guid, offer.messageGuid)] =
            _AcceptedOffer(offer, conversationId, session);
        _writePartMeta(offer);
      }
      zapisz(
        !zHistorii.accepted
            ? 'refused: outside the history grant'
            : zHistorii.alreadyHave
                ? 'already here'
                : 'accepted by the history grant',
        ostrzezenie: !zHistorii.accepted,
      );
      return zHistorii;
    }

    if (await db.messageByGuid(offer.messageGuid) != null) {
      // Ten plik już mamy, nadawca nie musi przesyłać ani bajtu.
      zapisz('already here');
      return const FileOfferReply(accepted: true, alreadyHave: true);
    }

    final resumeFrom = _resumableBytes(offer);

    // Przyjmowanie bez pytania wymaga **obu** warunków naraz. Sama flaga bez
    // zielonej tarczy znaczyłaby „bierz pliki od każdego, kto poda się za tego
    // rozmówcę", a nazwę urządzenia każdy może sobie ustawić dowolnie.
    // Potwierdzenia nie da się podrobić bez klucza prywatnego.
    var accepted = peer.verified && peer.autoAccept;
    var jak = 'accepted automatically';

    // Dalszy plik paczki, o którą już pytaliśmy: decyzja jest zapamiętana,
    // ale obowiązuje tylko w granicach tego, co nadawca zapowiedział.
    final zapamietana = accepted ? null : _batchDecision(offer);
    if (zapamietana != null) {
      accepted = zapamietana;
      jak = 'accepted with its batch';
      if (!accepted) {
        _discardPart(offer.messageGuid);
        zapisz('rejected with its batch');
        return const FileOfferReply(
            accepted: false, reason: offerRejectedBatch);
      }
    }

    if (!accepted) {
      final decyzja = await _offerPolicy(PendingFileOffer(
        messageGuid: offer.messageGuid,
        peerName: peer.displayName,
        fileName: offer.fileName,
        fileSize: offer.fileSize,
        resumeFrom: resumeFrom,
        conversationId: conversationId,
        fromVerifiedPeer: peer.verified,
        batch: offer.batch,
      ));
      accepted = decyzja == OfferDecision.accept;
      jak = 'accepted';
      // Brak odpowiedzi to nie odmowa: zapamiętujemy tylko to, co ktoś
      // naprawdę kliknął, więc po dwóch minutach ciszy następny plik paczki
      // zapyta jeszcze raz, zamiast przepaść bez słowa.
      if (decyzja != OfferDecision.noAnswer) _rememberBatch(offer, accepted);

      if (!accepted) {
        _discardPart(offer.messageGuid);
        zapisz(decyzja == OfferDecision.noAnswer ? 'no answer' : 'rejected');
        return FileOfferReply(
          accepted: false,
          // Odmowa paczki zatrzymuje nadawcę; odmowa pojedynczego pliku
          // dotyczy tylko jego. Cisza nie zatrzymuje nic: nikt nie
          // zdecydował, więc następny plik ma jeszcze raz zapytać.
          // Odmowa dowolnego pliku ze znanej paczki zatrzymuje nadawcę,
          // także wtedy, gdy ta zapowiedź nie niosła już opisu. Cisza nie
          // zatrzymuje nic i **nie jest** odmową: nadawca ma po niej powtórzyć
          // opis paczki, zamiast uznać, że tamten już go zna.
          reason: switch (decyzja) {
            OfferDecision.reject when offer.batchId != null =>
              offerRejectedBatch,
            OfferDecision.noAnswer => offerNoAnswer,
            _ => 'rejected',
          },
        );
      }
    }

    _acceptedOffers[_offerKey(offer.from.guid, offer.messageGuid)] =
        _AcceptedOffer(offer, conversationId, session);
    _writePartMeta(offer);
    zapisz(resumeFrom > 0 ? '$jak, resuming at $resumeFrom bytes' : jak);
    return FileOfferReply(accepted: true, resumeFrom: resumeFrom);
  }

  static String _batchKey(String senderGuid, String batchId) =>
      '$senderGuid|$batchId';

  /// Decyzja zapamiętana dla paczki tej zapowiedzi albo `null`, gdy trzeba
  /// zapytać: nie ma takiej paczki, wygasła albo ten plik się w niej nie
  /// mieści.
  ///
  /// Zgoda z góry jest warta tyle, ile zapowiedź, na której ją wydano, więc
  /// plik spoza spisu nazw, ponad zapowiedzianą liczbę albo ponad
  /// zapowiedziane bajty wypada z paczki i wraca do zwykłego pytania. Odmowa
  /// obowiązuje bez tych warunków: „nie" znaczy nie.
  bool? _batchDecision(FileOffer offer) {
    _pruneBatchGrants();
    final batchId = offer.batchId;
    if (batchId == null) return null;
    final grant = _batchGrants[_batchKey(offer.from.guid, batchId)];
    if (grant == null) return null;
    if (!grant.accepted) return false;

    // Ponowiona zapowiedź tego samego pliku (wznowienie przerwanego transferu)
    // korzysta ze zgody, którą już raz zapłaciła, ale tylko wtedy, gdy to
    // nadal ten sam plik. Bez porównania nazwy i rozmiaru wystarczyło wysłać
    // zapowiedź czterech kilobajtów, a potem tę samą jeszcze raz z ośmioma
    // gigabajtami: identyfikator był już wpuszczony, więc nikt by nie pytał.
    final wpuszczony = grant.admitted[offer.messageGuid];
    if (wpuszczony != null) {
      if (wpuszczony.name != offer.fileName ||
          wpuszczony.size != offer.fileSize) {
        return null;
      }
      grant.lastSeen = DateTime.now();
      return true;
    }

    if (grant.filesLeft <= 0 ||
        offer.fileSize > grant.bytesLeft ||
        !grant.names.contains(offer.fileName)) {
      return null;
    }
    grant.filesLeft--;
    grant.bytesLeft -= offer.fileSize;
    grant.admitted[offer.messageGuid] =
        (name: offer.fileName, size: offer.fileSize);
    // Zegar przesuwa tylko plik, który naprawdę wszedł na tę zgodę: inaczej
    // wystarczyłoby pukać w nią co pół godziny, żeby nie wygasła nigdy.
    grant.lastSeen = DateTime.now();
    return true;
  }

  /// Zapisuje decyzję o paczce. Pierwszy plik paczki niesie jej opis i to on
  /// otwiera wpis; przy pojedynczym pliku nie ma czego zapamiętywać.
  void _rememberBatch(FileOffer offer, bool accepted) {
    final batchId = offer.batchId;
    final batch = offer.batch;
    if (batchId == null || batch == null) return;
    if (_batchGrants.length >= _maxBatchGrants) {
      // Miejsce robi najstarszy wpis. Uczciwy nadawca ma jedną paczkę naraz,
      // więc do tego sufitu dochodzi się tylko z premedytacją.
      final najstarszy = _batchGrants.entries
          .reduce((a, b) => a.value.lastSeen.isBefore(b.value.lastSeen) ? a : b);
      _batchGrants.remove(najstarszy.key);
    }
    final grant = _BatchGrant(
      accepted: accepted,
      names: batch.names.toSet(),
      filesLeft: batch.count,
      bytesLeft: batch.bytes,
    );
    // Plik, na którym padło pytanie, też liczy się do paczki. Bezwarunkowo:
    // zapowiedź niosąca opis paczki, który jej nie opisuje, w ogóle nie dojdzie
    // tutaj z paczką (patrz FileOffer.fromJson), więc nazwa i rozmiar mieszczą
    // się w spisie. Bez tego pierwszy plik jechałby za darmo, poza budżetem.
    if (accepted) {
      grant.filesLeft--;
      grant.bytesLeft -= offer.fileSize;
      grant.admitted[offer.messageGuid] =
          (name: offer.fileName, size: offer.fileSize);
    }
    _batchGrants[_batchKey(offer.from.guid, batchId)] = grant;
  }

  void _pruneBatchGrants() =>
      _batchGrants.removeWhere((_, grant) => grant.expired);

  /// Plik przychodzący: streaming na dysk do pliku częściowego (dopisywanie
  /// przy wznowieniu), po komplecie weryfikacja rozmiaru i sumy kontrolnej,
  /// dopiero potem rename do [receivedDir] i wpis w bazie, w katalogu
  /// odebranych nigdy nie leży połowa pliku. Zerwany transfer zostawia część
  /// do dokończenia; duplikat (retry po zgubionym ACK-u) kwitujemy bez zapisu.
  Future<FileReceiveResult> _handleIncomingFile(IncomingFileMeta meta,
      Stream<List<int>> data, String fromHost, String session) async {
    // Treść pliku to surowe bajty, więc nadawcę rozpoznajemy po sesji
    // z nagłówka. Nie nasza sesja albo cudza, nie ma czego przyjmować.
    final sesja = _sessionsById[session];
    if (sesja == null || sesja.peerGuid != meta.from.guid || !meta.encrypted) {
      log.warning(
          LogArea.file,
          'Incoming file from ${peerLabel(meta.from.name, meta.from.guid)} '
          'refused: no matching session (message ${meta.messageGuid})');
      return FileReceiveResult.rejected;
    }
    sesja.touch();

    final peer = await db.upsertPeer(
      guid: meta.from.guid,
      name: meta.from.name,
      welcomeMessage: meta.from.welcomeMessage,
      // „Skąd przyszło" niesie raz adres IP, a raz adres radia. Jedno nie ma
      // prawa trafić tam, gdzie spodziewane jest drugie.
      host: ipAddressOf(fromHost),
      btAddress: btAddressOf(fromHost),
      protocol: _drogaPrzychodzaca(meta.from.guid, fromHost),
      port: meta.from.tcpPort,
    );
    final conversationId = await db.ensureConversation(peer.id);

    // Plik z historii ma wpis z góry (czeka na bajty), więc „już to mamy"
    // nie dotyczy go, dopóki ten wpis nie ma pliku.
    final zHistorii = _acceptedOffers[
                _offerKey(meta.from.guid, meta.messageGuid)]
            ?.offer
            .history !=
        null;
    if (zHistorii) {
      if (await db.restoredFileAwaiting(meta.messageGuid) == null) {
        // Wpis ma już plik albo go nie ma wcale: wtedy nie ma dokąd pisać.
        final wiersz = await db.messageByGuid(meta.messageGuid);
        return wiersz?.filePath != null
            ? FileReceiveResult.ok
            : FileReceiveResult.rejected;
      }
    } else if (await db.messageByGuid(meta.messageGuid) != null) {
      return FileReceiveResult.ok;
    }

    // Dwa równoległe transfery tego samego pliku pisałyby do jednego pliku
    // częściowego naraz, drugi odsyłamy z 409, nadawca ponowi.
    if (!_receivingFiles.add(meta.messageGuid)) {
      log.info(LogArea.file,
          'Incoming file from ${_kto(peer)} already in progress (message ${meta.messageGuid})');
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
    final kto = _kto(peer);
    final ktora = '(message ${meta.messageGuid})';

    // Stan uzgadniamy PRZED pytaniem użytkownika: inaczej pytalibyśmy
    // o plik, którego i tak nie przyjmiemy w tym zapytaniu.
    if (meta.offset != alreadyOnDisk) {
      // Nadawca chce dopisać od innego miejsca, niż mamy: część zostaje na
      // dysku (kolejna zapowiedź powie mu, ile jej jest).
      if (meta.offset != 0) {
        log.info(
            LogArea.file,
            'Incoming file from $kto starts at ${meta.offset} bytes, '
            'here $alreadyOnDisk $ktora');
        return FileReceiveResult.offsetMismatch;
      }
      // Nadawca leci od zera, nadpisujemy to, co było.
      alreadyOnDisk = 0;
    }

    // Zgoda jest związana z nadawcą, nie z samym guid-em wiadomości.
    final accepted =
        _acceptedOffers.remove(_offerKey(meta.from.guid, meta.messageGuid));
    // Od protokołu 5 każdy transfer poprzedza zapowiedź: to z niej bierzemy
    // prawdziwą nazwę, sumę kontrolną i zgodę użytkownika. Bajty bez
    // zapowiedzi albo w innej sesji niż ta zgoda nie mają czego skonsumować.
    if (accepted == null || accepted.session != sesja.id) {
      log.warning(LogArea.file,
          'Incoming file from $kto refused: no accepted offer $ktora');
      return FileReceiveResult.rejected;
    }
    // Rozmiar z nagłówka rządzi zapisem na dysku (pętla niżej przerywa po
    // `meta.fileSize` bajtach), a nagłówki przy zaszyfrowanym transferze nie
    // są uwierzytelnione: pod GCM przyszła zapowiedź, nie one. Bez tego
    // porównania zgoda na jeden plik 100 kB pozwalała przysłać osiem
    // gigabajtów, a przy paczce tyle razy, ile plików w zapowiedzi.
    if (meta.fileSize != accepted.offer.fileSize) {
      log.warning(
          LogArea.file,
          'Incoming file from $kto refused: ${meta.fileSize} bytes announced, '
          '${accepted.offer.fileSize} offered $ktora');
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
          // Długi plik z historii (film przez Bluetooth) nie może przy tym
          // wygasić zgody na całą resztę.
          _history.touch(meta.from.guid, accepted.offer.history);
        }
      }
      await sink.flush();
    } catch (blad) {
      // Zerwane połączenie: to, co doszło, zostaje na dysku do wznowienia.
      log.warning(
          LogArea.file,
          'Incoming file from $kto interrupted at $received of '
          '${meta.fileSize} bytes $ktora',
          error: blad);
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
      log.warning(
          LogArea.file,
          received > meta.fileSize
              ? 'Incoming file from $kto discarded: more than '
                  '${meta.fileSize} bytes $ktora'
              : 'Incoming file from $kto incomplete: $received of '
                  '${meta.fileSize} bytes $ktora');
      return FileReceiveResult.incomplete;
    }

    // Przy zaszyfrowanym transferze nagłówki są nieuwierzytelnione, więc suma
    // kontrolna liczy się tylko ta z zapowiedzi (ta przyszła pod GCM).
    final expectedHash = accepted.offer.sha256;
    if (expectedHash != null && await _sha256OfFile(part) != expectedHash) {
      _discardPart(meta.messageGuid);
      log.warning(LogArea.file,
          'Incoming file from $kto discarded: checksum mismatch $ktora');
      return FileReceiveResult.checksumMismatch;
    }

    // Najpierw plik na swoim miejscu, dopiero potem wpis w bazie: gdyby
    // rename padł (brak miejsca, blokada AV), zostalibyśmy z dymkiem
    // wskazującym na nieistniejący plik.
    final targetPath = _receivedPathFor(meta.messageGuid, fileName);
    try {
      part.renameSync(targetPath);
    } catch (blad) {
      log.warning(LogArea.file,
          'Incoming file from $kto could not be moved into place $ktora',
          error: blad);
      return FileReceiveResult.incomplete;
    }
    // Plik z historii trafia do wpisu, który na niego czekał. Bez
    // powiadomienia: to stara rozmowa, a nie nowy plik.
    if (accepted.offer.history != null) {
      _deletePartMeta(meta.messageGuid);
      await _history.fileReceived(accepted.offer, targetPath);
      log.info(
          LogArea.file,
          'Incoming file received from $kto: $received bytes '
          '(message ${meta.messageGuid}, shared history)');
      return FileReceiveResult.ok;
    }
    // Duplikat (ten sam guid) trafia w tę samą ścieżkę, więc rename tylko
    // podmienia identyczny plik, wtedy zostaje sam wpis z bazy.
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
    log.info(LogArea.file,
        'Incoming file received from $kto: $received bytes $ktora');
    return FileReceiveResult.ok;
  }

  /// Decyzja użytkownika: prośba ląduje w [pendingOffers], a my czekamy na
  /// [respondToOffer]. Bez odpowiedzi w 2 minuty traktujemy to jak odmowę
  /// (nadawca zobaczy "nie dostarczono" i będzie mógł ponowić).
  Future<OfferDecision> _askUserAboutOffer(PendingFileOffer offer) {
    final decision = Completer<OfferDecision>();
    _offerDecisions[offer.messageGuid] = decision;
    pendingOffers.value = [...pendingOffers.value, offer];
    return decision.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        // Cisza, a nie odmowa: przy paczce następny plik zapyta jeszcze raz,
        // zamiast przepaść dlatego, że nikt nie patrzył na ekran.
        _resolveOffer(offer.messageGuid, OfferDecision.noAnswer);
        return OfferDecision.noAnswer;
      },
    );
  }

  /// Odpowiedź UI na prośbę z [pendingOffers].
  void respondToOffer(String messageGuid, {required bool accept}) =>
      _resolveOffer(messageGuid,
          accept ? OfferDecision.accept : OfferDecision.reject);

  void _resolveOffer(String messageGuid, OfferDecision decyzja) {
    pendingOffers.value = pendingOffers.value
        .where((offer) => offer.messageGuid != messageGuid)
        .toList(growable: false);
    final decision = _offerDecisions.remove(messageGuid);
    if (decision != null && !decision.isCompleted) decision.complete(decyzja);
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
  /// kontrolnej: inaczej to inny plik pod tym samym guid-em i idzie do kosza.
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

  /// Lokalne adresy IPv4, pokazywane w ustawieniach, żeby dało się ręcznie
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
      unawaited(log.trim());
      final settings = await db.getSettings();
      if (settings != null) await applyRetention(settings.retentionDays);
    });
  }

  /// Kasuje wiadomości i historię pisania starsze niż [days] dni. Zero
  /// znaczy „nie kasuj". Zwraca liczbę usuniętych wiadomości.
  Future<int> applyRetention(int days) async {
    if (days <= 0) return 0;
    final wiek = Duration(days: days);
    final usuniete = await db.deleteMessagesOlderThan(wiek);
    await db.deleteTypingOlderThan(wiek);
    return usuniete;
  }

  // --- Transporty -----------------------------------------------------------

  BluetoothTransport? _bluetooth;
  StreamSubscription<Setting>? _transportWatch;

  /// Trwające podnoszenie transportu. Bez tego dwa wołania naraz (obserwator
  /// ustawień i przełącznik z ekranu) tworzą dwa transporty, a każdy z nich
  /// odpytuje stronę natywną osobno i wyrywa drugiemu gotowe łącza:
  /// jedno z nich trafia wtedy do transportu, którego nikt nie używa.
  Future<bool>? _bluetoothStarting;

  /// Czy dodatek Bluetooth jest włączony (Ustawienia, sekcja „Dodatki").
  ///
  /// To jest jedyny włącznik całej funkcji. Przy false Bluetooth w aplikacji
  /// nie istnieje: nasłuch stoi, kanał natywny milczy, żaden ekran nie
  /// pokazuje szukania przez radio ani znacznika drogi, a sieć lokalna jest
  /// jedyną drogą i nie da się jej wyłączyć.
  final ValueNotifier<bool> bluetoothAddon = ValueNotifier(false);

  /// Czy Bluetooth naprawdę chodzi. Włączony dodatek potrafi nie wstać:
  /// wyłączone radio, brak zgody, komputer bez modułu.
  final ValueNotifier<bool> bluetoothRunning = ValueNotifier(false);

  /// Rośnie, gdy łącze Bluetooth stanie albo padnie. Lista rozmów i ekran
  /// rozmowy patrzą tutaj, żeby znacznik protokołu odświeżał się na żywo.
  final ValueNotifier<int> bluetoothRevision = ValueNotifier(0);

  /// Stan radia i zgód. Odświeżany przy każdej próbie włączenia i na żądanie
  /// z ekranu ustawień.
  final ValueNotifier<BtStatus> bluetoothStatus =
      ValueNotifier(const BtStatus());

  /// Czy ta platforma w ogóle ma kod natywny do Bluetootha.
  bool get bluetoothSupported => BtChannel.supported;

  /// Adresy, z którymi stoi teraz łącze. Po tym widać w interfejsie, że
  /// rozmowa idzie przez radio.
  List<String> get bluetoothLinks => _bluetooth?.linkedAddresses ?? const [];

  /// Czy z tym rozmówcą stoi teraz łącze Bluetooth.
  bool isLinkedByBluetooth(Peer peer) {
    final address = peer.btAddress;
    if (address == null || address.isEmpty) return false;
    return _bluetooth?.isLinked(address) ?? false;
  }

  /// Przełączniki z ustawień trafiają na żywo tam, gdzie są potrzebne.
  /// Wyłączenie dodatku zatrzymuje radio od razu, bez czekania na restart.
  Future<void> _startTransports() async {
    final settings = await db.getSettings();
    bluetoothAddon.value =
        (settings?.bluetoothEnabled ?? false) && BtChannel.supported;
    _applyWifi(settings);
    if (bluetoothAddon.value) await startBluetooth();
    // Z obserwatora idzie wyłącznie sieć. Dodatek ma jednego właściciela,
    // [setBluetoothAddon], więc spóźnione zdarzenie z bazy nie podniesie
    // radia po jego wyłączeniu.
    _transportWatch = db.watchSettings().listen(_applyWifi, onError: (_) {});
  }

  /// Sieć z ustawień. Przełącznik sieci należy do dodatku Bluetooth: bez
  /// dodatku sieć jest jedyną drogą, więc chodzi zawsze, cokolwiek leży
  /// w bazie.
  void _applyWifi(Setting? settings) {
    client.useWifi(!bluetoothAddon.value || (settings?.wifiEnabled ?? true));
  }

  /// Kolejka przełączeń dodatku. Każde czeka na koniec poprzedniego, więc
  /// szybkie „wyłącz, włącz" w trakcie podnoszenia radia kończy się tym, co
  /// kliknięto na końcu, w pamięci, w bazie i w radiu jednocześnie.
  Future<void> _addonQueue = Future.value();

  /// Włącza albo wyłącza dodatek Bluetooth. Przy włączaniu zwraca, czy radio
  /// naprawdę wstało.
  ///
  /// Wyłączenie gasi transport, zanim cokolwiek trafi do bazy, i przywraca
  /// sieć: po zniknięciu dodatku znika też przełącznik, którym dałoby się
  /// ją włączyć z powrotem.
  Future<bool> setBluetoothAddon(bool on) {
    final wynik = _addonQueue.then((_) => _setBluetoothAddon(on));
    _addonQueue = wynik.then((_) {}, onError: (_) {});
    return wynik;
  }

  Future<bool> _setBluetoothAddon(bool on) async {
    if (on && !BtChannel.supported) return false;
    bluetoothAddon.value = on;
    if (!on) {
      client.useWifi(true);
      await stopBluetooth();
      await db.saveBluetoothAddon(false);
      return true;
    }
    await db.saveBluetoothAddon(true);
    _applyWifi(await db.getSettings());
    return startBluetooth();
  }

  /// Podnosi transport Bluetooth: nasłuch RFCOMM, wykrywalność radia
  /// i odpytywanie o nowe łącza. Zwraca false, gdy się nie da, także wtedy,
  /// gdy dodatek jest wyłączony.
  ///
  /// Drugie wołanie w trakcie pierwszego czeka na jego wynik.
  Future<bool> startBluetooth() {
    final trwa = _bluetoothStarting;
    if (trwa != null) return trwa;
    if (_bluetooth != null) return Future.value(true);
    final proba = _startBluetooth();
    _bluetoothStarting = proba;
    return proba.whenComplete(() {
      _bluetoothStarting = null;
      _watchForRadio();
    });
  }

  /// Ponawia podnoszenie radia, dopóki dodatek jest włączony, a transport
  /// leży. Radio włączone w systemie albo zgoda wydana poza aplikacją
  /// podnoszą go wtedy bez otwierania ustawień.
  Timer? _bluetoothRetry;

  /// Gaśnie przy [dispose], żeby zamykana aplikacja nie zaczęła ponawiać.
  bool _closing = false;

  void _watchForRadio() {
    if (_closing || !bluetoothAddon.value || _bluetooth != null) {
      _bluetoothRetry?.cancel();
      _bluetoothRetry = null;
      return;
    }
    _bluetoothRetry ??= Timer.periodic(btRetryInterval, (_) {
      if (_closing || !bluetoothAddon.value || _bluetooth != null) {
        _watchForRadio();
        return;
      }
      unawaited(refreshBluetoothStatus());
    });
  }

  Future<bool> _startBluetooth() async {
    if (_bluetooth != null) return true;
    if (!bluetoothAddon.value || !BtChannel.supported) return false;

    final stan = await BtChannel.status();
    bluetoothStatus.value = stan;
    if (!stan.usable) {
      bluetoothRunning.value = false;
      return false;
    }

    final transport = BluetoothTransport(
      // Żądanie z łącza Bluetooth idzie tą samą drogą co z gniazda TCP:
      // ten sam routing, ci sami obsługujący, to samo szyfrowanie.
      onRequest: (request, peerAddress) =>
          server.handleBluetooth(request, peerAddress),
      onLinkChange: (address, up) => bluetoothRevision.value++,
    );
    if (!await transport.start()) {
      bluetoothRunning.value = false;
      return false;
    }
    // Dodatek zgaszony w trakcie podnoszenia: radio wstało już po decyzji,
    // że ma go nie być.
    if (!bluetoothAddon.value) {
      await transport.stop();
      bluetoothRunning.value = false;
      return false;
    }
    _bluetooth = transport;
    client.useBluetooth(transport);
    bluetoothRunning.value = true;
    bluetoothRevision.value++;
    return true;
  }

  Future<void> stopBluetooth() async {
    // Zatrzymanie w trakcie podnoszenia czeka na jego koniec: inaczej
    // zostałby transport, o którym nikt już nie pamięta, a radio dalej
    // by nasłuchiwało.
    final trwa = _bluetoothStarting;
    if (trwa != null) await trwa;
    final transport = _bluetooth;
    _bluetooth = null;
    client.useBluetooth(null);
    bluetoothRunning.value = false;
    bluetoothRevision.value++;
    _watchForRadio();
    await transport?.stop();
  }

  /// Odświeża stan radia i zgód (ekrany pytają o to przy wejściu).
  ///
  /// Przy wyłączonym dodatku nie pyta systemu o nic i oddaje ostatni znany
  /// stan. [force] jest dla przełącznika dodatku, który przed włączeniem
  /// musi sprawdzić zgodę.
  ///
  /// Gdy dodatek jest włączony, a radio dopiero teraz da się użyć
  /// (użytkownik włączył je w systemie albo wydał zgodę), transport wstaje
  /// od razu, bez przełączania dodatku.
  Future<BtStatus> refreshBluetoothStatus({bool force = false}) async {
    if (!force && !bluetoothAddon.value) return bluetoothStatus.value;
    final stan = await BtChannel.status();
    bluetoothStatus.value = stan;
    if (bluetoothAddon.value && _bluetooth == null && stan.usable) {
      unawaited(startBluetooth());
    }
    return stan;
  }

  /// Prosi o zgodę na urządzenia w pobliżu. Najpierw systemowym okienkiem,
  /// a gdy nie ma jak (użytkownik odmówił na stałe, starszy Android), ekranem
  /// ustawień aplikacji. Dotyczy Androida.
  Future<bool> askForBluetoothPermission() async {
    if (await BtChannel.requestPermission()) return true;
    return BtChannel.openSettings();
  }

  /// Otwiera ekran zgód w ustawieniach systemu. Dotyczy Androida.
  Future<bool> openBluetoothSettings() => BtChannel.openSettings();

  /// Otwiera systemowy ekran lokalizacji. Bez włączonych usług lokalizacji
  /// Android nie oddaje wyników wyszukiwania Bluetooth, choć do samego
  /// połączenia nie są potrzebne.
  Future<bool> openLocationSettings() => BtChannel.openLocationSettings();

  /// Pokazuje ten telefon urządzeniom w pobliżu na dwie minuty, przez
  /// systemowe okienko z pytaniem. Bez tego drugi telefon nie znajdzie go
  /// szukaniem: Android jest widoczny tylko przy otwartym ekranie parowania.
  /// Dotyczy Androida; przy wyłączonym dodatku albo niedziałającym radiu nie
  /// dociera do kanału.
  Future<bool> showThisDeviceNearby() async {
    if (!bluetoothAddon.value || _bluetooth == null) return false;
    return BtChannel.showSelf();
  }

  /// Szuka Chatta po Bluetoothcie.
  ///
  /// Radio nie umie powiedzieć, kto jest Chattem: mówi tylko, jakie
  /// urządzenia są w pobliżu. Rozstrzyga dopiero próba połączenia pod naszym
  /// numerem usługi i zapytanie o `/info`, dokładnie jak przy ręcznym
  /// dodawaniu po adresie IP. Urządzenia bez Chatta odpadają od razu, bo nie
  /// mają takiego wpisu w SDP.
  ///
  /// Wyszukiwanie zagłusza łącze na cały czas trwania, więc nie robimy tego
  /// samo z siebie: pyta o to użytkownik z ekranu „W pobliżu".
  Future<List<Peer>> scanBluetooth({
    void Function(Peer peer)? onFound,
    /// Każde urządzenie, które zobaczyło radio, jeszcze przed sprawdzeniem,
    /// czy stoi pod nim Chatt. Po tym widać różnicę między „nie widzę
    /// komputera" a „widzę, ale nie odpowiada".
    void Function(BtDevice device, bool isChatt)? onDevice,
    /// Ile trwa samo zapytanie w eter. Android odpowiada przez kilkanaście
    /// sekund, więc krótsze okno ucina wyniki.
    Duration inquiry = const Duration(seconds: 16),
    /// Ile czasu zostaje na wypytanie znalezionych. Osobny budżet, bo
    /// wspólny zjadało zapytanie w eter i na pytanie nie zostawało nic.
    Duration probing = const Duration(seconds: 60),
  }) async {
    if (_bluetooth == null) return const [];
    await BtChannel.scan();

    // Odpowiedzi z eteru przychodzą rozgłoszeniami przez cały czas trwania
    // zapytania. Nie kończymy więc pętli na pierwszym „już nie szukam": ten
    // stan bywa prawdziwy, zanim cokolwiek wróci, i zostawałaby sama lista
    // sparowanych.
    final koniec = DateTime.now().add(inquiry);
    final minimum = DateTime.now().add(inquiry ~/ 2);

    // Najpierw zbieramy, dopiero potem pytamy. Połączenie RFCOMM przerywa
    // zapytanie w eter (obie platformy wołają wtedy cancelDiscovery), więc
    // sprawdzanie w trakcie skanu ucinało ten skan po pierwszym urządzeniu
    // i z eteru nie wracało nic ponad to, co i tak było sparowane.
    final widziane = <String, BtDevice>{};
    var szuka = true;
    while ((szuka || DateTime.now().isBefore(minimum)) &&
        DateTime.now().isBefore(koniec)) {
      // Dodatek zgaszony w trakcie szukania kończy szukanie.
      if (_bluetooth == null) return const [];
      final wynik = await BtChannel.scanResults();
      szuka = wynik.scanning;
      for (final device in wynik.devices) {
        widziane[device.address] = device;
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }

    // Radio nie umie powiedzieć, kto jest Chattem: rozstrzyga dopiero próba
    // połączenia pod naszym numerem usługi.
    final znalezione = <Peer>[];
    final koniecPytania = DateTime.now().add(probing);
    for (final device in btProbeOrder(widziane.values)) {
      if (DateTime.now().isAfter(koniecPytania) || _bluetooth == null) break;
      final peer = await _probeBluetooth(device.address);
      onDevice?.call(device, peer != null);
      if (peer == null) continue;
      znalezione.add(peer);
      onFound?.call(peer);
    }
    return znalezione;
  }

  /// Ręczne dodanie urządzenia po adresie radia: odpowiednik dodania po IP.
  ///
  /// Przydaje się wszędzie tam, gdzie szukanie nie wchodzi w grę: Android nie
  /// oddaje wyników wyszukiwania przy wyłączonych usługach lokalizacji, a
  /// adres i tak bywa znany skądinąd (z parowania systemowego albo z kodu QR).
  Future<Peer?> addPeerByBluetooth(String address) {
    final czysty = normalizeBtAddress(address);
    if (czysty.isEmpty || _bluetooth == null) return Future.value(null);
    return _probeBluetooth(czysty);
  }

  /// Czy pod tym adresem stoi Chatt. Zapisujemy go dopiero wtedy, gdy się
  /// przedstawi swoim kluczem, więc słuchawki i klawiatury nie trafiają
  /// na listę rozmówców.
  Future<Peer?> _probeBluetooth(String address) async {
    final info = await client.fetchInfo(
      BluetoothRoute(address),
      // Krótko: przy wyszukiwaniu pytamy wszystko, co widzi radio, a Chatt
      // po drugiej stronie odpowiada od razu.
      timeout: const Duration(seconds: 5),
    );
    if (info == null || info.guid == identity.guid) {
      // Łącze do czegoś, co Chattem nie jest, niepotrzebnie zajmuje kanał.
      await _bluetooth?.dropLink(address);
      return null;
    }
    final peer = await db.upsertPeer(
      guid: info.guid,
      name: info.name,
      welcomeMessage: info.welcomeMessage,
      // Rozmówca poznany przez radio nie ma adresu w sieci. Pusty host
      // i zerowy port nie nadpisują tego, co o nim wiemy z Wi-Fi.
      host: '',
      port: 0,
      btAddress: address,
      protocol: PeerProtocol.bluetooth.index,
    );
    return _przypnijKlucz(peer, info);
  }

  // --- Udostępnianie historii (issue #36) -----------------------------------

  /// Logika siedzi w `history.dart`, tu są tylko wejścia.
  late final _History _history = _History(this);

  /// Karty: rozmówca chce oddać nam historię albo prosi o naszą.
  ValueNotifier<List<PendingHistory>> get pendingHistory => _history.pending;

  /// Własne udostępnianie w toku, do paska postępu.
  ValueNotifier<HistoryTransfer?> get outgoingHistory => _history.outgoing;

  /// Przywracanie historii od rozmówcy w toku albo właśnie zakończone.
  ValueNotifier<HistoryTransfer?> get incomingHistory => _history.incoming;

  /// Co poszłoby rozmówcy z rozmowy [conversationId] (albo z rozmowy
  /// [sourceConversationId], patrz [shareHistory]).
  Future<HistoryPreview> previewHistory(int conversationId,
          {DateTime? since, bool withFiles = true, int? sourceConversationId}) =>
      _history.preview(conversationId,
          since: since,
          withFiles: withFiles,
          sourceConversationId: sourceConversationId);

  /// Oddaje rozmówcy z rozmowy [conversationId] naszą wspólną historię, od
  /// [since] (null = całość), z plikami albo bez. Z [sourceConversationId]
  /// wiadomości bierze się z innej rozmowy: starszej, z tym samym urządzeniem
  /// pod dawnym wpisem. Wolno tylko przy zielonej tarczy rozmówcy.
  Future<HistoryShareResult> shareHistory(int conversationId,
          {DateTime? since, bool withFiles = true, int? sourceConversationId}) =>
      _history.share(conversationId,
          since: since,
          withFiles: withFiles,
          sourceConversationId: sourceConversationId);

  /// Inne rozmowy z wiadomościami, do wyboru źródła przy udostępnianiu.
  Future<List<({int conversationId, Peer peer, int messages})>>
      otherConversations(int conversationId) =>
          db.otherConversations(conversationId);

  /// Łączy u siebie starą rozmowę [from] z rozmową [into], po udostępnieniu
  /// jej nowemu wpisowi tego samego urządzenia.
  Future<int> mergeConversations({required int from, required int into}) =>
      db.mergeConversation(from: from, into: into);

  /// Prosi rozmówcę o jego kopię naszej wspólnej historii.
  Future<HistoryRequestResult> requestHistory(int conversationId) =>
      _history.request(conversationId);

  /// Przerywa własne udostępnianie.
  void cancelHistoryShare() => _history.cancelShare();

  /// Odpowiedź z karty historii.
  void respondToHistory(String id, HistoryDecision decision) =>
      _history.respond(id, decision);

  /// Zamyka pasek zakończonego przywracania.
  void dismissIncomingHistory() => _history.dismissIncoming();
  void stopIncomingHistory() => _history.stopIncoming();

  // --- Zdalna klawiatura ----------------------------------------------------

  /// Dodatek „Klawiatura z PC" w obie strony; logika siedzi w
  /// `remote_input.dart`, tu są tylko wejścia.
  late final _RemoteInput _remoteInput = _RemoteInput(this);

  /// Czy dodatek klawiatury jest włączony (Ustawienia, sekcja „Dodatki").
  /// Jedyny włącznik całej funkcji, w obie strony: wyłączony znaczy, że żaden
  /// ekran poza kartą dodatku jej nie pokazuje, prośby i paczki dostają
  /// odmowę bez karty, a kanał `chatt/remoteinput` nie dostaje wywołań.
  ValueNotifier<bool> get keyboardAddon => _remoteInput.keyboardAddon;

  /// Prośby o pisanie na tym urządzeniu, czekające na decyzję. Nakładka
  /// pokazuje kartę i odpowiada przez [respondToRemoteInput].
  ValueNotifier<List<PendingRemoteInput>> get pendingRemoteInput =>
      _remoteInput.pending;

  /// Trwająca zgoda na pisanie na tym urządzeniu, do wskaźnika i Stopu.
  ValueNotifier<IncomingRemoteInput?> get incomingRemoteInput =>
      _remoteInput.incoming;

  /// Własna sesja pisania na innym urządzeniu.
  ValueNotifier<OutgoingRemoteInput?> get outgoingRemoteInput =>
      _remoteInput.outgoing;

  /// Czy na tej platformie inni mogą pisać (jest ujście natywne).
  bool get remoteInputReceiveSupported => _remoteInput.receiveSupported;

  /// Włącza albo wyłącza dodatek klawiatury. Wyłączenie kończy zgodę,
  /// prośby i własną sesję pisania, gasi odbiór w bazie i wyłącza klawiaturę
  /// Chatt w systemie. Przełączenia idą po kolei.
  Future<bool> setKeyboardAddon(bool on) => _remoteInput.setAddon(on);

  /// Przełącznik „Pozwól pisać na tym urządzeniu". Działa tylko przy
  /// włączonym dodatku; wyłączenie kończy zgodę i prośby od razu.
  Future<bool> setRemoteInputReceive(bool on) => _remoteInput.setReceive(on);

  /// Prosi [peer] o sesję pisania i czeka na jego decyzję (do dwóch minut).
  Future<RemoteInputStart> startRemoteInput(Peer peer) =>
      _remoteInput.start(peer);

  /// Dopisuje operacje do kolejki aktywnej sesji pisania.
  bool sendRemoteInput(List<RemoteInputOp> ops) => _remoteInput.send(ops);

  /// Kończy własną sesję pisania (albo wycofuje prośbę bez odpowiedzi).
  Future<void> stopRemoteInput() => _remoteInput.stop();

  /// Odpowiedź z karty na prośbę z [pendingRemoteInput]. [remember] to „nie
  /// pytaj więcej dla tego urządzenia".
  void respondToRemoteInput(String id,
          {required bool accept, bool remember = false}) =>
      _remoteInput.respond(id, accept: accept, remember: remember);

  /// Stop po stronie odbiorcy.
  void stopIncomingRemoteInput() => _remoteInput.stopIncoming();

  // --- Dziennik aplikacji i historia pisania (issue #50) --------------------

  /// Dziennik aplikacji do diagnostyki, w zaszyfrowanej bazie. Bez treści
  /// wiadomości, bez wpisywanego tekstu i bez kluczy (patrz `app_log.dart`).
  late final AppLog log = AppLog(db);

  /// Historia pisania zdalną klawiaturą, po obu stronach. Zapisuje tylko
  /// przy włączonym dodatku i włączonym przełączniku [typingHistory].
  late final TypingJournal typingJournal = TypingJournal(
    db,
    enabled: () => keyboardAddon.value && typingHistory.value,
    onError: (blad, slad) => log.error(
        LogArea.keyboard, 'Typing history could not be saved',
        error: blad, stack: slad),
  );

  /// Przełącznik „Zapisuj historię pisania" w karcie dodatku klawiatury.
  /// Domyślnie włączony; jedynym pisarzem jest [setTypingHistory].
  final ValueNotifier<bool> typingHistory = ValueNotifier(true);

  /// Włącza albo wyłącza zapis historii pisania. Wyłączenie nie kasuje tego,
  /// co już zapisane: do tego jest [clearTypingHistory].
  Future<bool> setTypingHistory(bool on) async {
    typingHistory.value = on;
    await db.saveTypingHistory(on);
    return on;
  }

  /// Kasuje całą historię pisania. Trwająca sesja pisze dalej, ale już bez
  /// zapisu. Zwraca liczbę usuniętych sesji.
  Future<int> clearTypingHistory() async {
    await typingJournal.flush();
    typingJournal.detachAll();
    return db.clearTypingHistory();
  }

  /// „Wyczyść historię" z Ustawień: wiadomości, rozmowy i historia pisania
  /// (patrz [ChattDb.clearHistory]). Zwraca liczbę usuniętych wiadomości.
  Future<int> clearHistory() async {
    await typingJournal.flush();
    typingJournal.detachAll();
    return db.clearHistory();
  }

  /// Czy wisi jakakolwiek karta z pytaniem. Zdalne pisanie wtedy czeka, żeby
  /// zdalny Enter nie odpowiedział na pytanie, którego nikt nie przeczytał.
  bool get _anyPromptPending =>
      pendingOffers.value.isNotEmpty ||
      pendingPairings.value.isNotEmpty ||
      _remoteInput.pending.value.isNotEmpty ||
      _history.pending.value.isNotEmpty;

  /// Zapomina sesje przychodzące od [peerGuid], bez ruszania zgód. Następne
  /// zapytanie od niego dostaje 409, jak po restarcie, a zgoda na pisanie
  /// zostaje.
  @visibleForTesting
  void debugDropIncomingSessions(String peerGuid) {
    final wychodzaca = _sessionsByPeer[peerGuid];
    _sessionsById.removeWhere((_, sesja) =>
        sesja.peerGuid == peerGuid && !identical(sesja, wychodzaca));
  }

  /// Pieczętuje dowolny ładunek bieżącą sesją z [peer] i wysyła go na
  /// `/input-session`, `/input`, `/history-offer` albo `/history-chunk`.
  /// Testy budują tym paczki, których prawdziwy nadawca nigdy nie wyśle.
  @visibleForTesting
  Future<({int status, Map<String, Object?>? reply})> debugSendSealed(
      Peer peer, String path, Map<String, Object?> payload) async {
    final wynik = await _exchangeSealed(
      peer,
      payload,
      (route, koperta) => switch (path) {
        '/input-session' =>
          client.requestInputSession(route: route, payload: koperta),
        '/history-offer' => client.historyOffer(route: route, payload: koperta),
        '/history-chunk' => client.historyChunk(route: route, payload: koperta),
        _ => client.sendInput(route: route, payload: koperta),
      },
    );
    return (status: wynik.status, reply: wynik.reply);
  }

  /// Zapowiedź pliku zapieczętowana bieżącą sesją z [peer]. Testy sprawdzają
  /// tym zapowiedzi, których prawdziwy nadawca nigdy nie wyśle.
  @visibleForTesting
  Future<FileOfferReply?> debugOfferFile(Peer peer, FileOffer offer) async {
    final koperta = await _sealFor(peer, offer.toJson());
    if (koperta == null) return null;
    return client.offerFile(route: routeOf(peer), payload: koperta);
  }

  // --- Podglądy odnośników --------------------------------------------------

  /// Pobieranie podglądów stron dla odnośników w wiadomościach. Stoi
  /// wyłączone, dopóki użytkownik nie włączy przełącznika w Ustawieniach:
  /// to drugi (po pytaniu o wydanie) rodzaj ruchu poza sieć lokalną.
  final LinkPreviewService linkPreviews = LinkPreviewService();

  StreamSubscription<Setting>? _linkPreviewWatch;

  /// Przełącznik z ustawień trafia do serwisu na żywo. Wyłączenie ma
  /// zatrzymać pytania od razu i wyrzucić to, co zdążyło przyjść, a nie
  /// czekać na restart aplikacji.
  void _startLinkPreviews() {
    _linkPreviewWatch = db.watchSettings().listen(
      (settings) {
        if (linkPreviews.enabled == settings.linkPreviews) return;
        linkPreviews.enabled = settings.linkPreviews;
        if (!settings.linkPreviews) linkPreviews.clear();
      },
      onError: (_) {},
    );
  }

  // --- Sprawdzanie aktualizacji ---------------------------------------------

  Timer? _updateTimer;

  /// Wydanie nowsze niż to, które chodzi. `null` znaczy, że albo nikt jeszcze
  /// nie pytał, albo nie ma nic nowego. Ustawienia patrzą tu na żywo.
  final ValueNotifier<Release?> availableRelease = ValueNotifier(null);

  /// Czy pytanie właśnie leci. Po tym przycisk wie, że ma być nieaktywny.
  final ValueNotifier<bool> checkingForUpdate = ValueNotifier(false);

  /// Pytanie o wydanie raz na dobę, i tylko przy włączonym przełączniku.
  ///
  /// Timer chodzi co godzinę, ale samo pytanie pada dopiero, gdy od ostatniego
  /// minęła doba. Dzięki temu aplikacja chodząca tygodniami bez restartu pyta
  /// tyle samo razy co taka, którą ktoś włącza raz dziennie.
  void _startUpdateChecks() {
    unawaited(_checkForUpdateIfDue());
    _updateTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(_checkForUpdateIfDue()),
    );
  }

  Future<void> _checkForUpdateIfDue() async {
    final ustawienia = await db.getSettings();
    if (ustawienia == null || !ustawienia.updateChecks) return;
    final ostatnie = ustawienia.lastUpdateCheck;
    if (ostatnie != null &&
        DateTime.now().difference(ostatnie) < updateCheckInterval) {
      return;
    }
    await checkForUpdate();
  }

  /// Pyta GitHuba o najnowsze wydanie i zapisuje wynik w [availableRelease].
  ///
  /// Pyta zawsze, bez oglądania się na przełącznik: tędy wchodzi przycisk
  /// „Sprawdź teraz", a ten ma działać także przy wyłączonym sprawdzaniu.
  Future<UpdateResult> checkForUpdate({http.Client? client}) async {
    checkingForUpdate.value = true;
    try {
      final wynik = await fetchLatestRelease(client: client);
      availableRelease.value = wynik.release;
      // Znacznik zapisujemy także po nieudanym pytaniu: brak sieci nie ma
      // zamieniać sprawdzania co dobę w pukanie co godzinę.
      await db.markUpdateCheck(DateTime.now());
      return wynik;
    } finally {
      checkingForUpdate.value = false;
    }
  }

  Future<void> dispose() async {
    _closing = true;
    _bluetoothRetry?.cancel();
    await _remoteInput.dispose();
    await _history.dispose();
    await typingJournal.close();
    typingHistory.dispose();
    // Nikt już nie odpowie na wiszące prośby o zgodę: odmawiamy, żeby
    // nadawcy nie czekali do timeoutu.
    for (final guid in _offerDecisions.keys.toList()) {
      // Zamykana aplikacja to nie odmowa użytkownika: nadawca ma nie czekać
      // do timeoutu, ale paczka zostaje bez zapamiętanej decyzji.
      _resolveOffer(guid, OfferDecision.noAnswer);
    }
    _updateTimer?.cancel();
    availableRelease.dispose();
    checkingForUpdate.dispose();
    _retentionTimer?.cancel();
    await _retentionWatch?.cancel();
    await _linkPreviewWatch?.cancel();
    linkPreviews.dispose();
    await _transportWatch?.cancel();
    // Radio gaśnie razem z aplikacją: nasłuch RFCOMM i wykrywalność
    // komputera nie mają prawa przeżyć jej zamknięcia.
    await stopBluetooth();
    bluetoothAddon.dispose();
    bluetoothRunning.dispose();
    bluetoothRevision.dispose();
    bluetoothStatus.dispose();
    responder.stop();
    await server.stop();
    client.dispose();
    await log.close();
    await db.close();
  }
}
