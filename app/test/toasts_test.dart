import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart' show AppStyle;
import 'package:chatt/ui/styles.dart';
import 'package:chatt/ui/widgets/toasts.dart';

/// Kolejka komunikatów w rogu okna: kolejność, limit, znikanie po czasie
/// i po kliknięciu, ruch karty w każdym stylu.
///
/// Osobny plik świadomie. Wystarczy jeden `testWidgets` w pliku, żeby
/// `TestWidgetsFlutterBinding` podmienił `HttpClient` na atrapę odpowiadającą
/// 400 dla **całego** zestawu, a obok, w peer_prefs_test.dart, stoją testy
/// dwóch instancji rozmawiających po prawdziwym gnieździe.
void main() {
  group('kolejka komunikatów', () {
    setUp(chattToasts.clear);
    tearDown(chattToasts.clear);

    test('komunikaty ustawiają się w kolejce i znikają po identyfikatorze', () {
      final pierwszy = chattToasts.show('raz');
      chattToasts.show('dwa');

      expect(chattToasts.value.map((m) => m.text), ['raz', 'dwa']);

      chattToasts.dismiss(pierwszy.id);
      expect(chattToasts.value.map((m) => m.text), ['dwa']);
    });

    test('najstarszy ustępuje miejsca, żeby róg nie zarósł tekstem', () {
      for (final tekst in ['raz', 'dwa', 'trzy', 'cztery']) {
        chattToasts.show(tekst);
      }

      expect(chattToasts.value, hasLength(ToastController.maxVisible));
      expect(chattToasts.value.map((m) => m.text), ['dwa', 'trzy', 'cztery']);
    });

    test('bez jawnego czasu komunikat zostawia czas stylowi', () {
      showToast('raz');
      showToast('dwa', duration: const Duration(seconds: 3));

      expect(chattToasts.value.map((m) => m.duration),
          [null, const Duration(seconds: 3)]);
    });

    testWidgets('karta znika sama po swoim czasie, jawny czas wygrywa '
        'z czasem stylu', (tester) async {
      // Precyzja trzyma komunikat 4,2 s, jawne 3 s ma pierwszeństwo.
      await _aplikacja(tester, styl: AppStyle.precyzja);

      showToast('zapisano', duration: const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('zapisano'), findsOneWidget);

      // W połowie odliczania karta ma jeszcze stać.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('zapisano'), findsOneWidget);
      expect(_pasek(tester), moreOrLessEquals(1 / 3, epsilon: 1e-6));

      // Koniec czasu: rusza wyjście, karta jeszcze w kolejce.
      await tester.pump(const Duration(seconds: 1) + _krok);
      expect(chattToasts.value, hasLength(1));

      await tester.pump(const Duration(milliseconds: 140) + _krok);
      await tester.pump();
      expect(find.text('zapisano'), findsNothing);
      expect(chattToasts.value, isEmpty,
          reason: 'kolejka nie może rosnąć w nieskończoność');
    });

    testWidgets('kliknięcie zamyka: najpierw wyjście, potem kolejka',
        (tester) async {
      // Zwykły MaterialApp bez motywu Chatta: ruch Ciszy.
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => ToastHost(child: child!),
        home: const SizedBox.shrink(),
      ));

      showToast('skopiowano', duration: const Duration(minutes: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240) + _krok);

      await tester.tap(find.text('skopiowano'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('skopiowano'), findsOneWidget,
          reason: 'karta schodzi w ruchu stylu');
      expect(chattToasts.value, hasLength(1));
      expect(_przezroczystosc(tester, 'skopiowano'), lessThan(1));

      await tester.pump(const Duration(milliseconds: 80) + _krok);
      await tester.pump();
      expect(find.text('skopiowano'), findsNothing);
      expect(chattToasts.value, isEmpty);
    });

    testWidgets('przycisk na karcie działa od razu, a karta schodzi wyjściem',
        (tester) async {
      await _aplikacja(tester, styl: AppStyle.cisza);

      var akcje = 0;
      showToast('/sdcard/Download/plik.txt',
          actionLabel: 'Kopiuj', onAction: () => akcje++);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240) + _krok);

      await tester.tap(find.text('Kopiuj'));
      await tester.pump();
      expect(akcje, 1);
      expect(chattToasts.value, hasLength(1),
          reason: 'z kolejki karta wypada dopiero po wyjściu');

      // W połowie wyjścia karta nie przyjmuje dotyku, a przycisk nie
      // powtarza akcji także drogą z pominięciem dotyku (czytnik ekranu).
      await tester.pump(const Duration(milliseconds: 80));
      expect(
          tester
              .widgetList<IgnorePointer>(find.ancestor(
                  of: find.text('Kopiuj'),
                  matching: find.byType(IgnorePointer)))
              .any((w) => w.ignoring),
          isTrue);
      await tester.tap(find.text('Kopiuj'), warnIfMissed: false);
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Kopiuj'))
          .onPressed!();
      await tester.pump();
      expect(akcje, 1, reason: 'schodząca karta nie kopiuje drugi raz');

      await tester.pump(const Duration(milliseconds: 80) + _krok);
      await tester.pump();
      expect(find.text('/sdcard/Download/plik.txt'), findsNothing);
      expect(chattToasts.value, isEmpty);
    });

    testWidgets('czwarta karta wypycha najstarszą, która schodzi wyjściem '
        'stylu, kolejka od razu ma trzy', (tester) async {
      final m = chattMotion(AppStyle.cisza);
      await _aplikacja(tester, styl: AppStyle.cisza);
      for (final tekst in ['jeden', 'dwa', 'trzy']) {
        showToast(tekst, duration: const Duration(minutes: 1));
      }
      await tester.pump();
      await tester.pump(m.toastIn + _krok);
      final miejsce = _gora(tester, 'jeden');

      showToast('cztery', duration: const Duration(minutes: 1));
      await tester.pump();
      expect(chattToasts.value.map((t) => t.text), ['dwa', 'trzy', 'cztery']);
      expect(find.text('jeden'), findsOneWidget,
          reason: 'wypchnięta karta schodzi jeszcze na ekranie');

      await tester.pump(m.toastOut ~/ 2);
      final widac = _przezroczystosc(tester, 'jeden');
      expect(widac, greaterThan(0));
      expect(widac, lessThan(1));
      expect(_gora(tester, 'jeden'), greaterThan(miejsce),
          reason: 'w Ciszy zjeżdża przy wyjściu');
      expect(_przezroczystosc(tester, 'dwa'), 1);

      await tester.pump(m.toastOut ~/ 2 + _krok);
      await tester.pump();
      expect(find.text('jeden'), findsNothing);
      expect(find.text('dwa'), findsOneWidget);
      expect(chattToasts.value, hasLength(3));
    });

    testWidgets('zmiana stylu w trakcie nie przestawia czasu karty',
        (tester) async {
      await _aplikacja(tester, styl: AppStyle.cisza);

      showToast('zapisano');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      // Precyzja trzymałaby 4,2 s; karta zostaje przy 3,2 s Ciszy
      // i odlicza dalej.
      await _aplikacja(tester, styl: AppStyle.precyzja);
      expect(_pasek(tester), moreOrLessEquals(1 - 2 / 3.2, epsilon: 1e-6));

      await tester.pump(const Duration(milliseconds: 1199));
      expect(_przezroczystosc(tester, 'zapisano'), 1);

      // Wyjście już w czasie nowego stylu (Precyzja: 140 ms).
      await tester.pump(_krok * 2);
      await tester.pump(const Duration(milliseconds: 140) + _krok);
      await tester.pump();
      expect(find.text('zapisano'), findsNothing);
      expect(chattToasts.value, isEmpty);
    });

    for (final styl in AppStyle.values) {
      final ruch = _projekt[styl]!;
      final nazwa = _nazwy[styl]!;

      testWidgets('$nazwa: bez jawnego czasu karta stoi '
          '${ruch.czas.inMilliseconds} ms', (tester) async {
        await _aplikacja(tester, styl: styl);

        showToast('zapisano');
        await tester.pump();
        await tester.pump(ruch.czas - _krok);
        expect(_przezroczystosc(tester, 'zapisano'), 1);
        expect(chattToasts.value, hasLength(1));

        // Czas liczy się od pokazania, razem z wejściem: tu rusza wyjście.
        await tester.pump(_krok * 2);
        await tester.pump(ruch.wyjscie ~/ 2);
        expect(_przezroczystosc(tester, 'zapisano'),
            moreOrLessEquals(1 - ruch.krzywaWyjscia.transform(0.5),
                epsilon: 1e-6));

        await tester.pump(ruch.wyjscie ~/ 2 + _krok);
        await tester.pump();
        expect(find.text('zapisano'), findsNothing);
        expect(chattToasts.value, isEmpty);
      });

      testWidgets('$nazwa: karta wjeżdża w górę o ${ruch.przesuniecie.round()} dp '
          'w ${ruch.wejscie.inMilliseconds} ms i się pojawia', (tester) async {
        await _aplikacja(tester, styl: styl);

        showToast('zapisano');
        await tester.pump();
        expect(_przezroczystosc(tester, 'zapisano'), 0);
        final start = _gora(tester, 'zapisano');

        await tester.pump(ruch.wejscie ~/ 2);
        final polowa = _gora(tester, 'zapisano');
        final przenikanie = _przezroczystosc(tester, 'zapisano');

        await tester.pump(ruch.wejscie ~/ 2);
        final miejsce = _gora(tester, 'zapisano');
        expect(_przezroczystosc(tester, 'zapisano'), 1);

        expect(start - miejsce,
            moreOrLessEquals(ruch.przesuniecie, epsilon: 1e-6));
        final k = ruch.krzywaWejscia.transform(0.5);
        expect(polowa - miejsce,
            moreOrLessEquals(ruch.przesuniecie * (1 - k), epsilon: 1e-6));
        expect(przenikanie, moreOrLessEquals(k, epsilon: 1e-6));
      });

      testWidgets('$nazwa: najechanie i fokus na karcie w '
          '${ruch.najechanie.inMilliseconds} ms', (tester) async {
        await _aplikacja(tester, styl: styl);

        showToast('zapisano');
        await tester.pump();
        expect(_najechanie(tester, 'zapisano'), ruch.najechanie);
      });

      testWidgets(
          '$nazwa: wyjście w ${ruch.wyjscie.inMilliseconds} ms, '
          '${ruch.zjazd ? 'przenikanie i zjazd w dół' : 'samo przenikanie'}',
          (tester) async {
        await _aplikacja(tester, styl: styl);

        showToast('zapisano', duration: const Duration(minutes: 1));
        await tester.pump();
        await tester.pump(ruch.wejscie + _krok);
        final miejsce = _gora(tester, 'zapisano');

        await tester.tap(find.text('zapisano'));
        await tester.pump();
        await tester.pump(ruch.wyjscie ~/ 2);
        final k = ruch.krzywaWyjscia.transform(0.5);
        expect(_przezroczystosc(tester, 'zapisano'),
            moreOrLessEquals(1 - k, epsilon: 1e-6));
        expect(
            _gora(tester, 'zapisano') - miejsce,
            moreOrLessEquals(ruch.zjazd ? ruch.przesuniecie * k : 0,
                epsilon: 1e-6));

        await tester.pump(ruch.wyjscie ~/ 2 + _krok);
        await tester.pump();
        expect(find.text('zapisano'), findsNothing);
        expect(chattToasts.value, isEmpty);
      });

      for (final zSystemu in [false, true]) {
        testWidgets('$nazwa: przy „ogranicz animacje” '
            '${zSystemu ? 'z systemu' : 'w MediaQuery'} przenikanie 100 ms bez '
            'przesunięcia, czas na ekranie bez zmian', (tester) async {
          // Flaga systemu skraca zwykłe kontrolery do 5% czasu: komunikat
          // zniknąłby po ułamku sekundy. Karta ma kontrolery z zachowanym
          // czasem, więc stoi i przenika tak samo.
          if (zSystemu) {
            tester.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(disableAnimations: true);
            addTearDown(
                tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
          }
          await _aplikacja(tester, styl: styl, ogranicz: !zSystemu);

          showToast('zapisano');
          await tester.pump();
          final miejsce = _gora(tester, 'zapisano');
          expect(_przezroczystosc(tester, 'zapisano'), 0);
          expect(_najechanie(tester, 'zapisano'),
              const Duration(milliseconds: 100));

          await tester.pump(const Duration(milliseconds: 50));
          expect(_przezroczystosc(tester, 'zapisano'),
              moreOrLessEquals(0.5, epsilon: 1e-6));
          expect(_gora(tester, 'zapisano'), miejsce);

          await tester.pump(const Duration(milliseconds: 50));
          expect(_przezroczystosc(tester, 'zapisano'), 1);
          expect(_gora(tester, 'zapisano'), miejsce);

          await tester.pump(
              ruch.czas - const Duration(milliseconds: 100) - _krok);
          expect(_przezroczystosc(tester, 'zapisano'), 1);
          expect(chattToasts.value, hasLength(1));

          await tester.pump(_krok * 2);
          await tester.pump(const Duration(milliseconds: 50));
          expect(_przezroczystosc(tester, 'zapisano'),
              moreOrLessEquals(0.5, epsilon: 1e-6));
          expect(_gora(tester, 'zapisano'), miejsce);

          await tester.pump(const Duration(milliseconds: 50) + _krok);
          await tester.pump();
          expect(find.text('zapisano'), findsNothing);
          expect(chattToasts.value, isEmpty);
        });
      }
    }
  });
}

