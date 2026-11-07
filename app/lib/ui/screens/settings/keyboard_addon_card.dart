import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/remote_input.dart';
import '../../../services/providers.dart';
import '../../l10n_context.dart';
import '../../widgets/motion.dart';
import '../typing_history_screen.dart';

/// Dodatek „Klawiatura z PC": przełącznik całej funkcji i, po jego włączeniu,
/// przełącznik odbioru oraz historia pisania.
///
/// Wyłączony dodatek to sam przełącznik. Włączony pozwala pisać stąd na
/// innych urządzeniach, a przełącznik „Pozwól pisać na tym urządzeniu" jest
/// osobną zgodą i startuje wyłączony: włączenie dodatku na komputerze,
/// z którego się pisze, nie wpuszcza nikogo na ten komputer. Przełącznik
/// „Zapisuj historię pisania" startuje włączony i działa tylko razem
/// z dodatkiem; przycisk obok otwiera zapisane sesje.
class KeyboardAddonCard extends ConsumerStatefulWidget {
  const KeyboardAddonCard({super.key});

  @override
  ConsumerState<KeyboardAddonCard> createState() => _KeyboardAddonCardState();
}

class _KeyboardAddonCardState extends ConsumerState<KeyboardAddonCard> {
  bool _zajete = false;

  /// Android: stan klawiatury Chatt w systemie. `null` = nie pytano albo
  /// platforma bez klawiatury.
  ({bool enabled, bool selected})? _ime;

  /// Trwa wędrówka po ustawieniach systemu: drugie kliknięcie nie zaczyna
  /// drugiego czekania.
  bool _wUstawieniach = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _odswiezIme());
  }

  /// Pyta system o klawiaturę tylko przy włączonym dodatku i odbiorze: wtedy
  /// i tylko wtedy komponent jest włączony, a kanał wolno wołać.
  Future<void> _odswiezIme() async {
    final services = ref.read(appServicesProvider);
    if (!Platform.isAndroid) return;
    final odbior =
        (await services.db.getSettings())?.remoteInputReceive ?? false;
    if (!services.keyboardAddon.value || !odbior) {
      if (mounted && _ime != null) setState(() => _ime = null);
      return;
    }
    final stan = await RemoteInputChannel.imeState();
    if (mounted) setState(() => _ime = stan);
  }

  /// Ekran klawiatur w ustawieniach systemu. Odpowiedź nie wraca kanałem,
  /// więc czekamy na powrót aplikacji na wierzch, jak przy zgodzie na
  /// Bluetooth, i wtedy pytamy o stan.
  Future<void> _wlaczWSystemie() async {
    if (_wUstawieniach) return;
    setState(() => _wUstawieniach = true);
    var wyszla = false;
    final powrot = Completer<void>();
    final sluchacz = AppLifecycleListener(onStateChange: (state) {
      if (state != AppLifecycleState.resumed) {
        wyszla = true;
      } else if (wyszla && !powrot.isCompleted) {
        powrot.complete();
      }
    });
    try {
      if (await RemoteInputChannel.openImeSettings()) {
        await powrot.future
            .timeout(const Duration(minutes: 10), onTimeout: () {});
      }
    } finally {
      sluchacz.dispose();
      if (mounted) setState(() => _wUstawieniach = false);
    }
    await _odswiezIme();
  }

  Future<void> _wybierz() async {
    await RemoteInputChannel.showImePicker();
    // Wybór kończy się poza aplikacją; stan pytamy po chwili.
    await Future<void>.delayed(const Duration(seconds: 2));
    await _odswiezIme();
  }

  Future<void> _przelacz(Future<bool> Function() krok) async {
    setState(() => _zajete = true);
    try {
      await krok();
    } finally {
      if (mounted) setState(() => _zajete = false);
    }
    await _odswiezIme();
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.read(appServicesProvider);
    final odbior =
        ref.watch(settingsProvider).value?.remoteInputReceive ?? false;
    final scheme = Theme.of(context).colorScheme;
    final przyjmuje = services.remoteInputReceiveSupported;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ListenableBuilder(
          listenable: Listenable.merge(
              [services.keyboardAddon, services.typingHistory]),
          builder: (context, _) {
            final wlaczony = services.keyboardAddon.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: wlaczony,
                  onChanged: _zajete
                      ? null
                      : (value) =>
                          _przelacz(() => services.setKeyboardAddon(value)),
                  secondary: const Icon(Icons.keyboard_outlined),
                  title: Text(context.l10n.keyboardAddon),
                  subtitle: Text(context.l10n.addonKeyboardShort),
                ),
                if (wlaczony) ...[
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: odbior && przyjmuje,
                    onChanged: (_zajete || !przyjmuje)
                        ? null
                        : (value) => _przelacz(
                            () => services.setRemoteInputReceive(value)),
                    secondary: const Icon(Icons.keyboard_alt_outlined),
                    title: Text(context.l10n.remoteInputReceive),
                    subtitle: przyjmuje
                        ? null
                        : Text(context.l10n.remoteInputUnsupported),
                  ),
                  if (odbior && przyjmuje)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_outlined,
                              size: 18, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.l10n.remoteInputSafety,
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Android pisze przez klawiaturę Chatt: włączoną raz
                  // w ustawieniach systemu i wybraną na czas sesji.
                  if (odbior && przyjmuje && _ime != null) ..._klawiatura(
                      context, scheme, _ime!),
                  // Historia pisania: obie strony sesji, w zaszyfrowanej
                  // bazie. Zapisane sesje zostają po wyłączeniu
                  // przełącznika; kasuje je przycisk na ekranie historii.
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: services.typingHistory.value,
                    onChanged: (value) => services.setTypingHistory(value),
                    secondary: const Icon(Icons.history),
                    title: Text(context.l10n.typingHistorySwitch),
                    subtitle: Text(context.l10n.typingHistoryHelp),
                    isThreeLine: true,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      ChattPageRoute(
                          builder: (_) => const TypingHistoryScreen()),
                    ),
                    icon: const Icon(Icons.manage_history_outlined),
                    label: Text(context.l10n.typingHistory),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

extension on _KeyboardAddonCardState {
  List<Widget> _klawiatura(BuildContext context, ColorScheme scheme,
      ({bool enabled, bool selected}) ime) {
    TextStyle maly() => TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
    if (!ime.enabled) {
      return [
        const SizedBox(height: 8),
        Text(context.l10n.remoteInputImeOff, style: maly()),
        const SizedBox(height: 4),
        Text(context.l10n.remoteInputImeWarning, style: maly()),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _wUstawieniach ? null : _wlaczWSystemie,
          icon: const Icon(Icons.settings_outlined),
          label: Text(context.l10n.remoteInputImeEnable),
        ),
      ];
    }
    return [
      const SizedBox(height: 8),
      Text(
        ime.selected
            ? context.l10n.remoteInputImeReady
            : context.l10n.remoteInputImeNotSelected,
        style: maly(),
      ),
      if (!ime.selected) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _wybierz,
          icon: const Icon(Icons.keyboard_outlined),
          label: Text(context.l10n.remoteInputImePick),
        ),
      ],
    ];
  }
}
