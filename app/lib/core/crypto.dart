import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';

import '../network/protocol.dart'
    show
        envelopeMarker,
        envelopeSession,
        isEncryptedEnvelope,
        pairingCodeDigits;

/// Szyfrowanie ruchu między sparowanymi urządzeniami.
///
/// Klucz powstaje przy parowaniu ze zwykłego uzgodnienia X25519, a z tego
/// samego sekretu (osobną gałęzią HKDF) liczony jest sześciocyfrowy kod do
/// porównania. Kod nie jest sekretem: obie strony pokazują go na ekranie,
/// a użytkownicy sprawdzają wzrokiem, czy jest ten sam. Napastnik w środku
/// prowadzi dwa osobne uzgodnienia, więc dostaje dwa różne kody i od razu to
/// widać.
///
/// Żeby nie mógł tych kodów naciągnąć, inicjator najpierw wysyła [commitment]
/// swojego klucza publicznego, a sam klucz dopiero po poznaniu klucza drugiej
/// strony. Bez tego napastnik mógłby losować własne klucze aż do zrównania
/// obu kodów; ze zobowiązaniem zostaje mu jedno trafienie na milion.
///
/// Poprzednia wersja mieszała kod PIN do HKDF jako sól. Było w tym słabe
/// miejsce: napastnik obecny przy parowaniu mógł potem sprawdzić offline
/// wszystkie sześciocyfrowe kody. Tutaj nie ma czego zgadywać, bo kod nie
/// bierze udziału w wyprowadzeniu klucza.
///
/// Po sparowaniu:
/// - wiadomości i zapowiedzi plików jadą jako koperta z AES-GCM (poufność
///   i integralność),
/// - treść pliku leci strumieniowo AES-CTR, bo tylko tak da się wznawiać
///   transfer od dowolnego bajtu; integralność pilnuje sha256 policzone
///   z jawnej treści, przesłane wcześniej w zaszyfrowanej zapowiedzi.
class ChattCrypto {
  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _gcm = AesGcm.with256bits();
  static final _ctr = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
  static final _hmac = Hmac.sha256();

  /// Para kluczy na jedno parowanie albo na jedną sesję.
  static Future<SimpleKeyPair> newKeyPair() => _x25519.newKeyPair();

  static Future<List<int>> publicKeyOf(SimpleKeyPair keyPair) async =>
      (await keyPair.extractPublicKey()).bytes;

  // --- Trwała tożsamość urządzenia -----------------------------------------

  /// Klucz prywatny do zapisu w bazie. Odtwarzamy z niego parę przez
  /// [identityKeyPair].
  static Future<List<int>> privateKeyOf(SimpleKeyPair keyPair) =>
      keyPair.extractPrivateKeyBytes();

  /// Para kluczy tożsamości odtworzona z zapisanego klucza prywatnego.
  static Future<SimpleKeyPair> identityKeyPair(List<int> privateKey) =>
      _x25519.newKeyPairFromSeed(privateKey);

