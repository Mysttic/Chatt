import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../core/crypto.dart';
import 'bt_link.dart' show BytePipe;
import 'udp_mux.dart';

/// Zaszyfrowana, niezawodna rura bajtów po UDP, czyli to, czego nad gołym
/// UDP brakuje, a co sieć lokalna dostaje za darmo z TCP: kolejność, brak
/// gubienia, brak powtórek i uścisk dłoni, który uwierzytelnia drugi koniec.
///
/// Trzy warstwy, każda z osobnym powodem:
///  1. **Uścisk KK**: obie strony znają nawzajem swój klucz statyczny
///     (trasa internetowa jest tylko dla rozmówców z zieloną tarczą), więc
///     wymieniają klucze efemeryczne i liczą klucz sesji tym samym
///     [ChattCrypto.sessionKey] co reszta aplikacji. Napastnik bez klucza
///     prywatnego policzy inny klucz i pierwszy pakiet danych mu się nie
///     odszyfruje, więc łącze pada, zanim cokolwiek przez nie przejdzie.
///  2. **Koperta pakietu**: każdy pakiet to AES-GCM z własnym licznikiem
///     w nonce. Licznik rośnie i nigdy się nie powtarza, a odbiorca trzyma
///     okno antyreplay, więc nagranego pakietu nie da się odtworzyć. To
///     zamyka lukę, którą koperta warstwy aplikacji ma w sieci lokalnej:
///     tam nagrać mógł tylko ktoś w tej samej sieci, w internecie każdy po
///     drodze.
///  3. **ARQ**: numery segmentów, potwierdzenia i retransmisja z czasem
///     RTO dają strumień bajtów w kolejności, nad którym działa ten sam
///     multiplekser żądań i odpowiedzi ([BtLink]), co nad Bluetoothem i TCP.
///
/// Nad tą rurą nic nie wie, że jedzie przez internet: uścisk sesji aplikacji,
/// koperty wiadomości i szyfrowanie plików działają bez zmiany.

/// Pierwszy bajt każdego pakietu łącza. Na wspólnym gnieździe odróżnia je od
/// STUN-u (pierwszy bajt 0x00 lub 0x01, dwa najstarsze bity zerowe) i od
/// bencode DHT (zaczyna się od `d`, `l`, `i` albo cyfry). 0xCC ma ustawione
/// dwa najstarsze bity, więc [looksLikeStun] go odrzuca, a żaden bencode się
/// nim nie zaczyna. Bez tego odpowiedź STUN (0x01…) trafiała do obsługi
/// pakietu powitalnego i nigdy nie docierała do klienta STUN.
const int _linkMagic = 0xCC;

/// Rodzaje pakietów łącza (drugi bajt, po [_linkMagic]).
class _PacketType {
  static const hello = 1;
  static const helloAck = 2;
  static const data = 3;
  static const knock = 4;
}

/// Numer segmentu znaczący „zamykam łącze". Jedzie w nagłówku wewnątrz koperty
/// AES-GCM, więc nie da się go podrobić bez klucza sesji (dawny jawny bajt
/// zamknięcia dało się wysłać z dowolnego adresu).
const int _closeSeq = 0xFFFFFFFF;

/// Offsety w pakiecie danych, po [_linkMagic] i bajcie typu.
const int _dataCounterOffset = 2;
const int _dataMacOffset = _dataCounterOffset + 8; // 10
const int _dataCipherOffset = _dataMacOffset + 16; // 26

/// Pakiet powitalny rozłożony na części: guid nadawcy i jego klucz
/// efemeryczny. Menedżer łącza potrzebuje guida, żeby znaleźć klucz statyczny
/// rozmówcy, więc rozpoznaje HELLO sam, nie każda rura z osobna.
class HelloPacket {
  final String guid;
  final Uint8List ephemeral;
  const HelloPacket(this.guid, this.ephemeral);
}

/// Czy pakiet w ogóle jest pakietem łącza (odróżnia od STUN i DHT na wspólnym
/// gnieździe).
bool isLinkPacket(Uint8List data) =>
    data.length >= 2 && data[0] == _linkMagic;

/// Pukanie: pakiet od odbiorcy pod adres dzwoniącego. Każdy wychodzący pakiet
/// otwiera w NAT-cie odbiorcy furtkę dla adresu, do którego poszedł, więc
/// po pukaniu HELLO dzwoniącego zaczyna dochodzić. Dzwoniący pukanie połyka;
/// pakiet nie niesie nic, co trzeba by chronić.
Uint8List knockPacket() => Uint8List.fromList([_linkMagic, _PacketType.knock]);

