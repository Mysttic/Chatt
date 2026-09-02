import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';

import '../network/protocol.dart'
    show envelopeMarker, isEncryptedEnvelope, pairingCodeDigits;

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

  /// Para kluczy na jedno parowanie.
  static Future<SimpleKeyPair> newKeyPair() => _x25519.newKeyPair();

  static Future<List<int>> publicKeyOf(SimpleKeyPair keyPair) async =>
      (await keyPair.extractPublicKey()).bytes;

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
  static Future<({List<int> sessionKey, String code})> agree({
    required SimpleKeyPair mine,
    required List<int> theirPublicKey,
    required List<int> initiatorPublicKey,
    required List<int> responderPublicKey,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: mine,
      remotePublicKey:
          SimplePublicKey(theirPublicKey, type: KeyPairType.x25519),
    );
    final sessionKey = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: const <int>[],
      info: utf8.encode('chatt-session-v2'),
    );
    final codeBytes = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: const <int>[],
      info: [
        ...utf8.encode('chatt-code-v2'),
        ...initiatorPublicKey,
        ...responderPublicKey,
      ],
    );
    return (
      sessionKey: await sessionKey.extractBytes(),
      code: _digits(await codeBytes.extractBytes(), pairingCodeDigits),
    );
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

  /// Pakuje [payload] w kopertę AES-GCM. Nadawca zostaje jawny, bo odbiorca
  /// musi wiedzieć, czyim kluczem odszyfrować.
  static Future<Map<String, Object?>> seal({
    required Map<String, Object?> payload,
    required List<int> key,
    required String senderGuid,
  }) async {
    final box = await _gcm.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: SecretKey(key),
    );
    return {
      envelopeMarker: 1,
      'from': senderGuid,
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

  /// Guid nadawcy z koperty (do znalezienia klucza), albo null.
  static String? senderOf(Map<String, Object?> envelope) {
    final from = envelope['from'];
    return from is String && from.isNotEmpty ? from : null;
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
