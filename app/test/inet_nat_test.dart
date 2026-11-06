import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:chatt/core/crypto.dart';
import 'package:chatt/network/bt_link.dart';
import 'package:chatt/network/dht.dart';
import 'package:chatt/network/inet_link.dart';
import 'package:chatt/network/inet_transport.dart';
import 'package:chatt/network/rendezvous.dart';
import 'package:chatt/network/secure_udp.dart';
import 'package:chatt/network/transport.dart';
import 'package:crypto/crypto.dart' as digest;
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
      Duration punch = const Duration(seconds: 6),
      Future<BtResponse> Function(BtRequest request, String guid)? obsluga}) {
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
      onRequest: obsluga ??
          (request, peerGuid) async {
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

  test('plik idzie przez NAT-y w całości, także gdy giną pakiety', () async {
    // Odbiorca liczy SHA-256 tego, co przyszło, i odsyła je w odpowiedzi.
    final sa = strona(a, b, '198.51.100.1', '192.168.1.10');
    strona(b, a, '198.51.100.2', '192.168.2.10',
        obsluga: (request, peerGuid) async {
      final suma = await digest.sha256.bind(request.body).first;
      return BtResponse.ofBytes(200, utf8.encode(suma.toString()));
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // Łącze staje bez strat; potem co dwudziesty pakiet ginie.
    expect((await sa.zapytaj(b.guid)).status, 200);
    net.loss = 0.05;

    final los = Random(68);
    final bajty =
        Uint8List.fromList(List<int>.generate(1 << 20, (_) => los.nextInt(256)));
    final plik = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'chatt_inet_${DateTime.now().microsecondsSinceEpoch}.bin');
    await plik.writeAsBytes(bajty);
    addTearDown(() => plik.delete());

    final odp = await sa.transport.stream(InternetRoute(b.guid), '/plik',
        headers: const {}, file: plik);
    expect(odp.status, 200);
    expect(InternetTransport.asText(odp), digest.sha256.convert(bajty).toString());
  });

  test('odświeżenie adresu w trakcie dzwonienia zostawia znacznik „dzwonię”',
      () async {
    // B nie odbiera, więc łącze nie stanie i nic nie nadpisze rekordu A po
    // drodze. A dzwoni od razu po starcie, kiedy zwykłe odświeżenie adresu
    // jeszcze trwa: oba zapisy muszą nieść znacznik.
    final sa = strona(a, b, '198.51.100.1', '192.168.1.10',
        punch: const Duration(milliseconds: 300));
    strona(b, a, '198.51.100.2', '192.168.2.10', odbiera: false);
    final dzwonienie = sa.mgr.linkTo(b.guid);
    await dzwonienie;
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final czytelnik = DhtClient(net.create('203.0.113.8', 4200),
        bootstrap: const [])
      ..debugBootstrap = [DhtEndpoint(dht.mux.address, dht.mux.port)];
    final skrzynkaA = await Rendezvous.forPeer(
        myStatic: b.klucz, theirStatic: a.pub, myGuid: b.guid, theirGuid: a.guid);
    final rekord = await skrzynkaA.lookup(czytelnik);
    expect(rekord, isNotNull);
    expect(rekord!.calling, isTrue);
    await czytelnik.close();
  });

  test('urządzenie bez potwierdzonej tożsamości dostaje ciszę', () async {
    // A zna tylko B. C ma poprawną tożsamość i zna adres A, ale A go nie
    // potwierdził: na jego HELLO nie wraca ani jeden pakiet.
    final c = await _Osoba.nowa();
    final muxA = net.create('203.0.113.10', 4000);
    final mgrA = InetLinkManager(
      mux: muxA,
      myStatic: a.klucz,
      myStaticPub: a.pub,
      myGuid: a.guid,
      resolveStatic: (g) async => g == b.guid ? b.pub : null,
      resolveRendezvous: (_) async => null,
    )..start();
    addTearDown(mgrA.stop);

    final muxC = net.create('203.0.113.66', 5000);
    var odA = 0;
    muxC.register((pakiet) {
      if (pakiet.address.address == '203.0.113.10') odA++;
      return false;
    });
    final rura = SecureUdpPipe(
      mux: muxC,
      myStatic: c.klucz,
      myStaticPub: c.pub,
      theirStatic: a.pub,
      myGuid: c.guid,
      remoteAddress: InternetAddress('203.0.113.10'),
      remotePort: 4000,
      initiator: true,
    );
    muxC.register((pakiet) {
      rura.handlePacket(pakiet);
      return true;
    });
    final stoi = await rura.connect()
        .timeout(const Duration(seconds: 2), onTimeout: () => false);
    expect(stoi, isFalse);
    expect(odA, 0);
    expect(mgrA.linkedGuids, isEmpty);
    await rura.close();
  });
}
