// ignore_for_file: avoid_print

// Pomiar do issue #68: czy w Twoich sieciach da się przebić dziurę w NAT-cie
// bez serwera przekazującego ruch. Od wyniku zależy, czy droga internetowa
// Chatta ma sens.
//
// `flutter test` nie dotyka prawdziwego internetu, więc pomiar robi osobny
// program uruchamiany na obu urządzeniach, tak jak przy Bluetoothcie
// (docs/spike-rfcomm.md). Program nie ma interfejsu: wynik idzie na konsolę,
// na telefonie do konsoli `flutter run` i do `adb logcat -s flutter`.
//
// Uruchomienie:
//
//   cd app
//   # komputer: wystarczy sama maszyna wirtualna Darta
//   dart run -DCHATT_NAT_MODE=stun tool/nat_spike.dart
//
//   # telefon: pomiar instaluje się obok Chatta pod osobnym identyfikatorem
//   # i nie rusza danych prawdziwej aplikacji
//   flutter run -d <telefon> -t tool/nat_spike.dart -P chattAppIdSuffix=.natspike \
//     --dart-define=CHATT_NAT_MODE=stun
//
// Tryby (CHATT_NAT_MODE):
//
//   stun   (domyślny) pyta dwa serwery STUN z jednego gniazda. Ten sam port
//          w obu odpowiedziach znaczy, że NAT nadaje mapowanie niezależne od
//          celu i przebicie powinno wyjść. Różne porty to NAT symetryczny,
//          przy którym przebicie zwykle zawodzi. Do tego: czy UDP w ogóle
//          wychodzi i czy jest globalny adres IPv6.
//
//   dht    zapis i odczyt rekordu w publicznym DHT BitTorrenta, z czasami.
//          Część sieci firmowych i szkolnych blokuje ruch DHT.
//
//   punch  próba właściwa na dwóch urządzeniach naraz: CHATT_NAT_ROLE=a po
//          jednej stronie, b po drugiej. Każda próba to świeże gniazdo, STUN,
//          wymiana adresów i nadawanie w obie strony co 200 ms przez najwyżej
//          30 s. Po pierwszej udanej próbie strona `a` sprawdza, po ilu
//          sekundach ciszy jej pakiet jeszcze dochodzi do `b` (CHATT_NAT_GAPS).
//          Stąd interwał podtrzymania. Żeby zmierzyć drugi kierunek, zamień
//          role.
//
//   link   droga internetowa aplikacji w całości: ten sam InetLinkManager
//          i InternetTransport, z tożsamościami wyprowadzonymi ze słowa
//          CHATT_NAT_PAIR, bez bazy i bez danych Chatta. Strona `b` tylko
//          czeka: wpisuje adres do skrzynki, czyta skrzynkę `a` i puka.
//          Strona `a` dzwoni CHATT_NAT_CALLS razy, za każdym razem od zimnego
//          startu (nowe gniazdo), mierzy czas do odpowiedzi, a przy pierwszej
//          rozmowie wysyła CHATT_NAT_BYTES bajtów i mierzy przepustowość.
//
// Wymiana adresów w trybie punch:
//
//   CHATT_NAT_PAIR=<słowo>  to samo słowo po obu stronach. Adresy idą przez
//          skrzynkę kontaktową w DHT (ten sam kod co w aplikacji, klucze
//          wyprowadzone ze słowa), więc nic nie trzeba przeklejać.
//   bez słowa  każda strona wypisuje swój adres i czeka na adres drugiej
//          w pliku, którego ścieżkę podaje (na telefonie zapis przez
//          `adb shell run-as`), a na komputerze także na wejściu: wklej
//          i Enter. Jedna próba.
//
// Pozostałe pokrętła:
//
//   CHATT_NAT_TRIES  liczba prób w trybie ze słowem, domyślnie 3
//   CHATT_NAT_GAPS   długości ciszy w sekundach, domyślnie 15,30,60,120;
//                    pusty napis pomija ten test
//   CHATT_NAT_PORT   stały port lokalny, domyślnie dowolny wolny
//   CHATT_NAT_LOCAL  true: bez STUN-u, adres 127.0.0.1; sprawdzenie samego
//                    narzędzia na jednym komputerze
//   CHATT_NAT_LISTEN true: ta strona nic nie wysyła, dopóki czegoś nie
//                    dostanie. Gdy pakiet drugiej strony mimo to dojdzie,
//                    NAT tej strony wpuszcza ruch od nieznanego nadawcy
//                    i odbiorca nie musi nadawać pierwszy
//   CHATT_NAT_WATCH  link: co ile sekund `b` czyta skrzynkę, domyślnie 60
//                    jak w aplikacji
//   CHATT_NAT_CALLS  link: ile razy `a` dzwoni, domyślnie 3
//   CHATT_NAT_BYTES  link: bajtów w próbie przepustowości, domyślnie 262144
//   CHATT_NAT_FOR    link: ile minut `b` czeka najwyżej, domyślnie 15
//   CHATT_NAT_PINGS  punch: po zestawieniu `a` wysyła tyle pakietów co 100 ms
//                    i mierzy czas obiegu (wysłanie, echo, powrót); 0 pomija
//   CHATT_NAT_LAN    punch: true bierze adres w sieci lokalnej, bez STUN-u,
//                    do porównania czasu obiegu w jednym Wi-Fi
//
// Na komputerze te same klucze można podać jako zmienne środowiska, co
// przydaje się przy zbudowanym programie (`flutter build windows -t
// tool/nat_spike.dart`, potrzebnym w trybie link). CHATT_NAT_LOG=<plik>
// dopisuje wydruk także do pliku.
//
// Na telefonie te same klucze można podać bez przebudowy, w pliku
// chatt_nat.conf w katalogu tymczasowym aplikacji (ścieżka w wydruku),
// po jednym KLUCZ=wartość w linii; plik wygrywa z --dart-define:
//
//   adb shell "run-as com.mysttic.chatt.natspike sh -c \
//     'printf \"CHATT_NAT_MODE=dht\n\" > code_cache/chatt_nat.conf'"
//   adb shell am force-stop com.mysttic.chatt.natspike
//   adb shell am start -n com.mysttic.chatt.natspike/com.mysttic.chatt.MainActivity
//
// Wyniki trafiają do docs/spike-nat.md, bez adresów IP.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:chatt/core/crypto.dart';
import 'package:chatt/network/bencode.dart';
import 'package:chatt/network/bt_link.dart';
import 'package:chatt/network/dht.dart';
import 'package:chatt/network/inet_link.dart';
import 'package:chatt/network/inet_transport.dart';
import 'package:chatt/network/rendezvous.dart';
import 'package:chatt/network/stun.dart';
import 'package:chatt/network/transport.dart';
import 'package:chatt/network/udp_mux.dart';
import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';

