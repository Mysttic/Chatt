import 'dart:convert';
import 'dart:io';

import 'package:chatt/core/crypto.dart';
import 'package:chatt/network/bt_link.dart';
import 'package:chatt/network/dht.dart';
import 'package:chatt/network/inet_link.dart';
import 'package:chatt/network/inet_transport.dart';
import 'package:chatt/network/rendezvous.dart';
import 'package:chatt/network/stun.dart';
import 'package:chatt/network/transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_udp.dart';
import 'dht_test_support.dart';

/// Capstone drogi internetowej: dwa urządzenia za „NAT-em" (różne gniazda
/// w sieci w pamięci), wspólny węzeł DHT jako skrzynka, przebicie dziury
/// i żądanie/odpowiedź tym samym multiplekserem co reszta aplikacji.
void main() {
  test('A łączy się z B przez skrzynkę i dostaje odpowiedź', () async {
    final net = FakeUdpNet();
    final dhtNode = FakeDhtNode(net.create('10.0.0.1', 6881), 'dht');

    // Tożsamości.
    final ka = await ChattCrypto.newKeyPair();
    final kb = await ChattCrypto.newKeyPair();
    final pa = await ChattCrypto.publicKeyOf(ka);
    final pb = await ChattCrypto.publicKeyOf(kb);
    final ga = ChattCrypto.guidFromPublicKey(pa);
    final gb = ChattCrypto.guidFromPublicKey(pb);

    // Skrzynki par (każda strona liczy swoją, z tym samym sekretem).
    Future<Rendezvous> rvA(String guid) =>
        Rendezvous.forPeer(myStatic: ka, theirStatic: pb, myGuid: ga, theirGuid: gb);
    Future<Rendezvous> rvB(String guid) =>
        Rendezvous.forPeer(myStatic: kb, theirStatic: pa, myGuid: gb, theirGuid: ga);

    // Menedżer A.
    final muxA = net.create('10.0.0.10', 4000);
    final mgrA = InetLinkManager(
      mux: muxA,
      myStatic: ka,
      myStaticPub: pa,
      myGuid: ga,
      resolveStatic: (g) async => g == gb ? pb : null,
      resolveRendezvous: (g) async => g == gb ? await rvA(g) : null,
    )
      ..debugPublic = StunMapping(InternetAddress('10.0.0.10'), 4000)
      ..dht.debugBootstrap = [DhtEndpoint(dhtNode.mux.address, dhtNode.mux.port)];

    // Menedżer B.
    final muxB = net.create('10.0.0.11', 4000);
    final mgrB = InetLinkManager(
      mux: muxB,
      myStatic: kb,
      myStaticPub: pb,
      myGuid: gb,
      resolveStatic: (g) async => g == ga ? pa : null,
      resolveRendezvous: (g) async => g == ga ? await rvB(g) : null,
    )
      ..debugPublic = StunMapping(InternetAddress('10.0.0.11'), 4000)
      ..dht.debugBootstrap = [DhtEndpoint(dhtNode.mux.address, dhtNode.mux.port)];

    // B odpowiada na /info, tak jak serwer Chatta.
    final transportA = InternetTransport(manager: mgrA);
    final transportB = InternetTransport(
      manager: mgrB,
      onRequest: (request, peerGuid) async {
        if (request.path == '/info') {
          // Odbierz całe ciało żądania (puste) i odpowiedz.
          await for (final _ in request.body) {}
          return BtResponse.ofBytes(
              200, utf8.encode(jsonEncode({'app': 'chatt', 'from': peerGuid})));
        }
        return BtResponse.ofBytes(404, const []);
      },
    );
    transportA.start();
    transportB.start();

    // B musi być w skrzynce, zanim A go poszuka (w realu publikuje co jakiś
    // czas sam z siebie). Publikujemy adres B przez osobnego klienta DHT.
    final publisher = DhtClient(net.create('10.0.0.20', 4100),
        bootstrap: const [])
      ..debugBootstrap = [DhtEndpoint(dhtNode.mux.address, dhtNode.mux.port)];
    final rendezvousB = await rvB(ga);
    final stored = await rendezvousB.publish(publisher,
        address: InternetAddress('10.0.0.11'), port: 4000);
    expect(stored, greaterThan(0));

    // A pyta B o /info — to uruchamia odnalezienie w skrzynce i przebicie.
    final reply = await transportA.request(
      InternetRoute(gb),
      'GET',
      '/info',
      timeout: const Duration(seconds: 5),
    );

    expect(reply.status, 200);
    final json = jsonDecode(InternetTransport.asText(reply)) as Map;
    expect(json['app'], 'chatt');
    expect(json['from'], ga); // B zobaczył, że to A puka

    expect(transportA.isLinked(gb), isTrue);
    expect(mgrA.publicAddress?.label, '10.0.0.10:4000');

    await transportA.stop();
    await transportB.stop();
    await publisher.close();
  });

  test('bierny odbiorca sam publikuje adres i daje się znaleźć', () async {
    final net = FakeUdpNet();
    final dhtNode = FakeDhtNode(net.create('10.0.0.1', 6881), 'dht');
    final ka = await ChattCrypto.newKeyPair();
    final kb = await ChattCrypto.newKeyPair();
    final pa = await ChattCrypto.publicKeyOf(ka);
    final pb = await ChattCrypto.publicKeyOf(kb);
    final ga = ChattCrypto.guidFromPublicKey(pa);
    final gb = ChattCrypto.guidFromPublicKey(pb);
    Future<Rendezvous> rvA(String g) => Rendezvous.forPeer(
        myStatic: ka, theirStatic: pb, myGuid: ga, theirGuid: gb);
    Future<Rendezvous> rvB(String g) => Rendezvous.forPeer(
        myStatic: kb, theirStatic: pa, myGuid: gb, theirGuid: ga);

    final mgrA = InetLinkManager(
      mux: net.create('10.0.0.10', 4000),
      myStatic: ka, myStaticPub: pa, myGuid: ga,
      resolveStatic: (g) async => g == gb ? pb : null,
      resolveRendezvous: (g) async => g == gb ? await rvA(g) : null,
    )
      ..debugPublic = StunMapping(InternetAddress('10.0.0.10'), 4000)
      ..dht.debugBootstrap = [DhtEndpoint(dhtNode.mux.address, dhtNode.mux.port)];

    // B dostaje listę potwierdzonych rozmówców, więc sam z siebie wpisuje
    // swój adres do skrzynki A — bez żadnego ręcznego publishera.
    final mgrB = InetLinkManager(
      mux: net.create('10.0.0.11', 4000),
      myStatic: kb, myStaticPub: pb, myGuid: gb,
      resolveStatic: (g) async => g == ga ? pa : null,
      resolveRendezvous: (g) async => g == ga ? await rvB(g) : null,
      verifiedPeers: () async => [ga],
    )
      ..debugPublic = StunMapping(InternetAddress('10.0.0.11'), 4000)
      ..dht.debugBootstrap = [DhtEndpoint(dhtNode.mux.address, dhtNode.mux.port)];

    final transportA = InternetTransport(manager: mgrA);
    final transportB = InternetTransport(
      manager: mgrB,
      onRequest: (request, peerGuid) async {
        await for (final _ in request.body) {}
        return BtResponse.ofBytes(200, utf8.encode('ok'));
      },
    );
    transportA.start();
    transportB.start();

    // Dajemy biernej publikacji B dojść do DHT, po czym A dzwoni.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final reply = await transportA.request(
      InternetRoute(gb),
      'GET',
      '/info',
      timeout: const Duration(seconds: 5),
    );
    expect(reply.status, 200);
    expect(transportA.isLinked(gb), isTrue);

    await transportA.stop();
    await transportB.stop();
  });
}
