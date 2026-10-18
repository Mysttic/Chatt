import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/network/bt_transport.dart';
import 'package:chatt/network/transport.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/ui/screens/nearby_screen.dart';
import 'package:chatt/ui/screens/settings_screen.dart';
import 'package:chatt/ui/widgets/common.dart';
import 'package:chatt/ui/widgets/protocol_badge.dart';

/// Interfejsowa połowa dodatku Bluetooth: bez dodatku żaden ekran poza jego
/// kartą nie pokazuje niczego z Bluetootha. Osobny plik, bo `testWidgets`
/// podmienia HttpClient dla całego pliku.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory katalog;

  setUp(() {
    katalog = Directory.systemTemp.createTempSync('chatt_dodatek_ui_');
    // Karta dodatku pokazuje przełącznik tylko tam, gdzie jest kod natywny.
    BtChannel.debugSupported = true;
  });
  tearDown(() {
    BtChannel.debugSupported = null;
    katalog.deleteSync(recursive: true);
  });

  Future<AppServices> uruchom(WidgetTester tester) async =>
      (await tester.runAsync(() => AppServices.start(
            executor: NativeDatabase.memory(),
            portOverride: 0,
            nameOverride: 'Alicja',
            enableDiscovery: false,
            receivedDirOverride: '${katalog.path}/Alicja',
          )))!;

  /// Drzewo schodzi przed zamknięciem stosu: ekrany odpinają słuchaczy,
  /// a strumienie z bazy sprzątają się swoim licznikiem.
  Future<void> sprzatnij(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(services.dispose);
  }

  Widget osadz(AppServices services, Widget child) => ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      );

  testWidgets('znacznik drogi bez dodatku nie zajmuje miejsca', (tester) async {
    final services = await uruchom(tester);
    final peer = (await tester.runAsync(() => services.db.upsertPeer(
          guid: 'guid-bartek',
          name: 'Bartek',
          welcomeMessage: '',
          host: '',
          port: 0,
          btAddress: '70:D8:C2:64:D9:B2',
          protocol: PeerProtocol.bluetooth.index,
        )))!;

    await tester.pumpWidget(osadz(
      services,
      Align(
        alignment: Alignment.topLeft,
        child: ProtocolBadge(peer: peer, padding: const EdgeInsets.only(left: 8)),
      ),
    ));
    expect(tester.getSize(find.byType(ProtocolBadge)), Size.zero,
        reason: 'razem z odstępem');
    expect(find.byIcon(Icons.bluetooth), findsNothing);

    // Ten sam znacznik z dodatkiem jest widoczny.
    services.bluetoothAddon.value = true;
    await tester.pump();
    expect(find.byIcon(Icons.bluetooth), findsOneWidget);

    await sprzatnij(tester, services);
  });

  testWidgets('W pobliżu bez dodatku nie ma wyboru drogi', (tester) async {
    final services = await uruchom(tester);
    await tester.pumpWidget(osadz(services, const NearbyScreen()));
    await tester.pump();
    expect(find.byType(SegmentedButton<PeerProtocol>), findsNothing);
    expect(find.byIcon(Icons.wifi_tethering), findsOneWidget);

    services.bluetoothAddon.value = true;
    await tester.pump();
    expect(find.byType(SegmentedButton<PeerProtocol>), findsOneWidget);

    services.bluetoothAddon.value = false;
    await tester.pump();
    expect(find.byType(SegmentedButton<PeerProtocol>), findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets('przycisk widoczności tylko na telefonie, przy radiu i Bluetoothcie',
      (tester) async {
    final services = await uruchom(tester);
    // Ekran wchodzi bez dodatku, więc odświeżenie stanu przy wejściu nie
    // pyta kanału; stan radia ustawia dalej sam test.
    await tester.pumpWidget(osadz(services, const NearbyScreen()));
    await tester.pump();
    const telefon = BtStatus(
      available: true,
      enabled: true,
      granted: true,
      canShowSelf: true,
    );
    services.bluetoothAddon.value = true;
    services.bluetoothRunning.value = true;
    services.bluetoothStatus.value = telefon;
    await tester.pump();
    final przycisk = find.text('Show this phone nearby');
    expect(przycisk, findsNothing, reason: 'wybrana jest sieć');

    await tester.tap(find.text('Bluetooth'));
    await tester.pump();
    expect(przycisk, findsOneWidget);

    // Widoczny telefon dostaje napis w miejsce przycisku.
    services.bluetoothStatus.value = const BtStatus(
      available: true,
      enabled: true,
      granted: true,
      canShowSelf: true,
      visible: true,
    );
    await tester.pump();
    expect(przycisk, findsNothing);
    expect(find.byIcon(Icons.visibility), findsOneWidget);

    // Windows: komputer jest widoczny przez cały czas dodatku.
    services.bluetoothStatus.value =
        const BtStatus(available: true, enabled: true, granted: true);
    await tester.pump();
    expect(przycisk, findsNothing);
    expect(find.byIcon(Icons.visibility), findsNothing);

    // Radio nie stoi: nie ma czego pokazywać.
    services.bluetoothStatus.value = telefon;
    services.bluetoothRunning.value = false;
    await tester.pump();
    expect(przycisk, findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets('karta dodatku bez dodatku to sam przełącznik', (tester) async {
    final services = await uruchom(tester);
    await tester.pumpWidget(osadz(
      services,
      const SingleChildScrollView(child: BluetoothAddonCard()),
    ));
    await tester.pump();

    final przelacznik = find.widgetWithIcon(SwitchListTile, Icons.bluetooth);
    expect(przelacznik, findsOneWidget);
    expect(tester.widget<SwitchListTile>(przelacznik).value, isFalse);
    expect(find.widgetWithIcon(SwitchListTile, Icons.wifi), findsNothing,
        reason: 'przełącznik sieci należy do dodatku');

    services.bluetoothAddon.value = true;
    await tester.pump();
    expect(find.widgetWithIcon(SwitchListTile, Icons.wifi), findsOneWidget);

    await sprzatnij(tester, services);
  });

  test('adres radia rozmówcy widać tylko z dodatkiem', () async {
    final db = ChattDb(NativeDatabase.memory());
    addTearDown(db.close);
    final radiowy = await db.upsertPeer(
      guid: 'guid-radio',
      name: 'Radio',
      welcomeMessage: '',
      host: '',
      port: 0,
      btAddress: 'AA:BB:CC:DD:EE:FF',
    );
    final sieciowy = await db.upsertPeer(
      guid: 'guid-siec',
      name: 'Siec',
      welcomeMessage: '',
      host: '192.168.0.7',
      port: 47777,
    );

    expect(peerAddressLabel(radiowy, radio: false), '');
    expect(peerAddressLabel(radiowy, radio: true), 'AA:BB:CC:DD:EE:FF');
    expect(peerAddressLabel(sieciowy, radio: false), '192.168.0.7:47777');
  });
}
