// Klawiatura z PC przez Bluetooth: pomiary opóźnień na prawdziwym telefonie.
//
// `flutter test` radia nie ma (kanał `chatt/bluetooth` żyje w runnerze), więc
// ten skrypt chodzi jako aplikacja na Windows. Jest nadawcą z bazą w pamięci,
// a odbiorcą jest aplikacja Chatt na telefonie podłączonym kablem: adb służy
// tylko do stukania i do sprawdzania, co jest na ekranie. Skrypt jest ostrożny
// wobec telefonu, którego ktoś używa na co dzień: nie wysyła żadnej wiadomości,
// pisze wyłącznie do formularza nowego kontaktu (sprawdza cel przed każdą
// paczką), na koniec kasuje wpisany tekst, zamyka formularz bez zapisu,
// przywraca klawiatury systemu i, jeśli to on włączył dodatek Bluetooth
// w aplikacji na telefonie, wyłącza go z powrotem. Do logu idzie tylko liczba
// węzłów na ekranie, nigdy jego treść.
//
//   cd app
//   set ADB=C:\...\platform-tools\adb.exe
//   set CHATT_DEVICE=<numer z adb devices>
//   flutter run -d windows -t tool/klawiatura_bt_pomiar.dart ^
//     --dart-define=CHATT_BT_ADDR=<adres radia telefonu>
//
// Adres radia telefonu: `adb shell settings get secure bluetooth_address`.
// Z --dart-define=CHATT_PHONE_IP=<adres w sieci> zamiast radia ta sama sesja
// idzie przez Wi‑Fi: porównanie z tym samym nadawcą, w tym samym procesie.
// CHATT_POMIAR_ZNAKI (dart-define, domyślnie 100) to liczba znaków pomiaru.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/network/transport.dart' show PeerProtocol;
import 'package:chatt/services/app_services.dart';

import 'uiautomator.dart';

const String appPackage = 'com.mysttic.chatt';
const String imeId = '$appPackage/.ChattInputMethod';
const String kontakty = 'com.google.android.contacts';

const String adresRadia = String.fromEnvironment('CHATT_BT_ADDR');
const String ipTelefonu = String.fromEnvironment('CHATT_PHONE_IP');
const int ileZnakow = int.fromEnvironment('CHATT_POMIAR_ZNAKI', defaultValue: 100);

bool get przezRadio => ipTelefonu.isEmpty;

/// Wypisanie widoczne w konsoli `flutter run`.
void wypisz(String linia) => debugPrint(linia);

void sprawdz(bool warunek, String co) {
  if (!warunek) throw StateError(co);
}

Future<String> ustawienie(String klucz) async =>
    ((await adb(['shell', 'settings', 'get', 'secure', klucz])).stdout
            as String)
        .trim();

Future<String> biezacaKlawiatura() => ustawienie('default_input_method');

