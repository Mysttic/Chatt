import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/ui/styles.dart';
import 'package:chatt/ui/widgets/security_sheet.dart';

/// Panel bezpieczeństwa dla urządzenia bez klucza w bazie. Świeżo dodane
/// z „W pobliżu” nie może być nazwane starszą wersją bez szyfrowania: to
/// wolno dopiero wtedy, gdy `/info` odpowiedziało bez klucza.
void main() {
  final teksty = lookupAppLocalizations(const Locale('en'));
  late Directory katalog;

  setUp(() => katalog = Directory.systemTemp.createTempSync('chatt_panel'));
  tearDown(() => katalog.deleteSync(recursive: true));

  Future<AppServices> uruchom(WidgetTester tester) async =>
      (await tester.runAsync(() => AppServices.start(
            executor: NativeDatabase.memory(),
            portOverride: 0,
            nameOverride: 'Bartek',
            enableDiscovery: false,
            receivedDirOverride: '${katalog.path}/Bartek',
          )))!;

  Future<void> sprzatnij(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(services.dispose);
  }

  /// Alicja tak, jak zapisuje ją discovery: bez klucza. [klucz] przypina go.
  Future<Peer> alicja(WidgetTester tester, AppServices s,
          {String? klucz}) async =>
      (await tester.runAsync(() async {
        await s.db.upsertPeer(
          guid: 'guid-alicja',
          name: 'Alicja',
          welcomeMessage: '',
          host: '',
          port: 0,
        );
        final peer = (await s.db.peerByGuid('guid-alicja'))!;
        if (klucz != null) await s.db.setPeerKey(peer.id, klucz);
        return s.db.peerByGuid('guid-alicja');
      }))!;

  Future<void> otworzPanel(
      WidgetTester tester, AppServices s, Peer peer) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(s)],
      child: MaterialApp(
        theme: chattTheme(AppStyle.values.first, Brightness.light),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showSecuritySheet(
                  context,
                  peer: peer,
                  onPair: () {},
                  onScan: () {},
                ),
                child: const Text('panel'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('panel'));
    await tester.pumpAndSettle();
  }

  testWidgets('bez klucza i bez odpowiedzi /info: klucz jeszcze nieznany',
      (tester) async {
    final services = await uruchom(tester);
    await otworzPanel(tester, services, await alicja(tester, services));

    expect(find.text(teksty.securityKeyUnknownTitle), findsOneWidget);
    expect(find.text(teksty.securityKeyUnknownBody), findsOneWidget);
    expect(find.text(teksty.securityNoEncryptionTitle), findsNothing);
    expect(find.text(teksty.securityNoEncryptionBody), findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets('/info bez klucza przy otwartym panelu: starsza wersja',
      (tester) async {
    final services = await uruchom(tester);
    await otworzPanel(tester, services, await alicja(tester, services));
    expect(find.text(teksty.securityKeyUnknownTitle), findsOneWidget);

    services.peersWithoutKey.value = {'guid-alicja'};
    await tester.pump();

    expect(find.text(teksty.securityNoEncryptionTitle), findsOneWidget);
    expect(find.text(teksty.securityKeyUnknownTitle), findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets('klucz jest: szyfrowane, tożsamość niepotwierdzona',
      (tester) async {
    final services = await uruchom(tester);
    final peer = await alicja(tester, services,
        klucz: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
    // Wpis spośród starszych: z kluczem ten zbiór nic już nie znaczy.
    services.peersWithoutKey.value = {'guid-alicja'};
    await otworzPanel(tester, services, peer);

    expect(find.text(teksty.securityEncryptedTitle), findsOneWidget);
    expect(find.text(teksty.securityNoEncryptionTitle), findsNothing);
    expect(find.text(teksty.securityKeyUnknownTitle), findsNothing);

    await sprzatnij(tester, services);
  });
}
