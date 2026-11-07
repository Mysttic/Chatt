import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

/// Jeden pakiet UDP: treść i skąd przyszedł.
class UdpPacket {
  final Uint8List data;
  final InternetAddress address;
  final int port;

  const UdpPacket(this.data, this.address, this.port);

  String get from => '${address.address}:$port';
}

/// Obsługa pakietu. Zwraca true, gdy pakiet był „mój" i nie ma go po co
/// podawać dalej.
typedef UdpHandler = bool Function(UdpPacket packet);

/// Czy pod ten adres gniazdo IPv4 może wysłać pakiet. Windows przyjmuje
/// `send` pod 0.0.0.0 bez błędu, po czym zgłasza błąd w strumieniu gniazda
/// i zamyka gniazdo. Taki adres potrafi przyjść z sieci (lista węzłów DHT),
/// więc odpada przed wysłaniem, razem z portem 0, rozgłoszeniem i grupami
/// multicast.
bool udpSendable(InternetAddress address, int port) {
  if (port <= 0 || port > 65535) return false;
  if (address.type != InternetAddressType.IPv4) return false;
  final pierwszy = address.rawAddress[0];
  return pierwszy != 0 && pierwszy < 224;
}

/// Jedno gniazdo UDP, z którego korzysta kilka warstw naraz: STUN, DHT
/// i łącze Chatta.
///
/// Dlaczego jedno: przebicie dziury w NAT-cie działa tylko wtedy, gdy
/// pakiety do rozmówcy wychodzą z tego samego portu, dla którego NAT nadał
/// mapowanie widziane przez STUN. Gdyby każda warstwa miała swoje gniazdo,
/// STUN zmierzyłby jedno mapowanie, a łącze dostałoby inne. Przychodzące
/// pakiety rozdziela [UdpHandler]: każdy patrzy, czy pakiet jest w jego
/// kształcie (ciasteczko STUN, słownik bencode, nagłówek łącza), i albo go
/// bierze, albo przepuszcza do następnego.
abstract class UdpMux {
  /// Lokalny port, na którym stoi gniazdo.
  int get port;

  /// Dokłada obsługę przychodzących pakietów. Kolejność dokładania jest
  /// kolejnością prób.
  void register(UdpHandler handler);

  void unregister(UdpHandler handler);

  /// Wysyła pakiet pod adres.
  void send(List<int> data, InternetAddress address, int port);

  Future<void> close();
}

/// Ile pakietów najwyżej czeka w [SocketUdpMux] na miejsce w buforze
/// wysyłki systemu. Więcej to już zator: nadmiar ginie jak każdy pakiet UDP,
/// a warstwa wyżej go ponowi.
const int kUdpSendBacklog = 1024;

/// [UdpMux] na prawdziwym gnieździe UDP.
class SocketUdpMux implements UdpMux {
  RawDatagramSocket _socket;
  final InternetAddress _address;
  int _port;
  final _handlers = <UdpHandler>[];
  StreamSubscription<RawSocketEvent>? _sub;
  bool _closed = false;

  /// Pakiety, których system nie przyjął od razu. `send` zwraca wtedy zero
  /// i pakiet nie wychodzi: na Windows z serii 64 pakietów wysłanych jednym
  /// ciągiem tak przepadało około czterech na pięć (pomiar w
  /// docs/spike-nat.md). Czekają tu, aż gniazdo zgłosi gotowość do zapisu,
  /// i wychodzą w kolejności.
  final _waiting = Queue<({List<int> data, InternetAddress address, int port})>();

  /// Ile pakietów odpadło, bo kolejka [_waiting] była pełna.
  int dropped = 0;

  /// Pakiety, których nikt nie wziął. Wyłącznie do diagnostyki (spike).
  void Function(UdpPacket packet)? onUnhandled;

  SocketUdpMux(this._socket)
      : _address = _socket.address,
        _port = _socket.port {
    _listen();
  }

