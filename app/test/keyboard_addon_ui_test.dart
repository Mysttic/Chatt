import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/remote_input.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/ui/screens/chat_screen.dart';
import 'package:chatt/ui/screens/conversations_screen.dart';
import 'package:chatt/ui/screens/settings_screen.dart';
import 'package:chatt/ui/widgets/prompt_overlay.dart';

/// Interfejsowa połowa dodatku klawiatury: bez dodatku żaden ekran poza jego
/// kartą nie pokazuje niczego z klawiatury, a karty zgody nie da się
/// przyjąć samym Enterem.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Prośby o pisanie idą tu przez prawdziwe gniazda (w `tester.runAsync`),
  // a podmieniony HttpClient odpowiadałby na wszystko 400.
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const kanal = MethodChannel('chatt/remoteinput');
  final teksty = lookupAppLocalizations(const Locale('en'));

  /// Wszystkie ikony, którymi klawiatura mogłaby się pokazać.
  const ikonyKlawiatury = [
    Icons.keyboard_outlined,
    Icons.keyboard_alt_outlined,
    Icons.keyboard,
  ];

  late Directory katalog;
  late Duration pingPrzed;

  setUp(() {
    katalog = Directory.systemTemp.createTempSync('chatt_klawiatura_ui_');
    // Przełącznik odbioru jest aktywny tylko tam, gdzie jest kod natywny.
    RemoteInputChannel.debugSupported = true;
    pingPrzed = debugRemoteInputPingInterval;
    debugRemoteInputPingInterval = const Duration(hours: 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      kanal,
      (call) async => switch (call.method) {
        'status' || 'apply' => const <String, Object?>{
            'active': true,
            'field': 'text',
            'applied': true,
          },
        'setImeEnabled' => const <String, Object?>{'ok': true},
        _ => const <String, Object?>{},
      },
    );
  });
  tearDown(() {
    RemoteInputChannel.debugSupported = null;
    debugRemoteInputPingInterval = pingPrzed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, null);
    katalog.deleteSync(recursive: true);
  });

  Future<AppServices> uruchom(
    WidgetTester tester,
    String nazwa, {
    RemoteInputPolicy? polityka,
  }) async =>
      (await tester.runAsync(() => AppServices.start(
            executor: NativeDatabase.memory(),
            portOverride: 0,
            nameOverride: nazwa,
            enableDiscovery: false,
            receivedDirOverride: '${katalog.path}/$nazwa',
            remoteInputPolicy: polityka,
          )))!;

  /// Drzewo schodzi przed zamknięciem stosów: ekrany odpinają słuchaczy,
  /// a strumienie z bazy sprzątają się swoim licznikiem.
  Future<void> sprzatnij(
      WidgetTester tester, List<AppServices> wszystkie) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    for (final services in wszystkie) {
      await tester.runAsync(services.dispose);
    }
  }

  /// Alicja i Bartek sparowani kodem, obie strony zweryfikowane. Zwraca
  /// Bartka tak, jak widzi go Alicja.
  Future<Peer> sparuj(
      WidgetTester tester, AppServices alicja, AppServices bartek) async {
    final peer = await tester.runAsync(() async {
      final bartekUAlicji =
          await alicja.addPeerByAddress('127.0.0.1', bartek.server.port!);
      await alicja.startPairing(bartekUAlicji!);
      expect(await alicja.confirmPairing(bartek.identity.guid),
          PairOutcome.accepted);
      expect(await bartek.confirmPairing(alicja.identity.guid),
          PairOutcome.accepted);
      return alicja.db.peerByGuid(bartek.identity.guid);
    });
    expect(peer!.verified, isTrue);
    return peer;
  }

  /// Czeka na prawdziwym zegarze, aż [warunek] się spełni.
  Future<void> czekajNa(WidgetTester tester, bool Function() warunek) =>
      tester.runAsync(() async {
        final koniec = DateTime.now().add(const Duration(seconds: 10));
        while (!warunek()) {
          if (DateTime.now().isAfter(koniec)) {
            fail('warunek nie spełnił się w ciągu 10 s');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

  /// Stuknięcie idzie w fałszywym czasie testu, kolejka przełączeń i baza
  /// żyją w prawdziwym. Na zmianę dajemy pochodzić jednemu i drugiemu,
  /// aż ekran pokaże [warunek].
  Future<void> dokoncz(WidgetTester tester, bool Function() warunek) async {
    for (var i = 0; i < 50 && !warunek(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(warunek(), isTrue, reason: 'przełączenie nie doszło do ekranu');
  }

  Widget aplikacja(AppServices services,
          {Widget? ekran, TransitionBuilder? builder}) =>
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: builder,
          home: ekran ?? const Scaffold(body: SizedBox.expand()),
        ),
      );

  Widget kartaDodatku(AppServices services) => aplikacja(
        services,
        ekran: const Scaffold(
          body: SingleChildScrollView(child: KeyboardAddonCard()),
        ),
      );

  /// Nakładka tak jak w aplikacji: w `MaterialApp.builder`, nad ekranem.
  Widget nakladka(AppServices services) => aplikacja(
        services,
        builder: (context, child) => PromptOverlay(child: child!),
      );

  void bezKlawiatury() {
    for (final ikona in ikonyKlawiatury) {
      expect(find.byIcon(ikona), findsNothing, reason: '$ikona');
    }
  }

  testWidgets('karta dodatku bez dodatku to sam przełącznik', (tester) async {
    final services = await uruchom(tester, 'Bartek');
    await tester.pumpWidget(kartaDodatku(services));
    await tester.pump();

    final dodatek =
        find.widgetWithIcon(SwitchListTile, Icons.keyboard_outlined);
    final odbior =
        find.widgetWithIcon(SwitchListTile, Icons.keyboard_alt_outlined);
    expect(dodatek, findsOneWidget);
    expect(tester.widget<SwitchListTile>(dodatek).value, isFalse);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(odbior, findsNothing,
        reason: 'przełącznik odbioru należy do dodatku');

    services.keyboardAddon.value = true;
    await tester.pump();
    expect(odbior, findsOneWidget);
    final przelacznik = tester.widget<SwitchListTile>(odbior);
    expect(przelacznik.value, isFalse);
    expect(przelacznik.onChanged, isNotNull);
    expect(find.text(teksty.remoteInputSafety), findsNothing);

    services.keyboardAddon.value = false;
    await tester.pump();
    expect(odbior, findsNothing);
    expect(find.byType(SwitchListTile), findsOneWidget);

    await sprzatnij(tester, [services]);
  });

  testWidgets('włączony odbiór pokazuje notę bezpieczeństwa', (tester) async {
    final services = await uruchom(tester, 'Bartek');
    await tester.pumpWidget(kartaDodatku(services));
    await tester.pump();
    final dodatek =
        find.widgetWithIcon(SwitchListTile, Icons.keyboard_outlined);
    final odbior =
        find.widgetWithIcon(SwitchListTile, Icons.keyboard_alt_outlined);

    bool gotowa() => tester.widget<SwitchListTile>(dodatek).onChanged != null;
    await tester.tap(dodatek);
    await dokoncz(tester, () => gotowa() && odbior.evaluate().isNotEmpty);
    expect(services.keyboardAddon.value, isTrue);
    expect(odbior, findsOneWidget);
    expect(find.text(teksty.remoteInputSafety), findsNothing);

    await tester.tap(odbior);
    await dokoncz(
        tester, () => gotowa() && tester.widget<SwitchListTile>(odbior).value);
    expect(tester.widget<SwitchListTile>(odbior).value, isTrue);
    expect(find.text(teksty.remoteInputSafety), findsOneWidget);

    // Dodatek wyłączony: znika odbiór razem z notą, baza też zapomina odbiór.
    await tester.tap(dodatek);
    await dokoncz(tester, () => gotowa() && odbior.evaluate().isEmpty);
    expect(services.keyboardAddon.value, isFalse);
    expect(odbior, findsNothing);
    expect(find.text(teksty.remoteInputSafety), findsNothing);
    final ustawienia = await tester.runAsync(services.db.getSettings);
    expect(ustawienia!.remoteInputReceive, isFalse);

    await sprzatnij(tester, [services]);
  });

  testWidgets('trwająca zgoda pokazuje „Pisze" ze Stopem, który ją kończy',
      (tester) async {
    final alicja = await uruchom(tester, 'Alicja');
    final bartek =
        await uruchom(tester, 'Bartek', polityka: acceptAllRemoteInput);
    final peer = await sparuj(tester, alicja, bartek);
    await tester.runAsync(() async {
      await alicja.setKeyboardAddon(true);
      await bartek.setKeyboardAddon(true);
      expect(await bartek.setRemoteInputReceive(true), isTrue);
    });

    await tester.pumpWidget(kartaDodatku(bartek));
    await tester.pump();
    expect(find.text('Typing: Alicja'), findsNothing);

    final start = await tester.runAsync(() => alicja.startRemoteInput(peer));
    expect(start, RemoteInputStart.accepted);
    await tester.pump();
    expect(find.text('Typing: Alicja'), findsOneWidget);
    final stop = find.widgetWithText(FilledButton, 'Stop');
    expect(stop, findsOneWidget);

    await tester.tap(stop);
    await tester.pump();
    expect(find.text('Typing: Alicja'), findsNothing);
    expect(bartek.incomingRemoteInput.value, isNull);

    // Stop naprawdę zakończył zgodę: następna paczka Alicji się odbija.
    await tester.runAsync(() async {
      expect(alicja.sendRemoteInput(const [RemoteInputOp.insert('x')]), isTrue);
    });
    await czekajNa(
        tester,
        () =>
            alicja.outgoingRemoteInput.value?.state ==
            OutgoingRemoteInputState.disconnected);
    expect(alicja.outgoingRemoteInput.value!.reason, inputNoGrant);

    await sprzatnij(tester, [alicja, bartek]);
  });

  testWidgets('nakładka bez dodatku nie pokazuje karty, choć prosi '
      'zweryfikowany', (tester) async {
    final alicja = await uruchom(tester, 'Alicja');
    final bartek = await uruchom(tester, 'Bartek');
    final peer = await sparuj(tester, alicja, bartek);
    await tester.runAsync(() => alicja.setKeyboardAddon(true));

    await tester.pumpWidget(nakladka(bartek));
    await tester.pump();
    bezKlawiatury();
    expect(find.textContaining('wants to type'), findsNothing);

    final start = await tester.runAsync(() => alicja.startRemoteInput(peer));
    expect(start, RemoteInputStart.notEnabled);
    await tester.pump();
    bezKlawiatury();
    expect(find.textContaining('wants to type'), findsNothing);
    expect(bartek.pendingRemoteInput.value, isEmpty);

    await sprzatnij(tester, [alicja, bartek]);
  });

  testWidgets('lista rozmów bez dodatku nie ma śladu klawiatury',
      (tester) async {
    final services = await uruchom(tester, 'Bartek');
    await tester.runAsync(() async {
      // Bez adresu: obecność odpowiada od razu, bez sieci.
      final alicja = await services.db.upsertPeer(
        guid: 'guid-alicja',
        name: 'Alicja',
        welcomeMessage: '',
        host: '',
        port: 0,
      );
      await services.db.setPeerVerified(alicja.id, true);
      await services.db.ensureConversation(alicja.id);
    });

    await tester
        .pumpWidget(aplikacja(services, ekran: const ConversationsScreen()));
    await tester.pump();
    await tester.pump();
    expect(find.text('Alicja'), findsOneWidget);
    bezKlawiatury();

    await sprzatnij(tester, [services]);
  });

  testWidgets('rozmowa bez dodatku nie ma śladu klawiatury', (tester) async {
    final services = await uruchom(tester, 'Bartek');
    final (rozmowa, alicja) = (await tester.runAsync(() async {
      final alicja = await services.db.upsertPeer(
        guid: 'guid-alicja',
        name: 'Alicja',
        welcomeMessage: '',
        host: '',
        port: 0,
      );
      await services.db.setPeerVerified(alicja.id, true);
      final rozmowa = await services.db.ensureConversation(alicja.id);
      return (rozmowa, (await services.db.peerByGuid('guid-alicja'))!);
    }))!;
    expect(alicja.verified, isTrue);

    await tester.pumpWidget(aplikacja(
      services,
      ekran: ChatScreen(conversationId: rozmowa, peer: alicja),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Alicja'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget,
        reason: 'ekran rozmowy naprawdę stoi');
    bezKlawiatury();

    await sprzatnij(tester, [services]);
  });

  testWidgets('karta zgody: fokus na Odrzuć i Enter odmawia', (tester) async {
    final alicja = await uruchom(tester, 'Alicja');
    final bartek = await uruchom(tester, 'Bartek');
    final peer = await sparuj(tester, alicja, bartek);
    await tester.runAsync(() async {
      await alicja.setKeyboardAddon(true);
      await bartek.setKeyboardAddon(true);
      expect(await bartek.setRemoteInputReceive(true), isTrue);
    });

    await tester.pumpWidget(nakladka(bartek));
    await tester.pump();
    expect(find.textContaining('wants to type'), findsNothing);

    // Prośba leci prawdziwą drogą i czeka u Bartka na decyzję.
    late Future<RemoteInputStart> prosba;
    await tester.runAsync(() async {
      prosba = alicja.startRemoteInput(peer);
    });
    await czekajNa(tester, () => bartek.pendingRemoteInput.value.isNotEmpty);
    await tester.pump();
    expect(find.text('Alicja wants to type on this device'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);

    // Fokus przychodzi klatkę po pokazaniu karty.
    await tester.pump();
    final odrzuc = find.widgetWithText(TextButton, 'Reject');
    expect(odrzuc, findsOneWidget);
    final fokus = tester.widget<TextButton>(odrzuc).focusNode;
    expect(fokus, isNotNull);
    expect(fokus!.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final wynik = await tester.runAsync(() => prosba);
    expect(wynik, RemoteInputStart.rejected);
    expect(bartek.pendingRemoteInput.value, isEmpty);
    expect(bartek.incomingRemoteInput.value, isNull);
    await tester.pump();
    expect(find.text('Alicja wants to type on this device'), findsNothing);

    await sprzatnij(tester, [alicja, bartek]);
  });
}