/// Ustawienia z --dart-define (albo `dart run -D`). Na telefonie nadpisuje je
/// plik chatt_nat.conf, patrz [_wczytajPlik].
final _ust = <String, String>{
  'CHATT_NAT_MODE':
      const String.fromEnvironment('CHATT_NAT_MODE', defaultValue: 'stun'),
  'CHATT_NAT_ROLE': const String.fromEnvironment('CHATT_NAT_ROLE'),
  'CHATT_NAT_PAIR': const String.fromEnvironment('CHATT_NAT_PAIR'),
  'CHATT_NAT_TRIES':
      const String.fromEnvironment('CHATT_NAT_TRIES', defaultValue: '3'),
  'CHATT_NAT_GAPS': const String.fromEnvironment('CHATT_NAT_GAPS',
      defaultValue: '15,30,60,120'),
  'CHATT_NAT_PORT':
      const String.fromEnvironment('CHATT_NAT_PORT', defaultValue: '0'),
  'CHATT_NAT_WATCH':
      const String.fromEnvironment('CHATT_NAT_WATCH', defaultValue: '60'),
  'CHATT_NAT_CALLS':
      const String.fromEnvironment('CHATT_NAT_CALLS', defaultValue: '3'),
  'CHATT_NAT_BYTES':
      const String.fromEnvironment('CHATT_NAT_BYTES', defaultValue: '262144'),
  'CHATT_NAT_FOR':
      const String.fromEnvironment('CHATT_NAT_FOR', defaultValue: '15'),
  'CHATT_NAT_PINGS':
      const String.fromEnvironment('CHATT_NAT_PINGS', defaultValue: '0'),
  'CHATT_NAT_LAN':
      const String.fromEnvironment('CHATT_NAT_LAN', defaultValue: 'false'),
  'CHATT_NAT_LISTEN':
      const String.fromEnvironment('CHATT_NAT_LISTEN', defaultValue: 'false'),
  'CHATT_NAT_LOCAL':
      const String.fromEnvironment('CHATT_NAT_LOCAL', defaultValue: 'false'),
};

String get _tryb => _ust['CHATT_NAT_MODE']!;
String get _rola => _ust['CHATT_NAT_ROLE']!;
String get _slowo => _ust['CHATT_NAT_PAIR']!;
int get _ileProb => int.tryParse(_ust['CHATT_NAT_TRIES']!) ?? 3;
int get _stalyPort => int.tryParse(_ust['CHATT_NAT_PORT']!) ?? 0;
bool get _lokalnie => _ust['CHATT_NAT_LOCAL'] == 'true';
bool get _tylkoSlucha => _ust['CHATT_NAT_LISTEN'] == 'true';
bool get _wSieciLokalnej => _ust['CHATT_NAT_LAN'] == 'true';
int get _pingi => int.tryParse(_ust['CHATT_NAT_PINGS']!) ?? 0;

/// Adres tego urządzenia w sieci lokalnej: najpierw 192.168/16, potem 10/8,
/// potem 172.16/12 (bez wirtualnych kart, które zwykle siedzą wyżej).
Future<InternetAddress?> _adresWSieci() async {
  final adresy = [
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
      for (final a in i.addresses) a,
  ];
  int ranga(InternetAddress a) {
    final b = a.rawAddress;
    if (b[0] == 192 && b[1] == 168) return 0;
    if (b[0] == 10) return 1;
    if (b[0] == 172 && b[1] >= 16 && b[1] < 32) return 2;
    return 9;
  }

  adresy.sort((x, y) => ranga(x).compareTo(ranga(y)));
  return adresy.isEmpty || ranga(adresy.first) == 9 ? null : adresy.first;
}
int _liczba(String klucz, int domyslna) =>
    int.tryParse(_ust[klucz]!) ?? domyslna;

List<int> get _przerwy => [
      for (final s in _ust['CHATT_NAT_GAPS']!.split(','))
        if (int.tryParse(s.trim()) case final n? when n > 0) n,
    ];

/// Okno nadawania jednej próby.
const _oknoPrzebicia = Duration(seconds: 30);

