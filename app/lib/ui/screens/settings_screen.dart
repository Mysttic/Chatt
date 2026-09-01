import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';

/// Ustawienia instancji (odpowiednik EditConfiguration.PNG) + informacje
/// potrzebne do ręcznego parowania (adresy IP i faktyczny port nasłuchu).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nickname;
  late final TextEditingController _welcome;
  late final TextEditingController _port;
  List<String> _addresses = const [];

  @override
  void initState() {
    super.initState();
    final services = ref.read(appServicesProvider);
    _nickname = TextEditingController(text: services.identity.name);
    _welcome = TextEditingController(text: services.identity.welcomeMessage);
    _port = TextEditingController();
    services.db.getSettings().then((settings) {
      if (mounted && settings != null) {
        _port.text = settings.tcpPort.toString();
      }
    });
    services.localAddresses().then((addresses) {
      if (mounted) setState(() => _addresses = addresses);
    });
  }

  @override
  void dispose() {
    _nickname.dispose();
    _welcome.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final needsRestart = await ref.read(appServicesProvider).saveSettings(
          nickname: _nickname.text.trim(),
          welcomeMessage: _welcome.text.trim(),
          tcpPort: int.parse(_port.text.trim()),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(needsRestart
          ? context.l10n.savedRestartNeeded
          : context.l10n.saved),
    ));
  }

  /// Ręczne sprzątanie listy. Automatyczne, przy starcie aplikacji, czeka
  /// tydzień — tutaj użytkownik mówi wprost, że chce to teraz.
  Future<void> _cleanUpPeers() async {
    final removed = await ref
        .read(appServicesProvider)
        .db
        .sweepStalePeers(keepFor: const Duration(hours: 1));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(removed == 0
          ? context.l10n.nothingToCleanUp
          : context.l10n.cleanedUp(removed)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.read(appServicesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nickname,
                  decoration: InputDecoration(
                    labelText: context.l10n.nicknameLabel,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? context.l10n.nicknameRequired
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _welcome,
                  decoration: InputDecoration(
                    labelText: context.l10n.welcomeLabel,
                    helperText: context.l10n.welcomeHelper,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.portFieldLabel,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final port = int.tryParse((value ?? '').trim());
                    return (port == null || port < 1024 || port > 65535)
                        ? context.l10n.portRange
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(context.l10n.save),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(context.l10n.appearance,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<AppTheme>(
            segments: [
              ButtonSegment(
                value: AppTheme.system,
                icon: const Icon(Icons.brightness_auto_outlined),
                label: Text(context.l10n.themeSystem),
              ),
              ButtonSegment(
                value: AppTheme.light,
                icon: const Icon(Icons.light_mode_outlined),
                label: Text(context.l10n.themeLight),
              ),
              ButtonSegment(
                value: AppTheme.dark,
                icon: const Icon(Icons.dark_mode_outlined),
                label: Text(context.l10n.themeDark),
              ),
            ],
            selected: {
              ref.watch(settingsProvider).value?.theme ?? AppTheme.system,
            },
            onSelectionChanged: (wybor) =>
                services.db.saveTheme(wybor.first),
          ),
          const SizedBox(height: 16),
          Text(context.l10n.language,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<AppLanguage>(
            segments: [
              ButtonSegment(
                value: AppLanguage.system,
                label: Text(context.l10n.languageSystem),
              ),
              ButtonSegment(
                value: AppLanguage.polish,
                label: Text(context.l10n.languagePolish),
              ),
              ButtonSegment(
                value: AppLanguage.english,
                label: Text(context.l10n.languageEnglish),
              ),
            ],
            selected: {
              ref.watch(settingsProvider).value?.language ?? AppLanguage.system,
            },
            onSelectionChanged: (wybor) =>
                services.db.saveLanguage(wybor.first),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _cleanUpPeers,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: Text(context.l10n.cleanUpDevices),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.cleanUpHelp,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 32),
          Text(context.l10n.thisDevice,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    label: context.l10n.listeningOn,
                    value: _addresses.isEmpty
                        ? context.l10n.listeningPort(services.identity.tcpPort)
                        : _addresses
                            .map((a) => '$a:${services.identity.tcpPort}')
                            .join('\n'),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                      label: context.l10n.deviceIdentifier,
                      value: services.identity.guid),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.manualPairingHint,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(child: SelectableText(value)),
      ],
    );
  }
}
