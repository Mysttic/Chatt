import 'dart:convert';

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

  void dispose() => _http.close();
}
