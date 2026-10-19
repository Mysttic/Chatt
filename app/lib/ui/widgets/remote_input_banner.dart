import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_services.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';

/// Pasek „Pisze: …" ze Stopem u góry aplikacji, przez całą zgodę na pisanie
/// na tym urządzeniu, na każdym ekranie.
///
/// Pisanie trafia także do pól samego Chatt, więc przy oknie na wierzchu
/// pasek mówi, że pisze się do Chatt. Poza oknem wskaźnikiem jest pasek
/// natywny: pływający na Windows, klawiatura Chatt i powiadomienie na
/// Androidzie.
///
/// Należy do dodatku klawiatury: przy wyłączonym nie zajmuje miejsca.
class RemoteInputBanner extends ConsumerWidget {
  final Widget child;

  const RemoteInputBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(appServicesProvider);
    return ListenableBuilder(
      listenable: Listenable.merge(
          [services.keyboardAddon, services.incomingRemoteInput]),
      builder: (context, _) {
        final pisze = services.keyboardAddon.value
            ? services.incomingRemoteInput.value
            : null;
        final media = MediaQuery.of(context);
        // Stały układ: aplikacja zostaje w tym samym miejscu drzewa, więc
        // pojawienie się paska nie przebudowuje nawigacji od zera.
        return Column(
          children: [
            if (pisze == null)
              const SizedBox.shrink()
            else
              _Pasek(
                pisze: pisze,
                onStop: services.stopIncomingRemoteInput,
              ),
            Expanded(
              // Pasek zajął górny margines (pasek stanu na telefonie), więc
              // ekrany pod nim go już nie doliczają.
              child: MediaQuery(
                data: pisze == null
                    ? media
                    : media.removePadding(removeTop: true),
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Pasek extends StatelessWidget {
  final IncomingRemoteInput pisze;
  final VoidCallback onStop;

  const _Pasek({required this.pisze, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cel = pisze.target;
    final aplikacja = cel.appLabel.isNotEmpty ? cel.appLabel : cel.app;
    // Aplikacja z nazwy tylko wtedy, gdy do niej naprawdę się pisze, jak na
    // pasku natywnym. Bez strzałki z tamtego paska: fonty stylów jej nie
    // mają.
    final napis = (cel.active && aplikacja.isNotEmpty)
        ? context.l10n.remoteInputBannerTarget(pisze.peerName, aplikacja)
        : context.l10n.remoteInputActive(pisze.peerName);
    // Czemu nic się nie wpisuje, gdy widać to z tego ekranu.
    final uwaga = cel.elevated ? context.l10n.remoteKeyboardElevated : null;
    final kolor = scheme.onPrimaryContainer;
    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Icon(Icons.keyboard, color: kolor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      napis,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: kolor, fontWeight: FontWeight.w600),
                    ),
                    if (uwaga != null)
                      Text(
                        uwaga,
                        style: TextStyle(color: kolor, fontSize: 12),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                onPressed: onStop,
                child: Text(context.l10n.remoteInputStop),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
