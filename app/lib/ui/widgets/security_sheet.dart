import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/crypto.dart';
import '../../core/identity.dart';
import '../../data/db.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import 'pair_qr.dart';

/// Panel „bezpieczeństwo rozmowy": w jakim stanie jest szyfrowanie i czyje
/// klucze są po obu stronach.
///
/// Odciski są tu po to, żeby dało się je porównać **kiedykolwiek**, a nie
/// tylko w oknie parowania. Jeśli kiedyś zaczniesz podejrzewać, że rozmawiasz
/// z kimś innym, odczytujesz odcisk na głos i sprawdzasz na drugim ekranie.
Future<void> showSecuritySheet(
  BuildContext context, {
  required Peer peer,
  required VoidCallback onPair,
  required VoidCallback onScan,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) =>
        _SecuritySheet(peer: peer, onPair: onPair, onScan: onScan),
  );
}

class _SecuritySheet extends ConsumerWidget {
  final Peer peer;
  final VoidCallback onPair;
  final VoidCallback onScan;

  const _SecuritySheet(
      {required this.peer, required this.onPair, required this.onScan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.read(appServicesProvider);
    final scheme = Theme.of(context).colorScheme;
    final klucz = DeviceIdentity.decodeKey(peer.publicKey);

    final (ikona, kolor, naglowek, opis) = switch ((klucz.isNotEmpty, peer.verified)) {
      (false, _) => (
          Icons.gpp_bad_outlined,
          scheme.error,
          context.l10n.securityNoEncryptionTitle,
          context.l10n.securityNoEncryptionBody,
        ),
      (true, false) => (
          Icons.lock_outline,
          scheme.primary,
          context.l10n.securityEncryptedTitle,
          context.l10n.securityEncryptedBody,
        ),
      (true, true) => (
          Icons.verified_user,
          Colors.green,
          context.l10n.securityVerifiedTitle,
          context.l10n.securityVerifiedBody,
        ),
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(ikona, color: kolor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(naglowek,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(opis, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            if (klucz.isNotEmpty)
              _Odcisk(
                etykieta: context.l10n.fingerprintOf(peer.name),
                odcisk: ChattCrypto.fingerprint(klucz),
              ),
            const SizedBox(height: 12),
            _Odcisk(
              etykieta: context.l10n.fingerprintMine,
              odcisk: ChattCrypto.fingerprint(services.identity.publicKey),
            ),
            const SizedBox(height: 20),
            Text(context.l10n.fingerprintHelp,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            if (klucz.isNotEmpty && !peer.verified) ...[
              const SizedBox(height: 20),
              // Kod QR jest pewniejszy od porównywania sześciu cyfr (napastnik
              // nie ma szansy jednej na milion, tylko zero), więc idzie
              // pierwszy. Porównanie kodu zostaje dla par bez aparatu.
              if (canScanQr)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onScan();
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(context.l10n.qrScanTitle),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  showPairQr(context);
                },
                icon: const Icon(Icons.qr_code_2),
                label: Text(context.l10n.qrShowTitle),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onPair();
                },
                icon: const Icon(Icons.shield_outlined),
                label: Text(context.l10n.pairTooltip),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Odcisk w jednym wierszu z możliwością skopiowania — łatwiej przedyktować
/// przez telefon niż przepisywać z ekranu.
class _Odcisk extends StatelessWidget {
  final String etykieta;
  final String odcisk;

  const _Odcisk({required this.etykieta, required this.odcisk});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etykieta,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: odcisk));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.copied)),
            );
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              odcisk,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 17,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
