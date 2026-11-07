import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/providers.dart';
import '../../l10n_context.dart';
import '../../widgets/export_dialog.dart';
import '../../widgets/motion.dart';
import '../app_log_screen.dart';
import 'settings_widgets.dart';

/// Kategoria Dane i diagnostyka: wszystko, co aplikacja wie, da się stąd
/// wynieść do analizy poza nią (eksport) i przejrzeć (dziennik).
class DataSection extends ConsumerWidget {
  const DataSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.read(appServicesProvider);
    return SettingsPage(
      children: [
        OutlinedButton.icon(
          onPressed: () => showExportDialog(context, services: services),
          icon: const Icon(Icons.archive_outlined),
          label: Text(context.l10n.exportData),
        ),
        SettingsHelp(context.l10n.exportDataHelp),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () =>
              Navigator.of(context)
                  .push(ChattPageRoute(builder: (_) => const AppLogScreen())),
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text(context.l10n.appLog),
        ),
        SettingsHelp(context.l10n.appLogHelp),
      ],
    );
  }
}
