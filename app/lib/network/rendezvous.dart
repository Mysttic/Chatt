import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';

import '../core/crypto.dart';
import 'bencode.dart';
import 'dht.dart';

/// Skrzynka kontaktowa w DHT: jak dwa sparowane urządzenia mówią sobie „jestem
/// teraz pod tym adresem", nie mając wspólnej sieci ani serwera.
///
/// Z sekretu statyczny × statyczny ([ChattCrypto.rendezvousMaterial]) obie
/// strony liczą ten sam klucz podpisu, klucz szyfrujący i bazę soli. Każda
/// strona zapisuje swój adres pod solą wyprowadzoną z **własnego** guida
/// i numeru epoki, a czyta spod soli **drugiej** strony. Dwie sole to dwie
/// różne skrzynki (adres = SHA-1 klucza+soli), więc strony się nie nadpisują.
/// Epoka (dzień UTC) zmienia adres skrzynki co dobę, żeby po stałym adresie
/// nie dało się śledzić pary w czasie.
///
/// W rekordzie jedzie tylko zaszyfrowany adres. Węzły DHT widzą podpisany
/// szyfrogram i nic więcej.

/// Długość epoki: jeden dzień. Krótsza utrudnia odnalezienie się po przerwie,
/// dłuższa dłużej trzyma ten sam adres skrzynki.
const Duration kRendezvousEpoch = Duration(days: 1);

/// Adres rozmówcy odczytany ze skrzynki.
class RendezvousAddress {
  final InternetAddress address;
  final int port;

  /// Adres IPv6, gdy rozmówca go podał (wtedy łączymy się najpierw nim: bez
  /// NAT-u przebicie dziury jest pewniejsze).
  final InternetAddress? address6;
  final int port6;

  /// Kiedy rekord powstał (ms od epoki) — starszy niż kilka minut znaczy, że
  /// rozmówca prawdopodobnie już gdzie indziej jest.
  final int timestamp;

  const RendezvousAddress({
    required this.address,
    required this.port,
    this.address6,
    this.port6 = 0,
    required this.timestamp,
  });

  @override
  String toString() => 'RendezvousAddress(${address.address}:$port)';
}

class Rendezvous {
  final List<int> signSeed;
  final List<int> sealKey;
  final List<int> saltBase;

  /// Guid tego urządzenia i rozmówcy. Wyznaczają, pod którą solą piszemy,
  /// a spod której czytamy.
  final String myGuid;
  final String theirGuid;

  final _gcm = AesGcm.with256bits();
  DhtSigner? _signer;

  Rendezvous({
    required this.signSeed,
    required this.sealKey,
    required this.saltBase,
    required this.myGuid,
    required this.theirGuid,
  });

  /// Buduje skrzynkę z sekretu pary.
  static Future<Rendezvous> forPeer({
    required SimpleKeyPair myStatic,
    required List<int> theirStatic,
    required String myGuid,
    required String theirGuid,
  }) async {
    final m = await ChattCrypto.rendezvousMaterial(
        myStatic: myStatic, theirStatic: theirStatic);
    return Rendezvous(
      signSeed: m.signSeed,
      sealKey: m.sealKey,
      saltBase: m.saltBase,
      myGuid: myGuid,
      theirGuid: theirGuid,
    );
  }

  Future<DhtSigner> _ensureSigner() async =>
      _signer ??= await DhtSigner.fromSeed(signSeed);

