import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../network/bt_transport.dart';
import '../../../services/app_services.dart';
import '../../../services/providers.dart';
import '../../l10n_context.dart';
import '../../styles.dart';
import '../../widgets/toasts.dart';

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
            services.internetRunning,
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
                  // Działająca droga internetowa dalej łączy z potwierdzonymi
                  // urządzeniami.
                  if (!wifi &&
                      !services.bluetoothRunning.value &&
                      !services.internetRunning.value)
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
