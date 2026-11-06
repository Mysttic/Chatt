import 'dart:async';
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

/// [UdpMux] na prawdziwym gnieździe UDP.
class SocketUdpMux implements UdpMux {
  final RawDatagramSocket _socket;
  final _handlers = <UdpHandler>[];
  StreamSubscription<RawSocketEvent>? _sub;

  /// Pakiety, których nikt nie wziął. Wyłącznie do diagnostyki (spike).
  void Function(UdpPacket packet)? onUnhandled;

  SocketUdpMux(this._socket) {
    _socket.readEventsEnabled = true;
    _sub = _socket.listen(_onEvent);
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
  int get port => _socket.port;

  @override
  void register(UdpHandler handler) => _handlers.add(handler);

  @override
  void unregister(UdpHandler handler) => _handlers.remove(handler);

  @override
  void send(List<int> data, InternetAddress address, int port) {
    try {
      _socket.send(data, address, port);
    } on SocketException {
      // Pojedynczy pakiet UDP, który nie wyszedł (np. sieć chwilowo znikła),
      // nie jest błędem warstwy wyżej: ta i tak ponawia.
    }
  }

  void _onEvent(RawSocketEvent event) {
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
    await _sub?.cancel();
    _sub = null;
    _socket.close();
  }
}
