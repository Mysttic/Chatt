import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/providers.dart';
import '../../l10n_context.dart';
import '../../widgets/motion.dart';
import '../../widgets/toasts.dart';
import 'settings_widgets.dart';

/// Kategoria Prywatność: gdzie leży klucz bazy, jak długo zostają
/// wiadomości, podglądy stron (druga rzecz po aktualizacjach, która łączy
/// się poza sieć lokalną) i na końcu wyczyszczenie historii.
class PrivacySection extends ConsumerWidget {
  const PrivacySection({super.key});

  /// Wyczyszczenie historii jest nieodwracalne, więc pytamy wprost. Razem
  /// z rozmowami znika historia pisania (patrz [AppServices.clearHistory]).
  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    final zgoda = await showChattDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.clearHistoryTitle),
        content: Text(context.l10n.clearHistoryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (zgoda != true || !context.mounted) return;

    final teksty = context.l10n;
    final services = ref.read(appServicesProvider);
    // Liczba sesji przed czyszczeniem: komunikat ma mówić o wszystkim, co
    // zniknęło, także gdy wiadomości nie było żadnych.
    final sesje = await services.db.watchTypingSessionCount().first;
    final usuniete = await services.clearHistory();
    showToast(switch ((usuniete, sesje)) {
      (0, 0) => teksty.nothingToCleanUp,
      (_, 0) => teksty.historyCleared(usuniete),
      _ => teksty.historyClearedWithTyping(usuniete, sesje),
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.read(appServicesProvider);
    final scheme = Theme.of(context).colorScheme;
    final teksty = context.l10n;

    return SettingsPage(
      children: [
        SettingsStatusCard(
          icon: services.keyProtected
              ? Icons.lock_outline
              : Icons.lock_open_outlined,
          bad: !services.keyProtected,
          text: services.keyProtected
              ? teksty.dbKeyProtected
              : teksty.dbKeyUnprotected,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: ref.watch(settingsProvider).value?.retentionDays ?? 0,
          decoration: InputDecoration(
            labelText: teksty.retentionLabel,
            prefixIcon: const Icon(Icons.auto_delete_outlined),
          ),
          items: [
            for (final dni in _retentionChoices)
              DropdownMenuItem(
                value: dni,
                child: Text(
                  dni == 0 ? teksty.retentionNever : teksty.retentionDays(dni),
                ),
              ),
          ],
          onChanged: (wybor) async {
            if (wybor == null) return;
            await services.db.saveRetentionDays(wybor);
            // Ustawienie ma zadziałać od razu, bez czekania na restart.
            await services.applyRetention(wybor);
          },
        ),
        SettingsHelp(teksty.retentionHelp),
        const SizedBox(height: 16),
        const _LinkPreviewsCard(),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _clearHistory(context, ref),
          icon: const Icon(Icons.delete_sweep_outlined),
          label: Text(teksty.clearHistory),
          style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
        ),
      ],
    );
  }
}

/// Przełącznik podglądów stron pod odnośnikami.
///
/// Włączenie wypuszcza aplikację poza sieć lokalną, i to pod adresy, które
/// wybiera nadawca wiadomości. Dlatego pod przełącznikiem stoi wprost
/// napisane, co zobaczy serwer po drugiej stronie i czego podgląd nie robi.
class _LinkPreviewsCard extends ConsumerWidget {
  const _LinkPreviewsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.read(appServicesProvider);
    final ustawienia = ref.watch(settingsProvider).value;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: ustawienia?.linkPreviews ?? false,
              secondary: const Icon(Icons.link),
              title: Text(context.l10n.linkPreviewsLabel),
              subtitle: Text(context.l10n.linkPreviewsHelp),
              isThreeLine: true,
              onChanged: ustawienia == null
                  ? null
                  : (wlaczone) => services.db.saveLinkPreviews(wlaczone),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.linkPreviewsSafety,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Granice wieku wiadomości do wyboru. Zero to „nie kasuj".
const _retentionChoices = [0, 7, 30, 90, 365];
