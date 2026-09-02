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
  /// nie musi znać swojego IP w naszej sieci). [sealed] mówi, czy treść
  /// przyszła w zaszyfrowanej kopercie — czyli czy jest uwierzytelniona.
  /// false = odrzucamy (400).
  final Future<bool> Function(
      IncomingMessage message, String fromHost, bool sealed) onMessage;

  /// Wołane dla POST /pair. Wynik trafia do odpowiedzi, żeby druga strona
  /// wiedziała, czy kod był zły, czy po prostu minął czas.
  final Future<PairReply> Function(PairMessage message, String fromHost)?
      onPair;

  /// Rozpakowanie koperty od sparowanego urządzenia. null = nie mamy klucza
  /// albo treść jest podmieniona; wtedy zapytanie leci do kosza.
  final Future<Map<String, Object?>?> Function(Map<String, Object?> envelope)?
      onEnvelope;

  /// Wołane dla POST /file-offer: odbiorca decyduje, czy chce ten plik
  /// i od którego bajtu ma go dostać. [sealed] jak przy [onMessage].
  final Future<FileOfferReply> Function(
      FileOffer offer, String fromHost, bool sealed)? onFileOffer;

  /// Wołane dla POST /file: odbiorca decyduje, gdzie strumień [data] zapisać.
  /// Zwrócony [FileReceiveResult] ląduje w kodzie odpowiedzi dla nadawcy.
  /// Wyjątek w środku = 500 (nadawca potraktuje wysyłkę jako nieudaną).
  final Future<FileReceiveResult> Function(
      IncomingFileMeta meta, Stream<List<int>> data, String fromHost)? onFile;

  HttpServer? _server;

  ChattServer({
    required this.identity,
    required this.onMessage,
    this.onPair,
    this.onEnvelope,
    this.onFileOffer,
    this.onFile,
  });

  /// Zamienia kopertę na jej zawartość i mówi, czy treść była zaszyfrowana.
  /// Jawny JSON przepuszczamy (niesparowane urządzenia dalej mają działać),
  /// ale wyżej sprawdzamy, czy akurat od tego nadawcy wolno go przyjąć.
  Future<({Map<String, Object?>? json, bool sealed})> _unseal(
      Map<String, Object?>? json) async {
    if (json == null) return (json: null, sealed: false);
    if (!isEncryptedEnvelope(json)) return (json: json, sealed: false);
    final handler = onEnvelope;
    if (handler == null) return (json: null, sealed: true);
    return (json: await handler(json), sealed: true);
  }

  /// Faktyczny port nasłuchu (ustalony w [start]).
  int? get port => _server?.port;

  /// Startuje na pierwszym wolnym porcie z zakresu
  /// [preferredPort] .. [preferredPort]+[attempts]-1 (port 0 = dowolny
  /// przydzielony przez system, używany w testach). Zwraca faktyczny port.
  Future<int> start({required int preferredPort, int attempts = tcpPortAttempts}) async {
    final router = Router()
      ..get('/info', _handleInfo)
      ..post('/message', _handleMessage)
      ..post('/pair', _handlePair)
      ..post('/file-offer', _handleFileOffer)
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
    final opened = await _unseal(tryDecodeJsonMap(body));
    final json = opened.json;
    final message = json == null ? null : IncomingMessage.fromJson(json);
    if (message == null) {
      return _json({'ok': false, 'error': 'bad_request'}, status: 400);
    }

    if (message.from.guid == identity().guid) {
      return _json({'ok': false, 'error': 'self'}, status: 400);
    }

    final connection =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final fromHost = connection?.remoteAddress.address ?? '';

    if (!await onMessage(message, fromHost, opened.sealed)) {
      return _json({'ok': false, 'error': 'unauthenticated'}, status: 400);
    }
    return _json({'ok': true, 'receivedAt': DateTime.now().toUtc().toIso8601String()});
  }

  /// Parowanie: prośba o kod albo przysłany kod do sprawdzenia.
  Future<Response> _handlePair(Request request) async {
    final handler = onPair;
    if (handler == null) {
      return _json({'ok': false, 'error': 'pairing_not_supported'}, status: 404);
    }
    final body = await request.read().expand((chunk) => chunk).toList();
    final json = tryDecodeJsonMap(body);
    final message = json == null ? null : PairMessage.fromJson(json);
    if (message == null) {
      return _json({'ok': false, 'error': 'bad_request'}, status: 400);
    }
    if (message.from.guid == identity().guid) {
      return _json({'ok': false, 'error': 'self'}, status: 400);
    }
    final connection =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final reply =
        await handler(message, connection?.remoteAddress.address ?? '');
    final accepted = reply.accepted;
    return _json(
      reply.toJson(),
      status: accepted ? 200 : 403,
    );
  }

  /// Zapowiedź pliku — pytamy użytkownika, zanim przyjmiemy choć bajt.
  Future<Response> _handleFileOffer(Request request) async {
    final handler = onFileOffer;
    if (handler == null) {
      return _json({'ok': false, 'error': 'files_not_supported'}, status: 404);
    }
    final body = await request.read().expand((chunk) => chunk).toList();
    final opened = await _unseal(tryDecodeJsonMap(body));
    final json = opened.json;
    final offer = json == null ? null : FileOffer.fromJson(json);
    if (offer == null) {
      return _json({'ok': false, 'error': 'bad_request'}, status: 400);
    }
    if (offer.from.guid == identity().guid) {
      return _json({'ok': false, 'error': 'self'}, status: 400);
    }
    final connection =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final reply = await handler(
        offer, connection?.remoteAddress.address ?? '', opened.sealed);
    return _json(
      {'ok': true, ...reply.toJson()},
      // 403 = świadoma odmowa użytkownika; nadawca nie ponawia jej sam z siebie.
      status: reply.accepted ? 200 : 403,
    );
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
    // Pętla na siebie samego (źle skonfigurowany tunel/przekierowanie portu)
    // nie może skończyć się rozmową z samym sobą.
    if (meta.from.guid == identity().guid) {
      return _json({'ok': false, 'error': 'self'}, status: 400);
    }
    final connection =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final result =
        await handler(meta, request.read(), connection?.remoteAddress.address ?? '');
    if (result == FileReceiveResult.ok) {
      return _json(
          {'ok': true, 'receivedAt': DateTime.now().toUtc().toIso8601String()});
    }
    return _json(
      {'ok': false, 'error': result.name},
      status: switch (result) {
        FileReceiveResult.ok => 200,
        FileReceiveResult.rejected => 403,
        FileReceiveResult.offsetMismatch => 409,
        FileReceiveResult.incomplete => 409,
        FileReceiveResult.checksumMismatch => 422,
      },
    );
  }

  static Response _json(Map<String, Object?> body, {int status = 200}) =>
      Response(status,
          body: jsonEncode(body), headers: {'content-type': 'application/json'});
}
