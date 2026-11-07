import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/updates.dart' show Release;
import 'package:chatt/core/version.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/network/bt_transport.dart' show BtStatus;
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/services/typing_journal.dart' show TypingResult;
import 'package:chatt/ui/screens/settings/bluetooth_addon_card.dart';
import 'package:chatt/ui/screens/settings/connection_section.dart';
import 'package:chatt/ui/screens/settings/internet_addon_card.dart';
import 'package:chatt/ui/screens/settings/keyboard_addon_card.dart';
import 'package:chatt/ui/screens/settings/profile_section.dart';
import 'package:chatt/ui/screens/settings/settings_category_row.dart';
import 'package:chatt/ui/screens/settings_screen.dart';
import 'package:chatt/ui/styles.dart';
import 'package:chatt/ui/widgets/motion.dart';
import 'package:chatt/ui/widgets/toasts.dart';

/// Ustawienia w kategoriach (issue #71) na ekranie: lista ze streszczeniami,
/// kategoria w tym samym ekranie i powrót z niej, dwa panele od 900 px,
/// zmiana szerokości z otwartą kategorią i pola, które zapisują się same.
///
/// Platforma idzie do ekranu wprost, więc lista kategorii jest ta sama na
/// Windowsie i w CI na Linuksie.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final teksty = lookupAppLocalizations(const Locale('en'));

  /// Kategorie na Windowsie w kolejności listy.
  final kategorie = [
    for (final karta in SettingsSection.grupy(TargetPlatform.windows)) ...karta,
  ];

  late Directory katalog;

  setUp(
    () => katalog = Directory.systemTemp.createTempSync('chatt_ustawienia_ui_'),
  );
  tearDown(() {
    chattToasts.clear();
    katalog.deleteSync(recursive: true);
  });

  Future<AppServices> uruchom(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final services = await AppServices.start(
          executor: NativeDatabase.memory(),
          portOverride: 0,
          nameOverride: 'Bartek',
          enableDiscovery: false,
          receivedDirOverride: '${katalog.path}/Bartek',
        );
        // Dziennik pisania powstaje przy pierwszym użyciu. Utworzony
        // w fałszywym czasie testu miałby tam swoją kolejkę zapisów,
        // a zamknięcie stosu czekałoby na nią w prawdziwym bez końca.
        await services.typingJournal.flush();
        return services;
      }))!;

  /// Drzewo schodzi przed zamknięciem stosu. Zamknięcie idzie na zmianę
  /// w prawdziwym i fałszywym czasie: zapisy ze stuknięć wyszły z fałszywej
  /// strefy i tylko tam da się je dokończyć.
  Future<void> sprzatnij(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    var zamkniete = false;
    unawaited(services.dispose().whenComplete(() => zamkniete = true));
    for (var i = 0; i < 300 && !zamkniete; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(zamkniete, isTrue, reason: 'stos się nie zamknął');
  }

  /// Aplikacja w motywie Ciszy: ruch i przejścia tras są te z Chatta.
  /// Ustawienia wchodzą na ekran startowy, jak w aplikacji, więc mają
  /// dokąd wrócić, a pasek kategorii ma strzałkę.
  Widget aplikacja(AppServices services, Widget ustawienia) => ProviderScope(
    overrides: [appServicesProvider.overrideWithValue(services)],
    child: MaterialApp(
      theme: chattTheme(AppStyle.cisza, Brightness.light),
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: _Start(ustawienia),
    ),
  );

  /// Zapis do bazy i strumienie żyją w prawdziwym czasie, ekran w fałszywym.
  /// Na zmianę dajemy pochodzić jednemu i drugiemu, aż [warunek] się spełni.
  Future<void> dokoncz(WidgetTester tester, bool Function() warunek) async {
    for (var i = 0; i < 100 && !warunek(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      warunek(),
      isTrue,
      reason: 'ekran nie doszedł do oczekiwanego stanu',
    );
  }

  /// Przejście do końca: lista i kategoria (Cisza: 300 ms w przód, 250 ms
  /// w tył), przenikanie prawego panelu i wjazd trasy. Klatki co 50 ms,
  /// bo przejście rusza dopiero w klatce po zapisie pól.
  Future<void> ruch(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void telefon(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  void szerokie(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Finder pasek(String tytul) => find.widgetWithText(AppBar, tytul);
  final wiersze = find.byType(SettingsCategoryRow);
  Finder wierszKategorii(SettingsSection kategoria) =>
      find.byKey(ValueKey(kategoria));

  /// Wiersz kategorii także wtedy, gdy lista stoi schowana pod kategorią.
  SettingsCategoryRow wiersz(WidgetTester tester, SettingsSection kategoria) =>
      tester.widget(find.byKey(ValueKey(kategoria), skipOffstage: false));

  /// Wąski ekran: stoi sama lista, bez kategorii, także tej, która schodzi.
  bool naLiscie() =>
      find.byType(AppBar).evaluate().length == 1 &&
      pasek(teksty.settingsTitle).evaluate().length == 1;

  /// Wąski ekran: stoi sama kategoria, a lista schowała się pod nią.
  bool wKategorii(SettingsSection kategoria) =>
      find.byType(AppBar).evaluate().length == 1 &&
      pasek(kategoria.title(teksty)).evaluate().length == 1 &&
      wiersze.evaluate().isEmpty;

  /// Ekran Ustawień dostał już wiersz ustawień z bazy, z którego biorą się
  /// streszczenia.
  bool zaladowane(WidgetTester tester) {
    final ekran = find.byType(SettingsScreen, skipOffstage: false);
    return ekran.evaluate().isNotEmpty &&
        ProviderScope.containerOf(
          tester.element(ekran),
          listen: false,
        ).read(settingsProvider).hasValue;
  }

  /// Stuknięcie w przycisk ekranu startowego i wjazd Ustawień do końca.
  Future<void> wejdz(WidgetTester tester) async {
    await tester.tap(find.text(_przyciskUstawien));
    await dokoncz(tester, () => zaladowane(tester));
    await ruch(tester);
  }

  /// Ustawienia zeszły ze stosu i znów stoi ekran startowy.
  Future<void> zamkniete(WidgetTester tester) async {
    await dokoncz(
      tester,
      () => find.byType(SettingsScreen, skipOffstage: false).evaluate().isEmpty,
    );
    expect(find.text(_przyciskUstawien), findsOneWidget);
  }

  /// Wąski ekran: stuknięcie w wiersz [kategoria] i wjazd kategorii.
  Future<void> otworz(WidgetTester tester, SettingsSection kategoria) async {
    await tester.ensureVisible(wierszKategorii(kategoria));
    await tester.pump();
    await tester.tap(wierszKategorii(kategoria));
    await ruch(tester);
    expect(
      wKategorii(kategoria),
      isTrue,
      reason: 'kategoria ${kategoria.name} nie stanęła',
    );
  }

  /// Dwa panele: stuknięcie w wiersz [kategoria] i jej wejście po prawej.
  Future<void> wybierz(WidgetTester tester, SettingsSection kategoria) async {
    await tester.ensureVisible(wierszKategorii(kategoria));
    await tester.pump();
    await tester.tap(wierszKategorii(kategoria));
    await dokoncz(
      tester,
      () => pasek(kategoria.title(teksty)).evaluate().length == 1,
    );
    await ruch(tester);
  }

  /// Dwa panele: zaznaczony jest dokładnie wiersz [wybrana], w semantyce
  /// i tłem akcentu.
  void zaznaczona(WidgetTester tester, SettingsSection wybrana) {
    final scheme = Theme.of(tester.element(wiersze.first)).colorScheme;
    for (final kategoria in kategorie) {
      final w = wierszKategorii(kategoria);
      expect(
        tester.getSemantics(w),
        isSemantics(isSelected: kategoria == wybrana),
        reason: kategoria.name,
      );
      final tlo = tester
          .widget<Material>(
            find.descendant(of: w, matching: find.byType(Material)).first,
          )
          .color;
      expect(
        tlo,
        kategoria == wybrana ? scheme.primaryContainer : Colors.transparent,
        reason: kategoria.name,
      );
    }
  }

  /// Pole tekstowe z etykietą [etykieta], przewinięte na ekran.
  Future<Finder> pole(WidgetTester tester, String etykieta) async {
    await tester.ensureVisible(
      find.widgetWithText(TextFormField, etykieta, skipOffstage: false),
    );
    await tester.pump();
    return find.widgetWithText(TextFormField, etykieta);
  }

  String tekstPola(WidgetTester tester, Finder pole) =>
      tester.widget<TextFormField>(pole).controller!.text;

  /// Wiersz ustawień z bazy, gdy spełni [warunek].
  Future<Setting> zapisane(
    WidgetTester tester,
    AppServices services,
    bool Function(Setting ustawienia) warunek,
  ) async {
    Setting? ostatnie;
    for (var i = 0; i < 100; i++) {
      ostatnie = await tester.runAsync<Setting?>(services.db.getSettings);
      if (ostatnie != null && warunek(ostatnie)) return ostatnie;
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail('baza nie doszła do oczekiwanego stanu: $ostatnie');
  }

  Future<void> strzalka(WidgetTester tester) =>
      tester.tap(find.byTooltip('Back'));
  Future<void> wsteczSystemu(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
  }

  Future<void> esc(WidgetTester tester) async {
    expect(
      await tester.sendKeyEvent(LogicalKeyboardKey.escape),
      isTrue,
      reason: 'Esc trafia w skrót Ustawień',
    );
  }

  final powroty = <(String, Future<void> Function(WidgetTester))>[
    ('strzałka', strzalka),
    ('Wstecz systemu', wsteczSystemu),
    ('Esc', esc),
  ];

  testWidgets('wąski ekran: osiem kategorii w trzech kartach, przy każdej '
      'streszczenie stanu, trzecia linia z kłopotem i nowością', (
    tester,
  ) async {
    telefon(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);

    expect(naLiscie(), isTrue);
    expect(kategorie, const [
      SettingsSection.profile,
      SettingsSection.connection,
      SettingsSection.backgroundListening,
      SettingsSection.keyboard,
      SettingsSection.appearance,
      SettingsSection.privacy,
      SettingsSection.data,
      SettingsSection.updates,
    ]);
    expect(wiersze, findsNWidgets(kategorie.length));

    // Jedna karta na grupę: Ty, łączenie z innymi, sama aplikacja.
    final karty = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Card),
    );
    expect(karty, findsNWidgets(3));
    for (final (i, karta) in SettingsSection.grupy(
      TargetPlatform.windows,
    ).indexed) {
      expect(
        find.descendant(of: karty.at(i), matching: wiersze),
        findsNWidgets(karta.length),
      );
      for (final kategoria in karta) {
        expect(
          find.descendant(
            of: karty.at(i),
            matching: wierszKategorii(kategoria),
          ),
          findsOneWidget,
          reason: kategoria.name,
        );
      }
    }
    for (var i = 1; i < kategorie.length; i++) {
      expect(
        tester.getTopLeft(wierszKategorii(kategorie[i - 1])).dy,
        lessThan(tester.getTopLeft(wierszKategorii(kategorie[i])).dy),
        reason: kategorie[i].name,
      );
    }

    // Streszczenie mówi, co jest ustawione. Świeża instalacja z testów:
    // port 0 w bazie, bez autostartu, angielski z bazy.
    final streszczenia = {
      SettingsSection.profile: 'Bartek',
      SettingsSection.connection: 'Local network · port 0',
      SettingsSection.backgroundListening: 'Manual start',
      SettingsSection.keyboard: 'Off',
      SettingsSection.appearance: 'Calm · system theme · English',
      SettingsSection.privacy: 'Never delete · no link previews',
      SettingsSection.data: 'Data export · app log',
      SettingsSection.updates: 'Version $appVersion · checked by hand',
    };
    for (final MapEntry(key: kategoria, value: tekst) in streszczenia.entries) {
      final w = wierszKategorii(kategoria);
      expect(
        find.descendant(of: w, matching: find.text(kategoria.title(teksty))),
        findsOneWidget,
        reason: kategoria.name,
      );
      expect(
        find.descendant(of: w, matching: find.text(tekst)),
        findsOneWidget,
        reason: kategoria.name,
      );
      expect(
        find.descendant(of: w, matching: find.byIcon(kategoria.icon)),
        findsOneWidget,
        reason: kategoria.name,
      );
      expect(
        find.descendant(of: w, matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget,
        reason: 'na liście kategoria otwiera się jako osobny widok',
      );
    }

    // Responder w testach milczy: pod Połączeniem kłopot w kolorze
    // ostrzeżenia. Reszta wierszy nie ma trzeciej linii.
    final klopot = find.descendant(
      of: wierszKategorii(SettingsSection.connection),
      matching: find.text(teksty.settingsSummaryOthersWontFind),
    );
    expect(klopot, findsOneWidget);
    expect(
      tester.widget<Text>(klopot).style?.color,
      ChattTokens.of(tester.element(klopot)).warning,
    );
    for (final kategoria in kategorie.where(
      (k) => k != SettingsSection.connection,
    )) {
      expect(wiersz(tester, kategoria).line, isNull, reason: kategoria.name);
    }

    // Nowe wydanie: nowość pod Aktualizacjami w kolorze akcentu, od razu.
    services.availableRelease.value = const Release(
      version: '0.15.0',
      notes: '',
      publishedAt: null,
      pageUrl: 'https://github.com/Mysttic/Mysttic/releases',
      assetUrl: null,
      assetName: null,
      assetSize: null,
    );
    await tester.pump();
    final nowosc = find.descendant(
      of: wierszKategorii(SettingsSection.updates),
      matching: find.text('Version 0.15.0 is out'),
    );
    expect(nowosc, findsOneWidget);
    expect(wiersz(tester, SettingsSection.updates).line?.problem, isFalse);
    expect(
      tester.widget<Text>(nowosc).style?.color,
      Theme.of(tester.element(nowosc)).colorScheme.primary,
    );

    // Pierwsza sesja w historii pisania zmienia streszczenie Klawiatury
    // z PC na żywo.
    await tester.runAsync(
      () => services.db.insertTypingSession(
        TypingSessionsCompanion.insert(
          inputId: 'input-alicja',
          direction: MessageDirection.incoming,
          peerGuid: 'guid-alicja',
          peerName: 'Alicja',
          startedAt: DateTime(2026, 10, 18, 10),
          result: TypingResult.rejected,
          endedAt: Value(DateTime(2026, 10, 18, 10)),
        ),
      ),
    );
    await dokoncz(
      tester,
      () =>
          wiersz(tester, SettingsSection.keyboard).summary ==
          'Off · 1 session in typing history',
    );
    expect(
      find.descendant(
        of: wierszKategorii(SettingsSection.keyboard),
        matching: find.text('Off · 1 session in typing history'),
      ),
      findsOneWidget,
    );

    await sprzatnij(tester, services);
  });

  testWidgets('streszczenie Połączenia idzie na żywo za dodatkami, siecią '
      'lokalną i stanem radia', (tester) async {
    telefon(tester);
    final services = await uruchom(tester);
    // Responder słucha, więc kłopot ze skanami nie przykrywa kłopotów radia.
    services.discoveryListening = true;
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);
    SettingsCategoryRow polaczenie() =>
        wiersz(tester, SettingsSection.connection);
    expect(polaczenie().summary, 'Local network · port 0');
    expect(polaczenie().line, isNull);
    expect(find.text(teksty.settingsSummaryOthersWontFind), findsNothing);

    services.bluetoothAddon.value = true;
    await tester.pump();
    expect(polaczenie().summary, 'Local network and Bluetooth · port 0');
    expect(polaczenie().line, (
      tekst: teksty.transportBluetoothRadioOff,
      problem: true,
    ));

    services.bluetoothStatus.value = const BtStatus(
      available: true,
      enabled: true,
      granted: false,
    );
    await tester.pump();
    expect(polaczenie().line, (
      tekst: teksty.transportBluetoothNoPermission,
      problem: true,
    ));

    services.bluetoothRunning.value = true;
    await tester.pump();
    expect(polaczenie().line, isNull);

    services.internetAddon.value = true;
    await tester.pump();
    expect(
      polaczenie().summary,
      'Local network, Bluetooth and Internet · port 0',
    );

    // Bez sieci lokalnej i bez radia to urządzenie z nikim się nie
    // skontaktuje.
    await tester.runAsync(() => services.db.saveWifiEnabled(false));
    services.bluetoothRunning.value = false;
    await dokoncz(
      tester,
      () => polaczenie().line?.tekst == teksty.settingsSummaryNobodyReached,
    );
    expect(polaczenie().summary, 'Bluetooth and Internet · port 0');
    expect(
      find.descendant(
        of: wierszKategorii(SettingsSection.connection),
        matching: find.text(teksty.settingsSummaryNobodyReached),
      ),
      findsOneWidget,
    );

    // Działająca droga internetowa dalej łączy z potwierdzonymi
    // urządzeniami: linia mówi wtedy o kolejnym kłopocie, braku zgody.
    services.internetRunning.value = true;
    await tester.pump();
    expect(polaczenie().line?.tekst, teksty.transportBluetoothNoPermission);
    services.internetRunning.value = false;
    await tester.pump();
    expect(polaczenie().line?.tekst, teksty.settingsSummaryNobodyReached);

    // Karta o skanach stoi w kategorii tylko przy milczącym responderze.
    // Test gasi dodatki: bez nich karta Bluetooth nie pyta kanału o stan
    // radia. Bez dodatku Bluetooth sieć lokalna chodzi zawsze.
    services.bluetoothAddon.value = false;
    services.internetAddon.value = false;
    await tester.pump();
    expect(polaczenie().summary, 'Local network · port 0');
    await otworz(tester, SettingsSection.connection);
    expect(find.text(teksty.discoveryDeaf), findsNothing);
    expect(find.byType(BluetoothAddonCard), findsOneWidget);

    await sprzatnij(tester, services);
  });

  testWidgets('treść kategorii stoi w kolejności z issue i nic z dawnej '
      'strony nie zginęło', (tester) async {
    // Wysokie wąskie okno: cała treść kategorii naraz, bez przewijania.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = await uruchom(tester);
    // Sesja w historii pisania: przy wyłączonym dodatku Klawiatura z PC ma
    // pod kartą wejście do historii.
    await tester.runAsync(
      () => services.db.insertTypingSession(
        TypingSessionsCompanion.insert(
          inputId: 'input-alicja',
          direction: MessageDirection.incoming,
          peerGuid: 'guid-alicja',
          peerName: 'Alicja',
          startedAt: DateTime(2026, 10, 18, 10),
          result: TypingResult.rejected,
          endedAt: Value(DateTime(2026, 10, 18, 10)),
        ),
      ),
    );
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);
    await dokoncz(
      tester,
      () => wiersz(
        tester,
        SettingsSection.keyboard,
      ).summary.endsWith('1 session in typing history'),
    );

    final tokeny = ChattTokens.of(tester.element(find.byType(SettingsScreen)));
    final tresc = <SettingsSection, List<Finder>>{
      SettingsSection.profile: [
        find.widgetWithText(TextFormField, teksty.nicknameLabel),
        find.widgetWithText(TextFormField, teksty.welcomeLabel),
      ],
      SettingsSection.connection: [
        find.text(teksty.discoveryDeaf),
        find.byType(BluetoothAddonCard),
        find.byType(InternetAddonCard),
        find.text(tokeny.overlineText(teksty.thisDevice)),
        find.widgetWithText(TextFormField, teksty.portFieldLabel),
        find.text(teksty.listeningOn),
        find.text(teksty.deviceIdentifier),
        find.text(teksty.fingerprintMine),
        find.text(teksty.manualPairingHint),
        find.widgetWithText(OutlinedButton, teksty.cleanUpDevices),
        find.text(teksty.cleanUpHelp),
      ],
      SettingsSection.backgroundListening: [
        find.widgetWithText(SwitchListTile, teksty.startWithWindows),
        find.text(teksty.trayHint),
      ],
      SettingsSection.keyboard: [
        find.byType(KeyboardAddonCard),
        find.widgetWithText(OutlinedButton, teksty.typingHistory),
        find.text(teksty.typingHistoryEntryHelp(1)),
      ],
      SettingsSection.appearance: [
        find.text(teksty.styleLabel),
        find.byType(SegmentedButton<AppStyle>),
        find.text(teksty.themeLabel),
        find.byType(SegmentedButton<AppTheme>),
        find.text(teksty.background),
        find.text(teksty.backgroundOcean),
        find.text(teksty.language),
        find.byType(DropdownButtonFormField<AppLanguage>),
      ],
      SettingsSection.privacy: [
        find.text(teksty.dbKeyProtected),
        find.byType(DropdownButtonFormField<int>),
        find.text(teksty.retentionHelp),
        find.widgetWithText(SwitchListTile, teksty.linkPreviewsLabel),
        find.widgetWithText(OutlinedButton, teksty.clearHistory),
      ],
      SettingsSection.data: [
        find.widgetWithText(OutlinedButton, teksty.exportData),
        find.text(teksty.exportDataHelp),
        find.widgetWithText(OutlinedButton, teksty.appLog),
        find.text(teksty.appLogHelp),
      ],
      SettingsSection.updates: [
        find.text('${teksty.version} $appVersion'),
        find.widgetWithText(SwitchListTile, teksty.updateChecksLabel),
        find.text(teksty.updateCheckNow),
      ],
    };
    expect(tresc.keys, unorderedEquals(kategorie));

    double y(Finder f) => tester.getTopLeft(f).dy;
    for (final MapEntry(key: kategoria, value: elementy) in tresc.entries) {
      await otworz(tester, kategoria);
      for (final f in elementy) {
        expect(f, findsOneWidget, reason: '${kategoria.name}: $f');
      }
      for (var i = 1; i < elementy.length; i++) {
        expect(
          y(elementy[i - 1]),
          lessThan(y(elementy[i])),
          reason: '${kategoria.name}: ${elementy[i]}',
        );
      }
      expect(find.text(teksty.save), findsNothing, reason: kategoria.name);
      await strzalka(tester);
      await ruch(tester);
      expect(naLiscie(), isTrue, reason: kategoria.name);
    }

    await sprzatnij(tester, services);
  });

  testWidgets('wąski ekran: kategoria otwiera się w tym samym ekranie, '
      'a strzałka, Wstecz systemu i Esc wracają z niej do listy', (
    tester,
  ) async {
    telefon(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);

    // Po jednym widgecie z treści każdej kategorii, z jej początku.
    final tresc = <SettingsSection, Finder>{
      SettingsSection.profile: find.widgetWithText(
        TextFormField,
        teksty.nicknameLabel,
      ),
      SettingsSection.connection: find.byType(BluetoothAddonCard),
      SettingsSection.backgroundListening: find.text(teksty.startWithWindows),
      SettingsSection.keyboard: find.byType(KeyboardAddonCard),
      SettingsSection.appearance: find.byType(SegmentedButton<AppStyle>),
      SettingsSection.privacy: find.text(teksty.dbKeyProtected),
      SettingsSection.data: find.text(teksty.exportData),
      SettingsSection.updates: find.text(teksty.updateChecksLabel),
    };
    expect(tresc.keys, unorderedEquals(kategorie));

    for (final (i, kategoria) in kategorie.indexed) {
      final nazwa = kategoria.title(teksty);
      await tester.ensureVisible(wierszKategorii(kategoria));
      await tester.pump();
      await tester.tap(wierszKategorii(kategoria));
      await tester.pump();
      // W trakcie przejścia stoją oba widoki: lista ustępuje kategorii.
      expect(find.byType(AppBar), findsNWidgets(2), reason: nazwa);
      expect(pasek(nazwa), findsOneWidget, reason: nazwa);

      await ruch(tester);
      // Po wjeździe lista chowa się pod kategorią, a pasek ma jej nazwę.
      expect(wKategorii(kategoria), isTrue, reason: nazwa);
      expect(tresc[kategoria], findsWidgets, reason: nazwa);
      expect(find.byType(BackButton), findsOneWidget, reason: nazwa);
      expect(
        find.byType(SettingsScreen),
        findsOneWidget,
        reason: 'kategoria bez nowej trasy',
      );

      final (sposob, wroc) = powroty[i % powroty.length];
      await wroc(tester);
      await ruch(tester);
      expect(naLiscie(), isTrue, reason: '$sposob z kategorii $nazwa');
      expect(tresc[kategoria], findsNothing, reason: nazwa);
    }

    await sprzatnij(tester, services);
  });

  testWidgets('wąski ekran: z listy strzałka, Wstecz systemu i Esc zamykają '
      'Ustawienia', (tester) async {
    telefon(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );

    for (final (sposob, wyjdz) in powroty) {
      await wejdz(tester);
      expect(naLiscie(), isTrue, reason: sposob);
      await wyjdz(tester);
      await zamkniete(tester);
    }

    await sprzatnij(tester, services);
  });

  testWidgets('initialSection otwiera kategorię od razu, bez listy w żadnej '
      'klatce, a Wstecz prowadzi do listy', (tester) async {
    telefon(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(
          initialSection: SettingsSection.privacy,
          platform: TargetPlatform.windows,
        ),
      ),
    );

    await tester.tap(find.text(_przyciskUstawien));
    await tester.pump();
    // Pierwszą klatkę trasa stoi poza sceną (Hero mierzy ekran). Lista leży
    // w niej już schowana pod kategorią.
    final lista = find
        .ancestor(
          of: find.byType(SettingsCategoryRow, skipOffstage: false).first,
          matching: find.byType(Offstage, skipOffstage: false),
        )
        .first;
    expect(tester.widget<Offstage>(lista).offstage, isTrue);
    expect(
      find.widgetWithText(AppBar, teksty.privacy, skipOffstage: false),
      findsOneWidget,
    );
    // Każda następna klatka wjazdu trasy: kategoria stoi, wierszy listy nie
    // ma.
    for (var i = 1; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(pasek(teksty.privacy), findsOneWidget, reason: 'klatka $i');
      expect(wiersze, findsNothing, reason: 'klatka $i');
      expect(pasek(teksty.settingsTitle), findsNothing, reason: 'klatka $i');
    }
    await dokoncz(tester, () => zaladowane(tester));
    expect(wKategorii(SettingsSection.privacy), isTrue);
    expect(find.text(teksty.dbKeyProtected), findsOneWidget);

    await strzalka(tester);
    await ruch(tester);
    expect(naLiscie(), isTrue, reason: 'Wstecz z kategorii prowadzi do listy');
    expect(find.byType(SettingsScreen), findsOneWidget);

    await strzalka(tester);
    await zamkniete(tester);

    await sprzatnij(tester, services);
  });

  testWidgets('na Linuksie nie ma Nasłuchu w tle, a initialSection z tą '
      'kategorią otwiera listę', (tester) async {
    telefon(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(
          initialSection: SettingsSection.backgroundListening,
          platform: TargetPlatform.linux,
        ),
      ),
    );
    await wejdz(tester);

    expect(naLiscie(), isTrue);
    expect(wiersze, findsNWidgets(kategorie.length - 1));
    expect(wierszKategorii(SettingsSection.backgroundListening), findsNothing);
    expect(find.text(teksty.backgroundListening), findsNothing);
    final karty = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Card),
    );
    expect(karty, findsNWidgets(3));
    expect(
      find.descendant(of: karty.at(1), matching: wiersze),
      findsNWidgets(2),
      reason: 'Połączenie i Klawiatura z PC',
    );
    expect(
      tester.getTopLeft(wierszKategorii(SettingsSection.connection)).dy,
      lessThan(tester.getTopLeft(wierszKategorii(SettingsSection.keyboard)).dy),
    );

    await sprzatnij(tester, services);
  });

  testWidgets('zmiana w kategorii od razu zmienia streszczenie na liście', (
    tester,
  ) async {
    telefon(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);
    expect(
      wiersz(tester, SettingsSection.appearance).summary,
      'Calm · system theme · English',
    );

    await otworz(tester, SettingsSection.appearance);
    await tester.tap(find.text(teksty.stylePrecyzja));
    // Lista pod kategorią idzie za bazą, zanim ktokolwiek do niej wróci.
    await dokoncz(
      tester,
      () =>
          wiersz(tester, SettingsSection.appearance).summary ==
          'Precise · system theme · English',
    );
    expect(wKategorii(SettingsSection.appearance), isTrue);

    await strzalka(tester);
    await ruch(tester);
    expect(naLiscie(), isTrue);
    expect(
      find.descendant(
        of: wierszKategorii(SettingsSection.appearance),
        matching: find.text('Precise · system theme · English'),
      ),
      findsOneWidget,
    );

    // Podglądy stron w Prywatności.
    await otworz(tester, SettingsSection.privacy);
    final podglady = find.widgetWithText(
      SwitchListTile,
      teksty.linkPreviewsLabel,
    );
    await tester.ensureVisible(podglady);
    await tester.pump();
    await tester.tap(podglady);
    await dokoncz(
      tester,
      () =>
          wiersz(tester, SettingsSection.privacy).summary ==
          'Never delete · with link previews',
    );
    await esc(tester);
    await ruch(tester);
    expect(naLiscie(), isTrue);
    expect(
      find.descendant(
        of: wierszKategorii(SettingsSection.privacy),
        matching: find.text('Never delete · with link previews'),
      ),
      findsOneWidget,
    );

    await sprzatnij(tester, services);
  });

  testWidgets('od 900 px dwa panele: lista i pierwsza kategoria naraz, '
      'zaznaczenie bez strzałek, a strzałka, Esc i Wstecz zamykają '
      'Ustawienia', (tester) async {
    szerokie(tester);
    final semantyka = tester.ensureSemantics();
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);

    // Prawy panel nie stoi pusty: bez wyboru Profil, pierwsza kategoria.
    expect(wiersze, findsNWidgets(kategorie.length));
    expect(pasek(teksty.settingsTitle), findsOneWidget);
    expect(pasek(teksty.profileSection), findsOneWidget);
    final nick = find.widgetWithText(TextFormField, teksty.nicknameLabel);
    expect(nick, findsOneWidget);
    expect(tekstPola(tester, nick), 'Bartek');

    // Lista 360 px, kreska, kategoria w kolumnie do 640 px.
    expect(find.byType(VerticalDivider), findsOneWidget);
    for (final kategoria in kategorie) {
      expect(
        tester.getRect(wierszKategorii(kategoria)).right,
        lessThanOrEqualTo(360),
        reason: kategoria.name,
      );
    }
    expect(tester.getTopLeft(nick).dx, greaterThan(361));
    expect(tester.getSize(nick).width, lessThanOrEqualTo(640));

    // Bez strzałek, zaznaczony sam Profil.
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    zaznaczona(tester, SettingsSection.profile);

    // Inny wiersz: prawy panel i zaznaczenie idą za nim.
    await wybierz(tester, SettingsSection.privacy);
    expect(pasek(teksty.profileSection), findsNothing);
    expect(nick, findsNothing);
    expect(find.text(teksty.dbKeyProtected), findsOneWidget);
    expect(wiersze, findsNWidgets(kategorie.length));
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    zaznaczona(tester, SettingsSection.privacy);

    // Stuknięcie w wybraną kategorię niczego nie przełącza.
    double krycie() => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: pasek(teksty.privacy),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    expect(krycie(), 1);
    await tester.tap(wierszKategorii(SettingsSection.privacy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(krycie(), 1);
    expect(pasek(teksty.privacy), findsOneWidget);

    await wybierz(tester, SettingsSection.updates);
    expect(find.text(teksty.updateChecksLabel), findsOneWidget);
    zaznaczona(tester, SettingsSection.updates);

    // Strzałka stoi nad listą i zamyka Ustawienia: listy, do której można
    // wrócić, nie ma.
    final wstecz = find.byType(BackButton);
    expect(wstecz, findsOneWidget);
    expect(tester.getCenter(wstecz).dx, lessThan(360));
    await tester.tap(wstecz);
    await zamkniete(tester);

    await wejdz(tester);
    expect(
      pasek(teksty.profileSection),
      findsOneWidget,
      reason: 'nowe Ustawienia znów od pierwszej kategorii',
    );
    await esc(tester);
    await zamkniete(tester);

    await wejdz(tester);
    await wsteczSystemu(tester);
    await zamkniete(tester);

    semantyka.dispose();
    await sprzatnij(tester, services);
  });

  /// Dwa Wstecz systemu naraz: drugie przychodzi, zanim zapis pól po
  /// pierwszym się skończy (w aplikacji baza pisze w osobnym izolacie).
  Future<void> dwaWstecz(WidgetTester tester) async {
    final pierwsze = tester.binding.handlePopRoute();
    final drugie = tester.binding.handlePopRoute();
    await pierwsze;
    await drugie;
  }

  testWidgets('wąski ekran: dwa Wstecz naraz z kategorii wracają do listy, '
      'z listy zamykają same Ustawienia', (tester) async {
    telefon(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);

    await otworz(tester, SettingsSection.profile);
    await tester.enterText(
      find.widgetWithText(TextFormField, teksty.nicknameLabel),
      'Gosia',
    );
    await dwaWstecz(tester);
    await dokoncz(tester, naLiscie);
    await ruch(tester);
    expect(naLiscie(), isTrue, reason: 'drugie Wstecz nie zamyka Ustawień');
    await zapisane(tester, services, (u) => u.nickname == 'Gosia');

    // Z listy: zwykłe zejście trasy, Navigator.maybePop pilnuje, czy stos
    // się w międzyczasie nie zmienił.
    await dwaWstecz(tester);
    await zamkniete(tester);

    await sprzatnij(tester, services);
  });

  testWidgets('dwa panele: drugie Wstecz w trakcie zapisu pól zamyka same '
      'Ustawienia', (tester) async {
    szerokie(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, teksty.nicknameLabel),
      'Gosia',
    );
    await dwaWstecz(tester);
    await zamkniete(tester);
    expect(
      find.text(_przyciskUstawien),
      findsOneWidget,
      reason: 'ekran pod Ustawieniami zostaje',
    );
    await zapisane(tester, services, (u) => u.nickname == 'Gosia');

    await sprzatnij(tester, services);
  });

  testWidgets('dwa panele: initialSection stoi od razu w prawym panelu '
      'i jest zaznaczona', (tester) async {
    szerokie(tester);
    final semantyka = tester.ensureSemantics();
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(
          initialSection: SettingsSection.updates,
          platform: TargetPlatform.windows,
        ),
      ),
    );
    await wejdz(tester);

    expect(pasek(teksty.updates), findsOneWidget);
    expect(find.text(teksty.updateChecksLabel), findsOneWidget);
    expect(pasek(teksty.profileSection), findsNothing);
    expect(wiersze, findsNWidgets(kategorie.length));
    zaznaczona(tester, SettingsSection.updates);

    semantyka.dispose();
    await sprzatnij(tester, services);
  });

  testWidgets('dwa panele: zmiana w kategorii zmienia wiersz po lewej, '
      'a kategoria zostaje otwarta', (tester) async {
    szerokie(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);
    await wybierz(tester, SettingsSection.appearance);
    final w = wierszKategorii(SettingsSection.appearance);

    Future<void> zmien(String przycisk, String streszczenie) async {
      await tester.tap(find.text(przycisk));
      await dokoncz(
        tester,
        () => find
            .descendant(of: w, matching: find.text(streszczenie))
            .evaluate()
            .isNotEmpty,
      );
      expect(pasek(teksty.appearance), findsOneWidget, reason: przycisk);
      expect(
        find.byType(SegmentedButton<AppStyle>),
        findsOneWidget,
        reason: przycisk,
      );
      expect(
        wiersz(tester, SettingsSection.appearance).selected,
        isTrue,
        reason: przycisk,
      );
    }

    await zmien(teksty.stylePrecyzja, 'Precise · system theme · English');
    await zmien(teksty.themeDark, 'Precise · dark · English');
    await zmien(teksty.backgroundOcean, 'Precise · dark · Ocean · English');

    await sprzatnij(tester, services);
  });

  testWidgets('zmiana szerokości przenosi otwartą kategorię razem ze stanem '
      'pól', (tester) async {
    telefon(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);
    await otworz(tester, SettingsSection.profile);

    final nick = find.widgetWithText(TextFormField, teksty.nicknameLabel);
    await tester.enterText(nick, 'Bartek z biura');
    final stan = tester.state(find.byType(ProfileSection));

    // Okno rozciągnięte: dwa panele, Profil po prawej, ten sam stan pól.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pump();
    expect(wiersze, findsNWidgets(kategorie.length));
    expect(pasek(teksty.profileSection), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(wiersz(tester, SettingsSection.profile).selected, isTrue);
    expect(tester.state(find.byType(ProfileSection)), same(stan));
    expect(tekstPola(tester, nick), 'Bartek z biura');

    // Z powrotem telefon: kategoria dalej otwarta, z tym samym tekstem.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    await tester.pump();
    expect(wKategorii(SettingsSection.profile), isTrue);
    expect(tester.state(find.byType(ProfileSection)), same(stan));
    expect(tekstPola(tester, nick), 'Bartek z biura');

    // Wstecz wraca do listy i zapisuje nick.
    await strzalka(tester);
    await dokoncz(tester, naLiscie);
    await zapisane(tester, services, (u) => u.nickname == 'Bartek z biura');
    expect(services.identity.name, 'Bartek z biura');

    await sprzatnij(tester, services);
  });

  testWidgets('dwa panele: stuknięcie w pokazany bez wyboru Profil '
      'zapamiętuje wybór: po zwężeniu okna Profil stoi dalej, '
      'z tym samym stanem pól', (tester) async {
    szerokie(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);

    await tester.tap(wierszKategorii(SettingsSection.profile));
    await ruch(tester);
    final nick = find.widgetWithText(TextFormField, teksty.nicknameLabel);
    await tester.enterText(nick, 'Zenek');
    final stan = tester.state(find.byType(ProfileSection));

    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    await tester.pump();
    expect(wKategorii(SettingsSection.profile), isTrue);
    expect(tester.state(find.byType(ProfileSection)), same(stan));
    expect(tekstPola(tester, nick), 'Zenek');

    await sprzatnij(tester, services);
  });

  testWidgets('dwa panele: Profil pokazany bez wyboru jest wybrany, więc po '
      'zwężeniu okna stoi dalej z tym samym stanem pól', (tester) async {
    szerokie(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);

    // Bez stuknięcia w wiersz: pisanie w Profilu, który stoi od wejścia.
    final nick = find.widgetWithText(TextFormField, teksty.nicknameLabel);
    await tester.enterText(nick, 'Wiesia');
    final stan = tester.state(find.byType(ProfileSection));

    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    await tester.pump();
    expect(wKategorii(SettingsSection.profile), isTrue);
    expect(tester.state(find.byType(ProfileSection)), same(stan));
    expect(tekstPola(tester, nick), 'Wiesia');

    // Wstecz wraca do listy i zapisuje nick.
    await strzalka(tester);
    await dokoncz(tester, naLiscie);
    await zapisane(tester, services, (u) => u.nickname == 'Wiesia');

    await sprzatnij(tester, services);
  });

  testWidgets('Profil zapisuje się sam: Enter, wyjście z kategorii, '
      'powitanie; pusty nick zatrzymuje w kategorii', (tester) async {
    telefon(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);
    await otworz(tester, SettingsSection.profile);
    expect(find.text(teksty.save), findsNothing, reason: 'bez „Zapisz”');

    final nick = find.widgetWithText(TextFormField, teksty.nicknameLabel);
    final powitanie = find.widgetWithText(TextFormField, teksty.welcomeLabel);
    expect(tekstPola(tester, nick), 'Bartek');

    // Enter w polu nicku: zapis od razu, fokus idzie do powitania.
    await tester.enterText(nick, 'Celina');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    await zapisane(tester, services, (u) => u.nickname == 'Celina');
    expect(services.identity.name, 'Celina');
    await dokoncz(
      tester,
      () => wiersz(tester, SettingsSection.profile).summary == 'Celina',
    );
    expect(
      wKategorii(SettingsSection.profile),
      isTrue,
      reason: 'Enter nie zamyka kategorii',
    );

    // Gotowe w powitaniu: zapis i fokus wraca do Ustawień, więc Esc działa.
    await tester.enterText(powitanie, 'Hej, tu Celina');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await zapisane(
      tester,
      services,
      (u) => u.welcomeMessage == 'Hej, tu Celina',
    );
    expect(services.identity.welcomeMessage, 'Hej, tu Celina');
    await esc(tester);
    await ruch(tester);
    expect(naLiscie(), isTrue);
    expect(
      find.descendant(
        of: wierszKategorii(SettingsSection.profile),
        matching: find.text('Celina · “Hej, tu Celina”'),
      ),
      findsOneWidget,
    );

    // Nowy nick i strzałka: zapis przy wyjściu z kategorii.
    await otworz(tester, SettingsSection.profile);
    await tester.enterText(nick, 'Darek');
    await strzalka(tester);
    await dokoncz(tester, naLiscie);
    await zapisane(tester, services, (u) => u.nickname == 'Darek');
    expect(services.identity.name, 'Darek');

    // Pusty nick: komunikat pola, kategoria zostaje, nic się nie zapisuje.
    await otworz(tester, SettingsSection.profile);
    await tester.enterText(nick, '');
    for (final (sposob, wroc) in powroty) {
      await wroc(tester);
      await ruch(tester);
      expect(wKategorii(SettingsSection.profile), isTrue, reason: sposob);
      expect(
        find.text(teksty.nicknameRequired),
        findsOneWidget,
        reason: sposob,
      );
    }
    expect(services.identity.name, 'Darek');
    expect((await tester.runAsync(services.db.getSettings))!.nickname, 'Darek');

    // Poprawiony nick wypuszcza i zapisuje się po drodze.
    await tester.enterText(nick, 'Edek');
    await tester.pump();
    expect(find.text(teksty.nicknameRequired), findsNothing);
    await wsteczSystemu(tester);
    await dokoncz(tester, naLiscie);
    await zapisane(tester, services, (u) => u.nickname == 'Edek');
    expect(services.identity.name, 'Edek');
    expect(services.identity.welcomeMessage, 'Hej, tu Celina');

    await sprzatnij(tester, services);
  });

  testWidgets('dwa panele: pusty nick zatrzymuje przy zmianie kategorii '
      'i przy zamykaniu Ustawień', (tester) async {
    szerokie(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);

    final nick = find.widgetWithText(TextFormField, teksty.nicknameLabel);
    await tester.enterText(nick, '');
    await tester.tap(wierszKategorii(SettingsSection.privacy));
    await ruch(tester);
    expect(pasek(teksty.profileSection), findsOneWidget);
    expect(pasek(teksty.privacy), findsNothing);
    expect(find.text(teksty.nicknameRequired), findsOneWidget);
    expect(wiersz(tester, SettingsSection.profile).selected, isTrue);

    for (final (sposob, wyjdz) in powroty) {
      await wyjdz(tester);
      await ruch(tester);
      expect(find.byType(SettingsScreen), findsOneWidget, reason: sposob);
      expect(pasek(teksty.profileSection), findsOneWidget, reason: sposob);
    }
    expect(services.identity.name, 'Bartek');

    // Poprawiony nick: zmiana kategorii zapisuje go po drodze.
    await tester.enterText(nick, 'Franek');
    await wybierz(tester, SettingsSection.privacy);
    await zapisane(tester, services, (u) => u.nickname == 'Franek');
    expect(services.identity.name, 'Franek');
    expect(wiersz(tester, SettingsSection.profile).summary, 'Franek');

    await sprzatnij(tester, services);
  });

  testWidgets('Połączenie: port zapisuje się sam, zły zatrzymuje '
      'w kategorii, nietknięty nie przeszkadza', (tester) async {
    telefon(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);

    // Nietknięte pole z portem spoza zakresu (0 w testach) nie zatrzymuje.
    await otworz(tester, SettingsSection.connection);
    var port = await pole(tester, teksty.portFieldLabel);
    await dokoncz(tester, () => tekstPola(tester, port) == '0');
    expect(find.text(teksty.portRestartHint), findsOneWidget);
    expect(find.text(teksty.save), findsNothing, reason: 'bez „Zapisz”');
    await strzalka(tester);
    await ruch(tester);
    expect(naLiscie(), isTrue);
    expect(find.text(teksty.portRange), findsNothing);
    expect(chattToasts.value, isEmpty);
    expect((await tester.runAsync(services.db.getSettings))!.tcpPort, 0);

    // Port spoza zakresu: zostajemy z komunikatem pola.
    await otworz(tester, SettingsSection.connection);
    port = await pole(tester, teksty.portFieldLabel);
    await tester.enterText(port, '70000');
    for (final (sposob, wroc) in powroty) {
      await wroc(tester);
      await ruch(tester);
      expect(wKategorii(SettingsSection.connection), isTrue, reason: sposob);
      expect(find.text(teksty.portRange), findsOneWidget, reason: sposob);
    }
    expect((await tester.runAsync(services.db.getSettings))!.tcpPort, 0);
    expect(chattToasts.value, isEmpty);

    // Poprawny port: zapis przy wyjściu i jeden komunikat o restarcie.
    final nowy = services.identity.tcpPort == 47999 ? 47998 : 47999;
    await tester.enterText(port, '$nowy');
    // Komunikat pola przenika z powrotem w podpowiedź pod polem.
    await ruch(tester);
    expect(find.text(teksty.portRange), findsNothing);
    expect(find.text(teksty.portRestartHint), findsOneWidget);
    await strzalka(tester);
    await dokoncz(tester, naLiscie);
    await zapisane(tester, services, (u) => u.tcpPort == nowy);
    expect(
      chattToasts.value.where((t) => t.text == teksty.savedRestartNeeded),
      hasLength(1),
    );
    await dokoncz(
      tester,
      () =>
          wiersz(tester, SettingsSection.connection).summary ==
          'Local network · port $nowy',
    );

    // Port, na którym serwer naprawdę słucha, zapisuje Enter, bez
    // komunikatu o restarcie i bez wychodzenia z kategorii.
    chattToasts.clear();
    await otworz(tester, SettingsSection.connection);
    port = await pole(tester, teksty.portFieldLabel);
    expect(tekstPola(tester, port), '$nowy');
    final slucha = services.identity.tcpPort;
    await tester.enterText(port, '$slucha');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await zapisane(tester, services, (u) => u.tcpPort == slucha);
    await ruch(tester);
    expect(chattToasts.value, isEmpty);
    expect(wKategorii(SettingsSection.connection), isTrue);

    await sprzatnij(tester, services);
  });

  testWidgets('Esc przy menu pola chowa samo menu, następne Esc zamyka '
      'Ustawienia', (tester) async {
    szerokie(tester);
    final services = await uruchom(tester);
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);

    final nick = find.widgetWithText(TextFormField, teksty.nicknameLabel);
    await tester.tap(nick);
    await tester.pump();
    final pole = tester.state<EditableTextState>(
      find.descendant(of: nick, matching: find.byType(EditableText)),
    );
    expect(pole.showToolbar(), isTrue);
    await tester.pump();
    expect(pole.selectionOverlay?.toolbarIsVisible, isTrue);

    await esc(tester);
    await tester.pump();
    expect(
      pole.selectionOverlay?.toolbarIsVisible ?? false,
      isFalse,
      reason: 'Esc chowa menu pola',
    );
    expect(
      find.byType(SettingsScreen),
      findsOneWidget,
      reason: 'pierwsze Esc nie zamyka Ustawień',
    );

    await esc(tester);
    await zamkniete(tester);

    await sprzatnij(tester, services);
  });

  testWidgets(
    'dwa panele: Dalej w polu nicku przenosi fokus do pola powitania',
    (tester) async {
      szerokie(tester);
      final services = await uruchom(tester);
      await tester.pumpWidget(
        aplikacja(
          services,
          const SettingsScreen(platform: TargetPlatform.windows),
        ),
      );
      await wejdz(tester);

      final nick = find.widgetWithText(TextFormField, teksty.nicknameLabel);
      await tester.tap(nick);
      await tester.pump();
      await tester.enterText(nick, 'Edek');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();

      final powitanie = find.widgetWithText(TextFormField, teksty.welcomeLabel);
      final fokus = FocusManager.instance.primaryFocus;
      expect(fokus, isNotNull);
      expect(
        find.descendant(
          of: powitanie,
          matching: find.byWidgetPredicate(
            (w) => w is EditableText && w.focusNode == fokus,
          ),
        ),
        findsOneWidget,
        reason: 'fokus stoi w polu powitania',
      );
      await zapisane(tester, services, (u) => u.nickname == 'Edek');

      await sprzatnij(tester, services);
    },
  );

  testWidgets('PageDown w otwartej kategorii przewija ją bez błędu: lista '
      'pod spodem nie bierze głównego przewijacza', (tester) async {
    telefon(tester);
    // Mały ekran: treść Połączenia jest dłuższa niż okno.
    tester.view.physicalSize = const Size(1080, 1500);
    final services = await uruchom(tester);
    services.discoveryListening = true;
    await tester.pumpWidget(
      aplikacja(
        services,
        const SettingsScreen(platform: TargetPlatform.windows),
      ),
    );
    await wejdz(tester);
    await otworz(tester, SettingsSection.connection);

    final przewijanie = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ConnectionSection),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(przewijanie.position.pixels, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await ruch(tester);
    expect(tester.takeException(), isNull);
    expect(przewijanie.position.pixels, greaterThan(0));

    await sprzatnij(tester, services);
  });
}

/// Napis przycisku na ekranie startowym.
const _przyciskUstawien = 'Otwórz Ustawienia';

/// Ekran startowy z jednym przyciskiem. Ustawienia wchodzą na niego trasą
/// stylu, tak jak z listy rozmów.
class _Start extends StatelessWidget {
  final Widget ustawienia;

  const _Start(this.ustawienia);

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () =>
            Navigator.of(context)
                .push(ChattPageRoute<void>(builder: (_) => ustawienia)),
        child: const Text(_przyciskUstawien),
      ),
    ),
  );
}
