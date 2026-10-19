import 'package:flutter/material.dart';

import '../styles.dart';

// Wspólne klocki ruchu stylów (issue #54). Czasy, krzywe i przesunięcia
// biorą z [ChattMotion] bieżącego stylu; przy „ogranicz animacje”
// w systemie każde przejście staje się przenikaniem 100 ms.

/// Telefon (dotyk) albo okno na komputerze. Z platformy motywu, więc testy
/// mogą ją podmienić.
bool czyTelefon(BuildContext context) => switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia =>
        true,
      _ => false,
    };

/// Wejście i wyjście w ruchu stylu: przenikanie, skala i przesunięcie
/// w pionie sterowane [animation] (0: ukryte, 1: na miejscu). Ruch może
/// przestrzelić (sprężynka Ciepła), przezroczystość nie. W drodze do zera
/// nie przyjmuje dotyku ani fokusu: znikająca karta nie przyjmie Entera.
class MotionTransition extends StatefulWidget {
  final Animation<double> animation;

  /// Krzywa ruchu wejścia; null: wejście stylu.
  final Curve? curve;

  /// Krzywa przenikania przy wejściu; null: wejście stylu.
  final Curve? fadeCurve;

  /// Skala na starcie.
  final double scale;

  /// Przesunięcie na starcie w dp: dodatnie z dołu, ujemne z góry.
  final double shift;

  /// Przesunięcie na końcu wyjścia; null: jak [shift].
  final double? exitShift;

  final Widget child;

  const MotionTransition({
    super.key,
    required this.animation,
    this.curve,
    this.fadeCurve,
    this.scale = 1,
    this.shift = 0,
    this.exitShift,
    required this.child,
  });

  @override
  State<MotionTransition> createState() => _MotionTransitionState();
}

