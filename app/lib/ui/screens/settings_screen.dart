import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/autostart.dart';
import '../../core/background_service.dart';
import '../../core/crypto.dart';
import '../../core/languages.dart';
import '../../core/remote_input.dart';
import '../../core/tray.dart';
import '../../core/update_install.dart';
import '../../core/updates.dart';
import '../../core/version.dart';
import '../../data/db.dart';
import '../../network/bt_transport.dart';
import '../../network/stun.dart' show NatMapping;
import '../../services/app_services.dart';
import '../../services/providers.dart';
import '../backgrounds.dart';
import '../l10n_context.dart';
import '../styles.dart';
import '../widgets/common.dart';
import '../widgets/export_dialog.dart';
import '../widgets/motion.dart';
import '../widgets/toasts.dart';
import '../widgets/update_card.dart';
import 'app_log_screen.dart';
import 'typing_history_screen.dart';

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

  /// Liczba sesji w historii pisania, na żywo. Jeden strumień na życie
  /// ekranu: przebudowa nie zakłada nowego zapytania w bazie.
  late final Stream<int> _sesjePisania =
      ref.read(appServicesProvider).db.watchTypingSessionCount();

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

  /// Wyczyszczenie historii jest nieodwracalne, więc pytamy wprost. Razem
  /// z rozmowami znika historia pisania (patrz [AppServices.clearHistory]).
  Future<void> _clearHistory() async {
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
    if (zgoda != true || !mounted) return;

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
          _Sekcja(context.l10n.profileSection, pierwsza: true),
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nickname,
                  decoration: InputDecoration(
                    labelText: context.l10n.nicknameLabel,
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
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.portFieldLabel,
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
          _Sekcja(context.l10n.appearance),
          // Styl zmienia wyłącznie wygląd: te same ekrany i informacje.
          Text(context.l10n.styleLabel,
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<AppStyle>(
            showSelectedIcon: false,
            segments: [
              for (final styl in AppStyle.values)
                ButtonSegment(value: styl, label: Text(styl.label(context))),
            ],
            selected: {
              ref.watch(settingsProvider).value?.style ?? AppStyle.cisza,
            },
            onSelectionChanged: (wybor) =>
                services.db.saveStyle(wybor.first),
          ),
          const SizedBox(height: 16),
          Text(context.l10n.themeLabel,
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          // Na wąskim ekranie same napisy, jak przy stylu: z ikoną
          // „Systemowy” łamał się w środku słowa. Szerokie okno mieści ikony.
          LayoutBuilder(builder: (context, miejsce) {
            final waskie = miejsce.maxWidth < 480;
            Widget? ikona(IconData dane) => waskie ? null : Icon(dane);
            return SegmentedButton<AppTheme>(
              showSelectedIcon: !waskie,
              style: waskie
                  ? const ButtonStyle(
                      padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 8)),
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
              selected: {
                ref.watch(settingsProvider).value?.theme ?? AppTheme.system,
              },
              onSelectionChanged: (wybor) =>
                  services.db.saveTheme(wybor.first),
            );
          }),
          const SizedBox(height: 16),
          Text(context.l10n.background,
              style: Theme.of(context).textTheme.labelLarge),
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
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          // Lista, a nie rzędek przycisków: kolejny język to jedna pozycja
          // więcej, bez przebudowy układu (patrz core/languages.dart).
          DropdownButtonFormField<AppLanguage>(
            initialValue:
                ref.watch(settingsProvider).value?.language ?? AppLanguage.system,
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
          // Tylko Android: na desktopie proces żyje tak długo, jak okno.
          if (Platform.isAndroid) ...[
            _Sekcja(context.l10n.backgroundListening),
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
            _Sekcja(context.l10n.windowsSection),
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
          const SizedBox(height: 16),
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
          _Sekcja(context.l10n.links),
          const _LinkPreviewsSection(),
          _Sekcja(context.l10n.updates),
          // Numer wersji mieszka tutaj: na górze aplikacji stoi nazwa
          // urządzenia.
          Text('${context.l10n.version} $appVersion',
              style: ChattTokens.of(context)
                  .mono
                  .copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          const _UpdatesSection(),
          _Sekcja(context.l10n.privacy),
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
          // Historia pisania, dziennik i eksport: wszystko, co aplikacja
          // wie, da się stąd przejrzeć i wynieść do analizy poza nią.
          _Sekcja(context.l10n.dataSection),
          // Wejście do historii pisania stoi tu, póki historia ma choć jedną
          // sesję: po wyłączeniu dodatku klawiatury jego karta chowa
          // przycisk, a zapisane sesje dalej da się przejrzeć i wyczyścić.
          StreamBuilder<int>(
            stream: _sesjePisania,
            builder: (context, snapshot) {
              final sesje = snapshot.data ?? 0;
              if (sesje == 0) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      ChattPageRoute(
                          builder: (_) => const TypingHistoryScreen()),
                    ),
                    icon: const Icon(Icons.manage_history_outlined),
                    label: Text(context.l10n.typingHistory),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.typingHistoryEntryHelp(sesje),
                    style:
                        TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              ChattPageRoute(builder: (_) => const AppLogScreen()),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(context.l10n.appLog),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.appLogHelp,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => showExportDialog(context, services: services),
            icon: const Icon(Icons.archive_outlined),
            label: Text(context.l10n.exportData),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.exportDataHelp,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          _Sekcja(context.l10n.addons),
          const BluetoothAddonCard(),
          const SizedBox(height: 8),
          const InternetAddonCard(),
          const SizedBox(height: 8),
          const KeyboardAddonCard(),
          _Sekcja(context.l10n.thisDevice),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: ValueListenableBuilder<BtStatus>(
                valueListenable: services.bluetoothStatus,
                builder: (context, radio, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Wartosc(
                      label: context.l10n.listeningOn,
                      value: _addresses.isEmpty
                          ? context.l10n.listeningPort(services.identity.tcpPort)
                          : _addresses
                              .map((a) => '$a:${services.identity.tcpPort}')
                              .join('\n'),
                    ),
                    // Własny adres radia: Android go nie podaje, więc tam
                    // tego wiersza nie ma.
                    if (services.bluetoothAddon.value && radio.address.isNotEmpty)
                      _Wartosc(
                          label: context.l10n.btAddressLabel,
                          value: radio.address),
                    _Wartosc(
                        label: context.l10n.deviceIdentifier,
                        value: services.identity.guid),
                    // Odcisk własnego klucza: to jego dyktujesz rozmówcy, gdy
                    // chcecie sprawdzić, czy rozmawiacie ze sobą.
                    _Wartosc(
                      label: context.l10n.fingerprintMine,
                      value:
                          ChattCrypto.fingerprint(services.identity.publicKey),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.manualPairingHint,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
        ),
      ),
    );
  }
}

/// Dodatek Bluetooth: jeden przełącznik, który włącza całą funkcję.
///
/// Przy wyłączonym dodatku karta pokazuje sam przełącznik, a reszta aplikacji
/// wygląda i działa jak przed Bluetoothem. Po włączeniu dochodzą: stan radia
/// i zgody, adres radia, wykrywalność komputera i przełącznik sieci lokalnej,
/// który bez dodatku nie ma sensu, bo sieć jest wtedy jedyną drogą.
class BluetoothAddonCard extends ConsumerStatefulWidget {
  const BluetoothAddonCard({super.key});

  @override
  ConsumerState<BluetoothAddonCard> createState() => BluetoothAddonCardState();
}

class BluetoothAddonCardState extends ConsumerState<BluetoothAddonCard> {
  bool _zajete = false;

  /// Trwa czekanie na zgodę wydaną w ustawieniach systemu. Drugie
  /// kliknięcie przycisku nie zaczyna drugiego czekania.
  bool _czekaNaZgode = false;

  @override
  void initState() {
    super.initState();
    // Stan radia i zgód potrafi się zmienić poza aplikacją (użytkownik gasi
    // Bluetooth w systemie), więc pytamy o niego przy każdym wejściu. Przy
    // wyłączonym dodatku serwis nie pyta systemu o nic.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appServicesProvider).refreshBluetoothStatus();
    });
  }

  Future<void> _setWifi(bool value) async {
    await ref.read(appServicesProvider).db.saveWifiEnabled(value);
  }

  Future<void> _setAddon(bool value) async {
    final services = ref.read(appServicesProvider);
    setState(() => _zajete = true);
    try {
      if (!value) {
        await services.setBluetoothAddon(false);
        return;
      }
      if (!await _upewnijSieOZgode(services, wlaczanie: true)) {
        if (mounted) showToast(context.l10n.transportBluetoothNoPermission);
        return;
      }
      // Serwis zapisuje przełącznik i podnosi radio. Wynik pokazujemy po jego
      // odpowiedzi.
      final udalo = await services.setBluetoothAddon(true);
      if (!mounted || udalo) return;
      await services.refreshBluetoothStatus();
      if (mounted) showToast(context.l10n.transportBluetoothFailed);
    } finally {
      if (mounted) setState(() => _zajete = false);
    }
  }

  /// Zgoda na urządzenia w pobliżu, pytana przy włączaniu dodatku
  /// ([wlaczanie]) i przyciskiem na karcie, gdy zgodę cofnięto. Poza tymi
  /// dwoma miejscami aplikacja o nią nie prosi.
  ///
  /// Odpowiedź z systemowego okienka nie wraca kanałem. Przychodzi razem
  /// z powrotem aplikacji na wierzch, po okienku albo po ekranie ustawień
  /// systemu, więc na ten powrót czekamy, bez odpytywania radia w tym czasie
  /// i bez limitu krótszego niż wędrówka po ustawieniach.
  Future<bool> _upewnijSieOZgode(AppServices services,
      {bool wlaczanie = false, bool ustawienia = false}) async {
    var stan = await services.refreshBluetoothStatus(force: wlaczanie);
    if (stan.granted) return true;

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
      var otwarte = ustawienia
          ? await services.openBluetoothSettings()
          : await services.askForBluetoothPermission();
      // Okienko, które się nie pokazało (system zbył prośbę bez słowa),
      // zostawia aplikację na wierzchu. Wtedy zostają ustawienia systemu.
      if (otwarte && !ustawienia) {
        await Future.any(
            [powrot.future, Future<void>.delayed(const Duration(seconds: 3))]);
        if (!wyszla) otwarte = await services.openBluetoothSettings();
      }
      if (!otwarte) return false;
      await powrot.future
          .timeout(const Duration(minutes: 10), onTimeout: () {});
    } finally {
      sluchacz.dispose();
    }
    if (!mounted || (!wlaczanie && !services.bluetoothAddon.value)) {
      return false;
    }
    // Stan zgody potrafi dojść chwilę po powrocie na wierzch.
    for (var proba = 0; proba < 4; proba++) {
      stan = await services.refreshBluetoothStatus(force: wlaczanie);
      if (stan.granted) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// Zgoda cofnięta przy włączonym dodatku. Przycisk obiecuje ustawienia
  /// systemu, więc je otwiera: tam zgodę da się wydać także po odmowie na
  /// stałe. Odświeżanie stanu podnosi radio, gdy tylko zgoda się pojawi.
  Future<void> _wydajZgode(AppServices services) async {
    if (_czekaNaZgode) return;
    setState(() => _czekaNaZgode = true);
    try {
      await _upewnijSieOZgode(services, ustawienia: true);
    } finally {
      if (mounted) setState(() => _czekaNaZgode = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.read(appServicesProvider);
    final wifi = ref.watch(settingsProvider).value?.wifiEnabled ?? true;
    final scheme = Theme.of(context).colorScheme;
    final wspierany = services.bluetoothSupported;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            services.bluetoothAddon,
            services.bluetoothRunning,
            services.bluetoothStatus,
          ]),
          builder: (context, _) {
            final wlaczony = services.bluetoothAddon.value;
            final BtStatus stan = services.bluetoothStatus.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: wlaczony,
                  onChanged: (!wspierany || _zajete) ? null : _setAddon,
                  secondary: const Icon(Icons.bluetooth),
                  title: Text(context.l10n.transportBluetooth),
                  subtitle: Text(wspierany
                      ? context.l10n.addonBluetoothShort
                      : context.l10n.transportBluetoothUnsupported),
                ),
                if (wlaczony) ...[
                  if (!stan.enabled)
                    _uwaga(scheme, Icons.bluetooth_disabled,
                        context.l10n.transportBluetoothRadioOff),
                  if (stan.enabled && !stan.granted) ...[
                    _uwaga(scheme, Icons.lock_outline,
                        context.l10n.transportBluetoothNoPermission),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed:
                          _czekaNaZgode ? null : () => _wydajZgode(services),
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(context.l10n.transportBluetoothGrant),
                    ),
                  ],
                  // Własny adres radia: druga strona potrzebuje go przy
                  // dodawaniu po adresie. Android go nie podaje, więc tam
                  // tego wiersza nie ma.
                  if (stan.address.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SelectableText(
                        context.l10n.myBtAddress(stan.address),
                        style: ChattTokens.of(context)
                            .mono
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  // Przy działającym radiu komputer widzi każdy, kto się
                  // rozejrzy. Użytkownik dowiaduje się o tym tutaj.
                  if (Platform.isWindows && services.bluetoothRunning.value)
                    _uwaga(scheme, Icons.visibility_outlined,
                        context.l10n.transportBluetoothDiscoverable),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: wifi,
                    onChanged: _setWifi,
                    secondary: const Icon(Icons.wifi),
                    title: Text(context.l10n.transportWifi),
                  ),
                  if (!wifi && !services.bluetoothRunning.value)
                    _uwaga(scheme, Icons.warning_amber_outlined,
                        context.l10n.transportBothOff,
                        bad: true),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _uwaga(ColorScheme scheme, IconData icon, String text,
          {bool bad = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 18,
                color: bad ? scheme.error : scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: bad ? scheme.error : scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Dodatek „Internet": rozmowa z potwierdzonym urządzeniem w innej sieci,
/// bez serwera pośredniczącego (issue #68). Jeden przełącznik całej funkcji,
/// domyślnie wyłączony; po włączeniu pokazuje adres publiczny i pozwala
/// sprawdzić, czy NAT nadaje się do przebicia dziury.
class InternetAddonCard extends ConsumerStatefulWidget {
  const InternetAddonCard({super.key});

  @override
  ConsumerState<InternetAddonCard> createState() => _InternetAddonCardState();
}

class _InternetAddonCardState extends ConsumerState<InternetAddonCard> {
  bool _zajete = false;
  bool _sprawdza = false;
  String? _natOpis;

  Future<void> _setAddon(bool on) async {
    if (_zajete) return;
    setState(() => _zajete = true);
    try {
      await ref.read(appServicesProvider).setInternetAddon(on);
      if (!on) setState(() => _natOpis = null);
    } finally {
      if (mounted) setState(() => _zajete = false);
    }
  }

  Future<void> _sprawdzNat() async {
    if (_sprawdza) return;
    setState(() => _sprawdza = true);
    final teksty = context.l10n;
    try {
      final wynik = await ref.read(appServicesProvider).probeInternetNat();
      if (!mounted) return;
      setState(() => _natOpis = switch (wynik.nat) {
            NatMapping.endpointIndependent => teksty.internetNatOpen,
            NatMapping.endpointDependent => teksty.internetNatSymmetric,
            NatMapping.none => teksty.internetNatNone,
            NatMapping.unknown => teksty.internetNatUnknown,
          });
    } finally {
      if (mounted) setState(() => _sprawdza = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.read(appServicesProvider);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            services.internetAddon,
            services.internetRunning,
            services.internetPublicAddress,
          ]),
          builder: (context, _) {
            final wlaczony = services.internetAddon.value;
            final adres = services.internetPublicAddress.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: wlaczony,
                  onChanged: _zajete ? null : _setAddon,
                  secondary: const Icon(Icons.public),
                  title: Text(context.l10n.transportInternet),
                  subtitle: Text(context.l10n.addonInternetShort),
                ),
                if (wlaczony) ...[
                  _uwaga(scheme, Icons.science_outlined,
                      context.l10n.internetAddonExperimental),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      adres.isEmpty
                          ? context.l10n.internetPublicAddressUnknown
                          : context.l10n.internetPublicAddressLabel(adres),
                      style: ChattTokens.of(context)
                          .mono
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _sprawdza ? null : _sprawdzNat,
                    icon: _sprawdza
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_check),
                    label: Text(context.l10n.internetCheckNat),
                  ),
                  if (_natOpis != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _natOpis!,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _uwaga(ColorScheme scheme, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
          ],
        ),
      );
}

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
                decoration: wallDecoration(background.wallIn(context),
                    borderRadius: promien),
                child: SizedBox(
                  width: 88,
                  height: 60,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: promien,
                      border: Border.all(
                        color: Color.lerp(
                            scheme.outlineVariant, scheme.primary, z)!,
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
                  color:
                      Color.lerp(scheme.onSurfaceVariant, scheme.primary, z),
                  fontWeight:
                      FontWeight.lerp(podpis.fontWeight, FontWeight.w600, z),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Granice wieku wiadomości do wyboru. Zero to „nie kasuj".
const _retentionChoices = [0, 7, 30, 90, 365];

/// Nagłówek sekcji Ustawień w stylu (wersaliki w Precyzji).
class _Sekcja extends StatelessWidget {
  final String title;
  final bool pierwsza;

  const _Sekcja(this.title, {this.pierwsza = false});

  @override
  Widget build(BuildContext context) {
    final k = ChattTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: pierwsza ? 0 : 32, bottom: 8),
      child: Text(
        k.overlineText(title),
        style: k.overline
            .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Wartość techniczna z podpisem i przyciskiem kopiowania. Font o stałej
/// szerokości stylu, bo te wartości się przepisuje i porównuje.
class _Wartosc extends StatelessWidget {
  final String label;
  final String value;

  const _Wartosc({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                SelectableText(value,
                    style: ChattTokens.of(context)
                        .mono
                        .copyWith(color: scheme.onSurface)),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: context.l10n.copy,
          icon: const Icon(Icons.copy_outlined, size: 20),
          onPressed: () async {
            final teksty = context.l10n;
            await Clipboard.setData(
                ClipboardData(text: value.replaceAll('\n', ' ')));
            showToast(teksty.copied);
          },
        ),
      ],
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