/// `print`, bo na Androidzie `stdout` nie dociera do konsoli `flutter run`,
/// a `print` trafia tam i do logcatu. Na komputerze z CHATT_NAT_LOG także do
/// pliku: zbudowany program okienkowy nie zawsze ma konsolę.
void wypisz(String linia) {
  print(linia);
  final log = Platform.isAndroid ? null : Platform.environment['CHATT_NAT_LOG'];
  if (log != null && log.isNotEmpty) {
    File(log).writeAsStringSync('$linia\n',
        mode: FileMode.append, flush: true);
  }
}

/// Start procesu. Ustawiany w [main]: zmienna globalna z inicjalizatorem
/// powstaje dopiero przy pierwszym użyciu.
late final DateTime _start;

String _wTemp(String nazwa) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}$nazwa';

/// Na komputerze: zmienne środowiska. Na telefonie: KLUCZ=wartość z pliku
/// chatt_nat.conf, żeby zmiana trybu nie wymagała przebudowy aplikacji.
void _wczytajPlik() {
  if (!Platform.isAndroid) {
    for (final klucz in _ust.keys.toList()) {
      final wartosc = Platform.environment[klucz];
      if (wartosc != null) _ust[klucz] = wartosc;
    }
    return;
  }
  final plik = File(_wTemp('chatt_nat.conf'));
  if (!plik.existsSync()) {
    wypisz('Bez pliku ${plik.path}, ustawienia z budowania.');
    return;
  }
  for (final linia in plik.readAsLinesSync()) {
    final i = linia.indexOf('=');
    if (i <= 0) continue;
    final klucz = linia.substring(0, i).trim();
    if (_ust.containsKey(klucz)) _ust[klucz] = linia.substring(i + 1).trim();
  }
  wypisz('Ustawienia z ${plik.path}.');
}

Future<void> main() async {
  _start = DateTime.now();
  _wczytajPlik();
  wypisz('== Chatt NAT spike: tryb "$_tryb"'
      '${_rola.isEmpty ? '' : ', rola $_rola'} ==');
  try {
    switch (_tryb) {
      case 'stun':
        await _stun();
      case 'dht':
        await _dht();
      case 'punch':
        await _punch();
      case 'link':
        await _link();
      default:
        wypisz('Nieznany tryb. Użyj stun, dht, punch albo link.');
    }
  } catch (blad, slad) {
    wypisz('Błąd: $blad\n$slad');
  }
  wypisz('== koniec ==');
  // Na telefonie aplikacja zostaje, żeby `flutter run` dowiózł ostatnie
  // linie. Na komputerze proces kończy się od razu, także gdy czekał na
  // wejście.
  if (!Platform.isAndroid) exit(0);
}

// --- stun ------------------------------------------------------------------

Future<void> _stun() async {
  final mux = await SocketUdpMux.bind(port: _stalyPort);
  final stun = StunClient(mux);
  try {
    final lokalne = await _lokalneV4();
    wypisz('Gniazdo UDP na porcie ${mux.port}. '
        'Adresy lokalne: ${lokalne.join(', ')}.');
    final pierwszy = await stun.query(defaultStunServers[0]);
    final drugi = await stun.query(defaultStunServers[1]);
    wypisz('${defaultStunServers[0].$1}: '
        '${pierwszy?.label ?? 'brak odpowiedzi'}');
    wypisz('${defaultStunServers[1].$1}: '
        '${drugi?.label ?? 'brak odpowiedzi'}');
    final m = pierwszy ?? drugi;
    if (m == null) {
      wypisz('Żaden serwer STUN nie odpowiedział: UDP prawdopodobnie nie '
          'wychodzi z tej sieci i droga internetowa się tu nie uda.');
      return;
    }
    wypisz('NAT: '
        '${_opisNat(classifyNat(pierwszy, drugi, localAddresses: lokalne))}.');
    wypisz(m.port == mux.port
        ? 'Port publiczny równy lokalnemu: NAT zachowuje numery portów.'
        : 'Port publiczny ${m.port}, lokalny ${mux.port}: NAT zmienia '
            'numery portów.');
  } finally {
    stun.dispose();
    await mux.close();
  }
  wypisz('Globalny adres IPv6: ${await _globalnyV6() ? 'jest' : 'brak'}.');
}

String _opisNat(NatMapping nat) => switch (nat) {
      NatMapping.endpointIndependent =>
        'niezależny od celu, przebicie powinno wyjść',
      NatMapping.endpointDependent => 'symetryczny, przebicie zwykle zawodzi',
      NatMapping.none => 'brak, urządzenie ma adres publiczny',
      NatMapping.unknown => 'nieznany, odpowiedział jeden serwer',
    };

Future<List<String>> _lokalneV4() async {
  final interfejsy =
      await NetworkInterface.list(type: InternetAddressType.IPv4);
  return [for (final i in interfejsy) for (final a in i.addresses) a.address];
}

/// Globalny adres IPv6: bez lokalnych łącza, bez prywatnych fc00::/7 i bez
/// tunelu Teredo (2001:0::/32), który na Windowsie udaje adres globalny.
Future<bool> _globalnyV6() async {
  try {
    final interfejsy =
        await NetworkInterface.list(type: InternetAddressType.IPv6);
    for (final i in interfejsy) {
      for (final a in i.addresses) {
        final s = a.address.toLowerCase();
        if (a.isLinkLocal || a.isLoopback) continue;
        if (s.startsWith('fc') || s.startsWith('fd')) continue;
        if (s.startsWith('2001:0:')) continue;
        return true;
      }
    }
  } catch (_) {}
  return false;
}

// --- dht -------------------------------------------------------------------

