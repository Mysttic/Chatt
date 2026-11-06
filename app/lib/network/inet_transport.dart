import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bt_link.dart';
import 'inet_link.dart';
import 'secure_udp.dart';
import 'transport.dart';

/// Internet jako droga dla bajtów Chatta, obok sieci lokalnej i Bluetootha.
///
/// Trzyma po jednym łączu na rozmówcę ([InetLinkManager] przebija dziurę,
/// [SecureUdpPipe] szyfruje i porządkuje) i zwielokrotnia na nim wymiany tym
/// samym multiplekserem [BtLink], co pozostałe transporty. Dzięki temu
/// żądanie i odpowiedź wyglądają tak samo, którędy by nie szły: ten sam
/// routing, ci sami obsługujący, to samo szyfrowanie warstwy aplikacji.
class InternetTransport implements PeerTransport {
  final InetLinkManager manager;

  /// Obsługa żądań od drugiej strony — ta sama, którą karmi serwer HTTP.
  /// Drugi argument to guid rozmówcy (trasa internetowa adresuje po
  /// tożsamości, nie po adresie).
  final Future<BtResponse> Function(BtRequest request, String peerGuid)?
      onRequest;

  /// Błąd w trakcie strumieniowania pliku, jak w pozostałych transportach.
  void Function(PeerRoute route, String path, Object error)? onStreamError;

  final _links = <String, _Muxed>{};
  bool _running = false;

  InternetTransport({
    required this.manager,
    this.onRequest,
  }) {
    manager.onNewPipe = _wrapIncoming;
  }

  @override
  PeerProtocol get protocol => PeerProtocol.internet;

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    manager.start();
    _running = true;
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    for (final m in _links.values.toList()) {
      await m.link.close();
    }
    _links.clear();
    await manager.stop();
  }

  @override
  Future<void> dispose() => stop();

  @override
  bool handles(PeerRoute route) =>
      _running && route is InternetRoute && route.isUsable;

  bool isLinked(String guid) {
    final m = _links[guid];
    return m != null && !m.link.isClosed && !m.pipe.isClosed;
  }

  List<String> get linkedGuids => [
        for (final e in _links.entries)
          if (!e.value.link.isClosed) e.key,
      ];

  /// Opakowuje świeżo postawione łącze przychodzące w multiplekser.
  void _wrapIncoming(String guid, SecureUdpPipe pipe) {
    final istniejace = _links[guid];
    if (istniejace != null && !istniejace.link.isClosed) return;
    _bind(guid, pipe);
  }

  _Muxed _bind(String guid, SecureUdpPipe pipe) {
    final handler = onRequest;
    final link = BtLink(
      pipe,
      initiator: pipe.initiator,
      onRequest:
          handler == null ? null : (request) => handler(request, guid),
    );
    final muxed = _Muxed(link, pipe);
    _links[guid] = muxed;
    // Gdy rura padnie, zamyka swój strumień wejścia, a wtedy multiplekser
    // domyka się sam (jego czytnik dostaje „koniec"). Nieaktualny wpis
    // sprząta [_muxFor] przy następnej próbie.
    return muxed;
  }

  /// Łącze do rozmówcy: istniejące albo świeżo przebite.
  Future<_Muxed?> _muxFor(String guid) async {
    final istniejace = _links[guid];
    if (istniejace != null &&
        !istniejace.link.isClosed &&
        !istniejace.pipe.isClosed) {
      return istniejace;
    }
    if (istniejace != null) {
      await istniejace.link.close();
      _links.remove(guid);
    }
    final pipe = await manager.linkTo(guid);
    if (pipe == null) return null;
    // Łącze przychodzące mogło w międzyczasie już zostać opakowane.
    final poZwrocie = _links[guid];
    if (poZwrocie != null && !poZwrocie.link.isClosed) return poZwrocie;
    return _bind(guid, pipe);
  }

  @override
  Future<TransportReply> request(
    PeerRoute route,
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int> body = const [],
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (route is! InternetRoute || !route.isUsable || !_running) {
      return const TransportReply.unreachable();
    }
    try {
      // `_muxFor` sięga do DHT i STUN-u: błąd stamtąd (brak węzłów, cisza
      // sieci) ma być „nieosiągalny", a nie wyjątkiem lecącym do wołającego.
      final muxed = await _muxFor(route.guid);
      if (muxed == null) return const TransportReply.unreachable();
      final response = await muxed.link
          .send(
            method,
            path,
            headers: headers,
            body: body.isEmpty ? null : Stream<List<int>>.value(body),
          )
          // Przez internet obrót trwa dłużej niż w sieci lokalnej: dajemy
          // zapas jak przy Bluetoothcie, żeby wolniejsze łącze nie wyglądało
          // na zerwane.
          .timeout(timeout * 3);
      return TransportReply(response.status, await _collect(response.body));
    } catch (_) {
      return const TransportReply.unreachable();
    }
  }

  @override
  Future<TransportReply> stream(
    PeerRoute route,
    String path, {
    required Map<String, String> headers,
    required File file,
    int offset = 0,
    void Function(int sentBytes, int totalBytes)? onProgress,
    Stream<List<int>> Function(Stream<List<int>> data, int startOffset)?
        transform,
  }) async {
    if (route is! InternetRoute || !route.isUsable || !_running) {
      return const TransportReply.unreachable();
    }
    try {
      final muxed = await _muxFor(route.guid);
      if (muxed == null) return const TransportReply.unreachable();
      final total = await file.length();
      final start = (offset < 0 || offset > total) ? 0 : offset;
      var sent = start;
      final source = transform == null
          ? file.openRead(start)
          : transform(file.openRead(start), start);
      final counted = source.map((chunk) {
        sent += chunk.length;
        onProgress?.call(sent, total);
        return chunk;
      });
      final response = await muxed.link.send(
        'POST',
        path,
        headers: {...headers, 'content-type': 'application/octet-stream'},
        body: counted,
      );
      return TransportReply(response.status, await _collect(response.body));
    } catch (blad) {
      try {
        onStreamError?.call(route, path, blad);
      } catch (_) {
        // Zgłoszenie jest dodatkiem; wynik to i tak „nieosiągalny".
      }
      return const TransportReply.unreachable();
    }
  }

  static Future<List<int>> _collect(Stream<List<int>> body) async {
    final out = <int>[];
    await for (final chunk in body) {
      out.addAll(chunk);
    }
    return out;
  }

  static String asText(TransportReply reply) =>
      utf8.decode(reply.body, allowMalformed: true);
}

/// Łącze (rura) i jego multiplekser razem.
class _Muxed {
  final BtLink link;
  final SecureUdpPipe pipe;
  _Muxed(this.link, this.pipe);
}
