import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart' show DropTarget;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:flutter/services.dart' show LogicalKeyboardKey, MethodChannel;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/network/transport.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/ui/screens/chat_screen.dart';
import 'package:chatt/ui/screens/conversations_screen.dart';
import 'package:chatt/ui/screens/nearby_screen.dart';
import 'package:chatt/ui/styles.dart';
import 'package:chatt/ui/widgets/link_confirm.dart';
import 'package:chatt/ui/widgets/motion.dart';
import 'package:chatt/ui/widgets/pair_qr.dart';
import 'package:chatt/ui/widgets/paste_shortcut.dart';

/// Okna i zmiana rozmowy w ruchu stylu (issue #54): okno wchodzi i wychodzi
/// w czasach karty zgody, zasłona dochodzi do koloru stylu w swoim czasie,
/// panel ma czasy panelu, rozmowy na szerokim oknie przenikają się, a przy
/// „ogranicz animacje” każde z tych przejść to przenikanie 100 ms.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final teksty = lookupAppLocalizations(const Locale('en'));
  final telefonIOkno = TargetPlatformVariant(
      const {TargetPlatform.android, TargetPlatform.windows});
  final okno = TargetPlatformVariant.only(TargetPlatform.windows);

  Duration ms(int n) => Duration(milliseconds: n);

  Widget aplikacja(
    Widget ekran, {
    AppStyle? styl,
    Brightness jasnosc = Brightness.light,
    bool ograniczone = false,
    AppServices? services,
  }) {
    final app = MaterialApp(
      // Osobne drzewo przy każdym wywołaniu: bez przejścia od poprzedniego.
      key: UniqueKey(),
      theme: styl == null ? null : chattTheme(styl, jasnosc),
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // „Ogranicz animacje” z systemu tak, jak widzi je MediaQuery.
      builder: ograniczone
          ? (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              )
          : null,
      home: ekran,
    );
    if (services == null) return app;
    return ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: app,
    );
  }

  /// Otwiera pytanie przez [showChattDialog] nad pustym ekranem i robi
  /// pierwszą klatkę: przejście stoi na zerze.
  Future<({ChattDialogRoute<bool> route, Future<bool?> odpowiedz})> otworz(
    WidgetTester tester, {
    required AppStyle styl,
    Brightness jasnosc = Brightness.light,
    bool panel = false,
    bool ograniczone = false,
  }) async {
    late BuildContext pod;
    await tester.pumpWidget(aplikacja(
      Scaffold(
        body: Builder(builder: (context) {
          pod = context;
          return const SizedBox.expand();
        }),
      ),
      styl: styl,
      jasnosc: jasnosc,
      ograniczone: ograniczone,
    ));
    final odpowiedz = showChattDialog<bool>(
      context: pod,
      panel: panel,
      builder: (context) => AlertDialog(
        title: const Text('Pytanie'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nie'),
          ),
        ],
      ),
    );
    await tester.pump();
    final route = ModalRoute.of(tester.element(find.text('Pytanie')))!;
    return (route: route as ChattDialogRoute<bool>, odpowiedz: odpowiedz);
  }

  /// Przezroczystość, skala i przesunięcie w pionie okna w tej klatce.
  ({double krycie, double skala, double dy}) ruchOkna(WidgetTester tester) {
    final przejscie = find.byType(MotionTransition);
    final krycie = tester
        .widget<Opacity>(find
            .descendant(of: przejscie, matching: find.byType(Opacity))
            .first)
        .opacity;
    // W MotionTransition przesunięcie obejmuje skalę.
    final transformy = tester
        .widgetList<Transform>(
            find.descendant(of: przejscie, matching: find.byType(Transform)))
        .toList();
    return (
      krycie: krycie,
      skala: transformy[1].transform.entry(0, 0),
      dy: transformy[0].transform.entry(1, 3),
    );
  }

  Color zaslona(WidgetTester tester) => tester
      .widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier))
      .color
      .value!;

  bool znikajacyIgnoruje(WidgetTester tester) => tester
      .widget<IgnorePointer>(find
          .descendant(
              of: find.byType(MotionTransition),
              matching: find.byType(IgnorePointer))
          .first)
      .ignoring;

  /// Kontroler dochodzi do końca dokładnie po swoim czasie, stan zmienia
  /// w następnym tyknięciu, a trasa schodzi z ekranu w kolejnej klatce.
  Future<void> dokonczZejscie(WidgetTester tester) async {
    await tester.pump(ms(1));
    await tester.pump();
  }

  /// Zamyka pytanie przyciskiem: wyjście trwa dokładnie [wyjscie].
  Future<void> zamknij(
      WidgetTester tester, ChattDialogRoute<bool> route, Duration wyjscie,
      {Curve? krzywa}) async {
    await tester.tap(find.text('Nie'));
    await tester.pump();
    expect(route.animation!.status, AnimationStatus.reverse);
    expect(znikajacyIgnoruje(tester), isTrue,
        reason: 'znikające okno nie przyjmuje dotyku');
    final polowa = wyjscie ~/ 2;
    await tester.pump(polowa);
    if (krzywa != null) {
      expect(ruchOkna(tester).krycie, closeTo(krzywa.transform(0.5), 1e-6));
    }
    await tester.pump(wyjscie - polowa - ms(1));
    expect(route.animation!.value, greaterThan(0));
    await tester.pump(ms(1));
    expect(route.animation!.value, 0);
    expect(find.text('Pytanie'), findsOneWidget);
    await dokonczZejscie(tester);
    expect(find.text('Pytanie'), findsNothing);
  }

  group('okno', () {
    for (final styl in AppStyle.values) {
      testWidgets('${styl.name}: wchodzi w czasie karty zgody, wychodzi '
          'w swoim, zasłona stylu dochodzi do pełnej przed oknem',
          (tester) async {
        final m = chattMotion(styl);
        final telefon = defaultTargetPlatform == TargetPlatform.android;
        final skala = telefon ? m.cardScalePhone : m.cardScaleWindow;
        final przesuniecie = telefon ? m.cardShiftPhone : m.cardShiftWindow;
        final scrim = chattTheme(styl, Brightness.light).colorScheme.scrim;

        final (:route, :odpowiedz) = await otworz(tester, styl: styl);
        expect(route.panel, isFalse);
        expect(route.telefon, telefon);
        expect(route.transitionDuration, m.cardIn);
        expect(route.reverseTransitionDuration, m.cardOut);
        expect(zaslona(tester).a, 0);

        // W ćwierci wejścia: krzywa karty, skala i przesunięcie stylu dla
        // tej platformy, okno jeszcze prześwituje. Sprężynka Ciepła
        // przestrzeliwuje już przed połową.
        final cwierc = m.cardIn ~/ 4;
        await tester.pump(cwierc);
        final ruch = m.cardCurve.transform(0.25);
        final wejscie = ruchOkna(tester);
        expect(wejscie.krycie, closeTo(m.enter.transform(0.25), 1e-6));
        expect(wejscie.krycie, inExclusiveRange(0, 1));
        expect(wejscie.skala, closeTo(skala + (1 - skala) * ruch, 1e-6));
        expect(wejscie.dy, closeTo(przesuniecie * (1 - ruch), 1e-6));
        if (skala < 1) expect(wejscie.skala, lessThan(1));
        if (przesuniecie > 0) {
          expect(wejscie.dy, greaterThan(0), reason: 'z dołu');
        }
        if (przesuniecie < 0) {
          expect(wejscie.dy, lessThan(0), reason: 'z góry');
        }
        expect(zaslona(tester).a, inExclusiveRange(0, scrim.a));

        // Zasłona ma kolor stylu po swoim czasie, okno jeszcze jedzie.
        await tester.pump(m.scrim + ms(1) - cwierc);
        expect(zaslona(tester), scrim);
        expect(route.animation!.status, AnimationStatus.forward);

        // Wejście dochodzi na miejsce dokładnie po cardIn.
        await tester.pump(m.cardIn - m.scrim - ms(2));
        expect(route.animation!.value, lessThan(1));
        await tester.pump(ms(1));
        expect(route.animation!.value, 1);
        final koniec = ruchOkna(tester);
        expect(koniec.krycie, 1);
        expect(koniec.skala, 1);
        expect(koniec.dy, 0);
        await tester.pump(ms(1));
        expect(route.animation!.status, AnimationStatus.completed);
        expect(znikajacyIgnoruje(tester), isFalse);

        await zamknij(tester, route, m.cardOut, krzywa: m.exitReverse);
        expect(await odpowiedz, isFalse);
      }, variant: telefonIOkno);
    }

    testWidgets('Ciepło: sprężynka lekko przestrzeliwuje i staje na 1, '
        'Cisza i Precyzja nie przestrzeliwują', (tester) async {
      for (final styl in AppStyle.values) {
        final m = chattMotion(styl);
        final (:route, :odpowiedz) = await otworz(tester, styl: styl);
        var najwieksza = 0.0;
        for (var t = 5; t <= m.cardIn.inMilliseconds; t += 5) {
          await tester.pump(ms(5));
          final r = ruchOkna(tester);
          najwieksza = math.max(najwieksza, r.skala);
          // Sprężynka nie trafia w przezroczystość.
          expect(r.krycie, inInclusiveRange(0, 1), reason: styl.name);
        }
        expect(route.animation!.value, 1, reason: styl.name);
        expect(ruchOkna(tester).skala, 1, reason: styl.name);
        await tester.pump(ms(1));
        expect(route.animation!.status, AnimationStatus.completed,
            reason: styl.name);
        if (styl == AppStyle.cieplo) {
          expect(najwieksza, greaterThan(1));
          expect(najwieksza, lessThan(1.005));
        } else {
          expect(najwieksza, lessThanOrEqualTo(1), reason: styl.name);
        }
        await zamknij(tester, route, m.cardOut);
        expect(await odpowiedz, isFalse);
      }
    }, variant: okno);

    testWidgets('zasłona Ciszy: 36% w jasnym motywie, 55% w ciemnym',
        (tester) async {
      final m = chattMotion(AppStyle.cisza);
      for (final (jasnosc, krycie) in [
        (Brightness.light, 0.36),
        (Brightness.dark, 0.55),
      ]) {
        final (:route, :odpowiedz) =
            await otworz(tester, styl: AppStyle.cisza, jasnosc: jasnosc);
        await tester.pump(m.scrim + ms(1));
        final kolor = zaslona(tester);
        expect(kolor, chattTheme(AppStyle.cisza, jasnosc).colorScheme.scrim);
        expect(kolor.a, closeTo(krycie, 0.005), reason: jasnosc.name);
        expect(route.animation!.status, AnimationStatus.forward);
        await tester.pump(m.cardIn);
        await zamknij(tester, route, m.cardOut);
        expect(await odpowiedz, isFalse);
      }
    });

    for (final styl in AppStyle.values) {
      testWidgets('${styl.name}: panel na środku okna ma czasy i skalę '
          'panelu, bez przesunięcia i sprężynki', (tester) async {
        final m = chattMotion(styl);
        final scrim = chattTheme(styl, Brightness.light).colorScheme.scrim;
        final (:route, :odpowiedz) =
            await otworz(tester, styl: styl, panel: true);
        expect(route.panel, isTrue);
        expect(route.transitionDuration, m.panelIn);
        expect(route.reverseTransitionDuration, m.panelOut);

        await tester.pump(m.panelIn ~/ 2);
        final ruch = m.enter.transform(0.5);
        final polowa = ruchOkna(tester);
        expect(polowa.krycie, closeTo(m.enter.transform(0.5), 1e-6));
        expect(polowa.skala, closeTo(m.panelScale + (1 - m.panelScale) * ruch,
            1e-6));
        expect(polowa.skala, lessThan(1));
        expect(polowa.dy, 0);

        await tester.pump(m.scrim + ms(1) - m.panelIn ~/ 2);
        expect(zaslona(tester), scrim);
        expect(route.animation!.status, AnimationStatus.forward);

        var najwieksza = 0.0;
        var uplynelo = m.scrim + ms(1);
        while (uplynelo < m.panelIn - ms(1)) {
          await tester.pump(ms(1));
          uplynelo += ms(1);
          najwieksza = math.max(najwieksza, ruchOkna(tester).skala);
        }
        expect(najwieksza, lessThanOrEqualTo(1));
        expect(route.animation!.value, lessThan(1));
        await tester.pump(ms(1));
        expect(route.animation!.value, 1);
        expect(ruchOkna(tester).skala, 1);
        await tester.pump(ms(1));
        expect(route.animation!.status, AnimationStatus.completed);

        await zamknij(tester, route, m.panelOut, krzywa: m.exitReverse);
        expect(await odpowiedz, isFalse);
      }, variant: okno);
    }

    for (final styl in AppStyle.values) {
      testWidgets('${styl.name}: przy „ogranicz animacje” okno i panel to '
          'przenikanie 100 ms bez skali i przesunięcia', (tester) async {
        final scrim = chattTheme(styl, Brightness.light).colorScheme.scrim;
        for (final panel in [false, true]) {
          final (:route, :odpowiedz) = await otworz(tester,
              styl: styl, panel: panel, ograniczone: true);
          expect(route.transitionDuration, ChattMotion.reducedDuration);
          expect(route.reverseTransitionDuration, ChattMotion.reducedDuration);

          await tester.pump(ms(50));
          final polowa = ruchOkna(tester);
          expect(polowa.krycie, closeTo(0.5, 1e-6), reason: '$panel');
          expect(polowa.skala, 1, reason: '$panel');
          expect(polowa.dy, 0, reason: '$panel');
          // Zasłona rośnie równo z oknem.
          expect(zaslona(tester).a, closeTo(scrim.a / 2, 0.01));

          await tester.pump(ms(49));
          expect(route.animation!.value, lessThan(1));
          await tester.pump(ms(1));
          expect(route.animation!.value, 1);
          expect(zaslona(tester), scrim);
          await tester.pump(ms(1));
          expect(route.animation!.status, AnimationStatus.completed);

          await zamknij(tester, route, ChattMotion.reducedDuration,
              krzywa: Curves.linear);
          expect(await odpowiedz, isFalse);
        }
      }, variant: telefonIOkno);
    }
  });

  testWidgets('pytanie przed otwarciem odnośnika idzie w ruchu stylu',
      (tester) async {
    await tester.pumpWidget(aplikacja(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                confirmAndOpenLink(context, Uri.parse('https://example.com/a')),
            child: const Text('Odnośnik'),
          ),
        ),
      ),
      styl: AppStyle.cieplo,
    ));
    await tester.tap(find.text('Odnośnik'));
    await tester.pump();
    final route =
        ModalRoute.of(tester.element(find.text(teksty.linkConfirmTitle)));
    expect(route, isA<ChattDialogRoute<bool>>());
    expect((route! as ChattDialogRoute<bool>).motion,
        same(chattMotion(AppStyle.cieplo)));
    expect(route.barrierDismissible, isTrue);

    await tester.pump(chattMotion(AppStyle.cieplo).cardIn);
    await tester.tap(find.text(teksty.cancel));
    await tester.pump();
    await tester.pump(chattMotion(AppStyle.cieplo).cardOut);
    await dokonczZejscie(tester);
    expect(find.text(teksty.linkConfirmTitle), findsNothing);
  });

  group('na żywo', () {
    late Directory katalog;
    setUp(() => katalog = Directory.systemTemp.createTempSync('chatt_okna_'));
    tearDown(() => katalog.deleteSync(recursive: true));

    Future<AppServices> uruchom(WidgetTester tester, String nazwa) async =>
        (await tester.runAsync(() => AppServices.start(
              executor: NativeDatabase.memory(),
              portOverride: 0,
              nameOverride: nazwa,
              enableDiscovery: false,
              receivedDirOverride: '${katalog.path}/$nazwa',
            )))!;

    Future<void> sprzatnij(
        WidgetTester tester, List<AppServices> wszystkie) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      for (final services in wszystkie) {
        await tester.runAsync(services.dispose);
      }
    }

    /// Stuknięcie idzie w fałszywym czasie testu, baza i sieć w prawdziwym.
    Future<void> dokoncz(WidgetTester tester, bool Function() warunek) async {
      for (var i = 0; i < 100 && !warunek(); i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(warunek(), isTrue);
    }

    /// Rozmowy z Alicją i Bartkiem, bez adresów: obecność odpowiada od
    /// razu, bez sieci.
    Future<Map<String, int>> rozmowy(
            WidgetTester tester, AppServices services) async =>
        (await tester.runAsync(() async => {
              for (final nazwa in ['Alicja', 'Bartek'])
                nazwa: await services.db.ensureConversation((await services.db
                        .upsertPeer(
                          guid: 'guid-$nazwa',
                          name: nazwa,
                          welcomeMessage: '',
                          host: '',
                          port: 0,
                        ))
                    .id),
            }))!;

    ChattDialogRoute<Object?>? trasa(WidgetTester tester, Finder w) {
      final route = ModalRoute.of(tester.element(w));
      return route is ChattDialogRoute ? route : null;
    }

    // Prawy panel na szerokim oknie: za listą (360) i kreską (1) do końca.
    const prawyPanel = Rect.fromLTRB(361, 0, 1280, 800);

    void szerokie(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Finder rozmowa(Map<String, int> id, String nazwa) => find.byWidgetPredicate(
        (w) => w is ChatScreen && w.conversationId == id[nazwa]);

    /// Obrazy poprzednich paneli, które jeszcze znikają.
    final obrazy = find.descendant(
        of: find.byType(ConversationsScreen), matching: find.byType(RawImage));

    double krycie(WidgetTester tester, Finder f) => tester
        .widget<FadeTransition>(
            find.ancestor(of: f, matching: find.byType(FadeTransition)).first)
        .opacity
        .value;

    bool ignoruje(WidgetTester tester, Finder f) => tester
        .widget<IgnorePointer>(
            find.ancestor(of: f, matching: find.byType(IgnorePointer)).first)
        .ignoring;

    bool trafia(WidgetTester tester, Finder f, Offset punkt) {
      final cel = tester.renderObject(f);
      return tester
          .hitTestOnBinding(punkt)
          .path
          .any((wpis) => wpis.target == cel);
    }

    /// Szeroka lista z Alicją i Bartkiem, w prawym panelu jeszcze nic.
    Future<Map<String, int>> lista(WidgetTester tester, AppServices services,
        {required AppStyle styl, bool ograniczone = false}) async {
      final id = await rozmowy(tester, services);
      await tester.pumpWidget(aplikacja(const ConversationsScreen(),
          styl: styl, ograniczone: ograniczone, services: services));
      await dokoncz(tester, () => find.byType(ListTile).evaluate().length == 2);
      return id;
    }

    /// Stuknięcie w rozmowę [nazwa]: ekran [stary] schodzi od razu, jego
    /// obraz znika w czasie zmiany panelu, [nowy] wchodzi w tym samym czasie.
    Future<void> przejdz(WidgetTester tester, ChattMotion m,
        {required Finder stary,
        required Finder nowy,
        required String nazwa}) async {
      expect(stary, findsOneWidget);
      expect(obrazy, findsNothing);
      await tester.tap(find.widgetWithText(ListTile, nazwa));
      await tester.pump();
      // Po starym panelu został obraz całego panelu, żywa jest tylko nowa
      // rozmowa.
      expect(stary, findsNothing);
      expect(nowy, findsOneWidget);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(obrazy, findsOneWidget);
      final obraz = tester.widget<RawImage>(obrazy).image!;
      expect((obraz.width, obraz.height), (919, 800));
      // Obraz to narysowana klatka panelu: tło w rogu i na środku kryje.
      final piksele = (await tester.runAsync(obraz.toByteData))!;
      expect(piksele.getUint8(3), 255);
      expect(piksele.getUint8((400 * 919 + 460) * 4 + 3), 255);
      expect(krycie(tester, nowy), 0);
      expect(krycie(tester, obrazy), 1);

      final polowa = m.paneSwitch ~/ 2;
      await tester.pump(polowa);
      expect(krycie(tester, nowy), closeTo(m.enter.transform(0.5), 1e-6));
      expect(
          krycie(tester, obrazy), closeTo(m.exitReverse.transform(0.5), 1e-6));
      expect(krycie(tester, nowy), inExclusiveRange(0, 1));
      // Oba panele leżą na sobie i wypełniają miejsce, dotyk trafia w nowy.
      expect(tester.getRect(nowy), prawyPanel);
      expect(tester.getRect(obrazy), prawyPanel);
      expect(ignoruje(tester, obrazy), isTrue, reason: 'znikający bez dotyku');
      expect(trafia(tester, nowy, prawyPanel.center), isTrue);

      await tester.pump(m.paneSwitch - polowa - ms(1));
      expect(krycie(tester, nowy), lessThan(1));
      expect(krycie(tester, obrazy), greaterThan(0));
      await tester.pump(ms(1));
      expect(krycie(tester, nowy), 1);
      expect(krycie(tester, obrazy), 0);
      await dokonczZejscie(tester);
      expect(obrazy, findsNothing);
      expect(nowy, findsOneWidget);
      expect(krycie(tester, nowy), 1);
      expect(find.byType(ChatScreen), findsOneWidget);
    }

    final przypadki = [
      for (final styl in AppStyle.values) (styl, false),
      (AppStyle.cisza, true),
    ];
    for (final (styl, ograniczone) in przypadki) {
      final m = ograniczone ? chattMotion(styl).reduced : chattMotion(styl);
      final opis = ograniczone ? ' przy „ogranicz animacje”' : '';
      testWidgets('${styl.name}$opis: zmiana rozmowy na szerokim oknie '
          'przenika panel w ${m.paneSwitch.inMilliseconds} ms, ekran starej '
          'rozmowy schodzi od razu', (tester) async {
        szerokie(tester);
        final services = await uruchom(tester, 'Pixel');
        final id = await lista(tester, services,
            styl: styl, ograniczone: ograniczone);

        await przejdz(tester, m,
            stary: find.text(teksty.pickConversation),
            nowy: rozmowa(id, 'Alicja'),
            nazwa: 'Alicja');
        await przejdz(tester, m,
            stary: rozmowa(id, 'Alicja'),
            nowy: rozmowa(id, 'Bartek'),
            nazwa: 'Bartek');

        await sprzatnij(tester, [services]);
      });
    }

    testWidgets('systemowe „ogranicz animacje”: zmiana rozmowy to '
        'przenikanie 100 ms, także po rozmowie otwartej przed zmianą '
        'ustawienia', (tester) async {
      szerokie(tester);
      final services = await uruchom(tester, 'Pixel');
      final id = await lista(tester, services, styl: AppStyle.cisza);
      await tester.tap(find.widgetWithText(ListTile, 'Alicja'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Ustawienie z systemu: Flutter skraca wtedy zwykłe animacje do 5%.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pump();
      expect(SemanticsBinding.instance.disableAnimations, isTrue);
      expect(
          MediaQuery.of(tester.element(find.byType(ConversationsScreen)))
              .disableAnimations,
          isTrue);

      await przejdz(tester, chattMotion(AppStyle.cisza).reduced,
          stary: rozmowa(id, 'Alicja'),
          nowy: rozmowa(id, 'Bartek'),
          nazwa: 'Bartek');

      await sprzatnij(tester, [services]);
    });

    testWidgets('zmiana w trakcie przenikania: obraz przerwanego panelu '
        'znika od krycia, które miał', (tester) async {
      szerokie(tester);
      final m = chattMotion(AppStyle.cisza);
      final polowa = m.paneSwitch ~/ 2;
      final services = await uruchom(tester, 'Pixel');
      final id = await lista(tester, services, styl: AppStyle.cisza);
      await tester.tap(find.widgetWithText(ListTile, 'Alicja'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.widgetWithText(ListTile, 'Bartek'));
      await tester.pump();
      await tester.pump(polowa);
      final bartek = krycie(tester, rozmowa(id, 'Bartek'));
      expect(bartek, closeTo(m.enter.transform(0.5), 1e-6));

      await tester.tap(find.widgetWithText(ListTile, 'Alicja'));
      await tester.pump();
      // Obraz Alicji znika dalej, obraz Bartka zaczyna od jego krycia.
      expect(obrazy, findsNWidgets(2));
      expect(krycie(tester, obrazy.at(0)),
          closeTo(m.exitReverse.transform(0.5), 1e-6));
      expect(krycie(tester, obrazy.at(1)), closeTo(bartek, 1e-6));
      expect(krycie(tester, rozmowa(id, 'Alicja')), 0);
      expect(find.byType(ChatScreen), findsOneWidget);

      await tester.pump(polowa);
      expect(krycie(tester, obrazy.last),
          closeTo(bartek * m.exitReverse.transform(0.5), 1e-6));
      await tester.pump(m.paneSwitch - polowa);
      await dokonczZejscie(tester);
      expect(obrazy, findsNothing);
      expect(krycie(tester, rozmowa(id, 'Alicja')), 1);
      expect(find.byType(ChatScreen), findsOneWidget);

      await sprzatnij(tester, [services]);
    });

    testWidgets('Ctrl+V w trakcie przenikania trafia tylko do nowej '
        'rozmowy, pliki upuszcza się tylko na nią', (tester) async {
      szerokie(tester);
      const kanal = MethodChannel('chatt/clipboard');
      var wklejenia = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(kanal,
          (call) async {
        if (call.method == 'pasteFiles') wklejenia++;
        return <String>[];
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(kanal, null));
      final m = chattMotion(AppStyle.cisza);
      final services = await uruchom(tester, 'Pixel');
      final id = await lista(tester, services, styl: AppStyle.cisza);
      await tester.tap(find.widgetWithText(ListTile, 'Alicja'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      Future<void> ctrlV() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await tester.tap(find.widgetWithText(ListTile, 'Bartek'));
      await tester.pump();
      await tester.pump(m.paneSwitch ~/ 2);
      expect(obrazy, findsOneWidget, reason: 'w trakcie przenikania');
      expect(rozmowa(id, 'Alicja'), findsNothing);
      expect(find.byType(PasteShortcut), findsOneWidget);
      expect(find.byType(DropTarget), findsOneWidget);
      await ctrlV();
      expect(wklejenia, 1);

      await tester.pump(m.paneSwitch);
      await ctrlV();
      expect(wklejenia, 2);

      await sprzatnij(tester, [services]);
    });

    testWidgets('usunięcie rozmowy pyta w ruchu stylu, zasłona zamyka',
        (tester) async {
      final services = await uruchom(tester, 'Pixel');
      await rozmowy(tester, services);
      await tester.pumpWidget(aplikacja(const ConversationsScreen(),
          styl: AppStyle.precyzja, services: services));
      await dokoncz(tester, () => find.byType(ListTile).evaluate().length == 2);
      final m = chattMotion(AppStyle.precyzja);

      await tester.longPress(find.widgetWithText(ListTile, 'Alicja'));
      await tester.pump();
      final tytul = find.text(teksty.deleteConversationTitle('Alicja'));
      final route = trasa(tester, tytul);
      expect(route, isA<ChattDialogRoute<bool>>());
      expect(route!.motion, same(m));
      expect(route.barrierDismissible, isTrue);

      await tester.pump(m.cardIn);
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      await tester.pump(m.cardOut);
      await dokonczZejscie(tester);
      expect(tytul, findsNothing);
      expect(find.widgetWithText(ListTile, 'Alicja'), findsOneWidget);

      await sprzatnij(tester, [services]);
    });

    testWidgets('W pobliżu: dodanie po adresie, po adresie Bluetooth '
        'i zapomnienie urządzenia pytają w ruchu stylu', (tester) async {
      final alicja = await uruchom(tester, 'Alicja');
      final bartek = await uruchom(tester, 'Bartek');
      final m = chattMotion(AppStyle.cisza);
      await tester.pumpWidget(aplikacja(const NearbyScreen(),
          styl: AppStyle.cisza, services: alicja));
      await tester.pump();

      Future<void> anuluj(Finder tytul) async {
        await tester.tap(find.text(teksty.cancel));
        await tester.pump();
        await tester.pump(m.cardOut);
        await dokonczZejscie(tester);
        expect(tytul, findsNothing);
      }

      // Po adresie IP: do Bartka, który naprawdę słucha.
      await tester.tap(find.byIcon(Icons.add_link));
      await tester.pump();
      final poIp = find.text(teksty.manualAddTitle);
      expect(trasa(tester, poIp), isA<ChattDialogRoute<(String, int)>>());
      await tester.pump(m.cardIn);
      await tester.enterText(
          find.widgetWithText(TextField, teksty.ipLabel), '127.0.0.1');
      await tester.enterText(find.widgetWithText(TextField, teksty.portLabel),
          '${bartek.server.port}');
      await tester.tap(find.text(teksty.connect));
      await dokoncz(
          tester, () => find.byType(ChatScreen).evaluate().isNotEmpty);
      expect(poIp, findsNothing);

      // Z rozmowy z powrotem na listę i zapomnienie Bartka.
      Navigator.of(tester.element(find.byType(ChatScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.longPress(find.widgetWithText(ListTile, 'Bartek'));
      await tester.pump();
      final zapomnij = find.text(teksty.deleteDeviceTitle('Bartek'));
      expect(trasa(tester, zapomnij), isA<ChattDialogRoute<bool>>());
      await tester.pump(m.cardIn);
      await anuluj(zapomnij);
      expect(find.widgetWithText(ListTile, 'Bartek'), findsOneWidget);

      // Po adresie Bluetooth.
      alicja.bluetoothAddon.value = true;
      alicja.bluetoothRunning.value = true;
      await tester.pump();
      await tester.tap(find.descendant(
          of: find.byType(SegmentedButton<PeerProtocol>),
          matching: find.text(teksty.protocolBluetooth)));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add_link));
      await tester.pump();
      final poBt = find.text(teksty.manualAddBtTitle);
      expect(trasa(tester, poBt), isA<ChattDialogRoute<String>>());
      await tester.pump(m.cardIn);
      await anuluj(poBt);

      alicja.bluetoothRunning.value = false;
      alicja.bluetoothAddon.value = false;
      await sprzatnij(tester, [alicja, bartek]);
    });

    testWidgets('kod QR tego urządzenia otwiera się w ruchu stylu',
        (tester) async {
      final services = await uruchom(tester, 'Pixel');
      await tester.pumpWidget(aplikacja(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPairQr(context),
              child: const Text('Kod'),
            ),
          ),
        ),
        styl: AppStyle.precyzja,
        services: services,
      ));
      await tester.tap(find.text('Kod'));
      await tester.pump();
      final tytul = find.text(teksty.qrShowTitle);
      final route = trasa(tester, tytul);
      expect(route, isA<ChattDialogRoute<void>>());
      expect(route!.motion, same(chattMotion(AppStyle.precyzja)));

      await tester.pump(chattMotion(AppStyle.precyzja).cardIn);
      await tester.tap(find.text(teksty.close));
      await tester.pump();
      await tester.pump(chattMotion(AppStyle.precyzja).cardOut);
      await dokonczZejscie(tester);
      expect(tytul, findsNothing);

      await sprzatnij(tester, [services]);
    });
  });

  group('flaga systemu „usuń animacje”', () {
    // Flaga z systemu skraca zwykłe kontrolery do 5% czasu. Trasy, karty
    // zgody i wejścia dymków mają kontrolery z zachowanym czasem, więc
    // przenikanie stylu trwa naprawdę 100 ms.
    void flaga(WidgetTester tester) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }

    /// Postęp trasy, w której stoi [cel].
    double postep(WidgetTester tester, Finder cel) =>
        ModalRoute.of(tester.element(cel))!.animation!.value;

    /// Przezroczystość najbliższego przejścia nad [cel].
    double widac(WidgetTester tester, Finder cel) => tester
        .widget<Opacity>(
            find.ancestor(of: cel, matching: find.byType(Opacity)).first)
        .opacity;

    /// Trasa wchodzi w 100 ms i schodzi w 100 ms.
    Future<void> trasaW100(
        WidgetTester tester, String tekst, Future<void> Function() otworz) async {
      final cel = find.text(tekst);
      unawaited(otworz());
      await tester.pump();
      await tester.pump(ms(50));
      expect(postep(tester, cel), closeTo(0.5, 0.02), reason: '$tekst: wejście');
      await tester.pump(ms(51));
      expect(postep(tester, cel), 1, reason: tekst);
      Navigator.of(tester.element(cel)).pop();
      await tester.pump();
      await tester.pump(ms(50));
      expect(postep(tester, cel), closeTo(0.5, 0.02), reason: '$tekst: wyjście');
      await tester.pump(ms(51));
      await tester.pump();
      expect(cel, findsNothing, reason: tekst);
    }

    testWidgets('okno, arkusz i nowy ekran przenikają w 100 ms',
        (tester) async {
      flaga(tester);
      late BuildContext ekran;
      await tester.pumpWidget(MaterialApp(
        // Jak w ChattApp: motyw z ruchem ograniczonym, bo czas przejścia
        // ekranu bierze się z motywu.
        theme: chattTheme(AppStyle.cisza, Brightness.light, reduceMotion: true),
        home: Builder(builder: (context) {
          ekran = context;
          return const Scaffold(body: SizedBox.expand());
        }),
      ));

      await trasaW100(
          tester,
          'okno',
          () => showChattDialog<void>(
              context: ekran,
              builder: (_) => const AlertDialog(title: Text('okno'))));
      await trasaW100(
          tester,
          'arkusz',
          () => showChattSheet<void>(
              context: ekran,
              builder: (_) =>
                  const SizedBox(height: 200, child: Text('arkusz'))));
      await trasaW100(
          tester,
          'ekran',
          () => Navigator.of(ekran).push(ChattPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('ekran')))));
    });

    testWidgets('karta zgody i nowy dymek przenikają w 100 ms bez ruchu',
        (tester) async {
      flaga(tester);
      Widget? karta;
      var dymek = false;
      late StateSetter ustaw;
      await tester.pumpWidget(MaterialApp(
        // Ciepło: sprężynka i przesunięcie z góry znikają przy fladze.
        theme: chattTheme(AppStyle.cieplo, Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            ustaw = setState;
            final m = ChattMotion.of(context);
            return Column(children: [
              CardSwitcher(child: karta),
              if (dymek)
                EnterOnce(
                  animate: true,
                  duration: m.bubble,
                  curve: m.bubbleCurve,
                  shift: m.bubbleShift,
                  child: const Text('dymek'),
                ),
            ]);
          }),
        ),
      ));

      ustaw(() => karta = const Text('karta', key: ValueKey(1)));
      await tester.pump();
      final miejsce = tester.getRect(find.text('karta'));
      await tester.pump(ms(50));
      expect(widac(tester, find.text('karta')), closeTo(0.5, 0.02));
      expect(tester.getRect(find.text('karta')), miejsce);
      await tester.pump(ms(51));
      expect(widac(tester, find.text('karta')), 1);

      ustaw(() => karta = null);
      await tester.pump();
      await tester.pump(ms(50));
      expect(widac(tester, find.text('karta')), closeTo(0.5, 0.02));
      await tester.pump(ms(51));
      await tester.pump();
      expect(find.text('karta'), findsNothing);

      ustaw(() => dymek = true);
      await tester.pump();
      await tester.pump(ms(50));
      expect(widac(tester, find.text('dymek')), closeTo(0.5, 0.02));
      await tester.pump(ms(51));
      expect(widac(tester, find.text('dymek')), 1);
    });
  });
}
