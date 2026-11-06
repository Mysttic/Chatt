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
///  1. **Uścisk KK** — obie strony znają nawzajem swój klucz statyczny
///     (trasa internetowa jest tylko dla rozmówców z zieloną tarczą), więc
///     wymieniają klucze efemeryczne i liczą klucz sesji tym samym
///     [ChattCrypto.sessionKey] co reszta aplikacji. Napastnik bez klucza
///     prywatnego policzy inny klucz i pierwszy pakiet danych mu się nie
///     odszyfruje — łącze pada, zanim cokolwiek przez nie przejdzie.
///  2. **Koperta pakietu** — każdy pakiet to AES-GCM z własnym licznikiem
///     w nonce. Licznik rośnie i nigdy się nie powtarza, a odbiorca trzyma
///     okno antyreplay, więc nagranego pakietu nie da się odtworzyć. To
///     zamyka lukę, którą koperta warstwy aplikacji ma w sieci lokalnej:
///     tam nagrać mógł tylko ktoś w tej samej sieci, w internecie każdy po
///     drodze.
///  3. **ARQ** — numery segmentów, potwierdzenia i retransmisja z czasem
///     RTO dają strumień bajtów w kolejności, nad którym działa ten sam
///     multiplekser żądań i odpowiedzi ([BtLink]), co nad Bluetoothem i TCP.
///
/// Nad tą rurą nic nie wie, że jedzie przez internet: uścisk sesji aplikacji,
/// koperty wiadomości i szyfrowanie plików działają bez zmiany.

/// Rodzaje pakietów łącza.
class _PacketType {
  static const hello = 1;
  static const helloAck = 2;
  static const data = 3;
  static const close = 4;
}

/// Największa treść segmentu danych. Ostrożnie poniżej typowego MTU (~1280
/// dla IPv6), żeby pakiet nie był dzielony po drodze: dzielony fragment UDP
/// ginie w całości, gdy zginie jedna jego część.
const int kSegmentPayload = 1024;

/// Nagłówek niezawodności w jawnej (odszyfrowanej) treści pakietu danych:
/// `seq(4) ack(4) sack(4) len(2)`.
const int _reliableHeader = 14;

/// Okno wysyłania: tyle segmentów może być w locie bez potwierdzenia.
const int kSendWindow = 64;

/// Domyślny czas do retransmisji, zanim zmierzymy RTT.
const Duration kInitialRto = Duration(milliseconds: 500);
const Duration kMinRto = Duration(milliseconds: 200);
const Duration kMaxRto = Duration(seconds: 5);

