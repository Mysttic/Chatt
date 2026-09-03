import 'dart:convert';
import 'dart:math';

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

/// Kształt identyfikatora wiadomości przyjmowany z sieci.
///
/// To nie jest kosmetyka. Identyfikator trafia do **nazw plików na dysku**
/// (część transferu i jej opis w `.incomplete/`), więc napis w rodzaju
/// `../../../cokolwiek` znaczyłby zapis albo skasowanie pliku poza katalogiem
/// aplikacji — na pulpicie wszędzie tam, gdzie sięga użytkownik. Nasz nadawca
/// wysyła UUID, więc przyjmujemy tylko litery, cyfry i myślnik.
final RegExp _messageGuidShape = RegExp(r'^[A-Za-z0-9-]{1,64}$');

bool isSafeMessageGuid(Object? value) =>
    value is String && _messageGuidShape.hasMatch(value);

/// Ile kolejnych portów TCP próbujemy, gdy preferowany jest zajęty
/// (np. druga instancja aplikacji na tym samym komputerze).
const int tcpPortAttempts = 10;

const String typeDiscover = 'chatt_discover';
const String typeHere = 'chatt_here';

/// Wersja protokołu — podbijamy przy niekompatybilnych zmianach.
/// 2: pliki wysyłane po akceptacji odbiorcy (POST /file-offer), ze wznawianiem
///    i sumą kontrolną.
/// 3: parowanie z uzgodnieniem klucza (POST /pair) i szyfrowanie ruchu między
///    sparowanymi urządzeniami.
/// 4: parowanie przez porównanie kodu na obu ekranach (zobowiązanie + kod
///    z uzgodnienia zamiast kodu jako soli) oraz podpisane odpowiedzi
///    discovery od sparowanych urządzeń.
/// 5: cały ruch szyfrowany, także z niesparowanymi. Tożsamością urządzenia
///    jest klucz (guid = skrót klucza publicznego), sesja powstaje przez
///    POST /handshake i ma klucze efemeryczne, więc nagrany ruch nie
///    odszyfruje się po późniejszej kradzieży tożsamości. Jawnego tekstu
///    w protokole już nie ma.
const int protocolVersion = 5;

/// [nonce] jest losowy na każdy skan. Sparowane urządzenie wplata go
/// w podpis odpowiedzi, więc podsłuchanej odpowiedzi nie da się odtworzyć
/// przy następnym skanie.
Map<String, Object?> discoverPacket(DeviceIdentity me, String nonce) => {
      'type': typeDiscover,
      'proto': protocolVersion,
      'nonce': nonce,
      ...me.toJson(),
    };

/// [tag] jest tylko dla sparowanych: skrót HMAC kluczem sesji, którym
/// odpowiadający dowodzi, że to naprawdę on. Dla nieznajomych zostaje null —
/// nie mamy z nimi żadnego wspólnego sekretu.
Map<String, Object?> herePacket(DeviceIdentity me, {String? tag}) => {
      'type': typeHere,
      'proto': protocolVersion,
      'tag': ?tag,
      ...me.toJson(),
    };

/// Nonce skanu: 16 losowych bajtów w base64.
String newDiscoveryNonce() {
  final rng = Random.secure();
  return base64.encode(List<int>.generate(16, (_) => rng.nextInt(256)));
}

/// Znacznik koperty z zaszyfrowaną treścią (szczegóły w core/crypto.dart).
/// Jawny zostaje tylko identyfikator sesji — po nim odbiorca znajduje klucz.
/// Od protokołu 5 nie ma tu guid-a nadawcy, więc podsłuchujący nie widzi
/// nawet tego, kto z kim rozmawia: numer sesji zmienia się z każdym uściskiem.
const String envelopeMarker = 'enc';

/// Pole z identyfikatorem sesji w kopercie.
const String envelopeSession = 'sid';

bool isEncryptedEnvelope(Map<String, Object?> json) =>
    json[envelopeMarker] == 1;

String? sessionOfEnvelope(Map<String, Object?> json) {
  final sid = json[envelopeSession];
  return sid is String && sid.isNotEmpty ? sid : null;
}

