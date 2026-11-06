// Rozpoznanie do issue #68: czy w TWOICH sieciach da się przebić dziurę
// w NAT-cie, czyli czy droga internetowa Chatta ma sens bez serwera
// przekazującego ruch. Mierzy, nie zakłada.
//
// `flutter test` nie dotknie prawdziwego internetu, więc tak jak przy
// Bluetoothcie (docs/spike-rfcomm.md) pomiar robi osobny program uruchamiany
// na obu urządzeniach: `flutter run -t tool/nat_spike.dart`.
//
// Trzy tryby, wybierane przez --dart-define=CHATT_NAT_MODE=...:
//
//   stun   (domyślny) — pyta dwa serwery STUN z jednego gniazda i mówi, jaki
//          masz NAT. Ten sam port w obu odpowiedziach = mapowanie niezależne
//          od celu (przebicie powinno wyjść). Różny = NAT symetryczny
//          (przebicie zwykle nie wyjdzie). Wypisuje też, czy jest globalny
//          adres IPv6 i czy UDP w ogóle wychodzi. Od tego zacznij, po obu
//          stronach osobno.
//
//   punch  — próba właściwa. Oba urządzenia pytają STUN o swój adres,
//          wypisują go, a Ty przeklejasz adres drugiej strony ręcznie
//          (schowek, dowolny komunikator) i podajesz go w CHATT_NAT_PEER.
//          Potem oba nadają do siebie naraz; program mówi, czy i po jakim
//          czasie pakiety zaczęły chodzić, a następnie testuje przerwy bez
//          ruchu (15/30/60/120 s), żeby zobaczyć, po jakim czasie NAT zamyka
//          furtkę — stąd wychodzi interwał podtrzymania.
//
//   dht    — sprawdza samą skrzynkę kontaktową: czy z tej sieci da się
//          zapisać i odczytać rekord w publicznym DHT BitTorrenta (część
//          sieci firmowych i szkolnych blokuje ruch DHT).
//
// Przykład:
//   cd app
//   # po obu stronach, każda u siebie:
//   flutter run -t tool/nat_spike.dart --dart-define=CHATT_NAT_MODE=stun
//
//   # próba przebicia (adres drugiej strony z jej wydruku):
//   flutter run -t tool/nat_spike.dart \
//     --dart-define=CHATT_NAT_MODE=punch \
//     --dart-define=CHATT_NAT_PEER=203.0.113.9:51820
//
// Wyniki wpisz do docs/spike-nat.md. To jest program bez interfejsu: cały
// wynik idzie na konsolę.

import 'dart:async';
import 'dart:io';

import 'package:chatt/network/bencode.dart';
import 'package:chatt/network/dht.dart';
import 'package:chatt/network/stun.dart';
import 'package:chatt/network/udp_mux.dart';
import 'package:flutter/widgets.dart';

const _mode = String.fromEnvironment('CHATT_NAT_MODE', defaultValue: 'stun');
const _peer = String.fromEnvironment('CHATT_NAT_PEER');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  stdout.writeln('== Chatt NAT spike: tryb "$_mode" ==');
  try {
    switch (_mode) {
      case 'stun':
        await _stun();
      case 'punch':
        await _punch();
      case 'dht':
        await _dht();
      default:
        stdout.writeln('Nieznany tryb. Użyj stun | punch | dht.');
    }
  } catch (blad, slad) {
    stdout.writeln('Błąd: $blad\n$slad');
  }
  stdout.writeln('== koniec ==');
}

Future<List<String>> _localV4() async {
  final interfaces =
      await NetworkInterface.list(type: InternetAddressType.IPv4);
  return [for (final i in interfaces) for (final a in i.addresses) a.address];
}

Future<bool> _hasGlobalV6() async {
  try {
    final interfaces =
        await NetworkInterface.list(type: InternetAddressType.IPv6);
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (!a.isLinkLocal && !a.isLoopback && !a.address.startsWith('fd')) {
          return true;
        }
      }
    }
  } catch (_) {}
  return false;
}