/// Trzy zapisy do tej samej skrzynki co 20 s, każdy z odczytem, tak jak
/// aplikacja odświeża swój adres. Do tego błędy KRPC od węzłów: 202 i 204
/// to zwykle węzły bez BEP 44, inne kody wskazują problem z zapisem.
Future<void> _dht() async {
  final mux = await SocketUdpMux.bind(port: _stalyPort);
  final bledy = <String, int>{};
  // Przed klientem DHT, więc widzi każdą odpowiedź i oddaje ją dalej.
  mux.register((p) {
    final m = tryBdecode(p.data);
    if (m is Map && bText(m, 'y') == 'e') {
      final e = m['e'];
      final opis = e is List
          ? e.map((x) => x is List<int> ? String.fromCharCodes(x) : '$x')
              .join(' ')
          : '$e';
      bledy[opis] = (bledy[opis] ?? 0) + 1;
    }
    return false;
  });
  final dht = DhtClient(mux);
  try {
    final los = Random.secure();
    final podpis = await DhtSigner.fromSeed(
        List<int>.generate(32, (_) => los.nextInt(256)));
    final sol = utf8.encode('chatt-nat-spike');
    for (var i = 1; i <= 3; i++) {
      if (i > 1) await Future<void>.delayed(const Duration(seconds: 20));
      final seq = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final t0 = DateTime.now();
      final ile = await dht
          .putMutable(podpis,
              bencodedValue: bencode('spike $seq'), seq: seq, salt: sol)
          .timeout(const Duration(seconds: 30), onTimeout: () => -1);
      final t1 = DateTime.now();
      final odczyt = await dht
          .getMutable(podpis.publicKey, salt: sol)
          .timeout(const Duration(seconds: 30), onTimeout: () => null);
      final t2 = DateTime.now();
      final zapis = ile < 0 ? 'nie skończył się w 30 s' : '$ile węzłów';
      final rekord = odczyt == null
          ? 'brak rekordu'
          : odczyt.seq == seq
              ? 'rekord aktualny'
              : 'rekord poprzedni';
      wypisz('Zapis $i: $zapis, ${t1.difference(t0).inMilliseconds} ms. '
          'Odczyt: $rekord, ${t2.difference(t1).inMilliseconds} ms.'
          '${bledy.isEmpty ? '' : ' Błędy węzłów: $bledy.'}');
      bledy.clear();
    }
  } finally {
    await dht.close();
    await mux.close();
  }
}

// --- punch -----------------------------------------------------------------

/// Pakiety próby. Pierwsze dwa bajty „CN" odróżniają je od STUN-u (dwa
/// najstarsze bity zero) i od DHT (słownik bencode zaczyna się od „d").
const _znak0 = 0x43, _znak1 = 0x4E;
const _probe = 0x50; // P: „jestem", z numerem do odesłania
const _echo = 0x45; // E: odpowiedź na P z tym samym numerem
const _cisza = 0x47; // G: `a` zapowiada ciszę: runda, sekundy
const _ciszaOk = 0x67; // g: `b` przyjął zapowiedź
const _koniec = 0x44; // D: `a` kończy próbę
const _koniecOk = 0x64; // d: `b` przyjął koniec

Uint8List _pakiet(int typ, [List<int> dane = const []]) =>
    Uint8List.fromList([_znak0, _znak1, typ, ...dane]);

