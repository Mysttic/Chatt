// Rozmowa przez Bluetooth na żywym sprzęcie.
//
// `flutter test` nie zobaczy tej drogi nigdy: kanał `chatt/bluetooth` żyje po
// stronie platformy, a CI nie ma radia. Ten skrypt podnosi prawdziwy stos
// aplikacji (baza, serwer, klient, transporty) po obu stronach i przepuszcza
// przez radio wiadomość i plik, z pełnym uściskiem dłoni i szyfrowaniem.
//
// Sprawdza to, czego nie sprawdzi nic innego: że rozmówca znaleziony przez
// radio trafia do bazy, że trasa przez Bluetooth działa dla wiadomości i dla
// pliku, i że plik dochodzi bajt w bajt.
//
//   cd app
//   # 1. komputer nasłuchuje
//   flutter run -d windows -t tool/bt_rozmowa_check.dart --dart-define=CHATT_BT_ROLE=serwer
//
//   # 2. telefon szuka, znajduje i pisze
//   flutter run -d <id-telefonu> -t tool/bt_rozmowa_check.dart --dart-define=CHATT_BT_ROLE=klient
//
// Role wolno odwrócić. Na Androidzie zgoda „Urządzenia w pobliżu" musi już
// być nadana: skrypt nie ma interfejsu, więc nie ma jak o nią zapytać.
//
//   adb shell pm grant com.mysttic.chatt android.permission.BLUETOOTH_CONNECT
//   adb shell pm grant com.mysttic.chatt android.permission.BLUETOOTH_SCAN
//
// Skrypt nie dotyka danych aplikacji: baza stoi w pamięci, katalog na odebrane
// pliki idzie do katalogu tymczasowego, discovery po UDP jest wyłączone,
// a serwer staje na porcie przydzielonym przez system. Można to puścić obok
// normalnie działającego Chatta. Tożsamość jest za każdym razem nowa, więc
// po obu stronach pojawia się nowy rozmówca.
//
// Pokrętła:
//
//   CHATT_BT_ROLE     serwer albo klient
//   CHATT_BT_ADDR     adres drugiej strony; podany pomija szukanie
//   CHATT_BT_BYTES    rozmiar pliku do przesłania, domyślnie 262144 (256 KiB)
//   CHATT_BT_WAIT     ile sekund serwer czeka, domyślnie 240
//
// CHATT_BT_ADDR przydaje się, bo szukanie i transport to dwie różne rzeczy
// i potrafią się psuć osobno. Android nie oddaje wyników wyszukiwania przy
// wyłączonych usługach lokalizacji, niezależnie od nadanych zgód; transport
// pod znanym adresem działa wtedy bez zmian.

import 'dart:async';
import 'dart:io';

import 'package:chatt/data/db.dart';
import 'package:chatt/services/app_services.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

/// Wypisanie widoczne wszędzie: `stdout` na Androidzie nie dociera do konsoli
/// `flutter run`, a `debugPrint` dociera na każdej platformie.
void wypisz(String linia) => debugPrint(linia);

const rola = String.fromEnvironment('CHATT_BT_ROLE', defaultValue: 'serwer');
const adres = String.fromEnvironment('CHATT_BT_ADDR');
const bajtow = int.fromEnvironment('CHATT_BT_BYTES', defaultValue: 262144);
const czekaj = int.fromEnvironment('CHATT_BT_WAIT', defaultValue: 240);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Okno musi istnieć, zanim cokolwiek pójdzie kanałem: na Windowsie kanał
  // rejestruje się dopiero przy tworzeniu okna.
  runApp(const SizedBox.shrink());
  await SchedulerBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(seconds: 2));

  wypisz('--- rozmowa przez bluetooth: $rola ---');

  final katalog = Directory(
      p.join(Directory.systemTemp.path, 'chatt-bt-check-$rola'));
  if (katalog.existsSync()) katalog.deleteSync(recursive: true);
  katalog.createSync(recursive: true);

  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final services = await AppServices.start(
    // Własna baza w pamięci: sprawdzian nie ma prawa dopisać się do historii
    // użytkownika ani otworzyć jego zaszyfrowanej bazy drugi raz.
    executor: NativeDatabase.memory(),
    // Bez discovery po UDP i na porcie od systemu: skrypt ma nie wchodzić
    // w drogę normalnie działającej aplikacji.
    enableDiscovery: false,
    portOverride: 0,
    nameOverride: rola == 'klient' ? 'Sprawdzian klient' : 'Sprawdzian serwer',
    receivedDirOverride: p.join(katalog.path, 'received'),
    // Bez interfejsu nie ma kto stuknąć „Akceptuj", a sprawdzamy transport,
    // nie kartę zgody.
    fileOfferPolicy: acceptAllFileOffers,
    onIncomingMessage: (peer, preview, conversationId) {
      wypisz('  <- ${peer.displayName}: $preview');
    },
  );

  try {
    if (!services.bluetoothSupported) {
      wypisz('BŁĄD: ta platforma nie ma Bluetootha w Chatcie');
      return;
    }
    final stan = await services.refreshBluetoothStatus(force: true);
    wypisz('radio:      ${stan.enabled ? 'włączone' : 'WYŁĄCZONE'}');
    wypisz('zgoda:      ${stan.granted ? 'jest' : 'BRAK'}');
    wypisz('szukanie:   ${stan.canScan ? 'wolno' : 'BRAK ZGODY'}');
    if (!await services.setBluetoothAddon(true)) {
      wypisz('BŁĄD: transport Bluetooth nie wstał');
      return;
    }
    wypisz('transport:  stoi');
    wypisz('');

    if (rola == 'klient') {
      await klient(services, katalog);
    } else {
      await serwer(services);
    }
  } finally {
    await services.dispose();
    wypisz('--- koniec ---');
  }

  exit(0);
}