  void _listen() {
    _socket.readEventsEnabled = true;
    // Nowe gniazdo po [_reopen]: zaległe pakiety czekają na jego gotowość.
    if (_waiting.isNotEmpty) _socket.writeEventsEnabled = true;
    _sub = _socket.listen(
      _onEvent,
      // Błąd jednego pakietu nie jest błędem warstwy wyżej: ta i tak ponawia.
      onError: (Object _) {},
      onDone: () => unawaited(_reopen()),
    );
  }

  /// Gniazdo zamknęło się samo: Windows robi tak po niektórych błędach
  /// wysyłki. Wstajemy na tym samym porcie, bo NAT trzyma mapowanie dla
  /// portu, więc adres w skrzynce kontaktowej i u rozmówcy dalej jest ważny.
  /// Gdy port jest zajęty, zostaje dowolny wolny.
  Future<void> _reopen() async {
    for (var proba = 0; proba < 4 && !_closed; proba++) {
      try {
        final nowe =
            await RawDatagramSocket.bind(_address, proba < 3 ? _port : 0);
        if (_closed) {
          nowe.close();
          return;
        }
        _socket = nowe;
        _port = nowe.port;
        _listen();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  /// Otwiera gniazdo na [port] (0 = dowolny wolny). Na IPv4, bo tyle wystarcza
  /// do STUN-u i DHT; podwójny stos jest do rozważenia osobno.
  static Future<SocketUdpMux> bind({
    InternetAddress? address,
    int port = 0,
  }) async {
    final socket = await RawDatagramSocket.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    return SocketUdpMux(socket);
  }

  @override
  int get port => _port;

  @override
  void register(UdpHandler handler) => _handlers.add(handler);

  @override
  void unregister(UdpHandler handler) => _handlers.remove(handler);

  @override
  void send(List<int> data, InternetAddress address, int port) {
    if (_closed || !udpSendable(address, port)) return;
    // Za czekającymi, żeby pakiety nie wyprzedzały się nawzajem.
    if (_waiting.isNotEmpty || !_trySend(data, address, port)) {
      _enqueue(data, address, port);
    }
  }

  /// Wysyła od razu. false: system nie przyjął pakietu (pełny bufor).
  bool _trySend(List<int> data, InternetAddress address, int port) {
    try {
      return _socket.send(data, address, port) > 0;
    } on SocketException {
      // Pojedynczy pakiet UDP, który nie wyszedł (np. sieć chwilowo znikła),
      // nie jest błędem warstwy wyżej: ta i tak ponawia.
      return true;
    }
  }

  void _enqueue(List<int> data, InternetAddress address, int port) {
    if (_waiting.length >= kUdpSendBacklog) {
      dropped++;
      return;
    }
    _waiting.add((data: data, address: address, port: port));
    _socket.writeEventsEnabled = true;
  }

  /// Gniazdo jest gotowe do zapisu: wychodzi tyle zaległych, ile przyjmie.
  void _drain() {
    while (_waiting.isNotEmpty) {
      final p = _waiting.first;
      if (!_trySend(p.data, p.address, p.port)) {
        _socket.writeEventsEnabled = true;
        return;
      }
      _waiting.removeFirst();
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.write) {
      _drain();
      return;
    }
    if (event != RawSocketEvent.read) return;
    final datagram = _socket.receive();
    if (datagram == null) return;
    final packet = UdpPacket(
      Uint8List.fromList(datagram.data),
      datagram.address,
      datagram.port,
    );
    // Kopia listy: obsługa może się wyrejestrować w trakcie (łącze padło).
    for (final handler in _handlers.toList()) {
      bool wziete;
      try {
        wziete = handler(packet);
      } catch (_) {
        wziete = false;
      }
      if (wziete) return;
    }
    onUnhandled?.call(packet);
  }

  @override
  Future<void> close() async {
    _closed = true;
    _waiting.clear();
    await _sub?.cancel();
    _sub = null;
    _socket.close();
  }
}
