import 'package:flutter/material.dart';

import '../../core/updates.dart';
import '../l10n_context.dart';

/// Nowe wydanie w ustawieniach: numer, opis od autora i to, co da się z nim
/// zrobić.
///
/// O tym, czy da się zainstalować, decyduje wywołujący ([canInstall]), a nie
/// sam widget. Odpowiedź zależy od platformy i od tego, czy aplikacja chodzi
/// z instalatora, czy z rozpakowanego zipa, i chcemy móc obejrzeć obie drogi
/// w teście.
class UpdateCard extends StatelessWidget {
  final Release release;

  /// Czy tę instalację da się podmienić z poziomu aplikacji.
  final bool canInstall;

  /// Postęp pobierania w procentach. `null` znaczy „nie pobieram".
  final int? progress;

  /// Komunikat błędu pod przyciskiem, gdy coś nie wyszło.
  final String? error;

  final VoidCallback onInstall;

  const UpdateCard({
    super.key,
    required this.release,
    required this.canInstall,
    required this.progress,
    required this.error,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final daSie = canInstall && release.assetUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.system_update, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.updateAvailable(release.version),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        if (release.notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            release.notes,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
        const SizedBox(height: 12),
        if (progress != null) ...[
          LinearProgressIndicator(value: progress! / 100),
          const SizedBox(height: 6),
          Text(context.l10n.updateDownloading(progress!)),
        ] else if (daSie)
          FilledButton.icon(
            onPressed: onInstall,
            icon: const Icon(Icons.download),
            label: Text(context.l10n.updateDownload),
          )
        else ...[
          Text(
            release.assetUrl == null
                ? context.l10n.updateNoAsset
                : context.l10n.updatePortableHint,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 4),
          SelectableText(release.pageUrl),
        ],
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: TextStyle(color: scheme.error)),
        ],
      ],
    );
  }
}
