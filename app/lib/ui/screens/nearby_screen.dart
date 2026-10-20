import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../network/bt_transport.dart';
import '../../network/transport.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../styles.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import 'chat_screen.dart';
import '../widgets/toasts.dart';

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

  /// Którędy szukamy. Radio i sieć to dwa różne pytania do dwóch różnych
  /// światów: broadcast UDP nie wyjdzie poza sieć, a zapytanie w eter nie
  /// znajdzie komputera piętro niżej.
  PeerProtocol _gdzie = PeerProtocol.wifi;

  /// Guidy urządzeń z ostatniego skanu. `null` znaczy „jeszcze nie szukałem",
  /// wtedy ekran nie pokazuje listy. Baza pamięta wszystkich, których
  /// kiedykolwiek widziała, a lista z poprzedniego wejścia wygląda jak wynik
  /// skanu, którego nie było.
  Set<String>? _znalezione;

  /// Dodatek Bluetooth, zapamiętany przy wejściu: [dispose] musi odpiąć
  /// słuchacza od tego samego obiektu.
  late final ValueNotifier<bool> _dodatek;

  /// Którędy szukamy naprawdę. Bez dodatku Bluetooth zostaje sama sieć,
  /// cokolwiek było wybrane wcześniej.
  PeerProtocol get _droga => _dodatek.value ? _gdzie : PeerProtocol.wifi;

  @override
  void initState() {
    super.initState();
    _dodatek = ref.read(appServicesProvider).bluetoothAddon
      ..addListener(_dodatekZmieniony);
    // Lokalizację i radio użytkownik przełącza poza aplikacją, więc stan
    // odświeżamy przy każdym wejściu na ekran. Przy wyłączonym dodatku
    // serwis nie pyta systemu o nic.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appServicesProvider).refreshBluetoothStatus();
    });
  }

  @override
  void dispose() {
    _dodatek.removeListener(_dodatekZmieniony);
    super.dispose();
  }

  void _dodatekZmieniony() {
    if (!mounted) return;
    setState(() {
      // Wyniki szukania przez radio znikają razem z dodatkiem.
      if (!_dodatek.value && _gdzie == PeerProtocol.bluetooth) {
        _gdzie = PeerProtocol.wifi;
        _znalezione = null;
      }
    });
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _foundInLastScan = 0;
    });
    final services = ref.read(appServicesProvider);
    void policz(_) {
      if (mounted) setState(() => _foundInLastScan++);
    }

    // Dwa różne pytania oddają dwa różne typy: skan sieci zwraca to, co
    // odpowiedziało na broadcast, a skan radia gotowe wpisy z bazy. Z obu
    // interesują nas te same identyfikatory.
    final List<String> guidy;
    if (_droga == PeerProtocol.bluetooth) {
      // Radio szuka do minuty, więc każdy, kto odpowie, trafia na listę od
      // razu. Komputer obok da się otworzyć, zanim skończy się pytanie
      // słuchawek i telewizorów z sąsiedztwa.
      setState(() => _znalezione = {});
      final found = await services.scanBluetooth(onFound: (peer) {
        if (!mounted) return;
        setState(() {
          _foundInLastScan++;
          _znalezione = {...?_znalezione, peer.guid};
        });
      });
      guidy = [for (final peer in found) peer.guid];
    } else {
      final found = await services.scan(onFound: policz);
      guidy = [for (final peer in found) peer.guid];
    }
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _foundInLastScan = guidy.length;
      _znalezione = guidy.toSet();
    });
    showToast(guidy.isEmpty
        ? _nicNieZnaleziono(context)
        : context.l10n.scanFound(guidy.length));
  }

  String _nicNieZnaleziono(BuildContext context) =>
      _droga == PeerProtocol.bluetooth
          ? context.l10n.scanNothingFoundBluetooth
          : context.l10n.scanNothingFound;

  Future<void> _openChat(Peer peer) async {
    final services = ref.read(appServicesProvider);
    final conversationId = await services.openConversationWith(peer);
    if (!mounted) return;
    await Navigator.of(context).push(
      ChattPageRoute(
        builder: (_) => ChatScreen(conversationId: conversationId, peer: peer),
      ),
    );
  }

  /// Ręczne usunięcie wpisu. Urządzenia, które przewinęły się przez sieć
  /// i nic nie napisały, znikają same po tygodniu, ale rozmowy trzeba
  /// kasować świadomie, bo idą z nimi wiadomości.
  Future<void> _forget(Peer peer) async {
    final confirmed = await showChattDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.deleteDeviceTitle(peer.displayName)),
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

    final teksty = context.l10n;
    final nazwa = peer.displayName;
    await ref.read(appServicesProvider).forgetPeer(peer);
    showToast(teksty.deviceDeleted(nazwa));
  }

  /// Ręczne dodanie. Przy wybranym Bluetoothcie pyta o adres radia: tam nie
  /// ma ani hosta, ani portu.
  Future<void> _addManually() async {
    if (_droga == PeerProtocol.bluetooth) return _addByBluetooth();

    final result = await showChattDialog<(String, int)>(
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
      showToast(context.l10n.noChattAtAddress(host, port));
    } else {
      // Dopisany ręcznie ma być widoczny na liście po powrocie z rozmowy,
      // choć żaden skan go nie zwrócił.
      setState(() => _znalezione = {...?_znalezione, peer.guid});
      await _openChat(peer);
    }
  }

  /// Adres radia wpisany z ręki: droga na wypadek, gdy szukanie nie wchodzi
  /// w grę. Na Androidzie z wyłączoną lokalizacją to jedyna droga.
  Future<void> _addByBluetooth() async {
    final address = await showChattDialog<String>(
      context: context,
      builder: (context) => const _ManualAddBluetoothDialog(),
    );
    if (address == null || !mounted) return;

    final teksty = context.l10n;
    final peer =
        await ref.read(appServicesProvider).addPeerByBluetooth(address);
    if (!mounted) return;
    if (peer == null) {
      showToast(teksty.noChattAtBtAddress(address));
      return;
    }
    setState(() => _znalezione = {...?_znalezione, peer.guid});
    await _openChat(peer);
  }

  @override
  Widget build(BuildContext context) {
    final peers = ref.watch(knownPeersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.nearbyTitle),
        actions: [
          IconButton(
            tooltip: _droga == PeerProtocol.bluetooth
                ? context.l10n.addByBtAddress
                : context.l10n.addByAddress,
            icon: const Icon(Icons.add_link),
            onPressed: _addManually,
          ),
        ],
      ),
      body: ContentColumn(
        child: Column(
        children: [
          // Wybór drogi należy do dodatku Bluetooth. Bez niego ekran jest
          // taki, jak był przed radiem: sam przycisk szukania w sieci.
          if (_dodatek.value)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _WyborProtokolu(
                wybrany: _gdzie,
                wlaczony: !_scanning,
                onChanged: (protokol) => setState(() => _gdzie = protokol),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, _dodatek.value ? 0 : 16, 16, 16),
            child: FilledButton.icon(
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_droga == PeerProtocol.bluetooth
                      ? Icons.bluetooth_searching
                      : Icons.wifi_tethering),
              label: Text(
                _scanning
                    ? (_droga == PeerProtocol.bluetooth
                        ? context.l10n.searchingBluetooth
                        : context.l10n.scanRunning(_foundInLastScan))
                    : (_droga == PeerProtocol.bluetooth
                        ? context.l10n.scanStartBluetooth
                        : context.l10n.scanStart),
              ),
              onPressed: _scanning ? null : _scan,
            ),
          ),
          Expanded(
            child: peers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text(context.l10n.errorWithDetails('$error'))),
              data: (all) {
                final znalezione = _znalezione;
                if (znalezione == null) {
                  return _Podpowiedz(_droga == PeerProtocol.bluetooth
                      ? context.l10n.nearbyBeforeScanBluetooth
                      : context.l10n.nearbyBeforeScan);
                }
                // Wpisy z bazy, bo tylko one wiedzą o potwierdzeniu
                // tożsamości i o własnej nazwie, zawężone do tego,
                // co odpowiedziało na ostatni skan.
                final items = all
                    .where((peer) => znalezione.contains(peer.guid))
                    .toList();
                if (items.isEmpty) {
                  return _Podpowiedz(
                      _scanning && _droga == PeerProtocol.bluetooth
                          ? context.l10n.nearbyScanningBluetooth
                          : _nicNieZnaleziono(context));
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
                            visualDensity: VisualDensity.standard,
                            leading: InitialsAvatar(name: peer.displayName),
                            title: PeerName(
                              name: peer.displayName,
                              verified: peer.verified,
                            ),
                            subtitle: Text(
                              peer.welcomeMessage.isEmpty
                                  ? peerAddressLabel(peer,
                                      radio: _dodatek.value)
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

/// Wybór drogi, którą szukamy. Stoi na ekranie tylko przy włączonym dodatku
/// Bluetooth, a sam Bluetooth jest do wzięcia, gdy radio naprawdę wstało.
class _WyborProtokolu extends ConsumerWidget {
  final PeerProtocol wybrany;
  final bool wlaczony;
  final void Function(PeerProtocol protokol) onChanged;

  const _WyborProtokolu({
    required this.wybrany,
    required this.wlaczony,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.read(appServicesProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: services.bluetoothRunning,
      builder: (context, radioStoi, _) {
        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.searchWhere,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<PeerProtocol>(
              segments: [
                ButtonSegment(
                  value: PeerProtocol.wifi,
                  icon: const Icon(Icons.wifi),
                  label: Text(context.l10n.protocolWifi),
                ),
                ButtonSegment(
                  value: PeerProtocol.bluetooth,
                  icon: const Icon(Icons.bluetooth),
                  label: Text(context.l10n.protocolBluetooth),
                  enabled: radioStoi,
                ),
              ],
              selected: {radioStoi ? wybrany : PeerProtocol.wifi},
              onSelectionChanged:
                  wlaczony ? (wybor) => onChanged(wybor.first) : null,
            ),
            const SizedBox(height: 6),
            Text(
              radioStoi
                  ? context.l10n.searchBluetoothHint
                  : context.l10n.searchBluetoothOff,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            // Wyłączona lokalizacja to najczęstszy powód, dla którego szukanie
            // po radiu nie zwraca nic. Bez tego ostrzeżenia objaw wygląda na
            // „nikogo nie ma w pobliżu" i szuka się go godzinami.
            if (radioStoi && wybrany == PeerProtocol.bluetooth)
              ValueListenableBuilder<BtStatus>(
                valueListenable: services.bluetoothStatus,
                builder: (context, stan, _) {
                  if (stan.locationOn) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_off_outlined,
                                size: 18, color: scheme.error),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                context.l10n.searchBluetoothNoLocation,
                                style:
                                    TextStyle(color: scheme.error, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await services.openLocationSettings();
                          },
                          icon: const Icon(Icons.my_location),
                          label: Text(context.l10n.turnOnLocation),
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (radioStoi && wybrany == PeerProtocol.bluetooth)
              const _Widocznosc(),
          ],
        );
      },
    );
  }
}

/// „Pokaż ten telefon w pobliżu". Android jest widoczny w eterze tylko przy
/// otwartym ekranie parowania w ustawieniach, więc drugie urządzenie nie
/// znajdzie telefonu, dopóki ten się na chwilę nie pokaże. Komputer
/// z Windows jest widoczny przez cały czas dodatku i przycisku nie dostaje.
class _Widocznosc extends ConsumerStatefulWidget {
  const _Widocznosc();

  @override
  ConsumerState<_Widocznosc> createState() => _WidocznoscState();
}

class _WidocznoscState extends ConsumerState<_Widocznosc> {
  /// Odpytywanie stanu po prośbie o widoczność. Okienko systemowe nie oddaje
  /// wyniku do Darta, a widoczność gaśnie sama po dwóch minutach.
  Timer? _pilnuj;

  /// Do kiedy odpytujemy: dwie minuty widoczności plus czas na decyzję.
  DateTime? _pilnujDo;

  @override
  void dispose() {
    _pilnuj?.cancel();
    super.dispose();
  }

  Future<void> _pokaz() async {
    final services = ref.read(appServicesProvider);
    final teksty = context.l10n;
    if (!await services.showThisDeviceNearby()) {
      showToast(teksty.showThisPhoneFailed);
      return;
    }
    _pilnujDo = DateTime.now().add(const Duration(minutes: 3));
    _pilnuj ??= Timer.periodic(const Duration(seconds: 2), (_) {
      final koniec = _pilnujDo;
      if (!mounted || koniec == null || DateTime.now().isAfter(koniec)) {
        _pilnuj?.cancel();
        _pilnuj = null;
        return;
      }
      unawaited(services.refreshBluetoothStatus());
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.read(appServicesProvider);
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<BtStatus>(
      valueListenable: services.bluetoothStatus,
      builder: (context, stan, _) {
        if (!stan.canShowSelf) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stan.visible)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.visibility, size: 18, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.l10n.thisPhoneVisible,
                        style: TextStyle(color: scheme.primary, fontSize: 12),
                      ),
                    ),
                  ],
                )
              else ...[
                OutlinedButton.icon(
                  onPressed: _pokaz,
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(context.l10n.showThisPhone),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.showThisPhoneHint,
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Adres radia z ręki. Odpowiednik dodania po IP, dla tej drugiej drogi.
class _ManualAddBluetoothDialog extends ConsumerStatefulWidget {
  const _ManualAddBluetoothDialog();

  @override
  ConsumerState<_ManualAddBluetoothDialog> createState() =>
      _ManualAddBluetoothDialogState();
}

class _ManualAddBluetoothDialogState
    extends ConsumerState<_ManualAddBluetoothDialog> {
  final _adres = TextEditingController();

  @override
  void dispose() {
    _adres.dispose();
    super.dispose();
  }

  /// Adres wychodzi stąd zawsze w jednej postaci. Przepisując go z ekranu
  /// drugiego urządzenia łatwo pominąć dwukropki, a Android przyjmuje
  /// wyłącznie `AA:BB:CC:DD:EE:FF`.
  void _submit() {
    final address = normalizeBtAddress(_adres.text);
    if (address.isEmpty) return;
    Navigator.of(context).pop(address);
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.read(appServicesProvider);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(context.l10n.manualAddBtTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.manualAddBtHelp,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _adres,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.l10n.btAddressLabel,
              hintText: context.l10n.btAddressHint,
            ),
            onSubmitted: (_) => _submit(),
          ),
          // Własny adres pokazujemy obok: druga strona i tak będzie go
          // potrzebowała, a Android nie podaje go nawet sam sobie.
          ValueListenableBuilder<BtStatus>(
            valueListenable: services.bluetoothStatus,
            builder: (context, stan, _) {
              if (stan.address.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SelectableText(
                  context.l10n.myBtAddress(stan.address),
                  style: ChattTokens.of(context)
                      .mono
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              );
            },
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

/// Miejsce po liście: zaproszenie do skanu albo wynik skanu bez znalezisk.
class _Podpowiedz extends StatelessWidget {
  final String text;

  const _Podpowiedz(this.text);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
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
