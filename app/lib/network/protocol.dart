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
/// aplikacji, na pulpicie wszędzie tam, gdzie sięga użytkownik. Nasz nadawca
/// wysyła UUID, więc przyjmujemy tylko litery, cyfry i myślnik.
final RegExp _messageGuidShape = RegExp(r'^[A-Za-z0-9-]{1,64}$');

bool isSafeMessageGuid(Object? value) =>
    value is String && _messageGuidShape.hasMatch(value);

/// Ile kolejnych portów TCP próbujemy, gdy preferowany jest zajęty
/// (np. druga instancja aplikacji na tym samym komputerze).
const int tcpPortAttempts = 10;

const String typeDiscover = 'chatt_discover';
const String typeHere = 'chatt_here';

/// Wersja protokołu, podbijamy ją przy niekompatybilnych zmianach.
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
/// odpowiadający dowodzi, że to naprawdę on. Dla nieznajomych zostaje null:
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
/// Jawny zostaje tylko identyfikator sesji: po nim odbiorca znajduje klucz.
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
// i przy kolejnej wysyłce powstaje nowa. To jest cała mechanika forward
// secrecy: nie ma czego wykraść z dysku po fakcie.

/// Jak długo żyje sesja bez ruchu.
const Duration sessionLifetime = Duration(hours: 1);

/// Odbiorca nie zna podanego numeru sesji (wygasła albo był restart).
/// Nadawca ma zrobić uścisk dłoni jeszcze raz i ponowić zapytanie.
const String errorNoSession = 'no_session';

/// Wynik próby dostarczenia. [noSession] jest osobno od [failed], bo to nie
/// jest błąd do pokazania użytkownikowi: to prośba o powtórzenie uścisku
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
//   1. POST /file-offer: JSON z metadanymi (nazwa, rozmiar, sha256).
//      Odbiorca pyta użytkownika i odpowiada [FileOfferReply]: zgoda albo
//      odmowa, "już to mam" (dedupe bez przesyłania bajtów) oraz offset,
//      od którego można wznowić wcześniej przerwany transfer.
//   2. POST /file: surowe bajty od tego offsetu (streaming w obie strony,
//      żeby duże pliki nie przechodziły przez pamięć). Metadane jadą
//      w nagłówkach, muszą być ASCII, stąd base64/percent-encoding.

const String headerMessageGuid = 'x-chatt-message-guid';
const String headerFrom = 'x-chatt-from';
const String headerFileName = 'x-chatt-file-name';
const String headerFileSize = 'x-chatt-file-size';
const String headerSentAt = 'x-chatt-sent-at';

/// sha256 całego pliku (hex). Odbiorca weryfikuje po złożeniu wszystkich
/// części, chroni przed cichym uszkodzeniem przy wznawianiu transferu.
const String headerFileSha256 = 'x-chatt-file-sha256';

/// Od którego bajtu nadawca wysyła treść (0 = całość, >0 = wznowienie).
const String headerFileOffset = 'x-chatt-file-offset';

/// "1" = treść jest zaszyfrowana kluczem pliku (AES-CTR). Nazwa pliku i suma
/// kontrolna są wtedy w zaszyfrowanej zapowiedzi, nie w nagłówkach.
const String headerEncrypted = 'x-chatt-encrypted';

/// Numer sesji nadawcy. Treść pliku to surowe bajty, a nie koperta, więc
/// odbiorca musi mieć gdzieś napisane, czyj to strumień.
const String headerSession = 'x-chatt-session';

/// Nazwa zastępcza w nagłówku zaszyfrowanego transferu, prawdziwa jest
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

  /// Suma kontrolna całego pliku (hex), null u nadawcy w protokole 1.
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

/// Ile plików najwyżej wchodzi do jednej paczki.
///
/// Granica jest po to, żeby spis nazw zmieścił się w zapowiedzi (serwer tnie
/// ciało zapytania na 1 MB) i żeby jedna zgoda nie obejmowała nie wiadomo
/// czego. Wybór stu jeden plików wyjdzie dwiema paczkami i dwoma pytaniami.
const int maxBatchFiles = 100;

/// Powód odmowy, po którym nadawca wie, że odbiorca odrzucił **całą paczkę**,
/// a nie ten jeden plik, więc nie ma po co zapowiadać reszty.
const String offerRejectedBatch = 'batch-rejected';

