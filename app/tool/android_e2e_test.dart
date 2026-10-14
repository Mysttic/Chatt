// E2E na PRAWDZIWYM Androidzie: instancja hosta (ten proces) rozmawia
// z aplikacją zainstalowaną na urządzeniu/emulatorze.
//
// Emulator siedzi za NAT-em, więc zamiast Wi-Fi używamy tuneli adb:
//   adb forward tcp:47781 tcp:47780   host  -> aplikacja na urządzeniu
//   adb reverse tcp:47790 tcp:47790   urządzenie -> instancja hosta
// (test ustawia je sam). Instancja hosta MUSI stać na innym porcie niż
// aplikacja na urządzeniu: `adb reverse` na 47780 nie wstanie, bo ten port
// jest już zajęty przez aplikację. Na fizycznym telefonie w tej samej sieci
// Wi-Fi nic z tego nie jest potrzebne, tam działa discovery.
//
// Wymagania: zainstalowana aplikacja na urządzeniu (`flutter install`) oraz
// adb w PATH albo w zmiennej ADB. Test sam ją restartuje na starcie.
//
// Uruchomienie:
//   flutter test tool/android_e2e_test.dart
//
// Zmienne: ADB (ścieżka do adb), CHATT_DEVICE (id urządzenia z `adb devices`).
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Canvas, Color, Offset, Paint, Rect;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/data/db.dart';
import 'package:chatt/services/app_services.dart';

import 'uiautomator.dart';

/// Port instancji hosta (inny niż domyślny 47780 aplikacji na urządzeniu).
const int hostPort = 47790;

/// Port aplikacji na urządzeniu widziany z hosta (tunel adb forward).
///
/// Do nadpisania przez `CHATT_PROXY_PORT`, bo domyślny bywa zajęty przez
/// zwyczajnie uruchomionego Chatta na tej samej maszynie. Kiedyś kończyło się
/// to testem, który po cichu rozmawiał z aplikacją na pulpicie zamiast
/// z telefonem.
final int deviceProxyPort =
    int.tryParse(Platform.environment['CHATT_PROXY_PORT'] ?? '') ?? 47781;

const String appPackage = 'com.mysttic.chatt';

