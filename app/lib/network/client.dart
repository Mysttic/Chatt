import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/identity.dart';
import 'protocol.dart';

/// Klient HTTP do rozmowy z serwerem innego urządzenia (server.dart).
class PeerClient {
  final http.Client _http;

  PeerClient([http.Client? client]) : _http = client ?? http.Client();

  /// Pobiera tożsamość urządzenia pod host:port. Zwraca null, gdy nie
  /// odpowiada albo to nie jest Chatt — służy też jako test obecności
  /// i jako "ręczne dodanie po IP".
  Future<DeviceIdentity?> fetchInfo(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final response = await _http
          .get(Uri.http('$host:$port', '/info'))
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final json = tryDecodeJsonMap(utf8.encode(response.body));
      if (json == null || json['app'] != 'chatt') return null;
      return DeviceIdentity.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Dostarcza wiadomość. true = odbiorca potwierdził zapis (ACK).
  Future<bool> sendMessage({
    required String host,
    required int port,
    required Map<String, Object?> payload,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final response = await _http
          .post(
            Uri.http('$host:$port', '/message'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(timeout);
      if (response.statusCode != 200) return false;
      final json = tryDecodeJsonMap(utf8.encode(response.body));
      return json?['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Wysyła krok parowania (prośbę albo potwierdzenie kodem).
  Future<PairOutcome> pair({
    required String host,
    required int port,
    required Map<String, Object?> payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final response = await _http
          .post(
            Uri.http('$host:$port', '/pair'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(timeout);
      final json = tryDecodeJsonMap(utf8.encode(response.body));
      if (json == null) return PairOutcome.unreachable;
      if (json['ok'] == true) return PairOutcome.accepted;
      final error = json['error'];
      return PairOutcome.fromName(error is String ? error : null);
    } catch (_) {
      return PairOutcome.unreachable;
    }
  }

  /// Zapowiada plik i czeka na decyzję odbiorcy. Zwraca null, gdy odbiorca
  /// nie odpowiada albo nie zna `/file-offer` (protokół 1) — wtedy nadawca
  /// wysyła plik po staremu, bez pytania o zgodę.
  Future<FileOfferReply?> offerFile({
    required String host,
    required int port,
    required Map<String, Object?> payload,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    try {
      final response = await _http
          .post(
            Uri.http('$host:$port', '/file-offer'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(timeout);
      final json = tryDecodeJsonMap(utf8.encode(response.body));
      if (json == null) return null; // 404 z routera = starszy odbiorca
      return FileOfferReply.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Wysyła plik strumieniowo (bez ładowania do pamięci), od bajtu [offset]
  /// (wznowienie przerwanego transferu). [onProgress] dostaje liczbę bajtów
  /// już zapisanych u odbiorcy, licząc te z poprzedniej próby. Timeout skaluje
  /// się z rozmiarem (wolne Wi-Fi nie może ubijać dużych transferów).
  Future<bool> sendFile({
    required String host,
    required int port,
    required Map<String, String> headers,
    required File file,
    int offset = 0,
    void Function(int sentBytes, int totalBytes)? onProgress,
    /// Przepuszczenie treści przez szyfrowanie. Dostaje strumień z pliku
    /// i bajt, od którego się zaczyna (żeby wznowienie trafiło w to samo
    /// miejsce strumienia klucza). Musi zachować długość.
    Stream<List<int>> Function(Stream<List<int>> data, int startOffset)?
        transform,
  }) async {
    // Czytanie pliku żyje własnym życiem obok zapytania. Gdy odbiorca zerwie
    // połączenie w połowie, `send` wraca od razu — a reader leciałby dalej
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
      request = http.StreamedRequest('POST', Uri.http('$host:$port', '/file'))
        ..contentLength = total - start
        ..headers.addAll({...headers, 'content-type': 'application/octet-stream'});

      final source = transform == null
          ? file.openRead(start)
          : transform(file.openRead(start), start);

      var sent = start;
      // Treść idzie przez addStream, bo tylko on hamuje czytanie pliku, gdy
      // sieć nie nadąża (ręczne `sink.add` w pętli buforowało cały plik
      // w pamięci). Pośredni kontroler jest po to, żeby dało się to czytanie
      // anulować, gdy odbiorca zerwie połączenie — inaczej zostaje otwarty
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
      final body = await response.stream.bytesToString().timeout(timeout);
      if (response.statusCode != 200) return false;
      return tryDecodeJsonMap(utf8.encode(body))?['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      // Zerwane połączenie: przestajemy czytać plik (zwalniamy uchwyt)
      // i zamykamy body, żeby nic już nie wołało [onProgress] po tym, jak
      // wołający posprzątał swój stan.
      await reader?.cancel();
      closeBody();
    }
  }

  void dispose() => _http.close();
}