/// Co ile wysyłamy pusty pakiet, żeby NAT nie zamknął furtki. Pomiar na
/// sprzęcie (patrz docs/spike-nat.md) ma to uściślić; 15 s jest ostrożne.
const Duration kKeepalive = Duration(seconds: 15);

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
  DateTime _lastSent = DateTime.now();

  /// Wołane, gdy łącze zmienia stan (do logu i interfejsu).
  final void Function(LinkState state, String reason)? onState;

  /// Wołane, gdy druga strona odezwała się z nowego adresu (NAT przestawił
  /// port). Menedżer po tym przepina swoją mapę „adres → łącze".
  void Function(String oldLabel, String newLabel)? onRebind;

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

  // --- uścisk dłoni --------------------------------------------------------

  /// Zaczyna uścisk (strona inicjująca wysyła HELLO). Strona przyjmująca
  /// dostaje HELLO z zewnątrz i woła [acceptHello].
  Future<bool> connect() async {
    await _prepareEphemeral();
    _armDead();
    _sendHello();
    // Ponawianie HELLO, póki nie przyjdzie HELLO_ACK: pierwszy pakiet
    // przebicia dziury często ginie.
    _handshakeRetry(0);
    return ready;
  }

  Future<void> _prepareEphemeral() async {
    final kp = await ChattCrypto.newKeyPair();
    _myEphemeral = kp;
    _myEphemeralPub = await ChattCrypto.publicKeyOf(kp);
  }

  void _handshakeRetry(int attempt) {
    if (_state != LinkState.handshaking || attempt >= 10) return;
    Timer(const Duration(milliseconds: 400), () {
      if (_state != LinkState.handshaking) return;
      if (initiator) {
        _sendHello();
      }
      _handshakeRetry(attempt + 1);
    });
  }

  void _sendHello() {
    final guid = Uint8List.fromList(_myGuid.codeUnits);
    final out = BytesBuilder(copy: false)
      ..addByte(_PacketType.hello)
      ..addByte(guid.length)
      ..add(guid)
      ..add(_myEphemeralPub!);
    _rawSend(out.takeBytes());
  }

  /// Przyjmuje HELLO od strony inicjującej: liczy klucz i odsyła HELLO_ACK.
  /// [theirEphemeral] wyjęła z pakietu warstwa, która go rozpoznała.
  Future<void> acceptHello(List<int> theirEphemeral) async {
    if (_state != LinkState.handshaking || _key != null) return;
    await _prepareEphemeral();
    await _deriveKey(theirEphemeral, initiator: false);
    final out = BytesBuilder(copy: false)
      ..addByte(_PacketType.helloAck)
      ..add(_myEphemeralPub!);
    _rawSend(out.takeBytes());
    _armDead();
    _up();
  }

  Future<void> _onHelloAck(List<int> theirEphemeral) async {
    if (_state != LinkState.handshaking || _key != null) return;
    await _deriveKey(theirEphemeral, initiator: true);
    _up();
  }

  Future<void> _deriveKey(List<int> theirEphemeral,
      {required bool initiator}) async {
    final mojEf = _myEphemeralPub!;
    _key = await ChattCrypto.sessionKey(
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
  }

  void _up() {
    if (_state != LinkState.handshaking) return;
    _state = LinkState.up;
    if (!_ready.isCompleted) _ready.complete(true);
    _armKeepalive();
    onState?.call(LinkState.up, initiator ? 'outgoing' : 'incoming');
    // Mogły już czekać bajty dodane przed końcem uścisku.
    _pump();
  }

  // --- wejście pakietów ----------------------------------------------------

  /// Woła to multiplekser gniazda, gdy pakiet przyszedł z adresu tego łącza.
  /// Zwraca true, gdy pakiet był dla tego łącza.
  void handlePacket(UdpPacket packet) {
    if (packet.data.isEmpty) return;
    // Adres mógł się zmienić (NAT przestawił port). Ufamy tylko pakietowi,
    // który się odszyfruje; sam fakt nowego adresu niczego nie przyznaje.
    final type = packet.data[0];
    switch (type) {
      case _PacketType.hello:
        // Obsługiwane przez menedżera (potrzebuje guida), nie tutaj.
        break;
      case _PacketType.helloAck:
        if (packet.data.length >= 33) {
          _touch(packet);
          unawaited(_onHelloAck(packet.data.sublist(1, 33)));
        }
      case _PacketType.data:
        _onData(packet);
      case _PacketType.close:
        close(powod: 'peer closed');
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
    final key = _key;
    if (key == null || packet.data.length < 1 + 8 + 16) return;
    final counter = _readCounter(packet.data, 1);
    // Antyreplay: licznik spoza okna albo już widziany odpada.
    if (!_acceptCounter(counter)) return;
    final nonce = _nonceFor(counter, incoming: true);
    final mac = packet.data.sublist(9, 25);
    final cipher = packet.data.sublist(25);
    List<int> clear;
    try {
      clear = await _gcm.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(key),
      );
    } catch (_) {
      // Pakiet, który się nie odszyfrował: podmieniony albo nie nasz. Nie
      // zapamiętujemy licznika, bo nic prawdziwego się nie wydarzyło; jego
      // powtórka znów tylko nie przejdzie uwierzytelnienia.
      return;
    }
    _touch(packet);
    _markSeen(counter);
    _handleReliable(Uint8List.fromList(clear));
  }

  void _handleReliable(Uint8List clear) {
    if (clear.length < _reliableHeader) return;
    final view = ByteData.sublistView(clear);
    final seq = view.getUint32(0);
    final ack = view.getUint32(4);
    final sack = view.getUint32(8);
    final len = view.getUint16(12);
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
          seq <= ack + 2 + 31 &&
          (sack & (1 << (seq - ack - 2))) != 0;
      if (seq <= ack || bySack) {
        final segment = _unacked.remove(seq);
        if (segment != null) {
          _sampleRtt(segment);
          potwierdzono = true;
        }
      }
    }
    if (ack >= _sendBase) {
      _sendBase = ack + 1;
      _timeoutBackoff = 0; // postęp: zdejmujemy wykładnicze wycofanie
    }
    if (potwierdzono) {
      _wakeWindow();
      _rearmRto();
      _pump();
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
    while (_sendQueue.isNotEmpty && _unacked.length < kSendWindow) {
      final take = _sendQueue.length < kSegmentPayload
          ? _sendQueue.length
          : kSegmentPayload;
      final payload = Uint8List.fromList(_sendQueue.sublist(0, take));
      _sendQueue.removeRange(0, take);
      final seq = _nextSeq++;
      final segment = _Segment(seq, payload);
      _unacked[seq] = segment;
      unawaited(_sendPacket(seq: seq, payload: payload));
    }
    _rearmRto();
  }

  @override
  Future<void> flush() async {
    // Hamowanie: wracamy dopiero, gdy zaległość zeszła na łącze (kolejka
    // pusta) i w oknie jest miejsce na kolejny segment. Bez tego duży plik
    // wjechałby w całości do pamięci, zamiast iść w tempie łącza.
    if (_sendQueue.isEmpty && _unacked.length < kSendWindow) return;
    final completer = Completer<void>();
    _windowDrained.add(completer);
    return completer.future;
  }

  void _wakeWindow() {
    if (_sendQueue.isEmpty && _unacked.length < kSendWindow) {
      for (final c in _windowDrained) {
        if (!c.isCompleted) c.complete();
      }
      _windowDrained.clear();
    }
  }

  Future<void> _sendPacket({required int seq, required List<int> payload}) async {
    final key = _key;
    if (key == null) return;
    final clear = Uint8List(_reliableHeader + payload.length);
    final view = ByteData.sublistView(clear);
    view.setUint32(0, seq);
    view.setUint32(4, _recvNext - 1); // kumulatywne ACK
    view.setUint32(8, _sackBits());
    view.setUint16(12, payload.length);
    clear.setRange(_reliableHeader, clear.length, payload);

    final counter = _sendCounter++;
    final nonce = _nonceFor(counter, incoming: false);
    final box = await _gcm.encrypt(clear, secretKey: SecretKey(key), nonce: nonce);
    final out = BytesBuilder(copy: false)
      ..addByte(_PacketType.data)
      ..add(_counterBytes(counter))
      ..add(box.mac.bytes)
      ..add(box.cipherText);
    _rawSend(out.takeBytes());
  }

  int _sackBits() {
    var bits = 0;
    for (var i = 0; i < 32; i++) {
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
        unawaited(_sendPacket(seq: segment.seq, payload: segment.payload));
      }
    }
    _timeoutBackoff++;
    _rearmRto();
  }

  void _armKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(kKeepalive, (_) {
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
    _seenBits.removeWhere((c) => c <= _highestSeen - _replayWindow);
  }

  // --- nonce ---------------------------------------------------------------

  /// Nonce 12 bajtów: bajt kierunku + 8 bajtów licznika + 3 zera. Kierunek
  /// rozróżnia strony, licznik — pakiety, więc żadna para (klucz, nonce) się
  /// nie powtórzy.
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
    if (byloUp && _key != null) {
      // Grzeczne pożegnanie, best-effort.
      _rawSend(Uint8List.fromList([_PacketType.close]));
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
  _Segment(this.seq, this.payload) : sentAt = DateTime.now();
}
