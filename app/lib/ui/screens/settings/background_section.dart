import 'package:flutter/material.dart';

import '../../l10n_context.dart';
import 'settings_widgets.dart';

/// Kategoria Nasłuch w tle. Android: usługa pierwszoplanowa i wyjątek od
/// optymalizacji baterii. Windows: start razem z systemem i zasobnik.
/// Stan baterii i autostartu trzyma ekran Ustawień, bo z niego powstaje też
/// streszczenie na liście.
class BackgroundSection extends StatelessWidget {
  final TargetPlatform platforma;
  final bool batteryOptimized;
  final bool autostart;
  final VoidCallback onBatteryExemption;
  final ValueChanged<bool> onAutostart;

  const BackgroundSection({
    super.key,
    required this.platforma,
    required this.batteryOptimized,
    required this.autostart,
    required this.onBatteryExemption,
    required this.onAutostart,
  });

  @override
  Widget build(BuildContext context) {
    final teksty = context.l10n;
    return SettingsPage(
      children: [
        if (platforma == TargetPlatform.android)
          SettingsStatusCard(
            icon: batteryOptimized
                ? Icons.battery_alert_outlined
                : Icons.check_circle_outline,
            bad: batteryOptimized,
            text: batteryOptimized
                ? teksty.batteryOptimizedWarning
                : teksty.batteryExemptOk,
            action: batteryOptimized
                ? FilledButton.tonalIcon(
                    onPressed: onBatteryExemption,
                    icon: const Icon(Icons.battery_saver_outlined),
                    label: Text(teksty.batteryExemptButton),
                  )
                : null,
          ),
        // Na Androidzie ciągłość nasłuchu załatwia usługa pierwszoplanowa,
        // a zasobnika nie ma.
        if (platforma == TargetPlatform.windows) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: autostart,
            onChanged: onAutostart,
            secondary: const Icon(Icons.rocket_launch_outlined),
            title: Text(teksty.startWithWindows),
            subtitle: Text(teksty.startWithWindowsHelp),
          ),
          const SizedBox(height: 8),
          SettingsNote(
            icon: Icons.dashboard_customize_outlined,
            text: teksty.trayHint,
          ),
        ],
      ],
    );
  }
}