// --- Uścisk dłoni: POST /handshake ---------------------------------------
// Jedna runda, bo obie strony znają już nawzajem klucz statyczny (z discovery
// albo z GET /info). Każda dorzuca klucz efemeryczny i z czterech uzgodnień
// X25519 wychodzi klucz ważny tylko na tę sesję (ChattCrypto.sessionKey).
//
//   A -> B   { from: <tożsamość A>, e: <klucz efemeryczny A> }
//   A <- B   { sessionId: ..., e: <klucz efemeryczny B>, from: <tożsamość B> }
//
// Sesja żyje wyłącznie w pamięci obu stron. Restart albo bezczynność ją kasuje
// i przy kolejnej wysyłce powstaje nowa — to jest cała mechanika forward
// secrecy: nie ma czego wykraść z dysku po fakcie.

/// Jak długo żyje sesja bez ruchu.
const Duration sessionLifetime = Duration(hours: 1);

/// Odbiorca nie zna podanego numeru sesji (wygasła albo był restart).
/// Nadawca ma zrobić uścisk dłoni jeszcze raz i ponowić zapytanie.
const String errorNoSession = 'no_session';

/// Wynik próby dostarczenia. [noSession] jest osobno od [failed], bo to nie
/// jest błąd do pokazania użytkownikowi — to prośba o powtórzenie uścisku
/// dłoni i jeszcze jedną próbę.
enum Delivery {
  ok,
  failed,
  noSession;

  bool get delivered => this == Delivery.ok;
}

Map<String, Object?> handshakeRequest({
  required DeviceIdentity from,
  required List<int> ephemeral,
}) =>
    {
      'from': from.toJson(),
      'e': base64.encode(ephemeral),
    };

Map<String, Object?> handshakeReply({
  required String sessionId,
  required DeviceIdentity from,
  required List<int> ephemeral,
}) =>
    {
      'ok': true,
      'sessionId': sessionId,
      'from': from.toJson(),
      'e': base64.encode(ephemeral),
    };

/// Odpowiedź na uścisk dłoni, po stronie inicjatora.
class HandshakeResult {
  final String sessionId;
  final DeviceIdentity peer;
  final List<int> ephemeral;

  const HandshakeResult({
    required this.sessionId,
    required this.peer,
    required this.ephemeral,
  });

  static HandshakeResult? fromJson(Map<String, Object?>? json) {
    if (json == null || json['ok'] != true) return null;
    final sid = json['sessionId'];
    final peer = DeviceIdentity.fromJson(json['from']);
    final e = DeviceIdentity.decodeKey(json['e']);
    if (sid is! String || sid.isEmpty || peer == null || e.isEmpty) return null;
    return HandshakeResult(sessionId: sid, peer: peer, ephemeral: e);
  }
}