List<int> _bajty(int n) =>
    [(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];

int _numer(Uint8List d) => (d[3] << 24) | (d[4] << 16) | (d[5] << 8) | d[6];

class _Proba {
  final int numer;
  _Proba(this.numer);

  String nat = '?';
  bool znamAdres = false;

  /// Od startu własnego nadawania do pierwszego pakietu z drugiej strony.
  int? msPierwszy;

  /// Do pierwszego echa, czyli do ruchu w obie strony.
  int? msObie;

  /// Druga strona nadawała z innego portu niż ten z wymiany adresów.
  bool innyPort = false;

  /// (sekundy ciszy, czy pakiet `a` po niej doszedł)
  final cisza = <(int, bool)>[];

  /// Czasy obiegu w milisekundach i ile pakietów nie wróciło.
  final rtt = <double>[];
  var zgubione = 0;
}

Future<void> _punch() async {
  if (_rola != 'a' && _rola != 'b') {
    wypisz('Tryb punch potrzebuje CHATT_NAT_ROLE=a po jednej stronie '
        'i b po drugiej.');
    return;
  }
  final ile = _slowo.isEmpty ? 1 : max(1, _ileProb);
  final wyniki = <_Proba>[];
  var ciszaZrobiona = _przerwy.isEmpty || _rola == 'b';
  for (var k = 1; k <= ile; k++) {
    final proba = await _jednaProba(k, zCisza: !ciszaZrobiona);
    wyniki.add(proba);
    if (proba.cisza.isNotEmpty) ciszaZrobiona = true;
  }
  _podsumuj(wyniki);
}

Future<_Proba> _jednaProba(int k, {required bool zCisza}) async {
  final p = _Proba(k);
  wypisz('--- próba $k ---');
  final mux = await SocketUdpMux.bind(port: _stalyPort);
  final stun = StunClient(mux);
  final dht = DhtClient(mux);
  try {
    final InternetAddress mojIp;
    final int mojPort;
    final wSieci = _wSieciLokalnej ? await _adresWSieci() : null;
    if (_lokalnie) {
      mojIp = InternetAddress.loopbackIPv4;
      mojPort = mux.port;
      p.nat = 'pominięty (CHATT_NAT_LOCAL)';
    } else if (wSieci != null) {
      mojIp = wSieci;
      mojPort = mux.port;
      p.nat = 'pominięty (CHATT_NAT_LAN)';
    } else {
      final wynik = await stun.discover(localAddresses: await _lokalneV4());
      final m = wynik.mapping;
      if (m == null) {
        wypisz('STUN nie odpowiada: UDP nie wychodzi z tej sieci.');
        return p;
      }
      p.nat = _opisNat(wynik.nat);
      mojIp = m.address;
      mojPort = m.port;
      wypisz('Mój adres publiczny: ${m.label} (port lokalny ${mux.port}), '
          'NAT ${p.nat}.');
    }
    final cel = _slowo.isNotEmpty
        ? await _adresZeSkrzynki(dht, k, mojIp, mojPort)
        : await _adresRecznie(mojIp, mojPort);
    if (cel == null) {
      wypisz('Brak adresu drugiej strony, próba przepada.');
      return p;
    }
    p.znamAdres = true;
    if (!_lokalnie && cel.$1.address == mojIp.address) {
      wypisz('Druga strona ma ten sam adres publiczny, czyli stoi za tym '
          'samym NAT-em. Przebicie wyjdzie tylko wtedy, gdy router zawraca '
          'ruch do własnych adresów (hairpin). W jednej sieci Chatt i tak '
          'łączy się wprost.');
    }
    await _przebij(mux, p, cel.$1, cel.$2, zCisza: zCisza);
  } finally {
    stun.dispose();
    await dht.close();
    await mux.close();
  }
  return p;
}

List<int> _zeSlowa(String cel) =>
    digest.sha256.convert(utf8.encode('chatt-nat-spike|$cel|$_slowo')).bytes;

/// Wymiana adresów przez skrzynkę kontaktową w DHT. Każda próba ma własną
/// parę skrzynek (numer próby w guidzie), więc rekord z poprzedniej próby
/// nie myli następnej.
Future<(InternetAddress, int)?> _adresZeSkrzynki(
    DhtClient dht, int k, InternetAddress ip, int port) async {
  final druga = _rola == 'a' ? 'b' : 'a';
  final skrzynka = Rendezvous(
    signSeed: _zeSlowa('sign'),
    sealKey: _zeSlowa('seal'),
    saltBase: _zeSlowa('salt'),
    myGuid: '$_rola#$k',
    theirGuid: '$druga#$k',
  );
  final start = DateTime.now();
  DateTime? zapisano;
  var ostatnio = 0;
  Future<void> zapisz() async {
    final t0 = DateTime.now();
    ostatnio = await skrzynka
        .publish(dht, address: ip, port: port)
        .catchError((Object _) => 0);
    zapisano = DateTime.now();
    wypisz('Zapis do skrzynki: $ostatnio węzłów, '
        '${zapisano!.difference(t0).inMilliseconds} ms.');
  }

  while (DateTime.now().difference(start) < const Duration(minutes: 3)) {
    // Zapis co 30 s, żeby rekord miał świeży znacznik czasu, i od razu
    // ponownie, gdy poprzedni nie trafił do żadnego węzła.
    final ostatni = zapisano;
    if (ostatni == null ||
        ostatnio == 0 ||
        DateTime.now().difference(ostatni) > const Duration(seconds: 30)) {
      await zapisz();
    }
    final t0 = DateTime.now();
    final adres =
        await skrzynka.lookup(dht).catchError((Object _) => null);
    final ms = DateTime.now().difference(t0).inMilliseconds;
    // Rekord sprzed startu tego procesu to ślad poprzedniego pomiaru z tym
    // samym słowem. Minuta zapasu na różnicę zegarów.
    if (adres != null &&
        adres.timestamp > _start.millisecondsSinceEpoch - 60000) {
      final wiek =
          (DateTime.now().millisecondsSinceEpoch - adres.timestamp) ~/ 1000;
      wypisz('Adres drugiej strony ze skrzynki: '
          '${adres.address.address}:${adres.port} '
          '(odczyt $ms ms, rekord sprzed $wiek s).');
      // Druga strona znajdzie nas tylko po rekordzie, więc nieudany zapis
      // trzeba powtórzyć przed nadawaniem.
      for (var i = 0; i < 3 && ostatnio == 0; i++) {
        await zapisz();
      }
      return (adres.address, adres.port);
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  wypisz('Druga strona nie pojawiła się w skrzynce przez 3 minuty.');
  return null;
}

/// Wymiana ręczna: adres drugiej strony z pliku albo z wejścia.
Future<(InternetAddress, int)?> _adresRecznie(
    InternetAddress ip, int port) async {
  final plik = File(_wTemp('chatt_nat_peer_$_rola.txt'));
  if (plik.existsSync()) plik.deleteSync();
  wypisz('Mój adres (przekaż drugiej stronie): ${ip.address}:$port');
  wypisz('Czekam na adres drugiej strony w pliku ${plik.path}'
      '${Platform.isAndroid ? '' : ' albo na wejściu (wklej i Enter)'}.');
  final wynik = Completer<(InternetAddress, int)?>();
  StreamSubscription<String>? wejscie;
  if (!Platform.isAndroid) {
    // Zbudowany program okienkowy może nie mieć wejścia: wtedy zostaje plik.
    try {
      wejscie = stdin
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((linia) {
        final a = _adres(linia);
        if (a != null && !wynik.isCompleted) wynik.complete(a);
      }, onError: (Object _) {});
    } catch (_) {}
  }
  final zegar = Timer.periodic(const Duration(milliseconds: 300), (_) {
    if (wynik.isCompleted || !plik.existsSync()) return;
    final a = _adres(plik.readAsStringSync());
    if (a != null) wynik.complete(a);
  });
  final a = await wynik.future
      .timeout(const Duration(minutes: 10), onTimeout: () => null);
  zegar.cancel();
  await wejscie?.cancel();
  return a;
}

(InternetAddress, int)? _adres(String napis) {
  final s = napis.trim();
  final i = s.lastIndexOf(':');
  if (i <= 0) return null;
  final ip = InternetAddress.tryParse(s.substring(0, i));
  final port = int.tryParse(s.substring(i + 1));
  if (ip == null || port == null || port <= 0 || port > 65535) return null;
  return (ip, port);
}

/// Nadawanie w obie strony i, po stronie `a`, test ciszy. Strona `b` tylko
/// odpowiada i wykonuje polecenia `a`.
Future<void> _przebij(UdpMux mux, _Proba p, InternetAddress ip, int port,
    {required bool zCisza}) async {
  var celPort = port;
  final start = DateTime.now();
  int ms() => DateTime.now().difference(start).inMilliseconds;
  final los = Random();
  final zegarRtt = Stopwatch()..start();
  final wyslanePingi = <int, int>{};

  // Strona tylko słuchająca odzywa się dopiero echem na cudzy pakiet.
  var nadaje = !_tylkoSlucha;
  var ostatnio = DateTime.now();
  var zapowiedzianaCisza = 0;
  var ostatniaRunda = 0;
  final koniecB = Completer<void>();
  Completer<void>? echo;
  int? echoNumer;
  Completer<void>? potwierdzenie;
  int? czekamNa;
  var runda = 0;

  void domknij(Completer<void>? c) {
    if (c != null && !c.isCompleted) c.complete();
  }

  bool obsluz(UdpPacket pk) {
    final d = pk.data;
    if (d.length < 3 || d[0] != _znak0 || d[1] != _znak1) return false;
    if (pk.address.address != ip.address) return true;
    if (pk.port != celPort) {
      wypisz('Druga strona nadaje z portu ${pk.port}, w wymianie był '
          '$celPort: jej NAT dał temu połączeniu osobny port. Odpowiadam '
          'na nowy.');
      p.innyPort = true;
      celPort = pk.port;
    }
    ostatnio = DateTime.now();
    if (p.msPierwszy == null) {
      p.msPierwszy = ms();
      wypisz('Pierwszy pakiet od drugiej strony po ${p.msPierwszy} ms.');
    }
    switch (d[2]) {
      case _probe:
        mux.send(_pakiet(_echo, d.sublist(3)), ip, celPort);
      case _echo:
        if (p.msObie == null) {
          p.msObie = ms();
          wypisz('Ruch w obie strony po ${p.msObie} ms.');
        }
        nadaje = false;
        if (d.length >= 7) {
          final wyslano = wyslanePingi.remove(_numer(d));
          if (wyslano != null) {
            p.rtt.add((zegarRtt.elapsedMicroseconds - wyslano) / 1000);
          }
        }
        if (echoNumer != null && d.length >= 7 && _numer(d) == echoNumer) {
          domknij(echo);
        }
      case _cisza:
        nadaje = false;
        if (d.length >= 6) {
          zapowiedzianaCisza = (d[4] << 8) | d[5];
          if (d[3] != ostatniaRunda) {
            ostatniaRunda = d[3];
            wypisz('Druga strona zapowiada ciszę: $zapowiedzianaCisza s.');
          }
          mux.send(_pakiet(_ciszaOk, [d[3]]), ip, celPort);
        }
      case _ciszaOk:
        if (czekamNa == _ciszaOk && d.length > 3 && d[3] == runda) {
          domknij(potwierdzenie);
        }
      case _koniec:
        nadaje = false;
        mux.send(_pakiet(_koniecOk), ip, celPort);
        domknij(koniecB);
      case _koniecOk:
        if (czekamNa == _koniecOk) domknij(potwierdzenie);
    }
    return true;
  }

  /// Wysyła co 300 ms, aż przyjdzie potwierdzenie danego typu (do 5 s).
  Future<bool> zPotwierdzeniem(Uint8List pakiet, int typOk) async {
    final c = potwierdzenie = Completer<void>();
    czekamNa = typOk;
    final zegar = Timer.periodic(const Duration(milliseconds: 300),
        (_) => mux.send(pakiet, ip, celPort));
    mux.send(pakiet, ip, celPort);
    try {
      await c.future.timeout(const Duration(seconds: 5));
      return true;
    } on TimeoutException {
      return false;
    } finally {
      zegar.cancel();
      czekamNa = null;
    }
  }

  final numerStartu = los.nextInt(1 << 30);
  var licznik = 0;
  final nadawanie = Timer.periodic(const Duration(milliseconds: 200), (_) {
    if (nadaje && ms() < _oknoPrzebicia.inMilliseconds) {
      mux.send(_pakiet(_probe, _bajty(numerStartu + ++licznik)), ip, celPort);
    }
  });
  mux.register(obsluz);
  if (nadaje) {
    wypisz('Nadaję do ${ip.address}:$port co 200 ms ...');
    mux.send(_pakiet(_probe, _bajty(numerStartu)), ip, celPort);
  } else {
    wypisz('Tylko słucham: nic nie wysyłam, dopóki ${ip.address}:$port '
        'się nie odezwie.');
  }

  try {
    if (_rola == 'a') {
      while (p.msObie == null && ms() < _oknoPrzebicia.inMilliseconds) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (p.msObie == null) {
        wypisz(p.msPierwszy == null
            ? 'Nic nie przyszło w ${_oknoPrzebicia.inSeconds} s.'
            : 'Pakiety szły tylko od drugiej strony do mnie.');
        return;
      }
      // Chwila, żeby druga strona też dostała echo i przestała nadawać.
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_pingi > 0) {
        wypisz('Mierzę czas obiegu: $_pingi pakietów co 100 ms ...');
        for (var k = 0; k < _pingi; k++) {
          final numer = los.nextInt(1 << 30);
          wyslanePingi[numer] = zegarRtt.elapsedMicroseconds;
          mux.send(_pakiet(_probe, _bajty(numer)), ip, celPort);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        p.zgubione = wyslanePingi.length;
        wyslanePingi.clear();
        wypisz(_opisRtt(p));
      }
      if (zCisza) {
        for (final s in _przerwy) {
          runda++;
          if (!await zPotwierdzeniem(
              _pakiet(_cisza, [runda, s >> 8, s & 0xFF]), _ciszaOk)) {
            wypisz('Druga strona nie potwierdziła ciszy, test przerwany.');
            break;
          }
          wypisz('Cisza przez $s s ...');
          await Future<void>.delayed(Duration(seconds: s));
          final numer = echoNumer = los.nextInt(1 << 30);
          final c = echo = Completer<void>();
          final zegar = Timer.periodic(const Duration(milliseconds: 400),
              (_) => mux.send(_pakiet(_probe, _bajty(numer)), ip, celPort));
          mux.send(_pakiet(_probe, _bajty(numer)), ip, celPort);
          var otwarta = true;
          try {
            await c.future.timeout(const Duration(seconds: 3));
          } on TimeoutException {
            otwarta = false;
          } finally {
            zegar.cancel();
          }
          p.cisza.add((s, otwarta));
          wypisz(otwarta
              ? 'Po $s s ciszy pakiet wciąż dochodzi.'
              : 'Po $s s ciszy pakiet już nie dochodzi.');
          if (!otwarta) break;
        }
      }
      if (!await zPotwierdzeniem(_pakiet(_koniec), _koniecOk)) {
        wypisz('Druga strona nie potwierdziła końca próby '
            '(po zamkniętej furtce to normalne).');
      }
    } else {
      while (!koniecB.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (p.msPierwszy == null && ms() > _oknoPrzebicia.inMilliseconds) {
          wypisz('Nic nie przyszło w ${_oknoPrzebicia.inSeconds} s.');
          break;
        }
        final limit = Duration(seconds: zapowiedzianaCisza + 20);
        if (p.msPierwszy != null &&
            DateTime.now().difference(ostatnio) > limit) {
          wypisz('Druga strona milczy dłużej, niż zapowiedziała: koniec '
              'próby.');
          break;
        }
      }
    }
  } finally {
    nadawanie.cancel();
    mux.unregister(obsluz);
  }
}

void _podsumuj(List<_Proba> wyniki) {
  wypisz('== Podsumowanie, rola $_rola ==');
  for (final p in wyniki) {
    final wynik = !p.znamAdres
        ? 'bez adresu drugiej strony'
        : p.msObie != null
            ? 'udana, pierwszy pakiet po ${p.msPierwszy} ms, obie strony po '
                '${p.msObie} ms'
            : p.msPierwszy != null
                ? 'tylko w jedną stronę (do mnie), pierwszy pakiet po '
                    '${p.msPierwszy} ms'
                : 'nieudana, nic nie przyszło';
    wypisz('Próba ${p.numer}: $wynik. NAT tej strony: ${p.nat}.'
        '${p.innyPort ? ' Druga strona nadawała z innego portu.' : ''}'
        '${_tylkoSlucha ? ' Ta strona tylko słuchała.' : ''}');
    for (final (s, otwarta) in p.cisza) {
      wypisz('  cisza $s s: pakiet ${otwarta ? 'doszedł' : 'nie doszedł'}');
    }
    if (p.rtt.isNotEmpty || p.zgubione > 0) wypisz('  ${_opisRtt(p)}');
  }
  final udane = wyniki.where((p) => p.msObie != null).length;
  wypisz('Udane: $udane z ${wyniki.length}.');
}

String _opisRtt(_Proba p) {
  if (p.rtt.isEmpty) return 'Czas obiegu: żaden pakiet nie wrócił.';
  final r = [...p.rtt]..sort();
  String f(double v) => v.toStringAsFixed(1);
  final srednia = r.reduce((a, b) => a + b) / r.length;
  final p90 = r[((r.length - 1) * 0.9).round()];
  return 'Czas obiegu (${r.length} pakietów): min ${f(r.first)} ms, '
      'mediana ${f(r[r.length ~/ 2])} ms, średnio ${f(srednia)} ms, '
      '90% poniżej ${f(p90)} ms, maks ${f(r.last)} ms; '
      'nie wróciło ${p.zgubione}.';
}

// --- link ------------------------------------------------------------------

class _Tozsamosc {
  _Tozsamosc(this.klucz, this.pub, this.guid);
  final SimpleKeyPair klucz;
  final List<int> pub;
  final String guid;
}

/// Tożsamość pomiarowa: klucz X25519 z ziarna wyprowadzonego ze słowa i roli,
/// więc każda strona zna klucz publiczny drugiej bez żadnej wymiany.
Future<_Tozsamosc> _tozsamosc(String rola) async {
  final klucz = await X25519().newKeyPairFromSeed(_zeSlowa('identity-$rola'));
  final pub = await ChattCrypto.publicKeyOf(klucz);
  return _Tozsamosc(klucz, pub, ChattCrypto.guidFromPublicKey(pub));
}

String _czas() {
  final ms = DateTime.now().difference(_start).inMilliseconds;
  return '${(ms / 1000).toStringAsFixed(1)} s';
}

InetLinkManager _menedzer(_Tozsamosc ja, _Tozsamosc on, UdpMux mux) =>
    InetLinkManager(
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
      verifiedPeers: () async => [on.guid],
      watchInterval: Duration(seconds: _liczba('CHATT_NAT_WATCH', 60)),
      onPhase: (_, faza, powod) =>
          wypisz('[${_czas()}] łącze: ${faza.name} ($powod)'),
    )
      ..onDebug = ((m) => wypisz('[${_czas()}] $m'))
      ..debugStun = _lokalnie
          // Sprawdzenie na jednym komputerze: adres pętli zwrotnej, bez STUN-u.
          ? (() => StunMapping(InternetAddress.loopbackIPv4, mux.port))
          : null;

Future<void> _link() async {
  if ((_rola != 'a' && _rola != 'b') || _slowo.isEmpty) {
    wypisz('Tryb link potrzebuje CHATT_NAT_ROLE=a albo b i tego samego '
        'CHATT_NAT_PAIR po obu stronach.');
    return;
  }
  final ja = await _tozsamosc(_rola);
  final on = await _tozsamosc(_rola == 'a' ? 'b' : 'a');
  if (_rola == 'b') {
    await _linkOdbiorca(ja, on);
  } else {
    await _linkDzwoniacy(ja, on);
  }
}

/// Strona `b`: zachowuje się jak aplikacja, która tylko czeka na rozmowę.
Future<void> _linkOdbiorca(_Tozsamosc ja, _Tozsamosc on) async {
  final mux = await SocketUdpMux.bind(port: _stalyPort);
  final koniec = Completer<void>();
  final transport = InternetTransport(
    manager: _menedzer(ja, on, mux),
    onRequest: (request, guid) async {
      var ile = 0;
      await for (final kawalek in request.body) {
        ile += kawalek.length;
      }
      wypisz('[${_czas()}] żądanie ${request.path}, $ile B.');
      if (request.path == '/done' && !koniec.isCompleted) koniec.complete();
      return BtResponse.ofBytes(200, utf8.encode('$ile'));
    },
  );
  transport.start();
  final limit = _liczba('CHATT_NAT_FOR', 15);
  wypisz('Odbiorca czeka najwyżej $limit min, skrzynkę `a` czyta co '
      '${_liczba('CHATT_NAT_WATCH', 60)} s.');
  await koniec.future
      .timeout(Duration(minutes: limit), onTimeout: () {});
  // Odpowiedź na /done musi jeszcze wyjść.
  await Future<void>.delayed(const Duration(seconds: 2));
  await transport.stop();
  await mux.close();
}

/// Strona `a`: każda rozmowa od zimnego startu, jak po uruchomieniu
/// aplikacji, a na koniec grzeczne zamknięcie, żeby `b` też zaczynał od zera.
Future<void> _linkDzwoniacy(_Tozsamosc ja, _Tozsamosc on) async {
  final ile = max(1, _liczba('CHATT_NAT_CALLS', 3));
  final bajtow = _liczba('CHATT_NAT_BYTES', 262144);
  final wyniki = <String>[];
  for (var k = 1; k <= ile; k++) {
    final mux = await SocketUdpMux.bind(port: _stalyPort);
    final transport = InternetTransport(manager: _menedzer(ja, on, mux));
    transport.start();
    wypisz('--- rozmowa $k ---');
    final t0 = DateTime.now();
    final odp = await transport.request(InternetRoute(on.guid), 'GET', '/info',
        timeout: const Duration(seconds: 10));
    final ms = DateTime.now().difference(t0).inMilliseconds;
    if (odp.status != 200) {
      wypisz('Rozmowa $k: brak połączenia po $ms ms.');
      wyniki.add('rozmowa $k: brak połączenia po ${ms ~/ 1000} s');
    } else {
      wypisz('Rozmowa $k: odpowiedź po $ms ms od zimnego startu.');
      var opis = 'rozmowa $k: odpowiedź po ${(ms / 1000).toStringAsFixed(1)} s';
      if (k == 1 && bajtow > 0) {
        final los = Random();
        final dane = List<int>.generate(bajtow, (_) => los.nextInt(256));
        final t1 = DateTime.now();
        final echo = await transport.request(
            InternetRoute(on.guid), 'POST', '/echo',
            body: dane, timeout: const Duration(seconds: 30));
        final msPrzesylu = DateTime.now().difference(t1).inMilliseconds;
        final doszlo = echo.status == 200 &&
            InternetTransport.asText(echo) == '$bajtow';
        final kBs = msPrzesylu <= 0 ? 0 : bajtow ~/ msPrzesylu;
        wypisz(doszlo
            ? 'Przesył $bajtow B: $msPrzesylu ms, około $kBs kB/s.'
            : 'Przesył $bajtow B nie doszedł (status ${echo.status}).');
        opis += doszlo ? ', przesył $kBs kB/s' : ', przesył nie doszedł';
      }
      wyniki.add(opis);
    }
    if (k == ile) {
      await transport.request(InternetRoute(on.guid), 'GET', '/done',
          timeout: const Duration(seconds: 5));
    }
    await transport.stop();
    await mux.close();
    if (k < ile) await Future<void>.delayed(const Duration(seconds: 5));
  }
  wypisz('== Podsumowanie, rola a ==');
  wyniki.forEach(wypisz);
}
