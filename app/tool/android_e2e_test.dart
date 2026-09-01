// E2E na PRAWDZIWYM Androidzie: instancja hosta (ten proces) rozmawia
// z aplikacją zainstalowaną na urządzeniu/emulatorze.
//
// Emulator siedzi za NAT-em, więc zamiast Wi-Fi używamy tuneli adb:
//   adb forward tcp:47781 tcp:47780   host  -> aplikacja na urządzeniu
//   adb reverse tcp:47790 tcp:47790   urządzenie -> instancja hosta
// (test ustawia je sam). Instancja hosta MUSI stać na innym porcie niż
// aplikacja na urządzeniu: `adb reverse` na 47780 nie wstanie, bo ten port
// jest już zajęty przez aplikację. Na fizycznym telefonie w tej samej sieci
// Wi-Fi nic z tego nie jest potrzebne — tam działa discovery.
//
// Wymagania: uruchomiona aplikacja na urządzeniu (`flutter install` +
// uruchomienie z ekranu) oraz adb w PATH albo w zmiennej ADB.
//
// Uruchomienie:
//   flutter test tool/android_e2e_test.dart
//
// Zmienne: ADB (ścieżka do adb), CHATT_DEVICE (id urządzenia z `adb devices`).
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/data/db.dart';
import 'package:chatt/services/app_services.dart';

/// Port instancji hosta (inny niż domyślny 47780 aplikacji na urządzeniu).
const int hostPort = 47790;

/// Port aplikacji na urządzeniu widziany z hosta (tunel adb forward).
const int deviceProxyPort = 47781;

String get _adb => Platform.environment['ADB'] ?? 'adb';
String get _device => Platform.environment['CHATT_DEVICE'] ?? 'emulator-5554';

Future<ProcessResult> adb(List<String> args) =>
    Process.run(_adb, ['-s', _device, ...args]);

/// Rozmiar ekranu w pikselach urządzenia (do klikania po współrzędnych).
Future<(int, int)> screenSize() async {
  final out = (await adb(['shell', 'wm', 'size'])).stdout as String;
  final match = RegExp(r'(\d+)x(\d+)').firstMatch(out);
  return (int.parse(match!.group(1)!), int.parse(match.group(2)!));
}

/// Klik w przycisk prośby o plik. Karta wisi u góry ekranu, „Akceptuj" jest
/// skrajnie po prawej, „Odrzuć" obok. Enter tu nie zadziała: na Androidzie
/// przycisk z autofocusem nie dostaje fokusu klawiatury.
Future<void> tapOfferButton({required bool accept}) async {
  final (width, height) = await screenSize();
  final x = (width * (accept ? 0.82 : 0.60)).round();
  final y = (height * 0.171).round();
  await adb(['shell', 'input', 'tap', '$x', '$y']);
}

/// Zrzut ekranu urządzenia do pliku (do dokumentacji i podglądu, co się stało).
Future<void> screenshot(String path) async {
  final result = await Process.run(_adb, ['-s', _device, 'exec-out', 'screencap', '-p'],
      stdoutEncoding: null);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(result.stdout as List<int>);
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
    await adb(['forward', 'tcp:$deviceProxyPort', 'tcp:47780']);
    final reverse = await adb(['reverse', 'tcp:$hostPort', 'tcp:$hostPort']);
    expect(reverse.exitCode, 0,
        reason: 'bez tunelu zwrotnego telefon nie odpowie hostowi: '
            '${reverse.stderr}');

    host = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: hostPort,
      nameOverride: 'Komputer PC',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'received'),
      // Host przyjmuje pliki bez pytania — pytanie o zgodę testujemy po
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
    source.writeAsBytesSync(List<int>.generate(1200 * 1024, (i) => i % 251));

    // Wysyłka czeka na decyzję użytkownika — nie blokujemy się na niej.
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
      // files/, nie app_flutter/ — tylko stamtąd FileProvider potrafi
      // wypuścić plik do innej aplikacji.
      '/data/data/com.mysttic.chatt/files/Chatt/received',
    ]);
    expect(listing.stdout.toString(), contains('raport-z-komputera.bin'));

    await Future<void>.delayed(const Duration(seconds: 2));
    await screenshot(p.join(shots.path, 'and3_plik_odebrany.png'));
  });

  test('odmowa na telefonie kończy się statusem "nie dostarczono"', () async {
    final phone = (await host.db.watchPeers().first).first;
    final conversation = await host.openConversationWith(phone);

    final source = File(p.join(work.path, 'niechciany.bin'));
    source.writeAsBytesSync(List<int>.filled(64 * 1024, 7));

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
