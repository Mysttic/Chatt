import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../network/protocol.dart' show PairOutcome;
import '../../services/app_services.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import 'common.dart';
import 'toasts.dart';

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
            child: Align(
              alignment: Alignment.topCenter,
              // Na szerokim oknie karta rozciągnięta na cały monitor czyta
              // się jak baner; na telefonie granica i tak nie wchodzi w grę.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
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
                            pairing: pairings.first,
                            services: services,
                          ),
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
                                context.l10n
                                    .moreFilesWaiting(offers.length - 1),
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
  bool _checking = false;
  PairOutcome? _outcome;

  Future<void> _confirm() async {
    setState(() {
      _checking = true;
      _outcome = null;
    });
    final outcome =
        await widget.services.confirmPairing(widget.pairing.peerGuid);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _outcome = outcome;
    });
    if (outcome == PairOutcome.accepted) {
      showToast(context.l10n.pairedWith(widget.pairing.peerName));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blad = switch (_outcome) {
      null || PairOutcome.accepted => null,
      PairOutcome.rejected => context.l10n.pairRejected,
      PairOutcome.expired => context.l10n.pairCodeExpired,
      PairOutcome.unreachable => context.l10n.pairPeerUnreachable,
    };
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
                Icon(
                  widget.pairing.alreadyPaired
                      ? Icons.gpp_maybe_outlined
                      : Icons.shield_outlined,
                  color: widget.pairing.alreadyPaired
                      ? scheme.error
                      : scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.pairing.fromScan
                        ? context.l10n.pairScannedTitle(widget.pairing.peerName)
                        : context.l10n.pairRequest(widget.pairing.peerName),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            // Ponowne parowanie znaczy nowy klucz, a prośbę mógł przysłać
            // ktokolwiek — sama nazwa niczego nie dowodzi.
            if (widget.pairing.alreadyPaired) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.pairAgainWarning,
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            Text(widget.pairing.fromScan
                ? context.l10n.pairScannedBody
                : context.l10n.pairCompareHint),
            const SizedBox(height: 8),
            // Kod rozstrzelony i wyśrodkowany: ma się dać porównać rzutem oka
            // na dwa ekrany obok siebie.
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.pairing.code.split('').join(' '),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 2,
                    ),
              ),
            ),
            if (blad != null) ...[
              const SizedBox(height: 8),
              Text(blad, style: TextStyle(color: scheme.error, fontSize: 13)),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _checking
                      ? null
                      : () => widget.services.cancelPairing(
                            widget.pairing.peerGuid,
                          ),
                  child: Text(widget.pairing.fromScan
                      ? context.l10n.cancel
                      : context.l10n.pairCodesDiffer),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _checking ? null : _confirm,
                  child: Text(_checking
                      ? context.l10n.pairChecking
                      : widget.pairing.fromScan
                          ? context.l10n.pairScannedConfirm
                          : context.l10n.pairCodesMatch),
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
                      Text(
                        context.l10n.fileOfferTitle(offer.peerName),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        offer.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        resumed
                            ? context.l10n.fileOfferResume(
                                formatFileSize(offer.fileSize),
                                formatFileSize(offer.resumeFrom),
                              )
                            : formatFileSize(offer.fileSize),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      if (!offer.fromVerifiedPeer)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.report_outlined,
                                size: 14,
                                color: scheme.error,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  context.l10n.unpairedWarning,
                                  style: TextStyle(
                                    color: scheme.error,
                                    fontSize: 11,
                                  ),
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
                  onPressed: () =>
                      services.respondToOffer(offer.messageGuid, accept: false),
                  child: Text(context.l10n.reject),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  focusNode: _acceptFocus,
                  onPressed: () =>
                      services.respondToOffer(offer.messageGuid, accept: true),
                  child: Text(context.l10n.accept),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
