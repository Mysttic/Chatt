import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/updates.dart';
import 'package:chatt/l10n/app_localizations.dart';
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

Widget _osadz(Widget dziecko) => MaterialApp(
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
