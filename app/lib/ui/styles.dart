import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../data/db.dart' show AppStyle;

// Trzy style wyglądu (issue #37): Cisza, Precyzja, Ciepło, każdy w motywie
// jasnym i ciemnym. Układ i informacje są wspólne; style różnią się
// wyłącznie tokenami z tego pliku. Wartości pochodzą z zaakceptowanego
// szablonu w Claude Design (`chatt-themes.js`).

/// Rodziny fontów zadeklarowane w `pubspec.yaml`.
const _figtree = 'Figtree';
const _plexSans = 'IBMPlexSans';
const _nunito = 'Nunito';
const _dmMono = 'DMMono';
const _plexMono = 'IBMPlexMono';
const _splineMono = 'SplineSansMono';

/// Para kolorów awatara: tło i inicjały.
typedef AvatarColors = ({Color background, Color foreground});

/// Jedno z pięciu teł pod aplikacją: jeden kolor albo gradient.
typedef Wall = ({List<Color> colors, List<double>? stops});

/// Kolory ramki z komunikatem: tło, tekst, ikona i obrys.
typedef NoteColors = ({
  Color background,
  Color foreground,
  Color icon,
  Color? border,
  double borderWidth,
});

/// Ruch stylu (issue #54): czasy, krzywe i przesunięcia przejść z projektów
/// stylów w Claude Design. Przesunięcia w dp. Krzywe wyjść opisują postęp
/// znikania, tak jak w CSS; animacja w tył bierze je odwrócone
/// ([exitReverse]).
@immutable
class ChattMotion {
  /// Krzywa wejść i krzywa wyjść.
  final Curve enter;
  final Curve exit;

  /// Nowy ekran: wspólna oś X, wjazd z prawej o [screenShift]
  /// i przenikanie; powrót w [screenOut].
  final Duration screenIn;
  final Duration screenOut;
  final double screenShift;

  /// Zmiana rozmowy na szerokim oknie: przenikanie panelu.
  final Duration paneSwitch;

  /// Karta zgody i okno: wejście, wyjście i krzywa ruchu wejścia
  /// (w Cieple sprężynka, która lekko przestrzeliwuje).
  final Duration cardIn;
  final Duration cardOut;
  final Curve cardCurve;

  /// Skala i przesunięcie karty na starcie, osobno na telefonie i w oknie.
  /// Przesunięcie dodatnie: karta przychodzi z dołu, ujemne: z góry.
  final double cardScalePhone;
  final double cardShiftPhone;
  final double cardScaleWindow;
  final double cardShiftWindow;

  /// Panel bezpieczeństwa: na telefonie arkusz od dołu, w oknie okno na
  /// środku ze skalą [panelScale] na starcie.
  final Duration panelIn;
  final Duration panelOut;
  final double panelScale;

  /// Zasłona pod oknem i arkuszem: czas narastania i krzywa.
  final Duration scrim;
  final Curve scrimCurve;

  /// Nowy dymek: wjazd w górę o [bubbleShift] i przenikanie.
  final Duration bubble;
  final double bubbleShift;
  final Curve bubbleCurve;

  /// Pasek postępu między próbkami. Zero: pasek idzie wprost za próbkami.
  final Duration progress;
  final Curve progressCurve;

  /// Komunikat w rogu: wejście w górę o [toastShift], wyjście, czas na
  /// ekranie. Bez [toastExitShift] komunikat znika samym przenikaniem.
  final Duration toastIn;
  final Duration toastOut;
  final double toastShift;
  final bool toastExitShift;
  final Duration toastHold;

  /// Przełączniki i wybór tła: kolor i pozycja.
  final Duration control;

  /// Zmiana stylu, motywu i tła: przenikanie.
  final Duration themeChange;

  /// Najechanie i fokus na Windows: kolor tła i pierścień.
  final Duration hover;

  const ChattMotion({
    required this.enter,
    required this.exit,
    required this.screenIn,
    required this.screenOut,
    required this.screenShift,
    required this.paneSwitch,
    required this.cardIn,
    required this.cardOut,
    required this.cardCurve,
    required this.cardScalePhone,
    required this.cardShiftPhone,
    required this.cardScaleWindow,
    required this.cardShiftWindow,
    required this.panelIn,
    required this.panelOut,
    required this.panelScale,
    required this.scrim,
    required this.scrimCurve,
    required this.bubble,
    required this.bubbleShift,
    required this.bubbleCurve,
    required this.progress,
    required this.progressCurve,
    required this.toastIn,
    required this.toastOut,
    required this.toastShift,
    required this.toastExitShift,
    required this.toastHold,
    required this.control,
    required this.themeChange,
    required this.hover,
  });

  /// Czas każdego przejścia przy „ogranicz animacje” w systemie.
  static const reducedDuration = Duration(milliseconds: 100);

  /// Ruch przy „ogranicz animacje”: każde przejście to przenikanie 100 ms
  /// bez przesunięć i skali, pasek postępu idzie wprost za próbkami.
  /// Komunikat stoi na ekranie tyle samo co zwykle.
  ChattMotion get reduced => ChattMotion(
        enter: Curves.linear,
        exit: Curves.linear,
        screenIn: reducedDuration,
        screenOut: reducedDuration,
        screenShift: 0,
        paneSwitch: reducedDuration,
        cardIn: reducedDuration,
        cardOut: reducedDuration,
        cardCurve: Curves.linear,
        cardScalePhone: 1,
        cardShiftPhone: 0,
        cardScaleWindow: 1,
        cardShiftWindow: 0,
        panelIn: reducedDuration,
        panelOut: reducedDuration,
        panelScale: 1,
        scrim: reducedDuration,
        scrimCurve: Curves.linear,
        bubble: reducedDuration,
        bubbleShift: 0,
        bubbleCurve: Curves.linear,
        progress: Duration.zero,
        progressCurve: Curves.linear,
        toastIn: reducedDuration,
        toastOut: reducedDuration,
        toastShift: 0,
        toastExitShift: false,
        toastHold: toastHold,
        control: reducedDuration,
        themeChange: reducedDuration,
        hover: reducedDuration,
      );

  /// Czy to ruch przy „ogranicz animacje”.
  bool get isReduced => screenIn == reducedDuration && screenShift == 0;

  /// Krzywa wyjścia dla animacji w tył (od 1 do 0).
  Curve get exitReverse => exit.flipped;

  /// Krzywa zasłony jako część przejścia o czasie [total]: zasłona dochodzi
  /// do pełnej w [scrim], nawet gdy okno wjeżdża dłużej.
  Curve scrimWithin(Duration total) {
    if (total <= Duration.zero || scrim >= total) return scrimCurve;
    return Interval(0, scrim.inMicroseconds / total.inMicroseconds,
        curve: scrimCurve);
  }