/// Świeży start aplikacji na urządzeniu. Bez tego kolejny przebieg zastaje
/// karty z poprzedniego (prośba o plik wisi dwie minuty, więc przerwany test
/// zostawia ją na ekranie) i klika w nieaktualną. Czekamy na `/info`, bo
/// dopiero odpowiedź stamtąd znaczy, że serwer w aplikacji wstał.
Future<void> restartApp() async {
  await adb(['shell', 'am', 'force-stop', appPackage]);
  await adb([
    'shell',
    'monkey',
    '-p',
    appPackage,
    '-c',
    'android.intent.category.LAUNCHER',
    '1',
  ]);
  final koniec = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(koniec)) {
    final client = HttpClient();
    try {
      final response = await (await client.get(
        '127.0.0.1',
        deviceProxyPort,
        '/info',
      ))
          .close();
      await response.drain<void>();
      if (response.statusCode == 200) return;
    } catch (_) {
      // Jeszcze nie wstała, próbujemy dalej.
    } finally {
      client.close(force: true);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('Aplikacja na urządzeniu nie odpowiedziała na /info '
      'przez minutę po starcie');
}

/// Zawartość pliku inna przy każdym uruchomieniu testu. Urządzenie trzyma
/// odebrane pliki między przebiegami, a zapowiedź wykrywa duplikat po sumie
/// kontrolnej, bo przy stałej treści drugi przebieg dostawałby „już to mam"
/// i nikt by o nic nie pytał.
List<int> swiezaTresc(int rozmiar) {
  final bajty = List<int>.generate(rozmiar, (i) => i % 251);
  // Znacznik czasu na początku: dwa przebiegi nie trafią w tę samą mikrosekundę.
  var znacznik = DateTime.now().microsecondsSinceEpoch;
  for (var i = 0; i < 8 && i < rozmiar; i++) {
    bajty[i] = znacznik & 0xff;
    znacznik >>= 8;
  }
  return bajty;
}

/// Klik w przycisk prośby o plik. Szukamy go po etykiecie, a nie po stałych
/// współrzędnych: karta zmienia wysokość (np. ostrzeżenie przy niesparowanym
/// urządzeniu), więc klikanie „na oko" trafiało raz w jeden przycisk, raz
/// w drugi. Enter tu nie zadziała: na Androidzie przycisk z autofocusem nie
/// dostaje fokusu klawiatury.
Future<void> tapOfferButton({required bool accept}) async {
  // Dwie etykiety, bo aplikacja na urządzeniu może być po polsku albo po
  // angielsku, a test nie ma powodu tego wymuszać.
  final labels = accept ? ['Akceptuj', 'Accept'] : ['Odrzuć', 'Reject'];
  for (final label in labels) {
    // Na drugą etykietę (inny język aplikacji) nie ma sensu czekać długo:
    // jeśli karta wisi, to z pierwszą albo z drugą, ale już teraz.
    final where = await findWidget(
      label,
      timeout: label == labels.first
          ? const Duration(seconds: 15)
          : const Duration(seconds: 1),
    );
    if (where == null) continue;
    await adb(['shell', 'input', 'tap', '${where.$1}', '${where.$2}']);
    return;
  }
  throw StateError('Nie znalazłem na ekranie przycisku ${labels.first}. '
      'Co widać: ${await widocznaTresc()}');
}

/// Obrazek na demo miniatury i zapisywania. Rysowany, bo zrzuty i testy mają
/// się odtwarzać bez wlekania za sobą cudzych zdjęć.
Future<List<int>> demoObrazek() async {
  const bok = 480.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, bok, bok));
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, bok, bok),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(bok, bok),
        const [Color(0xFF2E6BE6), Color(0xFF35C4C4)],
      ),
  );
  final obraz = await recorder.endRecording().toImage(bok.toInt(), bok.toInt());
  final dane = await obraz.toByteData(format: ui.ImageByteFormat.png);
  return dane!.buffer.asUint8List();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory work;
  late AppServices host;
  late Directory shots;

  setUpAll(() async {
    work = Directory.systemTemp.createTempSync('chatt_android');
    shots = Directory(p.join(Directory.current.path, '..', 'docs', 'screenshots', 'android'))
      ..createSync(recursive: true);

    // Tunele w obie strony (idempotentne).
    // Nieudany `forward` był tu wcześniej przemilczany, a to najgorszy
    // możliwy błąd w tym miejscu: gdy port jest już zajęty przez inną
    // instancję Chatta na tej maszynie (choćby zwykłą, uruchomioną aplikację
    // na Windows), test łączy się z NIĄ zamiast z telefonem. Wszystkie
    // asercje przechodzą, bo po drugiej stronie faktycznie stoi Chatt
    // z innym guidem, tylko urządzenia nikt nie dotknął. Kosztowało to
    // godzinę szukania nieistniejącego błędu zapisu na Androidzie.
    final forward = await adb(['forward', 'tcp:$deviceProxyPort', 'tcp:47780']);
    expect(forward.exitCode, 0,
        reason: 'port $deviceProxyPort jest zajęty, więc tunel do telefonu nie '
            'powstał i test rozmawiałby z czymś innym: ${forward.stderr}');
    final reverse = await adb(['reverse', 'tcp:$hostPort', 'tcp:$hostPort']);
    expect(reverse.exitCode, 0,
        reason: 'bez tunelu zwrotnego telefon nie odpowie hostowi: '
            '${reverse.stderr}');

    await restartApp();

    host = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: hostPort,
      nameOverride: 'Komputer PC',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'received'),
      // Host przyjmuje pliki bez pytania, a pytanie o zgodę testujemy po
      // stronie telefonu, na żywym UI.
      fileOfferPolicy: acceptAllFileOffers,
    );
  });

  tearDownAll(() async {
    await host.dispose();
    await adb(['forward', '--remove', 'tcp:$deviceProxyPort']);
    await adb(['reverse', '--remove', 'tcp:$hostPort']);
    work.deleteSync(recursive: true);
  });

  test('aplikacja na Androidzie odpowiada na /info i przyjmuje wiadomość',
      () async {
    final phone = await host.addPeerByAddress('127.0.0.1', deviceProxyPort);
    expect(phone, isNotNull,
        reason: 'serwer HTTP aplikacji na Androidzie musi odpowiedzieć na /info');
    expect(phone!.guid, isNot(host.identity.guid),
        reason: 'to musi być telefon, a nie pętla na nas samych');
    expect(phone.port, deviceProxyPort,
        reason: 'zapisany port to ten, pod którym telefon jest osiągalny '
            '(tunel), a nie ten, którym się przedstawia');

    final conversation = await host.openConversationWith(phone);
    await host.sendText(conversation, 'Hej z komputera! Widzisz to na telefonie?');

    final sent = (await host.db.watchMessages(conversation).first).last;
    expect(sent.status, MessageStatus.delivered,
        reason: 'Android potwierdził odbiór (ACK)');

    await Future<void>.delayed(const Duration(seconds: 2));
    await screenshot(p.join(shots.path, 'and1_wiadomosc_odebrana.png'));
  });

  test('plik: telefon pyta o zgodę i dopiero potem odbiera bajty', () async {
    final phone = (await host.db.watchPeers().first).first;
    final conversation = await host.openConversationWith(phone);

    final source = File(p.join(work.path, 'raport-z-komputera.bin'));
    source.writeAsBytesSync(swiezaTresc(1200 * 1024));

    // Wysyłka czeka na decyzję użytkownika, nie blokujemy się na niej.
    final sending = host.sendFile(conversation, source.path);

    // Prośba o zgodę powinna wyskoczyć na telefonie.
    await Future<void>.delayed(const Duration(seconds: 3));
    await screenshot(p.join(shots.path, 'and2_prosba_o_plik.png'));

    await tapOfferButton(accept: true);
    await sending;

    final message = (await host.db.watchMessages(conversation).first).last;
    expect(message.kind, MessageKind.file);
    expect(message.status, MessageStatus.delivered,
        reason: 'po akceptacji plik dochodzi w całości (sha256 się zgadza)');

    // Plik naprawdę leży w katalogu aplikacji na urządzeniu (nie tylko
    // „nadawca uznał, że dostarczył").
    final listing = await adb([
      'shell',
      'run-as',
      'com.mysttic.chatt',
      'ls',
      '-l',
      // files/, nie app_flutter/, bo tylko stamtąd FileProvider potrafi
      // wypuścić plik do innej aplikacji.
      '/data/data/com.mysttic.chatt/files/Chatt/received',
    ]);
    expect(listing.stdout.toString(), contains('raport-z-komputera.bin'));

    await Future<void>.delayed(const Duration(seconds: 2));
    await screenshot(p.join(shots.path, 'and3_plik_odebrany.png'));
  });

  test('zapisanie obrazka wynosi go z katalogu aplikacji do Zdjęć', () async {
    const galeria = '/sdcard/Pictures/Chatt';
    const nazwa = 'zdjecie-do-zapisania.png';
    // Po poprzednim przebiegu plik mógł zostać, inaczej test przeszedłby
    // na cudzym wyniku.
    await adb(['shell', 'rm', '-f', '$galeria/$nazwa']);

    final phone = (await host.db.watchPeers().first).first;
    final conversation = await host.openConversationWith(phone);

    final source = File(p.join(work.path, nazwa));
    source.writeAsBytesSync(await demoObrazek());
    final sending = host.sendFile(conversation, source.path);
    await Future<void>.delayed(const Duration(seconds: 3));
    await tapOfferButton(accept: true);
    await sending;
    await Future<void>.delayed(const Duration(seconds: 2));

    // Do dymka z plikiem trzeba wejść w rozmowę: wiersz listy Flutter scala
    // w jeden węzeł razem z podglądem i godziną, więc szukamy po fragmencie.
    await stuknijEtykiete(['Komputer PC'], fragment: true);
    await Future<void>.delayed(const Duration(seconds: 2));
    // Przycisków zapisu jest w rozmowie tyle, ile plików, bierzemy ten przy
    // najnowszej wiadomości, czyli przy obrazku.
    await stuknijEtykiete(['Zapisz na urządzeniu', 'Save to device'],
        ostatni: true);
    await Future<void>.delayed(const Duration(seconds: 2));
    // Zrzut przed asercją: gdy zapis się nie uda, na ekranie wisi komunikat
    // z powodem i bez tego zrzutu trzeba by zgadywać.
    await screenshot(p.join(shots.path, 'and22_zapisany_obrazek.png'));

    final listing = await adb(['shell', 'ls', '-l', galeria]);
    expect(listing.stdout.toString(), contains(nazwa),
        reason: 'zapisany obrazek ma wylądować w Zdjęciach, tam gdzie widzi '
            'go galeria, a nie tylko w katalogu aplikacji');

    await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
  });

  test('odmowa na telefonie kończy się statusem "nie dostarczono"', () async {
    final phone = (await host.db.watchPeers().first).first;
    final conversation = await host.openConversationWith(phone);

    final source = File(p.join(work.path, 'niechciany.bin'));
    source.writeAsBytesSync(swiezaTresc(64 * 1024));

    final sending = host.sendFile(conversation, source.path);
    await Future<void>.delayed(const Duration(seconds: 3));
    await screenshot(p.join(shots.path, 'and4_odmowa.png'));
    await tapOfferButton(accept: false);
    await sending;

    final message = (await host.db.watchMessages(conversation).first).last;
    expect(message.status, MessageStatus.failed,
        reason: 'odmowa odbiorcy = wiadomość niedostarczona, do ponowienia');
  });
}