  /// Numer epoki dla danej chwili (domyślnie teraz).
  int epochOf([DateTime? when]) =>
      (when ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/
      kRendezvousEpoch.inMilliseconds;

  /// Sól skrzynki: baza + epoka + guid właściciela, obcięte do 20 bajtów.
  /// Mieści się w limicie BEP 44 (64 B) i jest różna dla obu stron i epok.
  Uint8List _salt(String ownerGuid, int epoch) {
    final input = <int>[
      ...saltBase,
      ...ascii.encode('e$epoch|'),
      ...utf8.encode(ownerGuid),
    ];
    return Uint8List.fromList(
        digest.sha256.convert(input).bytes.sublist(0, 20));
  }

  /// Zapisuje własny adres do skrzynki, pod solą z własnego guida. [seq]
  /// musi rosnąć między zapisami (BEP 44 nie cofa numeru), więc bierzemy
  /// znacznik czasu w sekundach. Zwraca, do ilu węzłów rekord trafił.
  Future<int> publish(
    DhtClient dht, {
    required InternetAddress address,
    required int port,
    InternetAddress? address6,
    int port6 = 0,
    DateTime? now,
  }) async {
    final teraz = now ?? DateTime.now().toUtc();
    final signer = await _ensureSigner();
    final salt = _salt(myGuid, epochOf(teraz));
    final payload = bencode(<String, Object>{
      'ip': address.rawAddress,
      'p': port,
      if (address6 != null) 'ip6': address6.rawAddress,
      if (address6 != null) 'p6': port6,
      't': teraz.millisecondsSinceEpoch,
    });
    final sealed = await _seal(payload);
    final value = bencode(sealed); // v = napis bajtowy z szyfrogramem
    final seq = teraz.millisecondsSinceEpoch ~/ 1000;
    return dht.putMutable(signer,
        bencodedValue: value, seq: seq, salt: salt);
  }

  /// Czyta adres rozmówcy ze skrzynki (spod jego soli). Sprawdza bieżącą
  /// i poprzednią epokę, bo zapis mógł powstać tuż przed zmianą doby. null,
  /// gdy nic nie ma albo rekordu nie da się rozszyfrować.
  Future<RendezvousAddress?> lookup(DhtClient dht, {DateTime? now}) async {
    final teraz = now ?? DateTime.now().toUtc();
    final signer = await _ensureSigner();
    for (final epoch in [epochOf(teraz), epochOf(teraz) - 1]) {
      final salt = _salt(theirGuid, epoch);
      final record = await dht.getMutable(signer.publicKey, salt: salt);
      if (record == null) continue;
      final adres = await _openRecord(record.value);
      if (adres != null) return adres;
    }
    return null;
  }

  Future<RendezvousAddress?> _openRecord(Uint8List value) async {
    final sealed = tryBdecode(value);
    if (sealed is! Uint8List) return null;
    final clear = await _open(sealed);
    if (clear == null) return null;
    final payload = tryBdecode(clear);
    if (payload is! Map) return null;
    final ip = bBytes(payload, 'ip');
    final port = bInt(payload, 'p');
    if (ip == null || port == null) return null;
    final ip6 = bBytes(payload, 'ip6');
    return RendezvousAddress(
      address: InternetAddress.fromRawAddress(ip,
          type: InternetAddressType.IPv4),
      port: port,
      address6: ip6 == null
          ? null
          : InternetAddress.fromRawAddress(ip6,
              type: InternetAddressType.IPv6),
      port6: bInt(payload, 'p6') ?? 0,
      timestamp: bInt(payload, 't') ?? 0,
    );
  }

  /// AES-GCM: nonce(12) || mac(16) || szyfrogram.
  Future<Uint8List> _seal(List<int> plain) async {
    final box = await _gcm.encrypt(plain, secretKey: SecretKey(sealKey));
    return Uint8List.fromList([...box.nonce, ...box.mac.bytes, ...box.cipherText]);
  }

  Future<Uint8List?> _open(Uint8List sealed) async {
    if (sealed.length < 12 + 16) return null;
    try {
      final box = SecretBox(
        sealed.sublist(28),
        nonce: sealed.sublist(0, 12),
        mac: Mac(sealed.sublist(12, 28)),
      );
      return Uint8List.fromList(
          await _gcm.decrypt(box, secretKey: SecretKey(sealKey)));
    } catch (_) {
      return null;
    }
  }
}
