import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'styles.dart';
import 'widgets/motion.dart';

/// Tło aplikacji do wyboru w ustawieniach.
///
/// Zestawy, a nie dowolny kolor z palety: przy swobodnym wyborze łatwo
/// trafić na parę nie do czytania z kartami i dymkami. Kolory każdego
/// zestawu zależą od stylu i jasności motywu (`ChattTokens.walls`), bo ten
/// sam gradient nie pasuje do wszystkich.
///
/// Kolory są celowo przygaszone. Tło ma być tłem, a nie konkurencją dla
/// treści: na nim leżą karty i dymki, które muszą zostać czytelne.
class ChattBackground {
  final String id;

  /// Miejsce na liście, czyli numer zapisany w bazie i indeks
  /// w `ChattTokens.walls`.
  final int index;

  const ChattBackground({required this.id, required this.index});

  /// „Bez tła": zostaje kolor tła stylu.
  bool get plain => index == 0;

  /// Kolory tego tła w bieżącym stylu i motywie.
  Wall wallIn(BuildContext context) => ChattTokens.of(context).walls[index];

  String label(AppLocalizations l10n) => switch (id) {
        'zmierzch' => l10n.backgroundDusk,
        'ocean' => l10n.backgroundOcean,
        'las' => l10n.backgroundForest,
        'piasek' => l10n.backgroundSand,
        _ => l10n.backgroundNone,
      };
}

/// Kolejność decyduje o numerze zapisanym w bazie, więc nowe zestawy
/// dokłada się **na koniec**: inaczej komuś zmieni się tło po aktualizacji.
const chattBackgrounds = <ChattBackground>[
  ChattBackground(id: 'brak', index: 0),
  ChattBackground(id: 'zmierzch', index: 1),
  ChattBackground(id: 'ocean', index: 2),
  ChattBackground(id: 'las', index: 3),
  ChattBackground(id: 'piasek', index: 4),
];

/// Wypełnienie tła: kolor albo gradient pod kątem 165°, jak w szablonie.
BoxDecoration wallDecoration(Wall wall, {BorderRadius? borderRadius}) =>
    wall.colors.length == 1
        ? BoxDecoration(color: wall.colors.single, borderRadius: borderRadius)
        : BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: const Alignment(-0.26, -0.97),
              end: const Alignment(0.26, 0.97),
              colors: wall.colors,
              stops: wall.stops,
            ),
          );

ChattBackground backgroundAt(int index) => chattBackgrounds[
    index < 0 || index >= chattBackgrounds.length ? 0 : index];

/// Gradient pod całą aplikacją. Karty i dymki są nieprzezroczyste, więc
/// tło zmienia wrażenie, a nie czytelność.
///
/// Nowe tło przenika w czasie zmiany motywu stylu. Drzewo ma ten sam kształt
/// przy każdym tle, także przy „Bez tła” (kolor tła stylu): aplikacja pod
/// spodem zachowuje stan. Ekrany nad nim są przezroczyste przy każdym tle
/// (app.dart), więc to, co widać, to dokładnie to przenikanie.
class AppBackground extends StatefulWidget {
  final ChattBackground background;
  final Widget child;

  const AppBackground({
    super.key,
    required this.background,
    required this.child,
  });

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _zmiana =
      motionController(vsync: this, value: 1);
  Curve _krzywa = Curves.linear;

  /// Tło widoczne w chwili zmiany, od niego przenika nowe.
  Wall? _od;

  /// Tło na ekranie, gdy celem jest [cel].
  Wall _widac(Wall cel) {
    final od = _od;
    if (od == null || _zmiana.isCompleted) return cel;
    return lerpWall(od, cel, _krzywa.transform(_zmiana.value));
  }

  @override
  void didUpdateWidget(AppBackground old) {
    super.didUpdateWidget(old);
    if (old.background.index == widget.background.index) return;
    // Kolejna zmiana w trakcie przenikania rusza z tego, co widać.
    _od = _widac(old.background.wallIn(context));
    final ruch = ChattMotion.of(context);
    _krzywa = ruch.enter;
    _zmiana.duration = ruch.themeChange;
    _zmiana.forward(from: 0);
  }

  @override
  void dispose() {
    _zmiana.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Kolory celu idą za motywem, który przy zmianie stylu i jasności
    // przenika sam.
    final cel = widget.background.wallIn(context);
    return AnimatedBuilder(
      animation: _zmiana,
      child: widget.child,
      builder: (context, child) =>
          DecoratedBox(decoration: wallDecoration(_widac(cel)), child: child),
    );
  }
}
