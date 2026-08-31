import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'nearby_screen.dart';
import 'settings_screen.dart';

/// Ekran główny: lista konwersacji (odpowiednik ListOfConversation.PNG).
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(conversationSummariesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chatt'),
        actions: [
          IconButton(
            tooltip: 'Ustawienia',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_search),
        label: const Text('W pobliżu'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NearbyScreen()),
        ),
      ),
      body: summaries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Błąd: $error')),
        data: (items) {
          if (items.isEmpty) {
            return const _EmptyState();
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
            Text('Brak rozmów',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Znajdź urządzenia w tej samej sieci Wi-Fi przyciskiem „W pobliżu” '
              'i napisz pierwszą wiadomość.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
