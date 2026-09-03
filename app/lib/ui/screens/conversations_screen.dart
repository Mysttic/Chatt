import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/search.dart';
import '../../data/db.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'nearby_screen.dart';
import 'settings_screen.dart';

/// Usunięcie rozmowy kasuje też urządzenie z listy znanych — jedno bez
/// drugiego nie ma sensu, bo rozmowa i tak odtworzyłaby się przy pierwszym
/// kontakcie. Pytamy, bo idą z tym wiadomości.
Future<void> _confirmDelete(
    BuildContext context, WidgetRef ref, Peer peer) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(context.l10n.deleteConversationTitle(peer.name)),
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

  await ref.read(appServicesProvider).forgetPeer(peer);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.conversationDeleted(peer.name))));
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

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(conversationSummariesProvider);
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
            : Text(context.l10n.appTitle),
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
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: InitialsAvatar(name: item.peer.name),
                title: Text(item.peer.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
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
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      conversationId: item.conversationId,
                      peer: item.peer,
                    ),
                  ),
                ),
                onLongPress: () => _confirmDelete(context, ref, item.peer),
              );
            },
          );
        },
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
