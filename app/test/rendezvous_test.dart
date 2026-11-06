import 'dart:io';

import 'package:chatt/core/crypto.dart';
import 'package:chatt/network/dht.dart';
import 'package:chatt/network/rendezvous.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_udp.dart';
import 'dht_test_support.dart';

/// Skrzynka kontaktowa: dwa sparowane urządzenia zostawiają sobie w DHT
/// zaszyfrowany adres i odnajdują się bez wspólnej sieci. Testy pilnują, że
/// obie strony liczą ten sam materiał z sekretu pary, że adres w rekordzie
/// jest zaszyfrowany, i że cały obieg (zapis jednego, odczyt drugiego) działa
/// nad siecią i DHT w pamięci.
void main() {
  late FakeUdpNet net;
  late _Dht dht1;

  setUp(() {
    net = FakeUdpNet();
    final n1 = FakeDhtNode(net.create('10.9.0.1', 6881), 'rv-1');
    final n2 = FakeDhtNode(net.create('10.9.0.2', 6881), 'rv-2');
    n1.others.add((n2.id, n2.mux.address, n2.mux.port));
    dht1 = _Dht(net, n1);
  });

  Future<(Rendezvous, Rendezvous)> para() async {
    final aStatic = await ChattCrypto.newKeyPair();
    final bStatic = await ChattCrypto.newKeyPair();
    final aPub = await ChattCrypto.publicKeyOf(aStatic);
    final bPub = await ChattCrypto.publicKeyOf(bStatic);
    final aGuid = ChattCrypto.guidFromPublicKey(aPub);
    final bGuid = ChattCrypto.guidFromPublicKey(bPub);
    final a = await Rendezvous.forPeer(
        myStatic: aStatic, theirStatic: bPub, myGuid: aGuid, theirGuid: bGuid);
    final b = await Rendezvous.forPeer(
        myStatic: bStatic, theirStatic: aPub, myGuid: bGuid, theirGuid: aGuid);
    return (a, b);
  }

  test('obie strony liczą ten sam materiał', () async {
    final (a, b) = await para();
    expect(a.signSeed, b.signSeed);
    expect(a.sealKey, b.sealKey);
    expect(a.saltBase, b.saltBase);
  });

  test('inna para ma inny materiał', () async {
    final (a, _) = await para();
    final (c, _) = await para();
    expect(a.sealKey, isNot(c.sealKey));
  });

  test('A publikuje adres, B go odczytuje', () async {
    final (a, b) = await para();
    final dhtA = dht1.client();
    final dhtB = dht1.client();
    final stored = await a.publish(dhtA,
        address: InternetAddress('203.0.113.9'), port: 51820);
    expect(stored, greaterThan(0));

    final got = await b.lookup(dhtB);
    expect(got, isNotNull);
    expect(got!.address.address, '203.0.113.9');
    expect(got.port, 51820);
    await dhtA.close();
    await dhtB.close();
  });

  test('rekord w DHT nie zdradza adresu (jest zaszyfrowany)', () async {
    final (a, _) = await para();
    final dhtA = dht1.client();
    await a.publish(dhtA,
        address: InternetAddress('203.0.113.9'), port: 51820);
    // Surowe `v` ze wszystkich węzłów: nigdzie nie ma jawnego adresu.
    final jawne = dht1.node.stored.values
        .map((s) => String.fromCharCodes(s.value))
        .join('|');
    expect(jawne.contains('203.0.113.9'), isFalse);
    expect(jawne.contains('51820'), isFalse);
    await dhtA.close();
  });

  test('obca para nie odczyta cudzej skrzynki', () async {
    final (a, _) = await para();
    final (_, obcyB) = await para(); // inny sekret
    final dhtA = dht1.client();
    final dhtObcy = dht1.client();
    await a.publish(dhtA,
        address: InternetAddress('203.0.113.9'), port: 51820);
    final got = await obcyB.lookup(dhtObcy);
    expect(got, isNull);
    await dhtA.close();
    await dhtObcy.close();
  });
}

/// Pomost do jednego węzła DHT w pamięci (z bootstrapem wstrzykniętym wprost).
class _Dht {
  final FakeUdpNet net;
  final FakeDhtNode node;
  int _port = 41000;
  _Dht(this.net, this.node);

  DhtClient client() => DhtClient(
        net.create('10.9.1.${_next()}', 42000),
        bootstrap: const [],
        queryTimeout: const Duration(seconds: 1),
      )..debugBootstrap = [DhtEndpoint(node.mux.address, node.mux.port)];

  int _next() => (_port++) % 250 + 2;
}
