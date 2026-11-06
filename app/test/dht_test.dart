import 'dart:convert';
import 'dart:typed_data';

import 'package:chatt/network/bencode.dart';
import 'package:chatt/network/dht.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_udp.dart';
import 'dht_test_support.dart';

/// Klient DHT do skrzynki kontaktowej. Najpierw zgodność z wektorami BEP 44
/// (adres skrzynki, bajty do podpisu, sam podpis Ed25519), potem pełny obieg
/// zapisu i odczytu nad siecią UDP w pamięci.
void main() {
  Uint8List hex(String s) => Uint8List.fromList([
        for (var i = 0; i < s.length; i += 2)
          int.parse(s.substring(i, i + 2), radix: 16),
      ]);
  String hexOf(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  // Ziarno z przykładu BEP 44. UWAGA: przykładowy klucz publiczny i podpis
  // w tekście BEP 44 pochodzą ze starej, niestandardowej implementacji Ed25519
  // (sprzed RFC 8032) i NIE zgadzają się z tym, czego oczekują dzisiejsze
  // węzły DHT (libtorrent liczy Ed25519 zgodnie z RFC 8032). Wartości poniżej
  // policzono dla tego samego ziarna OpenSSL-em (kanon RFC 8032), więc są
  // dokładnie takie, jakie przyjmie prawdziwa sieć. Sam kształt bajtów do
  // podpisu (sekcje „bajty do podpisu") bierze się wprost z BEP 44 i jest
  // niezależny od implementacji Ed25519.
  final seed = hex('e06d3183d14159228433ed599221b80bd0a5ce8352e4bdf0262f76786ef1c74d');
  final pub = 'fe2252beefc08c16df947899c9d5e3c081cf088c94da1b136c398680ccfb891f';
  final value = bencode('Hello World!'); // 12:Hello World!

  group('wektory BEP 44 / RFC 8032', () {
    test('klucz publiczny z ziarna (RFC 8032)', () async {
      final signer = await DhtSigner.fromSeed(seed);
      expect(hexOf(signer.publicKey), pub);
    });

    test('adres skrzynki bez soli = SHA-1 klucza', () {
      expect(hexOf(dhtTarget(hex(pub))),
          'd2db3b52cbd201ab03a54e49169eccee5786ebd6');
    });

    test('adres skrzynki z solą "foobar" = SHA-1 klucza+soli', () {
      expect(hexOf(dhtTarget(hex(pub), ascii.encode('foobar'))),
          'b997c45bedec5b79b901986cf94902e3bc867896');
    });

    test('bajty do podpisu bez soli (z BEP 44)', () {
      final buffer = bep44SignatureBuffer(const [], 1, value);
      expect(latin1.decode(buffer), '3:seqi1e1:v12:Hello World!');
    });

    test('bajty do podpisu z solą (z BEP 44)', () {
      final buffer = bep44SignatureBuffer(ascii.encode('foobar'), 1, value);
      expect(latin1.decode(buffer), '4:salt6:foobar3:seqi1e1:v12:Hello World!');
    });

    test('podpis RFC 8032 bez soli', () async {
      final signer = await DhtSigner.fromSeed(seed);
      final sig = await signer.sign(bep44SignatureBuffer(const [], 1, value));
      expect(hexOf(sig),
          'c44ad65291c2b1087218db8a43e3fa7b73cfa01b585b0ff9e6b962ed50e701a1'
          'beedd5ee41c21054a2d04bed722ff79951cdd6c389b7bca5331a6dbc61e2750b');
    });

    test('podpis RFC 8032 z solą', () async {
      final signer = await DhtSigner.fromSeed(seed);
      final sig =
          await signer.sign(bep44SignatureBuffer(ascii.encode('foobar'), 1, value));
      expect(hexOf(sig),
          '63522541c46ae4f88104fd870dd46fb109bf3b019a54ea9a4fb8836f6fd4443d'
          '66e69ade645319d3d292d797420033482701a69bdc99ff4914cbf2f385d1020b');
    });

    test('weryfikacja odrzuca zmieniony podpis', () async {
      final signer = await DhtSigner.fromSeed(seed);
      final buffer = bep44SignatureBuffer(const [], 1, value);
      final sig = await signer.sign(buffer);
      expect(await DhtSigner.verify(buffer, sig, signer.publicKey), isTrue);
      sig[0] ^= 1;
      expect(await DhtSigner.verify(buffer, sig, signer.publicKey), isFalse);
    });
  });

  group('zapis i odczyt nad siecią w pamięci', () {
    late FakeUdpNet net;
    late FakeDhtNode node1;
    late FakeDhtNode node2;

    setUp(() {
      net = FakeUdpNet();
      // Dwa węzły: klient trafia na pierwszy (rozruchowy), a ten odsyła go
      // do drugiego, więc test przechodzi też krok iteracyjny.
      node1 = FakeDhtNode(net.create('10.0.0.1', 6881), 'wezel-1');
      node2 = FakeDhtNode(net.create('10.0.0.2', 6881), 'wezel-2');
      node1.others.add((node2.id, node2.mux.address, node2.mux.port));
    });

    DhtClient client() => DhtClient(
          net.create('10.0.0.9', 40000),
          bootstrap: const [],
          queryTimeout: const Duration(seconds: 1),
        )..debugBootstrap = [
            DhtEndpoint(node1.mux.address, node1.mux.port),
          ];

    test('put trafia do węzłów, get odczytuje i weryfikuje', () async {
      final signer = await DhtSigner.fromSeed(seed);
      final salt = ascii.encode('chatt-test');
      final record = bencode(<String, Object>{'addr': '203.0.113.7:51820'});

      final pisarz = client();
      final stored = await pisarz.putMutable(signer,
          bencodedValue: record, seq: 1, salt: salt);
      expect(stored, greaterThan(0));
      // Rekord wylądował w pamięci węzłów.
      expect(node1.stored.isNotEmpty || node2.stored.isNotEmpty, isTrue);

      final czytelnik = client();
      final got = await czytelnik.getMutable(signer.publicKey, salt: salt);
      expect(got, isNotNull);
      expect(got!.seq, 1);
      final decoded = bdecode(got.value) as Map;
      expect(latin1.decode(decoded['addr'] as Uint8List), '203.0.113.7:51820');

      await pisarz.close();
      await czytelnik.close();
    });

    test('nieznana skrzynka daje null', () async {
      final signer = await DhtSigner.fromSeed(seed);
      final czytelnik = client();
      final got = await czytelnik
          .getMutable(signer.publicKey, salt: ascii.encode('pusta'));
      expect(got, isNull);
      await czytelnik.close();
    });

    test('podrobiony rekord (zły podpis) jest odrzucany przy odczycie', () async {
      final signer = await DhtSigner.fromSeed(seed);
      final salt = ascii.encode('chatt-test');
      // Węzeł trzyma rekord z poprawnym kluczem, ale zepsutym podpisem.
      final record = bencode(<String, Object>{'addr': 'fałszywy'});
      node1.stored[keyOf(dhtTarget(signer.publicKey, salt))] = StoredItem(
        value: record,
        seq: 9,
        publicKey: signer.publicKey,
        signature: Uint8List(64), // same zera: podpis nieważny
      );
      final czytelnik = client();
      final got = await czytelnik.getMutable(signer.publicKey, salt: salt);
      expect(got, isNull);
      await czytelnik.close();
    });
  });
}
