import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../l10n_context.dart';
import '../../styles.dart';
import '../../widgets/common.dart';
import '../../widgets/toasts.dart';

/// Treść kategorii z polami, które zapisują się przy wyjściu z kategorii.
/// Ekran Ustawień woła [commit] przed zmianą kategorii i przed zamknięciem.
/// `false` zatrzymuje w kategorii, a błędne pole pokazuje swój komunikat.
mixin SettingsCommit<T extends StatefulWidget> on State<T> {
  Future<bool> commit();
}

/// Przewijana treść kategorii w kolumnie do 640 px: na telefonie cała
/// szerokość, w prawym panelu kolumna, którą da się czytać. W dwóch
/// panelach kolumna stoi przy lewej krawędzi, pod nazwą kategorii w pasku.
class SettingsPage extends StatelessWidget {
  final List<Widget> children;

  const SettingsPage({super.key, required this.children});

  static const double szerokosc = 640;

  @override
  Widget build(BuildContext context) => ContentColumn(
    maxWidth: szerokosc,
    alignment: czyDwupanel(context)
        ? AlignmentDirectional.topStart
        : Alignment.topCenter,
    child: ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomSystemInset(context)),
      children: children,
    ),
  );
}

/// Nagłówek grupy wewnątrz kategorii, w stylu (wersaliki w Precyzji).
class SettingsSubheader extends StatelessWidget {
  final String title;

  const SettingsSubheader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final k = ChattTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 8),
      child: Text(
        k.overlineText(title),
        style: k.overline.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Drobny opis pod kontrolką.
class SettingsHelp extends StatelessWidget {
  final String text;

  const SettingsHelp(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
    ),
  );
}

/// Ikona i drobny tekst obok: podpowiedź pod kontrolką.
class SettingsNote extends StatelessWidget {
  final IconData icon;
  final String text;

  const SettingsNote({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
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
    );
  }
}

/// Karta z ikoną stanu i opisem: zielone światło albo kłopot ([bad]).
class SettingsStatusCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool bad;
  final Widget? action;

  const SettingsStatusCard({
    super.key,
    required this.icon,
    required this.text,
    this.bad = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final przycisk = action;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: bad ? scheme.error : scheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
              ],
            ),
            if (przycisk != null) ...[const SizedBox(height: 12), przycisk],
          ],
        ),
      ),
    );
  }
}

/// Wartość techniczna z podpisem i przyciskiem kopiowania. Font o stałej
/// szerokości stylu, bo te wartości się przepisuje i porównuje.
class SettingsValue extends StatelessWidget {
  final String label;
  final String value;

  const SettingsValue({super.key, required this.label, required this.value});

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
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: ChattTokens.of(context).mono
                      .copyWith(color: scheme.onSurface),
                ),
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
              ClipboardData(text: value.replaceAll('\n', ' ')),
            );
            showToast(teksty.copied);
          },
        ),
      ],
    );
  }
}