class _MotionTransitionState extends State<MotionTransition> {
  CurvedAnimation? _ruch;
  CurvedAnimation? _przenikanie;
  (Animation<double>, Curve, Curve, Curve)? _klucz;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _krzywe();
  }

  @override
  void didUpdateWidget(MotionTransition old) {
    super.didUpdateWidget(old);
    _krzywe();
  }

  void _krzywe() {
    final m = ChattMotion.of(context);
    final ruch = widget.curve ?? m.enter;
    final przenikanie = widget.fadeCurve ?? m.enter;
    final klucz = (widget.animation, ruch, przenikanie, m.exit);
    if (klucz == _klucz) return;
    _klucz = klucz;
    _ruch?.dispose();
    _przenikanie?.dispose();
    _ruch = CurvedAnimation(
        parent: widget.animation, curve: ruch, reverseCurve: m.exitReverse);
    _przenikanie = CurvedAnimation(
        parent: widget.animation,
        curve: przenikanie,
        reverseCurve: m.exitReverse);
  }

  @override
  void dispose() {
    _ruch?.dispose();
    _przenikanie?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      child: widget.child,
      builder: (context, child) {
        final znika = widget.animation.status == AnimationStatus.reverse;
        final ruch = _ruch!.value;
        final przesuniecie =
            (znika ? (widget.exitShift ?? widget.shift) : widget.shift) *
                (1 - ruch);
        final skala = widget.scale + (1 - widget.scale) * ruch;
        return IgnorePointer(
          ignoring: znika,
          child: ExcludeFocus(
            excluding: znika,
            child: Opacity(
              opacity: _przenikanie!.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, przesuniecie),
                child: Transform.scale(scale: skala, child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Karta zgody pojawia się i znika w ruchu stylu: na telefonie po swojemu
/// (Cisza z dołu), w oknie ze skalą, w Cieple z góry ze sprężynką. Kolejna
/// karta w miejsce poprzedniej przechodzi tak samo, więc dzieci muszą mieć
/// klucze. null: brak karty.
class CardSwitcher extends StatelessWidget {
  final Widget? child;

  const CardSwitcher({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final m = ChattMotion.of(context);
    final telefon = czyTelefon(context);
    return AnimatedSwitcher(
      duration: m.cardIn,
      reverseDuration: m.cardOut,
      // Krzywe nakłada MotionTransition: sprężynka nie może trafić
      // w przezroczystość.
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => MotionTransition(
        animation: animation,
        curve: m.cardCurve,
        scale: telefon ? m.cardScalePhone : m.cardScaleWindow,
        shift: telefon ? m.cardShiftPhone : m.cardShiftWindow,
        child: child,
      ),
      child: child ?? const SizedBox.shrink(key: ValueKey('bez karty')),
    );
  }
}

/// Okno w ruchu stylu: karta zgody albo, przy [panel], panel na środku
/// okna. Zasłona narasta w czasie stylu, nawet gdy okno wjeżdża dłużej.
class ChattDialogRoute<T> extends DialogRoute<T> {
  final ChattMotion motion;
  final bool telefon;
  final bool panel;

  ChattDialogRoute({
    required super.context,
    required super.builder,
    required this.motion,
    required this.telefon,
    this.panel = false,
    super.themes,
    super.barrierColor,
    super.barrierDismissible,
    super.settings,
  }) : super(
          animationStyle: AnimationStyle(
            duration: panel ? motion.panelIn : motion.cardIn,
            reverseDuration: panel ? motion.panelOut : motion.cardOut,
          ),
        );

  @override
  Duration get transitionDuration => panel ? motion.panelIn : motion.cardIn;

  @override
  Duration get reverseTransitionDuration =>
      panel ? motion.panelOut : motion.cardOut;

  @override
  Curve get barrierCurve => motion.scrimWithin(transitionDuration);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      MotionTransition(
        animation: animation,
        // Sprężynka tylko przy kartach zgody, panel wjeżdża krzywą stylu.
        curve: panel ? motion.enter : motion.cardCurve,
        scale: panel
            ? motion.panelScale
            : telefon
                ? motion.cardScalePhone
                : motion.cardScaleWindow,
        shift: panel
            ? 0
            : telefon
                ? motion.cardShiftPhone
                : motion.cardShiftWindow,
        child: child,
      );
}

/// [showDialog] w ruchu stylu, z zasłoną stylu.
Future<T?> showChattDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  bool panel = false,
  RouteSettings? routeSettings,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push(ChattDialogRoute<T>(
    context: context,
    builder: builder,
    motion: ChattMotion.of(context),
    telefon: czyTelefon(context),
    panel: panel,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierColor: DialogTheme.of(context).barrierColor ??
        Theme.of(context).colorScheme.scrim,
    barrierDismissible: barrierDismissible,
    settings: routeSettings,
  ));
}

/// Arkusz od dołu w czasie i krzywej stylu. Przy „ogranicz animacje” stoi
/// od razu na miejscu i się pojawia.
class _ChattSheetRoute<T> extends ModalBottomSheetRoute<T> {
  final ChattMotion motion;

  _ChattSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    required this.motion,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.modalBarrierColor,
    super.showDragHandle,
    super.useSafeArea,
    super.settings,
  }) : super(
          sheetAnimationStyle: AnimationStyle(
            duration: motion.panelIn,
            reverseDuration: motion.panelOut,
            curve: motion.isReduced ? const Threshold(0) : motion.enter,
            reverseCurve:
                motion.isReduced ? const Threshold(0) : motion.exitReverse,
          ),
        );

  @override
  Curve get barrierCurve => motion.scrimWithin(motion.panelIn);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final arkusz =
        super.buildTransitions(context, animation, secondaryAnimation, child);
    return motion.isReduced
        ? FadeTransition(opacity: animation, child: arkusz)
        : arkusz;
  }
}

/// [showModalBottomSheet] w czasie, krzywej i zasłonie stylu.
Future<T?> showChattSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool? showDragHandle,
  bool useSafeArea = false,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final teksty = MaterialLocalizations.of(context);
  return navigator.push(_ChattSheetRoute<T>(
    builder: builder,
    isScrollControlled: isScrollControlled,
    motion: ChattMotion.of(context),
    capturedThemes:
        InheritedTheme.capture(from: context, to: navigator.context),
    barrierLabel: teksty.scrimLabel,
    barrierOnTapHint: teksty.scrimOnTapHint(teksty.bottomSheetLabel),
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    settings: routeSettings,
  ));
}

/// Pasek postępu, który między próbkami przechodzi w ruchu stylu: płynnie
/// (Cisza), liniowo (Ciepło) albo wprost za próbkami (Precyzja). Bez
/// [value] kręci się jak zwykły pasek bez końca.
class SmoothProgress extends StatelessWidget {
  final double? value;
  final double? minHeight;
  final Color? color;
  final Color? backgroundColor;
  final BorderRadiusGeometry? borderRadius;
  final String? semanticsLabel;
  final String? semanticsValue;

  const SmoothProgress({
    super.key,
    required this.value,
    this.minHeight,
    this.color,
    this.backgroundColor,
    this.borderRadius,
    this.semanticsLabel,
    this.semanticsValue,
  });

  @override
  Widget build(BuildContext context) {
    final m = ChattMotion.of(context);
    Widget pasek(double? wartosc) => LinearProgressIndicator(
          value: wartosc,
          minHeight: minHeight,
          color: color,
          backgroundColor: backgroundColor,
          borderRadius: borderRadius,
          semanticsLabel: semanticsLabel,
          semanticsValue: semanticsValue,
        );
    final cel = value;
    if (cel == null || m.progress == Duration.zero) return pasek(cel);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: cel.clamp(0.0, 1.0)),
      duration: m.progress,
      curve: m.progressCurve,
      builder: (context, wartosc, _) => pasek(wartosc),
    );
  }
}

/// Wejście raz, przy pojawieniu się: nowy dymek wjeżdża w górę o [shift]
/// i się pojawia. Bez [animate] (wiadomości już widziane, powrót po
/// przewinięciu) stoi od razu na miejscu.
class EnterOnce extends StatefulWidget {
  final bool animate;
  final Duration duration;
  final Curve curve;
  final double shift;
  final Widget child;

  const EnterOnce({
    super.key,
    required this.animate,
    required this.duration,
    required this.curve,
    required this.shift,
    required this.child,
  });

  @override
  State<EnterOnce> createState() => _EnterOnceState();
}

class _EnterOnceState extends State<EnterOnce>
    with SingleTickerProviderStateMixin {
  // Decyzja zapada raz: drzewo pod spodem ma ten sam kształt przez całe
  // życie wiersza, więc nic nie traci stanu po skończonym wejściu.
  late final bool _animuj = widget.animate;
  AnimationController? _wejscie;

  @override
  void initState() {
    super.initState();
    if (_animuj) {
      _wejscie = AnimationController(vsync: this, duration: widget.duration)
        ..forward();
    }
  }

  @override
  void dispose() {
    _wejscie?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wejscie = _wejscie;
    if (wejscie == null) return widget.child;
    return MotionTransition(
      animation: wejscie,
      curve: widget.curve,
      fadeCurve: widget.curve,
      shift: widget.shift,
      child: widget.child,
    );
  }
}
