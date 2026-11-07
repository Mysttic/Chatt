import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/languages.dart';
import '../../../data/db.dart';
import '../../../services/providers.dart';
import '../../backgrounds.dart';
import '../../l10n_context.dart';
import '../../styles.dart';
import 'settings_widgets.dart';

/// Kategoria Wygląd: styl, motyw, tło i język. Każda zmiana działa od razu.
/// Styl zmienia wyłącznie wygląd: te same ekrany i informacje.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.read(appServicesProvider);
    final ustawienia = ref.watch(settingsProvider).value;
    final etykieta = Theme.of(context).textTheme.labelLarge;

    return SettingsPage(
      children: [
        Text(context.l10n.styleLabel, style: etykieta),
        const SizedBox(height: 8),
        SegmentedButton<AppStyle>(
          showSelectedIcon: false,
          segments: [
            for (final styl in AppStyle.values)
              ButtonSegment(value: styl, label: Text(styl.label(context))),
          ],
          selected: {ustawienia?.style ?? AppStyle.cisza},
          onSelectionChanged: (wybor) => services.db.saveStyle(wybor.first),
        ),
        const SizedBox(height: 16),
        Text(context.l10n.themeLabel, style: etykieta),
        const SizedBox(height: 8),
        // Na wąskim ekranie same napisy, jak przy stylu: z ikoną
        // „Systemowy” łamał się w środku słowa. Szerokie okno mieści ikony.
        LayoutBuilder(
          builder: (context, miejsce) {
            final waskie = miejsce.maxWidth < 480;
            Widget? ikona(IconData dane) => waskie ? null : Icon(dane);
            return SegmentedButton<AppTheme>(
              showSelectedIcon: !waskie,
              style: waskie
                  ? const ButtonStyle(
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 8),
                      ),
                    )
                  : null,
              segments: [
                ButtonSegment(
                  value: AppTheme.system,
                  icon: ikona(Icons.brightness_auto_outlined),
                  label: Text(context.l10n.themeSystem),
                ),
                ButtonSegment(
                  value: AppTheme.light,
                  icon: ikona(Icons.light_mode_outlined),
                  label: Text(context.l10n.themeLight),
                ),
                ButtonSegment(
                  value: AppTheme.dark,
                  icon: ikona(Icons.dark_mode_outlined),
                  label: Text(context.l10n.themeDark),
                ),
              ],
              selected: {ustawienia?.theme ?? AppTheme.system},
              onSelectionChanged: (wybor) => services.db.saveTheme(wybor.first),
            );
          },
        ),
        const SizedBox(height: 16),
        Text(context.l10n.background, style: etykieta),
        const SizedBox(height: 8),
        // Próbki łamią się w kolejne rzędy: na telefonie ostatnia nie znika
        // za krawędzią ekranu.
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final tlo in chattBackgrounds)
              _BackgroundChip(
                background: tlo,
                selected: (ustawienia?.background ?? 0) == tlo.index,
                onTap: () => services.db.saveBackground(tlo.index),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(context.l10n.language, style: etykieta),
        const SizedBox(height: 8),
        // Lista, a nie rzędek przycisków: kolejny język to jedna pozycja
        // więcej, bez przebudowy układu (patrz core/languages.dart).
        DropdownButtonFormField<AppLanguage>(
          initialValue: ustawienia?.language ?? AppLanguage.system,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.translate_outlined),
          ),
          items: [
            for (final jezyk in AppLanguage.values)
              DropdownMenuItem(
                value: jezyk,
                child: Text(jezyk.label(context.l10n)),
              ),
          ],
          onChanged: (wybor) {
            if (wybor != null) services.db.saveLanguage(wybor);
          },
        ),
      ],
    );
  }
}

/// Podgląd jednego tła w bieżącym stylu: prostokąt z gradientem i podpis
/// pod spodem. „Bez tła" pokazuje kolor tła stylu. Zaznaczenie (obrys,
/// znacznik i podpis) przechodzi w czasie przełączników stylu.
class _BackgroundChip extends StatelessWidget {
  final ChattBackground background;
  final bool selected;
  final VoidCallback onTap;

  const _BackgroundChip({
    required this.background,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ruch = ChattMotion.of(context);
    final promien = BorderRadius.circular(12);
    final podpis = theme.textTheme.bodyMedium ?? const TextStyle();

    return InkWell(
      borderRadius: promien,
      hoverDuration: ruch.hover,
      onTap: onTap,
      // Animuje się sam postęp zaznaczenia (0 do 1). Kolory i font są
      // czytane z motywu w każdej klatce: przy zmianie stylu i jasności
      // przechodzą razem z nim.
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: selected ? 1.0 : 0.0),
        duration: ruch.control,
        curve: ruch.enter,
        builder: (context, postep, _) {
          final z = postep.clamp(0.0, 1.0);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: wallDecoration(
                  background.wallIn(context),
                  borderRadius: promien,
                ),
                child: SizedBox(
                  width: 88,
                  height: 60,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: promien,
                      border: Border.all(
                        color: Color.lerp(
                          scheme.outlineVariant,
                          scheme.primary,
                          z,
                        )!,
                        width: 1 + 2 * z,
                      ),
                    ),
                    child: Opacity(
                      opacity: z,
                      child: Icon(Icons.check, color: scheme.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                background.label(context.l10n),
                style: podpis.copyWith(
                  fontSize: 12,
                  color: Color.lerp(scheme.onSurfaceVariant, scheme.primary, z),
                  fontWeight: FontWeight.lerp(
                    podpis.fontWeight,
                    FontWeight.w600,
                    z,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

extension on AppStyle {
  String label(BuildContext context) => switch (this) {
    AppStyle.cisza => context.l10n.styleCisza,
    AppStyle.precyzja => context.l10n.stylePrecyzja,
    AppStyle.cieplo => context.l10n.styleCieplo,
  };
}