bool isKnock(Uint8List data) =>
    isLinkPacket(data) && data[1] == _PacketType.knock;

/// Rozkłada HELLO na guid i klucz efemeryczny; null, gdy to nie HELLO albo
/// jest obcięty.
HelloPacket? parseHello(Uint8List data) {
  if (!isLinkPacket(data) || data[1] != _PacketType.hello) return null;
  if (data.length < 3) return null;
  final guidLen = data[2];
  if (data.length < 3 + guidLen + 32) return null;
  final guid = String.fromCharCodes(data.sublist(3, 3 + guidLen));
  final ephemeral =
      Uint8List.fromList(data.sublist(3 + guidLen, 3 + guidLen + 32));
  return HelloPacket(guid, ephemeral);
}

/// Największa treść segmentu danych. Ostrożnie poniżej typowego MTU (~1280
/// dla IPv6), żeby pakiet nie był dzielony po drodze: dzielony fragment UDP
/// ginie w całości, gdy zginie jedna jego część.
const int kSegmentPayload = 1024;

/// Nagłówek niezawodności w jawnej (odszyfrowanej) treści pakietu danych:
/// `seq(4) ack(4) sack(8) len(2)`. Mapa SACK ma 64 bity, tyle, ile okno, więc
/// opisuje każdy segment w locie i nadawca nie ponawia niczego, co doszło.
const int _reliableHeader = 18;

/// Okno wysyłania: najwyżej tyle kolejnych numerów segmentów od najstarszego
/// niepotwierdzonego. Przy luce okno stoi, aż luka się wypełni, więc nic nie
/// wyjdzie poza zasięg mapy SACK.
const int kSendWindow = 64;

/// Ile wysyłek późniejszych niż ostatnia wysyłka segmentu musi już dojść,
/// żeby segment uznać za zgubiony i wysłać od razu, bez czekania na RTO (jak
/// trzy zdublowane ACK w TCP).
const int kFastRetransmitThreshold = 3;

/// Domyślny czas do retransmisji, zanim zmierzymy RTT.
const Duration kInitialRto = Duration(milliseconds: 500);
const Duration kMinRto = Duration(milliseconds: 200);
const Duration kMaxRto = Duration(seconds: 5);

/// Po takiej ciszy z naszej strony łącze wysyła pusty pakiet, żeby NAT nie
/// zamknął furtki. Zmierzone (docs/spike-nat.md): po 60 s ciszy furtka stała
/// w obu kierunkach, po 90 s w jednym i 120 s w drugim już nie. 25 s
/// zostawia miejsce na jeden zgubiony pakiet.
const Duration kKeepalive = Duration(seconds: 25);

/// Po tylu sekundach ciszy uznajemy łącze za martwe.
const Duration kLinkDead = Duration(seconds: 60);

/// Ile pakietów wstecz pamięta okno antyreplay.
const int _replayWindow = 1024;

/// Stan łącza, do interfejsu i logu.
enum LinkState { handshaking, up, closed }

/// Jedno zaszyfrowane łącze UDP do jednego zdalnego adresu.
class SecureUdpPipe implements BytePipe {
  final UdpMux _mux;
  final SimpleKeyPair _myStatic;
  final List<int> _myStaticPub;
  final List<int> _theirStatic;
  final String _myGuid;

  /// Strona, która zaczęła (wysłała HELLO), numeruje nonce inaczej niż druga,
  /// żeby licznik w nonce nie zderzył się między kierunkami.
  final bool initiator;

  InternetAddress _remoteAddress;
  int _remotePort;

  final _gcm = AesGcm.with256bits();

  /// Klucz sesji łącza. Pusty, dopóki uścisk się nie skończy.
  List<int>? _key;

  /// Ten sam klucz jako obiekt biblioteki, zrobiony raz na łącze: biblioteka
  /// rozwija z niego klucz AES tylko przy pierwszym pakiecie.
  SecretKey? _secret;
  SimpleKeyPair? _myEphemeral;
  List<int>? _myEphemeralPub;

  LinkState _state = LinkState.handshaking;
  final _ready = Completer<bool>();

  /// Strumień bajtów w kolejności, oddawany warstwie wyżej.
  final _inbound = StreamController<List<int>>();

  /// Licznik wychodzących pakietów (nonce). Rośnie o jeden na pakiet.
  int _sendCounter = 0;

