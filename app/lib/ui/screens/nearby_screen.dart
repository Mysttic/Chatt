import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../services/providers.dart';
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
              ? 'Nie znaleziono urządzeń. Sprawdź, czy Chatt działa na drugim '
                    'urządzeniu w tej samej sieci, albo dodaj je ręcznie po adresie.'
              : 'Znaleziono: ${found.length}',
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
        title: Text('Usunąć ${peer.name}?'),
        content: const Text(
          'Urządzenie zniknie z listy razem z rozmową i jej wiadomościami. '
          'Odebrane pliki zostają na dysku.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(appServicesProvider).forgetPeer(peer);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Usunięto ${peer.name}')));
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
        SnackBar(content: Text('Pod $host:$port nie odpowiada żaden Chatt.')),
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
        title: const Text('Urządzenia w pobliżu'),
        actions: [
          IconButton(
            tooltip: 'Dodaj po adresie IP',
            icon: const Icon(Icons.add_link),
            onPressed: _addManually,
          ),
        ],
      ),
      body: Column(
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
                    ? 'Szukam… (znaleziono $_foundInLastScan)'
                    : 'Szukaj urządzeń w sieci',
              ),
              onPressed: _scanning ? null : _scan,
            ),
          ),
          Expanded(
            child: peers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Błąd: $error')),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'Nie znasz jeszcze żadnych urządzeń.',
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
                        'Przytrzymaj urządzenie, żeby je usunąć',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
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
                              'widziano ${formatWhen(peer.lastSeen)}',
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
      title: const Text('Dodaj urządzenie po adresie'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _host,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Adres IP',
              hintText: 'np. 192.168.1.20',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Port'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Połącz')),
      ],
    );
  }
}
