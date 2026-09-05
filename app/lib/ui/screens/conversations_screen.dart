import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/search.dart';
import '../../core/version.dart';
import '../../data/db.dart';
import '../../services/presence.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'nearby_screen.dart';
import 'settings_screen.dart';
import '../widgets/toasts.dart';

/// Usunięcie rozmowy kasuje też urządzenie z listy znanych, jedno bez
/// drugiego nie ma sensu, bo rozmowa i tak odtworzyłaby się przy pierwszym
/// kontakcie. Pytamy, bo idą z tym wiadomości.
Future<void> _confirmDelete(
    BuildContext context, WidgetRef ref, Peer peer) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(context.l10n.deleteConversationTitle(peer.displayName)),
      content: Text(context.l10n.deleteConversationBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(context.l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final teksty = context.l10n;
  final nazwa = peer.displayName;
  await ref.read(appServicesProvider).forgetPeer(peer);
  showToast(teksty.conversationDeleted(nazwa));
}

/// Ekran główny: lista konwersacji (odpowiednik ListOfConversation.PNG).
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  final _search = TextEditingController();
  bool _searching = false;

  /// Rozmowa otwarta w prawym panelu. Ma sens tylko na szerokim oknie:
  /// na wąskim rozmowa jest osobnym ekranem na stosie nawigacji.
  int? _wybranaRozmowa;
  Peer? _wybranyRozmowca;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _search.clear();
    });
  }

  void _otworz(int conversationId, Peer peer) {
    if (czyDwupanel(context)) {
      setState(() {
        _wybranaRozmowa = conversationId;
        _wybranyRozmowca = peer;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(conversationId: conversationId, peer: peer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _lista(context);
    if (!czyDwupanel(context)) return lista;

    // Wybrana rozmowa mogła zniknąć (usunięcie rozmówcy), wtedy wracamy
    // do pustego panelu zamiast trzymać wpis, którego już nie ma.
    final rozmowa = _wybranaRozmowa;
    final rozmowca = _wybranyRozmowca;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(width: 360, child: lista),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: rozmowa == null || rozmowca == null
                ? const _NoSelection()
                : ChatScreen(
                    // Klucz po rozmowie: przełączenie ma zbudować ekran od
                    // nowa, a nie doklejać wiadomości do poprzedniego stanu.
                    key: ValueKey(rozmowa),
                    conversationId: rozmowa,
                    peer: rozmowca,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _lista(BuildContext context) {
    final summaries = ref.watch(conversationSummariesProvider);
    // Obecność odpytuje sieć tylko dopóki ktoś patrzy na listę.
    final presence = ref.watch(presenceProvider).value ?? const {};
    final query = _search.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.l10n.searchConversationsHint,
                  border: InputBorder.none,
                ),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(context.l10n.appTitle),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      appVersion,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: _searching
                ? context.l10n.close
                : context.l10n.searchConversationsTooltip,
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
          IconButton(
            tooltip: context.l10n.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_search),
        label: Text(context.l10n.nearbyButton),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NearbyScreen()),
        ),
      ),
      body: summaries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(context.l10n.errorWithDetails('$error'))),
        data: (all) {
          if (all.isEmpty) {
            return const _EmptyState();
          }
          final items = query.isEmpty
              ? all
              : all.where((item) => conversationMatches(item, query)).toList();
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  context.l10n.searchNothingFound(_search.text.trim()),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.separated(
            // Ostatnia rozmowa nie może chować się pod paskiem gestów.
            padding: EdgeInsets.only(bottom: bottomSystemInset(context)),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: InitialsAvatar(
                  name: item.peer.displayName,
                  online: presence[item.peer.guid],
                ),
                title: PeerName(
                  name: item.peer.displayName,
                  verified: item.peer.verified,
                ),
                subtitle: Text(
                  item.lastBody ?? item.peer.welcomeMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatWhen(item.lastAt),
                        style: Theme.of(context).textTheme.bodySmall),
                    if (item.unreadCount > 0) ...[
                      const SizedBox(height: 4),
                      Badge.count(count: item.unreadCount),
                    ],
                  ],
                ),
                selected: item.conversationId == _wybranaRozmowa &&
                    czyDwupanel(context),
                onTap: () => _otworz(item.conversationId, item.peer),
                onLongPress: () => _confirmDelete(context, ref, item.peer),
              );
            },
          );
        },
      ),
    );
  }
}

/// Prawy panel, dopóki nikt nie wybrał rozmowy.
class _NoSelection extends StatelessWidget {
  const _NoSelection();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              context.l10n.pickConversation,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum_outlined, size: 72, color: scheme.outline),
            const SizedBox(height: 16),
            Text(context.l10n.noConversationsTitle,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              context.l10n.noConversationsBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