/// Nowy numer sesji: 16 losowych bajtów.
String newSessionId() {
  final rng = Random.secure();
  return base64.encode(List<int>.generate(16, (_) => rng.nextInt(256)));
}

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
    if (!isSafeMessageGuid(guid) || text is! String || from == null) {
      return null;
    }
    final sentAt = DateTime.tryParse(json['sentAt'] is String ? json['sentAt'] as String : '');
    return IncomingMessage(
      messageGuid: guid as String,
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

/// "1" = treść jest zaszyfrowana kluczem pliku (AES-CTR). Nazwa pliku i suma
/// kontrolna są wtedy w zaszyfrowanej zapowiedzi, nie w nagłówkach.
const String headerEncrypted = 'x-chatt-encrypted';

/// Numer sesji nadawcy. Treść pliku to surowe bajty, a nie koperta, więc
/// odbiorca musi mieć gdzieś napisane, czyj to strumień.
const String headerSession = 'x-chatt-session';

/// Nazwa zastępcza w nagłówku zaszyfrowanego transferu — prawdziwa jest
/// w zapowiedzi, żeby nie wyciekała jawnym tekstem.
const String encryptedFilePlaceholder = 'zaszyfrowany-plik';

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

  /// Treść jest zaszyfrowana kluczem sesji (wtedy nazwa i suma pochodzą
  /// z wcześniejszej, zaszyfrowanej zapowiedzi).
  final bool encrypted;

  const IncomingFileMeta({
    required this.messageGuid,
    required this.from,
    required this.fileName,
    required this.fileSize,
    required this.sentAt,
    this.sha256,
    this.offset = 0,
    this.encrypted = false,
  });

  static IncomingFileMeta? fromHeaders(Map<String, String> headers) {
    final guid = headers[headerMessageGuid];
    final from = decodeIdentityHeader(headers[headerFrom]);
    final rawName = headers[headerFileName];
    final size = int.tryParse(headers[headerFileSize] ?? '');
    if (!isSafeMessageGuid(guid) ||
        from == null ||
        rawName == null ||
        size == null ||
        size < 0) {
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
      messageGuid: guid!,
      from: from,
      fileName: name,
      fileSize: size,
      sentAt: sentAt ?? DateTime.now(),
      sha256: (sha == null || sha.isEmpty) ? null : sha,
      offset: offset,
      encrypted: headers[headerEncrypted] == '1',
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

  /// Skrót klucza, którym poleci treść pliku. Klucz wisi na kluczu sesji,
  /// a ta wygasa — odbiorca porównuje ten znacznik z zapisanym obok części
  /// transferu i przy niezgodności każe zacząć od zera, zamiast cicho
  /// odszyfrować śmieci nowym kluczem na starych bajtach.
  final String? keyEpoch;

  const FileOffer({
    required this.messageGuid,
    required this.from,
    required this.fileName,
    required this.fileSize,
    required this.sentAt,
    this.sha256,
    this.keyEpoch,
  });

  Map<String, Object?> toJson() => {
        'messageGuid': messageGuid,
        'from': from.toJson(),
        'fileName': fileName,
        'fileSize': fileSize,
        'sha256': sha256,
        'keyEpoch': keyEpoch,
        'sentAt': sentAt.toUtc().toIso8601String(),
      };

  static FileOffer? fromJson(Map<String, Object?> json) {
    final guid = json['messageGuid'];
    final name = json['fileName'];
    final size = json['fileSize'];
    final from = DeviceIdentity.fromJson(json['from']);
    if (!isSafeMessageGuid(guid) ||
        name is! String ||
        name.isEmpty ||
        size is! int ||
        size < 0 ||
        from == null) {
      return null;
    }
    final sha = json['sha256'];
    final epoch = json['keyEpoch'];
    final sentAt =
        DateTime.tryParse(json['sentAt'] is String ? json['sentAt'] as String : '');
    return FileOffer(
      messageGuid: guid as String,
      from: from,
      fileName: name,
      fileSize: size,
      sha256: (sha is String && sha.isNotEmpty) ? sha : null,
      keyEpoch: (epoch is String && epoch.isNotEmpty) ? epoch : null,
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

// --- Parowanie: POST /pair -----------------------------------------------
// Trzy kroki, po nich porównanie kodu na obu ekranach:
//
//   1. [pairCommit]  A → B: skrót swojego klucza publicznego (zobowiązanie).
//                    B losuje własną parę kluczy i odsyła klucz publiczny.
//   2. [pairReveal]  A → B: właściwy klucz publiczny. B sprawdza, czy zgadza
//                    się ze skrótem z kroku 1.
//   3. Obie strony liczą z uzgodnienia X25519 klucz sesji i sześciocyfrowy
//      kod, po czym **pokazują ten kod u siebie**. Użytkownicy porównują je
//      wzrokowo i potwierdzają; potwierdzenie leci do drugiej strony jako
//      [pairConfirm]. Klucz zapisujemy dopiero, gdy potwierdzą oba końce.
//
// Po co zobowiązanie: bez niego ktoś w środku mógłby dobierać swoje klucze
// tak długo, aż kody po obu stronach wyjdą takie same. Skrót wysłany przed
// poznaniem klucza drugiej strony to uniemożliwia — napastnikowi zostaje
// jedno losowe trafienie na milion, w dodatku widoczne od razu, bo kody się
// nie zgodzą. Kod nie jest sekretem i nie idzie przez sieć, więc nie ma tu
// czego łamać offline (poprzedni schemat, z kodem jako solą HKDF, na to
// pozwalał).

/// „Zeskanowałem twój kod QR". Nie daje sama z siebie zielonej tarczy —
/// drugie urządzenie pyta jeszcze swojego użytkownika, bo kod z ekranu mógł
/// zobaczyć ktoś jeszcze. Człowiek potwierdza to, czego maszyna nie wie:
/// że skanowanie właśnie się odbyło i to on je zrobił.
const String pairScanned = 'scanned';

const String pairCommit = 'commit';
const String pairReveal = 'reveal';
const String pairConfirm = 'confirm';
const String pairCancel = 'cancel';

/// Ile cyfr ma kod do porównania. Sześć to kompromis: milion możliwości przy
/// jednym strzale napastnika, a jeszcze da się to porównać wzrokiem.
const int pairingCodeDigits = 6;

/// Jak długo żyje zaczęte parowanie. Trzeba zdążyć dojść do drugiego
/// urządzenia i porównać kod.
const Duration pairingCodeLifetime = Duration(minutes: 10);

/// Jak skończyło się parowanie. Rozróżnienie jest po to, żeby aplikacja nie
/// mówiła "kody się nie zgadzają", gdy naprawdę minął czas.
enum PairOutcome {
  accepted,

  /// Druga strona odrzuciła: użytkownik powiedział, że kody się różnią, albo
  /// klucz nie pasuje do przysłanego wcześniej skrótu.
  rejected,
  expired,

  /// Druga strona nie odpowiedziała (albo nie zna parowania).
  unreachable;

  static PairOutcome fromName(String? name) => switch (name) {
        'accepted' => PairOutcome.accepted,
        'expired' => PairOutcome.expired,
        'rejected' => PairOutcome.rejected,
        _ => PairOutcome.unreachable,
      };
}

/// Odpowiedź na `POST /pair`. Poza wynikiem niesie klucz publiczny, którym
/// odpowiadający włącza się do uzgodnienia (tylko przy [pairCommit]).
class PairReply {
  final PairOutcome outcome;
  final String? publicKey;

  const PairReply(this.outcome, {this.publicKey});

  bool get accepted => outcome == PairOutcome.accepted;

  Map<String, Object?> toJson() => {
        'ok': accepted,
        'error': accepted ? null : outcome.name,
        'publicKey': publicKey,
      };

  static PairReply fromJson(Map<String, Object?>? json) {
    if (json == null) return const PairReply(PairOutcome.unreachable);
    final key = json['publicKey'];
    return PairReply(
      json['ok'] == true
          ? PairOutcome.accepted
          : PairOutcome.fromName(json['error'] is String ? json['error'] as String : null),
      publicKey: key is String && key.isNotEmpty ? key : null,
    );
  }
}

class PairMessage {
  final String action;
  final DeviceIdentity from;

  /// Skrót klucza publicznego (base64) — przy [pairCommit].
  final String? commit;

  /// Klucz publiczny X25519 (base64) — przy [pairReveal].
  final String? publicKey;

  const PairMessage({
    required this.action,
    required this.from,
    this.commit,
    this.publicKey,
  });

  Map<String, Object?> toJson() => {
        'action': action,
        'from': from.toJson(),
        'commit': commit,
        'publicKey': publicKey,
      };

  static const _actions = {
    pairCommit,
    pairReveal,
    pairConfirm,
    pairCancel,
    pairScanned,
  };

  static PairMessage? fromJson(Map<String, Object?> json) {
    final action = json['action'];
    final from = DeviceIdentity.fromJson(json['from']);
    if (from == null || action is! String || !_actions.contains(action)) {
      return null;
    }
    final commit = json['commit'];
    final publicKey = json['publicKey'];
    return PairMessage(
      action: action,
      from: from,
      commit: commit is String && commit.isNotEmpty ? commit : null,
      publicKey: publicKey is String && publicKey.isNotEmpty ? publicKey : null,
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
