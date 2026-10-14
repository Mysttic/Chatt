// Rozpoznanie do issue #27: ile da się wycisnąć z Bluetooth Classic (RFCOMM)
// między telefonem a komputerem i czy to w ogóle stoi.
//
// Kanał `chatt/bluetooth` żyje po stronie platformy (Windows:
// `windows/runner/chatt_bluetooth.cpp`, Android: `ChattBluetooth.kt`), więc
// `flutter test` go nie widzi. Ten skrypt podnosi prawdziwą aplikację, łączy
// oba urządzenia i mierzy.
//
// Pomiar robi kod natywny: przez kanał idzie sama liczba bajtów. Dzięki temu
// mierzy się radio, bez kopiowania przez MethodChannel.
//
// Zanim cokolwiek uruchomisz, sparuj urządzenia w ustawieniach systemu.
// Na komputerze: Ustawienia > Bluetooth > Dodaj urządzenie (okno musi zostać
// otwarte, bo Windows jest wykrywalny tylko wtedy). Na telefonie: Ustawienia
// > Połączone urządzenia > Sparuj nowe urządzenie.
//
//   cd app
//   # 1. komputer nasłuchuje, wypisze swój adres
//   flutter run -d windows -t tool/bt_spike.dart --dart-define=CHATT_BT_ROLE=serwer
//
//   # 2. telefon łączy się pod ten adres
//   flutter run -d <id-telefonu> -t tool/bt_spike.dart \
//     --dart-define=CHATT_BT_ROLE=klient \
//     --dart-define=CHATT_BT_ADDR=AA:BB:CC:DD:EE:FF
//
// Role wolno odwrócić: telefon `serwer`, komputer `klient`. Adres telefonu
// bierze się wtedy z listy sparowanych urządzeń wypisanej przez komputer,
// bo Android od wersji 6 nie podaje aplikacji własnego adresu.
//
// Samo `--dart-define=CHATT_BT_ROLE=status` wypisuje tylko, co widać: radio,
// zgodę i listę sparowanych urządzeń. Od tego warto zacząć na telefonie.
//
// Pozostałe pokrętła:
//
//   CHATT_BT_BYTES    bajtów na jedną fazę, domyślnie 1048576 (1 MiB)
//   CHATT_BT_SECURE   false wyłącza wymóg uwierzytelnienia łącza; do próby,
//                     gdy połączenie nie wstaje mimo sparowania
//   CHATT_BT_UUID     inne UUID usługi, gdy to domyślne z czymś koliduje
//
// Wyniki wpisz do docs/spike-rfcomm.md. Windows w trakcie każdego wołania nie
// odpowiada (kanał blokuje wątek platformy) i tak ma być: to skrypt bez
// interfejsu.

import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Wypisanie widoczne wszędzie: `stdout` na Androidzie nie dociera do konsoli
/// `flutter run`, a `debugPrint` dociera na każdej platformie.
void wypisz(String linia) => debugPrint(linia);

/// Własny UUID usługi, nie SPP. SPP (`00001101-...`) dzieli z każdym
/// przejściem USB-szeregowym i z windowsowym portem COM, więc nasłuch pod nim
/// łapie cudze połączenia, a cudze usługi łapią nasze.
const uuid = String.fromEnvironment(
  'CHATT_BT_UUID',
  defaultValue: 'c4a1f7d2-5b3e-4f1a-9c8d-6e2b0a7f3d51',
);

const rola = String.fromEnvironment('CHATT_BT_ROLE', defaultValue: 'status');
const adres = String.fromEnvironment('CHATT_BT_ADDR');
const bajtow = int.fromEnvironment('CHATT_BT_BYTES', defaultValue: 1048576);
const bezpieczne = bool.fromEnvironment('CHATT_BT_SECURE', defaultValue: true);

/// Rozmiary porcji zapisu. 990 i 1024 leżą po dwóch stronach progu, na którym
/// RFCOMM dokłada drugi pakiet, więc różnica między nimi jest osobnym wynikiem.
const porcje = [990, 1024, 4096, 16384];

/// Krótka wiadomość na czas obrotu: tyle mniej więcej waży koperta Chatta.
const pingBajtow = 200;
const pingRund = 20;

const _kanal = MethodChannel('chatt/bluetooth');