  /// Okno antyreplay przychodzących liczników.
  int _highestSeen = -1;
  final _seenBits = <int>{};

  /// Segmenty danych wysłane pierwszy raz, ponowione od razu (luka w mapie
  /// SACK) i ponowione dopiero po upływie RTO. Do diagnostyki i testów.
  int get segmentsSent => _segmentsSent;
  int get fastRetransmits => _fastRetransmits;
  int get timeoutRetransmits => _timeoutRetransmits;

  /// Wygładzony czas obiegu (zero przed pierwszą próbką). Do dziennika.
  Duration get smoothedRtt => _srtt;
  int _segmentsSent = 0;
  int _fastRetransmits = 0;
  int _timeoutRetransmits = 0;

  /// Numer kolejnej wysyłki segmentu (pierwszej albo ponownej) i najwyższy
  /// numer wysyłki, o której druga strona już dała znać, że doszła.
  int _txCounter = 0;
  int _deliveredTx = 0;

  // --- ARQ: wysyłanie ---
  int _nextSeq = 1;
  int _sendBase = 1; // najstarszy niepotwierdzony
  final _unacked = <int, _Segment>{};
  final _sendQueue = <int>[]; // bajty czekające na segmentację
  final _windowDrained = <Completer<void>>[];

  // --- ARQ: odbiór ---
  int _recvNext = 1; // następny oczekiwany seq
  final _recvBuffer = <int, Uint8List>{};

  // --- RTT / RTO ---
  Duration _srtt = Duration.zero;
  Duration _rttvar = Duration.zero;
  Duration _rto = kInitialRto;

  Timer? _rtoTimer;
  Timer? _keepaliveTimer;
  Timer? _deadTimer;
  Timer? _handshakeTimer;
  DateTime _lastSent = DateTime.now();

  /// Wołane, gdy łącze zmienia stan (do logu i interfejsu).
  final void Function(LinkState state, String reason)? onState;

  /// Wołane, gdy druga strona odezwała się z nowego adresu (NAT przestawił
  /// port). Menedżer po tym przepina swoją mapę „adres → łącze".
  void Function(String oldLabel, String newLabel)? onRebind;

  /// Klucz efemeryczny z HELLO, które przyjęła strona przyjmująca.
  List<int>? _theirHelloEphemeral;

  SecureUdpPipe({
    required UdpMux mux,
    required SimpleKeyPair myStatic,
    required List<int> myStaticPub,
    required List<int> theirStatic,
    required String myGuid,
    required InternetAddress remoteAddress,
    required int remotePort,
    required this.initiator,
    this.onState,
  })  : _mux = mux,
        _myStatic = myStatic,
        _myStaticPub = myStaticPub,
        _theirStatic = theirStatic,
        _myGuid = myGuid,
        _remoteAddress = remoteAddress,
        _remotePort = remotePort;
  // Pola zostają prywatne i przypisywane w ciele: część z nich jest zmienna
  // (adres i port odświeża pakiet z nowego miejsca po przestawieniu NAT),
  // a nazwane parametry czytają się tu lepiej niż `this._...`.
  // ignore_for_file: prefer_initializing_formals

  LinkState get state => _state;

  /// Kończy się, gdy uścisk się powiedzie (true) albo łącze padnie (false).
  Future<bool> get ready => _ready.future;

  bool get isClosed => _state == LinkState.closed;

  @override
  Stream<List<int>> get input => _inbound.stream;

  /// Adres, pod którym stoi teraz druga strona. Może się zmienić, gdy NAT
  /// przestawi port: pakiet od znanego łącza z nowego adresu go odświeża.
  String get remoteLabel => '${_remoteAddress.address}:$_remotePort';

  /// Klucz statyczny drugiej strony, przypięty przy tworzeniu rury.
  List<int> get theirStatic => _theirStatic;

  /// Czy to HELLO tego samego uścisku, który ta rura już przyjęła. Dzwoniący
  /// powtarza HELLO co 400 ms; HELLO z nowym kluczem efemerycznym znaczy, że
  /// zaczął uścisk od nowa.
  bool isHelloFrom(List<int> ephemeral) {
    final mam = _theirHelloEphemeral;
    if (mam == null || mam.length != ephemeral.length) return false;
    for (var i = 0; i < mam.length; i++) {
      if (mam[i] != ephemeral[i]) return false;
    }
    return true;
  }

