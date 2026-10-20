import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'transport.dart';

/// Dotychczasowa droga: HTTP po TCP w sieci lokalnej.
///
/// Kod jest ten sam, który stał w `PeerClient` od początku. Zmieniło się
/// jedno: adres przychodzi jako [IpRoute], a wynik wraca jako
/// [TransportReply], z którego obiekt domenowy składa klient. Zachowanie, limity
/// czasu i sposób strumieniowania pliku zostają co do bajtu.
class HttpTransport implements PeerTransport {
  final http.Client _http;

  /// Błąd w trakcie strumieniowania pliku (zerwane połączenie, przekroczony
  /// czas, plik, którego nie da się czytać). Wynik i tak wraca jako
  /// nieosiągalny; to jest ślad z powodem dla dziennika aplikacji. Zwykłe
  /// zapytania nie zgłaszają niczego: nieosiągalny rozmówca przy sprawdzaniu
  /// obecności to codzienność.
  void Function(PeerRoute route, String path, Object error)? onStreamError;

  HttpTransport([http.Client? client]) : _http = client ?? http.Client();

  @override
  PeerProtocol get protocol => PeerProtocol.wifi;

  @override
  bool handles(PeerRoute route) => route is IpRoute && route.isUsable;

  @override
  Future<TransportReply> request(
    PeerRoute route,
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int> body = const [],
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (route is! IpRoute || !route.isUsable) {
      return const TransportReply.unreachable();
    }
    final uri = Uri.http('${route.host}:${route.port}', path);
    try {
      final response = method == 'GET'
          ? await _http.get(uri, headers: headers).timeout(timeout)
          : await _http
              .post(uri, headers: headers, body: body)
              .timeout(timeout);
      return TransportReply(response.statusCode, response.bodyBytes);
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
    if (route is! IpRoute || !route.isUsable) {
      return const TransportReply.unreachable();
    }
    // Czytanie pliku żyje własnym życiem obok zapytania. Gdy odbiorca zerwie
    // połączenie w połowie, `send` wraca od razu, a reader leciałby dalej
    // i wołał [onProgress] po tym, jak wołający posprzątał swój stan.
    // Stąd subskrypcja: w `finally` ją kasujemy i wyciszamy postęp.
    http.StreamedRequest? request;
    StreamSubscription<List<int>>? reader;
    void closeBody() {
      try {
        request?.sink.close();
      } catch (_) {}
    }

    try {
      final total = await file.length();
      final start = (offset < 0 || offset > total) ? 0 : offset;
      request = http.StreamedRequest(
          'POST', Uri.http('${route.host}:${route.port}', path))
        ..contentLength = total - start
        ..headers.addAll({...headers, 'content-type': 'application/octet-stream'});

      final source = transform == null
          ? file.openRead(start)
          : transform(file.openRead(start), start);

      var sent = start;
      // Treść idzie przez addStream, bo tylko on hamuje czytanie pliku, gdy
      // sieć nie nadąża (ręczne `sink.add` w pętli buforowało cały plik
      // w pamięci). Pośredni kontroler jest po to, żeby dało się to czytanie
      // anulować, gdy odbiorca zerwie połączenie: inaczej zostaje otwarty
      // uchwyt do pliku i strumień pompujący w próżnię.
      final pump = StreamController<List<int>>();
      reader = source.listen(
        (chunk) {
          sent += chunk.length;
          onProgress?.call(sent, total);
          pump.add(chunk);
        },
        onDone: pump.close,
        onError: (Object _) => pump.close(),
        cancelOnError: true,
      );
      pump.onPause = reader.pause;
      pump.onResume = reader.resume;
      pump.onCancel = reader.cancel;

      unawaited(request.sink
          .addStream(pump.stream)
          .whenComplete(closeBody)
          .catchError((Object _) {}));

      final timeout = Duration(seconds: 30 + (total - start) ~/ (512 * 1024));
      final response = await _http.send(request).timeout(timeout);
      final body = await response.stream.toBytes().timeout(timeout);
      return TransportReply(response.statusCode, body);
    } catch (blad) {
      try {
        onStreamError?.call(route, path, blad);
      } catch (_) {
        // Zgłoszenie jest dodatkiem: wynik to i tak „nieosiągalny”.
      }
      return const TransportReply.unreachable();
    } finally {
      // Zerwane połączenie: przestajemy czytać plik (zwalniamy uchwyt)
      // i zamykamy body, żeby nic już nie wołało [onProgress] po tym, jak
      // wołający posprzątał swój stan.
      await reader?.cancel();
      closeBody();
    }
  }

  @override
  Future<void> dispose() async => _http.close();
}