  /// Identyfikator urządzenia liczony z jego klucza publicznego, a nie
  /// losowany. Dzięki temu nie da się podać cudzego identyfikatora bez jego
  /// klucza prywatnego — podszycie się przestaje być kwestią wpisania cudzego
  /// napisu. Kształt zostaje UUID-owy, żeby nic w bazie, logach i testach nie
  /// musiało się zmieniać.
  static String guidFromPublicKey(List<int> publicKey) {
    final skrot = digest.sha256
        .convert([...utf8.encode('chatt-identity'), ...publicKey])
        .bytes
        .sublist(0, 16);
    final hex = skrot.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Odcisk klucza do pokazania użytkownikowi: pięć grup po cztery cyfry.
  /// Tyle da się porównać wzrokiem, a trafienie w cudzy odcisk wymaga
  /// przeszukania przestrzeni 10^20.
  static String fingerprint(List<int> publicKey) {
    final bajty = digest.sha256
        .convert([...utf8.encode('chatt-fingerprint'), ...publicKey])
        .bytes;
    final grupy = <String>[];
    for (var i = 0; i < 5; i++) {
      var wartosc = 0;
      for (var j = 0; j < 3; j++) {
        wartosc = (wartosc << 8) | bajty[i * 3 + j];
      }
      grupy.add((wartosc % 10000).toString().padLeft(4, '0'));
    }
    return grupy.join(' ');
  }

  // --- Uścisk dłoni sesji (Noise KK) ---------------------------------------

  /// Klucz sesji z czterech uzgodnień X25519. Obie strony znają nawzajem swój
  /// klucz statyczny (z discovery albo z `/info`) i dorzucają do tego klucze
  /// efemeryczne, ważne tylko na tę jedną sesję.
  ///
  /// Co daje który człon:
  /// - `ee` (efemeryczny × efemeryczny) — **forward secrecy**: po skasowaniu
  ///   kluczy efemerycznych nagrany ruch nie odszyfruje się nawet komuś, kto
  ///   później wykradnie klucze statyczne obu stron,
  /// - `ss` (statyczny × statyczny) — wiąże sesję z tożsamościami,
  /// - `es` i `se` — wiążą każdy klucz efemeryczny z tożsamością drugiej
  ///   strony, więc napastnik bez klucza prywatnego nie podstawi swojego.
  ///
  /// Do `info` wchodzi cały zapis rozmowy (oba klucze statyczne i oba
  /// efemeryczne w ustalonej kolejności), więc podmiana czegokolwiek po
  /// drodze daje po prostu inny klucz i ruch się nie odszyfruje.
  static Future<List<int>> sessionKey({
    required SimpleKeyPair myStatic,
    required SimpleKeyPair myEphemeral,
    required List<int> theirStatic,
    required List<int> theirEphemeral,
    required bool initiator,
    required List<int> initiatorStatic,
    required List<int> responderStatic,
    required List<int> initiatorEphemeral,
    required List<int> responderEphemeral,
  }) async {
    Future<List<int>> dh(SimpleKeyPair mine, List<int> ich) async =>
        (await _x25519.sharedSecretKey(
          keyPair: mine,
          remotePublicKey: SimplePublicKey(ich, type: KeyPairType.x25519),
        )).extractBytes();

    final ee = await dh(myEphemeral, theirEphemeral);
    final ss = await dh(myStatic, theirStatic);
    // Kolejność es/se musi być ta sama po obu stronach, a każda strona liczy
    // je innym kluczem — stąd rozróżnienie ról.
    final es = initiator
        ? await dh(myEphemeral, theirStatic)
        : await dh(myStatic, theirEphemeral);
    final se = initiator
        ? await dh(myStatic, theirEphemeral)
        : await dh(myEphemeral, theirStatic);

    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey([...ee, ...es, ...se, ...ss]),
      nonce: const <int>[],
      info: [
        ...utf8.encode('chatt-session-v5'),
        ...initiatorStatic,
        ...responderStatic,
        ...initiatorEphemeral,
        ...responderEphemeral,
      ],
    );
    return derived.extractBytes();
  }