/// Strona nasłuchująca: czeka i pokazuje, co przyszło.
Future<void> serwer(AppServices services) async {
  wypisz('czekam przez $czekaj s. Wiadomości i pliki wypiszą się niżej.');

  final koniec = DateTime.now().add(Duration(seconds: czekaj));
  var pokazane = 0;
  while (DateTime.now().isBefore(koniec)) {
    await Future<void>.delayed(const Duration(seconds: 2));
    final rozmowy = await services.db.watchConversationSummaries().first;
    for (final rozmowa in rozmowy) {
      final wiadomosci =
          await services.db.watchMessages(rozmowa.conversationId).first;
      if (wiadomosci.length <= pokazane) continue;
      for (final m in wiadomosci.skip(pokazane)) {
        wypisz('  ${opisWiadomosci(m)}');
      }
      pokazane = wiadomosci.length;
      wypisz('  rozmówca:   ${rozmowa.peer.displayName} '
          '${protokol(rozmowa.peer)}');
    }
  }
}

/// Strona szukająca: znajduje, pisze, wysyła plik i sprawdza wynik.
Future<void> klient(AppServices services, Directory katalog) async {
  final List<Peer> znalezieni;
  if (adres.isNotEmpty) {
    wypisz('pomijam szukanie, idę wprost pod $adres');
    final peer = await services.addPeerByBluetooth(adres);
    znalezieni = peer == null ? const [] : [peer];
  } else {
    wypisz('szukam przez radio (to trwa kilkanaście sekund)...');
    znalezieni = await services.scanBluetooth(
      // Wypisujemy każde urządzenie, które zobaczyło radio, razem z wynikiem
      // pytania o /info. Bez tego „nic nie znalazłem" nie mówi, czy komputera
      // nie widać, czy tylko nie odpowiada.
      onDevice: (device, czyChatt) => wypisz(
          '  ${czyChatt ? 'CHATT ' : 'obce  '} ${device.address}  ${device.name}'),
    );
  }
  if (znalezieni.isEmpty) {
    wypisz('BŁĄD: nie znalazłem żadnego Chatta przez Bluetooth.');
    wypisz('Sprawdź, czy druga strona ma włączony transport i czy jest');
    wypisz('wykrywalna (na Windowsie robi to sam transport).');
    return;
  }

  final peer = znalezieni.first;
  wypisz('rozmówca:   ${peer.displayName} ${peer.btAddress}');
  wypisz('trasy:      ${services.routesOf(peer).map((r) => r.label).join(', ')}');
  wypisz('');

  final rozmowa = await services.openConversationWith(peer);
  wypisz('łącza:      ${services.bluetoothLinks.join(', ')}');

  // 1. Wiadomość tekstowa.
  final start = DateTime.now();
  await services.sendText(rozmowa, 'Dzień dobry przez Bluetooth');
  final tekstMs = DateTime.now().difference(start).inMilliseconds;
  wypisz('łącza:      ${services.bluetoothLinks.join(', ')}');
  final poTekscie = await services.db.watchMessages(rozmowa).first;
  wypisz('wiadomość:  ${opisWiadomosci(poTekscie.last)}  $tekstMs ms');

  // 2. Plik o znanej treści, żeby dało się sprawdzić, co dojechało.
  final plik = File(p.join(katalog.path, 'sprawdzian.bin'));
  plik.writeAsBytesSync(
      List<int>.generate(bajtow, (i) => (i * 31 + 7) & 0xFF));
  wypisz('plik:       ${plik.path} ($bajtow B)');

  final startPliku = DateTime.now();
  await services.sendFiles(rozmowa, [plik.path]);
  final plikMs = DateTime.now().difference(startPliku).inMilliseconds;
  final poPliku = await services.db.watchMessages(rozmowa).first;
  final ostatnia = poPliku.last;
  wypisz('plik:       ${opisWiadomosci(ostatnia)}  $plikMs ms  '
      '${plikMs <= 0 ? '?' : (bajtow / plikMs).round()} kB/s');

  wypisz('');
  final peerPo = await services.db.peerByGuid(peer.guid);
  wypisz('protokół:   ${peerPo == null ? '?' : protokol(peerPo)}');
  wypisz(ostatnia.status == MessageStatus.delivered
      ? 'WYNIK: rozmowa przez Bluetooth działa.'
      : 'WYNIK: plik nie doszedł, patrz status wyżej.');
}

String opisWiadomosci(Message m) {
  final kierunek = m.direction == MessageDirection.outgoing ? '->' : '<-';
  final tresc = m.kind == MessageKind.file
      ? '[plik ${m.fileName} ${m.fileSize} B]'
      : m.body;
  return '$kierunek $tresc  (${m.status.name})';
}

String protokol(Peer peer) => switch (peer.lastProtocol) {
      0 => 'przez sieć',
      1 => 'przez Bluetooth',
      _ => 'jeszcze nie wiadomo',
    };
