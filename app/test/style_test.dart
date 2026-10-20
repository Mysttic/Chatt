import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import 'package:chatt/ui/backgrounds.dart';
import 'package:chatt/ui/screens/conversations_screen.dart';
import 'package:chatt/ui/screens/settings_screen.dart';
import 'package:chatt/ui/styles.dart';
import 'package:chatt/ui/widgets/common.dart';
import 'package:chatt/ui/widgets/motion.dart';
import 'package:chatt/ui/widgets/toasts.dart';

/// Kontrast WCAG między dwoma kolorami.
double kontrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (jasny, ciemny) = la > lb ? (la, lb) : (lb, la);
  return (jasny + 0.05) / (ciemny + 0.05);
}

/// Krzywa o punktach kontrolnych [punkty]; null: liniowa.
void krzywa(Curve c, List<double>? punkty, String powod) {
  if (punkty == null) {
    expect(c, same(Curves.linear), reason: powod);
    return;
  }
  expect(c, isA<Cubic>(), reason: powod);
  final k = c as Cubic;
  expect([k.a, k.b, k.c, k.d], punkty, reason: powod);
}

/// Kolory równe z dokładnością do zaokrąglenia: przenikanie motywu między
/// równymi wartościami potrafi zgubić ostatni bit.
void kolory(List<Color> faktyczne, List<Color> oczekiwane, String powod) {
  expect(faktyczne, hasLength(oczekiwane.length), reason: powod);
  for (var i = 0; i < oczekiwane.length; i++) {
    final (f, o) = (faktyczne[i], oczekiwane[i]);
    for (final (a, b) in [(f.a, o.a), (f.r, o.r), (f.g, o.g), (f.b, o.b)]) {
      expect(a, closeTo(b, 1e-9), reason: '$powod, kolor $i');
    }
  }
}

/// Kolory narysowanego tła: jeden kolor albo kolory gradientu.
List<Color> koloryTla(Decoration dekoracja) {
  final d = dekoracja as BoxDecoration;
  final gradient = d.gradient;
  return gradient == null ? [d.color!] : (gradient as LinearGradient).colors;
}

/// Każdy kanał [c] leży między [a] i [b]. [scisle]: [c] różni się od obu
/// końców, czyli przenikanie nie skoczyło na jeden z nich.
void pomiedzy(Color c, Color a, Color b, String powod, {bool scisle = false}) {
  double odleglosc(Color x, Color y) =>
      (x.a - y.a).abs() + (x.r - y.r).abs() + (x.g - y.g).abs() +
      (x.b - y.b).abs();
  for (final (nazwa, k, ka, kb) in [
    ('a', c.a, a.a, b.a),
    ('r', c.r, a.r, b.r),
    ('g', c.g, a.g, b.g),
    ('b', c.b, a.b, b.b),
  ]) {
    expect(
        k,
        inInclusiveRange(
            math.min(ka, kb) - 1e-6, math.max(ka, kb) + 1e-6),
        reason: '$powod, kanał $nazwa');
  }
  if (scisle && odleglosc(a, b) > 2e-3) {
    expect(odleglosc(c, a), greaterThan(1e-3), reason: '$powod: stary kolor');
    expect(odleglosc(c, b), greaterThan(1e-3), reason: '$powod: nowy kolor');
  }
}

/// Kolor tła w miejscu [x] gradientu (0: początek, 1: koniec).
Color probka(Wall w, double x) {
  final c = w.colors;
  if (c.length == 1) return c.single;
  final p =
      w.stops ?? [for (var i = 0; i < c.length; i++) i / (c.length - 1)];
  if (x <= p.first) return c.first;
  for (var i = 0; i < c.length - 1; i++) {
    if (x <= p[i + 1]) {
      return Color.lerp(c[i], c[i + 1], (x - p[i]) / (p[i + 1] - p[i]))!;
    }
  }
  return c.last;
}

/// Wiersz tabeli ruchu z issue #54 dla jednego stylu: czasy w ms,
/// przesunięcia w dp, krzywe jako punkty kontrolne (null: liniowa).
typedef WierszRuchu = ({
  List<double> wejscie,
  List<double> wyjscie,
  int ekranIn,
  int ekranOut,
  double ekranShift,
  int rozmowa,
  int kartaIn,
  int kartaOut,
  List<double> kartaKrzywa,
  double skalaTelefon,
  double shiftTelefon,
  double skalaOkno,
  double shiftOkno,
  int panelIn,
  int panelOut,
  double panelSkala,
  int zaslona,
  List<double>? zaslonaKrzywa,
  int dymek,
  double dymekShift,
  List<double> dymekKrzywa,
  int postep,
  List<double>? postepKrzywa,
  int toastIn,
  int toastOut,
  double toastShift,
  bool toastZjazd,
  int toastHold,
  int przelacznik,
  int motyw,
  int najechanie,
});

const _ciszy = [0.2, 0.0, 0.0, 1.0];
const _wyjsciePrecyzji = [0.3, 0.0, 1.0, 1.0];
const _ciepla = [0.2, 0.8, 0.2, 1.0];
const _sprezynka = [0.2, 0.9, 0.3, 1.15];
const _easeOut = [0.0, 0.0, 0.58, 1.0];