  /// Strona inicjująca w trakcie uścisku: rozmówca podał w skrzynce nowy
  /// adres, więc HELLO idzie od teraz tam.
  void retarget(InternetAddress address, int port) {
    if (_state != LinkState.handshaking || !initiator) return;
    if (address.address == _remoteAddress.address && port == _remotePort) {
      return;
    }
    final stary = remoteLabel;
    _remoteAddress = address;
    _remotePort = port;
    onRebind?.call(stary, remoteLabel);
    if (_myEphemeralPub != null) _sendHello();
  }

  // --- uścisk dłoni --------------------------------------------------------

  /// Zaczyna uścisk (strona inicjująca wysyła HELLO). Strona przyjmująca
  /// dostaje HELLO z zewnątrz i woła [acceptHello].
  Future<bool> connect() async {
    await _prepareEphemeral();
    _armDead();
    _sendHello();
    _startHandshakeTimer();
    return ready;
  }

  Future<void> _prepareEphemeral() async {
    final kp = await ChattCrypto.newKeyPair();
    _myEphemeral = kp;
    _myEphemeralPub = await ChattCrypto.publicKeyOf(kp);
  }

  /// Powtarza swój krok uścisku co 400 ms, póki łącze nie stanie: pierwsze
  /// pakiety przebicia dziury często giną, a odpowiedzi na HELLO nie da się
  /// odzyskać inaczej niż ponawianiem. Stan „stoi" ustawia dopiero pierwszy
  /// pakiet, który się odszyfruje (patrz [_onData]), więc timer chodzi aż do
  /// tego momentu albo do zamknięcia łącza.
  void _startHandshakeTimer() {
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (_state != LinkState.handshaking) {
        _handshakeTimer?.cancel();
        _handshakeTimer = null;
        return;
      }
      if (initiator) {
        _sendHello();
        if (_key != null) _sendConfirm();
      } else {
        _sendHelloAck();
        _sendConfirm();
      }
    });
  }

  void _sendHello() {
    final guid = Uint8List.fromList(_myGuid.codeUnits);
    final out = BytesBuilder(copy: false)
      ..addByte(_linkMagic)
      ..addByte(_PacketType.hello)
      ..addByte(guid.length)
      ..add(guid)
      ..add(_myEphemeralPub!);
    _rawSend(out.takeBytes());
  }

  void _sendHelloAck() {
    final out = BytesBuilder(copy: false)
      ..addByte(_linkMagic)
      ..addByte(_PacketType.helloAck)
      ..add(_myEphemeralPub!);
    _rawSend(out.takeBytes());
  }

  /// Pusty, uwierzytelniony pakiet (seq 0): dowód dla drugiej strony, że mamy
  /// klucz. Dopiero taki pakiet, który się u niej odszyfruje, przełącza ją
  /// w stan „stoi". Podszywający się pod cudzy guid nie policzy klucza i tego
  /// pakietu nie wyśle.
  void _sendConfirm() {
    if (_key != null) unawaited(_sendPacket(seq: 0, payload: const []));
  }

  /// Przyjmuje HELLO od strony inicjującej: liczy klucz i odsyła HELLO_ACK
  /// razem z potwierdzeniem. Nie przechodzi od razu w „stoi": zrobi to dopiero
  /// pakiet od drugiej strony, który się odszyfruje.
  Future<void> acceptHello(List<int> theirEphemeral) async {
    if (_state != LinkState.handshaking || _key != null) return;
    _theirHelloEphemeral = List<int>.of(theirEphemeral);
    await _prepareEphemeral();
    await _deriveKey(theirEphemeral, initiator: false);
    _armDead();
    _sendHelloAck();
    _sendConfirm();
    _startHandshakeTimer();
  }

  Future<void> _onHelloAck(List<int> theirEphemeral) async {
    if (_state != LinkState.handshaking || _key != null) return;
    await _deriveKey(theirEphemeral, initiator: true);
    _sendConfirm();
  }

  Future<void> _deriveKey(List<int> theirEphemeral,
      {required bool initiator}) async {
    final mojEf = _myEphemeralPub!;
    final key = await ChattCrypto.sessionKey(
      myStatic: _myStatic,
      myEphemeral: _myEphemeral!,
      theirStatic: _theirStatic,
      theirEphemeral: theirEphemeral,
      initiator: initiator,
      initiatorStatic: initiator ? _myStaticPub : _theirStatic,
      responderStatic: initiator ? _theirStatic : _myStaticPub,
      initiatorEphemeral: initiator ? mojEf : theirEphemeral,
      responderEphemeral: initiator ? theirEphemeral : mojEf,
    );
    _secret = await _gcm.newSecretKeyFromBytes(key);
    _key = key;
  }

  void _up() {
    if (_state != LinkState.handshaking) return;
    _state = LinkState.up;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    if (!_ready.isCompleted) _ready.complete(true);
    _armKeepalive();
    // Jeszcze jedno potwierdzenie, już po przejściu w „stoi": druga strona
    // mogła zgubić wcześniejsze (albo dostać je, zanim zdążyła policzyć
    // klucz), a po tym, jak my stanęliśmy, przestajemy je słać z timera.
    _sendConfirm();
    onState?.call(LinkState.up, initiator ? 'outgoing' : 'incoming');
    // Mogły już czekać bajty dodane przed końcem uścisku.
    _pump();
  }

  /// Druga strona wciąż się przedstawia (powtarza HELLO), choć my już stoimy:
  /// odsyłamy potwierdzenie, żeby też mogła stanąć. Woła to menedżer.
  void resendConfirm() {
    if (_state == LinkState.up) _sendConfirm();
  }

  // --- wejście pakietów ----------------------------------------------------

  /// Woła to multiplekser gniazda, gdy pakiet przyszedł z adresu tego łącza.
  /// Zwraca true, gdy pakiet był dla tego łącza.
  void handlePacket(UdpPacket packet) {
    if (packet.data.length < 2 || packet.data[0] != _linkMagic) return;
    // Adres mógł się zmienić (NAT przestawił port). Ufamy tylko pakietowi,
    // który się odszyfruje; sam fakt nowego adresu niczego nie przyznaje,
    // a zamknięcie łącza jedzie teraz w zaszyfrowanym segmencie, nie jawnym
    // bajtem, więc nie ma już czego obsługiwać bez klucza.
    final type = packet.data[1];
    switch (type) {
      case _PacketType.hello:
        // Obsługiwane przez menedżera (potrzebuje guida), nie tutaj.
        break;
      case _PacketType.helloAck:
        if (packet.data.length >= 2 + 32) {
          // HELLO_ACK nie jest uwierzytelniony, więc nie odświeża licznika
          // ciszy ([_touch] robi to dopiero pakiet, który się odszyfruje):
          // sam efemeryczny klucz niczego nie dowodzi.
          unawaited(_onHelloAck(packet.data.sublist(2, 2 + 32)));
        }
      case _PacketType.data:
        _onData(packet);
    }
  }

  void _touch(UdpPacket packet) {
    _lastSeen = DateTime.now();
    if (packet.address.address != _remoteAddress.address ||
        packet.port != _remotePort) {
      final stary = remoteLabel;
      _remoteAddress = packet.address;
      _remotePort = packet.port;
      onRebind?.call(stary, remoteLabel);
    }
    _armDead();
  }

  DateTime _lastSeen = DateTime.now();

  Future<void> _onData(UdpPacket packet) async {
    final secret = _secret;
    if (secret == null || packet.data.length < _dataCipherOffset) return;
    final counter = _readCounter(packet.data, _dataCounterOffset);
    // Antyreplay: licznik spoza okna albo już widziany odpada.
    if (!_acceptCounter(counter)) return;
    final nonce = _nonceFor(counter, incoming: true);
    final mac = packet.data.sublist(_dataMacOffset, _dataCipherOffset);
    final cipher = packet.data.sublist(_dataCipherOffset);
    List<int> clear;
    try {
      clear = await _gcm.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: secret,
      );
    } catch (_) {
      // Pakiet, który się nie odszyfrował: podmieniony albo nie nasz. Nie
      // zapamiętujemy licznika, bo nic prawdziwego się nie wydarzyło; jego
      // powtórka znów tylko nie przejdzie uwierzytelnienia.
      return;
    }
    _touch(packet);
    _markSeen(counter);
    // Pierwszy pakiet, który się odszyfrował, dowodzi, że druga strona ma
    // klucz: dopiero teraz łącze „stoi". Dzięki temu podszycie się pod cudzy
    // guid nie zajmuje miejsca jako gotowe łącze.
    if (_state == LinkState.handshaking) _up();
    _handleReliable(Uint8List.fromList(clear));
  }

  void _handleReliable(Uint8List clear) {
    if (clear.length < _reliableHeader) return;
    final view = ByteData.sublistView(clear);
    final seq = view.getUint32(0);
    final ack = view.getUint32(4);
    final sack = (view.getUint32(8) << 32) | view.getUint32(12);
    final len = view.getUint16(16);
    if (seq == _closeSeq) {
      close(powod: 'peer closed');
      return;
    }
    _onAck(ack, sack);
    if (seq == 0 || len == 0) return; // czysty ACK albo keepalive
    final payload = Uint8List.sublistView(clear, _reliableHeader, _reliableHeader + len);
    _onSegment(seq, payload);
  }

  // --- odbiór segmentów ----------------------------------------------------

  void _onSegment(int seq, Uint8List payload) {
    if (seq < _recvNext) {
      // Już dostarczony: nadawca nie dostał ACK-a. Potwierdzamy jeszcze raz.
      _sendAck();
      return;
    }
    _recvBuffer[seq] = payload;
    while (_recvBuffer.containsKey(_recvNext)) {
      final bytes = _recvBuffer.remove(_recvNext)!;
      if (!_inbound.isClosed) _inbound.add(bytes);
      _recvNext++;
    }
    _sendAck();
  }

  void _sendAck() {
    unawaited(_sendPacket(seq: 0, payload: const []));
  }

  // --- potwierdzenia wysłanego ---------------------------------------------

  void _onAck(int ack, int sack) {
    // Kumulatywne ACK: wszystko do `ack` włącznie dotarło. Bity SACK opisują
    // segmenty tuż za luką: bit i to seq `ack + 2 + i` (seq `ack + 1` to
    // właśnie brakujący, więc go nie kodujemy).
    var potwierdzono = false;
    for (final seq in _unacked.keys.toList()) {
      final bySack = seq >= ack + 2 &&
          seq <= ack + 2 + 63 &&
          ((sack >>> (seq - ack - 2)) & 1) != 0;
      if (seq <= ack || bySack) {
        final segment = _unacked.remove(seq);
        if (segment != null) {
          _sampleRtt(segment);
          if (segment.tx > _deliveredTx) _deliveredTx = segment.tx;
          potwierdzono = true;
        }
      }
    }
    if (ack >= _sendBase) {
      _sendBase = ack + 1;
      _timeoutBackoff = 0; // postęp: zdejmujemy wykładnicze wycofanie
    }
    if (potwierdzono) _fastRetransmit();
    if (potwierdzono) {
      _wakeWindow();
      _rearmRto();
      _pump();
    }
  }

  /// Szybkie ponowienie: segment, którego ostatnią wysyłkę wyprzedziło już co
  /// najmniej [kFastRetransmitThreshold] późniejszych wysyłek, które doszły
  /// (cumulative ACK albo bit SACK), zginął. Idzie od razu, bez czekania na
  /// RTO, które przy każdej stracie zatrzymywało łącze na co najmniej 200 ms.
  /// Liczy się kolejność wysyłek: ponowiony segment, który zginie drugi raz,
  /// wraca, gdy dojdą wysłane po nim, a potwierdzenia sprzed ponowienia,
  /// które dalej pokazują lukę, nie sypią duplikatami.
  void _fastRetransmit() {
    final teraz = DateTime.now();
    for (final segment in _unacked.values) {
      if (_deliveredTx - segment.tx < kFastRetransmitThreshold) continue;
      segment.retransmitted = true;
      segment.sentAt = teraz;
      segment.tx = ++_txCounter;
      _fastRetransmits++;
      unawaited(_sendPacket(seq: segment.seq, payload: segment.payload));
    }
  }

  void _sampleRtt(_Segment segment) {
    if (segment.retransmitted) return; // próbka z retransmisji kłamie (Karn)
    final r = DateTime.now().difference(segment.sentAt);
    if (_srtt == Duration.zero) {
      _srtt = r;
      _rttvar = r ~/ 2;
    } else {
      final diff = (r - _srtt).abs();
      _rttvar = (_rttvar * 3 + diff) ~/ 4;
      _srtt = (_srtt * 7 + r) ~/ 8;
    }
    final rto = _srtt + _rttvar * 4;
    _rto = rto < kMinRto ? kMinRto : (rto > kMaxRto ? kMaxRto : rto);
  }

  // --- wysyłanie bajtów ----------------------------------------------------

  @override
  void add(List<int> data) {
    if (_state == LinkState.closed) return;
    _sendQueue.addAll(data);
    _pump();
  }

  /// Dzieli kolejkę na segmenty i wysyła tyle, ile mieści okno.
  void _pump() {
    if (_state != LinkState.up) return;
    while (_sendQueue.isNotEmpty && _windowOpen) {
      final take = _sendQueue.length < kSegmentPayload
          ? _sendQueue.length
          : kSegmentPayload;
      final payload = Uint8List.fromList(_sendQueue.sublist(0, take));
      _sendQueue.removeRange(0, take);
      final seq = _nextSeq++;
      final segment = _Segment(seq, payload, ++_txCounter);
      _unacked[seq] = segment;
      _segmentsSent++;
      unawaited(_sendPacket(seq: seq, payload: payload));
    }
    _rearmRto();
  }

  @override
  Future<void> flush() async {
    // Hamowanie: wracamy dopiero, gdy zaległość zeszła na łącze (kolejka
    // pusta) i w oknie jest miejsce na kolejny segment. Dzięki temu duży
    // plik idzie w tempie łącza i nie ląduje w całości w pamięci.
    if (_sendQueue.isEmpty && _windowOpen) return;
    final completer = Completer<void>();
    _windowDrained.add(completer);
    return completer.future;
  }

  /// Czy następny segment mieści się w oknie (patrz [kSendWindow]).
  bool get _windowOpen => _nextSeq - _sendBase < kSendWindow;

  void _wakeWindow() {
    if (_sendQueue.isEmpty && _windowOpen) {
      for (final c in _windowDrained) {
        if (!c.isCompleted) c.complete();
      }
      _windowDrained.clear();
    }
  }

  Future<void> _sendPacket({required int seq, required List<int> payload}) async {
    final secret = _secret;
    if (secret == null) return;
    final clear = Uint8List(_reliableHeader + payload.length);
    final view = ByteData.sublistView(clear);
    final sack = _sackBits();
    view.setUint32(0, seq);
    view.setUint32(4, _recvNext - 1); // kumulatywne ACK
    view.setUint32(8, (sack >>> 32) & 0xFFFFFFFF);
    view.setUint32(12, sack & 0xFFFFFFFF);
    view.setUint16(16, payload.length);
    clear.setRange(_reliableHeader, clear.length, payload);

    final counter = _sendCounter++;
    final nonce = _nonceFor(counter, incoming: false);
    final box = await _gcm.encrypt(clear, secretKey: secret, nonce: nonce);
    final out = BytesBuilder(copy: false)
      ..addByte(_linkMagic)
      ..addByte(_PacketType.data)
      ..add(_counterBytes(counter))
      ..add(box.mac.bytes)
      ..add(box.cipherText);
    _rawSend(out.takeBytes());
  }

  int _sackBits() {
    if (_recvBuffer.isEmpty) return 0;
    var bits = 0;
    for (var i = 0; i < 64; i++) {
      if (_recvBuffer.containsKey(_recvNext + 1 + i)) bits |= 1 << i;
    }
    return bits;
  }

  void _rawSend(List<int> bytes) {
    _lastSent = DateTime.now();
    _mux.send(bytes, _remoteAddress, _remotePort);
  }

  // --- retransmisja i podtrzymanie ----------------------------------------

  /// Ile razy z rzędu upłynął RTO bez postępu. Wydłuża czas do kolejnej
  /// retransmisji (wykładnicze wycofanie), zerowane, gdy coś się potwierdzi.
  int _timeoutBackoff = 0;

  /// Efektywny czas oczekiwania: RTT z pomiaru, pomnożony przez wycofanie.
  Duration get _effectiveRto {
    final mult = 1 << (_timeoutBackoff > 6 ? 6 : _timeoutBackoff);
    final rto = _rto * mult;
    return rto > kMaxRto ? kMaxRto : rto;
  }

  void _rearmRto() {
    _rtoTimer?.cancel();
    if (_unacked.isEmpty) return;
    _rtoTimer = Timer(_effectiveRto, _onRtoTimeout);
  }

  void _onRtoTimeout() {
    if (_state != LinkState.up || _unacked.isEmpty) return;
    // Wszystkie zaległe segmenty idą jeszcze raz (go-back-N). Pojedyncza
    // retransmisja na RTO dławiła przepustowość, gdy ginęło kilka naraz.
    // Karn: próbek RTT z retransmisji nie liczymy.
    final teraz = DateTime.now();
    final prog = _effectiveRto;
    for (final segment in _unacked.values) {
      if (teraz.difference(segment.sentAt) >= prog) {
        segment.retransmitted = true;
        segment.sentAt = teraz;
        segment.tx = ++_txCounter;
        _timeoutRetransmits++;
        unawaited(_sendPacket(seq: segment.seq, payload: segment.payload));
      }
    }
    _timeoutBackoff++;
    _rearmRto();
  }

  void _armKeepalive() {
    _keepaliveTimer?.cancel();
    // Sprawdzanie co piąty ułamek: przy sprawdzaniu co [kKeepalive] cisza
    // potrafiła trwać prawie dwa takie odstępy.
    _keepaliveTimer = Timer.periodic(kKeepalive ~/ 5, (_) {
      if (_state != LinkState.up) return;
      if (DateTime.now().difference(_lastSent) >= kKeepalive) {
        _sendAck(); // pusty pakiet trzyma furtkę w NAT-cie otwartą
      }
    });
  }

  void _armDead() {
    _deadTimer?.cancel();
    _deadTimer = Timer(kLinkDead, () {
      if (DateTime.now().difference(_lastSeen) >= kLinkDead) {
        close(powod: 'no packets for ${kLinkDead.inSeconds}s');
      } else {
        _armDead();
      }
    });
  }

  // --- antyreplay ----------------------------------------------------------

  bool _acceptCounter(int counter) {
    if (counter > _highestSeen) return true;
    if (_highestSeen - counter >= _replayWindow) return false; // za stary
    return !_seenBits.contains(counter);
  }

  void _markSeen(int counter) {
    if (counter > _highestSeen) _highestSeen = counter;
    _seenBits.add(counter);
    // Liczniki starsze niż okno odrzuca już [_acceptCounter], więc zbiór
    // czyścimy rzadko: przeglądanie go przy każdym pakiecie kosztowało więcej
    // niż reszta obsługi pakietu.
    if (_seenBits.length > _replayWindow * 2) {
      _seenBits.removeWhere((c) => c <= _highestSeen - _replayWindow);
    }
  }

  // --- nonce ---------------------------------------------------------------

  /// Nonce 12 bajtów: bajt kierunku + 8 bajtów licznika + 3 zera. Kierunek
  /// rozróżnia strony, licznik rozróżnia pakiety, więc żadna para (klucz,
  /// nonce) się nie powtórzy.
  Uint8List _nonceFor(int counter, {required bool incoming}) {
    final dir = (initiator ? !incoming : incoming) ? 1 : 0;
    final nonce = Uint8List(12);
    nonce[0] = dir;
    final view = ByteData.sublistView(nonce);
    view.setUint32(4, (counter >> 32) & 0xFFFFFFFF);
    view.setUint32(8, counter & 0xFFFFFFFF);
    return nonce;
  }

  Uint8List _counterBytes(int counter) {
    final out = Uint8List(8);
    ByteData.sublistView(out)
      ..setUint32(0, (counter >> 32) & 0xFFFFFFFF)
      ..setUint32(4, counter & 0xFFFFFFFF);
    return out;
  }

  int _readCounter(Uint8List data, int offset) {
    final view = ByteData.sublistView(data, offset, offset + 8);
    return (view.getUint32(0) << 32) | view.getUint32(4);
  }

  // --- zamknięcie ----------------------------------------------------------

  @override
  Future<void> close({String powod = 'closed'}) async {
    if (_state == LinkState.closed) return;
    final byloUp = _state == LinkState.up;
    _state = LinkState.closed;
    _rtoTimer?.cancel();
    _keepaliveTimer?.cancel();
    _deadTimer?.cancel();
    _handshakeTimer?.cancel();
    if (byloUp && _key != null) {
      // Grzeczne pożegnanie: zaszyfrowany segment z numerem [_closeSeq],
      // best-effort. Jawnego bajtu nie wysyłamy, bo dało się go podrobić.
      unawaited(_sendPacket(seq: _closeSeq, payload: const []));
    }
    if (!_ready.isCompleted) _ready.complete(false);
    for (final c in _windowDrained) {
      if (!c.isCompleted) c.complete();
    }
    _windowDrained.clear();
    if (!_inbound.isClosed) unawaited(_inbound.close());
    onState?.call(LinkState.closed, powod);
  }
}

/// Jeden wysłany, jeszcze niepotwierdzony segment.
class _Segment {
  final int seq;
  final Uint8List payload;
  DateTime sentAt;
  bool retransmitted = false;

  /// Numer ostatniej wysyłki tego segmentu w kolejności wszystkich wysyłek.
  int tx;

  _Segment(this.seq, this.payload, this.tx) : sentAt = DateTime.now();
}
