import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Tło aplikacji do wyboru w ustawieniach.
///
/// Zestawy, a nie dowolny kolor z palety: dymki i karty biorą kolory
/// z motywu Material, więc przy swobodnym wyborze łatwo trafić na parę
/// nie do czytania. Każdy zestaw ma osobne kolory dla motywu jasnego
/// i ciemnego, bo ten sam gradient nie działa w obu.
///
/// Kolory są celowo przygaszone. Tło ma być tłem, a nie konkurencją dla
/// treści: na nim leżą karty i dymki, które muszą zostać czytelne.
class ChattBackground {
  final String id;

  /// Puste znaczy „bez tła": zostaje zwykły kolor powierzchni z motywu.
  final List<Color> light;
  final List<Color> dark;

  const ChattBackground({
    required this.id,
    this.light = const [],
    this.dark = const [],
  });

  bool get plain => light.isEmpty;

  List<Color> colorsFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

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
  ChattBackground(id: 'brak'),
  ChattBackground(
    id: 'zmierzch',
    light: [Color(0xFFF3E8FF), Color(0xFFFFE4EC)],
    dark: [Color(0xFF241B33), Color(0xFF33202B)],
  ),
  ChattBackground(
    id: 'ocean',
    light: [Color(0xFFE3F0FF), Color(0xFFDFF6F3)],
    dark: [Color(0xFF16233A), Color(0xFF14302F)],
  ),
  ChattBackground(
    id: 'las',
    light: [Color(0xFFE8F5E4), Color(0xFFE6F2EC)],
    dark: [Color(0xFF19281C), Color(0xFF152A25)],
  ),
  ChattBackground(
    id: 'piasek',
    light: [Color(0xFFFBF0E0), Color(0xFFF6E7E1)],
    dark: [Color(0xFF2C2419), Color(0xFF2E211C)],
  ),
];

ChattBackground backgroundAt(int index) => chattBackgrounds[
    index < 0 || index >= chattBackgrounds.length ? 0 : index];

/// Gradient pod całą aplikacją. Karty i dymki są nieprzezroczyste, więc
/// tło zmienia wrażenie, a nie czytelność.
class AppBackground extends StatelessWidget {
  final ChattBackground background;
  final Widget child;

  const AppBackground({
    super.key,
    required this.background,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (background.plain) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: background.colorsFor(Theme.of(context).brightness),
        ),
      ),
      child: child,
    );
  }
}