  /// Ruch bieżącego stylu z uwzględnieniem „ogranicz animacje” w systemie.
  static ChattMotion of(BuildContext context) {
    final m = ChattTokens.of(context).motion;
    return (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
        ? m.reduced
        : m;
  }
}

/// Wejście Ciszy, wejście i wyjście Precyzji.
const _krzywaCiszy = Cubic(0.2, 0, 0, 1);
const _wyjsciePrecyzji = Cubic(0.3, 0, 1, 1);
const _krzywaCiepla = Cubic(0.2, 0.8, 0.2, 1);

/// Sprężynka Ciepła przy kartach zgody: lekko przestrzeliwuje.
const _sprezynkaCiepla = Cubic(0.2, 0.9, 0.3, 1.15);

const _ruchCiszy = ChattMotion(
  enter: _krzywaCiszy,
  exit: _krzywaCiszy,
  screenIn: Duration(milliseconds: 300),
  screenOut: Duration(milliseconds: 250),
  screenShift: 30,
  paneSwitch: Duration(milliseconds: 200),
  cardIn: Duration(milliseconds: 280),
  cardOut: Duration(milliseconds: 180),
  cardCurve: _krzywaCiszy,
  cardScalePhone: 1,
  cardShiftPhone: 24,
  cardScaleWindow: 0.96,
  cardShiftWindow: 0,
  panelIn: Duration(milliseconds: 280),
  panelOut: Duration(milliseconds: 180),
  panelScale: 0.96,
  scrim: Duration(milliseconds: 200),
  scrimCurve: _krzywaCiszy,
  bubble: Duration(milliseconds: 220),
  bubbleShift: 8,
  bubbleCurve: _krzywaCiszy,
  progress: Duration(milliseconds: 400),
  progressCurve: _krzywaCiszy,
  toastIn: Duration(milliseconds: 240),
  toastOut: Duration(milliseconds: 160),
  toastShift: 16,
  toastExitShift: true,
  toastHold: Duration(milliseconds: 3200),
  control: Duration(milliseconds: 200),
  themeChange: Duration(milliseconds: 300),
  hover: Duration(milliseconds: 120),
);

const _ruchPrecyzji = ChattMotion(
  enter: _krzywaCiszy,
  exit: _wyjsciePrecyzji,
  screenIn: Duration(milliseconds: 220),
  screenOut: Duration(milliseconds: 220),
  screenShift: 24,
  paneSwitch: Duration(milliseconds: 120),
  cardIn: Duration(milliseconds: 180),
  cardOut: Duration(milliseconds: 180),
  cardCurve: _krzywaCiszy,
  cardScalePhone: 0.98,
  cardShiftPhone: 0,
  cardScaleWindow: 0.98,
  cardShiftWindow: 0,
  panelIn: Duration(milliseconds: 180),
  panelOut: Duration(milliseconds: 180),
  panelScale: 0.98,
  scrim: Duration(milliseconds: 140),
  scrimCurve: Curves.linear,
  bubble: Duration(milliseconds: 140),
  bubbleShift: 6,
  bubbleCurve: _krzywaCiszy,
  progress: Duration.zero,
  progressCurve: Curves.linear,
  toastIn: Duration(milliseconds: 180),
  toastOut: Duration(milliseconds: 140),
  toastShift: 8,
  toastExitShift: true,
  toastHold: Duration(milliseconds: 4200),
  control: Duration(milliseconds: 120),
  themeChange: Duration(milliseconds: 120),
  hover: Duration(milliseconds: 120),
);

const _ruchCiepla = ChattMotion(
  enter: _krzywaCiepla,
  exit: _krzywaCiepla,
  screenIn: Duration(milliseconds: 280),
  screenOut: Duration(milliseconds: 280),
  screenShift: 18,
  paneSwitch: Duration(milliseconds: 200),
  cardIn: Duration(milliseconds: 260),
  cardOut: Duration(milliseconds: 180),
  cardCurve: _sprezynkaCiepla,
  cardScalePhone: 0.97,
  cardShiftPhone: -10,
  cardScaleWindow: 0.97,
  cardShiftWindow: -10,
  panelIn: Duration(milliseconds: 300),
  panelOut: Duration(milliseconds: 180),
  panelScale: 0.97,
  scrim: Duration(milliseconds: 180),
  scrimCurve: _krzywaCiepla,
  bubble: Duration(milliseconds: 200),
  bubbleShift: 8,
  bubbleCurve: Curves.easeOut,
  progress: Duration(milliseconds: 250),
  progressCurve: Curves.linear,
  toastIn: Duration(milliseconds: 220),
  toastOut: Duration(milliseconds: 160),
  toastShift: 8,
  toastExitShift: false,
  toastHold: Duration(milliseconds: 3200),
  control: Duration(milliseconds: 200),
  themeChange: Duration(milliseconds: 200),
  hover: Duration(milliseconds: 120),
);

/// Ruch stylu bez „ogranicz animacje”.
ChattMotion chattMotion(AppStyle style) => switch (style) {
      AppStyle.cisza => _ruchCiszy,
      AppStyle.precyzja => _ruchPrecyzji,
      AppStyle.cieplo => _ruchCiepla,
    };

/// Przejście między ekranami w stylu: wspólna oś X. Nowy ekran wjeżdża
/// z prawej o [ChattMotion.screenShift] i pojawia się, poprzedni odjeżdża
/// w lewo i znika; powrót odwrotnie.
class ChattPageTransitionsBuilder extends PageTransitionsBuilder {
  final ChattMotion motion;

  const ChattPageTransitionsBuilder(this.motion);

  @override
  Duration get transitionDuration => motion.screenIn;