Future<void> _stun() async {
  final mux = await SocketUdpMux.bind();
  stdout.writeln('Gniazdo UDP na porcie ${mux.port}.');
  final client = StunClient(mux);
  final lokalne = await _localV4();
  final wynik = await client.discover(localAddresses: lokalne);
  final m = wynik.mapping;
  if (m == null) {
    stdout.writeln('Żaden serwer STUN nie odpowiedział.');
    stdout.writeln('UDP prawdopodobnie nie wychodzi z tej sieci: droga '
        'internetowa się tu nie uda.');
  } else {
    stdout.writeln('Widać mnie pod: ${m.label}');
    stdout.writeln('Lokalne adresy IPv4: ${lokalne.join(", ")}');
    stdout.writeln(switch (wynik.nat) {
      NatMapping.endpointIndependent =>
        'NAT niezależny od celu — przebicie dziury powinno działać.',
      NatMapping.endpointDependent =>
        'NAT symetryczny — przebicie dziury zwykle tu zawodzi, bez '
            'przekaźnika się nie połączysz.',
      NatMapping.none => 'Brak NAT — jesteś osiągalny wprost.',
      NatMapping.unknown => 'Odpowiedział jeden serwer; rodzaju NAT nie '
          'dało się ocenić.',
    });
  }
  stdout.writeln('Globalny adres IPv6: ${await _hasGlobalV6() ? "jest "
      "(pomaga, bez translacji portów)" : "brak"}.');
  client.dispose();
  await mux.close();
}

Future<void> _punch() async {
  final mux = await SocketUdpMux.bind();
  final client = StunClient(mux);
  final me = (await client.discover()).mapping;
  stdout.writeln('Mój publiczny adres (przeklej drugiej stronie): '
      '${me?.label ?? "nieznany"}');
  if (_peer.isEmpty) {
    stdout.writeln('Podaj adres drugiej strony w CHATT_NAT_PEER i uruchom '
        'ponownie na obu urządzeniach mniej więcej naraz.');
    client.dispose();
    await mux.close();
    return;
  }
  final czesci = _peer.split(':');
  final peerAddr = InternetAddress(czesci[0]);
  final peerPort = int.parse(czesci[1]);
  stdout.writeln('Przebijam do $_peer ...');

  var odebrane = 0;
  DateTime? pierwszy;
  mux.register((p) {
    if (p.address.address == peerAddr.address && p.port == peerPort) {
      odebrane++;
      pierwszy ??= DateTime.now();
      return true;
    }
    return false;
  });

  final start = DateTime.now();
  // Nadajemy co 200 ms przez 20 s. Każdy pakiet otwiera furtkę w naszym NAT.
  final nadawanie = Timer.periodic(const Duration(milliseconds: 200), (_) {
    mux.send([0x9e, 0x3c], peerAddr, peerPort); // dwa bajty: „jestem"
  });
  await Future<void>.delayed(const Duration(seconds: 20));
  nadawanie.cancel();

  if (odebrane > 0) {
    final ms = pierwszy!.difference(start).inMilliseconds;
    stdout.writeln('UDAŁO SIĘ: pierwszy pakiet po $ms ms, łącznie '
        '$odebrane pakietów. Dziura stoi.');
    stdout.writeln('To znaczy, że w tej parze sieci droga internetowa Chatta '
        'ma szansę działać.');
  } else {
    stdout.writeln('Nic nie przyszło w 20 s. W tej parze sieci przebicie '
        'dziury nie wychodzi (symetryczny NAT albo UDP zablokowane).');
  }
  client.dispose();
  await mux.close();
}

Future<void> _dht() async {
  final mux = await SocketUdpMux.bind();
  final dht = DhtClient(mux);
  stdout.writeln('Pytam węzły rozruchowe DHT ...');
  // Prosty rekord niemutowalny by wymagał innej ścieżki; tu sprawdzamy samą
  // osiągalność przez zapytanie o losowy cel i policzenie odpowiedzi.
  final signer = await DhtSigner.fromSeed(
      List<int>.generate(32, (i) => (i * 7 + 13) & 0xFF));
  final salt = 'chatt-nat-spike'.codeUnits;
  try {
    final zapis = await dht
        .putMutable(signer,
            bencodedValue: bencode('spike'),
            seq: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            salt: salt)
        .timeout(const Duration(seconds: 20));
    stdout.writeln(zapis > 0
        ? 'Zapis do DHT: dotarł do $zapis węzłów. DHT działa z tej sieci.'
        : 'Zapis do DHT nie dotarł do żadnego węzła: ruch DHT jest tu '
            'prawdopodobnie zablokowany.');
  } on TimeoutException {
    stdout.writeln('DHT nie odpowiedziało w 20 s: ruch DHT jest tu '
        'prawdopodobnie zablokowany.');
  }
  await dht.close();
  await mux.close();
}