/// Powód odmowy, gdy nikt nie odpowiedział na kartę. Z zewnątrz wygląda jak
/// odmowa (plik nie wchodzi), ale nadawca musi je rozróżniać: po ciszy opis
/// paczki nadal do nikogo nie dotarł, więc następna zapowiedź ma go powtórzyć.
const String offerNoAnswer = 'no-answer';

/// Czym jest paczka: ile plików, ile bajtów i jak się nazywają.
///
/// Jedzie tylko w **pierwszej** zapowiedzi paczki, bo tylko ona otwiera
/// pytanie do użytkownika; kolejne niosą sam [FileOffer.batchId]. Spis nazw
/// jest po to, żeby karta z pytaniem mówiła, na co właściwie idzie zgoda:
/// bez niego użytkownik widziałby nazwę pierwszego pliku i liczbę reszty.
class FileBatch {
  final int count;
  final int bytes;

  /// Nazwy plików, dokładnie [count] pozycji, w kolejności wysyłania. To
  /// napisy od nadawcy, więc nadają się do pokazania i do porównania, ale nie
  /// do zbudowania ścieżki.
  final List<String> names;

  const FileBatch({
    required this.count,
    required this.bytes,
    required this.names,
  });

  Map<String, Object?> toJson() =>
      {'count': count, 'bytes': bytes, 'names': names};

  /// `null`, gdy cokolwiek się nie zgadza. Odbiorca traktuje to jak brak
  /// paczki, czyli pyta o każdy plik osobno: gorzej, ale nigdy szkodliwie.
  static FileBatch? fromJson(Object? value) {
    if (value is! Map) return null;
    final count = value['count'];
    final bytes = value['bytes'];
    final names = value['names'];
    if (count is! int ||
        count < 2 ||
        count > maxBatchFiles ||
        bytes is! int ||
        bytes < 0 ||
        names is! List ||
        names.length != count) {
      return null;
    }
    final czyste = <String>[];
    for (final name in names) {
      // Nazwa idzie na kartę z pytaniem, a stamtąd nigdzie dalej. Długość
      // ograniczamy, żeby jeden napis nie rozepchnął zapowiedzi.
      if (name is! String || name.isEmpty || name.length > 255) return null;
      czyste.add(name);
    }
    return FileBatch(count: count, bytes: bytes, names: czyste);
  }
}

/// Zapowiedź pliku (POST /file-offer): to na jej podstawie odbiorca decyduje,
/// czy w ogóle chce ten plik odebrać.
class FileOffer {
  final String messageGuid;
  final DeviceIdentity from;
  final String fileName;
  final int fileSize;
  final String? sha256;
  final DateTime sentAt;

  /// Skrót klucza, którym poleci treść pliku. Klucz wisi na kluczu sesji,
  /// a ta wygasa, odbiorca porównuje ten znacznik z zapisanym obok części
  /// transferu i przy niezgodności każe zacząć od zera, zamiast cicho
  /// odszyfrować śmieci nowym kluczem na starych bajtach.
  final String? keyEpoch;

  /// Do której paczki należy ten plik; `null` znaczy „sam sobie". Odbiorca
  /// pyta raz na paczkę, a nie raz na plik.
  final String? batchId;

  /// Czym jest ta paczka. Niesie ją wyłącznie pierwsza zapowiedź, bo tylko
  /// ona otwiera pytanie; w kolejnych jest `null`.
  final FileBatch? batch;

  const FileOffer({
    required this.messageGuid,
    required this.from,
    required this.fileName,
    required this.fileSize,
    required this.sentAt,
    this.sha256,
    this.keyEpoch,
    this.batchId,
    this.batch,
  });