/// Strona natywna oddaje błąd na dwa sposoby: Android rzuca
/// [PlatformException], Windows zwraca mapę z kluczem `error`, bo jego błędy
/// biorą się w środku funkcji zwracającej wynik. Tutaj oba wyglądają tak samo.
Future<Map<String, Object?>> wolaj(String metoda, [Map<String, Object?>? args]) async {
  final Map<String, Object?>? odpowiedz;
  try {
    odpowiedz = await _kanal.invokeMapMethod<String, Object?>(metoda, args);
  } on PlatformException catch (blad) {
    throw StateError('$metoda: ${blad.code} ${blad.message}');
  } on MissingPluginException {
    throw StateError('$metoda: kanału chatt/bluetooth nie ma na tej platformie');
  }
  if (odpowiedz == null) {
    throw StateError('$metoda: pusta odpowiedź');
  }
  final blad = odpowiedz['error'];
  if (blad != null) {
    throw StateError('$metoda: $blad (kod ${odpowiedz['code']})');
  }
  return odpowiedz;
}

/// Dwie metody kanału oddają zwykłe `true`/`false`.
Future<bool> wolajBool(String metoda) async {
  try {
    return await _kanal.invokeMethod<bool>(metoda) ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

int liczba(Object? value) => value is num ? value.toInt() : 0;

/// kB liczone po 1000 bajtów, bo tak podaje się przepustowość łącza.
String naSekunde(int bytes, int ms) =>
    ms <= 0 ? '?' : (bytes / ms).round().toString();

String szesnastkowo(Object? hash) =>
    '0x${(liczba(hash) & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Okno musi istnieć, zanim cokolwiek pójdzie kanałem: na Windowsie kanał
  // rejestruje się dopiero przy tworzeniu okna.
  runApp(const SizedBox.shrink());
  await SchedulerBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(seconds: 2));

  wypisz('--- bt spike: $rola ---');
  try {
    await pokazStatus();
    switch (rola) {
      case 'serwer':
        await serwer();
      case 'klient':
        await klient();
      default:
        wypisz('');
        wypisz('Nic więcej nie robię. Rolę wybiera się przez');
        wypisz('--dart-define=CHATT_BT_ROLE=serwer albo =klient.');
    }
  } on StateError catch (blad) {
    wypisz('BŁĄD: ${blad.message}');
  } finally {
    if (rola != 'status') {
      await wolajBool('benchClose');
    }
  }
  wypisz('--- koniec ---');

  exit(0);
}

Future<void> pokazStatus() async {
  final status = await wolaj('status');
  final nazwa = status['name'];
  final adresRadia = status['address'];
  wypisz('radio:      ${status['available'] == true ? 'jest' : 'BRAK'}'
      '${status['enabled'] == true ? ', włączone' : ', WYŁĄCZONE'}');
  wypisz('nazwa:      ${nazwa == null || nazwa == '' ? '(nieznana)' : nazwa}');
  wypisz('adres:      ${adresRadia == null || adresRadia == '' ? '(Android go nie podaje)' : adresRadia}');
  wypisz('zgoda:      ${status['granted'] == true ? 'jest' : 'BRAK'}');

  // Komputer potrafi mieć dwa radia (układ na płycie i pastylka w USB),
  // a druga strona jest sparowana tylko z jednym: bez pełnej listy łatwo
  // podać do połączenia adres tego drugiego.
  final radios = (status['radios'] as List<Object?>? ?? const []);
  if (radios.length > 1) {
    wypisz('radia:      ${radios.length}, sprawdź, z którym sparowana jest');
    wypisz('            druga strona:');
    for (final entry in radios) {
      final radio = (entry as Map<Object?, Object?>);
      wypisz('            ${radio['address']}  ${radio['name']}');
    }
  }

  final paired = (status['paired'] as List<Object?>? ?? const []);
  wypisz('sparowane:  ${paired.isEmpty ? '(puste)' : ''}');
  for (final entry in paired) {
    final device = (entry as Map<Object?, Object?>);
    wypisz('            ${device['address']}  ${device['name']}');
  }
  wypisz('uuid:       $uuid');
  wypisz('');

  if (status['granted'] != true) {
    wypisz('Brak zgody „Urządzenia w pobliżu". Dwie drogi:');
    wypisz('  adb shell pm grant com.mysttic.chatt '
        'android.permission.BLUETOOTH_CONNECT');
    wypisz('  albo ustawienia systemu, które właśnie otwieram.');
    await wolajBool('openSettings');
    wypisz('Po nadaniu zgody wciśnij R w konsoli flutter run.');
    throw StateError('brak zgody BLUETOOTH_CONNECT');
  }
  if (status['available'] != true || status['enabled'] != true) {
    throw StateError('radio Bluetooth jest wyłączone albo go nie ma');
  }
}

