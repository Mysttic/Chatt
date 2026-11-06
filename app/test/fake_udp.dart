import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:chatt/network/stun.dart';
import 'package:chatt/network/udp_mux.dart';

/// Sieć UDP w pamięci: kilka [UdpMux] połączonych tak, że pakiet wysłany
/// z jednego trafia do drugiego po adresie i porcie. Dzięki temu DHT, STUN
/// i łącze dają się sprawdzić bez prawdziwych gniazd, bez internetu i bez
/// drugiego urządzenia — tak samo, jak Bluetooth sprawdza się nad rurą
/// w pamięci.
class FakeUdpNet {
  final _muxes = <String, FakeUdpMux>{};
  final _nats = <String, FakeNat>{};
  final Random _random;

  /// Udział pakietów gubionych w obie strony (0..1). Do testów ARQ.
  double loss;

  /// Opóźnienie dostarczenia. Zero = w następnym mikrozadaniu.
  Duration latency;

  FakeUdpNet({this.loss = 0, this.latency = Duration.zero, int seed = 1})
      : _random = Random(seed);

  /// Gniazdo w sieci. Za [behind] ma adres prywatny i z zewnątrz da się do
  /// niego dotrzeć tylko przez NAT.
  FakeUdpMux create(String address, int port, {FakeNat? behind}) {
    final mux = FakeUdpMux(this, InternetAddress(address), port, behind);
    if (behind == null) _muxes['$address:$port'] = mux;
    return mux;
  }

  /// NAT z adresem publicznym [public]; gniazda za nim tworzy [create]
  /// z `behind`.
  FakeNat createNat(String public,
      {Duration timeout = const Duration(seconds: 60)}) {
    final nat = FakeNat._(this, InternetAddress(public), timeout);
    _nats[public] = nat;
    return nat;
  }

  void _deliver(
      Uint8List data, InternetAddress from, int fromPort, InternetAddress to, int toPort) {
    if (loss > 0 && _random.nextDouble() < loss) return;
    final nat = _nats[to.address];
    final target = _muxes['${to.address}:$toPort'];
    if (nat == null && target == null) return;
    void go() => nat != null
        ? nat._inbound(data, from, fromPort, toPort)
        : target!._receive(UdpPacket(data, from, fromPort));
    if (latency == Duration.zero) {
      scheduleMicrotask(go);
    } else {
      Timer(latency, go);
    }
  }
}

class FakeUdpMux implements UdpMux {
  final FakeUdpNet _net;
  final FakeNat? _nat;
  final InternetAddress address;
  @override
  final int port;

  final _handlers = <UdpHandler>[];
  bool _closed = false;

  /// Ile pakietów wysłano (do pomiaru ruchu w testach).
  int sent = 0;

  FakeUdpMux(this._net, this.address, this.port, [this._nat]);

  @override
  void register(UdpHandler handler) => _handlers.add(handler);

  @override
  void unregister(UdpHandler handler) => _handlers.remove(handler);

  @override
  void send(List<int> data, InternetAddress to, int toPort) {
    if (_closed) return;
    sent++;
    final nat = _nat;
    if (nat != null) {
      nat._outbound(this, Uint8List.fromList(data), to, toPort);
    } else {
      _net._deliver(Uint8List.fromList(data), address, port, to, toPort);
    }
  }

  void _receive(UdpPacket packet) {
    if (_closed) return;
    for (final handler in _handlers.toList()) {
      try {
        if (handler(packet)) return;
      } catch (_) {
        // Obsługa, która rzuciła, po prostu nie bierze pakietu.
      }
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _handlers.clear();
  }
}

/// NAT w pamięci w kształcie obu zmierzonych (docs/spike-nat.md): jedno
/// mapowanie na gniazdo, to samo dla każdego celu, i filtrowanie zależne od
/// adresu i portu. Pakiet z zewnątrz wchodzi tylko od kogoś, do kogo gniazdo
/// samo coś wysłało w ciągu [timeout].
class FakeNat {
  final FakeUdpNet _net;
  final InternetAddress public;
  final Duration timeout;

  var _nextPort = 20000;
  final _ports = <FakeUdpMux, int>{};
  final _byPort = <int, FakeUdpMux>{};

  /// Ostatni pakiet wychodzący: „port publiczny>adres:port celu" -> kiedy.
  final _permits = <String, DateTime>{};

  /// Ile pakietów z zewnątrz NAT odrzucił, bo nikt ich nie zamawiał.
  int dropped = 0;

  FakeNat._(this._net, this.public, this.timeout);

  /// To, co gniazdu za NAT-em powiedziałby STUN.
  StunMapping mappingOf(FakeUdpMux mux) => StunMapping(public, _portOf(mux));

  /// NAT zapomina mapowania i furtki, jak po długiej ciszy. Następny pakiet
  /// z gniazda dostaje nowy port publiczny.
  void forget() {
    _ports.clear();
    _byPort.clear();
    _permits.clear();
  }

  int _portOf(FakeUdpMux mux) => _ports.putIfAbsent(mux, () {
        final port = _nextPort++;
        _byPort[port] = mux;
        return port;
      });

  void _outbound(
      FakeUdpMux mux, Uint8List data, InternetAddress to, int toPort) {
    final port = _portOf(mux);
    _permits['$port>${to.address}:$toPort'] = DateTime.now();
    _net._deliver(data, public, port, to, toPort);
  }

  void _inbound(
      Uint8List data, InternetAddress from, int fromPort, int toPort) {
    final mux = _byPort[toPort];
    final kiedy = _permits['$toPort>${from.address}:$fromPort'];
    if (mux == null ||
        kiedy == null ||
        DateTime.now().difference(kiedy) > timeout) {
      dropped++;
      return;
    }
    mux._receive(UdpPacket(data, from, fromPort));
  }
}