  Map<String, Object?> toJson() => {
        'messageGuid': messageGuid,
        'from': from.toJson(),
        'fileName': fileName,
        'fileSize': fileSize,
        'sha256': sha256,
        'keyEpoch': keyEpoch,
        'sentAt': sentAt.toUtc().toIso8601String(),
        if (batchId != null) 'batchId': batchId,
        if (batch != null) 'batch': batch!.toJson(),
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
    // Identyfikator paczki trzymamy w tym samym kształcie co identyfikator
    // wiadomości. Na dysku się nie pojawia, ale jest kluczem zapamiętanej
    // zgody, a to za dużo, żeby przyjmować pod nim dowolny napis z sieci.
    final surowyBatchId = json['batchId'];
    var batchId =
        isSafeMessageGuid(surowyBatchId) ? surowyBatchId as String : null;
    // Zepsuty opis paczki znaczy „nie ma paczki", więc odbiorca zapyta o ten
    // plik osobno. Odmowa byłaby gorsza: gubiłaby plik przez błąd nadawcy.
    var batch = batchId == null ? null : FileBatch.fromJson(json['batch']);
    // Opis, który nie opisuje **tej** zapowiedzi, nie jest jej opisem. Bez
    // tego nadawca dołączałby spis trzech niewinnych nazw na dwa kilobajty do
    // zapowiedzi zupełnie innego pliku: karta pokazałaby tamte nazwy i tamten
    // rozmiar, a zgoda poszłaby na plik, którego nikt nie widział.
    if (batch != null &&
        (!batch.names.contains(name) || size > batch.bytes)) {
      batchId = null;
      batch = null;
    }
    return FileOffer(
      messageGuid: guid as String,
      from: from,
      fileName: name,
      fileSize: size,
      sha256: (sha is String && sha.isNotEmpty) ? sha : null,
      keyEpoch: (epoch is String && epoch.isNotEmpty) ? epoch : null,
      sentAt: sentAt ?? DateTime.now(),
      batchId: batchId,
      batch: batch,
    );
  }
}

/// Odpowiedź odbiorcy na [FileOffer].
class FileOfferReply {
  final bool accepted;

  /// Odbiorca ma już tę wiadomość, nadawca może od razu uznać ją za
  /// dostarczoną i nie przesyłać ani bajtu (dedupe po zgubionym ACK-u).
  final bool alreadyHave;

  /// Ile bajtów odbiorca ma już zapisanych z poprzedniego, przerwanego
  /// transferu tego samego pliku, nadawca wysyła treść od tego miejsca.
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
// poznaniem klucza drugiej strony to uniemożliwia, napastnikowi zostaje
// jedno losowe trafienie na milion, w dodatku widoczne od razu, bo kody się
// nie zgodzą. Kod nie jest sekretem i nie idzie przez sieć, więc nie ma tu
// czego łamać offline (poprzedni schemat, z kodem jako solą HKDF, na to
// pozwalał).

/// „Zeskanowałem twój kod QR". Nie daje sama z siebie zielonej tarczy:
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

  /// Skrót klucza publicznego (base64), przy [pairCommit].
  final String? commit;

