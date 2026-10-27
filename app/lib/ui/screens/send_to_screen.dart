import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/share_intake.dart';
import '../../data/db.dart';
import '../../services/presence.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../styles.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import 'nearby_screen.dart';

/// Odstęp między kartami rozmów, ten sam co na liście rozmów.
const _odstepKart = 8.0;

/// Wysokość rozszerzonego przycisku „W pobliżu" (Material 3).
const _wysokoscPrzycisku = 56.0;

/// Wybór rozmowy dla treści udostępnionej z innej aplikacji (issue #60).
///
/// U góry to, co przyszło: tekst albo liczba plików. Niżej rozmowy od
/// ostatniej, z szukaniem po nazwie, a przycisk „W pobliżu" prowadzi do
/// urządzenia, z którym rozmowy jeszcze nie ma. Wybór oddaje rozmowę
/// [onChosen]. Ten ekran niczego nie wysyła: treść czeka w rozmowie na
/// „Wyślij".
///
/// Zamknięcie bez wyboru odrzuca treść razem z kopiami plików.
class SendToScreen extends ConsumerStatefulWidget {
  final IncomingShare share;
  final void Function(int conversationId, Peer peer) onChosen;

  const SendToScreen({super.key, required this.share, required this.onChosen});

  @override
  ConsumerState<SendToScreen> createState() => _SendToScreenState();
}

class _SendToScreenState extends ConsumerState<SendToScreen> {
  final _search = TextEditingController();

  /// Zapamiętany przy wejściu: [dispose] odrzuca przez niego treść.
  late final ShareIntake _intake;

  /// Rozmowa wybrana: treść przechodzi do niej i nie wolno jej odrzucić.
  bool _wybrano = false;

  @override
  void initState() {
    super.initState();
    _intake = ref.read(shareIntakeProvider);
  }

  @override
  void dispose() {
    _search.dispose();
    if (!_wybrano) unawaited(_intake.discard(widget.share.id));
    super.dispose();
  }

  void _wybierz(int conversationId, Peer peer) {
    if (_wybrano) return;
    _wybrano = true;
    widget.onChosen(conversationId, peer);
  }

  /// Urządzenie bez rozmowy: „W pobliżu" w trybie wyboru oddaje je tutaj.
  Future<void> _wPoblizu() async {
    final peer = await Navigator.of(context).push<Peer>(
      ChattPageRoute(builder: (_) => const NearbyScreen(choose: true)),
    );
    if (peer == null || !mounted) return;
    final conversationId =
        await ref.read(appServicesProvider).openConversationWith(peer);
    if (!mounted) return;
    _wybierz(conversationId, peer);
  }

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(conversationSummariesProvider);
    // Obecność pomaga wybrać urządzenie, które teraz odbierze.
    final presence = ref.watch(presenceProvider).value ?? const {};
    final query = _search.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.l10n.close,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(context.l10n.shareSendToTitle),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_search),
        label: Text(context.l10n.nearbyButton),
        onPressed: _wPoblizu,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: _Zapowiedz(share: widget.share),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.l10n.searchConversationsHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: summaries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text(context.l10n.errorWithDetails('$error'))),
              data: (all) {
                if (all.isEmpty) return const _BrakRozmow();
                final items = query.isEmpty
                    ? all
                    : all.where((item) => _pasuje(item.peer, query)).toList();
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        context.l10n.searchNothingFound(_search.text.trim()),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  // Ostatnia karta da się przewinąć spod przycisku
                  // „W pobliżu".
                  padding: EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    _odstepKart +
                        _wysokoscPrzycisku +
                        kFloatingActionButtonMargin +
                        bottomSystemInset(context),
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: _odstepKart),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _KartaRozmowy(
                      peer: item.peer,
                      online: presence[item.peer.guid],
                      onTap: () => _wybierz(item.conversationId, item.peer),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Szukanie po nazwie, także po nazwie nadanej rozmówcy w Chatcie.
bool _pasuje(Peer peer, String query) =>
    peer.displayName.toLowerCase().contains(query) ||
    peer.name.toLowerCase().contains(query);

/// To, co przyszło z innej aplikacji: początek tekstu i liczba plików.
class _Zapowiedz extends StatelessWidget {
  final IncomingShare share;

  const _Zapowiedz({required this.share});

  @override
  Widget build(BuildContext context) {
    final k = ChattTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tekst = share.text?.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: k.surface2,
        borderRadius: BorderRadius.circular(k.radiusCard),
        border: Border.all(color: k.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tekst != null && tekst.isNotEmpty)
            Text(tekst, maxLines: 4, overflow: TextOverflow.ellipsis),
          if (tekst != null && tekst.isNotEmpty && share.fileCount > 0)
            const SizedBox(height: 6),
          if (share.fileCount > 0)
            Row(
              children: [
                Icon(Icons.attach_file, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text(context.l10n.shareFiles(share.fileCount)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Rozmowa na liście wyboru: awatar, nazwa z tarczą i obecność. Karta
/// w wyglądzie kart z listy rozmów.
class _KartaRozmowy extends StatelessWidget {
  final Peer peer;
  final bool? online;
  final VoidCallback onTap;

  const _KartaRozmowy({required this.peer, required this.online, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final k = ChattTokens.of(context);
    final ksztalt = BorderRadius.circular(k.radiusRow);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: ksztalt, boxShadow: k.shadow1),
      child: Material(
        color: k.surface1,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: ksztalt,
          // Precyzja odcina karty obrysem, bo cienia nie ma.
          side: k.style == AppStyle.precyzja
              ? BorderSide(color: k.outline)
              : BorderSide.none,
        ),
        child: ListTile(
          contentPadding: k.rowPadding,
          horizontalTitleGap: k.rowGap,
          visualDensity: VisualDensity.standard,
          leading: InitialsAvatar(name: peer.displayName, online: online),
          title: PeerName(name: peer.displayName, verified: peer.verified),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Jeszcze żadnej rozmowy: zostaje „W pobliżu".
class _BrakRozmow extends StatelessWidget {
  const _BrakRozmow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              context.l10n.shareNoConversations,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
