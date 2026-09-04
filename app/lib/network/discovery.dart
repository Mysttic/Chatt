import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/crypto.dart';
import '../core/identity.dart';
import 'protocol.dart';

/// Urządzenie znalezione w sieci (albo nadawca zapytania discovery).
class DiscoveredPeer {
  final String guid;
  final String name;
  final String welcomeMessage;
  final String host;
  final int tcpPort;

  /// Klucz publiczny znalezionego urządzenia. Od protokołu 5 discovery go
  /// niesie, więc pierwszą wiadomość da się zaszyfrować bez dodatkowej rundy.
  final List<int> publicKey;

  const DiscoveredPeer({
    required this.guid,
    required this.name,
    required this.welcomeMessage,
    required this.host,
    required this.tcpPort,
    this.publicKey = const [],
  });

  @override
  String toString() => 'DiscoveredPeer($name @ $host:$tcpPort)';
}

/// Pakiet na urządzenie. Tożsamość musi się zgadzać ze swoim kluczem: guid
/// jest skrótem klucza publicznego, więc ogłoszenie cudzego identyfikatora ze
/// swoim kluczem odpada już tutaj i nie wchodzi do żadnej listy.
DiscoveredPeer? _peerFromPacket(Map<String, Object?> packet, String host) {
  final identity = DeviceIdentity.fromJson(packet);
  if (identity == null) return null;
  if (identity.hasKey &&
      ChattCrypto.guidFromPublicKey(identity.publicKey) != identity.guid) {
    return null;
  }
  return DiscoveredPeer(
    guid: identity.guid,
    name: identity.name,
    welcomeMessage: identity.welcomeMessage,
    host: host,
    tcpPort: identity.tcpPort,
    publicKey: identity.publicKey,
  );
}

/// Nasłuchuje na [discoveryPort] i odpowiada na zapytania discovery własną
/// tożsamością. Dodatkowo zgłasza nadawcę zapytania przez [onPeerSeen] —
/// dzięki temu jeden skan uczy obie strony nawzajem.
class DiscoveryResponder {
  final DeviceIdentity Function() identity;
  final void Function(DiscoveredPeer peer)? onPeerSeen;

  /// Podpis odpowiedzi dla pytającego, jeśli już go znamy. null = nieznajomy,
  /// odpowiadamy bez podpisu (nie ma z czego go policzyć).
  final Future<String?> Function(DiscoveredPeer pytajacy, String nonce)? sign;

  RawDatagramSocket? _socket;

  DiscoveryResponder({required this.identity, this.onPeerSeen, this.sign});

  bool get isRunning => _socket != null;

  Future<void> start() async {
    if (_socket != null) return;
    // reusePort pozwala dwóm instancjom na jednej maszynie dzielić port:
    // broadcasty trafiają wtedy do obu. Przydaje się wyłącznie w testach
    // i przy dwóch kopiach aplikacji na jednym pulpicie.
    //
    // Lista platform jest wyliczona, a nie wykluczająca Windows, bo Dart nie
    // wspiera SO_REUSEPORT także na Androidzie: bind rzucał tam wyjątek,
    // `AppServices.start` go połykał i telefon po cichu przestawał odpowiadać
    // na cudze skany. W logu widać było tylko
    // „`reusePort` not supported on this platform".
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
      reusePort: Platform.isLinux || Platform.isMacOS,
    );
    socket.broadcastEnabled = true;
    socket.listen((event) async {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final packet = tryDecodeJsonMap(datagram.data);
      if (packet == null || packet['type'] != typeDiscover) return;

      final me = identity();
      if (packet['guid'] == me.guid) return; // własny broadcast

      final sender = _peerFromPacket(packet, datagram.address.address);
      if (sender != null) onPeerSeen?.call(sender);

      final nonce = packet['nonce'];
      final tag = (sender == null || nonce is! String || sign == null)
          ? null
          : await sign!(sender, nonce);

      // Odpowiedź unicastem prosto do gniazda skanera. Gniazdo mogło się
      // w międzyczasie zamknąć (podpisywanie jest asynchroniczne).
      if (_socket == null) return;
      socket.send(
        utf8.encode(jsonEncode(herePacket(me, tag: tag))),
        datagram.address,
        datagram.port,
      );
    });
    _socket = socket;
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }
}

/// Jednorazowy skan sieci: broadcast zapytania + zbieranie odpowiedzi.
class DiscoveryScanner {
  /// Wysyła zapytanie i przez [timeout] zbiera odpowiedzi. [onFound] jest
  /// wołane na żywo (do UI), wynik zawiera komplet bez duplikatów.
  ///
  /// [accept] dostaje znalezione urządzenie i podpis z jego odpowiedzi.
  /// Zwrócenie false wyrzuca wpis z wyniku — tak odsiewamy podszywanie się
  /// pod sparowane urządzenia (patrz `AppServices`).
  static Future<List<DiscoveredPeer>> scan(
    DeviceIdentity me, {
    Duration timeout = const Duration(seconds: 2),
    void Function(DiscoveredPeer peer)? onFound,
    Future<bool> Function(DiscoveredPeer peer, String? tag, String nonce)?
        accept,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;

    final nonce = newDiscoveryNonce();
    final found = <String, DiscoveredPeer>{};
    final pending = <Future<void>>[];
    final done = Completer<void>();

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final packet = tryDecodeJsonMap(datagram.data);
      if (packet == null || packet['type'] != typeHere) return;
      final peer = _peerFromPacket(packet, datagram.address.address);
      if (peer == null || peer.guid == me.guid) return;
      if (found.containsKey(peer.guid)) return;
      // Wpis rezerwujemy od razu, żeby powtórzona odpowiedź (skan wysyła
      // zapytanie dwa razy) nie weszła drugi raz w sprawdzanie podpisu.
      found[peer.guid] = peer;
      final tag = packet['tag'];
      pending.add(() async {
        final ok = accept == null ||
            await accept(peer, tag is String ? tag : null, nonce);
        if (!ok) {
          found.remove(peer.guid);
          return;
        }
        onFound?.call(peer);
      }());
    });

    final payload = utf8.encode(jsonEncode(discoverPacket(me, nonce)));
    for (final target in await _broadcastTargets()) {
      try {
        socket.send(payload, target, discoveryPort);
      } on SocketException {
        // np. interfejs bez uprawnień do broadcastu — pomijamy
      }
    }
    // Powtórka po chwili: pojedynczy datagram UDP w Wi-Fi łatwo ginie.
    Timer(const Duration(milliseconds: 400), () async {
      if (done.isCompleted) return;
      for (final target in await _broadcastTargets()) {
        if (done.isCompleted) return;
        try {
          socket.send(payload, target, discoveryPort);
        } on SocketException {
          // jw.
        }
      }
    });

    Timer(timeout, () {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    socket.close();
    // Sprawdzanie podpisów jest asynchroniczne — czekamy, aż wszystkie
    // odpowiedzi przejdą przez sito, zanim oddamy listę.
    await Future.wait(pending);
    return found.values.toList();
  }

  /// Adresy broadcast: globalny 255.255.255.255 plus kierowane per interfejs.
  /// dart:io nie zdradza maski podsieci, więc zakładamy /24 — to pokrywa
  /// typowe sieci domowe; globalny broadcast łapie resztę przypadków.
  static Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <String>{'255.255.255.255'};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
          }
        }
      }
    } catch (_) {
      // brak listy interfejsów -> zostaje broadcast globalny
    }
    return targets.map(InternetAddress.new).toList();
  }
}
