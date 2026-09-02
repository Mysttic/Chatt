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
    await napisz('Mam, dzieki!');
    await Future<void>.delayed(const Duration(seconds: 2));
    await zrzut('android_rozmowa_z_plikiem');

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
