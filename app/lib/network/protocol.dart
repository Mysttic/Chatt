import 'dart:convert';

import '../core/identity.dart';

/// Stałe i kształty komunikatów protokołu Chatt.
///
/// Discovery: UDP na stałym porcie [discoveryPort]. Skaner wysyła broadcast
/// [typeDiscover] ze swoją tożsamością, każde urządzenie odpowiada unicastem
/// [typeHere]. Dzięki temu, że zapytanie też niesie tożsamość, OBIE strony
/// poznają się po jednym skanie.
///
/// Wiadomości: każde urządzenie hostuje serwer HTTP (patrz server.dart).
///   GET  /info     -> tożsamość urządzenia (używane też jako "ping")
///   POST /message  -> dostarczenie wiadomości; 200 = potwierdzenie odbioru

const int discoveryPort = 47777;
const int defaultTcpPort = 47780;

/// Ile kolejnych portów TCP próbujemy, gdy preferowany jest zajęty
/// (np. druga instancja aplikacji na tym samym komputerze).
const int tcpPortAttempts = 10;

const String typeDiscover = 'chatt_discover';
const String typeHere = 'chatt_here';

/// Wersja protokołu — podbijamy przy niekompatybilnych zmianach.
const int protocolVersion = 1;

Map<String, Object?> discoverPacket(DeviceIdentity me) => {
      'type': typeDiscover,
      'proto': protocolVersion,
      ...me.toJson(),
    };

Map<String, Object?> herePacket(DeviceIdentity me) => {
      'type': typeHere,
      'proto': protocolVersion,
      ...me.toJson(),
    };

/// Bezpieczne dekodowanie datagramu/body: śmieci z sieci nie mogą wywalić
/// aplikacji, więc każdy błąd parsowania oznacza po prostu "to nie nasze".
Map<String, Object?>? tryDecodeJsonMap(List<int> bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    return decoded is Map<String, Object?> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Wiadomość przychodząca przez POST /message.
class IncomingMessage {
  final String messageGuid;
  final DeviceIdentity from;
  final String text;
  final DateTime sentAt;

  const IncomingMessage({
    required this.messageGuid,
    required this.from,
    required this.text,
    required this.sentAt,
  });

  static IncomingMessage? fromJson(Map<String, Object?> json) {
    final guid = json['messageGuid'];
    final text = json['text'];
    final from = DeviceIdentity.fromJson(json['from']);
    if (guid is! String || guid.isEmpty || text is! String || from == null) {
      return null;
    }
    final sentAt = DateTime.tryParse(json['sentAt'] is String ? json['sentAt'] as String : '');
    return IncomingMessage(
      messageGuid: guid,
      from: from,
      text: text,
      sentAt: sentAt ?? DateTime.now(),
    );
  }
}

Map<String, Object?> messagePacket({
  required String messageGuid,
  required DeviceIdentity from,
  required String text,
  required DateTime sentAt,
}) =>
    {
      'messageGuid': messageGuid,
      'from': from.toJson(),
      'text': text,
      'sentAt': sentAt.toUtc().toIso8601String(),
    };
