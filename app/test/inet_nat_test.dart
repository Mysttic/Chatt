import 'dart:convert';

import 'package:chatt/core/crypto.dart';
import 'package:chatt/network/bt_link.dart';
import 'package:chatt/network/dht.dart';
import 'package:chatt/network/inet_link.dart';
import 'package:chatt/network/inet_transport.dart';
import 'package:chatt/network/rendezvous.dart';
import 'package:chatt/network/transport.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dht_test_support.dart';
import 'fake_udp.dart';

/// Droga internetowa za NAT-ami w kształcie zmierzonych na sprzęcie
/// (docs/spike-nat.md): każdy NAT wpuszcza pakiet tylko od adresu, do którego
/// gniazdo samo coś wysłało. HELLO dzwoniącego dochodzi więc dopiero po tym,
/// jak odbiorca zapuka pod jego adres.
class _Strona {
  _Strona(this.guid, this.mgr, this.transport, this.mux, this.nat);
  final String guid;
  final InetLinkManager mgr;
  final InternetTransport transport;
  final FakeUdpMux mux;
  final FakeNat nat;

  Future<TransportReply> zapytaj(String guid) => transport.request(
        InternetRoute(guid),
        'GET',
        '/info',
        timeout: const Duration(seconds: 2),
      );
}

class _Osoba {
  _Osoba(this.klucz, this.pub, this.guid);
  final SimpleKeyPair klucz;
  final List<int> pub;
  final String guid;

  static Future<_Osoba> nowa() async {
    final k = await ChattCrypto.newKeyPair();
    final p = await ChattCrypto.publicKeyOf(k);
    return _Osoba(k, p, ChattCrypto.guidFromPublicKey(p));
  }
}

void main() {
  late FakeUdpNet net;
  late FakeDhtNode dht;
  late _Osoba a;
  late _Osoba b;
  final doSprzatania = <_Strona>[];

  setUp(() async {
    net = FakeUdpNet();
    dht = FakeDhtNode(net.create('203.0.113.1', 6881), 'dht');
    a = await _Osoba.nowa();
    b = await _Osoba.nowa();
  });

  tearDown(() async {
    for (final s in doSprzatania) {
      await s.transport.stop();
    }
    doSprzatania.clear();
  });

  /// Urządzenie za własnym NAT-em. [odbiera]: czyta skrzynkę rozmówcy i puka,
  /// jak w aplikacji; bez tego tylko dzwoni.
  _Strona strona(_Osoba ja, _Osoba on, String publiczny, String prywatny,
      {bool odbiera = true,
      Duration punch = const Duration(seconds: 6)}) {
    final nat = net.createNat(publiczny);
    final mux = net.create(prywatny, 4000, behind: nat);
    final mgr = InetLinkManager(
      mux: mux,
      myStatic: ja.klucz,
      myStaticPub: ja.pub,
      myGuid: ja.guid,
      resolveStatic: (g) async => g == on.guid ? on.pub : null,
      resolveRendezvous: (g) async => g == on.guid
          ? await Rendezvous.forPeer(
              myStatic: ja.klucz,
              theirStatic: on.pub,
              myGuid: ja.guid,
              theirGuid: on.guid)
          : null,
      verifiedPeers: odbiera ? () async => [on.guid] : null,
      watchInterval: const Duration(milliseconds: 300),
      watchMax: const Duration(seconds: 1),
      punchTimeout: punch,
      relookup: const Duration(seconds: 1),
      knockGap: const Duration(milliseconds: 50),
      knockFor: const Duration(seconds: 3),
    )
      ..debugStun = (() => nat.mappingOf(mux))
      ..dht.debugBootstrap = [DhtEndpoint(dht.mux.address, dht.mux.port)];
    final transport = InternetTransport(
      manager: mgr,
      onRequest: (request, peerGuid) async {
        await for (final _ in request.body) {}
        return BtResponse.ofBytes(200, utf8.encode(peerGuid));
      },
    );
    transport.start();
    final s = _Strona(ja.guid, mgr, transport, mux, nat);
    doSprzatania.add(s);
    return s;
  }

  test('bez pukania NAT odbiorcy nie wpuszcza HELLO', () async {
    final sa = strona(a, b, '198.51.100.1', '192.168.1.10',
        punch: const Duration(seconds: 2));
    final sb = strona(b, a, '198.51.100.2', '192.168.2.10', odbiera: false);
    // Adres B trafia do skrzynki ręcznie: B sam nie publikuje i nie puka.
    final publisher = DhtClient(net.create('203.0.113.9', 4100),
        bootstrap: const [])
      ..debugBootstrap = [DhtEndpoint(dht.mux.address, dht.mux.port)];
    final mapowanie = sb.nat.mappingOf(sb.mux);
    final skrzynkaB = await Rendezvous.forPeer(
        myStatic: b.klucz, theirStatic: a.pub, myGuid: b.guid, theirGuid: a.guid);
    expect(
        await skrzynkaB.publish(publisher,
            address: mapowanie.address, port: mapowanie.port),
        greaterThan(0));

    final odp = await sa.zapytaj(b.guid);
    expect(odp.status, -1);
    expect(sb.nat.dropped, greaterThan(0));
    await publisher.close();
  });

  test('odbiorca puka pod adres dzwoniącego i HELLO dochodzi', () async {
    final sa = strona(a, b, '198.51.100.1', '192.168.1.10');
    final sb = strona(b, a, '198.51.100.2', '192.168.2.10');
    // B zdąża wpisać swój adres do skrzynki, zanim A zadzwoni.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final odp = await sa.zapytaj(b.guid);
    expect(odp.status, 200);
    expect(InternetTransport.asText(odp), a.guid);
    expect(sa.transport.isLinked(b.guid), isTrue);
    expect(sb.mgr.isLinked(a.guid), isTrue);
  });

  test('odbiorca z nieaktualnym adresem w skrzynce wpisuje nowy', () async {
    final sa = strona(a, b, '198.51.100.1', '192.168.1.10');
    final sb = strona(b, a, '198.51.100.2', '192.168.2.10');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final stary = sb.nat.mappingOf(sb.mux);
    // NAT B zapomina mapowanie, jak po długiej ciszy: adres w skrzynce
    // prowadzi donikąd, a następny pakiet B wyjdzie z innego portu.
    sb.nat.forget();

    final odp = await sa.zapytaj(b.guid);
    expect(odp.status, 200);
    expect(sb.nat.mappingOf(sb.mux).port, isNot(stary.port));
  });

  test('obie strony dzwonią naraz i zostaje jedno łącze', () async {
    final sa = strona(a, b, '198.51.100.1', '192.168.1.10');
    final sb = strona(b, a, '198.51.100.2', '192.168.2.10');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final odpowiedzi =
        await Future.wait([sa.zapytaj(b.guid), sb.zapytaj(a.guid)]);
    expect(odpowiedzi.map((o) => o.status), [200, 200]);
    expect(sa.mgr.linkedGuids, [b.guid]);
    expect(sb.mgr.linkedGuids, [a.guid]);
  });
}
