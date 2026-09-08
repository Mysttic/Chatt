import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/autostart.dart';
import '../../core/background_service.dart';
import '../../core/crypto.dart';
import '../../core/languages.dart';
import '../../core/tray.dart';
import '../../core/update_install.dart';
import '../../core/updates.dart';
import '../../core/version.dart';
import '../../data/db.dart';
import '../../services/providers.dart';
import '../backgrounds.dart';
import '../l10n_context.dart';
import '../widgets/common.dart';
import '../widgets/toasts.dart';
import '../widgets/update_card.dart';

/// Ustawienia instancji (odpowiednik EditConfiguration.PNG) + informacje
/// potrzebne do ręcznego parowania (adresy IP i faktyczny port nasłuchu).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nickname;
  late final TextEditingController _welcome;
  late final TextEditingController _port;
  List<String> _addresses = const [];
  bool _batteryOptimized = false;
  bool _autostart = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBattery();
    Autostart.enabled().then((wlaczony) {
      if (mounted) setState(() => _autostart = wlaczony);
    });
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
    WidgetsBinding.instance.removeObserver(this);
    _nickname.dispose();
    _welcome.dispose();
    _port.dispose();
    super.dispose();
  }

  /// Odpowiedź na systemowe okienko przychodzi dopiero przy powrocie do
  /// aplikacji, innego sygnału Android nie daje.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkBattery();
  }

  Future<void> _checkBattery() async {
    final optimized = await BackgroundService.batteryOptimized();
    if (mounted && optimized != _batteryOptimized) {
      setState(() => _batteryOptimized = optimized);
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final needsRestart = await ref.read(appServicesProvider).saveSettings(
          nickname: _nickname.text.trim(),
          welcomeMessage: _welcome.text.trim(),
          tcpPort: int.parse(_port.text.trim()),
        );
    if (!mounted) return;
    showToast(needsRestart
        ? context.l10n.savedRestartNeeded
        : context.l10n.saved);
  }

  Future<void> _askBatteryExemption() async {
    final pokazane = await BackgroundService.requestBatteryExemption();
    if (!mounted || pokazane) return;
    showToast(context.l10n.batteryExemptUnavailable);
  }

  /// Ręczne sprzątanie listy. Automatyczne, przy starcie aplikacji, czeka
  /// tydzień, a tutaj użytkownik mówi wprost, że chce to teraz.
  Future<void> _cleanUpPeers() async {
    final removed = await ref
        .read(appServicesProvider)
        .db
        .sweepStalePeers(keepFor: const Duration(hours: 1));
    if (!mounted) return;
    showToast(removed == 0
        ? context.l10n.nothingToCleanUp
        : context.l10n.cleanedUp(removed));
  }

  /// Zapis do rejestru może odmówić (polityka, zablokowany klucz), wtedy
  /// przełącznik wraca na swoje miejsce zamiast kłamać.
  Future<void> _setAutostart(bool value) async {
    final udalo = await Autostart.setEnabled(value);
    if (!mounted) return;
    setState(() => _autostart = udalo ? value : !value);
    if (!udalo) showToast(context.l10n.startWithWindowsFailed);
  }

  /// Wyczyszczenie historii jest nieodwracalne, więc pytamy wprost.
  Future<void> _clearHistory() async {
    final zgoda = await showDialog<bool>(
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
    if (zgoda != true || !mounted) return;

    final teksty = context.l10n;
    final usuniete = await ref.read(appServicesProvider).db.clearHistory();
    showToast(usuniete == 0
        ? teksty.nothingToCleanUp
        : teksty.historyCleared(usuniete));
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.read(appServicesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      // Formularz rozciągnięty na cały monitor czyta się fatalnie.
      body: ContentColumn(
        child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomSystemInset(context)),
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
          Text(context.l10n.background,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: chattBackgrounds.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final tlo = chattBackgrounds[index];
                final wybrane =
                    (ref.watch(settingsProvider).value?.background ?? 0) == index;
                return _BackgroundChip(
                  background: tlo,
                  selected: wybrane,
                  onTap: () => services.db.saveBackground(index),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(context.l10n.language,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          // Lista, a nie rzędek przycisków: kolejny język to jedna pozycja
          // więcej, bez przebudowy układu (patrz core/languages.dart).
          DropdownButtonFormField<AppLanguage>(
            initialValue:
                ref.watch(settingsProvider).value?.language ?? AppLanguage.system,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
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
          // Tylko Android: na desktopie proces żyje tak długo, jak okno.
          if (Platform.isAndroid) ...[
            const SizedBox(height: 24),
            Text(context.l10n.backgroundListening,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _batteryOptimized
                              ? Icons.battery_alert_outlined
                              : Icons.check_circle_outline,
                          color: _batteryOptimized
                              ? scheme.error
                              : scheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(_batteryOptimized
                              ? context.l10n.batteryOptimizedWarning
                              : context.l10n.batteryExemptOk),
                        ),
                      ],
                    ),
                    if (_batteryOptimized) ...[
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: _askBatteryExemption,
                        icon: const Icon(Icons.battery_saver_outlined),
                        label: Text(context.l10n.batteryExemptButton),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          // Tylko Windows: na Androidzie ciągłość nasłuchu załatwia usługa
          // pierwszoplanowa, a zasobnika nie ma.
          if (Autostart.supported) ...[
            const SizedBox(height: 24),
            Text(context.l10n.windowsSection,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autostart,
              onChanged: _setAutostart,
              secondary: const Icon(Icons.rocket_launch_outlined),
              title: Text(context.l10n.startWithWindows),
              subtitle: Text(context.l10n.startWithWindowsHelp),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.dashboard_customize_outlined,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.trayHint,
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
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
          Text(context.l10n.links,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const _LinkPreviewsSection(),
          const SizedBox(height: 32),
          Text(context.l10n.updates,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const _UpdatesSection(),
          const SizedBox(height: 32),
          Text(context.l10n.privacy,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    services.keyProtected
                        ? Icons.lock_outline
                        : Icons.lock_open_outlined,
                    color: services.keyProtected ? scheme.primary : scheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(services.keyProtected
                        ? context.l10n.dbKeyProtected
                        : context.l10n.dbKeyUnprotected),
                  ),
                ],
              ),
            ),
          ),
          // Milczący responder znaczy, że urządzenia nikt nie znajdzie skanem.
          // Bez tego wiersza objaw wygląda jak problem z siecią po drugiej
          // stronie i szuka się go tygodniami.
          if (!services.discoveryListening) ...[
            const SizedBox(height: 12),
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.wifi_find_outlined, color: scheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(context.l10n.discoveryDeaf,
                          style: TextStyle(color: scheme.onErrorContainer)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: ref.watch(settingsProvider).value?.retentionDays ?? 0,
            decoration: InputDecoration(
              labelText: context.l10n.retentionLabel,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.auto_delete_outlined),
            ),
            items: [
              for (final dni in _retentionChoices)
                DropdownMenuItem(
                  value: dni,
                  child: Text(dni == 0
                      ? context.l10n.retentionNever
                      : context.l10n.retentionDays(dni)),
                ),
            ],
            onChanged: (wybor) async {
              if (wybor == null) return;
              await services.db.saveRetentionDays(wybor);
              // Ustawienie ma zadziałać od razu, a nie dopiero przy restarcie.
              await services.applyRetention(wybor);
            },
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.retentionHelp,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _clearHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(context.l10n.clearHistory),
            style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
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
                  _InfoRow(label: context.l10n.version, value: appVersion),
                  const SizedBox(height: 8),
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
                  // Odcisk własnego klucza: to jego dyktujesz rozmówcy, gdy
                  // chcecie sprawdzić, czy rozmawiacie ze sobą.
                  _InfoRow(
                    label: context.l10n.fingerprintMine,
                    value: ChattCrypto.fingerprint(services.identity.publicKey),
                  ),
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
      ),
    );
  }
}

/// Przełącznik podglądów stron pod odnośnikami.
///
/// Osobna sekcja, a nie wiersz w „Prywatności", bo to zgoda tego samego
/// rodzaju co pytanie o aktualizacje: włączenie jej wypuszcza aplikację poza
/// sieć lokalną, i to pod adresy, których nie wybiera użytkownik, tylko
/// nadawca wiadomości. Dlatego pod przełącznikiem stoi wprost napisane, co
/// zobaczy serwer po drugiej stronie i czego podgląd nie robi.
class _LinkPreviewsSection extends ConsumerWidget {
  const _LinkPreviewsSection();

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
                Icon(Icons.shield_outlined,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.linkPreviewsSafety,
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 12),
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

/// Sekcja „Aktualizacje": przełącznik, sprawdzenie na żądanie i karta
/// z nowym wydaniem, gdy jakieś jest.
///
/// Pobieranie i uruchomienie instalatora dzieje się tutaj, a nie w warstwie
/// serwisów, bo to jedyne miejsce, w którym użytkownik o to prosi i w którym
/// widzi postęp.
class _UpdatesSection extends ConsumerStatefulWidget {
  const _UpdatesSection();

  @override
  ConsumerState<_UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends ConsumerState<_UpdatesSection> {
  /// Wynik ostatniego sprawdzenia zrobionego z tego ekranu. `null`, dopóki
  /// nikt nie nacisnął przycisku: sam brak nowego wydania nie jest jeszcze
  /// powodem, żeby cokolwiek pisać.
  UpdateCheck? _ostatniWynik;

  /// Ile procent pliku już jest. `null` znaczy „nie pobieram".
  int? _postep;
  String? _blad;

  Future<void> _sprawdz() async {
    setState(() {
      _ostatniWynik = null;
      _blad = null;
    });
    final wynik = await ref.read(appServicesProvider).checkForUpdate();
    if (mounted) setState(() => _ostatniWynik = wynik.outcome);
  }

  Future<void> _pobierzIZainstaluj(Release wydanie) async {
    final teksty = context.l10n;
    setState(() {
      _postep = 0;
      _blad = null;
    });
    try {
      final plik = await downloadRelease(
        wydanie,
        onProgress: (odebrane, razem) {
          if (!mounted || razem == null || razem == 0) return;
          setState(() => _postep = (odebrane * 100 ~/ razem));
        },
      );
      final ruszyl = await launchInstaller(plik);
      if (!mounted) return;
      if (!ruszyl) {
        setState(() {
          _postep = null;
          _blad = teksty.updateInstallFailed;
        });
        return;
      }
      setState(() => _postep = null);
      // Windows: instalator wgrywa się w miejsce działającej aplikacji, więc
      // ta musi zejść mu z drogi. Android zostaje otwarty, bo tam podmianą
      // zajmuje się osobny ekran systemu.
      if (Platform.isWindows) {
        showToast(teksty.updateClosingForInstall);
        await Future<void>.delayed(const Duration(seconds: 2));
        await TrayIcon.instance.quit();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _postep = null;
        _blad = teksty.updateDownloadFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              value: ustawienia?.updateChecks ?? false,
              title: Text(context.l10n.updateChecksLabel),
              subtitle: Text(context.l10n.updateChecksHelp),
              isThreeLine: true,
              onChanged: ustawienia == null
                  ? null
                  : (wlaczone) async {
                      await services.db.saveUpdateChecks(wlaczone);
                      // Włączenie ma dać odpowiedź od razu, zamiast kazać
                      // czekać do jutra na pierwsze pytanie.
                      if (wlaczone) await _sprawdz();
                    },
            ),
            const Divider(height: 24),
            ValueListenableBuilder<bool>(
              valueListenable: services.checkingForUpdate,
              builder: (context, sprawdza, _) => Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: sprawdza || _postep != null ? null : _sprawdz,
                    icon: sprawdza
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(sprawdza
                        ? context.l10n.updateChecking
                        : context.l10n.updateCheckNow),
                  ),
                  if (ustawienia?.lastUpdateCheck != null) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        context.l10n.updateLastChecked(
                            formatWhen(ustawienia!.lastUpdateCheck)),
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_ostatniWynik == UpdateCheck.upToDate) ...[
              const SizedBox(height: 12),
              Text(context.l10n.updateUpToDate),
            ],
            if (_ostatniWynik == UpdateCheck.failed) ...[
              const SizedBox(height: 12),
              Text(context.l10n.updateDownloadFailed,
                  style: TextStyle(color: scheme.error)),
            ],
            ValueListenableBuilder<Release?>(
              valueListenable: services.availableRelease,
              builder: (context, wydanie, _) => wydanie == null
                  ? const SizedBox.shrink()
                  : UpdateCard(
                      release: wydanie,
                      canInstall: canInstallUpdate(),
                      progress: _postep,
                      error: _blad,
                      onInstall: () => _pobierzIZainstaluj(wydanie),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Podgląd jednego tła: prostokąt z gradientem i podpis pod spodem.
/// „Bez tła" pokazuje kolor powierzchni z motywu, żeby wybór wyglądał
/// tak samo jak reszta.
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
    final scheme = Theme.of(context).colorScheme;
    final kolory = background.plain
        ? [scheme.surfaceContainerHighest, scheme.surfaceContainerHighest]
        : background.colorsFor(Theme.of(context).brightness);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: kolory,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(Icons.check, color: scheme.primary)
                : null,
          ),
          const SizedBox(height: 4),
          Text(
            background.label(context.l10n),
            style: TextStyle(
              fontSize: 12,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Granice wieku wiadomości do wyboru. Zero to „nie kasuj".
const _retentionChoices = [0, 7, 30, 90, 365];

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