/// Krok za koniec animacji: kontroler kończy w pierwszej klatce po swoim
/// czasie, w klatce równo na końcu stoi jeszcze w biegu.
const _krok = Duration(milliseconds: 1);

/// Ruch komunikatu z projektu stylów (issue #54).
typedef _Ruch = ({
  Duration wejscie,
  Duration wyjscie,
  double przesuniecie,
  bool zjazd,
  Duration czas,
  Curve krzywaWejscia,
  Curve krzywaWyjscia,
  Duration najechanie,
});

const _projekt = <AppStyle, _Ruch>{
  AppStyle.cisza: (
    wejscie: Duration(milliseconds: 240),
    wyjscie: Duration(milliseconds: 160),
    przesuniecie: 16,
    zjazd: true,
    czas: Duration(milliseconds: 3200),
    krzywaWejscia: Cubic(0.2, 0, 0, 1),
    krzywaWyjscia: Cubic(0.2, 0, 0, 1),
    najechanie: Duration(milliseconds: 120),
  ),
  AppStyle.precyzja: (
    wejscie: Duration(milliseconds: 180),
    wyjscie: Duration(milliseconds: 140),
    przesuniecie: 8,
    zjazd: true,
    czas: Duration(milliseconds: 4200),
    krzywaWejscia: Cubic(0.2, 0, 0, 1),
    krzywaWyjscia: Cubic(0.3, 0, 1, 1),
    najechanie: Duration(milliseconds: 120),
  ),
  AppStyle.cieplo: (
    wejscie: Duration(milliseconds: 220),
    wyjscie: Duration(milliseconds: 160),
    przesuniecie: 8,
    zjazd: false,
    czas: Duration(milliseconds: 3200),
    krzywaWejscia: Cubic(0.2, 0.8, 0.2, 1),
    krzywaWyjscia: Cubic(0.2, 0.8, 0.2, 1),
    najechanie: Duration(milliseconds: 120),
  ),
};