  /// Klucz publiczny X25519 (base64), przy [pairReveal].
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

// --- Zdalna klawiatura: POST /input-session, POST /input -------------------
// Dodatek „Klawiatura z PC": nadawca pisze, a tekst ląduje w polu, które ma
// fokus na urządzeniu odbiorcy. Dwa kroki:
//
//   1. POST /input-session: prośba o sesję. Odbiorca sprawdza bramki
//      (dodatek, przełącznik odbioru, zweryfikowany nadawca), pyta
//      użytkownika i przy zgodzie odsyła losowy [InputSessionReply.token].
//   2. POST /input: paczki operacji z tym tokenem i rosnącym `seq`. Jedna
//      paczka w locie, a to, co nadawca uzbierał w tym czasie, jedzie
//      sklejone w następnej.
//
// Obie odpowiedzi są **zapieczętowane** kluczem sesji, także odmowy: jawne
// zostają tylko 409 (brak sesji, nie ma czym pieczętować), 404 (starsza
// wersja), 400 (zły kształt), 413 i 500. Odpowiedź nie niesie `from`, więc
// odbita do serwera nadawcy nie przejdzie przez `_openEnvelope`, a pole
// `reply` odróżnia ją od zapytania zapieczętowanego tym samym kluczem.

/// Prośba o sesję i wycofanie prośby, na którą odbiorca jeszcze nie odpowiedział.
const String inputSessionRequest = 'request';
const String inputSessionCancel = 'cancel';

/// Powody odmowy w odpowiedzi na [InputSessionRequest].
///
/// [inputRejected] dostaje każdy niezweryfikowany nadawca, cokolwiek leży
/// w ustawieniach, więc z zewnątrz nie da się poznać, czy dodatek jest
/// włączony. [inputNotEnabled] słyszy tylko zweryfikowany.
const String inputRejected = 'rejected';
const String inputNotEnabled = 'not_enabled';
const String inputNoAnswer = 'no-answer';
const String inputBusy = 'busy';
const String inputCancelled = 'cancelled';

/// Powody odmowy w odpowiedzi na [RemoteInputPacket]. [inputNoGrant] kończy
/// sesję nadawcy: tokenu nie ma, wygasł albo odbiorca nacisnął Stop.
const String inputNoGrant = 'no_grant';
const String inputStaleSeq = 'stale_seq';

/// Paczka przyszła, ale nic z niej nie wpisano, bo u odbiorcy wisi karta
/// z pytaniem: zdalny Enter nie ma prawa odpowiadać na cudze karty.
const String inputPaused = 'paused';

/// Wartości pola `reply` w zapieczętowanych odpowiedziach.
const String replyInputSession = 'input-session';
const String replyInput = 'input';

/// Ile jednostek UTF-16 tekstu najwyżej w jednej paczce, łącznie we
/// wszystkich operacjach `insert`. Dłuższe wklejenie jedzie kilkoma.
const int maxInputTextUnits = 4096;

/// Ile znaków najwyżej kasuje jedna operacja `bs` albo `del`.
const int maxInputDeleteRun = 64;

/// Ile znaków najwyżej kasuje jedna paczka, łącznie.
const int maxInputDeletes = 4096;

/// Ile operacji najwyżej w jednej paczce.
const int maxInputOps = 256;

/// Górna granica ciała `/input` i `/input-session` na drucie. Paczka
/// z kompletem tekstu to kilkanaście kilobajtów po zaszyfrowaniu i base64;
/// bez tej granicy serwer czytałby i odszyfrowywał megabajt, zanim odrzuci
/// kształt.
const int maxInputBodyBytes = 32 * 1024;

/// Ładunek jest dopełniany do wielokrotności tylu bajtów (pole `pad`).
/// GCM nie zmienia długości, więc bez tego długość koperty zdradzałaby
/// liczbę wpisanych znaków i nazwę aplikacji w odpowiedzi.
const int inputPadBlock = 64;

/// I nigdy poniżej tylu bajtów. Paczka z jednym znakiem, z jednym `bs` i sam
/// ping mają wtedy tę samą długość, a każda odpowiedź mieści się w tym
/// rozmiarze bez względu na rodzaj pola i nazwę aplikacji (patrz
/// [RemoteInputTarget.fromJson]).
const int inputPadMinimum = 512;

/// Jak długo nadawca czeka na odpowiedź na prośbę. Karta u odbiorcy wisi
/// [remoteInputAnswerTimeout], reszta to zapas na drogę.
const Duration remoteInputRequestTimeout = Duration(seconds: 150);

/// Jak długo karta zgody czeka na decyzję.
const Duration remoteInputAnswerTimeout = Duration(minutes: 2);

/// Limit czasu jednej paczki. Po nim ta sama paczka idzie jeszcze raz,
/// z tym samym `seq`.
const Duration remoteInputPacketTimeout = Duration(seconds: 2);

/// Ile najwyżej trwa wpisanie jednego znaku (albo jednego Backspace) po
/// stronie odbiorcy. Windows wpisuje znak po znaku z milisekundą przerwy, bo
/// część aplikacji gubi znaki wysłane serią; zapas jest na wolniejszy zegar.
const Duration remoteInputTypingPerUnit = Duration(milliseconds: 20);

/// Czas wpisania paczki u odbiorcy, ponad zwykły limit odpowiedzi. Nadawca
/// dolicza go do limitu czasu paczki, a odbiorca do limitu wywołania kanału.
Duration remoteInputTypingTime(List<RemoteInputOp> ops) {
  var jednostki = 0;
  for (final op in ops) {
    if (op.kind.types) jednostki += op.text.length + op.count + 1;
  }
  return remoteInputTypingPerUnit * jednostki;
}

/// Zgoda gaśnie po tylu minutach bez operacji. Pingi się nie liczą.
const Duration remoteInputIdle = Duration(minutes: 30);

/// I po tylu godzinach od wydania, cokolwiek się dzieje.
const Duration remoteInputMaxLife = Duration(hours: 8);

/// Kształt identyfikatora sesji pisania i tokenu.
final RegExp _inputTokenShape = RegExp(r'^[A-Za-z0-9+/=]{1,64}$');

/// Platformy, które nadawca może podać w prośbie. Inna wartość znaczy
/// „nie podano", bez odrzucania prośby.
const Set<String> _inputPlatforms = {
  'windows',
  'android',
  'linux',
  'macos',
  'ios',
};

/// Czy tekst nadaje się do wpisania: bez znaków sterujących poza nową linią
/// i bez samotnych połówek surogatów. Tab też odpada, bo na Windows to
/// przejście do następnej kontrolki, a nawigacja jest poza zakresem dodatku.
bool isTypableText(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 0x0A) continue;
    if (unit < 0x20 || (unit >= 0x7F && unit <= 0x9F)) return false;
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      // Wysoka połówka musi mieć zaraz za sobą niską.
      if (i + 1 >= text.length) return false;
      final next = text.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return false;
      i++;
      continue;
    }
    if (unit >= 0xDC00 && unit <= 0xDFFF) return false;
  }
  return true;
}

