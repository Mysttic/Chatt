import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../services/app_services.dart';
import '../../services/providers.dart';
import '../widgets/common.dart';

/// Ekran rozmowy (odpowiednik Conversation.PNG): dymki, statusy dostarczenia,
/// ponawianie nieudanych wysyłek.
class ChatScreen extends ConsumerStatefulWidget {
  final int conversationId;
  final Peer peer;

  const ChatScreen({super.key, required this.conversationId, required this.peer});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool? _online;

  @override
  void initState() {
    super.initState();
    final services = ref.read(appServicesProvider);
    services.db.markConversationRead(widget.conversationId);
    services.isPeerOnline(widget.peer).then((online) {
      if (mounted) setState(() => _online = online);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    _input.clear();
    await ref.read(appServicesProvider).sendText(widget.conversationId, text);
  }

  Future<void> _attachFile() async {
    final file = await openFile();
    if (file == null) return;
    await ref.read(appServicesProvider).sendFile(widget.conversationId, file.path);
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.conversationId));

    // Nowa wiadomość przychodząca przy otwartym ekranie = od razu przeczytana.
    ref.listen(messagesProvider(widget.conversationId), (_, _) {
      ref.read(appServicesProvider).db.markConversationRead(widget.conversationId);
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            InitialsAvatar(name: widget.peer.name, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.peer.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    switch (_online) {
                      null => '${widget.peer.host}:${widget.peer.port}',
                      true => 'dostępny',
                      false => 'niedostępny',
                    },
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: switch (_online) {
                            true => Colors.green,
                            false => Theme.of(context).colorScheme.error,
                            null => null,
                          },
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Błąd: $error')),
              data: (items) => ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  // reverse: true -> element 0 na dole, więc czytamy od końca.
                  final message = items[items.length - 1 - index];
                  return _MessageBubble(
                    message: message,
                    services: ref.read(appServicesProvider),
                    onRetry: () => ref
                        .read(appServicesProvider)
                        .retryMessage(message.id),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Wyślij plik',
                    icon: const Icon(Icons.attach_file),
                    onPressed: _attachFile,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Napisz wiadomość…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Wyślij',
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final AppServices services;
  final VoidCallback onRetry;

  const _MessageBubble(
      {required this.message, required this.services, required this.onRetry});

  static String formatSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Treść dymka: tekst albo kafelek pliku (nazwa, rozmiar, pasek postępu
  /// podczas trwającej wysyłki).
  Widget _content(BuildContext context, bool mine, ColorScheme scheme) {
    final textColor = mine ? scheme.onPrimary : scheme.onSurface;
    if (message.kind != MessageKind.file) {
      return Text(message.body, style: TextStyle(color: textColor, fontSize: 15));
    }
    final progress = services.progressOf(message.id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.insert_drive_file_outlined, color: textColor),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message.fileName ?? 'plik',
                  style: TextStyle(
                      color: textColor, fontSize: 15, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              Text(formatSize(message.fileSize),
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.8), fontSize: 12)),
              if (progress != null) ...[
                const SizedBox(height: 6),
                ValueListenableBuilder<double>(
                  valueListenable: progress,
                  builder: (_, value, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      backgroundColor: textColor.withValues(alpha: 0.25),
                      color: mine ? scheme.onPrimary : scheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.direction == MessageDirection.outgoing;
    final failed = mine && message.status == MessageStatus.failed;

    final bubble = Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _content(context, mine, scheme),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatClock(message.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: mine
                      ? scheme.onPrimary.withValues(alpha: 0.7)
                      : scheme.onSurfaceVariant,
                ),
              ),
              if (mine) ...[
                const SizedBox(width: 4),
                Icon(
                  switch (message.status) {
                    MessageStatus.pending => Icons.schedule,
                    MessageStatus.delivered => Icons.done_all,
                    MessageStatus.failed => Icons.error_outline,
                  },
                  size: 14,
                  color: failed
                      ? scheme.errorContainer
                      : scheme.onPrimary.withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: failed
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                bubble,
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Nie dostarczono — ponów'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            )
          : bubble,
    );
  }
}
