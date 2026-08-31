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

// --- Pliki: POST /file --------------------------------------------------
// Treść zapytania to surowe bajty pliku (streaming w obie strony, żeby duże
// pliki nie przechodziły przez pamięć). Metadane jadą w nagłówkach — muszą
// być ASCII, stąd base64/percent-encoding.

const String headerMessageGuid = 'x-chatt-message-guid';
const String headerFrom = 'x-chatt-from';
const String headerFileName = 'x-chatt-file-name';
const String headerFileSize = 'x-chatt-file-size';
const String headerSentAt = 'x-chatt-sent-at';

String encodeIdentityHeader(DeviceIdentity identity) =>
    base64Url.encode(utf8.encode(jsonEncode(identity.toJson())));

DeviceIdentity? decodeIdentityHeader(String? value) {
  if (value == null) return null;
  try {
    return DeviceIdentity.fromJson(jsonDecode(utf8.decode(base64Url.decode(value))));
  } catch (_) {
    return null;
  }
}

/// Metadane pliku przychodzącego przez POST /file.
class IncomingFileMeta {
  final String messageGuid;
  final DeviceIdentity from;
  final String fileName;
  final int fileSize;
  final DateTime sentAt;

  const IncomingFileMeta({
    required this.messageGuid,
    required this.from,
    required this.fileName,
    required this.fileSize,
    required this.sentAt,
  });

  static IncomingFileMeta? fromHeaders(Map<String, String> headers) {
    final guid = headers[headerMessageGuid];
    final from = decodeIdentityHeader(headers[headerFrom]);
    final rawName = headers[headerFileName];
    final size = int.tryParse(headers[headerFileSize] ?? '');
    if (guid == null || guid.isEmpty || from == null || rawName == null || size == null || size < 0) {
      return null;
    }
    String name;
    try {
      name = Uri.decodeComponent(rawName);
    } catch (_) {
      return null;
    }
    final sentAt = DateTime.tryParse(headers[headerSentAt] ?? '');
    return IncomingFileMeta(
      messageGuid: guid,
      from: from,
      fileName: name,
      fileSize: size,
      sentAt: sentAt ?? DateTime.now(),
    );
  }
}
