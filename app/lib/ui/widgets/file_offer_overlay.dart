import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_services.dart';
import '../../services/providers.dart';
import 'common.dart';

/// Prośba o zgodę na odbiór pliku. Wisi nad całą aplikacją, bo plik może
/// przyjść, gdy jesteśmy na dowolnym ekranie — i pojawia się ZANIM nadawca
/// prześle choćby bajt. Przycisk „Akceptuj" ma fokus, więc wystarczy Enter.
class FileOfferOverlay extends ConsumerWidget {
  final Widget child;

  const FileOfferOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(appServicesProvider);
    return Stack(
      children: [
        child,
        ValueListenableBuilder<List<PendingFileOffer>>(
          valueListenable: services.pendingOffers,
          builder: (context, offers, _) {
            if (offers.isEmpty) return const SizedBox.shrink();
            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  // Pytamy o jeden plik naraz: kolejka kart potrafiłaby
                  // wyjść poza ekran (a wtedy nie da się już nic kliknąć).
                  child: Column(
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
                  ),
                ),
              ),
            );
          },
        ),
      ],
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
