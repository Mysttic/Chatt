import 'dart:convert';

import 'crypto.dart';
import 'identity.dart';

/// Treść kodu QR do potwierdzenia tożsamości.
///
/// Nie ma tu żadnego sekretu: klucz publiczny i adres są jawne. Wartość tego
/// kodu bierze się z **kanału**, a nie z zawartości — kto go zeskanował, ten
/// widział ekran drugiego urządzenia, więc wie, że dostał klucz od niego,
/// a nie od kogoś po drodze.
///
/// Identyfikatora nie ma w kodzie, bo wynika z klucza (patrz
/// [ChattCrypto.guidFromPublicKey]). Krótszy kod to rzadsza siatka i łatwiejsze
/// skanowanie.
class PairLink {
  final List<int> publicKey;
  final String host;
  final int port;
  final String name;

  const PairLink({
    required this.publicKey,
    required this.host,
    required this.port,
    required this.name,
  });

  String get guid => ChattCrypto.guidFromPublicKey(publicKey);

  static const String _scheme = 'chatt';
  static const String _host = 'pair';

  /// Kod dla tego urządzenia. [address] to adres, pod którym jest osiągalne
  /// w tej sieci — bierzemy pierwszy sensowny z listy interfejsów.
  static String encode({
    required DeviceIdentity identity,
    required String address,
  }) =>
      Uri(
        scheme: _scheme,
        host: _host,
        queryParameters: {
          'k': base64Url.encode(identity.publicKey),
          'h': address,
          'p': '${identity.tcpPort}',
          'n': identity.name,
        },
      ).toString();

  /// Zwraca null dla wszystkiego, co nie jest naszym kodem — aparat widzi
  /// mnóstwo kodów, które nas nie dotyczą.
  static PairLink? decode(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != _scheme || uri.host != _host) return null;

    final klucz = _decodeKey(uri.queryParameters['k']);
    final host = uri.queryParameters['h'];
    final port = int.tryParse(uri.queryParameters['p'] ?? '');
    if (klucz == null ||
        host == null ||
        host.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535) {
      return null;
    }
    return PairLink(
      publicKey: klucz,
      host: host,
      port: port,
      name: uri.queryParameters['n']?.trim().isNotEmpty == true
          ? uri.queryParameters['n']!.trim()
          : host,
    );
  }

  /// base64url bez wyrównania też przyjmujemy — różne czytniki potrafią je
  /// obciąć, a X25519 i tak ma zawsze 32 bajty, więc długość sprawdzamy sami.
  static List<int>? _decodeKey(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final wyrownane = value.padRight((value.length + 3) ~/ 4 * 4, '=');
      final bytes = base64Url.decode(wyrownane);
      return bytes.length == 32 ? bytes : null;
    } catch (_) {
      return null;
    }
  }
}