const _nazwy = {
  AppStyle.cisza: 'Cisza',
  AppStyle.precyzja: 'Precyzja',
  AppStyle.cieplo: 'Ciepło',
};

/// Aplikacja z nakładką komunikatów jak w `app.dart` (w `builder`, nad
/// nawigatorem), w motywie [styl]. [ogranicz]: „ogranicz animacje”
/// w systemie.
Future<void> _aplikacja(WidgetTester tester,
    {required AppStyle styl, bool ogranicz = false}) {
  return tester.pumpWidget(MaterialApp(
    theme: chattTheme(styl, Brightness.light),
    builder: (context, child) => MediaQuery(
      // Bez [ogranicz] zostaje to, co mówi system.
      data: ogranicz
          ? MediaQuery.of(context).copyWith(disableAnimations: true)
          : MediaQuery.of(context),
      child: ToastHost(child: child!),
    ),
    home: const SizedBox.shrink(),
  ));
}

/// Przezroczystość karty z tekstem [tekst] (przenikanie wejścia i wyjścia).
double _przezroczystosc(WidgetTester tester, String tekst) => tester
    .widget<Opacity>(
        find.ancestor(of: find.text(tekst), matching: find.byType(Opacity)))
    .opacity;

/// Górna krawędź tekstu na ekranie, z przesunięciem karty.
double _gora(WidgetTester tester, String tekst) =>
    tester.getTopLeft(find.text(tekst)).dy;

/// Czas podświetlenia karty z tekstem [tekst] przy najechaniu i fokusie.
Duration? _najechanie(WidgetTester tester, String tekst) => tester
    .widget<InkWell>(
        find.ancestor(of: find.text(tekst), matching: find.byType(InkWell)))
    .hoverDuration;

/// Ile zostało na pasku odliczania (1: pełny, 0: koniec czasu).
double _pasek(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
    .value!;
