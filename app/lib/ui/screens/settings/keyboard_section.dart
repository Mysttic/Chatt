import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/providers.dart';
import '../../l10n_context.dart';
import '../../widgets/motion.dart';
import '../typing_history_screen.dart';
import 'keyboard_addon_card.dart';
import 'settings_widgets.dart';

/// Kategoria Klawiatura z PC: karta dodatku, a pod nią wejście do historii
/// pisania, gdy dodatek jest wyłączony, a zapisane sesje zostały. Włączony
/// dodatek ma ten przycisk w swojej karcie.
class KeyboardSection extends ConsumerWidget {
  /// Liczba sesji w historii pisania, na żywo z ekranu Ustawień.
  final int typingSessions;

  const KeyboardSection({super.key, required this.typingSessions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.read(appServicesProvider);
    return SettingsPage(
      children: [
        const KeyboardAddonCard(),
        ValueListenableBuilder<bool>(
          valueListenable: services.keyboardAddon,
          builder: (context, wlaczony, _) {
            if (wlaczony || typingSessions == 0) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      ChattPageRoute(
                        builder: (_) => const TypingHistoryScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.manage_history_outlined),
                    label: Text(context.l10n.typingHistory),
                  ),
                  SettingsHelp(
                    context.l10n.typingHistoryEntryHelp(typingSessions),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