/// Tekst od użytkownika nadawcy w postaci, którą odbiorca przyjmie: końce
/// linii jako `\n`, tabulator jako spacja, bez innych znaków sterujących
/// i bez samotnych połówek surogatów.
String typableText(String raw) {
  final out = StringBuffer();
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 0x0A) {
      out.writeCharCode(unit);
    } else if (unit == 0x09) {
      out.write(' ');
    } else if (unit < 0x20 || (unit >= 0x7F && unit <= 0x9F)) {
      continue;
    } else if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 < text.length) {
        final next = text.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          out.writeCharCode(unit);
          out.writeCharCode(next);
          i++;
        }
      }
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      continue;
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString();
}

/// Dopełnia ładunek polem `pad` do co najmniej [inputPadMinimum] bajtów,
/// a powyżej do wielokrotności [inputPadBlock], po zakodowaniu w JSON.
Map<String, Object?> padInputPayload(Map<String, Object?> payload) {
  final bez = {...payload, 'pad': ''};
  final dlugosc = utf8.encode(jsonEncode(bez)).length;
  final brak = dlugosc < inputPadMinimum
      ? inputPadMinimum - dlugosc
      : (inputPadBlock - dlugosc % inputPadBlock) % inputPadBlock;
  return {...payload, 'pad': ' ' * brak};
}

/// Rodzaj operacji zdalnej klawiatury, z nazwą na drucie.
enum RemoteInputOpKind {
  insert('insert'),
  backspace('bs'),
  delete('del'),
  action('action'),
  ping('ping'),
  stop('stop');

  final String wire;
  const RemoteInputOpKind(this.wire);

  static RemoteInputOpKind? fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }

  /// Czy operacja coś wpisuje albo kasuje, czyli trafia do ujścia.
  bool get types =>
      this == insert || this == backspace || this == delete || this == action;
}

/// Jedna operacja: wpisanie tekstu, skasowanie znaków przed albo za kursorem,
/// akcja pola (Enter), ping albo koniec sesji. Innych nie ma: skróty, Tab,
/// strzałki i Esc są poza zakresem dodatku.
class RemoteInputOp {
  final RemoteInputOpKind kind;

  /// Tekst dla [RemoteInputOpKind.insert], pusty dla reszty.
  final String text;

  /// Liczba **punktów kodowych** dla `bs` i `del`, zero dla reszty: jedno
  /// `bs` kasuje emoji w całości.
  final int count;

  const RemoteInputOp._(this.kind, {this.text = '', this.count = 0});

  const RemoteInputOp.insert(String text)
      : this._(RemoteInputOpKind.insert, text: text);
  const RemoteInputOp.backspace([int count = 1])
      : this._(RemoteInputOpKind.backspace, count: count);
  const RemoteInputOp.delete([int count = 1])
      : this._(RemoteInputOpKind.delete, count: count);
  const RemoteInputOp.action() : this._(RemoteInputOpKind.action);
  const RemoteInputOp.ping() : this._(RemoteInputOpKind.ping);
  const RemoteInputOp.stop() : this._(RemoteInputOpKind.stop);

  Map<String, Object?> toJson() => {
        't': kind.wire,
        if (kind == RemoteInputOpKind.insert) 's': text,
        if (kind == RemoteInputOpKind.backspace ||
            kind == RemoteInputOpKind.delete)
          'n': count,
      };

