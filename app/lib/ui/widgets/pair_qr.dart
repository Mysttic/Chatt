import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/pair_link.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';

/// Kod QR tego urządzenia do zeskanowania przez drugie.
///
/// W kodzie nie ma nic tajnego: klucz publiczny i adres. Cała wartość jest
/// w tym, **jak** trafia do drugiej strony: kto go zeskanował, ten patrzył na
/// ten ekran, więc wie, że klucz pochodzi stąd, a nie od kogoś po drodze.
Future<void> showPairQr(BuildContext context) => showDialog<void>(
      context: context,
      builder: (dialog) => const _PairQrDialog(),
    );

class _PairQrDialog extends ConsumerStatefulWidget {
  const _PairQrDialog();

  @override
  ConsumerState<_PairQrDialog> createState() => _PairQrDialogState();
}

class _PairQrDialogState extends ConsumerState<_PairQrDialog> {
  List<String> _adresy = const [];
  int _wybrany = 0;

  @override
  void initState() {
    super.initState();
    // Adresów może być kilka (Wi-Fi, kabel, wirtualne karty od Dockera czy
    // WSL). Drugie urządzenie musi dostać ten, pod którym naprawdę nas widzi,
    // więc dajemy je do przełączenia zamiast zgadywać.
    ref.read(appServicesProvider).localAddresses().then((adresy) {
      if (mounted) setState(() => _adresy = adresy);
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.read(appServicesProvider);
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(context.l10n.qrShowTitle),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_adresy.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  // Czytniki lubią ciemny wzór na jasnym tle, więc kod ma
                  // własne, białe tło niezależnie od motywu aplikacji.
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: PairLink.encode(
                    identity: services.identity,
                    address: _adresy[_wybrany],
                  ),
                  size: 240,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${_adresy[_wybrany]}:${services.identity.tcpPort}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              if (_adresy.length > 1)
                TextButton.icon(
                  onPressed: () => setState(
                      () => _wybrany = (_wybrany + 1) % _adresy.length),
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(context.l10n.qrOtherAddress),
                ),
              const SizedBox(height: 8),
              Text(
                context.l10n.qrShowBody,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}

/// Czy na tej platformie da się w ogóle skanować. Na desktopie nie ma aparatu,
/// więc pokazywanie przycisku byłoby obietnicą bez pokrycia.
bool get canScanQr => Platform.isAndroid || Platform.isIOS;
