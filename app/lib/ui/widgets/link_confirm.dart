import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../core/links.dart';
import '../l10n_context.dart';
import 'toasts.dart';

/// Pytanie zadawane przed opuszczeniem aplikacji: „czy na pewno chcesz przejść
/// do tej strony?".
///
/// Odnośnik w rozmowie przyszedł od kogoś z sieci, a napis w wiadomości nie
/// musi mówić prawdy o tym, dokąd prowadzi. Dlatego okienko pokazuje **adres
/// rozłożony na części**: osobno serwer, do którego naprawdę się idzie, i
/// osobno cały adres, a nad nimi ostrzeżenia o sztuczkach, które właśnie na
/// tym polegają (login przed nazwą serwera, litery z obcego alfabetu).
///
/// Nic się nie otwiera, dopóki użytkownik nie naciśnie „Otwórz".
Future<void> confirmAndOpenLink(BuildContext context, Uri uri) async {
  final teksty = context.l10n;
  final zgoda = await showDialog<bool>(
    context: context,
    builder: (dialog) => _LinkConfirmDialog(uri: uri),
  );
  if (zgoda != true) return;

  final wynik = await openExternalLink(uri);
  switch (wynik) {
    case LinkOpenResult.ok:
      break;
    case LinkOpenResult.unsupported:
    case LinkOpenResult.failed:
      // Bez przeglądarki zostaje adres do skopiowania: to nadal jest droga
      // do celu, tylko dłuższa.
      showToast(
        teksty.linkOpenFailed,
        actionLabel: teksty.copy,
        onAction: () => Clipboard.setData(ClipboardData(text: uri.toString())),
      );
  }
}

class _LinkConfirmDialog extends StatelessWidget {
  final Uri uri;

  const _LinkConfirmDialog({required this.uri});

  @override
  Widget build(BuildContext context) {
    final teksty = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final ostrzezenia = warningsFor(uri);
    final serwer = uri.host + (uri.hasPort ? ':${uri.port}' : '');

    return AlertDialog(
      icon: const Icon(Icons.open_in_new),
      title: Text(teksty.linkConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(teksty.linkConfirmHost,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 2),
            // Nazwa serwera osobno i większa niż reszta: to jedyna część
            // adresu, która decyduje, czyja to strona.
            SelectableText(
              serwer,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(teksty.linkConfirmFull,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              // Cały adres do przeczytania i do zaznaczenia. Ograniczony
              // wysokością, bo adres potrafi mieć kilometr.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: SelectableText(
                    uri.toString(),
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
              ),
            ),
            for (final ostrzezenie in ostrzezenia) ...[
              const SizedBox(height: 10),
              _Warning(warning: ostrzezenie),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(teksty.cancel),
        ),
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: uri.toString()));
            Navigator.of(context).pop(false);
            showToast(teksty.linkCopied);
          },
          child: Text(teksty.linkCopy),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(teksty.linkOpen),
        ),
      ],
    );
  }
}

/// Jedno ostrzeżenie: ikona i zdanie o tym, co jest z adresem nie tak.
class _Warning extends StatelessWidget {
  final LinkWarning warning;

  const _Warning({required this.warning});

  @override
  Widget build(BuildContext context) {
    final teksty = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    // Podszycie się pod cudzy serwer jest groźne, brak szyfrowania i adres
    // w sieci lokalnej to raczej „wiedz o tym", stąd dwa kolory.
    final powazne = warning == LinkWarning.userInfo ||
        warning == LinkWarning.nonAsciiHost;
    final (ikona, tekst) = switch (warning) {
      LinkWarning.userInfo => (Icons.report_gmailerrorred, teksty.linkWarnUserInfo),
      LinkWarning.nonAsciiHost => (Icons.translate, teksty.linkWarnNonAscii),
      LinkWarning.insecure => (Icons.lock_open_outlined, teksty.linkWarnInsecure),
      LinkWarning.localAddress => (Icons.router_outlined, teksty.linkWarnLocal),
    };
    final kolor = powazne ? scheme.error : scheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ikona, size: 18, color: kolor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(tekst, style: TextStyle(color: kolor, fontSize: 12)),
        ),
      ],
    );
  }
}
