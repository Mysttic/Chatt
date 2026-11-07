import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto.dart';
import '../../../services/app_services.dart';
import '../../../services/providers.dart';
import '../../l10n_context.dart';
import '../../widgets/toasts.dart';
import 'bluetooth_addon_card.dart';
import 'internet_addon_card.dart';
import 'settings_widgets.dart';

/// Kategoria Połączenie: drogi do innych urządzeń (Bluetooth z siecią
/// lokalną, Internet), port nasłuchu, dane tego urządzenia do ręcznego
/// parowania i sprzątanie listy znanych urządzeń.
///
/// Port zapisuje się przy wyjściu z pola i przy wyjściu z kategorii
/// ([commit]). Port spoza zakresu zatrzymuje w kategorii.
class ConnectionSection extends ConsumerStatefulWidget {
  const ConnectionSection({super.key});

  @override
  ConsumerState<ConnectionSection> createState() => ConnectionSectionState();
}

class ConnectionSectionState extends ConsumerState<ConnectionSection>
    with SettingsCommit {
  late final AppServices _services = ref.read(appServicesProvider);
  final _portPole = GlobalKey<FormFieldState<String>>();
  final _port = TextEditingController();
  final _portFokus = FocusNode();

  /// Port, który ostatnio wyszedł do zapisu. `null`, dopóki pole nie
  /// dostało wartości z bazy: wtedy nie ma czego zapisywać.
  int? _zapisanyPort;

  /// Port, którego zapis właśnie trwa.
  int? _wZapisie;
  List<String> _adresy = const [];

  @override
  void initState() {
    super.initState();
    final zBazy = ref.read(settingsProvider).value?.tcpPort;
    if (zBazy != null) {
      _ustawPort(zBazy);
    } else {
      _services.db.getSettings().then((ustawienia) {
        if (mounted && ustawienia != null && _zapisanyPort == null) {
          _ustawPort(ustawienia.tcpPort);
        }
      });
    }
    _portFokus.addListener(() {
      if (!_portFokus.hasFocus) unawaited(commit());
    });
    _services.localAddresses().then((adresy) {
      if (mounted) setState(() => _adresy = adresy);
    });
  }

  void _ustawPort(int port) {
    _zapisanyPort = port;
    _port.text = '$port';
  }

  @override
  void dispose() {
    // Zamknięcie ekranu bez „Wstecz”: poprawny port i tak zostaje.
    final port = _poprawny(_port.text);
    if (port != null && port != _zapisanyPort) {
      unawaited(_services.savePort(port));
    }
    _portFokus.dispose();
    _port.dispose();
    super.dispose();
  }

  static int? _poprawny(String tekst) {
    final port = int.tryParse(tekst.trim());
    return (port == null || port < 1024 || port > 65535) ? null : port;
  }

  @override
  Future<bool> commit() async {
    final zapisany = _zapisanyPort;
    // Pole bez zmian nie ma czego sprawdzać. W bazie bywa port spoza
    // zakresu pola (CHATT_TCP_PORT, testy z portem 0) i nie może on
    // zamknąć nikogo w kategorii.
    if (zapisany == null || _port.text.trim() == '$zapisany') return true;
    if (!(_portPole.currentState?.validate() ?? true)) return false;
    final port = _poprawny(_port.text);
    if (port == null) return false;
    if (port == zapisany || port == _wZapisie) return true;
    final teksty = context.l10n;
    // Port w zapisie: drugie wyjście z pola w tym czasie nie zapisuje go
    // drugi raz. Za zapisany uchodzi dopiero po udanym zapisie, więc błąd
    // bazy da się powtórzyć tym samym portem.
    _wZapisie = port;
    try {
      final restart = await _services.savePort(port);
      _zapisanyPort = port;
      if (restart) showToast(teksty.savedRestartNeeded);
    } finally {
      _wZapisie = null;
    }
    return true;
  }

  /// Ręczne sprzątanie listy. Automatyczne, przy starcie aplikacji, czeka
  /// tydzień, a tutaj użytkownik mówi wprost, że chce to teraz.
  Future<void> _cleanUpPeers() async {
    final removed = await _services.db.sweepStalePeers(
      keepFor: const Duration(hours: 1),
    );
    if (!mounted) return;
    showToast(
      removed == 0
          ? context.l10n.nothingToCleanUp
          : context.l10n.cleanedUp(removed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    final scheme = Theme.of(context).colorScheme;
    final teksty = context.l10n;
    final port = services.identity.tcpPort;

    return SettingsPage(
      children: [
        // Milczący responder znaczy, że urządzenia nikt nie znajdzie skanem.
        // Bez tej karty objaw wygląda jak problem z siecią po drugiej
        // stronie i szuka się go tygodniami. Stoi na górze, bo to o nim
        // mówi linia pod nazwą kategorii.
        if (!services.discoveryListening) ...[
          Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.wifi_find_outlined,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      teksty.discoveryDeaf,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const BluetoothAddonCard(),
        const SizedBox(height: 8),
        const InternetAddonCard(),
        SettingsSubheader(teksty.thisDevice),
        TextFormField(
          key: _portPole,
          controller: _port,
          focusNode: _portFokus,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autovalidateMode: AutovalidateMode.onUserInteractionIfError,
          decoration: InputDecoration(
            labelText: teksty.portFieldLabel,
            helperText: teksty.portRestartHint,
            helperMaxLines: 2,
          ),
          validator: (value) =>
              _poprawny(value ?? '') == null ? teksty.portRange : null,
          onFieldSubmitted: (_) => unawaited(commit()),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsValue(
                  label: teksty.listeningOn,
                  value: _adresy.isEmpty
                      ? teksty.listeningPort(port)
                      : _adresy.map((a) => '$a:$port').join('\n'),
                ),
                SettingsValue(
                  label: teksty.deviceIdentifier,
                  value: services.identity.guid,
                ),
                // Odcisk własnego klucza: to jego dyktujesz rozmówcy, gdy
                // chcecie sprawdzić, czy rozmawiacie ze sobą.
                SettingsValue(
                  label: teksty.fingerprintMine,
                  value: ChattCrypto.fingerprint(services.identity.publicKey),
                ),
              ],
            ),
          ),
        ),
        SettingsHelp(teksty.manualPairingHint),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _cleanUpPeers,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: Text(teksty.cleanUpDevices),
        ),
        SettingsHelp(teksty.cleanUpHelp),
      ],
    );
  }
}
