import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/app.dart';
import 'package:chatt/core/crypto.dart';
import 'package:chatt/core/version.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/ui/screens/conversations_screen.dart';
import 'package:chatt/ui/screens/settings_screen.dart';
import 'package:chatt/ui/styles.dart';
import 'package:chatt/ui/widgets/common.dart';
import 'package:chatt/ui/widgets/toasts.dart';

/// Kontrast WCAG między dwoma kolorami.
double kontrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (jasny, ciemny) = la > lb ? (la, lb) : (lb, la);
  return (jasny + 0.05) / (ciemny + 0.05);
}

/// Trzy style (issue #37) różnią się wyłącznie wyglądem: te same ekrany, te
/// same informacje. Sprawdzamy, że każdy z sześciu wariantów da się czytać,
/// że ma swoje fonty i że wybór stylu przeżywa restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const fonty = {
    AppStyle.cisza: ('Figtree', 'DMMono'),
    AppStyle.precyzja: ('IBMPlexSans', 'IBMPlexMono'),
    AppStyle.cieplo: ('Nunito', 'SplineSansMono'),
  };

  group('sześć wariantów', () {
    for (final styl in AppStyle.values) {
      for (final jasnosc in Brightness.values) {
        test('${styl.name} ${jasnosc.name}: tokeny, fonty i kontrast', () {
          final theme = chattTheme(styl, jasnosc);
          final k = theme.extension<ChattTokens>()!;
          final scheme = theme.colorScheme;
          expect(k.style, styl);
          expect(theme.brightness, jasnosc);
          expect(scheme.brightness, jasnosc);

          final (tekst, mono) = fonty[styl]!;
          expect(theme.textTheme.bodyLarge!.fontFamily, tekst);
          expect(theme.textTheme.titleMedium!.fontFamily, tekst);
          expect(k.mono.fontFamily, mono);
          expect(k.code.fontFamily, mono);

          // Tekst czytany ciągiem: co najmniej 4,5:1 (WCAG AA).
          final pary = <String, (Color, Color)>{
            'tekst na powierzchni': (scheme.onSurface, scheme.surface),
            'tekst na tle': (scheme.onSurface, k.background),
            'tekst drugorzędny': (scheme.onSurfaceVariant, scheme.surface),
            'mój dymek': (k.onBubbleMine, k.bubbleMine),
            'dymek rozmówcy': (k.onBubbleTheirs, k.bubbleTheirs),
            'przycisk': (scheme.onPrimary, scheme.primary),
            'ostrzeżenie': (k.security.foreground, k.security.background),
            'zagrożenie': (k.dangerNote.foreground, k.dangerNote.background),
            'potwierdzenie':
                (k.verifiedNote.foreground, k.verifiedNote.background),
            'komunikat': (k.onToast, k.toast),
          };
          for (final MapEntry(key: nazwa, value: (przod, tyl))
              in pary.entries) {
            expect(kontrast(przod, tyl), greaterThanOrEqualTo(4.5),
                reason: '$nazwa: ${kontrast(przod, tyl).toStringAsFixed(2)}');
          }
          // Odnośnik na dymku rozmówcy ma kolor główny i podkreślenie: 3:1.
          expect(kontrast(scheme.primary, k.bubbleTheirs),
              greaterThanOrEqualTo(3),
              reason: 'odnośnik: '
                  '${kontrast(scheme.primary, k.bubbleTheirs).toStringAsFixed(2)}');
          // Godzina i stan w dymku są drobne, ale pomocnicze: 3:1.
          expect(kontrast(k.bubbleMineMeta, k.bubbleMine),
              greaterThanOrEqualTo(3));
          expect(kontrast(k.bubbleTheirsMeta, k.bubbleTheirs),
              greaterThanOrEqualTo(3));

          expect(k.walls, hasLength(5));
          expect(k.avatars, isNotEmpty);
        });
      }
    }
  });

  test('ostrzeżenie bezpieczeństwa: czerwone w Ciszy, bursztynowe w '
      'Precyzji i Cieple', () {
    for (final jasnosc in Brightness.values) {
      final cisza = chattTokens(AppStyle.cisza, jasnosc);
      expect(cisza.security.icon, cisza.danger);
      for (final styl in [AppStyle.precyzja, AppStyle.cieplo]) {
        final k = chattTokens(styl, jasnosc);
        expect(k.security.icon, k.warning, reason: styl.name);
        expect(k.security.icon, isNot(k.danger), reason: styl.name);
      }
    }
  });

  test('każdy font stylu jest zadeklarowany w pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final (tekst, mono) in fonty.values) {
      expect(pubspec, contains('family: $tekst'), reason: tekst);
      expect(pubspec, contains('family: $mono'), reason: mono);
    }
  });

  testWidgets('licznik nieprzeczytanych w wierszu listy ma rozmiar swojej '
      'liczby w każdym stylu', (tester) async {
    for (final styl in AppStyle.values) {
      await tester.pumpWidget(MaterialApp(
        theme: chattTheme(styl, Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ListTile(
              title: const Text('Alicja'),
              trailing: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [Text('16:07'), UnreadCount(count: 3)],
              ),
            ),
          ),
        ),
      ));
      final rozmiar = tester.getSize(find.byType(UnreadCount));
      expect(rozmiar.width, lessThan(40), reason: styl.name);
      expect(rozmiar.height, lessThan(30), reason: styl.name);
      expect(find.text('Alicja'), findsOneWidget);
    }
  });

  testWidgets('bez rozszerzenia w motywie tokeny to Cisza', (tester) async {
    late ChattTokens k;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        k = ChattTokens.of(context);
        return const SizedBox();
      }),
    ));
    expect(k.style, AppStyle.cisza);
  });

  group('na żywo', () {
    late Directory katalog;
    setUp(() => katalog = Directory.systemTemp.createTempSync('chatt_styl_'));
    tearDown(() => katalog.deleteSync(recursive: true));

    Future<AppServices> uruchom(WidgetTester tester) async =>
        (await tester.runAsync(() => AppServices.start(
              executor: NativeDatabase.memory(),
              portOverride: 0,
              nameOverride: 'Pixel Mysttic',
              enableDiscovery: false,
              receivedDirOverride: '${katalog.path}/odebrane',
            )))!;

    Future<void> sprzatnij(WidgetTester tester, AppServices services) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(services.dispose);
    }

    /// Stuknięcie idzie w fałszywym czasie testu, baza w prawdziwym. Krok
    /// zegara testu przesuwa też przejście między motywami (200 ms).
    Future<void> dokoncz(WidgetTester tester, bool Function() warunek) async {
      for (var i = 0; i < 50 && !warunek(); i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(warunek(), isTrue);
    }

    testWidgets('aplikacja przełącza styl od razu, a na górze listy stoi '
        'nazwa urządzenia', (tester) async {
      final services = await uruchom(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const ChattApp(),
      ));
      await dokoncz(tester,
          () => find.text('Pixel Mysttic').evaluate().isNotEmpty);
      expect(find.textContaining(appVersion), findsNothing,
          reason: 'wersja mieszka w Ustawieniach');

      ChattTokens tokeny() => ChattTokens.of(
          tester.element(find.text('Pixel Mysttic')));
      expect(tokeny().style, AppStyle.cisza);

      for (final styl in [AppStyle.precyzja, AppStyle.cieplo, AppStyle.cisza]) {
        await tester.runAsync(() => services.db.saveStyle(styl));
        await dokoncz(tester, () => tokeny().style == styl);
        expect(
            Theme.of(tester.element(find.text('Pixel Mysttic')))
                .textTheme
                .bodyLarge!
                .fontFamily,
            fonty[styl]!.$1);
      }

      await sprzatnij(tester, services);
    });

    testWidgets('Ustawienia: wybór stylu zapisuje się w bazie, panel „To '
        'urządzenie" kopiuje identyfikator', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final teksty = lookupAppLocalizations(const Locale('en'));

      String? schowek;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            schowek = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final services = await uruchom(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ));
      await dokoncz(
          tester, () => find.text(teksty.stylePrecyzja).evaluate().isNotEmpty);

      // Trzy style do wyboru, Cisza na start.
      final wybor = tester.widget<SegmentedButton<AppStyle>>(
          find.byType(SegmentedButton<AppStyle>));
      expect(wybor.selected, {AppStyle.cisza});
      expect(find.text(teksty.styleCisza), findsOneWidget);
      expect(find.text(teksty.styleCieplo), findsOneWidget);

      await tester.tap(find.text(teksty.stylePrecyzja));
      await tester.pump();
      // Zaznaczenie idzie za bazą: zmienia się dopiero po zapisie.
      await dokoncz(
          tester,
          () =>
              tester
                  .widget<SegmentedButton<AppStyle>>(
                      find.byType(SegmentedButton<AppStyle>))
                  .selected
                  .single ==
              AppStyle.precyzja);
      final zapisane = await tester.runAsync(services.db.getSettings);
      expect(zapisane!.style, AppStyle.precyzja);

      // Panel na samym dole: identyfikator i odcisk fontem o stałej
      // szerokości, każdy z przyciskiem kopiowania.
      final identyfikator = find.byWidgetPredicate((w) =>
          w is SelectableText && w.data == services.identity.guid);
      await tester.scrollUntilVisible(identyfikator, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      expect(find.text(teksty.thisDevice), findsOneWidget);
      final odcisk = ChattCrypto.fingerprint(services.identity.publicKey);
      expect(
          find.byWidgetPredicate((w) =>
              w is SelectableText &&
              (w.data ?? '').replaceAll('\n', ' ') == odcisk),
          findsOneWidget);
      expect(tester.widget<SelectableText>(identyfikator).style!.fontFamily,
          'DMMono');

      final wiersz = find.ancestor(
          of: identyfikator, matching: find.byType(Row)).first;
      await tester.tap(find.descendant(
          of: wiersz, matching: find.byTooltip(teksty.copy)));
      await tester.pump();
      expect(schowek, services.identity.guid);
      expect(chattToasts.value.map((t) => t.text), contains(teksty.copied));
      chattToasts.clear();

      await sprzatnij(tester, services);
    });

    testWidgets('lista rozmów: w każdym stylu każda rozmowa jest osobną '
        'kartą, a ostatnia kończy się nad paskiem systemu', (tester) async {
      // Telefon z paskiem nawigacji systemu wysokim na 48 dp.
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(bottom: 144);
      tester.view.viewPadding = const FakeViewPadding(bottom: 144);
      addTearDown(tester.view.reset);
      const pasekSystemu = 48.0;

      final services = await uruchom(tester);
      await tester.runAsync(() async {
        for (final nazwa in ['Alicja', 'Bartek', 'Celina']) {
          final peer = await services.db.upsertPeer(
            guid: 'guid-$nazwa',
            name: nazwa,
            welcomeMessage: '',
            host: '',
            port: 0,
          );
          await services.db.ensureConversation(peer.id);
        }
      });

      for (final styl in AppStyle.values) {
        final theme = chattTheme(styl, Brightness.light);
        final k = theme.extension<ChattTokens>()!;
        await tester.pumpWidget(ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: MaterialApp(
            // Osobne drzewo na styl: bez przejścia od poprzedniego motywu.
            key: ValueKey(styl),
            theme: theme,
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ConversationsScreen(),
          ),
        ));
        await dokoncz(
            tester, () => find.byType(ListTile).evaluate().length == 3);

        // Najbliższy Material nad wierszem to jego karta: obejmuje tylko
        // ten jeden wiersz i ma kształt, kolor i obrys stylu.
        final karty = <Rect>[];
        for (var i = 0; i < 3; i++) {
          final karta = find
              .ancestor(
                  of: find.byType(ListTile).at(i),
                  matching: find.byType(Material))
              .first;
          expect(find.descendant(of: karta, matching: find.byType(ListTile)),
              findsOneWidget,
              reason: styl.name);
          final material = tester.widget<Material>(karta);
          expect(material.color, k.surface1, reason: styl.name);
          final ksztalt = material.shape! as RoundedRectangleBorder;
          expect(ksztalt.borderRadius, BorderRadius.circular(k.radiusRow),
              reason: styl.name);
          expect(
              ksztalt.side,
              styl == AppStyle.precyzja
                  ? BorderSide(color: k.outline)
                  : BorderSide.none,
              reason: styl.name);
          final cien = tester.widget<DecoratedBox>(find
              .ancestor(of: karta, matching: find.byType(DecoratedBox))
              .first);
          expect((cien.decoration as BoxDecoration).boxShadow, k.shadow1,
              reason: styl.name);
          karty.add(tester.getRect(karta));
        }
        // Między kartami 8 dp tła ekranu, bez linii oddzielających.
        expect(karty[1].top - karty[0].bottom, 8, reason: styl.name);
        expect(karty[2].top - karty[1].bottom, 8, reason: styl.name);
        expect(find.byType(Divider), findsNothing, reason: styl.name);

        // Listy nie obejmuje wspólny panel w kolorze powierzchni.
        final lista = find.byType(ListView);
        for (final material in tester.widgetList<Material>(
            find.ancestor(of: lista, matching: find.byType(Material)))) {
          expect(material.color, isNot(k.surface1), reason: styl.name);
        }

        // Po przewinięciu do końca ostatnia karta stoi nad przyciskiem
        // „W pobliżu”, a ten nad paskiem systemu.
        final dol = tester
            .widget<ListView>(lista)
            .padding!
            .resolve(TextDirection.ltr)
            .bottom;
        final koniecListy = tester.getRect(lista).bottom;
        final przycisk = tester.getRect(find.byType(FloatingActionButton));
        expect(przycisk.bottom, lessThanOrEqualTo(koniecListy - pasekSystemu),
            reason: styl.name);
        expect(koniecListy - dol, lessThanOrEqualTo(przycisk.top),
            reason: styl.name);
      }

      await sprzatnij(tester, services);
    });
  });
}
