import 'package:flutter/material.dart';

import '../../styles.dart';
import 'settings_summary.dart';

/// Wiersz kategorii na liście Ustawień: kafelek z ikoną, nazwa,
/// streszczenie stanu i opcjonalna trzecia linia z nowością albo kłopotem.
///
/// Wiersz ułożony ręcznie: linia między wierszami zaczyna się na wysokości
/// tekstu (72 px od krawędzi karty, [wciecie]), a paddingi [ListTile]
/// przesuwają tekst przy każdej zmianie gęstości.
class SettingsCategoryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String summary;
  final LiniaKategorii? line;

  /// Wybrany wiersz w dwóch panelach: tło akcentu i zaznaczenie
  /// w semantyce. `null` na liście, z której kategoria otwiera się osobno:
  /// tam nic nie jest wybrane, więc wiersz nie ma stanu zaznaczenia.
  final bool? selected;

  /// Strzałka na końcu: na liście, z której kategoria otwiera się jako
  /// osobny widok. W dwóch panelach kategoria stoi obok, więc strzałki nie
  /// ma.
  final bool chevron;
  final VoidCallback onTap;

  const SettingsCategoryRow({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    this.line,
    this.selected,
    this.chevron = true,
    required this.onTap,
  });

  /// Odległość tekstu od krawędzi karty: padding, kafelek i odstęp.
  static const double wciecie = 16 + 40 + 16;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pismo = theme.textTheme;
    final k = ChattTokens.of(context);
    final ruch = ChattMotion.of(context);
    final wybrany = selected ?? false;
    final naWybranym = wybrany ? scheme.onPrimaryContainer : null;
    final linia = line;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: wybrany ? scheme.primaryContainer : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverDuration: ruch.hover,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: scheme.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: pismo.titleSmall?.copyWith(color: naWybranym),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: pismo.bodyMedium?.copyWith(
                            color: naWybranym ?? scheme.onSurfaceVariant,
                          ),
                        ),
                        if (linia != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            linia.tekst,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: pismo.bodyMedium?.copyWith(
                              color: linia.problem ? k.warning : scheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (chevron) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