  /// `null`, gdy operacja ma zły kształt. Odbiorca odrzuca wtedy całą
  /// paczkę: połowa paczki wpisana to gorzej niż żadna.
  static RemoteInputOp? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = RemoteInputOpKind.fromWire(json['t']);
    switch (kind) {
      case null:
        return null;
      case RemoteInputOpKind.insert:
        final s = json['s'];
        if (s is! String ||
            s.isEmpty ||
            s.length > maxInputTextUnits ||
            !isTypableText(s)) {
          return null;
        }
        return RemoteInputOp.insert(s);
      case RemoteInputOpKind.backspace:
      case RemoteInputOpKind.delete:
        final n = json['n'];
        if (n is! int || n < 1 || n > maxInputDeleteRun) return null;
        return kind == RemoteInputOpKind.backspace
            ? RemoteInputOp.backspace(n)
            : RemoteInputOp.delete(n);
      case RemoteInputOpKind.action:
        return const RemoteInputOp.action();
      case RemoteInputOpKind.ping:
        return const RemoteInputOp.ping();
      case RemoteInputOpKind.stop:
        return const RemoteInputOp.stop();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteInputOp &&
      other.kind == kind &&
      other.text == text &&
      other.count == count;

  @override
  int get hashCode => Object.hash(kind, text, count);

  /// Bez tekstu: ten napis trafia do logów i komunikatów testów.
  @override
  String toString() => switch (kind) {
        RemoteInputOpKind.insert => 'insert(${text.length})',
        RemoteInputOpKind.backspace => 'bs($count)',
        RemoteInputOpKind.delete => 'del($count)',
        _ => kind.wire,
      };
}

/// Ile bajtów (w JSON-ie) najwyżej mają nazwa pakietu i nazwa aplikacji
/// w celu. Najdłuższa odpowiedź bez nich ma niecałe 300 bajtów, więc dwie
/// takie nazwy mieszczą się w [inputPadMinimum].
const int _maxTargetLabelBytes = 96;

/// Rodzaj pola z fokusem u odbiorcy. Przy [password] nadawca zasłania echo.
enum RemoteInputField { text, password, none }

/// Akcja pola z fokusem na Androidzie (`imeOptions`). Windows zawsze mówi
/// [none] i tam akcja to zwykły Enter.
enum RemoteInputAction { search, send, go, done, next, previous, none }

/// Stan celu u odbiorcy: dokąd trafi to, co nadawca wpisze. Nadawca nie
/// dostaje nic poza tym, co potrzebne do pisania: rodzaj pola, akcja
/// i nazwa aplikacji.
class RemoteInputTarget {
  /// Czy jest pole, do którego da się teraz pisać.
  final bool active;
  final RemoteInputField field;
  final RemoteInputAction action;

  /// Pakiet (Android) albo nazwa pliku programu (Windows).
  final String app;

  /// Nazwa aplikacji do pokazania: etykieta aplikacji na Androidzie, nazwa
  /// programu na Windows (opis z zasobu wersji, inaczej nazwa pliku). Nigdy
  /// tytuł okna: ten niesie treść (nazwę dokumentu, temat wiadomości, tytuł
  /// strony), a odczyt treści u odbiorcy jest poza zakresem dodatku.
  final String appLabel;

  /// Fokus jest w samym Chatcie. Odbiorca wtedy nie wpisuje: zdalny Enter
  /// nie wyśle wiadomości i nie kliknie karty.
  final bool ownApp;

  /// Ekran zablokowany albo wygaszony.
  final bool locked;

  /// Okno z uprawnieniami administratora na Windows, do którego `SendInput`
  /// nie wpisze (i nie powie, że nie wpisał).
  final bool elevated;

  const RemoteInputTarget({
    this.active = false,
    this.field = RemoteInputField.none,
    this.action = RemoteInputAction.none,
    this.app = '',
    this.appLabel = '',
    this.ownApp = false,
    this.locked = false,
    this.elevated = false,
  });

  /// Nie ma dokąd pisać (platforma bez ujścia, brak odpowiedzi strony
  /// natywnej).
  static const RemoteInputTarget none = RemoteInputTarget();

  Map<String, Object?> toJson() => {
        'active': active,
        'field': field.name,
        'action': action.name,
        'app': app,
        'appLabel': appLabel,
        'ownApp': ownApp,
        'locked': locked,
        'elevated': elevated,
      };

