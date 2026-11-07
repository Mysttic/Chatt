import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../network/stun.dart' show NatMapping;
import '../../../services/providers.dart';
import '../../l10n_context.dart';
import '../../styles.dart';

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
      if (!on && mounted) setState(() => _natOpis = null);
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
                  _uwaga(scheme, Icons.battery_alert_outlined,
                      context.l10n.internetBatteryWarning),
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