Future<void> czekaj(Future<bool> Function() warunek, String co,
    {Duration ile = const Duration(seconds: 20)}) async {
  final koniec = DateTime.now().add(ile);
  while (!await warunek()) {
    if (DateTime.now().isAfter(koniec)) throw StateError('nie doczekano: $co');
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

/// Percentyl z posortowanej listy (metoda najbliższego rzędu).
int percentyl(List<int> wartosci, double p) {
  final s = [...wartosci]..sort();
  final i = math.max(0, (p * s.length).ceil() - 1);
  return s[math.min(i, s.length - 1)];
}

String statystyka(String co, List<int> ms) => ms.isEmpty
    ? '$co: brak próbek'
    : '$co: n=${ms.length} p50=${percentyl(ms, 0.5)} ms '
        'p95=${percentyl(ms, 0.95)} ms min=${ms.reduce(math.min)} ms '
        'max=${ms.reduce(math.max)} ms';

/// Czy dodatek Bluetooth w aplikacji na telefonie nasłuchuje: gniazdo
/// RFCOMM „Chatt" w stanie nasłuchu w ostatnich zdarzeniach radia.
Future<bool> telefonNasluchuje() async {
  final zrzut = (await adb(['shell', 'dumpsys', 'bluetooth_manager'])).stdout
      as String;
  String? ostatni;
  for (final linia in zrzut.split('\n')) {
    if (!linia.trimRight().endsWith('Chatt')) continue;
    if (linia.contains('STATE_LISTENING')) ostatni = 'nasłuch';
    if (linia.contains('STATE_DISCONNECTED') ||
        linia.contains('STATE_CLOSED')) {
      ostatni = 'koniec';
    }
  }
  return ostatni == 'nasłuch';
}

/// Przełącznik dodatku Bluetooth w ustawieniach aplikacji na telefonie.
/// Stuka wyłącznie w elementy aplikacji Chatt.
Future<void> przelaczBluetoothNaTelefonie() async {
  await adb([
    'shell', 'monkey', '-p', appPackage, '-c',
    'android.intent.category.LAUNCHER', '1',
  ]);
  await Future<void>.delayed(const Duration(seconds: 2));
  // Aplikacja wraca na ekranie, na którym ją zostawiono: najpierw lista.
  for (var i = 0; i < 3; i++) {
    final wstecz = await findAnyWidget(['Back', 'Wstecz'],
        pakiet: appPackage, timeout: const Duration(seconds: 2));
    if (wstecz == null) break;
    await adb(['shell', 'input', 'tap', '${wstecz.$2.$1}', '${wstecz.$2.$2}']);
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  await stuknijEtykiete(['Settings', 'Ustawienia'], pakiet: appPackage);
  // Tytuł i opis przełącznika to jeden węzeł: szukamy po początku opisu,
  // bo samo „Bluetooth" pada też w innych napisach ustawień.
  const przelacznik = [
    'Messages and files over the radio',
    'Wiadomości i pliki przez radio',
  ];
  for (var i = 0; i < 12; i++) {
    if (await findAnyWidget(przelacznik,
            fragment: true,
            pakiet: appPackage,
            timeout: const Duration(seconds: 2)) !=
        null) {
      break;
    }
    await adb(['shell', 'input', 'swipe', '640', '2200', '640', '1200', '300']);
  }
  await stuknijEtykiete(przelacznik, fragment: true, pakiet: appPackage);
  await Future<void>.delayed(const Duration(seconds: 3));
  await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Okno musi istnieć, zanim cokolwiek pójdzie kanałem: na Windowsie kanał
  // rejestruje się dopiero przy tworzeniu okna.
  runApp(const SizedBox.shrink());
  await SchedulerBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(seconds: 2));

  var kod = 1;
  try {
    kod = await pomiar();
  } catch (blad, slad) {
    wypisz('BŁĄD: $blad');
    wypisz('$slad');
  }
  wypisz('--- koniec (kod $kod) ---');
  exit(kod);
}

Future<int> pomiar() async {
  if (Platform.environment['CHATT_DEVICE'] == null) {
    wypisz('BŁĄD: brak CHATT_DEVICE, nie wiadomo, który telefon');
    return 1;
  }
  if (przezRadio && adresRadia.isEmpty) {
    wypisz('BŁĄD: brak CHATT_BT_ADDR (adres radia telefonu)');
    return 1;
  }
  // Ekran telefonu niesie prywatne rozmowy: do logów idzie tylko liczba
  // węzłów.
  ukryjTrescEkranu = true;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  wypisz('--- klawiatura z PC: pomiar przez '
      '${przezRadio ? 'Bluetooth do $adresRadia' : 'Wi‑Fi do $ipTelefonu'}, '
      'telefon $deviceId ---');

  final work = Directory.systemTemp.createTempSync('chatt_klawiatura_bt');
  final klawiaturyPrzed = await ustawienie('enabled_input_methods');
  final klawiaturaPrzed = await biezacaKlawiatura();
  var wlaczylemBluetooth = false;
  var formularzOtwarty = false;
  var wpisaneWFormularzu = 0;

  await adb(['shell', 'ime', 'enable', imeId]);
  await adb([
    'shell', 'monkey', '-p', appPackage, '-c',
    'android.intent.category.LAUNCHER', '1',
  ]);

  final host = await AppServices.start(
    executor: NativeDatabase.memory(),
    portOverride: 0,
    nameOverride: przezRadio ? 'Pomiar PC radio' : 'Pomiar PC sieć',
    enableDiscovery: false,
    receivedDirOverride: p.join(work.path, 'received'),
  );
  OutgoingRemoteInput? stan() => host.outgoingRemoteInput.value;

  Future<OutgoingRemoteInput> odpowiedz(int przed) async {
    final koniec = DateTime.now().add(const Duration(seconds: 20));
    while ((stan()?.typedReplies ?? przed) <= przed) {
      if (DateTime.now().isAfter(koniec)) {
        throw StateError('brak odpowiedzi na paczkę');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    return stan()!;
  }

  /// Pisze wyłącznie, gdy pole z fokusem należy do Kontaktów.
  Future<OutgoingRemoteInput> wpiszDoKontaktu(List<RemoteInputOp> ops) async {
    final cel = stan()?.target;
    if (cel == null || cel.app != kontakty || !cel.active) {
      throw StateError('cel to nie Kontakty (${cel?.app}), nic nie wysyłam');
    }
    final przed = stan()!.typedReplies;
    sprawdz(host.sendRemoteInput(ops), 'paczka nie poszła');
    return odpowiedz(przed);
  }

  try {
    await host.setKeyboardAddon(true);
    Peer? telefon;
    if (przezRadio) {
      sprawdz(host.bluetoothSupported, 'ta platforma nie ma Bluetootha');
      final radio = await host.refreshBluetoothStatus(force: true);
      sprawdz(radio.enabled && radio.granted, 'radio komputera niegotowe');
      sprawdz(await host.setBluetoothAddon(true), 'transport nie wstał');
      if (!await telefonNasluchuje()) {
        wypisz('dodatek Bluetooth na telefonie nie nasłuchuje: włączam');
        await przelaczBluetoothNaTelefonie();
        wlaczylemBluetooth = true;
        await czekaj(telefonNasluchuje, 'nasłuch „Chatt" na telefonie');
      }
      for (var proba = 0; proba < 3 && telefon == null; proba++) {
        telefon = await host.addPeerByBluetooth(adresRadia);
        if (telefon == null) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    } else {
      telefon = await host.addPeerByAddress(ipTelefonu, 47780);
    }
    sprawdz(telefon != null, 'aplikacja na telefonie nie odpowiada na /info');
    wypisz('trasy: ${host.routesOf(telefon!).map((r) => r.label).join(', ')}');

    // Parowanie kodem: tarcza po obu stronach.
    sprawdz(await host.startPairing(telefon) != null, 'parowanie nie ruszyło');
    await host.confirmPairing(telefon.guid);
    await stuknijEtykiete(['They match', 'Zgadza się'],
        azZniknie: true, pakiet: appPackage);
    await czekaj(() async => (await host.db.peerByGuid(telefon!.guid))!.verified,
        'tarcza po obu stronach',
        ile: const Duration(seconds: 60));
    telefon = (await host.db.peerByGuid(telefon.guid))!;

    // Zgoda na karcie i wybór klawiatury Chatt.
    var start = host.startRemoteInput(telefon);
    final odmowa = await czekajNaKarteAlbo(start, ['Accept', 'Akceptuj'],
        pakiet: appPackage, timeout: const Duration(seconds: 60));
    if (odmowa == RemoteInputStart.notEnabled) {
      wypisz('dodatek klawiatury albo odbiór wyłączony w aplikacji: włączam');
      await wlaczDodatekKlawiatury(appPackage);
      await adb([
        'shell', 'monkey', '-p', appPackage, '-c',
        'android.intent.category.LAUNCHER', '1',
      ]);
      start = host.startRemoteInput(telefon);
    }
    await stuknijEtykiete(['Accept', 'Akceptuj'],
        azZniknie: true, pakiet: appPackage);
    final wynikStartu = await start;
    sprawdz(wynikStartu == RemoteInputStart.accepted, 'start: $wynikStartu');
    if (await biezacaKlawiatura() != imeId) {
      await stuknijEtykiete(['Chatt keyboard', 'Klawiatura Chatt'],
          ostatni: true);
    }
    await czekaj(() async => await biezacaKlawiatura() == imeId,
        'klawiatura Chatt bieżącą');
    wypisz('droga sesji: ${stan()?.protocol?.name}');
    if (przezRadio) {
      sprawdz(stan()?.protocol == PeerProtocol.bluetooth,
          'sesja nie idzie przez radio');
    }

    // Formularz nowego kontaktu.
    await adb(['shell', 'am', 'force-stop', kontakty]);
    await adb([
      'shell', 'am', 'start', '-a', 'android.intent.action.INSERT', '-t',
      'vnd.android.cursor.dir/contact',
    ]);
    formularzOtwarty = true;
    await stuknijPole();
    await czekaj(() async {
      final cel = stan()?.target;
      return cel != null && cel.active && cel.app == kontakty;
    }, 'cel u nadawcy: formularz kontaktu', ile: const Duration(seconds: 30));

    // Poprawność: polskie znaki, Backspace, emoji jako jeden znak.
    await wpiszDoKontaktu(const [RemoteInputOp.insert('Chatt ąęł 124')]);
    await wpiszDoKontaktu(const [RemoteInputOp.backspace()]);
    await wpiszDoKontaktu(const [RemoteInputOp.insert('3 😀')]);
    await wpiszDoKontaktu(const [RemoteInputOp.backspace()]);
    wpisaneWFormularzu = 'Chatt ąęł 123 '.runes.length;
    await czekaj(() => jestPoleZTekstem('Chatt ąęł 123 '), 'tekst w polu');
    wypisz('tekst w polu: zgodny');

    // Ping: tło bez pisania, co sekundę.
    final pingi = <int>[];
    var ostatnieOdpowiedzi = stan()!.typedReplies;
    void naPing() {
      final s = host.outgoingRemoteInput.value;
      if (s == null || s.rtt == null) return;
      if (s.typedReplies == ostatnieOdpowiedzi) pingi.add(s.rtt!.inMilliseconds);
      ostatnieOdpowiedzi = s.typedReplies;
    }

    host.outgoingRemoteInput.addListener(naPing);
    await Future<void>.delayed(const Duration(seconds: 30));
    host.outgoingRemoteInput.removeListener(naPing);

    // Znak po znaku co 100 ms: czas od wysłania do odpowiedzi i sam czas
    // wymiany paczki u nadawcy.
    final znaki = <int>[];
    final wymiany = <int>[];
    for (var i = 0; i < ileZnakow; i++) {
      final zegar = Stopwatch()..start();
      final po = await wpiszDoKontaktu(
          [RemoteInputOp.insert(String.fromCharCode(0x61 + i % 26))]);
      znaki.add(zegar.elapsedMilliseconds);
      if (po.rtt != null) wymiany.add(po.rtt!.inMilliseconds);
      wpisaneWFormularzu++;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    // Szybkie pisanie (co 20 ms) bez czekania: ile paczek na znak.
    final przedSeria = stan()!.typedReplies;
    final seria = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      final cel = stan()?.target;
      if (cel == null || cel.app != kontakty) {
        throw StateError('cel się zmienił w trakcie serii (${cel?.app})');
      }
      sprawdz(host.sendRemoteInput(const [RemoteInputOp.insert('z')]),
          'paczka serii nie poszła');
      wpisaneWFormularzu++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    var ostatnio = stan()!.typedReplies;
    var cisza = 0;
    while (cisza < 10) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final teraz = stan()!.typedReplies;
      cisza = teraz == ostatnio ? cisza + 1 : 0;
      ostatnio = teraz;
    }
    seria.stop();
    final paczkiSerii = stan()!.typedReplies - przedSeria;

    wypisz(statystyka('RTT pingu', pingi));
    wypisz(statystyka('znak (wysłanie do odpowiedzi, co 100 ms)', znaki));
    wypisz(statystyka('znak, sama wymiana paczki (rtt nadawcy)', wymiany));
    wypisz('seria 50 znaków co 20 ms: $paczkiSerii paczek '
        '(${(paczkiSerii / 50).toStringAsFixed(2)} paczki na znak), '
        'całość ${seria.elapsedMilliseconds} ms');
    wypisz('droga na końcu: ${stan()?.protocol?.name}');

    // Cały wpisany tekst z powrotem.
    await wpiszDoKontaktu([RemoteInputOp.backspace(wpisaneWFormularzu)]);
    wpisaneWFormularzu = 0;
    await czekaj(() async => !await jestPoleZTekstem('Chatt'),
        'pole kontaktu z powrotem puste');
    return 0;
  } finally {
    // Każdy krok z limitem: zawieszone adb nie trzyma skryptu w nieskończoność.
    Future<void> krok(String nazwa, Future<void> Function() co,
            {Duration limit = const Duration(seconds: 30)}) =>
        (() async {
          await co();
        })()
            .timeout(limit, onTimeout: () {
          wypisz('sprzątanie: „$nazwa" nie skończyło się');
        }).catchError((Object blad) {
          wypisz('sprzątanie: „$nazwa": $blad');
        });
    await krok('stop sesji', host.stopRemoteInput);
    if (formularzOtwarty) {
      await krok('zamknięcie formularza', () async {
        await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
        await Future<void>.delayed(const Duration(seconds: 1));
        await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
        await Future<void>.delayed(const Duration(seconds: 1));
        for (final e in ['Discard', 'Odrzuć']) {
          final gdzie = await findWidget(e, timeout: const Duration(seconds: 2));
          if (gdzie != null) {
            await adb(['shell', 'input', 'tap', '${gdzie.$1}', '${gdzie.$2}']);
            break;
          }
        }
      });
      await krok('Kontakty zatrzymane',
          () => adb(['shell', 'am', 'force-stop', kontakty]));
    }
    await krok('klawiatury jak przed pomiarem', () async {
      if (!klawiaturyPrzed.contains(imeId)) {
        await adb(['shell', 'ime', 'disable', imeId]);
      }
      await adb(['shell', 'ime', 'set', klawiaturaPrzed]);
    });
    if (wlaczylemBluetooth) {
      await krok('dodatek Bluetooth na telefonie z powrotem wyłączony',
          () async {
        await przelaczBluetoothNaTelefonie();
        await czekaj(() async => !await telefonNasluchuje(),
            'koniec nasłuchu na telefonie');
      }, limit: const Duration(seconds: 120));
    }
    await krok('zamknięcie nadawcy', host.dispose);
    wypisz('klawiatura po pomiarze: ${await biezacaKlawiatura()} '
        '(przed: $klawiaturaPrzed); dodatek Bluetooth na telefonie: '
        '${await telefonNasluchuje() ? 'nasłuchuje' : 'nie nasłuchuje'}');
    work.deleteSync(recursive: true);
  }
}
