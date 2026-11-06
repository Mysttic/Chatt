import 'dart:io';

import 'package:chatt/core/crypto.dart';
import 'package:chatt/network/secure_udp.dart';
import 'package:chatt/network/udp_mux.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_udp.dart';

/// Zaszyfrowana, niezawodna rura po UDP. Testy nad siecią w pamięci
/// sprawdzają uścisk, dostarczanie w kolejności mimo gubienia i przestawiania
/// pakietów, odporność na powtórki i to, że napastnik bez klucza statycznego
/// nie postawi łącza.
void main() {
  late FakeUdpNet net;

  /// Para łączy: dwa klucze statyczne, dwa gniazda, uścisk w obie strony.
  /// Oddaje gotowe, połączone rury i zebrane u każdej strony bajty.
  Future<({SecureUdpPipe a, SecureUdpPipe b, List<int> gotA, List<int> gotB})>
      parka({double loss = 0}) async {
    net.loss = loss;
    final aStatic = await ChattCrypto.newKeyPair();
    final bStatic = await ChattCrypto.newKeyPair();
    final aPub = await ChattCrypto.publicKeyOf(aStatic);
    final bPub = await ChattCrypto.publicKeyOf(bStatic);

    final muxA = net.create('10.0.0.1', 5000);
    final muxB = net.create('10.0.0.2', 5000);

    final a = SecureUdpPipe(
      mux: muxA,
      myStatic: aStatic,
      myStaticPub: aPub,
      theirStatic: bPub,
      myGuid: 'AAA',
      remoteAddress: InternetAddress('10.0.0.2'),
      remotePort: 5000,
      initiator: true,
    );
    final b = SecureUdpPipe(
      mux: muxB,
      myStatic: bStatic,
      myStaticPub: bPub,
      theirStatic: aPub,
      myGuid: 'BBB',
      remoteAddress: InternetAddress('10.0.0.1'),
      remotePort: 5000,
      initiator: false,
    );

    // Routing pakietów do właściwej rury; B przyjmuje HELLO od A.
    muxA.register((p) {
      a.handlePacket(p);
      return true;
    });
    muxB.register((p) {
      final hello = parseHello(p.data);
      if (hello != null) {
        b.acceptHello(hello.ephemeral);
      } else {
        b.handlePacket(p);
      }
      return true;
    });

    final gotA = <int>[];
    final gotB = <int>[];
    a.input.listen(gotA.addAll);
    b.input.listen(gotB.addAll);

    final up = await a.connect();
    expect(up, isTrue);
    await b.ready;
    return (a: a, b: b, gotA: gotA, gotB: gotB);
  }

  setUp(() => net = FakeUdpNet());

  test('uścisk staje i obie strony liczą ten sam klucz', () async {
    final p = await parka();
    expect(p.a.state, LinkState.up);
    expect(p.b.state, LinkState.up);
    await p.a.close();
    await p.b.close();
  });

  test('bajty dochodzą w obie strony', () async {
    final p = await parka();
    p.a.add(utf8Bytes('czesc od A'));
    p.b.add(utf8Bytes('i od B'));
    await _settle();
    expect(String.fromCharCodes(p.gotB), 'czesc od A');
    expect(String.fromCharCodes(p.gotA), 'i od B');
    await p.a.close();
    await p.b.close();
  });

  test('duży strumień dochodzi w kolejności mimo 20% strat', () async {
    final p = await parka(loss: 0.2);
    // 50 kB rosnącego wzorca: każda luka albo przestawienie od razu widać.
    final data = Uint8List.fromList(
        List<int>.generate(50000, (i) => i % 251));
    p.a.add(data);
    // Czekamy na komplet, a nie stałą liczbę rund: na Windowsie bez
    // podniesionej rozdzielczości zegara Future.delayed(1 ms) trwa 15,6 ms
    // i 4000 rund przekraczało limit testu.
    await _czekajNa(() => p.gotB.length >= data.length,
        limit: const Duration(seconds: 25));
    expect(p.gotB.length, data.length);
    expect(listEquals(p.gotB, data), isTrue);
    await p.a.close();
    await p.b.close();
  });

  test('powtórzony pakiet nie dubluje bajtów', () async {
    net.loss = 0;
    final aStatic = await ChattCrypto.newKeyPair();
    final bStatic = await ChattCrypto.newKeyPair();
    final aPub = await ChattCrypto.publicKeyOf(aStatic);
    final bPub = await ChattCrypto.publicKeyOf(bStatic);
    final muxA = net.create('10.0.0.1', 5000);
    final muxB = net.create('10.0.0.2', 5000);

    final a = SecureUdpPipe(
        mux: muxA, myStatic: aStatic, myStaticPub: aPub, theirStatic: bPub,
        myGuid: 'A', remoteAddress: InternetAddress('10.0.0.2'), remotePort: 5000,
        initiator: true);
    final b = SecureUdpPipe(
        mux: muxB, myStatic: bStatic, myStaticPub: bPub, theirStatic: aPub,
        myGuid: 'B', remoteAddress: InternetAddress('10.0.0.1'), remotePort: 5000,
        initiator: false);

    // Każdy pakiet do B jest doręczany dwa razy: replay nie ma prawa
    // przełożyć się na zdublowane bajty u odbiorcy.
    final gotB = <int>[];
    b.input.listen(gotB.addAll);
    muxA.register((p) { a.handlePacket(p); return true; });
    muxB.register((p) {
      final hello = parseHello(p.data);
      if (hello != null) {
        b.acceptHello(hello.ephemeral);
      } else {
        b.handlePacket(p);
        b.handlePacket(UdpPacket(Uint8List.fromList(p.data), p.address, p.port));
      }
      return true;
    });
    await a.connect();
    await b.ready;
    a.add(utf8Bytes('dokladnie raz'));
    await _settle();
    expect(String.fromCharCodes(gotB), 'dokladnie raz');
    await a.close();
    await b.close();
  });

  test('napastnik z innym kluczem statycznym nie postawi łącza', () async {
    final aStatic = await ChattCrypto.newKeyPair();
    final bStatic = await ChattCrypto.newKeyPair();
    final obcy = await ChattCrypto.newKeyPair(); // nie ten, kogo A oczekuje
    final aPub = await ChattCrypto.publicKeyOf(aStatic);
    final bPub = await ChattCrypto.publicKeyOf(bStatic);
    final obcyPub = await ChattCrypto.publicKeyOf(obcy);
    final muxA = net.create('10.0.0.1', 5000);
    final muxB = net.create('10.0.0.2', 5000);

    // A oczekuje B (bPub), ale po drugiej stronie odpowiada obcy (obcy klucz).
    final a = SecureUdpPipe(
        mux: muxA, myStatic: aStatic, myStaticPub: aPub, theirStatic: bPub,
        myGuid: 'A', remoteAddress: InternetAddress('10.0.0.2'), remotePort: 5000,
        initiator: true);
    final zly = SecureUdpPipe(
        mux: muxB, myStatic: obcy, myStaticPub: obcyPub, theirStatic: aPub,
        myGuid: 'X', remoteAddress: InternetAddress('10.0.0.1'), remotePort: 5000,
        initiator: false);

    final gotA = <int>[];
    a.input.listen(gotA.addAll);
    muxA.register((p) { a.handlePacket(p); return true; });
    muxB.register((p) {
      final hello = parseHello(p.data);
      if (hello != null) {
        zly.acceptHello(hello.ephemeral);
      } else {
        zly.handlePacket(p);
      }
      return true;
    });

    // Klucze się różnią, więc żaden pakiet obcego się u A nie odszyfruje.
    // A nigdy nie przejdzie w „stoi" (czeka na pakiet, który się odszyfruje),
    // więc connect() nie kończy się sukcesem i nie czekamy na nie.
    unawaited(a.connect());
    zly.add(utf8Bytes('cokolwiek'));
    await _settle();
    expect(a.state, isNot(LinkState.up),
        reason: 'bez wspólnego klucza łącze nie ma prawa stanąć');
    expect(gotA, isEmpty, reason: 'pakiet obcego nie powinien się odszyfrować');
    await a.close();
    await zly.close();
  });

  test('zgubiony segment idzie od razu, gdy doszły późniejsze, bez czekania '
      'na RTO i bez powtarzania tego, co doszło', () async {
    net.latency = const Duration(milliseconds: 5);
    final p = await parka();
    // Ginie trzeci pakiet danych od A (pełny segment, dłuższy niż 100 B);
    // potwierdzenia i krótkie pakiety przechodzą.
    var duze = 0;
    net.filter = (data, from, to) {
      if (from.address != '10.0.0.1' || data.length < 100) return true;
      duze++;
      return duze != 3;
    };
    final dane = List<int>.generate(40 * kSegmentPayload, (i) => i % 251);
    p.a.add(dane);
    await _czekajNa(() => p.gotB.length >= dane.length);

    expect(p.gotB, dane);
    expect(p.a.segmentsSent, 40);
    // Jedno ponowienie, wywołane luką w mapie SACK, zanim RTO (co najmniej
    // 200 ms) zdążyło upłynąć; segmenty za luką nie poszły drugi raz.
    expect(p.a.fastRetransmits, 1);
    expect(p.a.timeoutRetransmits, 0);
    expect(duze, 41);
    await p.a.close();
    await p.b.close();
  });

  test('mapa SACK sięga za całe okno: przy luce na początku nic, co doszło, '
      'nie idzie drugi raz', () async {
    net.latency = const Duration(milliseconds: 5);
    final p = await parka();
    // Ginie pierwszy pakiet danych, a za nim leci całe okno.
    var duze = 0;
    net.filter = (data, from, to) {
      if (from.address != '10.0.0.1' || data.length < 100) return true;
      duze++;
      return duze != 1;
    };
    final dane =
        List<int>.generate(kSendWindow * kSegmentPayload, (i) => i % 241);
    p.a.add(dane);
    await _czekajNa(() => p.gotB.length >= dane.length);

    expect(p.gotB, dane);
    expect(p.a.fastRetransmits + p.a.timeoutRetransmits, 1);
    expect(duze, kSendWindow + 1);
    await p.a.close();
    await p.b.close();
  });

  test('przy stracie co setnego pakietu nadawca ponawia tylko zgubione '
      'i nie czeka na RTO', () async {
    // Przed zmianą każda strata zatrzymywała łącze na RTO, a potem szło
    // drugi raz wszystko, co czekało na potwierdzenie: przy 1% strat co
    // trzeci segment szedł dwa razy.
    net.latency = const Duration(milliseconds: 5);
    final p = await parka();
    var duze = 0;
    var zgubione = 0;
    net.filter = (data, from, to) {
      if (from.address != '10.0.0.1' || data.length < 100) return true;
      duze++;
      if (duze % 100 != 0) return true;
      zgubione++;
      return false;
    };
    final dane = List<int>.generate(512 * kSegmentPayload, (i) => i % 239);
    for (var i = 0; i < dane.length; i += 16384) {
      p.a.add(dane.sublist(i, i + 16384));
      await p.a.flush();
    }
    await _czekajNa(() => p.gotB.length >= dane.length,
        limit: const Duration(seconds: 20));

    expect(p.gotB, dane);
    expect(zgubione, 5);
    expect(p.a.fastRetransmits, zgubione);
    expect(p.a.timeoutRetransmits, 0);
    await p.a.close();
    await p.b.close();
  });
}

List<int> utf8Bytes(String s) => s.codeUnits;

/// Czeka, aż [warunek] będzie prawdziwy, najwyżej [limit].
Future<void> _czekajNa(bool Function() warunek,
    {Duration limit = const Duration(seconds: 5)}) async {
  final koniec = DateTime.now().add(limit);
  while (!warunek()) {
    if (DateTime.now().isAfter(koniec)) {
      fail('warunek nie spełnił się w ${limit.inMilliseconds} ms');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Przepuszcza mikrozadania i timery, aż ruch ucichnie.
Future<void> _settle({int rounds = 200}) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
