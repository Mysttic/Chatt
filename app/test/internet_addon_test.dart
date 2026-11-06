import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/network/transport.dart';
import 'package:chatt/services/app_services.dart';

/// Dodatek drogi internetowej w [AppServices]: przełącznik włącza i wyłącza
/// transport, zapisuje się w bazie, a trasa internetowa pojawia się tylko dla
/// rozmówcy z zieloną tarczą. Bez prawdziwego ruchu: samo wpięcie w resztę.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory katalog;

  setUp(() => katalog = Directory.systemTemp.createTempSync('chatt_inet_'));
  tearDown(() => katalog.deleteSync(recursive: true));

  Future<AppServices> instancja() async {
    final services = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Ja',
      enableDiscovery: false,
      receivedDirOverride: katalog.path,
    );
    addTearDown(services.dispose);
    return services;
  }

  test('domyślnie wyłączony, włącza się i zapisuje w bazie', () async {
    final s = await instancja();
    expect(s.internetAddon.value, isFalse);

    final ok = await s.setInternetAddon(true);
    expect(ok, isTrue);
    expect(s.internetAddon.value, isTrue);
    expect(s.internetRunning.value, isTrue);
    expect((await s.db.getSettings())!.internetEnabled, isTrue);

    await s.setInternetAddon(false);
    expect(s.internetAddon.value, isFalse);
    expect(s.internetRunning.value, isFalse);
    expect((await s.db.getSettings())!.internetEnabled, isFalse);
  });

  test('trasa internetowa tylko dla potwierdzonego rozmówcy i tylko przy '
      'włączonym dodatku', () async {
    final s = await instancja();
    await s.db.upsertPeer(
      guid: 'guid-goly',
      name: 'Bez tarczy',
      welcomeMessage: '',
      host: '192.168.0.5',
      port: 47780,
    );
    final pewny = await s.db.upsertPeer(
      guid: 'guid-pewny',
      name: 'Z tarczą',
      welcomeMessage: '',
      host: '192.168.0.6',
      port: 47780,
    );
    await s.db.setPeerVerified(pewny.id, true);
    final pewnyWiersz = (await s.db.peerByGuid('guid-pewny'))!;
    final golyWiersz = (await s.db.peerByGuid('guid-goly'))!;

    // Dodatek wyłączony: żadnej trasy internetowej.
    expect(
        s.routesOf(pewnyWiersz).whereType<InternetRoute>(), isEmpty);

    await s.setInternetAddon(true);
    // Potwierdzony dostaje trasę internetową; niepotwierdzony nie.
    expect(s.routesOf(pewnyWiersz).whereType<InternetRoute>(), hasLength(1));
    expect(s.routesOf(golyWiersz).whereType<InternetRoute>(), isEmpty);

    // Sieć lokalna zostaje pierwsza (szybsza), internet na końcu.
    final trasy = s.routesOf(pewnyWiersz);
    expect(trasy.first, isA<IpRoute>());
    expect(trasy.last, isA<InternetRoute>());
    expect((trasy.last as InternetRoute).guid, 'guid-pewny');
  });
}