const tabelaRuchu = <AppStyle, WierszRuchu>{
  AppStyle.cisza: (
    wejscie: _ciszy,
    wyjscie: _ciszy,
    ekranIn: 300,
    ekranOut: 250,
    ekranShift: 30,
    rozmowa: 200,
    kartaIn: 280,
    kartaOut: 180,
    kartaKrzywa: _ciszy,
    skalaTelefon: 1,
    shiftTelefon: 24,
    skalaOkno: 0.96,
    shiftOkno: 0,
    panelIn: 280,
    panelOut: 180,
    panelSkala: 0.96,
    zaslona: 200,
    zaslonaKrzywa: _ciszy,
    dymek: 220,
    dymekShift: 8,
    dymekKrzywa: _ciszy,
    postep: 400,
    postepKrzywa: _ciszy,
    toastIn: 240,
    toastOut: 160,
    toastShift: 16,
    toastZjazd: true,
    toastHold: 3200,
    przelacznik: 200,
    motyw: 300,
    najechanie: 120,
  ),
  AppStyle.precyzja: (
    wejscie: _ciszy,
    wyjscie: _wyjsciePrecyzji,
    ekranIn: 220,
    ekranOut: 220,
    ekranShift: 24,
    rozmowa: 120,
    kartaIn: 180,
    kartaOut: 180,
    kartaKrzywa: _ciszy,
    skalaTelefon: 0.98,
    shiftTelefon: 0,
    skalaOkno: 0.98,
    shiftOkno: 0,
    panelIn: 180,
    panelOut: 180,
    panelSkala: 0.98,
    zaslona: 140,
    zaslonaKrzywa: null,
    dymek: 140,
    dymekShift: 6,
    dymekKrzywa: _ciszy,
    postep: 0,
    postepKrzywa: null,
    toastIn: 180,
    toastOut: 140,
    toastShift: 8,
    toastZjazd: true,
    toastHold: 4200,
    przelacznik: 120,
    motyw: 120,
    najechanie: 120,
  ),
  AppStyle.cieplo: (
    wejscie: _ciepla,
    wyjscie: _ciepla,
    ekranIn: 280,
    ekranOut: 280,
    ekranShift: 18,
    rozmowa: 200,
    kartaIn: 260,
    kartaOut: 180,
    kartaKrzywa: _sprezynka,
    skalaTelefon: 0.97,
    shiftTelefon: -10,
    skalaOkno: 0.97,
    shiftOkno: -10,
    panelIn: 300,
    panelOut: 180,
    panelSkala: 0.97,
    zaslona: 180,
    zaslonaKrzywa: _ciepla,
    dymek: 200,
    dymekShift: 8,
    dymekKrzywa: _easeOut,
    postep: 250,
    postepKrzywa: null,
    toastIn: 220,
    toastOut: 160,
    toastShift: 8,
    toastZjazd: false,
    toastHold: 3200,
    przelacznik: 200,
    motyw: 200,
    najechanie: 120,
  ),
};

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

  group('ruch stylów (issue #54)', () {
    const sto = Duration(milliseconds: 100);
    Duration ms(int n) => Duration(milliseconds: n);

    for (final MapEntry(key: styl, value: o) in tabelaRuchu.entries) {
      test('${styl.name}: czasy, krzywe, przesunięcia i skale z tabeli', () {
        final m = chattMotion(styl);
        expect(m.isReduced, isFalse);

        krzywa(m.enter, o.wejscie, 'wejście');
        krzywa(m.exit, o.wyjscie, 'wyjście');
        // Wyjście w tył to krzywa wyjścia odwrócona.
        for (final x in [0.25, 0.5, 0.75]) {
          expect(m.exitReverse.transform(x),
              closeTo(1 - m.exit.transform(1 - x), 1e-12));
        }

        expect(m.screenIn, ms(o.ekranIn), reason: 'ekran');
        expect(m.screenOut, ms(o.ekranOut), reason: 'powrót');
        expect(m.screenShift, o.ekranShift, reason: 'ekran');
        expect(m.paneSwitch, ms(o.rozmowa), reason: 'zmiana rozmowy');

        expect(m.cardIn, ms(o.kartaIn), reason: 'karta');
        expect(m.cardOut, ms(o.kartaOut), reason: 'karta znika');
        krzywa(m.cardCurve, o.kartaKrzywa, 'karta');
        expect(m.cardScalePhone, o.skalaTelefon, reason: 'karta, telefon');
        expect(m.cardShiftPhone, o.shiftTelefon, reason: 'karta, telefon');
        expect(m.cardScaleWindow, o.skalaOkno, reason: 'karta, okno');
        expect(m.cardShiftWindow, o.shiftOkno, reason: 'karta, okno');

        expect(m.panelIn, ms(o.panelIn), reason: 'panel');
        expect(m.panelOut, ms(o.panelOut), reason: 'panel znika');
        expect(m.panelScale, o.panelSkala, reason: 'panel');

        expect(m.scrim, ms(o.zaslona), reason: 'zasłona');
        krzywa(m.scrimCurve, o.zaslonaKrzywa, 'zasłona');
        // Zasłona dochodzi do pełnej w swoim czasie, choć karta i panel
        // wjeżdżają dłużej.
        for (final calosc in [m.cardIn, m.panelIn]) {
          final udzial = m.scrim.inMicroseconds / calosc.inMicroseconds;
          final z = m.scrimWithin(calosc);
          expect(z.transform(udzial), 1.0, reason: 'zasłona w $calosc');
          expect(z.transform(udzial / 2), lessThan(1.0),
              reason: 'zasłona w $calosc');
        }

        expect(m.bubble, ms(o.dymek), reason: 'dymek');
        expect(m.bubbleShift, o.dymekShift, reason: 'dymek');
        krzywa(m.bubbleCurve, o.dymekKrzywa, 'dymek');

        expect(m.progress, ms(o.postep), reason: 'postęp');
        krzywa(m.progressCurve, o.postepKrzywa, 'postęp');

        expect(m.toastIn, ms(o.toastIn), reason: 'komunikat');
        expect(m.toastOut, ms(o.toastOut), reason: 'komunikat znika');
        expect(m.toastShift, o.toastShift, reason: 'komunikat');
        expect(m.toastExitShift, o.toastZjazd, reason: 'komunikat znika');
        expect(m.toastHold, ms(o.toastHold), reason: 'komunikat stoi');

        expect(m.control, ms(o.przelacznik), reason: 'przełącznik');
        expect(m.themeChange, ms(o.motyw), reason: 'motyw');
        expect(m.hover, ms(o.najechanie), reason: 'najechanie');

        // Ten sam ruch w tokenach i motywie obu jasności; przyciski
        // zmieniają tło w czasie najechania.
        for (final jasnosc in Brightness.values) {
          expect(chattTokens(styl, jasnosc).motion, same(m));
          final theme = chattTheme(styl, jasnosc);
          expect(theme.extension<ChattTokens>()!.motion, same(m));
          for (final przycisk in [
            theme.filledButtonTheme.style,
            theme.outlinedButtonTheme.style,
            theme.textButtonTheme.style,
            theme.iconButtonTheme.style,
            theme.segmentedButtonTheme.style,
          ]) {
            expect(przycisk!.animationDuration, m.hover, reason: 'przycisk');
          }
        }
      });
    }

    test('zasłona stylu pod oknem i arkuszem, w Ciszy 36% (ciemny 55%)', () {
      for (final styl in AppStyle.values) {
        for (final jasnosc in Brightness.values) {
          final theme = chattTheme(styl, jasnosc);
          expect(theme.dialogTheme.barrierColor, theme.colorScheme.scrim);
          expect(theme.bottomSheetTheme.modalBarrierColor,
              theme.colorScheme.scrim);
        }
      }
      expect(chattTheme(AppStyle.cisza, Brightness.light).colorScheme.scrim.a,
          closeTo(0.36, 0.005));
      expect(chattTheme(AppStyle.cisza, Brightness.dark).colorScheme.scrim.a,
          closeTo(0.55, 0.005));
    });

    for (final styl in AppStyle.values) {
      test('${styl.name}: przy „ogranicz animacje” każde przejście to '
          'przenikanie 100 ms', () {
        final zwykly = chattMotion(styl);
        final r = zwykly.reduced;
        expect(r.isReduced, isTrue);

        for (final MapEntry(key: nazwa, value: czas) in {
          'ekran': r.screenIn,
          'powrót': r.screenOut,
          'zmiana rozmowy': r.paneSwitch,
          'karta': r.cardIn,
          'karta znika': r.cardOut,
          'panel': r.panelIn,
          'panel znika': r.panelOut,
          'zasłona': r.scrim,
          'dymek': r.bubble,
          'komunikat': r.toastIn,
          'komunikat znika': r.toastOut,
          'przełącznik': r.control,
          'motyw': r.themeChange,
          'najechanie': r.hover,
        }.entries) {
          expect(czas, sto, reason: nazwa);
        }
        // Pasek postępu idzie wprost za próbkami.
        expect(r.progress, Duration.zero);

        for (final MapEntry(key: nazwa, value: przesuniecie) in {
          'ekran': r.screenShift,
          'karta, telefon': r.cardShiftPhone,
          'karta, okno': r.cardShiftWindow,
          'dymek': r.bubbleShift,
          'komunikat': r.toastShift,
        }.entries) {
          expect(przesuniecie, 0, reason: nazwa);
        }
        expect(r.toastExitShift, isFalse);
        expect(r.cardScalePhone, 1);
        expect(r.cardScaleWindow, 1);
        expect(r.panelScale, 1);

        for (final MapEntry(key: nazwa, value: c) in {
          'wejście': r.enter,
          'wyjście': r.exit,
          'karta': r.cardCurve,
          'zasłona': r.scrimCurve,
          'dymek': r.bubbleCurve,
          'postęp': r.progressCurve,
        }.entries) {
          krzywa(c, null, nazwa);
        }
        expect(r.exitReverse.transform(0.3), closeTo(0.3, 1e-12));
        // Komunikat stoi na ekranie tyle samo co zwykle.
        expect(r.toastHold, zwykly.toastHold);

        // Motyw z „ogranicz animacje” niesie ten ruch w tokenach,
        // przejściu ekranów i przyciskach.
        for (final jasnosc in Brightness.values) {
          expect(
              chattTokens(styl, jasnosc, reduceMotion: true).motion.isReduced,
              isTrue);
          final theme = chattTheme(styl, jasnosc, reduceMotion: true);
          final k = theme.extension<ChattTokens>()!;
          expect(k.motion.isReduced, isTrue);
          expect(k.motion.toastHold, zwykly.toastHold);
          for (final platforma in TargetPlatform.values) {
            final przejscie = theme.pageTransitionsTheme.builders[platforma]!
                as ChattPageTransitionsBuilder;
            expect(przejscie.motion.isReduced, isTrue, reason: platforma.name);
            expect(przejscie.transitionDuration, sto, reason: platforma.name);
            expect(przejscie.reverseTransitionDuration, sto,
                reason: platforma.name);
          }
          expect(theme.filledButtonTheme.style!.animationDuration, sto);
        }
      });
    }

    testWidgets('ChattMotion.of idzie za „ogranicz animacje” w systemie',
        (tester) async {
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      for (final styl in AppStyle.values) {
        late ChattMotion m;
        await tester.pumpWidget(MaterialApp(
          key: ValueKey(styl),
          theme: chattTheme(styl, Brightness.light),
          home: Builder(builder: (context) {
            m = ChattMotion.of(context);
            return const SizedBox();
          }),
        ));
        expect(m.isReduced, isFalse, reason: styl.name);
        expect(m.screenIn, chattMotion(styl).screenIn, reason: styl.name);

        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        await tester.pump();
        expect(m.isReduced, isTrue, reason: styl.name);
        expect(m.themeChange, sto, reason: styl.name);
        expect(m.toastHold, chattMotion(styl).toastHold, reason: styl.name);

        tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
        await tester.pump();
        expect(m.isReduced, isFalse, reason: styl.name);
      }
    });

    test('przejście ekranów: wspólna oś X stylu na każdej platformie', () {
      for (final styl in AppStyle.values) {
        final m = chattMotion(styl);
        final theme = chattTheme(styl, Brightness.light);
        for (final platforma in TargetPlatform.values) {
          final przejscie = theme.pageTransitionsTheme.builders[platforma];
          expect(przejscie, isA<ChattPageTransitionsBuilder>(),
              reason: '${styl.name} ${platforma.name}');
          przejscie as ChattPageTransitionsBuilder;
          expect(przejscie.motion, same(m));
          expect(przejscie.transitionDuration, m.screenIn,
              reason: '${styl.name} ${platforma.name}');
          expect(przejscie.reverseTransitionDuration, m.screenOut,
              reason: '${styl.name} ${platforma.name}');
        }
      }
    });

    testWidgets('nowy ekran wjeżdża z prawej o przesunięcie stylu i się '
        'pojawia, wraca w czasie powrotu; przy „ogranicz animacje” samo '
        'przenikanie', (tester) async {
      const drugi = Key('drugi');
      for (final styl in AppStyle.values) {
        for (final ogranicz in [false, true]) {
          final powod = '${styl.name}${ogranicz ? ', ograniczone' : ''}';
          final theme =
              chattTheme(styl, Brightness.light, reduceMotion: ogranicz);
          final m = theme.extension<ChattTokens>()!.motion;
          final nawigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(MaterialApp(
            key: ValueKey((styl, ogranicz)),
            navigatorKey: nawigator,
            theme: theme,
            home: const SizedBox.expand(),
          ));

          final trasa = MaterialPageRoute<void>(
              builder: (_) => const SizedBox.expand(key: drugi));
          unawaited(nawigator.currentState!.push(trasa));
          // Pierwszą klatkę trasa stoi poza ekranem (pomiar bohaterów),
          // w drugiej rusza od zera.
          await tester.pump();
          await tester.pump();
          expect(trasa.transitionDuration, m.screenIn, reason: powod);
          expect(trasa.reverseTransitionDuration, m.screenOut, reason: powod);

          double x() => tester.getTopLeft(find.byKey(drugi)).dx;
          double widac() => tester
              .widget<Opacity>(find
                  .ancestor(of: find.byKey(drugi), matching: find.byType(Opacity))
                  .first)
              .opacity;

          // Start: przesunięty o przesunięcie stylu i przezroczysty.
          expect(x(), m.screenShift, reason: powod);
          expect(x(), ogranicz ? 0 : greaterThan(0), reason: powod);
          expect(widac(), 0, reason: powod);
          // W połowie: przy „ogranicz animacje” stoi na miejscu i się
          // pojawia.
          await tester.pump(m.screenIn ~/ 2);
          expect(widac(), inExclusiveRange(0, 1), reason: powod);
          if (ogranicz) expect(x(), 0, reason: powod);
          // Koniec: na miejscu i widoczny.
          await tester.pump(m.screenIn ~/ 2);
          expect(x(), 0, reason: powod);
          expect(widac(), 1, reason: powod);
          // Kontroler kończy dopiero w klatce po upływie czasu: bez niej
          // powrót wziąłby krzywą wejścia.
          await tester.pump(const Duration(milliseconds: 16));

          // Powrót w czasie i krzywej powrotu stylu.
          nawigator.currentState!.pop();
          await tester.pump();
          await tester.pump(m.screenOut ~/ 2);
          expect(x(),
              closeTo(m.screenShift * (1 - m.exitReverse.transform(0.5)), 1e-9),
              reason: powod);
          await tester.pump(m.screenOut ~/ 2 - const Duration(milliseconds: 5));
          expect(find.byKey(drugi), findsOneWidget, reason: powod);
          await tester.pump(const Duration(milliseconds: 10));
          await tester.pump();
          expect(find.byKey(drugi), findsNothing, reason: powod);
        }
      }
    });

    test('przenikanie tokenów: kolory w połowie drogi, przełączniki stylu '
        'w połowie czasu', () {
      final jasny = chattTokens(AppStyle.cisza, Brightness.light);
      final ciemny = chattTokens(AppStyle.cisza, Brightness.dark);
      expect(jasny.lerp(ciemny, 0), same(jasny));
      expect(jasny.lerp(ciemny, 1), same(ciemny));

      final pol = jasny.lerp(ciemny, 0.5);
      for (final (nazwa, faktyczny, a, b) in [
        ('tło', pol.background, jasny.background, ciemny.background),
        ('powierzchnia', pol.surface1, jasny.surface1, ciemny.surface1),
        ('mój dymek', pol.bubbleMine, jasny.bubbleMine, ciemny.bubbleMine),
        ('zagrożenie', pol.danger, jasny.danger, ciemny.danger),
        ('komunikat', pol.toast, jasny.toast, ciemny.toast),
      ]) {
        expect(faktyczny, Color.lerp(a, b, 0.5), reason: nazwa);
        expect(faktyczny, isNot(a), reason: nazwa);
        expect(faktyczny, isNot(b), reason: nazwa);
      }
      expect(pol.shadow2, BoxShadow.lerpList(jasny.shadow2, ciemny.shadow2, 0.5));
      for (var i = 0; i < jasny.walls.length; i++) {
        kolory(pol.walls[i].colors,
            lerpWall(jasny.walls[i], ciemny.walls[i], 0.5).colors, 'tło $i');
      }
      // Motyw Fluttera przenika rozszerzenie tak samo.
      final motyw = ThemeData.lerp(chattTheme(AppStyle.cisza, Brightness.light),
          chattTheme(AppStyle.cisza, Brightness.dark), 0.5);
      expect(motyw.extension<ChattTokens>()!.background,
          Color.lerp(jasny.background, ciemny.background, 0.5));

      // Przełączniki stylu skaczą w połowie, wymiary idą płynnie.
      final precyzja = chattTokens(AppStyle.precyzja, Brightness.light);
      final przed = jasny.lerp(precyzja, 0.49);
      final po = jasny.lerp(precyzja, 0.5);
      expect(przed.style, AppStyle.cisza);
      expect(po.style, AppStyle.precyzja);
      for (final (nazwa, a, b) in [
        ('awatar koło', przed.avatarCircle, po.avatarCircle),
        ('separator linią', przed.separatorLine, po.separatorLine),
        ('wersaliki', przed.overlineUppercase, po.overlineUppercase),
        ('ostrzeżenie jak zagrożenie', przed.securityAsDanger,
            po.securityAsDanger),
      ]) {
        expect(a, isNot(b), reason: nazwa);
      }
      expect(przed.avatarCircle, jasny.avatarCircle);
      expect(po.avatarCircle, precyzja.avatarCircle);
      expect(przed.motion, same(jasny.motion));
      expect(po.motion, same(precyzja.motion));
      expect(po.radiusCard, (jasny.radiusCard + precyzja.radiusCard) / 2);
    });

    // Tła o różnej liczbie kolorów przenikają przez lerpWall bez skoku
    // w połowie drogi.
    test('przenikanie teł o różnej liczbie kolorów idzie płynnie: Zmierzch '
        'w Ocean w Cieple, Cisza w Precyzję z wybranym tłem', () {
      void plynnie(Wall a, Wall b, Wall pol, String powod) {
        for (final x in [0.0, 0.25, 0.55, 0.8, 1.0]) {
          pomiedzy(probka(pol, x), probka(a, x), probka(b, x),
              '$powod, miejsce $x',
              scisle: true);
        }
      }

      for (final jasnosc in Brightness.values) {
        // Zmiana tła w AppBackground.
        final cieplo = chattTokens(AppStyle.cieplo, jasnosc);
        final (zmierzch, ocean) = (cieplo.walls[1], cieplo.walls[2]);
        expect(zmierzch.colors.length, isNot(ocean.colors.length));
        plynnie(zmierzch, ocean, lerpWall(zmierzch, ocean, 0.5),
            'Ciepło ${jasnosc.name}, Zmierzch w Ocean');
        plynnie(ocean, zmierzch, lerpWall(ocean, zmierzch, 0.5),
            'Ciepło ${jasnosc.name}, Ocean w Zmierzch');

        // Zmiana stylu przy wybranym tle: przenikanie motywu.
        final cisza = chattTokens(AppStyle.cisza, jasnosc);
        final precyzja = chattTokens(AppStyle.precyzja, jasnosc);
        final pol = cisza.lerp(precyzja, 0.5);
        for (var i = 1; i < cisza.walls.length; i++) {
          plynnie(cisza.walls[i], precyzja.walls[i], pol.walls[i],
              'Cisza w Precyzję ${jasnosc.name}, tło $i');
        }
      }
    });
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
    /// zegara testu przesuwa też przenikanie motywu (czas zmiany motywu
    /// w stylu).
    Future<void> dokoncz(WidgetTester tester, bool Function() warunek) async {
      for (var i = 0; i < 50 && !warunek(); i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(warunek(), isTrue);
    }

    /// Ekran Ustawień w motywie [theme]. Motyw przenika liniowo w 200 ms.
    /// [ograniczRuch]: „ogranicz animacje” wprost w MediaQuery (flaga
    /// systemu skraca dodatkowo kontrolery Fluttera do 5% czasu).
    Widget ustawienia(AppServices services, ThemeData theme,
            {required Key key, bool ograniczRuch = false}) =>
        ProviderScope(
          key: key,
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: ograniczRuch),
              child: MaterialApp(
                theme: theme,
                themeAnimationStyle: const AnimationStyle(
                    duration: Duration(milliseconds: 200),
                    curve: Curves.linear),
                locale: const Locale('en'),
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                home: const SettingsScreen(),
              ),
            ),
          ),
        );

    /// Kafelek tła z podpisem [podpis] w Ustawieniach i jego części.
    Finder kafelek(String podpis) => find
        .ancestor(of: find.text(podpis), matching: find.byType(InkWell))
        .first;
    Finder obrys(String podpis) => find.descendant(
        of: kafelek(podpis),
        matching: find.byWidgetPredicate((w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border != null));
    Border obrysNaEkranie(WidgetTester tester, String podpis) =>
        (tester.widget<DecoratedBox>(obrys(podpis)).decoration
                as BoxDecoration)
            .border! as Border;
    TweenAnimationBuilder<double> zaznaczenie(
            WidgetTester tester, String podpis) =>
        tester.widget(find.descendant(
            of: kafelek(podpis),
            matching: find.byType(TweenAnimationBuilder<double>)));
    double znacznik(WidgetTester tester, String podpis) => tester
        .widget<Opacity>(find.descendant(
            of: kafelek(podpis), matching: find.byType(Opacity)))
        .opacity;
    TextStyle stylPodpisu(WidgetTester tester, String podpis) => tester
        .widget<RichText>(find.descendant(
            of: find.text(podpis), matching: find.byType(RichText)))
        .text
        .style!;

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

    testWidgets('aplikacja: motyw przenika w czasie stylu, nowe tło przenika '
        'od starego bez zmiany drzewa i bez przyciemnienia; przy „ogranicz '
        'animacje” w 100 ms, także przy fladze systemu', (tester) async {
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final services = await uruchom(tester);
      // „Ogranicz animacje” wprost w MediaQuery nad aplikacją. Flaga
      // systemu dodatkowo skraca we Flutterze każdy kontroler do 5% czasu,
      // więc czas 100 ms da się zmierzyć tylko tą drogą.
      final ograniczRuch = ValueNotifier(false);
      addTearDown(ograniczRuch.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: ValueListenableBuilder<bool>(
          valueListenable: ograniczRuch,
          child: const ChattApp(),
          builder: (context, ogranicz, app) {
            final dane = MediaQuery.of(context);
            return MediaQuery(
              data: ogranicz ? dane.copyWith(disableAnimations: true) : dane,
              child: app!,
            );
          },
        ),
      ));
      await dokoncz(tester,
          () => find.text('Pixel Mysttic').evaluate().isNotEmpty);

      AnimationStyle przejscie() => tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .themeAnimationStyle!;
      ChattTokens tokeny() =>
          ChattTokens.of(tester.element(find.text('Pixel Mysttic')));

      // Przenikanie motywu: czas zmiany motywu i krzywa wejścia stylu.
      const czasy = {
        AppStyle.cisza: 300,
        AppStyle.precyzja: 120,
        AppStyle.cieplo: 200,
      };
      for (final styl in [
        AppStyle.cisza,
        AppStyle.precyzja,
        AppStyle.cieplo,
        AppStyle.cisza,
      ]) {
        await tester.runAsync(() => services.db.saveStyle(styl));
        await dokoncz(tester, () => tokeny().style == styl);
        expect(przejscie().duration, Duration(milliseconds: czasy[styl]!),
            reason: styl.name);
        expect(przejscie().curve, same(chattMotion(styl).enter),
            reason: styl.name);
        expect(tokeny().motion.isReduced, isFalse, reason: styl.name);
        await tester.pump(const Duration(seconds: 1));
      }

      // Tło: „Bez tła” to kolor tła stylu, nowe przenika od niego.
      final sciany = tokeny().walls;
      final nawigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      List<Color> narysowane() => koloryTla(tester
          .widget<DecoratedBox>(find
              .descendant(
                  of: find.byType(AppBackground),
                  matching: find.byType(DecoratedBox))
              .first)
          .decoration);
      Future<void> zmienTlo(int indeks) async {
        await tester.runAsync(() => services.db.saveBackground(indeks));
        int teraz() => tester
            .widget<AppBackground>(find.byType(AppBackground))
            .background
            .index;
        // Klatka po klatce bez upływu czasu testu: przenikanie rusza
        // w klatce, w której tło się zmieniło.
        for (var i = 0; i < 50 && teraz() != indeks; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
        }
        expect(teraz(), indeks);
      }

      // Na ekranie tło leży pod tłem ekranu, a pasek u góry jeszcze nad
      // nim. W każdej klatce złożony kolor ma leżeć między starym a nowym
      // tłem: bez przyciemnienia w połowie drogi.
      Color kolorSciany(Wall w, int i) =>
          w.colors.length == 1 ? w.colors.single : w.colors[i];
      void naEkranie(Wall od, Wall cel, String powod) {
        final motyw = Theme.of(tester.element(find.text('Pixel Mysttic')));
        final widac = narysowane();
        for (var i = 0; i < widac.length; i++) {
          final ekran =
              Color.alphaBlend(motyw.scaffoldBackgroundColor, widac[i]);
          final pasek = Color.alphaBlend(
              motyw.appBarTheme.backgroundColor ?? motyw.colorScheme.surface,
              ekran);
          for (final (gdzie, kolor) in [('ekran', ekran), ('pasek', pasek)]) {
            pomiedzy(kolor, kolorSciany(od, i), kolorSciany(cel, i),
                '$powod, $gdzie, kolor $i');
          }
        }
      }

      final cisza = chattMotion(AppStyle.cisza);
      final krok = cisza.themeChange ~/ 10;
      kolory(narysowane(), sciany[0].colors, 'bez tła');
      await zmienTlo(2);
      kolory(narysowane(), sciany[0].colors, 'klatka zmiany');
      for (var i = 1; i <= 10; i++) {
        await tester.pump(krok);
        naEkranie(sciany[0], sciany[2], 'klatka $i');
        if (i == 5) {
          final wPolowie = narysowane();
          kolory(
              wPolowie,
              lerpWall(sciany[0], sciany[2], cisza.enter.transform(0.5))
                  .colors,
              'w połowie');
          expect(wPolowie, isNot(sciany[2].colors));
        }
      }
      kolory(narysowane(), sciany[2].colors, 'po przenikaniu');
      expect(tester.state<NavigatorState>(find.byType(Navigator).first),
          same(nawigator));

      // Powrót do „Bez tła” tak samo, nawigator zostaje ten sam.
      await zmienTlo(0);
      for (var i = 1; i <= 10; i++) {
        await tester.pump(krok);
        naEkranie(sciany[2], sciany[0], 'z powrotem, klatka $i');
      }
      kolory(narysowane(), sciany[0].colors, 'znowu bez tła');
      expect(tester.state<NavigatorState>(find.byType(Navigator).first),
          same(nawigator));
      await tester.pump(const Duration(seconds: 1));

      // „Ogranicz animacje” w MediaQuery: motyw, ekrany i tło ustawione na
      // przenikanie 100 ms.
      const sto = Duration(milliseconds: 100);
      ChattPageTransitionsBuilder ekrany() =>
          Theme.of(tester.element(find.text('Pixel Mysttic')))
              .pageTransitionsTheme
              .builders[TargetPlatform.android]! as ChattPageTransitionsBuilder;
      ograniczRuch.value = true;
      await tester.pump();
      expect(przejscie().duration, sto);
      expect(przejscie().curve, same(Curves.linear));
      await tester.pump(const Duration(seconds: 1));
      expect(tokeny().motion.isReduced, isTrue);
      expect(ekrany().transitionDuration, sto);
      expect(ekrany().reverseTransitionDuration, sto);

      await zmienTlo(1);
      await tester.pump(sto ~/ 2);
      kolory(narysowane(), lerpWall(sciany[0], sciany[1], 0.5).colors,
          'w połowie, ograniczone');
      await tester.pump(sto ~/ 2);
      kolory(narysowane(), sciany[1].colors, 'po 100 ms');
      expect(tester.state<NavigatorState>(find.byType(Navigator).first),
          same(nawigator));

      // Bez „ogranicz animacje” wraca ruch stylu, a flaga systemu dochodzi
      // do aplikacji tak samo.
      ograniczRuch.value = false;
      await tester.pump();
      expect(przejscie().duration, chattMotion(AppStyle.cisza).themeChange);
      await tester.pump(const Duration(seconds: 1));
      expect(tokeny().motion.isReduced, isFalse);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pump();
      expect(przejscie().duration, sto);
      expect(przejscie().curve, same(Curves.linear));
      await tester.pump(const Duration(seconds: 1));
      expect(tokeny().motion.isReduced, isTrue);
      expect(ekrany().transitionDuration, sto);

      // Przy fladze systemu Flutter skraca zwykłe kontrolery do 5% czasu.
      // Tło ma kontroler z zachowanym czasem, więc i na urządzeniu przenika
      // w 100 ms.
      await zmienTlo(3);
      await tester.pump(sto ~/ 2);
      kolory(narysowane(), lerpWall(sciany[1], sciany[3], 0.5).colors,
          'flaga systemu, w połowie');
      await tester.pump(sto ~/ 2);
      kolory(narysowane(), sciany[3].colors, 'flaga systemu, po 100 ms');

      await sprzatnij(tester, services);
    });

    testWidgets('Ustawienia: zaznaczenie tła przechodzi w czasie przełączników '
        'stylu, przy „ogranicz animacje” w MediaQuery w 100 ms',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final teksty = lookupAppLocalizations(const Locale('en'));
      final services = await uruchom(tester);
      final zmierzch = teksty.backgroundDusk;

      for (final (styl, ogranicz) in [
        for (final styl in AppStyle.values) (styl, false),
        (AppStyle.cieplo, true),
      ]) {
        final powod = '${styl.name}${ogranicz ? ', ograniczone' : ''}';
        final m = ogranicz ? chattMotion(styl).reduced : chattMotion(styl);
        await tester.runAsync(() => services.db.saveBackground(0));
        await tester.pumpWidget(ustawienia(
            services, chattTheme(styl, Brightness.light),
            key: ValueKey(powod), ograniczRuch: ogranicz));
        await dokoncz(tester, () => find.text(zmierzch).evaluate().isNotEmpty);
        await tester.ensureVisible(find.text(zmierzch));
        await tester.pump(const Duration(seconds: 1));

        // Postęp zaznaczenia w czasie i krzywej przełączników stylu,
        // najechanie w czasie najechania.
        final animacja = zaznaczenie(tester, zmierzch);
        expect(animacja.duration, m.control, reason: powod);
        expect(animacja.curve, same(m.enter), reason: powod);
        expect(animacja.tween.end, 0, reason: powod);
        expect(tester.widget<InkWell>(kafelek(zmierzch)).hoverDuration,
            m.hover,
            reason: powod);
        expect(obrysNaEkranie(tester, zmierzch).top.width, 1, reason: powod);
        expect(znacznik(tester, zmierzch), 0, reason: powod);

        await tester.tap(find.text(zmierzch));
        await tester.pump();
        // Zaznaczenie idzie za bazą: przejście rusza w klatce zmiany.
        for (var i = 0;
            i < 50 && zaznaczenie(tester, zmierzch).tween.end != 1;
            i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
        }
        expect(zaznaczenie(tester, zmierzch).tween.end, 1, reason: powod);
        expect(obrysNaEkranie(tester, zmierzch).top.width, 1, reason: powod);

        // W połowie czasu: obrys, znacznik i podpis w połowie krzywej.
        await tester.pump(m.control ~/ 2);
        final pol = m.enter.transform(0.5);
        final scheme = Theme.of(tester.element(obrys(zmierzch))).colorScheme;
        final wPolowie = obrysNaEkranie(tester, zmierzch).top;
        expect(wPolowie.width, closeTo(1 + 2 * pol, 1e-9), reason: powod);
        expect(wPolowie.width, inExclusiveRange(1, 3), reason: powod);
        expect(znacznik(tester, zmierzch), closeTo(pol, 1e-9), reason: powod);
        kolory([
          wPolowie.color,
          stylPodpisu(tester, zmierzch).color!,
        ], [
          Color.lerp(scheme.outlineVariant, scheme.primary, pol)!,
          Color.lerp(scheme.onSurfaceVariant, scheme.primary, pol)!,
        ], '$powod, w połowie');

        await tester.pump(m.control ~/ 2);
        final poPrzejsciu = obrysNaEkranie(tester, zmierzch).top;
        expect(poPrzejsciu.width, 3, reason: powod);
        expect(znacznik(tester, zmierzch), 1, reason: powod);
        kolory([poPrzejsciu.color, stylPodpisu(tester, zmierzch).color!],
            [scheme.primary, scheme.primary], '$powod, po przejściu');
        expect(stylPodpisu(tester, zmierzch).fontWeight, FontWeight.w600,
            reason: powod);
        await tester.pump(const Duration(seconds: 1));
      }

      await sprzatnij(tester, services);
    });

    testWidgets('Ustawienia: zaznaczone tło przy zmianie stylu zmienia kolory '
        'i font w każdej klatce razem z motywem', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final teksty = lookupAppLocalizations(const Locale('en'));
      final services = await uruchom(tester);
      final zmierzch = teksty.backgroundDusk;
      await tester.runAsync(() => services.db.saveBackground(1));

      const klucz = ValueKey('ustawienia');
      final od = chattTheme(AppStyle.cisza, Brightness.light);
      final cel = chattTheme(AppStyle.precyzja, Brightness.light);
      await tester.pumpWidget(ustawienia(services, od, key: klucz));
      await dokoncz(tester, () => find.text(zmierzch).evaluate().isNotEmpty);
      await tester.ensureVisible(find.text(zmierzch));
      // Zaznaczenie przychodzi z bazy.
      await dokoncz(
          tester, () => zaznaczenie(tester, zmierzch).tween.end == 1);
      await tester.pump(const Duration(seconds: 1));
      expect(obrysNaEkranie(tester, zmierzch).top.width, 3);
      expect(stylPodpisu(tester, zmierzch).fontFamily, 'Figtree');

      // Motyw przenika liniowo w 200 ms. Obrys i podpis mają w każdej
      // klatce kolor i font motywu z tej klatki.
      await tester.pumpWidget(ustawienia(services, cel, key: klucz));
      for (var ms = 40; ms <= 200; ms += 40) {
        await tester.pump(const Duration(milliseconds: 40));
        final powod = 'po $ms ms';
        final motyw = Theme.of(tester.element(obrys(zmierzch)));
        final obramowanie = obrysNaEkranie(tester, zmierzch).top;
        final podpis = stylPodpisu(tester, zmierzch);
        kolory([obramowanie.color, podpis.color!],
            [motyw.colorScheme.primary, motyw.colorScheme.primary], powod);
        expect(obramowanie.width, 3, reason: powod);
        expect(podpis.fontFamily, motyw.textTheme.bodyMedium!.fontFamily,
            reason: powod);
        if (ms < 200) {
          pomiedzy(motyw.colorScheme.primary, od.colorScheme.primary,
              cel.colorScheme.primary, powod,
              scisle: true);
        }
      }
      expect(stylPodpisu(tester, zmierzch).fontFamily, 'IBMPlexSans');

      await sprzatnij(tester, services);
    });

    testWidgets('Ustawienia: pytanie o wyczyszczenie historii wchodzi jak '
        'karta zgody, z zasłoną stylu; Anuluj niczego nie kasuje',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final teksty = lookupAppLocalizations(const Locale('en'));
      final services = await uruchom(tester);
      await tester.runAsync(() async {
        final peer = await services.db.upsertPeer(
          guid: 'guid-Alicja',
          name: 'Alicja',
          welcomeMessage: '',
          host: '',
          port: 0,
        );
        await services.db.ensureConversation(peer.id);
      });
      Future<int> rozmowy() async => (await tester.runAsync(
              () => services.db.select(services.db.conversations).get()))!
          .length;
      expect(await rozmowy(), 1);
      chattToasts.clear();

      for (final (styl, ogranicz) in [
        for (final styl in AppStyle.values) (styl, false),
        (AppStyle.cisza, true),
      ]) {
        final powod = '${styl.name}${ogranicz ? ', ograniczone' : ''}';
        final theme = chattTheme(styl, Brightness.light);
        final m = ogranicz ? chattMotion(styl).reduced : chattMotion(styl);
        await tester.pumpWidget(ustawienia(services, theme,
            key: ValueKey(powod), ograniczRuch: ogranicz));
        await dokoncz(tester,
            () => find.text(teksty.stylePrecyzja).evaluate().isNotEmpty);
        final przycisk = find.text(teksty.clearHistory);
        await tester.scrollUntilVisible(przycisk, 300,
            scrollable: find.byType(Scrollable).first);
        await tester.pump();
        await tester.tap(przycisk);
        await tester.pump();

        // Okno stylu na głównym nawigatorze: ruch karty zgody i zasłona
        // stylu.
        final okno = find.byType(AlertDialog);
        expect(okno, findsOneWidget, reason: powod);
        final trasa = ModalRoute.of(tester.element(okno));
        expect(trasa, isA<ChattDialogRoute<bool>>(), reason: powod);
        trasa as ChattDialogRoute<bool>;
        expect(trasa.navigator,
            same(tester.state<NavigatorState>(find.byType(Navigator).first)),
            reason: powod);
        expect(trasa.panel, isFalse, reason: powod);
        expect(trasa.motion.isReduced, ogranicz, reason: powod);
        expect(trasa.transitionDuration, m.cardIn, reason: powod);
        expect(trasa.reverseTransitionDuration, m.cardOut, reason: powod);
        expect(trasa.barrierColor, theme.colorScheme.scrim, reason: powod);
        expect(
            find.ancestor(of: okno, matching: find.byType(MotionTransition)),
            findsOneWidget,
            reason: powod);

        await tester.pump(m.cardIn);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.tap(
            find.descendant(of: okno, matching: find.text(teksty.cancel)));
        await tester.pump();
        await tester.pump(m.cardOut);
        await tester.pump(const Duration(milliseconds: 16));
        expect(okno, findsNothing, reason: powod);
        expect(await rozmowy(), 1, reason: powod);
        expect(chattToasts.value, isEmpty, reason: powod);
      }

      await sprzatnij(tester, services);
    });
  });
}