  @override
  Duration get reverseTransitionDuration => motion.screenOut;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      _WspolnaOs(
        motion: motion,
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
}

class _WspolnaOs extends StatefulWidget {
  final ChattMotion motion;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  const _WspolnaOs({
    required this.motion,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  @override
  State<_WspolnaOs> createState() => _WspolnaOsState();
}

class _WspolnaOsState extends State<_WspolnaOs> {
  late CurvedAnimation _wjazd;
  late CurvedAnimation _odjazd;

  // Przenikanie przez tło: stary ekran znika w pierwszych 30% przejścia,
  // nowy pojawia się w pozostałych, więc w żadnej chwili oba nie leżą na
  // sobie w połowie przezroczystości.
  static const _pojawianie = Interval(0.3, 1);
  static const _znikanie = Interval(0, 0.3);

  @override
  void initState() {
    super.initState();
    _krzywe();
  }

  @override
  void didUpdateWidget(_WspolnaOs old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation ||
        old.secondaryAnimation != widget.secondaryAnimation ||
        old.motion != widget.motion) {
      _wjazd.dispose();
      _odjazd.dispose();
      _krzywe();
    }
  }

  void _krzywe() {
    final m = widget.motion;
    _wjazd = CurvedAnimation(
        parent: widget.animation, curve: m.enter, reverseCurve: m.exitReverse);
    _odjazd = CurvedAnimation(
        parent: widget.secondaryAnimation,
        curve: m.enter,
        reverseCurve: m.exitReverse);
  }

  @override
  void dispose() {
    _wjazd.dispose();
    _odjazd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final przesuniecie = widget.motion.screenShift;
    final kierunek =
        Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    return AnimatedBuilder(
      animation: Listenable.merge([widget.animation, widget.secondaryAnimation]),
      child: widget.child,
      builder: (context, child) {
        final dx = kierunek *
            (przesuniecie * (1 - _wjazd.value) - przesuniecie * _odjazd.value);
        final widac = _pojawianie.transform(widget.animation.value) *
            (1 - _znikanie.transform(widget.secondaryAnimation.value));
        return Opacity(
          opacity: widac.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
    );
  }
}

/// Tokeny stylu spoza [ColorScheme]: sygnały bezpieczeństwa, dymki, awatary,
/// promienie, gęstość, teksty o stałej szerokości i ruch.
@immutable
class ChattTokens extends ThemeExtension<ChattTokens> {
  final AppStyle style;

  /// Powierzchnie od tła po najjaśniejszą (`bg`, `s1`, `s2`, `s3`).
  final Color background;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color outline;
  final Color outlineStrong;
  final Color textMuted;

  /// Akcent jako tekst albo odnośnik.
  final Color accentText;

  final Color bubbleMine;
  final Color onBubbleMine;
  final Color bubbleMineMeta;
  final Color bubbleTheirs;
  final Color onBubbleTheirs;
  final Color bubbleTheirsMeta;
  final Color? bubbleTheirsBorder;
  final double bubbleRadius;
  final double bubbleTail;
  final EdgeInsets bubblePadding;
  final double bubbleMaxFraction;
  final double gapBetweenSenders;
  final List<BoxShadow> bubbleShadow;

  /// Cienie trzech poziomów. W Precyzji płasko: poziom wyznacza obrys.
  final List<BoxShadow> shadow1;
  final List<BoxShadow> shadow2;
  final List<BoxShadow> shadow3;

  final Color presence;

  /// Pusty pierścień przy rozmówcy offline (Precyzja). null: bez kropki.
  final Color? presenceOff;
  final double presenceDot;
  final double presenceDotBorder;

  final Color verified;
  final Color verifiedContainer;
  final Color onVerifiedContainer;
  final Color? verifiedBorder;

  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color? warningBorder;

  final Color danger;
  final Color dangerContainer;
  final Color onDangerContainer;
  final Color dangerBorder;
  final double dangerBorderWidth;

  /// Ostrzeżenie bezpieczeństwa (tożsamość niepotwierdzona): w Ciszy ma
  /// wygląd zagrożenia, w Precyzji i Cieple bursztynowy.
  final bool securityAsDanger;

  final Color toast;
  final Color onToast;
  final Color searchHit;
  final Color onSearchHit;
  final Color searchHitCurrent;

  final double radiusCard;
  final double radiusSheet;
  final double radiusField;
  final double radiusButton;
  final double radiusBadge;
  final double radiusWarning;
  final double radiusRow;

  /// Awatar: koło albo zaokrąglony kwadrat z promieniem [avatarCorner]
  /// boku.
  final bool avatarCircle;
  final double avatarCorner;
  final double avatarSize;

  /// Awatar w nagłówku rozmowy.
  final double avatarHeaderSize;
  final FontWeight avatarWeight;
  final List<AvatarColors> avatars;

  /// Lista rozmów.
  final double rowHeight;
  final EdgeInsets rowPadding;
  final double rowGap;
  final Color unreadTime;

  /// Znacznik drogi na liście.
  final Color? routeBackground;
  final Color? routeBorder;
  final double routeRadius;
  final double routeBox;
  final double routeIcon;

  /// Separator daty: linia z etykietą (Precyzja) albo pigułka.
  final bool separatorLine;
  final Color separatorBackground;
  final List<BoxShadow> separatorShadow;

  /// Teksty: wartości techniczne, kod bezpieczeństwa, etykiety sekcji,
  /// separator daty, metadane.
  final TextStyle mono;
  final TextStyle code;
  final TextStyle overline;
  final bool overlineUppercase;
  final TextStyle separator;
  final TextStyle caption;

  final List<Wall> walls;

  /// Ruch stylu. Przy „ogranicz animacje” czytaj przez [ChattMotion.of].
  final ChattMotion motion;

  const ChattTokens({
    required this.style,
    required this.background,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.outline,
    required this.outlineStrong,
    required this.textMuted,
    required this.accentText,
    required this.bubbleMine,
    required this.onBubbleMine,
    required this.bubbleMineMeta,
    required this.bubbleTheirs,
    required this.onBubbleTheirs,
    required this.bubbleTheirsMeta,
    required this.bubbleTheirsBorder,
    required this.bubbleRadius,
    required this.bubbleTail,
    required this.bubblePadding,
    required this.bubbleMaxFraction,
    required this.gapBetweenSenders,
    required this.bubbleShadow,
    required this.shadow1,
    required this.shadow2,
    required this.shadow3,
    required this.presence,
    required this.presenceOff,
    required this.presenceDot,
    required this.presenceDotBorder,
    required this.verified,
    required this.verifiedContainer,
    required this.onVerifiedContainer,
    required this.verifiedBorder,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.warningBorder,
    required this.danger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.dangerBorder,
    required this.dangerBorderWidth,
    required this.securityAsDanger,
    required this.toast,
    required this.onToast,
    required this.searchHit,
    required this.onSearchHit,
    required this.searchHitCurrent,
    required this.radiusCard,
    required this.radiusSheet,
    required this.radiusField,
    required this.radiusButton,
    required this.radiusBadge,
    required this.radiusWarning,
    required this.radiusRow,
    required this.avatarCircle,
    required this.avatarCorner,
    required this.avatarSize,
    required this.avatarHeaderSize,
    required this.avatarWeight,
    required this.avatars,
    required this.rowHeight,
    required this.rowPadding,
    required this.rowGap,
    required this.unreadTime,
    required this.routeBackground,
    required this.routeBorder,
    required this.routeRadius,
    required this.routeBox,
    required this.routeIcon,
    required this.separatorLine,
    required this.separatorBackground,
    required this.separatorShadow,
    required this.mono,
    required this.code,
    required this.overline,
    required this.overlineUppercase,
    required this.separator,
    required this.caption,
    required this.walls,
    required this.motion,
  });

  /// Tokeny bieżącego motywu. Poza aplikacją (testy widżetów z gołym
  /// `MaterialApp`) zostaje Cisza w jasności motywu.
  static ChattTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ChattTokens>() ??
        chattTokens(AppStyle.cisza, theme.brightness);
  }

  /// Kolory awatara dla nazwy: stałe dla tej samej nazwy, różne dla
  /// różnych.
  AvatarColors avatarFor(String name) {
    var hash = 0;
    for (final unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return avatars[hash % avatars.length];
  }

  /// Ostrzeżenie bezpieczeństwa w wyglądzie tego stylu: czerwone w Ciszy,
  /// bursztynowe w Precyzji i Cieple.
  NoteColors get security => securityAsDanger ? dangerNote : warningNote;

  /// Zagrożenie: czerwone w każdym stylu.
  NoteColors get dangerNote => (
        background: dangerContainer,
        foreground: onDangerContainer,
        icon: danger,
        border: dangerBorder,
        borderWidth: dangerBorderWidth,
      );

  NoteColors get warningNote => (
        background: warningContainer,
        foreground: onWarningContainer,
        icon: warning,
        border: warningBorder,
        borderWidth: warningBorder == null ? 0 : 1.5,
      );

  /// Potwierdzona tożsamość.
  NoteColors get verifiedNote => (
        background: verifiedContainer,
        foreground: onVerifiedContainer,
        icon: verified,
        border: verifiedBorder,
        borderWidth: verifiedBorder == null ? 0 : 1.5,
      );

  /// Nagłówek sekcji w stylu (wersaliki w Precyzji).
  String overlineText(String text) =>
      overlineUppercase ? text.toUpperCase() : text;

  @override
  ChattTokens copyWith() => this;

  /// Przenikanie przy zmianie motywu, stylu i tła: kolory, cienie, wymiary
  /// i teksty przechodzą płynnie, przełączniki stylu w połowie drogi.
  @override
  ChattTokens lerp(ThemeExtension<ChattTokens>? other, double t) {
    if (other is! ChattTokens) return this;
    if (identical(other, this) || t <= 0) return this;
    if (t >= 1) return other;
    final b = other;
    final pierwszy = t < 0.5;
    T skok<T>(T a, T z) => pierwszy ? a : z;
    Color k(Color a, Color z) => Color.lerp(a, z, t)!;
    Color? kn(Color? a, Color? z) => Color.lerp(a, z, t);
    double d(double a, double z) => a + (z - a) * t;
    List<BoxShadow> c(List<BoxShadow> a, List<BoxShadow> z) =>
        BoxShadow.lerpList(a, z, t) ?? const [];
    TextStyle s(TextStyle a, TextStyle z) => TextStyle.lerp(a, z, t)!;
    return ChattTokens(
      style: skok(style, b.style),
      background: k(background, b.background),
      surface1: k(surface1, b.surface1),
      surface2: k(surface2, b.surface2),
      surface3: k(surface3, b.surface3),
      outline: k(outline, b.outline),
      outlineStrong: k(outlineStrong, b.outlineStrong),
      textMuted: k(textMuted, b.textMuted),
      accentText: k(accentText, b.accentText),
      bubbleMine: k(bubbleMine, b.bubbleMine),
      onBubbleMine: k(onBubbleMine, b.onBubbleMine),
      bubbleMineMeta: k(bubbleMineMeta, b.bubbleMineMeta),
      bubbleTheirs: k(bubbleTheirs, b.bubbleTheirs),
      onBubbleTheirs: k(onBubbleTheirs, b.onBubbleTheirs),
      bubbleTheirsMeta: k(bubbleTheirsMeta, b.bubbleTheirsMeta),
      bubbleTheirsBorder: kn(bubbleTheirsBorder, b.bubbleTheirsBorder),
      bubbleRadius: d(bubbleRadius, b.bubbleRadius),
      bubbleTail: d(bubbleTail, b.bubbleTail),
      bubblePadding: EdgeInsets.lerp(bubblePadding, b.bubblePadding, t)!,
      bubbleMaxFraction: d(bubbleMaxFraction, b.bubbleMaxFraction),
      gapBetweenSenders: d(gapBetweenSenders, b.gapBetweenSenders),
      bubbleShadow: c(bubbleShadow, b.bubbleShadow),
      shadow1: c(shadow1, b.shadow1),
      shadow2: c(shadow2, b.shadow2),
      shadow3: c(shadow3, b.shadow3),
      presence: k(presence, b.presence),
      presenceOff: kn(presenceOff, b.presenceOff),
      presenceDot: d(presenceDot, b.presenceDot),
      presenceDotBorder: d(presenceDotBorder, b.presenceDotBorder),
      verified: k(verified, b.verified),
      verifiedContainer: k(verifiedContainer, b.verifiedContainer),
      onVerifiedContainer: k(onVerifiedContainer, b.onVerifiedContainer),
      verifiedBorder: kn(verifiedBorder, b.verifiedBorder),
      warning: k(warning, b.warning),
      warningContainer: k(warningContainer, b.warningContainer),
      onWarningContainer: k(onWarningContainer, b.onWarningContainer),
      warningBorder: kn(warningBorder, b.warningBorder),
      danger: k(danger, b.danger),
      dangerContainer: k(dangerContainer, b.dangerContainer),
      onDangerContainer: k(onDangerContainer, b.onDangerContainer),
      dangerBorder: k(dangerBorder, b.dangerBorder),
      dangerBorderWidth: d(dangerBorderWidth, b.dangerBorderWidth),
      securityAsDanger: skok(securityAsDanger, b.securityAsDanger),
      toast: k(toast, b.toast),
      onToast: k(onToast, b.onToast),
      searchHit: k(searchHit, b.searchHit),
      onSearchHit: k(onSearchHit, b.onSearchHit),
      searchHitCurrent: k(searchHitCurrent, b.searchHitCurrent),
      radiusCard: d(radiusCard, b.radiusCard),
      radiusSheet: d(radiusSheet, b.radiusSheet),
      radiusField: d(radiusField, b.radiusField),
      radiusButton: d(radiusButton, b.radiusButton),
      radiusBadge: d(radiusBadge, b.radiusBadge),
      radiusWarning: d(radiusWarning, b.radiusWarning),
      radiusRow: d(radiusRow, b.radiusRow),
      avatarCircle: skok(avatarCircle, b.avatarCircle),
      avatarCorner: d(avatarCorner, b.avatarCorner),
      avatarSize: d(avatarSize, b.avatarSize),
      avatarHeaderSize: d(avatarHeaderSize, b.avatarHeaderSize),
      avatarWeight: FontWeight.lerp(avatarWeight, b.avatarWeight, t)!,
      avatars: avatars.length == b.avatars.length
          ? [
              for (var i = 0; i < avatars.length; i++)
                (
                  background:
                      k(avatars[i].background, b.avatars[i].background),
                  foreground:
                      k(avatars[i].foreground, b.avatars[i].foreground),
                ),
            ]
          : skok(avatars, b.avatars),
      rowHeight: d(rowHeight, b.rowHeight),
      rowPadding: EdgeInsets.lerp(rowPadding, b.rowPadding, t)!,
      rowGap: d(rowGap, b.rowGap),
      unreadTime: k(unreadTime, b.unreadTime),
      routeBackground: kn(routeBackground, b.routeBackground),
      routeBorder: kn(routeBorder, b.routeBorder),
      routeRadius: d(routeRadius, b.routeRadius),
      routeBox: d(routeBox, b.routeBox),
      routeIcon: d(routeIcon, b.routeIcon),
      separatorLine: skok(separatorLine, b.separatorLine),
      separatorBackground: k(separatorBackground, b.separatorBackground),
      separatorShadow: c(separatorShadow, b.separatorShadow),
      mono: s(mono, b.mono),
      code: s(code, b.code),
      overline: s(overline, b.overline),
      overlineUppercase: skok(overlineUppercase, b.overlineUppercase),
      separator: s(separator, b.separator),
      caption: s(caption, b.caption),
      walls: walls.length == b.walls.length
          ? [
              for (var i = 0; i < walls.length; i++)
                lerpWall(walls[i], b.walls[i], t),
            ]
          : skok(walls, b.walls),
      motion: skok(motion, b.motion),
    );
  }
}

/// Tło w połowie drogi między dwoma. Gradienty o tej samej liczbie kolorów
/// przechodzą kolor po kolorze. Przy różnej liczbie oba gradienty
/// próbkujemy we wszystkich progach obu, więc każdy na starcie i na końcu
/// wygląda dokładnie jak on sam; jeden kolor to gradient z tego koloru.
Wall lerpWall(Wall a, Wall b, double t) {
  if (t <= 0) return a;
  if (t >= 1) return b;
  List<double> progi(Wall w) =>
      w.stops ??
      [
        for (var i = 0; i < w.colors.length; i++)
          w.colors.length == 1 ? 0.0 : i / (w.colors.length - 1),
      ];
  if (a.colors.length == b.colors.length) {
    final pa = progi(a);
    final pb = progi(b);
    return (
      colors: [
        for (var i = 0; i < a.colors.length; i++)
          Color.lerp(a.colors[i], b.colors[i], t)!,
      ],
      stops: a.stops == null && b.stops == null
          ? null
          : [for (var i = 0; i < pa.length; i++) pa[i] + (pb[i] - pa[i]) * t],
    );
  }
  // Kolor gradientu w miejscu x (od 0 do 1), liniowo między progami.
  Color probka(Wall w, double x) {
    final k = w.colors;
    if (k.length == 1) return k.single;
    final p = progi(w);
    if (x <= p.first) return k.first;
    for (var i = 1; i < p.length; i++) {
      if (x <= p[i]) {
        final odcinek = p[i] - p[i - 1];
        return Color.lerp(
            k[i - 1], k[i], odcinek <= 0 ? 1 : (x - p[i - 1]) / odcinek)!;
      }
    }
    return k.last;
  }

  final wspolne = <double>{
    for (final w in [a, b])
      if (w.colors.length > 1) ...progi(w),
  }.toList()
    ..sort();
  return (
    colors: [
      for (final x in wspolne) Color.lerp(probka(a, x), probka(b, x), t)!,
    ],
    stops: wspolne,
  );
}

Color _c(int argb) => Color(argb);

List<BoxShadow> _shadow(List<(double y, double blur, double spread, int color)> parts) => [
      for (final (y, blur, spread, color) in parts)
        BoxShadow(
          offset: Offset(0, y),
          blurRadius: blur,
          spreadRadius: spread,
          color: Color(color),
        ),
    ];

const _none = <BoxShadow>[];

/// Gradient 165° z szablonu.
Wall _wall(List<int> colors, [List<double>? stops]) =>
    (colors: [for (final c in colors) Color(c)], stops: stops);

/// Kolor z przestrzeni OKLCH (awatary Precyzji liczone z odcienia).
Color _oklch(double l, double c, double hueDegrees) {
  final h = hueDegrees * math.pi / 180;
  final a = c * math.cos(h);
  final b = c * math.sin(h);
  final l1 = math.pow(l + 0.3963377774 * a + 0.2158037573 * b, 3).toDouble();
  final m1 = math.pow(l - 0.1055613458 * a - 0.0638541728 * b, 3).toDouble();
  final s1 = math.pow(l - 0.0894841775 * a - 1.2914855480 * b, 3).toDouble();
  double gamma(double x) {
    final v = x <= 0.0031308 ? 12.92 * x : 1.055 * math.pow(x, 1 / 2.4) - 0.055;
    return v.clamp(0.0, 1.0);
  }

  final r = gamma(4.0767416621 * l1 - 3.3077115913 * m1 + 0.2309699292 * s1);
  final g = gamma(-1.2684380046 * l1 + 2.6097574011 * m1 - 0.3413193965 * s1);
  final bl = gamma(-0.0041960863 * l1 - 0.7034186147 * m1 + 1.7076147010 * s1);
  return Color.from(alpha: 1, red: r, green: g, blue: bl);
}

const _precyzjaHues = [275.0, 210.0, 60.0, 150.0, 330.0];

TextStyle _t(String family, double size, FontWeight weight,
        {double? height, double letterSpacing = 0}) =>
    TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: weight,
      height: height == null ? null : height / size,
      letterSpacing: letterSpacing * size,
    );

TextStyle _tr(String family, double size, FontWeight weight, double ratio,
        {double letterSpacing = 0}) =>
    TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: weight,
      height: ratio,
      letterSpacing: letterSpacing * size,
    );

const _tabular = [FontFeature.tabularFigures()];

/// Tokeny jednego z sześciu wariantów. [reduceMotion]: „ogranicz animacje”
/// w systemie, każde przejście staje się przenikaniem 100 ms.
ChattTokens chattTokens(AppStyle style, Brightness brightness,
    {bool reduceMotion = false}) {
  final dark = brightness == Brightness.dark;
  final ruch =
      reduceMotion ? chattMotion(style).reduced : chattMotion(style);
  switch (style) {
    case AppStyle.cisza:
      return ChattTokens(
        style: style,
        background: _c(dark ? 0xFF1A1E1E : 0xFFF3F5F4),
        surface1: _c(dark ? 0xFF242A2A : 0xFFFFFFFF),
        surface2: _c(dark ? 0xFF2D3434 : 0xFFEDF1F0),
        surface3: _c(dark ? 0xFF363E3E : 0xFFE1E7E5),
        outline: _c(dark ? 0xFF3B4545 : 0xFFD3DCDA),
        outlineStrong: _c(dark ? 0xFF3B4545 : 0xFFD3DCDA),
        textMuted: _c(dark ? 0xFFA1AEAC : 0xFF566462),
        accentText: _c(dark ? 0xFF7CCDD5 : 0xFF0F6A73),
        bubbleMine: _c(dark ? 0xFF1F4245 : 0xFFDBEEEC),
        onBubbleMine: _c(dark ? 0xFFE2F3F3 : 0xFF0E2B2D),
        bubbleMineMeta: _c(dark ? 0xFFA1AEAC : 0xFF566462),
        bubbleTheirs: _c(dark ? 0xFF242A2A : 0xFFFFFFFF),
        onBubbleTheirs: _c(dark ? 0xFFE5ECEB : 0xFF162120),
        bubbleTheirsMeta: _c(dark ? 0xFFA1AEAC : 0xFF566462),
        bubbleTheirsBorder: null,
        bubbleRadius: 20,
        bubbleTail: 6,
        bubblePadding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        bubbleMaxFraction: 0.84,
        gapBetweenSenders: 8,
        bubbleShadow: dark
            ? _shadow([(1, 2, 0, 0x59000000)])
            : _shadow([(1, 2, 0, 0x0F162826), (0, 0, 1, 0x08162826)]),
        shadow1: dark
            ? _shadow([(1, 2, 0, 0x59000000)])
            : _shadow([(1, 2, 0, 0x0F162826), (0, 0, 1, 0x08162826)]),
        shadow2: dark
            ? _shadow([(6, 20, 0, 0x59000000)])
            : _shadow([(6, 20, 0, 0x17162826)]),
        shadow3: dark
            ? _shadow([(18, 48, 0, 0x8C000000)])
            : _shadow([(18, 48, 0, 0x33162826)]),
        presence: _c(dark ? 0xFF5BD08F : 0xFF1B8048),
        presenceOff: null,
        presenceDot: 15,
        presenceDotBorder: 3,
        verified: _c(dark ? 0xFF5BD08F : 0xFF1B8048),
        verifiedContainer: _c(dark ? 0xFF17362A : 0xFFDDF1E3),
        onVerifiedContainer: _c(dark ? 0xFFBDEFD0 : 0xFF0E4A28),
        verifiedBorder: null,
        warning: _c(dark ? 0xFFF2C46B : 0xFF9A5B00),
        warningContainer: _c(dark ? 0xFF3D2E12 : 0xFFFCEFD6),
        onWarningContainer: _c(dark ? 0xFFFBE3B4 : 0xFF5A3600),
        warningBorder: null,
        danger: _c(dark ? 0xFFFFB4A9 : 0xFFB42318),
        dangerContainer: _c(dark ? 0xFF4A1D18 : 0xFFFDE8E4),
        onDangerContainer: _c(dark ? 0xFFFFDAD4 : 0xFF6F170D),
        dangerBorder: _c(dark ? 0xFFFFB4A9 : 0xFFB42318),
        dangerBorderWidth: 1.5,
        securityAsDanger: true,
        toast: _c(dark ? 0xFFE5ECEB : 0xFF1E2827),
        onToast: _c(dark ? 0xFF1A1E1E : 0xFFEEF3F2),
        searchHit: _c(dark ? 0xFF3D2E12 : 0xFFFCEFD6),
        onSearchHit: _c(dark ? 0xFFFBE3B4 : 0xFF5A3600),
        searchHitCurrent: _c(dark ? 0xFFF2C46B : 0xFF9A5B00),
        radiusCard: 24,
        radiusSheet: 24,
        radiusField: 14,
        radiusButton: 16,
        radiusBadge: 999,
        radiusWarning: 16,
        radiusRow: 18,
        avatarCircle: true,
        avatarCorner: 0.5,
        avatarSize: 48,
        avatarHeaderSize: 40,
        avatarWeight: FontWeight.w600,
        avatars: [
          for (final (b, f) in dark
              ? const [
                  (0xFF1F3F42, 0xFFA3DBDF),
                  (0xFF3D3426, 0xFFE8CFA2),
                  (0xFF2B3442, 0xFFBCCBE0),
                  (0xFF42302B, 0xFFF0C0B3),
                  (0xFF352F43, 0xFFD1C6EC),
                ]
              : const [
                  (0xFFD3EBEC, 0xFF145A60),
                  (0xFFF1E6D3, 0xFF6A4A17),
                  (0xFFDFE5EF, 0xFF33465E),
                  (0xFFF3DFD9, 0xFF7A3A2A),
                  (0xFFE7E2F1, 0xFF4B3F6B),
                ])
            (background: Color(b), foreground: Color(f)),
        ],
        rowHeight: 76,
        rowPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        rowGap: 14,
        unreadTime: _c(dark ? 0xFF7CCDD5 : 0xFF0F6A73),
        routeBackground: _c(dark ? 0xFF2D3434 : 0xFFEDF1F0),
        routeBorder: null,
        routeRadius: 8,
        routeBox: 24,
        routeIcon: 15,
        separatorLine: false,
        separatorBackground: _c(dark ? 0xFF242A2A : 0xFFFFFFFF),
        separatorShadow: dark
            ? _shadow([(1, 2, 0, 0x59000000)])
            : _shadow([(1, 2, 0, 0x0F162826), (0, 0, 1, 0x08162826)]),
        mono: _t(_dmMono, 12.5, FontWeight.w500, height: 16)
            .copyWith(fontFeatures: _tabular),
        code: _t(_dmMono, 26, FontWeight.w500, height: 32, letterSpacing: 0.04)
            .copyWith(fontFeatures: _tabular),
        overline: _t(_figtree, 13, FontWeight.w600,
            height: 18, letterSpacing: 0.01),
        overlineUppercase: false,
        separator: _t(_figtree, 12, FontWeight.w600, height: 16),
        caption: _t(_figtree, 12.5, FontWeight.w500, height: 16)
            .copyWith(fontFeatures: _tabular),
        walls: dark
            ? [
                _wall([0xFF1A1E1E]),
                _wall([0xFF27212E, 0xFF2C2323]),
                _wall([0xFF13262C, 0xFF1A222C]),
                _wall([0xFF15251C, 0xFF1F2720]),
                _wall([0xFF2A241B, 0xFF221F1A]),
              ]
            : [
                _wall([0xFFF3F5F4]),
                _wall([0xFFECE5F2, 0xFFF6E8E2]),
                _wall([0xFFD9ECF0, 0xFFE8EFF7]),
                _wall([0xFFDFECE1, 0xFFEEF2E5]),
                _wall([0xFFF3EBDD, 0xFFF8F2E9]),
              ],
        motion: ruch,
      );
    case AppStyle.precyzja:
      return ChattTokens(
        style: style,
        background: _c(dark ? 0xFF0B0C10 : 0xFFEEF0F4),
        surface1: _c(dark ? 0xFF111318 : 0xFFFFFFFF),
        surface2: _c(dark ? 0xFF181B22 : 0xFFF2F3F7),
        surface3: _c(dark ? 0xFF22262F : 0xFFE6E8EE),
        outline: _c(dark ? 0xFF272C36 : 0xFFDCDFE6),
        outlineStrong: _c(dark ? 0xFF3B4250 : 0xFFB9BFCB),
        textMuted: _c(dark ? 0xFF8A91A1 : 0xFF5E6475),
        accentText: _c(dark ? 0xFFA9A7FF : 0xFF3532C8),
        bubbleMine: _c(dark ? 0xFF4340D8 : 0xFF4744E6),
        onBubbleMine: _c(0xFFFFFFFF),
        bubbleMineMeta: _c(dark ? 0xFFD2D1FF : 0xFFE1E0FF),
        bubbleTheirs: _c(dark ? 0xFF181B22 : 0xFFF2F3F7),
        onBubbleTheirs: _c(dark ? 0xFFE9EBF1 : 0xFF0D0F15),
        bubbleTheirsMeta: _c(dark ? 0xFF8A91A1 : 0xFF5E6475),
        bubbleTheirsBorder: _c(dark ? 0xFF272C36 : 0xFFDCDFE6),
        bubbleRadius: 8,
        bubbleTail: 2,
        bubblePadding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        bubbleMaxFraction: 0.80,
        gapBetweenSenders: 0,
        bubbleShadow: _none,
        shadow1: _none,
        shadow2: _none,
        shadow3: dark
            ? _shadow([(16, 40, 0, 0x8C000000)])
            : _shadow([(16, 40, 0, 0x2E0D0F15)]),
        presence: _c(dark ? 0xFF3DDC84 : 0xFF0A9A57),
        presenceOff: _c(dark ? 0xFF8A91A1 : 0xFF5E6475),
        presenceDot: 13,
        presenceDotBorder: 2,
        verified: _c(dark ? 0xFF5BE69A : 0xFF06733F),
        verifiedContainer: _c(dark ? 0xFF0D2A1B : 0xFFE3F6EC),
        onVerifiedContainer: _c(dark ? 0xFF5BE69A : 0xFF06733F),
        verifiedBorder: _c(dark ? 0xFF1E5C3B : 0xFF98D9B6),
        warning: _c(dark ? 0xFFF2B23A : 0xFFA85400),
        warningContainer: _c(dark ? 0xFF2B210D : 0xFFFFF3DE),
        onWarningContainer: _c(dark ? 0xFFE9EBF1 : 0xFF0D0F15),
        warningBorder: _c(dark ? 0xFF5E4516 : 0xFFEDC07E),
        danger: _c(dark ? 0xFFFF6B6B : 0xFFC3261B),
        dangerContainer: _c(dark ? 0xFF2E1216 : 0xFFFDECEA),
        onDangerContainer: _c(dark ? 0xFFE9EBF1 : 0xFF0D0F15),
        dangerBorder: _c(dark ? 0xFF76262F : 0xFFEFA49D),
        dangerBorderWidth: 1,
        securityAsDanger: false,
        toast: _c(dark ? 0xFFE9EBF1 : 0xFF151821),
        onToast: _c(dark ? 0xFF0B0C10 : 0xFFF2F3F7),
        searchHit: _c(0xFFF7D46B),
        onSearchHit: _c(0xFF14110A),
        searchHitCurrent: _c(0xFFFF9F43),
        radiusCard: 8,
        radiusSheet: 8,
        radiusField: 6,
        radiusButton: 6,
        radiusBadge: 4,
        radiusWarning: 6,
        radiusRow: 6,
        avatarCircle: false,
        avatarCorner: 0.2,
        avatarSize: 40,
        avatarHeaderSize: 32,
        avatarWeight: FontWeight.w600,
        avatars: [
          for (final h in _precyzjaHues)
            dark
                ? (background: _oklch(0.33, 0.07, h), foreground: _oklch(0.9, 0.08, h))
                : (background: _oklch(0.92, 0.045, h), foreground: _oklch(0.36, 0.12, h)),
        ],
        rowHeight: 68,
        rowPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        rowGap: 12,
        unreadTime: _c(dark ? 0xFFA9A7FF : 0xFF3532C8),
        routeBackground: null,
        routeBorder: _c(dark ? 0xFF3B4250 : 0xFFB9BFCB),
        routeRadius: 4,
        routeBox: 22,
        routeIcon: 14,
        separatorLine: true,
        separatorBackground: _c(dark ? 0xFF0B0C10 : 0xFFEEF0F4),
        separatorShadow: _none,
        mono: _t(_plexMono, 12, FontWeight.w400, height: 16)
            .copyWith(fontFeatures: _tabular),
        code: _t(_plexMono, 22, FontWeight.w600, height: 28, letterSpacing: 0.08)
            .copyWith(fontFeatures: _tabular),
        overline: _t(_plexMono, 10.5, FontWeight.w500,
            height: 14, letterSpacing: 0.08),
        overlineUppercase: true,
        separator: _t(_plexMono, 10, FontWeight.w500,
            height: 14, letterSpacing: 0.08),
        caption: _t(_plexMono, 11, FontWeight.w400, height: 16)
            .copyWith(fontFeatures: _tabular),
        walls: dark
            ? [
                _wall([0xFF0B0C10]),
                _wall([0xFF1C1531, 0xFF0E0C16, 0xFF25141B], [0, 0.55, 1]),
                _wall([0xFF0B1B28, 0xFF0A0F17, 0xFF0A2125], [0, 0.55, 1]),
                _wall([0xFF0F1E16, 0xFF0B0F0D, 0xFF18210F], [0, 0.55, 1]),
                _wall([0xFF231C12, 0xFF100E0B, 0xFF251A12], [0, 0.55, 1]),
              ]
            : [
                _wall([0xFFEEF0F4]),
                _wall([0xFFECE6F7, 0xFFF4F0F6, 0xFFF8EAE4], [0, 0.55, 1]),
                _wall([0xFFE1ECF6, 0xFFEEF3F7, 0xFFE2F2F1], [0, 0.55, 1]),
                _wall([0xFFE4EFE6, 0xFFF0F3EE, 0xFFEDF1E0], [0, 0.55, 1]),
                _wall([0xFFF4ECDD, 0xFFF6F2EA, 0xFFF6E7D9], [0, 0.55, 1]),
              ],
        motion: ruch,
      );
    case AppStyle.cieplo:
      return ChattTokens(
        style: style,
        background: _c(dark ? 0xFF161514 : 0xFFF7F1E8),
        surface1: _c(dark ? 0xFF1F1D1C : 0xFFFFFCF7),
        surface2: _c(dark ? 0xFF2A2725 : 0xFFF1E7DA),
        surface3: _c(dark ? 0xFF35322F : 0xFFE6D8C5),
        outline: _c(dark ? 0xFF3A3633 : 0xFFE0D1BD),
        outlineStrong: _c(dark ? 0xFF3A3633 : 0xFFE0D1BD),
        textMuted: _c(dark ? 0xFFB8B0A8 : 0xFF6B5949),
        accentText: _c(dark ? 0xFFF09A76 : 0xFFA84A2B),
        bubbleMine: _c(dark ? 0xFFF09A76 : 0xFFA84A2B),
        onBubbleMine: _c(dark ? 0xFF3A1306 : 0xFFFFFFFF),
        bubbleMineMeta: _c(dark ? 0xFF3A1306 : 0xFFFFFFFF),
        bubbleTheirs: _c(dark ? 0xFF1F1D1C : 0xFFFFFCF7),
        onBubbleTheirs: _c(dark ? 0xFFF2EEE9 : 0xFF2B211A),
        bubbleTheirsMeta: _c(dark ? 0xFFB8B0A8 : 0xFF6B5949),
        bubbleTheirsBorder: null,
        bubbleRadius: 22,
        bubbleTail: 6,
        bubblePadding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        bubbleMaxFraction: 0.80,
        gapBetweenSenders: 6,
        bubbleShadow: dark
            ? _shadow([(1, 2, 0, 0x4D000000), (2, 8, 0, 0x33000000)])
            : _shadow([(1, 2, 0, 0x144A2C18), (2, 8, 0, 0x0F4A2C18)]),
        shadow1: dark
            ? _shadow([(1, 2, 0, 0x4D000000), (2, 8, 0, 0x33000000)])
            : _shadow([(1, 2, 0, 0x144A2C18), (2, 8, 0, 0x0F4A2C18)]),
        shadow2: dark
            ? _shadow([(2, 6, 0, 0x59000000), (10, 28, 0, 0x4D000000)])
            : _shadow([(2, 6, 0, 0x1A4A2C18), (10, 28, 0, 0x1F4A2C18)]),
        shadow3: dark
            ? _shadow([(18, 50, 0, 0x99000000)])
            : _shadow([(18, 50, 0, 0x42341E10)]),
        presence: _c(dark ? 0xFF5CC97E : 0xFF2E9E52),
        presenceOff: null,
        presenceDot: 18,
        presenceDotBorder: 3,
        verified: _c(dark ? 0xFF7AD596 : 0xFF25723C),
        verifiedContainer: _c(dark ? 0xFF2A2725 : 0xFFD7EDDA),
        onVerifiedContainer: _c(dark ? 0xFFF2EEE9 : 0xFF14502A),
        verifiedBorder: dark ? _c(0xFF7AD596) : null,
        warning: _c(dark ? 0xFFE9C463 : 0xFF8A6400),
        warningContainer: _c(dark ? 0xFF2A2725 : 0xFFFAE8B0),
        onWarningContainer: _c(dark ? 0xFFF2EEE9 : 0xFF553D00),
        warningBorder: dark ? _c(0xFFE9C463) : null,
        danger: _c(dark ? 0xFFFF97A6 : 0xFFB4233C),
        dangerContainer: _c(dark ? 0xFF2A2725 : 0xFFFADADF),
        onDangerContainer: _c(dark ? 0xFFF2EEE9 : 0xFF6B0E20),
        dangerBorder: _c(dark ? 0xFFFF97A6 : 0xFFB4233C),
        dangerBorderWidth: 2,
        securityAsDanger: false,
        toast: _c(dark ? 0xFFF2EEE9 : 0xFF2B211A),
        onToast: _c(dark ? 0xFF1F1D1C : 0xFFFBF4EA),
        searchHit: _c(0xFFF2D27A),
        onSearchHit: _c(0xFF2B211A),
        searchHitCurrent: _c(dark ? 0xFFE9C463 : 0xFF8A6400),
        radiusCard: 24,
        radiusSheet: 28,
        radiusField: 16,
        radiusButton: 24,
        radiusBadge: 12,
        radiusWarning: 16,
        radiusRow: 20,
        avatarCircle: false,
        avatarCorner: 0.36,
        avatarSize: 52,
        avatarHeaderSize: 44,
        avatarWeight: FontWeight.w900,
        avatars: [
          for (final (b, f) in dark
              ? const [
                  (0xFF6A3020, 0xFFFFD9C8),
                  (0xFF464D22, 0xFFE4EBBE),
                  (0xFF21504A, 0xFFC8EFE9),
                  (0xFF5C4710, 0xFFFBE6A6),
                  (0xFF5A2A3F, 0xFFF8D4E3),
                ]
              : const [
                  (0xFFF3CDB9, 0xFF74290F),
                  (0xFFDCE3B6, 0xFF414A16),
                  (0xFFC5E2DD, 0xFF1B534D),
                  (0xFFF1DC9C, 0xFF644800),
                  (0xFFEBCFDA, 0xFF672843),
                ])
            (background: Color(b), foreground: Color(f)),
        ],
        rowHeight: 80,
        rowPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        rowGap: 14,
        unreadTime: _c(dark ? 0xFFB8B0A8 : 0xFF6B5949),
        routeBackground: null,
        routeBorder: null,
        routeRadius: 0,
        routeBox: 22,
        routeIcon: 17,
        separatorLine: false,
        separatorBackground: _c(dark ? 0xFF2A2725 : 0xFFF1E7DA),
        separatorShadow: _none,
        mono: _tr(_splineMono, 13, FontWeight.w500, 1.3)
            .copyWith(fontFeatures: _tabular),
        code: _tr(_splineMono, 28, FontWeight.w700, 1.2, letterSpacing: 0.04)
            .copyWith(fontFeatures: _tabular),
        overline: _tr(_nunito, 16, FontWeight.w800, 1.3),
        overlineUppercase: false,
        separator: _tr(_nunito, 13, FontWeight.w700, 1.3),
        caption: _tr(_nunito, 13, FontWeight.w700, 1.3)
            .copyWith(fontFeatures: _tabular),
        walls: dark
            ? [
                _wall([0xFF161514]),
                _wall([0xFF221A1D, 0xFF1F1922, 0xFF1A1A23], [0, 0.55, 1]),
                _wall([0xFF141C1D, 0xFF141B21]),
                _wall([0xFF161C18, 0xFF141A16]),
                _wall([0xFF1F1D1B, 0xFF24211E]),
              ]
            : [
                _wall([0xFFF7F1E8]),
                _wall([0xFFF6E1D2, 0xFFF0D3D0, 0xFFE4D3E2], [0, 0.55, 1]),
                _wall([0xFFE4EFEC, 0xFFD3E4E8]),
                _wall([0xFFEBEDDA, 0xFFD9E2C8]),
                _wall([0xFFF6EDDC, 0xFFEBDAC0]),
              ],
        motion: ruch,
      );
  }
}

/// Główne kolory wariantu: tekst, akcent i jego kontener, błąd, zasłona.
typedef _Core = ({
  Color text,
  Color text2,
  Color accent,
  Color onAccent,
  Color accentContainer,
  Color onAccentContainer,
  Color focus,
  Color scrim,
  Color onError,
});

_Core _core(AppStyle style, bool dark) => switch ((style, dark)) {
      (AppStyle.cisza, false) => (
          text: _c(0xFF162120),
          text2: _c(0xFF566462),
          accent: _c(0xFF0F6A73),
          onAccent: _c(0xFFFFFFFF),
          accentContainer: _c(0xFFD3EBEC),
          onAccentContainer: _c(0xFF0A3B40),
          focus: _c(0xFF0F6A73),
          scrim: _c(0x5C0E1817),
          onError: _c(0xFFFFFFFF),
        ),
      (AppStyle.cisza, true) => (
          text: _c(0xFFE5ECEB),
          text2: _c(0xFFA1AEAC),
          accent: _c(0xFF7CCDD5),
          onAccent: _c(0xFF00363B),
          accentContainer: _c(0xFF1D4549),
          onAccentContainer: _c(0xFFC6EEF0),
          focus: _c(0xFF7CCDD5),
          scrim: _c(0x8C000000),
          onError: _c(0xFF4A1D18),
        ),
      (AppStyle.precyzja, false) => (
          text: _c(0xFF0D0F15),
          text2: _c(0xFF454B5A),
          accent: _c(0xFF4744E6),
          onAccent: _c(0xFFFFFFFF),
          accentContainer: _c(0xFFE9E9FF),
          onAccentContainer: _c(0xFF2A27A8),
          focus: _c(0xFF4744E6),
          scrim: _c(0x6B0D0F15),
          onError: _c(0xFFFFFFFF),
        ),
      (AppStyle.precyzja, true) => (
          text: _c(0xFFE9EBF1),
          text2: _c(0xFFA6ACBA),
          accent: _c(0xFF5B58F6),
          onAccent: _c(0xFFFFFFFF),
          accentContainer: _c(0xFF1E1F4A),
          onAccentContainer: _c(0xFFC9C8FF),
          focus: _c(0xFFA9A7FF),
          scrim: _c(0xAD030407),
          onError: _c(0xFF0B0C10),
        ),
      (AppStyle.cieplo, false) => (
          text: _c(0xFF2B211A),
          text2: _c(0xFF6B5949),
          accent: _c(0xFFA84A2B),
          onAccent: _c(0xFFFFFFFF),
          accentContainer: _c(0xFFF7DCCD),
          onAccentContainer: _c(0xFF5A2414),
          focus: _c(0xFF2B211A),
          scrim: _c(0x612B1C12),
          onError: _c(0xFFFFFFFF),
        ),
      (AppStyle.cieplo, true) => (
          text: _c(0xFFF2EEE9),
          text2: _c(0xFFB8B0A8),
          accent: _c(0xFFF09A76),
          onAccent: _c(0xFF3A1306),
          accentContainer: _c(0xFF2A2725),
          onAccentContainer: _c(0xFFF09A76),
          focus: _c(0xFFF2EEE9),
          scrim: _c(0x8C000000),
          onError: _c(0xFF161514),
        ),
    };

/// Typografia wariantu jako [TextTheme] Materiala.
TextTheme _textTheme(AppStyle style, Color text) {
  final t = switch (style) {
    AppStyle.cisza => TextTheme(
        displaySmall: _t(_figtree, 40, FontWeight.w700, height: 46, letterSpacing: -0.02),
        headlineSmall: _t(_figtree, 28, FontWeight.w700, height: 34, letterSpacing: -0.015),
        titleLarge: _t(_figtree, 22, FontWeight.w700, height: 28),
        titleMedium: _t(_figtree, 17, FontWeight.w700, height: 23),
        titleSmall: _t(_figtree, 16, FontWeight.w600, height: 22),
        bodyLarge: _t(_figtree, 15.5, FontWeight.w400, height: 22),
        bodyMedium: _t(_figtree, 14, FontWeight.w400, height: 20),
        bodySmall: _t(_figtree, 12.5, FontWeight.w500, height: 16),
        labelLarge: _t(_figtree, 14.5, FontWeight.w600, height: 20),
        labelMedium: _t(_figtree, 13, FontWeight.w600, height: 18),
        labelSmall: _t(_figtree, 12, FontWeight.w600, height: 16),
      ),
    AppStyle.precyzja => TextTheme(
        displaySmall: _t(_plexSans, 32, FontWeight.w700, height: 38, letterSpacing: -0.01),
        headlineSmall: _t(_plexSans, 24, FontWeight.w700, height: 29, letterSpacing: -0.01),
        titleLarge: _t(_plexSans, 18, FontWeight.w700, height: 22, letterSpacing: -0.01),
        titleMedium: _t(_plexSans, 15, FontWeight.w600, height: 20),
        titleSmall: _t(_plexSans, 14, FontWeight.w600, height: 18),
        bodyLarge: _t(_plexSans, 14, FontWeight.w400, height: 20),
        bodyMedium: _t(_plexSans, 13, FontWeight.w400, height: 19),
        bodySmall: _t(_plexSans, 12, FontWeight.w400, height: 16),
        labelLarge: _t(_plexSans, 13, FontWeight.w600, height: 18),
        labelMedium: _t(_plexSans, 12, FontWeight.w500, height: 16),
        labelSmall: _t(_plexSans, 11, FontWeight.w500, height: 14),
      ),
    AppStyle.cieplo => TextTheme(
        displaySmall: _tr(_nunito, 32, FontWeight.w900, 1.1, letterSpacing: -0.02),
        headlineSmall: _tr(_nunito, 24, FontWeight.w900, 1.2),
        titleLarge: _tr(_nunito, 21, FontWeight.w900, 1.25),
        titleMedium: _tr(_nunito, 18, FontWeight.w900, 1.2),
        titleSmall: _tr(_nunito, 17, FontWeight.w800, 1.3),
        bodyLarge: _tr(_nunito, 17, FontWeight.w500, 1.4),
        bodyMedium: _tr(_nunito, 15, FontWeight.w600, 1.45),
        bodySmall: _tr(_nunito, 13, FontWeight.w700, 1.3),
        labelLarge: _tr(_nunito, 15, FontWeight.w800, 1.2),
        labelMedium: _tr(_nunito, 13, FontWeight.w800, 1.3),
        labelSmall: _tr(_nunito, 12, FontWeight.w700, 1.3),
      ),
  };
  return t.apply(bodyColor: text, displayColor: text);
}

/// Krój pisma stylu. Także poza drzewem widżetów: awatary skrótów rozmów
/// rysuje ui/share_shortcuts.dart.
String fontFamilyOf(AppStyle style) => switch (style) {
      AppStyle.cisza => _figtree,
      AppStyle.precyzja => _plexSans,
      AppStyle.cieplo => _nunito,
    };

/// Gotowe motywy. Ten sam wariant to ten sam obiekt, więc przebudowa
/// aplikacji po zapisie innego ustawienia nie zaczyna przejścia motywu
/// między dwoma równymi motywami.
final _motywy =
    <(AppStyle, Brightness, bool, bool, TargetPlatform), ThemeData>{};

/// Motyw Fluttera dla stylu i jasności. [gradient]: pod aplikacją leży tło
/// z gradientem, więc ekrany i paski są przezroczyste. [reduceMotion]:
/// „ogranicz animacje” w systemie.
ThemeData chattTheme(AppStyle style, Brightness brightness,
        {bool gradient = false, bool reduceMotion = false}) =>
    // Motyw zapisuje platformę z chwili budowy, więc ona też jest w kluczu.
    _motywy.putIfAbsent(
        (style, brightness, gradient, reduceMotion, defaultTargetPlatform),
        () => _motyw(style, brightness, gradient, reduceMotion));

ThemeData _motyw(AppStyle style, Brightness brightness, bool gradient,
    bool reduceMotion) {
  final dark = brightness == Brightness.dark;
  final k = chattTokens(style, brightness, reduceMotion: reduceMotion);
  final c = _core(style, dark);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: c.accentContainer,
    onPrimaryContainer: c.onAccentContainer,
    secondary: c.accent,
    onSecondary: c.onAccent,
    secondaryContainer: c.accentContainer,
    onSecondaryContainer: c.onAccentContainer,
    tertiary: k.accentText,
    onTertiary: c.onAccent,
    tertiaryContainer: c.accentContainer,
    onTertiaryContainer: c.onAccentContainer,
    error: k.danger,
    onError: c.onError,
    errorContainer: k.dangerContainer,
    onErrorContainer: k.onDangerContainer,
    surface: k.surface1,
    onSurface: c.text,
    onSurfaceVariant: c.text2,
    surfaceDim: k.background,
    surfaceBright: k.surface1,
    surfaceContainerLowest: k.background,
    surfaceContainerLow: k.surface1,
    surfaceContainer: k.surface2,
    surfaceContainerHigh: k.surface2,
    surfaceContainerHighest: k.surface3,
    outline: k.outlineStrong,
    outlineVariant: k.outline,
    shadow: Colors.black,
    scrim: c.scrim,
    inverseSurface: k.toast,
    onInverseSurface: k.onToast,
    inversePrimary: k.accentText,
    surfaceTint: Colors.transparent,
  );
  final text = _textTheme(style, c.text);
  final font = fontFamilyOf(style);
  RoundedRectangleBorder shape(double r, {Color? side}) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r),
        side: side == null ? BorderSide.none : BorderSide(color: side),
      );
  // Precyzja jest płaska: karty i arkusze odcina obrys, nie cień.
  final obrys = style == AppStyle.precyzja ? k.outline : null;
  final przyciskPadding = EdgeInsets.symmetric(
      horizontal: style == AppStyle.precyzja ? 18 : 22);
  final wyglad = (minimumSize: const Size(64, 48), shape: shape(k.radiusButton));
  // Najechanie i fokus zmieniają tylko kolor tła i pierścień, w czasie stylu.
  final najechanie = k.motion.hover;
  final przejscie = ChattPageTransitionsBuilder(k.motion);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: font,
    textTheme: text,
    primaryTextTheme: text,
    scaffoldBackgroundColor: gradient ? Colors.transparent : k.background,
    canvasColor: k.surface1,
    dividerColor: k.outline,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    extensions: [k],
    // Ekrany wjeżdżają po wspólnej osi X na każdej platformie.
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final platforma in TargetPlatform.values) platforma: przejscie,
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: gradient ? Colors.transparent : k.background,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge,
      // Jasność ikon paska systemowego wprost: pasek aplikacji bywa
      // przezroczysty i Flutter policzyłby ją źle.
      systemOverlayStyle:
          dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: k.surface1,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: shape(k.radiusCard, side: obrys),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: k.surface1,
      surfaceTintColor: Colors.transparent,
      barrierColor: c.scrim,
      shape: shape(k.radiusSheet, side: style == AppStyle.precyzja ? k.outlineStrong : null),
      titleTextStyle: text.titleLarge,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: k.surface1,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: c.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(k.radiusSheet)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: k.surface1,
      surfaceTintColor: Colors.transparent,
      shape: shape(style == AppStyle.precyzja ? 8 : 16, side: obrys),
      textStyle: text.bodyLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: wyglad.minimumSize,
        shape: wyglad.shape,
        padding: przyciskPadding,
        textStyle: text.labelLarge,
        animationDuration: najechanie,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: wyglad.minimumSize,
        shape: wyglad.shape,
        padding: przyciskPadding,
        textStyle: text.labelLarge,
        animationDuration: najechanie,
        side: BorderSide(color: k.outlineStrong),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: wyglad.minimumSize,
        shape: wyglad.shape,
        textStyle: text.labelLarge,
        animationDuration: najechanie,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        animationDuration: najechanie,
        shape: style == AppStyle.precyzja ? shape(6) : const CircleBorder(),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accentContainer,
      foregroundColor: c.onAccentContainer,
      elevation: style == AppStyle.precyzja ? 0 : 2,
      highlightElevation: style == AppStyle.precyzja ? 0 : 4,
      shape: shape(k.radiusButton,
          side: style == AppStyle.precyzja ? k.outlineStrong : null),
      extendedTextStyle: text.labelLarge,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: style == AppStyle.precyzja,
      fillColor: k.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(k.radiusField),
        borderSide: BorderSide(color: k.outlineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(k.radiusField),
        borderSide: BorderSide(color: k.outlineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(k.radiusField),
        borderSide: BorderSide(color: c.focus, width: 2),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        animationDuration: najechanie,
        shape: WidgetStatePropertyAll(shape(style == AppStyle.cieplo
            ? 24
            : style == AppStyle.precyzja
                ? 6
                : 13)),
        side: WidgetStatePropertyAll(BorderSide(color: k.outlineStrong)),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? (style == AppStyle.precyzja ? c.accent : c.accentContainer)
                : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? (style == AppStyle.precyzja ? c.onAccent : c.onAccentContainer)
                : c.text2),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? c.accent
              : (style == AppStyle.precyzja ? k.surface3 : k.surface2)),
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? c.onAccent : c.text2),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? c.accent
              : (style == AppStyle.precyzja ? k.outlineStrong : c.text2)),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: shape(switch (style) {
        AppStyle.cisza => 7,
        AppStyle.precyzja => 4,
        AppStyle.cieplo => 6,
      }),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: c.accentContainer,
      selectedColor: c.onAccentContainer,
      iconColor: c.text2,
      shape: shape(k.radiusRow),
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodyMedium?.copyWith(color: c.text2),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: c.accent,
      textColor: c.onAccent,
      textStyle: style == AppStyle.precyzja
          ? k.caption.copyWith(fontWeight: FontWeight.w600)
          : text.labelSmall,
    ),
    dividerTheme: DividerThemeData(color: k.outline, space: 1, thickness: 1),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: k.toast,
        borderRadius: BorderRadius.circular(style == AppStyle.precyzja ? 4 : 8),
      ),
      textStyle: text.bodySmall?.copyWith(color: k.onToast),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: k.surface3,
    ),
    chipTheme: ChipThemeData(
      shape: shape(k.radiusBadge == 999 ? 18 : k.radiusBadge),
      side: BorderSide(color: k.outlineStrong),
    ),
    focusColor: c.focus.withValues(alpha: 0.18),
  );
}
