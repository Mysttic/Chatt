import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/pair_link.dart';
import '../../data/db.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../widgets/common.dart';

/// Skanowanie kodu QR z drugiego urządzenia. Zwraca rozmówcę, którego
/// tożsamość została właśnie potwierdzona, albo null (rezygnacja lub błąd).
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// Aparat zgłasza ten sam kod wiele razy na sekundę, a my za pierwszym
  /// razem idziemy do sieci: bez tej blokady poleciałoby kilkanaście prób.
  bool _zajete = false;
  String? _blad;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _odczytano(BarcodeCapture zdarzenie) async {
    if (_zajete) return;
    final surowy = zdarzenie.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .map(PairLink.decode)
        .whereType<PairLink>()
        .firstOrNull;
    // Aparat widzi też kody, które nas nie dotyczą, te po prostu mijamy,
    // bez komunikatu, żeby nie migać błędem przy każdej naklejce.
    if (surowy == null) return;

    setState(() {
      _zajete = true;
      _blad = null;
    });
    await _controller.stop();

    final peer = await ref.read(appServicesProvider).pairByScan(surowy);
    if (!mounted) return;
    if (peer == null) {
      setState(() {
        _zajete = false;
        _blad = context.l10n.qrScanFailed;
      });
      await _controller.start();
      return;
    }
    Navigator.pop<Peer>(context, peer);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.qrScanTitle)),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _odczytano),
          // Ramka celownika: bez niej nie wiadomo, gdzie trzymać telefon.
          IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            // Podgląd z aparatu idzie na cały ekran, więc podpowiedź trzeba
            // samemu odsunąć od paska gestów.
            bottom: 32 + bottomSystemInset(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_blad != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _blad!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    context.l10n.qrScanHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