  /// Klucz na jeden plik, wyprowadzony z klucza sesji w chwili zapowiedzi.
  /// Zapisujemy go obok części transferu, więc wznowienie działa nawet wtedy,
  /// gdy sesja dawno wygasła — bez tego strumień AES-CTR nie miałby czym
  /// dokończyć.
  static Future<List<int>> fileKey({
    required List<int> sessionKey,
    required String messageGuid,
  }) async {
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(sessionKey),
      nonce: const <int>[],
      info: utf8.encode('chatt-file-v5|$messageGuid'),
    );
    return derived.extractBytes();
  }

  /// Znacznik klucza pliku do zapowiedzi. Sam klucz nigdzie nie idzie —
  /// odbiorca porównuje tylko, czy jego część transferu była szyfrowana tym
  /// samym, czym nadawca szyfruje teraz.
  static String keyEpoch(List<int> fileKey) => base64.encode(
        digest.sha256
            .convert([...utf8.encode('chatt-file-epoch'), ...fileKey])
            .bytes
            .sublist(0, 8),
      );

  /// Zobowiązanie do klucza publicznego: inicjator wysyła je, zanim pozna
  /// klucz drugiej strony, więc potem nie może już swojego podmienić.
  static String commitment(List<int> publicKey) => base64.encode(
        digest.sha256
            .convert([...utf8.encode('chatt-commit'), ...publicKey])
            .bytes,
      );

  /// Uzgodnienie: z jednego sekretu X25519 wychodzą dwie niezależne rzeczy —
  /// klucz sesji do szyfrowania ruchu i kod do porównania na ekranach.
  /// Do kodu wchodzą oba klucze publiczne w ustalonej kolejności, więc
  /// napastnik nie przełoży kodu z jednej sesji na drugą.
  /// Do kodu wchodzą oba klucze **statyczne** (tożsamości), więc zgodny kod
  /// dowodzi nie tylko braku kogoś w środku, ale też tego, że po drugiej
  /// stronie siedzi właściciel klucza prywatnego od tej tożsamości. Od
  /// protokołu 5 nic tu już nie ustala klucza do szyfrowania ruchu — ten
  /// bierze się z sesji — więc wynikiem jest sam kod do porównania.
  static Future<String> agreeCode({
    required SimpleKeyPair mine,
    required List<int> theirPublicKey,
    required List<int> initiatorPublicKey,
    required List<int> responderPublicKey,
    required List<int> initiatorStatic,
    required List<int> responderStatic,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: mine,
      remotePublicKey:
          SimplePublicKey(theirPublicKey, type: KeyPairType.x25519),
    );
    final codeBytes = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: const <int>[],
      info: [
        ...utf8.encode('chatt-code-v5'),
        ...initiatorPublicKey,
        ...responderPublicKey,
        ...initiatorStatic,
        ...responderStatic,
      ],
    );
    return _digits(await codeBytes.extractBytes(), pairingCodeDigits);
  }

  /// Pierwsze bajty skrótu na [count] cyfr, z zerami wiodącymi.
  static String _digits(List<int> bytes, int count) {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      value = (value << 8) | bytes[i];
    }
    final modulo = pow(10, count).toInt();
    return (value % modulo).toString().padLeft(count, '0');
  }

  /// Podpis odpowiedzi discovery: dowód, że po drugiej stronie jest to samo
  /// urządzenie, z którym mamy wspólny klucz. [nonce] pochodzi z zapytania,
  /// więc podsłuchanej odpowiedzi nie da się użyć przy następnym skanie.
  static Future<String> discoveryTag({
    required List<int> sessionKey,
    required String guid,
    required int tcpPort,
    required String nonce,
  }) async {
    final mac = await _hmac.calculateMac(
      utf8.encode('chatt-here|$guid|$tcpPort|$nonce'),
      secretKey: SecretKey(sessionKey),
    );
    return base64.encode(mac.bytes);
  }

  /// Porównanie w stałym czasie — przy skrótach to darmowa ostrożność.
  static bool sameTag(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  // --- Koperta na JSON (wiadomości, zapowiedzi plików) ---------------------

  static bool isEnvelope(Map<String, Object?> json) =>
      isEncryptedEnvelope(json);

  /// Pakuje [payload] w kopertę AES-GCM. Jawny zostaje sam numer sesji —
  /// po nim odbiorca znajduje klucz. Guid nadawcy z koperty zniknął, więc
  /// podsłuchujący nie ma po czym rozpoznać, kto z kim rozmawia.
  static Future<Map<String, Object?>> seal({
    required Map<String, Object?> payload,
    required List<int> key,
    required String sessionId,
  }) async {
    final box = await _gcm.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: SecretKey(key),
    );
    return {
      envelopeMarker: 1,
      envelopeSession: sessionId,
      'nonce': base64.encode(box.nonce),
      'mac': base64.encode(box.mac.bytes),
      'data': base64.encode(box.cipherText),
    };
  }

  /// Rozpakowuje kopertę. null = nie nasza, uszkodzona albo podmieniona.
  static Future<Map<String, Object?>?> open({
    required Map<String, Object?> envelope,
    required List<int> key,
  }) async {
    try {
      final box = SecretBox(
        base64.decode(envelope['data']! as String),
        nonce: base64.decode(envelope['nonce']! as String),
        mac: Mac(base64.decode(envelope['mac']! as String)),
      );
      final clear = await _gcm.decrypt(box, secretKey: SecretKey(key));
      final decoded = jsonDecode(utf8.decode(clear));
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Klucz do podpisywania odpowiedzi discovery. Wychodzi z uzgodnienia
  /// samych kluczy statycznych, więc obie strony policzą go bez żywej sesji —
  /// discovery dzieje się, zanim jakakolwiek sesja powstanie.
  static Future<List<int>> discoveryKey({
    required SimpleKeyPair myStatic,
    required List<int> theirStatic,
  }) async {
    final wspolny = await _x25519.sharedSecretKey(
      keyPair: myStatic,
      remotePublicKey: SimplePublicKey(theirStatic, type: KeyPairType.x25519),
    );
    final derived = await _hkdf.deriveKey(
      secretKey: wspolny,
      nonce: const <int>[],
      info: utf8.encode('chatt-discovery-v5'),
    );
    return derived.extractBytes();
  }

  // --- Strumień pliku ------------------------------------------------------

  /// Nonce dla pliku: guid wiadomości ORAZ suma kontrolna treści. Sam guid
  /// nie wystarcza — ponowienie wysyłki tej samej wiadomości po podmianie
  /// pliku pod tą samą ścieżką użyłoby drugi raz tego samego strumienia
  /// klucza, a to przy AES-CTR wystawia różnicę obu treści. Obie strony
  /// liczą to samo: suma przychodzi w zapowiedzi chronionej AES-GCM.
  static List<int> fileNonce(String messageGuid, String contentHash) =>
      Uint8List.fromList(digest.sha256
          .convert(utf8.encode('$messageGuid|$contentHash'))
          .bytes
          .sublist(0, 12));

  /// AES-CTR w obie strony (szyfrowanie i odszyfrowanie to ta sama operacja).
  /// [startOffset] to numer bajtu, od którego zaczyna się [data] — dzięki temu
  /// wznowiony transfer trafia w to samo miejsce strumienia klucza.
  static Stream<List<int>> crypt(
    Stream<List<int>> data, {
    required List<int> key,
    required List<int> nonce,
    int startOffset = 0,
  }) async* {
    final secret = SecretKey(key);
    var offset = startOffset;
    await for (final chunk in data) {
      if (chunk.isEmpty) continue;
      final box = await _ctr.encrypt(
        chunk,
        secretKey: secret,
        nonce: nonce,
        keyStreamIndex: offset,
      );
      offset += chunk.length;
      yield box.cipherText;
    }
  }
}
