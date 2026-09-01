import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_services.dart';
import '../../services/providers.dart';
import 'common.dart';

/// Prośby wymagające decyzji „tu i teraz": zgoda na odbiór pliku i kod
/// parowania. Wiszą nad całą aplikacją, bo mogą przyjść, gdy jesteśmy na
/// dowolnym ekranie, a prośba o plik pojawia się ZANIM nadawca prześle
/// choćby bajt.
class PromptOverlay extends ConsumerWidget {
  final Widget child;

  const PromptOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(appServicesProvider);
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<List<PendingPairing>>(
                    valueListenable: services.pendingPairings,
                    builder: (context, pairings, _) => pairings.isEmpty
                        ? const SizedBox.shrink()
                        : _PairingCard(
                            pairing: pairings.first, services: services),
                  ),
                  ValueListenableBuilder<List<PendingFileOffer>>(
                    valueListenable: services.pendingOffers,
                    builder: (context, offers, _) {
                      if (offers.isEmpty) return const SizedBox.shrink();
                      // Pytamy o jeden plik naraz: kolejka kart potrafiłaby
                      // wyjść poza ekran (a wtedy nie da się już nic kliknąć).
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _OfferCard(offer: offers.first, services: services),
                          if (offers.length > 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Czeka jeszcze ${offers.length - 1} '
                                '${offers.length == 2 ? "plik" : "plików"}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Drugie urządzenie pokazuje kod, tutaj się go przepisuje.
class _PairingCard extends StatefulWidget {
  final PendingPairing pairing;
  final AppServices services;

  const _PairingCard({required this.pairing, required this.services});

  @override
  State<_PairingCard> createState() => _PairingCardState();
}

class _PairingCardState extends State<_PairingCard> {
  final _code = TextEditingController();
  bool _checking = false;
  bool _wrong = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _checking = true;
      _wrong = false;
    });
    final ok = await widget.services
        .confirmPairing(widget.pairing.peerGuid, _code.text);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _wrong = !ok;
    });
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sparowano z ${widget.pairing.peerName}'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 6,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('${widget.pairing.peerName} chce się sparować',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'Kod z drugiego urządzenia',
                errorText: _wrong ? 'Kod się nie zgadza' : null,
                border: const OutlineInputBorder(),
                counterText: '',
              ),
              onSubmitted: (_) => _confirm(),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _checking
                      ? null
                      : () => widget.services
                          .cancelPairing(widget.pairing.peerGuid),
                  child: const Text('Anuluj'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _checking ? null : _confirm,
                  child: Text(_checking ? 'Sprawdzam…' : 'Potwierdź'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatefulWidget {
  final PendingFileOffer offer;
  final AppServices services;

  const _OfferCard({required this.offer, required this.services});

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  /// Fokus bierzemy ręcznie: `autofocus` nie działa w poddrzewie wstrzykiwanym
  /// przez `MaterialApp.builder` (jest poza zakresem fokusu nawigatora),
  /// a bez fokusu Enter nie akceptuje pliku.
  final _acceptFocus = FocusNode(debugLabel: 'akceptuj plik');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _acceptFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _acceptFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final services = widget.services;
    final scheme = Theme.of(context).colorScheme;
    final resumed = offer.resumeFrom > 0;

    return Card(
      elevation: 6,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.download_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${offer.peerName} chce wysłać plik',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(offer.fileName,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(
                        resumed
                            ? '${formatFileSize(offer.fileSize)} — wznowienie, '
                                'masz już ${formatFileSize(offer.resumeFrom)}'
                            : formatFileSize(offer.fileSize),
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                      if (!offer.fromVerifiedPeer)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.report_outlined,
                                  size: 14, color: scheme.error),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Urządzenie niesparowane — nazwę można sobie '
                                  'ustawić dowolną',
                                  style: TextStyle(
                                      color: scheme.error, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => services.respondToOffer(offer.messageGuid,
                      accept: false),
                  child: const Text('Odrzuć'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  focusNode: _acceptFocus,
                  onPressed: () =>
                      services.respondToOffer(offer.messageGuid, accept: true),
                  child: const Text('Akceptuj'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
