// Ręczne sprawdzenie discovery w prawdziwej sieci: ten komputer rozgłasza
// zapytanie po UDP i wypisuje, kto się odezwał. Emulator jest za NAT-em, więc
// tego jednego nie da się sprawdzić inaczej niż na sprzęcie w tym samym Wi-Fi.
//
// Warunki: aplikacja uruchomiona na drugim urządzeniu, oba w tej samej
// podsieci, na Windows przepuszczony ruch przychodzący UDP dla chatt.exe.
//
// Uruchomienie:
//   flutter test tool/wifi_discovery_check.dart
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/services/app_services.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('skan znajduje inne urządzenie w tej samej sieci', () async {
    final work = Directory.systemTemp.createTempSync('chatt_wifi');
    // Port inny niż domyślny, żeby nie wchodzić w drogę aplikacji, która
    // może już działać na tym komputerze.
    final host = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 47791,
      nameOverride: 'Skaner',
      receivedDirOverride: p.join(work.path, 'received'),
    );
    addTearDown(() async {
      await host.dispose();
      work.deleteSync(recursive: true);
    });

    print('adresy tego komputera: ${await host.localAddresses()}');
    final found = await host.scan();
    for (final peer in found) {
      print('znaleziono: ${peer.name} ${peer.host}:${peer.tcpPort} '
          'guid=${peer.guid}');
    }
    expect(found, isNotEmpty,
        reason: 'nikt nie odpowiedział na broadcast — sprawdź zaporę i to, '
            'czy oba urządzenia są w tej samej podsieci');
  });
}