  /// Wyrozumiale: cel przychodzi od zweryfikowanego odbiorcy albo od
  /// własnej strony natywnej. Nieznana wartość to „nie wiadomo", a napisy
  /// są przycinane do [_maxTargetLabelBytes] bajtów w JSON-ie, po całych
  /// znakach: idą na ekran, a odpowiedź z nimi ma się zmieścić
  /// w [inputPadMinimum] bajtach także przy nazwach pisanych cyrylicą czy
  /// znakami CJK.
  static RemoteInputTarget fromJson(Object? json) {
    if (json is! Map) return none;
    String napis(Object? value) {
      if (value is! String) return '';
      final przyciete = StringBuffer();
      var bajty = 0;
      for (final punkt in value.runes) {
        final znak = String.fromCharCode(punkt);
        // Długość w JSON-ie, bez cudzysłowów: znaki ucieczki też się liczą.
        final ile = utf8.encode(jsonEncode(znak)).length - 2;
        if (bajty + ile > _maxTargetLabelBytes) break;
        przyciete.write(znak);
        bajty += ile;
      }
      return przyciete.toString();
    }

    return RemoteInputTarget(
      active: json['active'] == true,
      field: RemoteInputField.values.firstWhere(
          (f) => f.name == json['field'],
          orElse: () => RemoteInputField.none),
      action: RemoteInputAction.values.firstWhere(
          (a) => a.name == json['action'],
          orElse: () => RemoteInputAction.none),
      app: napis(json['app']),
      appLabel: napis(json['appLabel']),
      ownApp: json['ownApp'] == true,
      locked: json['locked'] == true,
      elevated: json['elevated'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteInputTarget &&
      other.active == active &&
      other.field == field &&
      other.action == action &&
      other.app == app &&
      other.appLabel == appLabel &&
      other.ownApp == ownApp &&
      other.locked == locked &&
      other.elevated == elevated;

  @override
  int get hashCode => Object.hash(
      active, field, action, app, appLabel, ownApp, locked, elevated);
}

/// `POST /input-session`: prośba o sesję pisania albo jej wycofanie.
class InputSessionRequest {
  final DeviceIdentity from;

  /// [inputSessionRequest] albo [inputSessionCancel].
  final String op;

  /// Identyfikator tej sesji, losowany przez nadawcę. Jednorazowy: odbiorca
  /// pamięta zużyte i powtórzonej prośby nie pokaże drugi raz.
  final String input;

  /// System nadawcy, do pokazania na karcie. `null` = nie podano.
  final String? platform;

  const InputSessionRequest({
    required this.from,
    required this.op,
    required this.input,
    this.platform,
  });

  Map<String, Object?> toJson() => {
        'from': from.toJson(),
        'op': op,
        'input': input,
        if (platform != null) 'platform': platform,
      };

  static InputSessionRequest? fromJson(Map<String, Object?> json) {
    final from = DeviceIdentity.fromJson(json['from']);
    final op = json['op'];
    final input = json['input'];
    if (from == null ||
        (op != inputSessionRequest && op != inputSessionCancel) ||
        !isSafeMessageGuid(input)) {
      return null;
    }
    final platform = json['platform'];
    return InputSessionRequest(
      from: from,
      op: op as String,
      input: input as String,
      platform: _inputPlatforms.contains(platform) ? platform as String : null,
    );
  }
}

/// Odpowiedź na [InputSessionRequest], zawsze zapieczętowana.
class InputSessionReply {
  final bool accepted;
  final String input;

  /// Losowany przez odbiorcę przy zgodzie. Każda paczka musi go nieść.
  final String? token;

  /// Powód odmowy ([inputRejected], [inputNotEnabled], ...).
  final String? reason;
  final RemoteInputTarget target;

  const InputSessionReply({
    required this.accepted,
    required this.input,
    this.token,
    this.reason,
    this.target = RemoteInputTarget.none,
  });

  Map<String, Object?> toJson() => {
        'reply': replyInputSession,
        'ok': accepted,
        'accepted': accepted,
        'input': input,
        if (token != null) 'token': token,
        if (reason != null) 'reason': reason,
        if (accepted) 'target': target.toJson(),
      };

  /// `null`, gdy to nie jest odpowiedź na prośbę [input]: inny kształt,
  /// inna sesja pisania albo zgoda bez tokenu.
  static InputSessionReply? fromJson(Map<String, Object?>? json,
      {required String input}) {
    if (json == null ||
        json['reply'] != replyInputSession ||
        json['input'] != input ||
        json.containsKey('from')) {
      return null;
    }
    final accepted = json['accepted'];
    if (accepted is! bool) return null;
    final token = json['token'];
    if (accepted &&
        (token is! String || !_inputTokenShape.hasMatch(token))) {
      return null;
    }
    final reason = json['reason'];
    return InputSessionReply(
      accepted: accepted,
      input: input,
      token: accepted ? token as String : null,
      reason: reason is String ? reason : null,
      target: RemoteInputTarget.fromJson(json['target']),
    );
  }
}

/// `POST /input`: paczka operacji w ramach przyznanej sesji.
class RemoteInputPacket {
  final DeviceIdentity from;
  final String input;
  final String token;

  /// Numer paczki, od 1, rosnący w ramach sesji. Powtórzona paczka (po
  /// limicie czasu) ma ten sam numer i odbiorca nie wpisuje jej drugi raz.
  final int seq;
  final List<RemoteInputOp> ops;

  const RemoteInputPacket({
    required this.from,
    required this.input,
    required this.token,
    required this.seq,
    required this.ops,
  });

  Map<String, Object?> toJson() => {
        'from': from.toJson(),
        'input': input,
        'token': token,
        'seq': seq,
        'ops': [for (final op in ops) op.toJson()],
      };

  /// `null` przy złym kształcie czegokolwiek: typy, zakresy, nieznana
  /// operacja, tekst ze znakami sterującymi, przekroczone limity paczki,
  /// `stop` gdzie indziej niż na końcu.
  static RemoteInputPacket? fromJson(Map<String, Object?> json) {
    final from = DeviceIdentity.fromJson(json['from']);
    final input = json['input'];
    final token = json['token'];
    final seq = json['seq'];
    final rawOps = json['ops'];
    final pad = json['pad'];
    if (from == null ||
        !isSafeMessageGuid(input) ||
        token is! String ||
        !_inputTokenShape.hasMatch(token) ||
        seq is! int ||
        seq < 1 ||
        rawOps is! List ||
        rawOps.isEmpty ||
        rawOps.length > maxInputOps ||
        (json.containsKey('pad') && pad is! String)) {
      return null;
    }
    final ops = <RemoteInputOp>[];
    var tekst = 0;
    var kasowanie = 0;
    for (var i = 0; i < rawOps.length; i++) {
      final op = RemoteInputOp.fromJson(rawOps[i]);
      if (op == null) return null;
      if (op.kind == RemoteInputOpKind.stop && i != rawOps.length - 1) {
        return null;
      }
      tekst += op.text.length;
      kasowanie += op.count;
      if (tekst > maxInputTextUnits || kasowanie > maxInputDeletes) {
        return null;
      }
      ops.add(op);
    }
    return RemoteInputPacket(
      from: from,
      input: input as String,
      token: token,
      seq: seq,
      ops: List.unmodifiable(ops),
    );
  }
}

/// Odpowiedź na [RemoteInputPacket], zawsze zapieczętowana.
class RemoteInputReply {
  /// `false` przy odmowie (403): [reason] mówi, czy to koniec sesji.
  final bool ok;
  final String input;
  final int seq;

  /// Czy operacje zostały wpisane. `false` przy `ok` znaczy, że paczka
  /// przyszła, ale odbiorca nie miał dokąd pisać albo czekał na kartę.
  final bool applied;

  /// To jest powtórzona paczka, wpisana już za pierwszym razem.
  final bool duplicate;
  final String? reason;
  final RemoteInputTarget target;

  const RemoteInputReply({
    required this.ok,
    required this.input,
    required this.seq,
    this.applied = false,
    this.duplicate = false,
    this.reason,
    this.target = RemoteInputTarget.none,
  });

  Map<String, Object?> toJson() => {
        'reply': replyInput,
        'ok': ok,
        'input': input,
        'seq': seq,
        'applied': applied,
        if (duplicate) 'duplicate': true,
        if (reason != null) 'reason': reason,
        if (ok) 'target': target.toJson(),
      };

  /// `null`, gdy to nie jest odpowiedź na paczkę [seq] sesji [input].
  static RemoteInputReply? fromJson(Map<String, Object?>? json,
      {required String input, required int seq}) {
    if (json == null ||
        json['reply'] != replyInput ||
        json['input'] != input ||
        json['seq'] != seq ||
        json.containsKey('from')) {
      return null;
    }
    final ok = json['ok'];
    if (ok is! bool) return null;
    final reason = json['reason'];
    return RemoteInputReply(
      ok: ok,
      input: input,
      seq: seq,
      applied: json['applied'] == true,
      duplicate: json['duplicate'] == true,
      reason: reason is String ? reason : null,
      target: RemoteInputTarget.fromJson(json['target']),
    );
  }
}

/// Wynik zapisu pliku po stronie odbiorcy, mapowany na kod HTTP w server.dart.
enum FileReceiveResult {
  /// Komplet zapisany i zweryfikowany (200).
  ok,

  /// Użytkownik odmówił odbioru (403), nadawca nie ponawia automatycznie.
  rejected,

  /// Nadawca zaczął od innego bajtu, niż odbiorca ma zapisane (409):
  /// część została skasowana, ponowienie pójdzie od zera.
  offsetMismatch,

  /// Transfer się urwał albo rozmiar się nie zgadza (409), część zostaje
  /// na dysku, kolejna próba wznowi od tego miejsca.
  incomplete,

  /// Suma kontrolna złożonego pliku się nie zgadza (422), część skasowana.
  checksumMismatch,
}
