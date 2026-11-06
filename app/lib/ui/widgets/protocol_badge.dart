import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../network/transport.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../styles.dart';

/// Znacznik drogi, którą idzie rozmowa.
///
/// Bluetooth jest kilkadziesiąt razy wolniejszy od sieci, więc użytkownik ma
/// prawo wiedzieć, czemu ten sam plik raz leci sekundę, a raz minutę. Issue
/// #27 stawia to wprost: różnicę trzeba pokazać.
///
/// Stoi na dwóch źródłach, bo każde mówi o czym innym: żywe łącze radiowe
/// wie, co jest teraz, a zapisany protokół wie, czym poszło ostatnio.
///
/// Należy do dodatku Bluetooth. Przy wyłączonym dodatku nie zajmuje nawet
/// miejsca, razem z odstępem [padding].
class ProtocolBadge extends ConsumerWidget {
  final Peer peer;

  /// Sama ikona, bez podpisu: do ciasnych miejsc, jak wiersz listy rozmów.
  final bool compact;

  /// Odstęp od sąsiadów. Znika razem ze znacznikiem.
  final EdgeInsetsGeometry padding;

  const ProtocolBadge({
    super.key,
    required this.peer,
    this.compact = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.read(appServicesProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([
        services.bluetoothAddon,
        services.bluetoothRevision,
        services.internetAddon,
        services.internetRevision,
      ]),
      builder: (context, _) {
        // Znacznik ma sens tylko wtedy, gdy jest więcej niż jedna droga:
        // dopóki żaden dodatek nie działa, sieć lokalna jest jedyną i nie ma
        // czego rozróżniać.
        if (!services.bluetoothAddon.value && !services.internetAddon.value) {
          return const SizedBox.shrink();
        }
        final radiem = services.isLinkedByBluetooth(peer) ||
            peer.lastProtocol == PeerProtocol.bluetooth.index;
        final internetem = !radiem &&
            (services.isLinkedByInternet(peer) ||
                peer.lastProtocol == PeerProtocol.internet.index);
        final scheme = Theme.of(context).colorScheme;
        final wyrozniona = radiem || internetem;
        final kolor =
            wyrozniona ? scheme.tertiary : scheme.onSurfaceVariant;
        final ikona = radiem
            ? Icons.bluetooth
            : (internetem ? Icons.public : Icons.wifi);
        final podpis = radiem
            ? context.l10n.viaBluetooth
            : (internetem ? context.l10n.viaInternet : context.l10n.viaWifi);

        // Sama ikona, także w nagłówku rozmowy: podpis jest w podpowiedzi
        // i dla czytnika ekranu. Na liście styl dokłada kafelek (Cisza)
        // albo obrys (Precyzja).
        final k = ChattTokens.of(context);
        final ikonaW = Icon(ikona,
            size: compact ? k.routeIcon : 18,
            color: kolor,
            semanticLabel: podpis);
        final kafelek = compact &&
            (k.routeBackground != null || k.routeBorder != null);
        return Padding(
          padding: padding,
          child: Tooltip(
            message: podpis,
            child: kafelek
                ? Container(
                    width: k.routeBox,
                    height: k.routeBox,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: k.routeBackground,
                      borderRadius: BorderRadius.circular(k.routeRadius),
                      border: k.routeBorder == null
                          ? null
                          : Border.all(color: k.routeBorder!),
                    ),
                    child: ikonaW,
                  )
                : ikonaW,
          ),
        );
      },
    );
  }
}
