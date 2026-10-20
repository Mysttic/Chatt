import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/updates.dart';
import 'package:chatt/data/db.dart' show AppStyle;
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/ui/styles.dart';
import 'package:chatt/ui/widgets/update_card.dart';

/// Karta nowego wydania ma trzy drogi i każda kończy się czym innym: przycisk
/// instalacji, adres strony do rozpakowania z ręki, albo pasek postępu.
Release _wydanie({String? plik = 'chatt-0.9.0-windows-instalator.exe'}) =>
    Release(
      version: '0.9.0',
      notes: 'Coś naprawione, coś dodane.',
      publishedAt: DateTime(2026, 9, 6),
      pageUrl: 'https://github.com/Mysttic/Chatt/releases/tag/v0.9.0',
      assetUrl: plik == null
          ? null
          : 'https://github.com/Mysttic/Chatt/releases/download/v0.9.0/$plik',
      assetName: plik,
      assetSize: 1234,
    );

Widget _osadz(Widget dziecko, {ThemeData? motyw}) => MaterialApp(
      theme: motyw,
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: dziecko)),
    );

void main() {
  testWidgets('instalacja możliwa: numer, opis i przycisk', (tester) async {
    var kliknieto = 0;
    await tester.pumpWidget(_osadz(UpdateCard(
      release: _wydanie(),
      canInstall: true,
      progress: null,
      error: null,
      onInstall: () => kliknieto++,
    )));
    await tester.pump();

    expect(find.text('Version 0.9.0 is out'), findsOneWidget);
    expect(find.text('Coś naprawione, coś dodane.'), findsOneWidget);
    expect(find.text('Download and install'), findsOneWidget);

    await tester.tap(find.text('Download and install'));
    expect(kliknieto, 1);
  });

  testWidgets('wersja przenośna: bez przycisku, za to z adresem strony',
      (tester) async {
    await tester.pumpWidget(_osadz(UpdateCard(
      release: _wydanie(),
      canInstall: false,
      progress: null,
      error: null,
      onInstall: () {},
    )));
    await tester.pump();

    expect(find.text('Download and install'), findsNothing);
    expect(find.textContaining('unpacked by hand'), findsOneWidget);
    expect(
      find.text('https://github.com/Mysttic/Chatt/releases/tag/v0.9.0'),
      findsOneWidget,
    );
  });

  testWidgets('wydanie bez pliku dla tej platformy mówi to wprost',
      (tester) async {
    await tester.pumpWidget(_osadz(UpdateCard(
      release: _wydanie(plik: null),
      canInstall: true,
      progress: null,
      error: null,
      onInstall: () {},
    )));
    await tester.pump();

    expect(find.text('Download and install'), findsNothing);
    expect(find.textContaining('no file for this platform'), findsOneWidget);
  });

  testWidgets('w trakcie pobierania zamiast przycisku jest postęp',
      (tester) async {
    await tester.pumpWidget(_osadz(UpdateCard(
      release: _wydanie(),
      canInstall: true,
      progress: 42,
      error: null,
      onInstall: () {},
    )));
    await tester.pump();

    expect(find.text('Download and install'), findsNothing);
    expect(find.text('Downloading… 42%'), findsOneWidget);
    final pasek = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(pasek.value, closeTo(0.42, 0.001));
  });

  // Między próbkami pasek idzie w ruchu stylu (issue #54).
  for (final styl in AppStyle.values) {
    testWidgets('${styl.name}: pasek pobierania przechodzi między próbkami '
        'w ruchu stylu', (tester) async {
      final ruch = chattMotion(styl);
      final (czas, krzywa) = switch (styl) {
        AppStyle.cisza =>
          (const Duration(milliseconds: 400), const Cubic(0.2, 0, 0, 1)),
        AppStyle.precyzja => (Duration.zero, Curves.linear),
        AppStyle.cieplo => (const Duration(milliseconds: 250), Curves.linear),
      };
      expect(ruch.progress, czas);
      expect(ruch.progressCurve, krzywa);

      Widget karta(int procent) => _osadz(
            UpdateCard(
              release: _wydanie(),
              canInstall: true,
              progress: procent,
              error: null,
              onInstall: () {},
            ),
            motyw: chattTheme(styl, Brightness.light),
          );
      double pasek() => tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;

      await tester.pumpWidget(karta(40));
      expect(pasek(), closeTo(0.40, 0.001), reason: 'pierwsza próbka od razu');

      await tester.pumpWidget(karta(80));
      if (czas == Duration.zero) {
        expect(pasek(), closeTo(0.80, 0.001),
            reason: 'Precyzja idzie wprost za próbkami');
        await tester.pumpWidget(karta(95));
        expect(pasek(), closeTo(0.95, 0.001));
      } else {
        expect(pasek(), closeTo(0.40, 0.001));
        await tester.pump(czas ~/ 2);
        final polowa = pasek();
        expect(polowa, closeTo(0.40 + 0.40 * krzywa.transform(0.5), 0.001));

        // Kolejna próbka w trakcie ruchu: bez skoku, z miejsca, w którym
        // pasek jest, do nowej próbki w czasie stylu.
        await tester.pumpWidget(karta(95));
        expect(pasek(), closeTo(polowa, 0.001));
        await tester.pump(czas ~/ 2);
        expect(pasek(), allOf(greaterThan(polowa), lessThan(0.95)));
        await tester.pump(czas - czas ~/ 2);
        expect(pasek(), closeTo(0.95, 0.001));
      }
      expect(find.text('Downloading… 95%'), findsOneWidget);
    });
  }

  testWidgets('ograniczone animacje: pasek pobierania idzie wprost za '
      'próbkami', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    Widget karta(int procent) => _osadz(UpdateCard(
          release: _wydanie(),
          canInstall: true,
          progress: procent,
          error: null,
          onInstall: () {},
        ));
    await tester.pumpWidget(karta(40));
    await tester.pumpWidget(karta(80));
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        closeTo(0.80, 0.001));
  });

  testWidgets('błąd ląduje pod spodem, przycisk zostaje', (tester) async {
    await tester.pumpWidget(_osadz(UpdateCard(
      release: _wydanie(),
      canInstall: true,
      progress: null,
      error: 'Could not start the installer.',
      onInstall: () {},
    )));
    await tester.pump();

    expect(find.text('Download and install'), findsOneWidget);
    expect(find.text('Could not start the installer.'), findsOneWidget);
  });
}
