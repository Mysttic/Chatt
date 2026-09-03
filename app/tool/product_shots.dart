// Zrzuty ekranu do dokumentacji, robione na żywej aplikacji na emulatorze.
//
// Skrypt zakłada demonstracyjną rozmowę (dwóch rozmówców, wiadomości w obie
// strony, plik), przechodzi po ekranach i zapisuje zrzuty do
// docs/screenshots/produkt/. Po wszystkim czyści po sobie dane aplikacji,
// żeby na urządzeniu nie zostały wpisy z niczyjej prawdziwej rozmowy.
//
// Uruchomienie (aplikacja musi być zainstalowana na emulatorze):
//   set ADB=...\platform-tools\adb.exe
//   flutter test tool/product_shots.dart
//
// ignore_for_file: avoid_print
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Canvas, Color, Offset, Paint, Rect;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';

const String appPackage = 'com.mysttic.chatt';
const int deviceProxyPort = 47781;

String get _adb => Platform.environment['ADB'] ?? 'adb';
String get _device => Platform.environment['CHATT_DEVICE'] ?? 'emulator-5554';

Future<ProcessResult> adb(List<String> args) => Process.run(
      _adb,
      ['-s', _device, ...args],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

late Directory shots;

Future<void> zrzut(String nazwa) async {
  // Chwila na dokończenie animacji — inaczej łapiemy przejście w połowie.
  await Future<void>.delayed(const Duration(milliseconds: 700));
  final wynik = await Process.run(
    _adb,
    ['-s', _device, 'exec-out', 'screencap', '-p'],
    stdoutEncoding: null,
  );
  final plik = File(p.join(shots.path, '$nazwa.png'))
    ..writeAsBytesSync(wynik.stdout as List<int>);
  print('zapisano ${plik.path}');
}

Future<String> drzewo() async {
  const dump = '/sdcard/chatt_shots.xml';
  final dumped = await adb(['shell', 'uiautomator', 'dump', dump]);
  if (!'${dumped.stdout}'.contains(dump)) return '';
  return (await adb(['shell', 'cat', dump])).stdout as String;
}

/// Środek widgetu, którego opis zawiera [etykieta]. Flutter wystawia teksty
/// jako `content-desc` i potrafi scalić całą kartę w jeden węzeł, więc
/// dopasowujemy po fragmencie, a nie po całości.
/// [wystapienie] rozstrzyga, gdy ta sama etykieta jest na ekranie kilka razy
/// (np. „System" i przy motywie, i przy języku) — liczone od góry drzewa.
Future<(int, int)?> znajdz(
  String etykieta, {
  Duration timeout = const Duration(seconds: 10),
  int wystapienie = 0,
  bool dokladnie = false,
}) async {
  final koniec = DateTime.now().add(timeout);
  final szukane = RegExp.escape(etykieta);
  final wzorzec = dokladnie
      ? RegExp('content-desc="$szukane"')
      : RegExp('content-desc="[^"]*$szukane');
  do {
    var pominiete = 0;
    for (final node in (await drzewo()).split('<node ')) {
      if (!wzorzec.hasMatch(node)) continue;
      final b =
          RegExp(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"').firstMatch(node);
      if (b == null) continue;
      if (pominiete++ < wystapienie) continue;
      return (
        (int.parse(b.group(1)!) + int.parse(b.group(3)!)) ~/ 2,
        (int.parse(b.group(2)!) + int.parse(b.group(4)!)) ~/ 2,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  } while (DateTime.now().isBefore(koniec));
  return null;
}

/// Pisze wiadomość w otwartej rozmowie i wysyła ją. `adb shell input text`
/// nie umie polskich znaków (rzuca wyjątkiem), więc teksty wpisywane tą drogą
/// są bez diakrytyków — to widać tylko w zrzutach, aplikacji nie dotyczy.
Future<void> napisz(String tekst) async {
  // Pole tekstowe nie ma opisu w drzewie (Flutter wystawia sam podpowiedź),
  // więc szukamy po klasie widoku.
  final pole = await znajdzKlase('android.widget.EditText');
  if (pole == null) throw StateError('Nie ma pola wiadomości');
  await adb(['shell', 'input', 'tap', '${pole.$1}', '${pole.$2}']);
  await adb(['shell', 'input', 'text', tekst.replaceAll(' ', '%s')]);
  // Dokładnie „Wyślij", bo spinacz obok ma opis „Wyślij plik".
  await stuknij('Wyślij', dokladnie: true);
  // Klawiatura zasłania pół ekranu i zjada miejsce kartom nad aplikacją,
  // więc po wysłaniu ją chowamy.
  await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
  await Future<void>.delayed(const Duration(seconds: 2));
}

/// Wpisuje tekst w pierwsze pole edycji na ekranie. W trybie szukania jest
/// nim pole w pasku u góry — leży w drzewie wyżej niż pole wiadomości.
Future<void> wpisz(String tekst) async {
  final pole = await znajdzKlase('android.widget.EditText');
  if (pole == null) throw StateError('Nie ma pola do wpisania');
  await adb(['shell', 'input', 'tap', '${pole.$1}', '${pole.$2}']);
  await adb(['shell', 'input', 'text', tekst.replaceAll(' ', '%s')]);
  await Future<void>.delayed(const Duration(seconds: 1));
}

/// Prostokąt węzła o opisie zawierającym [etykieta].
Future<(int, int, int, int)?> ramka(String etykieta,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final koniec = DateTime.now().add(timeout);
  final wzorzec = RegExp('content-desc="[^"]*${RegExp.escape(etykieta)}');
  do {
    for (final node in (await drzewo()).split('<node ')) {
      if (!wzorzec.hasMatch(node)) continue;
      final b =
          RegExp(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"').firstMatch(node);
      if (b == null) continue;
      return (
        int.parse(b.group(1)!),
        int.parse(b.group(2)!),
        int.parse(b.group(3)!),
        int.parse(b.group(4)!),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  } while (DateTime.now().isBefore(koniec));
  return null;
}

/// Przytrzymanie palcem. Dwie rzeczy, które trzeba tu zrobić inaczej niż
/// w [stuknij]:
///
/// 1. Osobne `motionevent DOWN` i `UP` z prawdziwą przerwą między nimi.
///    `input swipe` wstrzykuje całą gestykulację na raz i licznik
///    przytrzymania po stronie Fluttera (zwykły Timer) nie zdąży się odpalić.
/// 2. [poziom] zamiast środka węzła. Dymek własnej wiadomości jest dosunięty
///    do prawej, a semantyka Fluttera obejmuje cały wiersz listy — środek
///    takiego węzła wypada w pustym miejscu obok dymka.
Future<void> przytrzymaj(String etykieta, {double poziom = 0.5}) async {
  // Układ musi się uspokoić: współrzędne z drzewa sprzed animacji trafiają
  // w miejsce, którego już tam nie ma.
  await Future<void>.delayed(const Duration(seconds: 2));
  final r = await ramka(etykieta);
  if (r == null) throw StateError('Nie ma na ekranie: $etykieta');
  final x = '${(r.$1 + (r.$3 - r.$1) * poziom).round()}';
  final y = '${(r.$2 + r.$4) ~/ 2}';
  // Źródło podane wprost: bez niego `input` wybiera domyślne (mysz).
  await adb(['shell', 'input', 'touchscreen', 'motionevent', 'DOWN', x, y]);
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  await adb(['shell', 'input', 'touchscreen', 'motionevent', 'UP', x, y]);
  await Future<void>.delayed(const Duration(seconds: 1));
}

/// Obrazek na demo miniatury. Rysowany, a nie dołączany do repozytorium —
/// zrzuty mają dać się odtworzyć bez wlekania za sobą cudzych zdjęć.
Future<List<int>> demoObrazek() async {
  const szerokosc = 720.0;
  const wysokosc = 480.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder,
      const Rect.fromLTWH(0, 0, szerokosc, wysokosc));
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, szerokosc, wysokosc),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(szerokosc, wysokosc),
        const [Color(0xFF2E6BE6), Color(0xFF35C4C4)],
      ),
  );
  canvas.drawCircle(const Offset(520, 140), 70,
      Paint()..color = const Color(0xFFFFE082));
  final obraz = await recorder
      .endRecording()
      .toImage(szerokosc.toInt(), wysokosc.toInt());
  final dane = await obraz.toByteData(format: ui.ImageByteFormat.png);
  return dane!.buffer.asUint8List();
}

Future<(int, int)?> znajdzKlase(String klasa,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final koniec = DateTime.now().add(timeout);
  do {
    for (final node in (await drzewo()).split('<node ')) {
      if (!node.contains('class="$klasa"')) continue;
      final b =
          RegExp(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"').firstMatch(node);
      if (b == null) continue;
      return (
        (int.parse(b.group(1)!) + int.parse(b.group(3)!)) ~/ 2,
        (int.parse(b.group(2)!) + int.parse(b.group(4)!)) ~/ 2,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  } while (DateTime.now().isBefore(koniec));
  return null;
}

Future<void> stuknij(String etykieta,
    {int wystapienie = 0, bool dokladnie = false}) async {
  final gdzie = await znajdz(etykieta,
      wystapienie: wystapienie, dokladnie: dokladnie);
  if (gdzie == null) throw StateError('Nie ma na ekranie: $etykieta');
  await adb(['shell', 'input', 'tap', '${gdzie.$1}', '${gdzie.$2}']);
  await Future<void>.delayed(const Duration(seconds: 1));
}

/// Rozmówca po stronie komputera: osobna instancja stosu, która rozmawia
/// z aplikacją na emulatorze przez tunel adb.
Future<AppServices> rozmowca({
  required String nazwa,
  required int port,
  required Directory work,
}) =>
    AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: port,
      nameOverride: nazwa,
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'received-$port'),
      fileOfferPolicy: acceptAllFileOffers,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory work;
  late AppServices anna;
  late AppServices biuro;

  setUpAll(() async {
    work = Directory.systemTemp.createTempSync('chatt_shots');
    shots = Directory(p.join(
        Directory.current.path, '..', 'docs', 'screenshots', 'produkt'))
      ..createSync(recursive: true);

    await adb(['forward', 'tcp:$deviceProxyPort', 'tcp:$defaultTcpPort']);
    await adb(['reverse', 'tcp:47790', 'tcp:47790']);
    await adb(['reverse', 'tcp:47792', 'tcp:47792']);

    // Czysta aplikacja: zrzuty mają pokazywać demo, a nie czyjeś dane.
    // `pm clear` kasuje też zgodę na powiadomienia, a systemowe okienko
    // z pytaniem zasłoniłoby pierwszy ekran — dlatego przyznajemy ją z góry.
    await adb(['shell', 'pm', 'clear', appPackage]);
    await adb([
      'shell',
      'pm',
      'grant',
      appPackage,
      'android.permission.POST_NOTIFICATIONS',
    ]);
    await adb([
      'shell',
      'monkey',
      '-p',
      appPackage,
      '-c',
      'android.intent.category.LAUNCHER',
      '1',
    ]);
    await Future<void>.delayed(const Duration(seconds: 10));

    // Świeża instalacja idzie za językiem systemu (na emulatorze angielskim),
    // a dokumentacja jest po polsku. Przestawiamy w ustawieniach.
    await stuknij('Settings');
    // Drugie „System" na ekranie to lista języków; pierwsze należy do motywu.
    await stuknij('System', wystapienie: 1);
    await stuknij('Polish');
    await stuknij('Wstecz');

    anna = await rozmowca(nazwa: 'Laptop Anny', port: 47790, work: work);
    biuro = await rozmowca(nazwa: 'Komputer w biurze', port: 47792, work: work);
  });

  tearDownAll(() async {
    await anna.dispose();
    await biuro.dispose();
    await adb(['forward', '--remove', 'tcp:$deviceProxyPort']);
    await adb(['reverse', '--remove', 'tcp:47790']);
    await adb(['reverse', '--remove', 'tcp:47792']);
    // Nie zostawiamy demonstracyjnych rozmów na urządzeniu.
    await adb(['shell', 'pm', 'clear', appPackage]);
    work.deleteSync(recursive: true);
  });

  test('zrzuty ekranu do dokumentacji', () async {
    // --- Materiał na demo: dwie rozmowy, wiadomości w obie strony ----------
    final telefonUAnny =
        await anna.addPeerByAddress('127.0.0.1', deviceProxyPort);
    final rozmowaAnny = await anna.openConversationWith(telefonUAnny!);
    await anna.sendText(rozmowaAnny, 'Cześć! Widzisz mnie w sieci?');
    await anna.sendText(rozmowaAnny, 'Wysyłam Ci za chwilę zdjęcia z wyjazdu.');

    final telefonWBiurze =
        await biuro.addPeerByAddress('127.0.0.1', deviceProxyPort);
    final rozmowaBiura = await biuro.openConversationWith(telefonWBiurze!);
    await biuro.sendText(rozmowaBiura, 'Raport gotowy, leci do Ciebie.');

    await Future<void>.delayed(const Duration(seconds: 2));
    await zrzut('android_lista_rozmow');

    // --- Rozmowa w obie strony --------------------------------------------
    await stuknij('Laptop Anny');
    await zrzut('android_rozmowa');

    // --- Prośba o zgodę na plik -------------------------------------------
    final zdjecie = File(p.join(work.path, 'zdjecia-z-wyjazdu.zip'));
    zdjecie.writeAsBytesSync(List<int>.generate(2 * 1024 * 1024, (i) => i % 251));
    final wysylka = anna.sendFile(rozmowaAnny, zdjecie.path);
    await Future<void>.delayed(const Duration(seconds: 2));
    await zrzut('android_prosba_o_plik');
    await stuknij('Akceptuj');
    await wysylka;

    // --- Miniatura obrazka -------------------------------------------------
    // Drugi transfer idzie zaraz po pierwszym, przed pisaniem: klawiatura
    // zasłania kartę z pytaniem o zgodę i kolejny plik nie miałby jak wejść.
    final obrazek = File(p.join(work.path, 'zachod-slonca.png'));
    obrazek.writeAsBytesSync(await demoObrazek());
    final wysylkaObrazka = anna.sendFile(rozmowaAnny, obrazek.path);
    await Future<void>.delayed(const Duration(seconds: 2));
    await stuknij('Akceptuj');
    await wysylkaObrazka;
    await Future<void>.delayed(const Duration(seconds: 2));
    await zrzut('android_miniatura_obrazka');

    await napisz('Mam, dzieki!');
    await Future<void>.delayed(const Duration(seconds: 2));
    await zrzut('android_rozmowa_z_plikiem');

    // --- Menu wiadomości (kopiowanie, kasowanie u siebie) ------------------
    await przytrzymaj('Mam, dzieki', poziom: 0.85);
    // Bez tego sprawdzenia nieotwarte menu kończy się cichym cofnięciem
    // z ekranu rozmowy i mylącym błędem kilka kroków dalej.
    if (await znajdz('Usuń wiadomość', timeout: const Duration(seconds: 3)) ==
        null) {
      throw StateError('Przytrzymanie dymka nie otworzyło menu');
    }
    await zrzut('android_menu_wiadomosci');
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
    await Future<void>.delayed(const Duration(seconds: 1));

    // --- Szukanie w rozmowie -----------------------------------------------
    await stuknij('Szukaj w rozmowie');
    await wpisz('zdjecia');
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
    await Future<void>.delayed(const Duration(seconds: 1));
    await zrzut('android_szukanie_w_rozmowie');
    await stuknij('Zamknij');

    // --- Urządzenia w pobliżu ---------------------------------------------
    await stuknij('Wstecz');
    await stuknij('W pobliżu');
    await zrzut('android_urzadzenia_w_poblizu');

    // --- Ustawienia --------------------------------------------------------
    await stuknij('Wstecz');
    await stuknij('Ustawienia');
    await zrzut('android_ustawienia');

    // --- To samo w trybie ciemnym -----------------------------------------
    await stuknij('Ciemny');
    await stuknij('Wstecz');
    await zrzut('android_lista_rozmow_ciemny');
  });
}
