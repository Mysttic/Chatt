import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:chatt/network/udp_mux.dart';

/// Sieć UDP w pamięci: kilka [UdpMux] połączonych tak, że pakiet wysłany
/// z jednego trafia do drugiego po adresie i porcie. Dzięki temu DHT, STUN
/// i łącze dają się sprawdzić bez prawdziwych gniazd, bez internetu i bez
/// drugiego urządzenia — tak samo, jak Bluetooth sprawdza się nad rurą
/// w pamięci.
class FakeUdpNet {
  final _muxes = <String, FakeUdpMux>{};
  final Random _random;

  /// Udział pakietów gubionych w obie strony (0..1). Do testów ARQ.
  double loss;

  /// Opóźnienie dostarczenia. Zero = w następnym mikrozadaniu.
  Duration latency;

  FakeUdpNet({this.loss = 0, this.latency = Duration.zero, int seed = 1})
      : _random = Random(seed);

  FakeUdpMux create(String address, int port) {
    final mux = FakeUdpMux(this, InternetAddress(address), port);
    _muxes['$address:$port'] = mux;
    return mux;
  }

  void _deliver(
      Uint8List data, InternetAddress from, int fromPort, InternetAddress to, int toPort) {
    if (loss > 0 && _random.nextDouble() < loss) return;
    final target = _muxes['${to.address}:$toPort'];
    if (target == null) return;
    void go() => target._receive(UdpPacket(data, from, fromPort));
    if (latency == Duration.zero) {
      scheduleMicrotask(go);
    } else {
      Timer(latency, go);
    }
  }
}

class FakeUdpMux implements UdpMux {
  final FakeUdpNet _net;
  final InternetAddress address;
  @override
  final int port;

  final _handlers = <UdpHandler>[];
  bool _closed = false;

  /// Ile pakietów wysłano (do pomiaru ruchu w testach).
  int sent = 0;

  FakeUdpMux(this._net, this.address, this.port);

  @override
  void register(UdpHandler handler) => _handlers.add(handler);

  @override
  void unregister(UdpHandler handler) => _handlers.remove(handler);

  @override
  void send(List<int> data, InternetAddress to, int toPort) {
    if (_closed) return;
    sent++;
    _net._deliver(
        Uint8List.fromList(data), address, port, to, toPort);
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
