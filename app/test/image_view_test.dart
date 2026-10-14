import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/ui/screens/image_view_screen.dart';

/// Podgląd zdjęcia: obrót, akcje w pasku i to, co widać, gdy pliku nie ma
/// albo gdy nie jest obrazkiem.
///
/// Osobny plik świadomie, tak samo jak przy komunikatach: jeden
/// `testWidgets` wystarczy, żeby `TestWidgetsFlutterBinding` podmienił
/// `HttpClient` na atrapę dla całego zestawu, a obok stoją testy dwóch
/// instancji rozmawiających po prawdziwym gnieździe.

/// Najmniejszy poprawny PNG: jeden przezroczysty piksel. Dekoder Fluttera
/// bierze go bez mrugnięcia, więc test nie zależy od żadnego pliku w repo.
final _pikselPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8'
  'AAAAASUVORK5CYII=',
);

Widget _osadz(Widget ekran) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: ekran,
    );

void main() {
  late Directory katalog;

  setUp(() => katalog = Directory.systemTemp.createTempSync('chatt-podglad'));
  tearDown(() => katalog.deleteSync(recursive: true));

  String zapisz(String nazwa, List<int> bajty) {
    final plik = File('${katalog.path}${Platform.pathSeparator}$nazwa')
      ..writeAsBytesSync(bajty);
    return plik.path;
  }

  testWidgets('pokazuje nazwę od nadawcy i sam obrazek', (tester) async {
    await tester.pumpWidget(_osadz(ImageViewScreen(
      path: zapisz('piksel.png', _pikselPng),
      name: 'wakacje.png',
    )));
    await tester.pump();

    expect(find.text('wakacje.png'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('obrót idzie co ćwiartkę i po czterech wraca do zera',
      (tester) async {
    await tester.pumpWidget(_osadz(ImageViewScreen(
      path: zapisz('piksel.png', _pikselPng),
      name: 'wakacje.png',
    )));
    await tester.pump();

    int cwiartki() =>
        tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns;
    expect(cwiartki(), 0);

    for (final oczekiwane in [1, 2, 3, 0]) {
      await tester.tap(find.byIcon(Icons.rotate_90_degrees_cw_outlined));
      await tester.pump();
      expect(cwiartki(), oczekiwane);
    }
  });

  testWidgets('skasowany plik: komunikat zamiast pustego czarnego ekranu',
      (tester) async {
    await tester.pumpWidget(_osadz(ImageViewScreen(
      path: '${katalog.path}${Platform.pathSeparator}nie-ma-mnie.png',
      name: 'nie-ma-mnie.png',
    )));
    await tester.pump();

    expect(find.text('That file is no longer on disk.'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  /// Uszkodzony albo spreparowany obrazek ma skończyć się komunikatem, a nie
  /// wywrotką ekranu. Tego, co narysuje `errorBuilder`, nie da się tu
  /// sprawdzić: w środowisku testowym dekoder obrazów nigdy nie kończy pracy,
  /// więc ani obrazek, ani błąd nie dochodzą do widoku. Zostaje sprawdzenie,
  /// że sam ekran stoi i że obsługa błędu jest podpięta — reszta jest na
  /// liście do obejrzenia na urządzeniu (docs/testing.md).
  testWidgets('plik, który nie jest obrazkiem, nie wywraca ekranu',
      (tester) async {
    await tester.pumpWidget(_osadz(ImageViewScreen(
      path: zapisz('udaje.png', utf8.encode('to nie jest obrazek')),
      name: 'udaje.png',
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('udaje.png'), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).errorBuilder, isNotNull);
  });

  testWidgets('akcje z ekranu rozmowy trafiają do paska podglądu',
      (tester) async {
    var kliknieto = 0;
    await tester.pumpWidget(_osadz(ImageViewScreen(
      path: zapisz('piksel.png', _pikselPng),
      name: 'wakacje.png',
      actions: [
        IconButton(
          icon: const Icon(Icons.save_alt),
          onPressed: () => kliknieto++,
        ),
      ],
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.save_alt));
    expect(kliknieto, 1);
  });
}
