import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';

import '../network/protocol.dart' show envelopeMarker, isEncryptedEnvelope;

/// Szyfrowanie ruchu między sparowanymi urządzeniami.
///
/// Klucz powstaje przy parowaniu: obie strony robią uzgodnienie X25519,
/// a wynik przepuszczają przez HKDF z kodem PIN jako solą. Kod nie leci więc
/// przez sieć — zamiast niego jedzie skrót potwierdzający, który da się
/// policzyć tylko znając i wspólny sekret, i kod. Tym samym podszycie się pod
/// urządzenie wymaga zgadnięcia sześciu cyfr w trakcie tych dwóch minut,
/// a bierny podsłuchiwacz nie dowie się z podsłuchanej rozmowy niczego.
///
/// Ograniczenie, o którym warto wiedzieć: to nie jest pełny PAKE. Ktoś, kto
/// aktywnie wejdzie w środek parowania (osobne uzgodnienie z każdą ze stron),
/// może potem offline sprawdzić wszystkie sześciocyfrowe kody. Chroni nas
/// tylko to, że musiałby być w sieci dokładnie w tych dwóch minutach.
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

  /// Wspólny klucz sesji: X25519 + HKDF z kodem PIN jako solą.
  static Future<List<int>> sessionKey({
    required SimpleKeyPair mine,
    required List<int> theirPublicKey,
    required String pin,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: mine,
      remotePublicKey:
          SimplePublicKey(theirPublicKey, type: KeyPairType.x25519),
    );
    final derived = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(pin),
      info: utf8.encode('chatt-pair-v1'),
    );
    return derived.extractBytes();
  }

  /// Skrót, którym strona przepisująca kod dowodzi, że go zna. Wchodzą do
  /// niego oba klucze publiczne, więc nie da się go przełożyć na inną sesję.
  static Future<String> pairingTag({
    required List<int> sessionKey,
    required List<int> initiatorPublicKey,
    required List<int> responderPublicKey,
  }) async {
    final mac = await _hmac.calculateMac(
      [
        ...utf8.encode('chatt-confirm'),
        ...initiatorPublicKey,
        ...responderPublicKey,
      ],
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
