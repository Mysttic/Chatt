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
/// 2: pliki wysyłane po akceptacji odbiorcy (POST /file-offer), ze wznawianiem
///    i sumą kontrolną.
const int protocolVersion = 2;

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

// --- Pliki: POST /file-offer, POST /file ---------------------------------
// Transfer jest dwuetapowy:
//   1. POST /file-offer — JSON z metadanymi (nazwa, rozmiar, sha256).
//      Odbiorca pyta użytkownika i odpowiada [FileOfferReply]: zgoda albo
//      odmowa, "już to mam" (dedupe bez przesyłania bajtów) oraz offset,
//      od którego można wznowić wcześniej przerwany transfer.
//   2. POST /file — surowe bajty od tego offsetu (streaming w obie strony,
//      żeby duże pliki nie przechodziły przez pamięć). Metadane jadą
//      w nagłówkach — muszą być ASCII, stąd base64/percent-encoding.

const String headerMessageGuid = 'x-chatt-message-guid';
const String headerFrom = 'x-chatt-from';
const String headerFileName = 'x-chatt-file-name';
const String headerFileSize = 'x-chatt-file-size';
const String headerSentAt = 'x-chatt-sent-at';

/// sha256 całego pliku (hex). Odbiorca weryfikuje po złożeniu wszystkich
/// części — chroni przed cichym uszkodzeniem przy wznawianiu transferu.
const String headerFileSha256 = 'x-chatt-file-sha256';

/// Od którego bajtu nadawca wysyła treść (0 = całość, >0 = wznowienie).
const String headerFileOffset = 'x-chatt-file-offset';

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

  /// Suma kontrolna całego pliku (hex) — null u nadawcy w protokole 1.
  final String? sha256;

  /// Bajt, od którego zaczyna się treść tego zapytania.
  final int offset;

  const IncomingFileMeta({
    required this.messageGuid,
    required this.from,
    required this.fileName,
    required this.fileSize,
    required this.sentAt,
    this.sha256,
    this.offset = 0,
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
    final offset = int.tryParse(headers[headerFileOffset] ?? '0');
    if (offset == null || offset < 0 || offset > size) return null;
    final sha = headers[headerFileSha256];
    final sentAt = DateTime.tryParse(headers[headerSentAt] ?? '');
    return IncomingFileMeta(
      messageGuid: guid,
      from: from,
      fileName: name,
      fileSize: size,
      sentAt: sentAt ?? DateTime.now(),
      sha256: (sha == null || sha.isEmpty) ? null : sha,
      offset: offset,
    );
  }
}

/// Zapowiedź pliku (POST /file-offer) — to na jej podstawie odbiorca decyduje,
/// czy w ogóle chce ten plik odebrać.
class FileOffer {
  final String messageGuid;
  final DeviceIdentity from;
  final String fileName;
  final int fileSize;
  final String? sha256;
  final DateTime sentAt;

  const FileOffer({
    required this.messageGuid,
    required this.from,
    required this.fileName,
    required this.fileSize,
    required this.sentAt,
    this.sha256,
  });

  Map<String, Object?> toJson() => {
        'messageGuid': messageGuid,
        'from': from.toJson(),
        'fileName': fileName,
        'fileSize': fileSize,
        'sha256': sha256,
        'sentAt': sentAt.toUtc().toIso8601String(),
      };

  static FileOffer? fromJson(Map<String, Object?> json) {
    final guid = json['messageGuid'];
    final name = json['fileName'];
    final size = json['fileSize'];
    final from = DeviceIdentity.fromJson(json['from']);
    if (guid is! String ||
        guid.isEmpty ||
        name is! String ||
        name.isEmpty ||
        size is! int ||
        size < 0 ||
        from == null) {
      return null;
    }
    final sha = json['sha256'];
    final sentAt =
        DateTime.tryParse(json['sentAt'] is String ? json['sentAt'] as String : '');
    return FileOffer(
      messageGuid: guid,
      from: from,
      fileName: name,
      fileSize: size,
      sha256: (sha is String && sha.isNotEmpty) ? sha : null,
      sentAt: sentAt ?? DateTime.now(),
    );
  }
}

/// Odpowiedź odbiorcy na [FileOffer].
class FileOfferReply {
  final bool accepted;

  /// Odbiorca ma już tę wiadomość — nadawca może od razu uznać ją za
  /// dostarczoną i nie przesyłać ani bajtu (dedupe po zgubionym ACK-u).
  final bool alreadyHave;

  /// Ile bajtów odbiorca ma już zapisanych z poprzedniego, przerwanego
  /// transferu tego samego pliku — nadawca wysyła treść od tego miejsca.
  final int resumeFrom;

  /// Powód odmowy (dla logów/UI), np. 'rejected', 'timeout'.
  final String? reason;

  const FileOfferReply({
    required this.accepted,
    this.alreadyHave = false,
    this.resumeFrom = 0,
    this.reason,
  });

  Map<String, Object?> toJson() => {
        'accepted': accepted,
        'alreadyHave': alreadyHave,
        'resumeFrom': resumeFrom,
        'reason': reason,
      };

  static FileOfferReply? fromJson(Map<String, Object?> json) {
    final accepted = json['accepted'];
    if (accepted is! bool) return null;
    final resumeFrom = json['resumeFrom'];
    final reason = json['reason'];
    return FileOfferReply(
      accepted: accepted,
      alreadyHave: json['alreadyHave'] == true,
      resumeFrom: (resumeFrom is int && resumeFrom > 0) ? resumeFrom : 0,
      reason: reason is String ? reason : null,
    );
  }
}

/// Wynik zapisu pliku po stronie odbiorcy — mapowany na kod HTTP w server.dart.
enum FileReceiveResult {
  /// Komplet zapisany i zweryfikowany (200).
  ok,

  /// Użytkownik odmówił odbioru (403) — nadawca nie ponawia automatycznie.
  rejected,

  /// Nadawca zaczął od innego bajtu, niż odbiorca ma zapisane (409) —
  /// część została skasowana, ponowienie pójdzie od zera.
  offsetMismatch,

  /// Transfer się urwał albo rozmiar się nie zgadza (409) — część zostaje
  /// na dysku, kolejna próba wznowi od tego miejsca.
  incomplete,

  /// Suma kontrolna złożonego pliku się nie zgadza (422) — część skasowana.
  checksumMismatch,
}
