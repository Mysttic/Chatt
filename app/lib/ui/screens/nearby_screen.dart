import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// Wyszukiwanie urządzeń w sieci (odpowiednik ListOfNearbyDevices.PNG
/// + ManuallyFindDevice.PNG). Wyniki skanu od razu trafiają do bazy, więc
/// lista niżej to po prostu wszystkie znane urządzenia, na żywo.
class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  bool _scanning = false;
  int _foundInLastScan = 0;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _foundInLastScan = 0;
    });
    final found = await ref
        .read(appServicesProvider)
        .scan(onFound: (_) => setState(() => _foundInLastScan++));
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _foundInLastScan = found.length;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          found.isEmpty
              ? context.l10n.scanNothingFound
              : context.l10n.scanFound(found.length),
        ),
      ),
    );
  }

  Future<void> _openChat(Peer peer) async {
    final services = ref.read(appServicesProvider);
    final conversationId = await services.openConversationWith(peer);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: conversationId, peer: peer),
      ),
    );
  }

  /// Ręczne usunięcie wpisu. Urządzenia, które przewinęły się przez sieć
  /// i nic nie napisały, znikają same po tygodniu — ale rozmowy trzeba
  /// kasować świadomie, bo idą z nimi wiadomości.
  Future<void> _forget(Peer peer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.deleteDeviceTitle(peer.name)),
        content: Text(context.l10n.deleteDeviceBody),
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
    if (confirmed != true || !mounted) return;

    await ref.read(appServicesProvider).forgetPeer(peer);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.deviceDeleted(peer.name))));
  }

  Future<void> _addManually() async {
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (context) => const _ManualAddDialog(),
    );
    if (result == null || !mounted) return;
    final (host, port) = result;
    final peer = await ref
        .read(appServicesProvider)
        .addPeerByAddress(host, port);
    if (!mounted) return;
    if (peer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noChattAtAddress(host, port))),
      );
    } else {
      await _openChat(peer);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peers = ref.watch(knownPeersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.nearbyTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.addByAddress,
            icon: const Icon(Icons.add_link),
            onPressed: _addManually,
          ),
        ],
      ),
      body: ContentColumn(
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: Text(
                _scanning
                    ? context.l10n.scanRunning(_foundInLastScan)
                    : context.l10n.scanStart,
              ),
              onPressed: _scanning ? null : _scan,
            ),
          ),
          Expanded(
            child: peers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text(context.l10n.errorWithDetails('$error'))),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      context.l10n.noKnownDevices,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        context.l10n.longPressToDelete,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.only(
                            bottom: bottomSystemInset(context)),
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 72),
                        itemBuilder: (context, index) {
                          final peer = items[index];
                          return ListTile(
                            leading: InitialsAvatar(name: peer.name),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    peer.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (peer.verified) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.verified_user,
                                    size: 16,
                                    color: Colors.green,
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              peer.welcomeMessage.isEmpty
                                  ? '${peer.host}:${peer.port}'
                                  : peer.welcomeMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              context.l10n.lastSeen(formatWhen(peer.lastSeen)),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            onTap: () => _openChat(peer),
                            onLongPress: () => _forget(peer),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _ManualAddDialog extends StatefulWidget {
  const _ManualAddDialog();

  @override
  State<_ManualAddDialog> createState() => _ManualAddDialogState();
}

class _ManualAddDialogState extends State<_ManualAddDialog> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '47780');

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _submit() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null || port < 1 || port > 65535) return;
    Navigator.of(context).pop((host, port));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.manualAddTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _host,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.l10n.ipLabel,
              hintText: context.l10n.ipHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.l10n.portLabel),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(context.l10n.connect)),
      ],
    );
  }
}
