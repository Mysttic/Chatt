import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../core/identity.dart';
import 'protocol.dart';

/// Serwer HTTP tej instancji — to przez niego przychodzą wiadomości od
/// innych urządzeń. Działa identycznie na Windows, Linuksie i Androidzie
/// (dart:io), więc każde urządzenie jest równorzędnym "peerem".
class ChattServer {
  final DeviceIdentity Function() identity;

  /// Wołane po zdekodowaniu poprawnej wiadomości; [fromHost] to adres IP,
  /// z którego przyszło połączenie (bo nadawca zna swój port serwera, ale
  /// nie musi znać swojego IP w naszej sieci).
  final Future<void> Function(IncomingMessage message, String fromHost) onMessage;

  /// Wołane dla POST /file: odbiorca decyduje, gdzie strumień [data] zapisać.
  /// Wyjątek w środku = 500 dla nadawcy (potraktuje wysyłkę jako nieudaną).
  final Future<void> Function(
      IncomingFileMeta meta, Stream<List<int>> data, String fromHost)? onFile;

  HttpServer? _server;

  ChattServer({required this.identity, required this.onMessage, this.onFile});

  /// Faktyczny port nasłuchu (ustalony w [start]).
  int? get port => _server?.port;

  /// Startuje na pierwszym wolnym porcie z zakresu
  /// [preferredPort] .. [preferredPort]+[attempts]-1 (port 0 = dowolny
  /// przydzielony przez system, używany w testach). Zwraca faktyczny port.
  Future<int> start({required int preferredPort, int attempts = tcpPortAttempts}) async {
    final router = Router()
      ..get('/info', _handleInfo)
      ..post('/message', _handleMessage)
      ..post('/file', _handleFile);
    final handler =
        const Pipeline().addMiddleware(_guardErrors).addHandler(router.call);

    final tries = preferredPort == 0 ? 1 : attempts;
    Object? lastError;
    for (var i = 0; i < tries; i++) {
      try {
        _server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          preferredPort == 0 ? 0 : preferredPort + i,
        );
        return _server!.port;
      } on SocketException catch (e) {
        lastError = e; // port zajęty — próbujemy następny
      }
    }
    throw StateError('Nie udało się otworzyć portu serwera: $lastError');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Nic z sieci nie może położyć serwera: błąd handlera to 500 i jedziemy dalej.
  Middleware get _guardErrors => (inner) => (request) async {
        try {
          return await inner(request);
        } catch (_) {
          return Response.internalServerError(body: '{"ok":false}');
        }
      };

  Response _handleInfo(Request request) => _json({
        'app': 'chatt',
        'proto': protocolVersion,
        ...identity().toJson(),
      });

  Future<Response> _handleMessage(Request request) async {
    final body = await request.read().expand((chunk) => chunk).toList();
    final json = tryDecodeJsonMap(body);
    final message = json == null ? null : IncomingMessage.fromJson(json);
    if (message == null) {
      return _json({'ok': false, 'error': 'bad_request'}, status: 400);
    }

    final connection =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final fromHost = connection?.remoteAddress.address ?? '';

    await onMessage(message, fromHost);
    return _json({'ok': true, 'receivedAt': DateTime.now().toUtc().toIso8601String()});
  }

  Future<Response> _handleFile(Request request) async {
    final handler = onFile;
    if (handler == null) {
      return _json({'ok': false, 'error': 'files_not_supported'}, status: 404);
    }
    final meta = IncomingFileMeta.fromHeaders(request.headers);
    if (meta == null) {
      return _json({'ok': false, 'error': 'bad_request'}, status: 400);
    }
    final connection =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    await handler(meta, request.read(), connection?.remoteAddress.address ?? '');
    return _json({'ok': true, 'receivedAt': DateTime.now().toUtc().toIso8601String()});
  }

  static Response _json(Map<String, Object?> body, {int status = 200}) =>
      Response(status,
          body: jsonEncode(body), headers: {'content-type': 'application/json'});
}
