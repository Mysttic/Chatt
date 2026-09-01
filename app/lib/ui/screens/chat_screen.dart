import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/file_actions.dart';
import '../../data/db.dart';
import '../../network/protocol.dart' show pairingCodeLifetime;
import '../../services/app_services.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
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

  /// Parowanie: kod losuje i pokazuje ta strona, druga go przepisuje.
  Future<void> _startPairing() async {
    final services = ref.read(appServicesProvider);
    final peer = await services.db.peerByGuid(widget.peer.guid) ?? widget.peer;
    final pin = await services.startPairing(peer);
    if (!mounted) return;

    if (pin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.pairStartFailed)),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.pairCodeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              pin,
              style: const TextStyle(
                  fontSize: 40, letterSpacing: 8, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.pairCodeBody(
                  widget.peer.name, pairingCodeLifetime.inMinutes),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _attachFile() async {
    final file = await openFile();
    if (file == null) return;
    await ref.read(appServicesProvider).sendFile(widget.conversationId, file.path);
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.read(appServicesProvider);
    final messages = ref.watch(messagesProvider(widget.conversationId));
    // Stan sparowania czytamy na żywo: może się zmienić w trakcie rozmowy.
    final peer = ref.watch(knownPeersProvider).value?.firstWhere(
              (p) => p.guid == widget.peer.guid,
              orElse: () => widget.peer,
            ) ??
        widget.peer;

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
                      true => context.l10n.peerOnline,
                      false => context.l10n.peerOffline,
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
        actions: [
          IconButton(
            tooltip: peer.verified
                ? context.l10n.pairTooltipPaired
                : context.l10n.pairTooltip,
            icon: Icon(
              peer.verified ? Icons.verified_user : Icons.shield_outlined,
              color: peer.verified ? Colors.green : null,
            ),
            onPressed: peer.verified ? null : _startPairing,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            // Start i koniec wysyłki muszą przerysować dymki, żeby pasek
            // postępu pojawił się także wtedy, gdy wiadomość trafiła na
            // ekran ułamek sekundy przed rejestracją transferu.
            child: ValueListenableBuilder<int>(
              valueListenable: services.transfersRevision,
              builder: (context, _, _) => messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text(context.l10n.errorWithDetails('$error'))),
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
          ),
          // Pliki, które właśnie do nas płyną (po akceptacji) — z postępem.
          ValueListenableBuilder<Map<String, IncomingTransfer>>(
            valueListenable: services.incomingTransfers,
            builder: (context, transfers, _) {
              final here = transfers.values
                  .where((t) => t.conversationId == widget.conversationId)
                  .toList(growable: false);
              if (here.isEmpty) return const SizedBox.shrink();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final t in here) _IncomingTransferTile(transfer: t)],
              );
            },
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: context.l10n.sendFileTooltip,
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
                        hintText: context.l10n.messageHint,
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
                    tooltip: context.l10n.sendTooltip,
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

  /// Otwarcie pliku systemowym skojarzeniem; komunikat tylko wtedy, gdy się
  /// nie udało (na Androidzie pokazujemy ścieżkę do skopiowania).
  Future<void> _openFile(BuildContext context) async {
    final result = await services.openFileFromMessage(message);
    if (!context.mounted) return;
    _report(context, result);
  }

  Future<void> _revealFile(BuildContext context) async {
    final result = await services.revealFileFromMessage(message);
    if (!context.mounted) return;
    _report(context, result);
  }

  void _report(BuildContext context, FileActionResult result) {
    final path = message.filePath ?? '';
    final snack = switch (result) {
      FileActionResult.ok => null,
      FileActionResult.missing =>
        SnackBar(content: Text(context.l10n.fileGone)),
      // Android/iOS: bez wtyczki platformowej zostaje ścieżka do skopiowania.
      FileActionResult.unsupported => SnackBar(
          content: Text(path),
          action: SnackBarAction(
            label: context.l10n.copy,
            onPressed: () => Clipboard.setData(ClipboardData(text: path)),
          ),
        ),
      FileActionResult.failed =>
        SnackBar(content: Text(context.l10n.fileOpenFailed)),
    };
    if (snack != null) ScaffoldMessenger.of(context).showSnackBar(snack);
  }

  void _fileMenu(BuildContext context) {
    final path = message.filePath ?? '';
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(context.l10n.openFile),
              onTap: () {
                Navigator.pop(sheet);
                _openFile(context);
              },
            ),
            ListTile(
              // Android nie ma menedżera plików do pokazania — tam ta sama
              // akcja udostępnia plik dalej.
              leading: Icon(Platform.isAndroid ? Icons.share : Icons.folder_open),
              title: Text(Platform.isAndroid
                  ? context.l10n.shareFile
                  : context.l10n.showFolder),
              onTap: () {
                Navigator.pop(sheet);
                _revealFile(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: Text(context.l10n.copyPath),
              subtitle: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(sheet);
                Clipboard.setData(ClipboardData(text: path));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Treść dymka: tekst albo kafelek pliku (nazwa, rozmiar, pasek postępu
  /// podczas trwającej wysyłki). Kafelek pliku otwiera go po kliknięciu,
  /// przytrzymanie daje menu (otwórz / pokaż folder / kopiuj ścieżkę).
  Widget _content(BuildContext context, bool mine, ColorScheme scheme) {
    final textColor = mine ? scheme.onPrimary : scheme.onSurface;
    if (message.kind != MessageKind.file) {
      return Text(message.body, style: TextStyle(color: textColor, fontSize: 15));
    }
    final progress = services.progressOf(message.id);
    return InkWell(
      onTap: () => _openFile(context),
      onLongPress: () => _fileMenu(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, color: textColor),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message.fileName ?? context.l10n.fileFallbackName,
                    style: TextStyle(
                        color: textColor, fontSize: 15, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Text(formatFileSize(message.fileSize),
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
      ),
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
                  label: Text(context.l10n.notDeliveredRetry),
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

/// Plik, który właśnie do nas płynie (zgoda już wydana) — pasek postępu nad
/// polem tekstowym. Wpis znika, gdy plik jest kompletny i staje się dymkiem.
class _IncomingTransferTile extends StatelessWidget {
  final IncomingTransfer transfer;

  const _IncomingTransferTile({required this.transfer});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: ValueListenableBuilder<int>(
        valueListenable: transfer.receivedBytes,
        builder: (context, received, _) {
          final value = transfer.fileSize == 0
              ? 1.0
              : (received / transfer.fileSize).clamp(0.0, 1.0).toDouble();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.download_outlined, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(context.l10n.receivingFile(transfer.fileName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle),
                  ),
                  Text(
                    '${formatFileSize(received)} / ${formatFileSize(transfer.fileSize)}',
                    style: labelStyle,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: value, minHeight: 5),
              ),
            ],
          );
        },
      ),
    );
  }
}