Future<void> serwer() async {
  wypisz('nasłuch pod $uuid, czekam na klienta...');
  final peer = await czekajNaKlienta();
  wypisz('klient:     $peer');
  wypisz('');
  naglowek();

  for (final porcja in porcje) {
    // Kolejność jest umówiona po obu stronach: najpierw klient nadaje.
    final odebrane = await wolaj('benchReceive', {
      'bytes': bajtow,
      'timeoutMs': 60000,
    });
    wiersz('klient->serwer', porcja, odebrane);

    final wyslane = await wolaj('benchSend', {
      'bytes': bajtow,
      'chunk': porcja,
      'timeoutMs': 60000,
    });
    wiersz('serwer->klient', porcja, wyslane, nadawca: true);
  }

  wypisz('');
  await wolaj('benchEcho', {
    'bytes': pingBajtow,
    'rounds': pingRund,
    'timeoutMs': 60000,
  });
  wypisz('czas obrotu mierzy klient.');
}

Future<void> klient() async {
  if (adres.isEmpty) {
    throw StateError('brak --dart-define=CHATT_BT_ADDR z adresem drugiej strony');
  }
  wypisz('łączę się z $adres ...');
  final polaczenie = await wolaj('benchConnect', {
    'address': adres,
    'uuid': uuid,
    'secure': bezpieczne,
    'timeoutMs': 20000,
  });
  if (polaczenie['connected'] != true) {
    throw StateError('nie udało się połączyć');
  }
  wypisz('połączony:  ${polaczenie['peer'] ?? adres}');
  wypisz('');
  naglowek();

  for (final porcja in porcje) {
    final wyslane = await wolaj('benchSend', {
      'bytes': bajtow,
      'chunk': porcja,
      'timeoutMs': 60000,
    });
    wiersz('klient->serwer', porcja, wyslane, nadawca: true);

    final odebrane = await wolaj('benchReceive', {
      'bytes': bajtow,
      'timeoutMs': 60000,
    });
    wiersz('serwer->klient', porcja, odebrane);
  }

  wypisz('');
  final ping = await wolaj('benchPing', {
    'bytes': pingBajtow,
    'rounds': pingRund,
    'timeoutMs': 60000,
  });
  final ms = liczba(ping['ms']);
  final rund = liczba(ping['rounds']);
  wypisz('czas obrotu $pingBajtow B x $rund:  '
      '${rund == 0 ? '?' : (ms / rund).toStringAsFixed(1)} ms');
}

/// Nasłuch pyta o klienta krótkimi rzutami:
/// na Windowsie kanał trzyma wątek platformy, więc długi rzut zawiesiłby okno
/// i `flutter run` uznałby aplikację za martwą.
Future<String> czekajNaKlienta() async {
  final koniec = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(koniec)) {
    final odpowiedz = await wolaj('benchListen', {
      'uuid': uuid,
      'name': 'Chatt spike',
      'secure': bezpieczne,
      'timeoutMs': 5000,
    });
    if (odpowiedz['connected'] == true) {
      return '${odpowiedz['peer'] ?? '(nieznany)'}';
    }
  }
  throw StateError('nikt się nie zgłosił przez trzy minuty');
}

void naglowek() {
  wypisz('porcja  kierunek         bajty       ms    kB/s  wzorzec');
}

void wiersz(
  String kierunek,
  int porcja,
  Map<String, Object?> wynik, {
  bool nadawca = false,
}) {
  final bytes = liczba(wynik['bytes']);
  final ms = liczba(wynik['ms']);
  final stan = nadawca
      ? '(nadane)'
      : (wynik['ok'] == true ? 'ok ${szesnastkowo(wynik['hash'])}' : 'ROZJECHANY');
  wypisz('${porcja.toString().padRight(7)} '
      '${kierunek.padRight(16)} '
      '${bytes.toString().padLeft(9)} '
      '${ms.toString().padLeft(6)} '
      '${naSekunde(bytes, ms).padLeft(6)}  $stan');
}
