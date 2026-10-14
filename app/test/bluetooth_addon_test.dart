import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/network/bt_transport.dart';
import 'package:chatt/network/transport.dart';
import 'package:chatt/services/app_services.dart';

/// Dodatek Bluetooth (Ustawienia, sekcja „Dodatki") jest jedynym włącznikiem
/// całej funkcji. Wyłączony znaczy, że Bluetootha w aplikacji nie ma: kanał
/// natywny nie dostaje ani jednego wywołania, a sieć lokalna chodzi zawsze.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Wiązanie testowe podmienia HttpClient na taki, który na wszystko
  // odpowiada 400. Tu dwie instancje rozmawiają przez prawdziwe gniazda.
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const kanal = MethodChannel('chatt/bluetooth');
  const siec = IpRoute('127.0.0.1', 47777);

  /// Radio gotowe do pracy.
  const radioGotowe = <String, Object?>{
    'available': true,
    'enabled': true,
    'granted': true,
    'canScan': true,
    'locationOn': true,
    'name': 'Testowy',
    'address': '70:D8:C2:64:D9:B1',
  };

  /// Radio wyłączone w systemie: dodatek się włącza, transport nie wstaje.
  const radioWylaczone = <String, Object?>{
    'available': true,
    'enabled': false,
    'granted': true,
  };

  final wywolania = <String>[];

  /// Kolejne wartości `on` z wywołań `discoverable`.
  final wykrywalnosc = <bool>[];
  var radio = radioGotowe;

  /// Czy natywny nasłuch żyje, tak jak melduje go `linkPoll`.
  var nasluch = true;

  /// Gdy ustawione, `linkStart` czeka na nie: tak wygląda radio, które
  /// podnosi się dłuższą chwilę.
  Completer<void>? wstrzymajStart;
  Completer<void>? startDotarl;
  late Directory katalog;

  setUp(() {
    wywolania.clear();
    wykrywalnosc.clear();
    radio = radioGotowe;
    nasluch = true;
    wstrzymajStart = null;
    startDotarl = null;
    katalog = Directory.systemTemp.createTempSync('chatt_dodatek_');
    // Udajemy platformę z kodem natywnym także na Linuksie z CI. Inaczej kanał
    // milczałby z powodu platformy i test niczego by nie dowodził.
    BtChannel.debugSupported = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, (call) async {
      wywolania.add(call.method);
      if (call.method == 'discoverable') {
        wykrywalnosc.add((call.arguments as Map)['on'] == true);
      }
      if (call.method == 'linkStart') {
        final czekaj = wstrzymajStart;
        if (czekaj != null) {
          startDotarl?.complete();
          await czekaj.future;
        }
      }
      return switch (call.method) {
        'status' => radio,
        'linkStart' => const <String, Object?>{'listening': true},
        'linkPoll' => <String, Object?>{'listening': nasluch},
        'discoverable' || 'linkStop' => true,
        _ => null,
      };
    });
  });

  tearDown(() {
    BtChannel.debugSupported = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, null);
    katalog.deleteSync(recursive: true);
  });

  Future<AppServices> instancja(String nazwa, {File? plik}) async {
    final services = await AppServices.start(
      executor: plik == null ? NativeDatabase.memory() : NativeDatabase(plik),
      portOverride: 0,
      nameOverride: nazwa,
      enableDiscovery: false,
      receivedDirOverride: '${katalog.path}/$nazwa',
    );
    addTearDown(services.dispose);
    return services;
  }

  /// Linkstart wstrzymany do odwołania. Zwraca to, co go puszcza.
  Completer<void> wstrzymanyStart() {
    final pusc = Completer<void>();
    wstrzymajStart = pusc;
    startDotarl = Completer<void>();
    return pusc;
  }

  test('wyłączony dodatek nie dotyka kanału Bluetooth', () async {
    final services = await instancja('Alicja');

    expect(services.bluetoothAddon.value, isFalse);
    await services.refreshBluetoothStatus();
    expect(await services.startBluetooth(), isFalse);
    expect(await services.scanBluetooth(), isEmpty);
    expect(await services.addPeerByBluetooth('70:D8:C2:64:D9:B1'), isNull);

    expect(wywolania, isEmpty);
    expect(services.bluetoothRunning.value, isFalse);
  });

  test('dodatek podnosi radio, a wyłączony gasi je i więcej go nie rusza',
      () async {
    final services = await instancja('Alicja');

    expect(await services.setBluetoothAddon(true), isTrue);
    expect(services.bluetoothRunning.value, isTrue);
    expect(wywolania, containsAll(['status', 'linkStart']));
    expect(wykrywalnosc, [true]);

    // Włączony transport odpytuje stronę natywną o łącza.
    await Future<void>.delayed(btPollInterval * 3);
    expect(wywolania, contains('linkPoll'));

    wywolania.clear();
    await services.setBluetoothAddon(false);
    expect(services.bluetoothRunning.value, isFalse);
    expect(wykrywalnosc, [true, false],
        reason: 'wyłączenie gasi wykrywalność komputera');
    expect(wywolania, contains('linkStop'));

    // Po wyłączeniu cisza: żadnego odpytywania łączy, żadnego pytania o stan.
    wywolania.clear();
    await Future<void>.delayed(btPollInterval * 3);
    await services.refreshBluetoothStatus();
    expect(await services.scanBluetooth(), isEmpty);
    expect(wywolania, isEmpty);

    final ustawienia = await services.db.getSettings();
    expect(ustawienia!.bluetoothEnabled, isFalse);
  });

  test('wyłączenie dodatku przywraca sieć, także w bazie', () async {
    radio = radioWylaczone;
    final services = await instancja('Alicja');

    expect(await services.setBluetoothAddon(true), isFalse,
        reason: 'radio wyłączone w systemie');
    expect(services.bluetoothAddon.value, isTrue);

    // Z dodatkiem sieć da się zgasić.
    await services.db.saveWifiEnabled(false);
    await services.db.watchSettings().firstWhere((s) => !s.wifiEnabled);
    await pumpEventQueue();
    expect(services.client.transportFor(siec), isNull);

    await services.setBluetoothAddon(false);
    expect(services.bluetoothAddon.value, isFalse);
    expect(services.client.transportFor(siec), isNotNull);
    final ustawienia = await services.db.getSettings();
    expect(ustawienia!.bluetoothEnabled, isFalse);
    expect(ustawienia.wifiEnabled, isTrue);
  });

  test('bez dodatku sieć chodzi, cokolwiek leży w bazie', () async {
    final alice = await instancja('Alicja');
    final bob = await instancja('Bartek');

    // Stan, którego bez dodatku nie da się ustawić z interfejsu, ale który
    // baza potrafi pamiętać: sieć zgaszona przy wyłączonym dodatku.
    await alice.db.saveWifiEnabled(false);
    await alice.db.watchSettings().firstWhere((s) => !s.wifiEnabled);
    await pumpEventQueue();
    expect(alice.client.transportFor(siec), isNotNull);

    final bobAtAlice =
        await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    expect(bobAtAlice, isNotNull);
    final rozmowa = await alice.openConversationWith(bobAtAlice!);
    await alice.sendText(rozmowa, 'Cześć');
    final wiadomosci = await alice.db.watchMessages(rozmowa).first;
    expect(wiadomosci.single.status, MessageStatus.delivered);
    expect(wywolania, isEmpty);
  });

  test('zapis w bazie nie podnosi radia za plecami dodatku', () async {
    final services = await instancja('Alicja');

    // Spóźnione albo obce zdarzenie z bazy: przełącznik jest włączony
    // w wierszu, ale nikt nie przełączył dodatku.
    await services.db.saveBluetoothAddon(true);
    await services.db.watchSettings().firstWhere((s) => s.bluetoothEnabled);
    await pumpEventQueue();

    expect(services.bluetoothAddon.value, isFalse);
    expect(services.bluetoothRunning.value, isFalse);
    expect(wywolania, isEmpty);
  });

  test('wyłączenie w trakcie podnoszenia zostawia radio zgaszone', () async {
    final services = await instancja('Alicja');
    final pusc = wstrzymanyStart();

    final wlaczanie = services.setBluetoothAddon(true);
    await startDotarl!.future;
    final wylaczanie = services.setBluetoothAddon(false);
    pusc.complete();

    // Przełączenia idą po kolei: radio wstaje, po czym gaśnie.
    expect(await wlaczanie, isTrue);
    await wylaczanie;
    expect(services.bluetoothAddon.value, isFalse);
    expect(services.bluetoothRunning.value, isFalse);
    expect(wywolania.last, 'linkStop');
    expect(wykrywalnosc.last, isFalse);
    expect((await services.db.getSettings())!.bluetoothEnabled, isFalse);

    wywolania.clear();
    await Future<void>.delayed(btPollInterval * 3);
    expect(wywolania, isEmpty);
  });

  test('szybkie „wyłącz, włącz" w trakcie podnoszenia kończy się włączonym',
      () async {
    final services = await instancja('Alicja');
    final pusc = wstrzymanyStart();

    final a = services.setBluetoothAddon(true);
    await startDotarl!.future;
    final b = services.setBluetoothAddon(false);
    final c = services.setBluetoothAddon(true);
    await pumpEventQueue();
    wstrzymajStart = null;
    pusc.complete();
    await Future.wait([a, b, c]);

    // Pamięć, baza i radio mówią to samo, co ostatnie kliknięcie.
    expect(services.bluetoothAddon.value, isTrue);
    expect((await services.db.getSettings())!.bluetoothEnabled, isTrue);
    expect(services.bluetoothRunning.value, isTrue);
  });

  test('radio włączone w systemie podnosi transport przy odświeżeniu',
      () async {
    radio = radioWylaczone;
    final services = await instancja('Alicja');
    expect(await services.setBluetoothAddon(true), isFalse);
    expect(wywolania, isNot(contains('linkStart')));

    radio = radioGotowe;
    await services.refreshBluetoothStatus();
    // Dołącza do podnoszenia, które ruszyło przy odświeżeniu.
    expect(await services.startBluetooth(), isTrue);
    expect(services.bluetoothRunning.value, isTrue);
    expect(wywolania.where((m) => m == 'linkStart'), hasLength(1));
  });

  test('nasłuch, który padł po stronie natywnej, wstaje z powrotem', () async {
    final services = await instancja('Alicja');
    expect(await services.setBluetoothAddon(true), isTrue);
    expect(wywolania.where((m) => m == 'linkStart'), hasLength(1));

    // Radio zgaszone i włączone w systemie: natywny nasłuch nie żyje, choć
    // transport po stronie Darta dalej stoi.
    nasluch = false;
    await Future<void>.delayed(btPollInterval * 3);
    expect(wywolania.where((m) => m == 'linkStart'), hasLength(2));
    expect(wykrywalnosc, [true, true],
        reason: 'wykrywalność wraca razem z nasłuchem');
  });

  group('dodatek zapisany w bazie', () {
    /// Pierwsze uruchomienie: dodatek włączony, sieć zgaszona, aplikacja
    /// zamknięta. Plik zostaje jak u użytkownika.
    Future<File> zapisanyDodatek() async {
      final plik = File('${katalog.path}/chatt.db');
      final pierwsza = await AppServices.start(
        executor: NativeDatabase(plik),
        portOverride: 0,
        nameOverride: 'Alicja',
        enableDiscovery: false,
        receivedDirOverride: '${katalog.path}/pierwsza',
      );
      expect(await pierwsza.setBluetoothAddon(true), isTrue);
      await pierwsza.db.saveWifiEnabled(false);
      await pierwsza.dispose();
      return plik;
    }

    test('wstaje razem z aplikacją', () async {
      final plik = await zapisanyDodatek();
      wywolania.clear();
      final druga = await instancja('Alicja', plik: plik);
      expect(druga.bluetoothAddon.value, isTrue);
      expect(druga.bluetoothRunning.value, isTrue);
      expect(wywolania, containsAll(['status', 'linkStart']));
      expect(druga.client.transportFor(siec), isNull,
          reason: 'sieć zgaszona przy dodatku zostaje zgaszona');
    });

    test('na platformie bez kodu natywnego nie istnieje', () async {
      final plik = await zapisanyDodatek();
      BtChannel.debugSupported = false;
      wywolania.clear();
      final druga = await instancja('Alicja', plik: plik);
      expect(druga.bluetoothAddon.value, isFalse);
      expect(druga.bluetoothRunning.value, isFalse);
      expect(druga.client.transportFor(siec), isNotNull);
      expect(await druga.setBluetoothAddon(true), isFalse);
      expect(wywolania, isEmpty);
    });
  });
}
