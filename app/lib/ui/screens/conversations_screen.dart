import 'dart:async' show unawaited;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer, RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/search.dart';
import '../../core/share_intake.dart';
import '../../data/db.dart';
import '../../services/presence.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../styles.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/protocol_badge.dart';
import 'chat_screen.dart';
import 'nearby_screen.dart';
import 'send_to_screen.dart';
import 'settings_screen.dart';
import '../widgets/toasts.dart';

/// Usunięcie rozmowy kasuje też urządzenie z listy znanych, jedno bez
/// drugiego nie ma sensu, bo rozmowa i tak odtworzyłaby się przy pierwszym
/// kontakcie. Pytamy, bo idą z tym wiadomości.
Future<void> _confirmDelete(
    BuildContext context, WidgetRef ref, Peer peer) async {
  final confirmed = await showChattDialog<bool>(
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

/// Odstęp między kartami rozmów, ten sam w każdym stylu.
const _odstepKart = 8.0;

/// Wysokość rozszerzonego przycisku „W pobliżu” (Material 3).
const _wysokoscPrzycisku = 56.0;

/// Granica przerysowania prawego panelu. Przy zmianie rozmowy daje obraz
/// ostatniej klatki panelu i znika ten obraz. Ekran poprzedniej rozmowy
/// odchodzi od razu, więc Ctrl+V i upuszczone pliki trafiają tylko do nowej
/// rozmowy.
class _Granica extends SingleChildRenderObjectWidget {
  const _Granica({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGranica();
}

class _RenderGranica extends RenderRepaintBoundary {
  /// Ostatnia narysowana klatka w gęstości [gestosc]; null, dopóki panel nic
  /// nie narysował. Wprost z warstwy: to jest dokładnie to, co widać, także
  /// gdy panel czeka już na przerysowanie.
  ui.Image? obraz(double gestosc) {
    final warstwa = layer;
    if (warstwa is! OffsetLayer || !hasSize) return null;
    return warstwa.toImageSync(Offset.zero & size, pixelRatio: gestosc);
  }
}

/// Obraz panelu, który ustąpił miejsca nowej rozmowie, i jego zejście:
/// od krycia, które panel miał w chwili zmiany, do zera.
class _ZnikajacyPanel {
  final ui.Image obraz;
  final double gestosc;
  final AnimationController ruch;
  final Animation<double> krycie;

  _ZnikajacyPanel(this.obraz, this.gestosc, this.ruch,
      {required double od, required Curve krzywa})
      : krycie = ruch.drive(
            Tween<double>(begin: 0, end: od).chain(CurveTween(curve: krzywa)));

  void dispose() {
    ruch.dispose();
    obraz.dispose();
  }
}

/// Ekran główny: lista konwersacji (odpowiednik ListOfConversation.PNG).
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen>
    with TickerProviderStateMixin {
  final _search = TextEditingController();
  bool _searching = false;

  /// Rozmowa otwarta w prawym panelu. Ma sens tylko na szerokim oknie:
  /// na wąskim rozmowa jest osobnym ekranem na stosie nawigacji.
  int? _wybranaRozmowa;
  Peer? _wybranyRozmowca;

  /// Prawy panel przy zmianie rozmowy: wejście bieżącego i obrazy
  /// poprzednich, które jeszcze znikają.
  final _granica = GlobalKey();
  late final AnimationController _wejscie;
  Animation<double> _krycie = kAlwaysCompleteAnimation;
  final _znikajace = <_ZnikajacyPanel>[];

  /// Prośby spoza aplikacji: udostępnienie i skrót rozmowy (issue #60).
  late final ShareIntake _intake;

  @override
  void initState() {
    super.initState();
    _wejscie = AnimationController(
      vsync: this,
      value: 1,
      // Czas przy „ogranicz animacje” daje już ChattMotion.of. Domyślnie
      // Flutter skróciłby go jeszcze do 5%.
      animationBehavior: AnimationBehavior.preserve,
    );
    // Udostępnienie, które uruchomiło aplikację, czeka już przed pierwszą
    // klatką; kolejne przychodzą w trakcie.
    _intake = ref.read(shareIntakeProvider)..pending.addListener(_zZewnatrz);
    WidgetsBinding.instance.addPostFrameCallback((_) => _zZewnatrz());
  }

  @override
  void dispose() {
    _intake.pending.removeListener(_zZewnatrz);
    _search.dispose();
    _wejscie.dispose();
    for (final panel in _znikajace) {
      panel.dispose();
    }
    super.dispose();
  }

  /// Zmiana rozmowy na szerokim oknie: nowy panel wchodzi na obraz
  /// poprzedniego w czasie i krzywych stylu z chwili zmiany.
  void _przenikaj() {
    final m = ChattMotion.of(context);
    final gestosc = MediaQuery.devicePixelRatioOf(context);
    final krycie = _krycie.value;
    final granica = _granica.currentContext?.findRenderObject();
    final obraz = krycie > 0 && granica is _RenderGranica
        ? granica.obraz(gestosc)
        : null;
    if (obraz != null) {
      final panel = _ZnikajacyPanel(
        obraz,
        gestosc,
        AnimationController(
          vsync: this,
          duration: m.paneSwitch,
          value: 1,
          animationBehavior: AnimationBehavior.preserve,
        ),
        od: krycie,
        krzywa: m.exitReverse,
      );
      panel.ruch.addStatusListener((status) {
        if (status != AnimationStatus.dismissed) return;
        setState(() => _znikajace.remove(panel));
        panel.dispose();
      });
      _znikajace.add(panel);
      panel.ruch.reverse();
    }
    _wejscie.duration = m.paneSwitch;
    _krycie = _wejscie.drive(CurveTween(curve: m.enter));
    _wejscie.forward(from: 0);
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _search.clear();
    });
  }

  void _otworz(int conversationId, Peer peer) {
    if (czyDwupanel(context)) {
      if (conversationId != _wybranaRozmowa) _przenikaj();
      setState(() {
        _wybranaRozmowa = conversationId;
        _wybranyRozmowca = peer;
      });
      return;
    }
    Navigator.of(context).push(
      ChattPageRoute(
        builder: (_) =>
            ChatScreen(conversationId: conversationId, peer: peer),
      ),
    );
  }

  /// Prośba spoza aplikacji: treść z systemowego okna „Udostępnij” albo
  /// skrót rozmowy z ekranu głównego. Wszystko, co leży nad listą rozmów,
  /// schodzi, tak jak po stuknięciu w powiadomienie.
  ///
  /// Rozmówca wskazany wprost (skrót) dostaje rozmowę od razu, z treścią
  /// czekającą na „Wyślij”. Bez niego, albo gdy tego rozmówcy już nie ma,
  /// rozmowę wybiera się na ekranie „Wyślij do”.
  Future<void> _zZewnatrz() async {
    final prosba = _intake.pending.value;
    if (prosba == null || !mounted) return;
    _intake.pending.value = null;
    final services = ref.read(appServicesProvider);
    final teksty = context.l10n;
    Navigator.of(context).popUntil((route) => route.isFirst);

    if (prosba is IncomingShare) {
      if (prosba.isEmpty) {
        unawaited(_intake.discard(prosba.id));
        showToast(teksty.shareNothing);
        return;
      }
      if (prosba.skipped > 0) showToast(teksty.shareSkipped(prosba.skipped));
    }
    final guid = switch (prosba) {
      OpenConversationRequest(:final peerGuid) => peerGuid,
      IncomingShare(:final peerGuid) => peerGuid,
    };
    final peer = guid == null ? null : await services.db.peerByGuid(guid);
    if (!mounted) return;
    if (peer != null) {
      final conversationId = await services.openConversationWith(peer);
      if (!mounted) return;
      if (prosba is IncomingShare) _intake.stage(conversationId, prosba);
      _otworz(conversationId, peer);
      return;
    }
    switch (prosba) {
      case OpenConversationRequest():
        showToast(teksty.conversationGone);
      case IncomingShare share:
        unawaited(Navigator.of(context).push(ChattPageRoute(
          builder: (_) => SendToScreen(
            share: share,
            onChosen: (conversationId, peer) =>
                _poWyborze(share, conversationId, peer),
          ),
        )));
    }
  }

  /// Rozmowa wybrana na ekranie „Wyślij do”: treść czeka w niej na „Wyślij”.
  void _poWyborze(IncomingShare share, int conversationId, Peer peer) {
    _intake.stage(conversationId, share);
    if (czyDwupanel(context)) {
      Navigator.of(context).pop();
      _otworz(conversationId, peer);
      return;
    }
    // Rozmowa zastępuje ekran wyboru, więc „wstecz” wraca do listy rozmów.
    Navigator.of(context).pushReplacement(ChattPageRoute(
      builder: (_) => ChatScreen(conversationId: conversationId, peer: peer),
    ));
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
            // Zmiana rozmowy przenika cały panel w czasie stylu. Panele leżą
            // na sobie i wypełniają miejsce, obrazy poprzednich pod spodem
            // nie przyjmują dotyku.
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final panel in _znikajace)
                  IgnorePointer(
                    key: ObjectKey(panel),
                    child: FadeTransition(
                      opacity: panel.krycie,
                      child: RawImage(
                        image: panel.obraz,
                        scale: panel.gestosc,
                        fit: BoxFit.none,
                        alignment: Alignment.topLeft,
                      ),
                    ),
                  ),
                FadeTransition(
                  key: const ValueKey('panel rozmowy'),
                  opacity: _krycie,
                  child: _Granica(
                    key: _granica,
                    child: rozmowa == null || rozmowca == null
                        ? const _NoSelection()
                        : ChatScreen(
                            // Klucz po rozmowie: przełączenie ma zbudować
                            // ekran od nowa, a nie doklejać wiadomości do
                            // poprzedniego stanu.
                            key: ValueKey(rozmowa),
                            conversationId: rozmowa,
                            peer: rozmowca,
                          ),
                  ),
                ),
              ],
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
                  // Bez ramki i tła, ale na wysokość celu dotyku (48 dp).
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              )
            // Nazwa tego urządzenia: tak widzą je inni, a przy kilku
            // urządzeniach od razu wiadomo, na którym się jest. Numer wersji
            // mieszka w Ustawieniach, w sekcji Aktualizacje.
            : Text(
                ref.watch(settingsProvider).value?.nickname ??
                    context.l10n.appTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
              ChattPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_search),
        label: Text(context.l10n.nearbyButton),
        onPressed: () => Navigator.of(context).push(
          ChattPageRoute(builder: (_) => const NearbyScreen()),
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
          final k = ChattTokens.of(context);
          final scheme = Theme.of(context).colorScheme;
          final dwupanel = czyDwupanel(context);
          Widget wiersz(ConversationSummary item) {
            final wybrany =
                item.conversationId == _wybranaRozmowa && dwupanel;
            final tile = ListTile(
              contentPadding: k.rowPadding,
              // Wysokość wiersza ze stylu liczy już odstępy; ListTile dokłada
              // je osobno.
              minTileHeight: k.rowHeight - k.rowPadding.vertical,
              horizontalTitleGap: k.rowGap,
              // Na pulpicie gęstość kompaktowa przycina awatar i kolumnę
              // z godziną do 48 px.
              visualDensity: VisualDensity.standard,
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Sama ikona: w wierszu listy nie ma miejsca na
                      // podpis, a różnicę między sekundą a minutą przy tym
                      // samym pliku trzeba pokazać.
                      ProtocolBadge(
                        peer: item.peer,
                        compact: true,
                        padding: const EdgeInsets.only(right: 6),
                      ),
                      Text(
                        formatWhen(item.lastAt),
                        style: k.caption.copyWith(
                          color: item.unreadCount > 0
                              ? k.unreadTime
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (item.unreadCount > 0) ...[
                    const SizedBox(height: 4),
                    UnreadCount(count: item.unreadCount),
                  ],
                ],
              ),
              selected: wybrany,
              onTap: () => _otworz(item.conversationId, item.peer),
              onLongPress: () => _confirmDelete(context, ref, item.peer),
            );
            // Każdy wiersz to osobna karta na tle ekranu. Tło daje Material:
            // dekoracja zasłoniłaby efekt dotyku i zaznaczenie wiersza.
            // Wybrany ma ramkę w kolorze akcentu, Precyzja odcina karty
            // obrysem, bo cienia nie ma.
            final ksztalt = BorderRadius.circular(k.radiusRow);
            final obrys = k.style == AppStyle.precyzja;
            return DecoratedBox(
              decoration:
                  BoxDecoration(borderRadius: ksztalt, boxShadow: k.shadow1),
              child: Material(
                color: k.surface1,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: ksztalt,
                  side: wybrany
                      ? BorderSide(color: scheme.primary, width: 2)
                      : obrys
                          ? BorderSide(color: k.outline)
                          : BorderSide.none,
                ),
                child: tile,
              ),
            );
          }

          return ListView.separated(
            // Ostatnia karta kończy się nad paskiem nawigacji systemu i da
            // się ją przewinąć spod przycisku „W pobliżu”.
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
            separatorBuilder: (_, _) => const SizedBox(height: _odstepKart),
            itemBuilder: (context, index) => wiersz(items[index]),
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
