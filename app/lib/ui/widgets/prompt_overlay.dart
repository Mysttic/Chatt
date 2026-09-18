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
                constraints: BoxConstraints(
                  maxWidth: 560,
                  // Spis nazw z paczki i dwucyfrowe powiększenie czcionki
                  // potrafią urosnąć ponad wysokość ekranu, a wtedy przyciski
                  // „Przyjmij wszystkie" i „Odrzuć" lądują poza nim i nie da
                  // się już odpowiedzieć na nic.
                  maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                ),
                child: SingleChildScrollView(
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
                      // Pytamy o jedną prośbę naraz: kolejka kart potrafiłaby
                      // wyjść poza ekran (a wtedy nie da się już nic kliknąć).
                      // Czekające liczymy w plikach, nie w prośbach: jedna
                      // prośba bywa paczką kilkudziesięciu.
                      final czeka = offers
                          .skip(1)
                          .fold(0, (suma, offer) => suma + offer.fileCount);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Klucz po prośbie: bez niego Flutter podstawia
                          // nową prośbę pod ten sam stan karty, a razem z nim
                          // ognisko z przycisku poprzedniej. Enter wciśnięty
                          // do przyjęcia jednego pliku przyjmowałby wtedy
                          // paczkę, która właśnie weszła na jego miejsce.
                          _OfferCard(
                            key: ValueKey(offers.first.messageGuid),
                            offer: offers.first,
                            services: services,
                          ),
                          if (czeka > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                context.l10n.moreFilesWaiting(czeka),
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
            // ktokolwiek, sama nazwa niczego nie dowodzi.
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

  const _OfferCard(
      {super.key, required this.offer, required this.services});

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  /// Fokus bierzemy ręcznie: `autofocus` nie działa w poddrzewie wstrzykiwanym
  /// przez `MaterialApp.builder` (jest poza zakresem fokusu nawigatora),
  /// a bez fokusu Enter nie akceptuje pliku.
  final _acceptFocus = FocusNode(debugLabel: 'akceptuj plik');
  final _rejectFocus = FocusNode(debugLabel: 'odrzuć plik');

  @override
  void initState() {
    super.initState();
    // Karta wyskakuje nad całą aplikacją, poza zakresem tabulatora, więc bez
    // ogniska nie da się jej odpowiedzieć z klawiatury w ogóle. Ognisko
    // dostaje więc zawsze, tylko przy paczce nie „Przyjmij wszystkie", a
    // „Odrzuć": Enter wciśnięty do wysłania wiadomości ma najwyżej odmówić,
    // a nie przyjąć kilkadziesiąt plików naraz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (widget.offer.batch == null ? _acceptFocus : _rejectFocus).requestFocus();
    });
  }

  @override
  void dispose() {
    _acceptFocus.dispose();
    _rejectFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final services = widget.services;
    final scheme = Theme.of(context).colorScheme;
    final resumed = offer.resumeFrom > 0;
    final batch = offer.batch;

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
                        batch == null
                            ? context.l10n.fileOfferTitle(offer.peerName)
                            : context.l10n.fileOfferBatchTitle(
                                offer.peerName, batch.count),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      // Zgody na paczkę nie da się potem cofnąć, więc karta
                      // wymienia, na co ona idzie. Spis jest przewijany, bo
                      // sto nazw nie zmieści się na telefonie, a karta nie ma
                      // zasłonić całego ekranu.
                      if (batch == null)
                        Text(
                          offer.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 132),
                          child: Scrollbar(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final name in batch.names)
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Text(
                        batch != null
                            ? formatFileSize(batch.bytes)
                            : resumed
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
                  focusNode: _rejectFocus,
                  onPressed: () =>
                      services.respondToOffer(offer.messageGuid, accept: false),
                  child: Text(context.l10n.reject),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  focusNode: _acceptFocus,
                  onPressed: () =>
                      services.respondToOffer(offer.messageGuid, accept: true),
                  child: Text(batch == null
                      ? context.l10n.accept
                      : context.l10n.acceptAll),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
