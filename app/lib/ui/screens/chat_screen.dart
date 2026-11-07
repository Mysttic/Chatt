import 'dart:async' show unawaited;
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, KeyboardInsertedContent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clipboard.dart';
import '../../core/file_actions.dart';
import '../../core/links.dart';
import '../../core/search.dart';
import '../../core/share_intake.dart';
import '../../data/db.dart';
import '../../services/app_services.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../styles.dart';
import '../widgets/common.dart';
import '../widgets/history_ui.dart';
import '../widgets/link_confirm.dart';
import '../widgets/link_preview_card.dart';
import '../widgets/linked_text.dart';
import '../widgets/motion.dart';
import '../widgets/paste_shortcut.dart';
import '../widgets/protocol_badge.dart';
import '../widgets/security_sheet.dart';
import '../widgets/toasts.dart';
import 'image_view_screen.dart';
import 'remote_keyboard_screen.dart';
import 'scan_screen.dart';

/// Telefon zamiast pulpitu. Decyduje o tym, jak zaznacza się tekst i czym
/// otwiera się menu dymka: myszą klika się prawym przyciskiem, palcem
/// przytrzymuje.
final bool dotykowy = Platform.isAndroid || Platform.isIOS;

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

  /// Numer bieżącego sprawdzenia obecności. Wynik starszego sprawdzenia,
  /// który wraca po nowszej wiedzy o łączu, nie nadpisuje nagłówka.
  var _obecnoscNr = 0;

  /// Zmiany łączy internetowego i radiowego, na które czeka nagłówek.
  late final Listenable _lacza;

  /// Szukanie filtruje listę dymków w miejscu. Pusty napis znaczy „nie szukam",
  /// wtedy pole w pasku w ogóle się nie pokazuje.
  final _search = TextEditingController();
  bool _searching = false;

  /// Pliki wiszą nad oknem (przeciąganie z pulpitu). Podpowiedź pokazuje się
  /// tylko wtedy, bo poza tym nie ma o czym mówić.
  bool _dragging = false;

  /// Treść udostępniona z innej aplikacji (issue #60). Tekst trafia do pola
  /// wiadomości, pliki czekają na pasku nad nim, aż padnie „Wyślij".
  late final ShareIntake _intake;
  _Udostepnione? _udostepnione;

  /// Trasa, na której stoi ten ekran (na szerokim oknie: lista rozmów).
  ModalRoute<Object?>? _trasa;

  /// Wiadomości już pokazane, po id. null: pierwsze dane jeszcze nie
  /// przyszły, a to, co przyjdzie z nimi, stoi od razu na miejscu.
  Set<int>? _pokazane;

  /// Wiadomości, które przyszły albo wyszły przy otwartej rozmowie. Tylko
  /// one wjeżdżają, i tylko w klatce, w której pojawiły się na liście:
  /// powrót po przewinięciu buduje dymek od razu na miejscu.
  Set<int> _wjezdzaja = const {};

  /// Porównanie z poprzednią listą. Nie wjeżdża przywrócona historia
  /// (potrafi przyjść setkami naraz) ani nic w trakcie szukania. Zmiana
  /// statusu nie zmienia id, więc niczego nie wnosi. Nowa wiadomość ma id
  /// większe od każdego pokazanego: wiersze przeniesione przy scalaniu
  /// starszej rozmowy mają swoje dawne, mniejsze id i stoją od razu.
  void _zauwazNowe(List<Message> all, String query) {
    final pokazane = _pokazane;
    _pokazane = {for (final m in all) m.id};
    if (pokazane == null || query.isNotEmpty) return;
    final najnowsza = pokazane.fold(-1, (a, b) => a > b ? a : b);
    final nowe = {
      for (final m in all)
        if (m.restoredAt == null && m.id > najnowsza) m.id,
    };
    if (nowe.isEmpty) return;
    _wjezdzaja = nowe;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_wjezdzaja, nowe)) _wjezdzaja = const {};
    });
  }

  @override
  void initState() {
    super.initState();
    final services = ref.read(appServicesProvider);
    services.db.markConversationRead(widget.conversationId);
    final nr = ++_obecnoscNr;
    services.isPeerOnline(widget.peer).then((online) {
      if (mounted && nr == _obecnoscNr) setState(() => _online = online);
    });
    _lacza = Listenable.merge(
        [services.internetRevision, services.bluetoothRevision])
      ..addListener(_naZmianeLacza);
    // Treść czeka na tę rozmowę od chwili wyboru, a przy otwartej rozmowie
    // (prawy panel) może przyjść w każdej chwili.
    _intake = ref.read(shareIntakeProvider)
      ..staged.addListener(_wezUdostepnione);
    WidgetsBinding.instance.addPostFrameCallback((_) => _wezUdostepnione());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _trasa = ModalRoute.of(context);
  }

  /// Łącze internetowe albo radiowe do rozmówcy właśnie stoi, więc rozmówca
  /// odpowiada. Pierwsze sprawdzenie po zmianie sieci trafia często w chwilę,
  /// gdy łącze dopiero się zestawia: bez tego nagłówek mówiłby „niedostępny”
  /// aż do ponownego otwarcia rozmowy, choć wiadomości już chodzą. Samo
  /// zerwanie łącza niczego tu nie zmienia, bo sieć lokalna mogła zostać.
  void _naZmianeLacza() {
    if (!mounted || _online == true) return;
    final services = ref.read(appServicesProvider);
    if (!services.isLinkedByInternet(widget.peer) &&
        !services.isLinkedByBluetooth(widget.peer)) {
      return;
    }
    _obecnoscNr++;
    setState(() => _online = true);
  }

  @override
  void dispose() {
    _lacza.removeListener(_naZmianeLacza);
    _intake.staged.removeListener(_wezUdostepnione);
    // Wyjście z rozmowy bez „Wyślij": kopie udostępnionych plików do kosza.
    final udostepnione = _udostepnione;
    if (udostepnione != null) unawaited(_intake.discard(udostepnione.share.id));
    _input.dispose();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Treść z okna „Udostępnij" dla tej rozmowy. Tekst dopisuje się do tego,
  /// co już jest w polu. Pliki z nowszego udostępnienia wypierają starsze.
  ///
  /// Ekran zdjęty ze stosu (udostępnienie z zewnątrz zdejmuje wszystko nad
  /// listą rozmów) żyje jeszcze przez animację wyjścia. Treść tej samej
  /// rozmowy jest wtedy dla nowego ekranu, który zaraz wejdzie.
  void _wezUdostepnione() {
    if (!mounted || !(_trasa?.isActive ?? true)) return;
    final share = _intake.takeStaged(widget.conversationId);
    if (share == null) return;
    final tekst = share.text?.trim();
    if (tekst != null && tekst.isNotEmpty) {
      final obecny = _input.text;
      _input.text = obecny.trim().isEmpty ? tekst : '$obecny\n$tekst';
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    if (share.fileCount == 0) return;
    final starsze = _udostepnione;
    if (starsze != null) unawaited(_intake.discard(starsze.share.id));
    final czekajace = _Udostepnione(share, _intake.files(share.id));
    setState(() => _udostepnione = czekajace);
    final teksty = context.l10n;
    czekajace.files.then((pliki) {
      if (!mounted || !identical(_udostepnione, czekajace)) return;
      final brak = share.fileCount - pliki.length;
      if (brak > 0) showToast(teksty.shareFilesMissing(brak, share.fileCount));
      setState(() {
        czekajace.ready = pliki;
        if (pliki.isEmpty) _udostepnione = null;
      });
    });
  }

  /// Rezygnacja z udostępnionych plików (krzyżyk na pasku).
  void _odrzucUdostepnione() {
    final udostepnione = _udostepnione;
    if (udostepnione == null) return;
    setState(() => _udostepnione = null);
    unawaited(_intake.discard(udostepnione.share.id));
  }

  /// Wysłana wiadomość podnosi tę rozmowę w podpowiedziach systemowego okna
  /// „Udostępnij".
  void _zglosUzycie() => unawaited(_intake.reportUsed(widget.peer.guid));

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _search.clear();
    });
  }

  Future<void> _deleteMessage(Message message) async {
    final teksty = context.l10n;
    await ref.read(appServicesProvider).db.deleteMessage(message.id);
    showToast(teksty.messageDeleted);
  }

  /// Tekst z pola, a za nim pliki czekające na pasku, jeśli są.
  Future<void> _send() async {
    final text = _input.text;
    final udostepnione = _udostepnione;
    _input.clear();
    if (udostepnione != null) setState(() => _udostepnione = null);
    if (text.trim().isEmpty && udostepnione == null) return;
    final services = ref.read(appServicesProvider);
    _zglosUzycie();
    await services.sendText(widget.conversationId, text);
    if (udostepnione == null) return;
    // Kopie mogą się jeszcze robić. Wysyłka rusza, gdy będą gotowe, także
    // po wyjściu z rozmowy.
    final pliki = await udostepnione.files;
    unawaited(_intake.keep(udostepnione.share.id));
    if (pliki.isEmpty) return;
    await services.sendFiles(
        widget.conversationId, pliki.map((plik) => plik.path));
  }

  /// Parowanie: uzgodnienie leci pod spodem, a kod do porównania pokazuje
  /// karta nad aplikacją (PromptOverlay), po obu stronach ten sam.
  Future<void> _startPairing() async {
    final services = ref.read(appServicesProvider);
    final teksty = context.l10n;
    final peer = await services.db.peerByGuid(widget.peer.guid) ?? widget.peer;
    final code = await services.startPairing(peer);
    if (code != null) return;
    showToast(teksty.pairStartFailed);
  }


  /// Pisanie na tamtym urządzeniu. Własna trasa na całe okno, także
  /// w układzie dwukolumnowym: pole pisania ma być jedynym polem na ekranie.
  void _piszNaTamtym(Peer peer) {
    Navigator.of(context, rootNavigator: true).push(ChattPageRoute<void>(
      builder: (_) => RemoteKeyboardScreen(peer: peer),
    ));
  }

  /// Skanowanie kodu z drugiego urządzenia. Po udanym skanie tożsamość jest
  /// potwierdzona po tej stronie od razu: widzieliśmy tamten ekran.
  Future<void> _scanQr() async {
    final peer = await Navigator.of(context).push<Peer>(
      ChattPageRoute(builder: (_) => const ScanScreen()),
    );
    if (!mounted || peer == null) return;
    showToast(context.l10n.pairedWith(peer.displayName));
  }

  /// Spinacz. Gdy w schowku leży plik albo obrazek, najpierw pytamy, o którą
  /// z dwóch dróg chodzi: na telefonie nie ma Ctrl+V, więc bez tego pytania
  /// wklejanie nie miałoby się skąd wziąć.
  Future<void> _attachFile() async {
    if (await clipboardHasFiles()) {
      if (!mounted) return;
      final zeSchowka = await _askWhereFrom();
      if (zeSchowka == null || !mounted) return;
      if (zeSchowka) return _pasteFiles(report: true);
    }
    await _pickFiles();
  }

  /// Karta z dwiema drogami do pliku. `null` znaczy „zamknięta bez wyboru".
  Future<bool?> _askWhereFrom() => showChattSheet<bool>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: Text(context.l10n.attachFromClipboard),
                onTap: () => Navigator.pop(sheet, true),
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(context.l10n.attachFromDevice),
                onTap: () => Navigator.pop(sheet, false),
              ),
            ],
          ),
        ),
      );

  /// Wybór plików: można zaznaczyć kilka naraz, wyślą się po kolei. Android
  /// ma własne okno przez kanał (patrz [FileActions.pickFiles]), pulpit
  /// bierze systemowe z `file_selector`.
  Future<void> _pickFiles() async {
    final paths = Platform.isAndroid
        ? await FileActions.pickFiles()
        : (await openFiles()).map((f) => f.path).toList();
    if (paths.isEmpty) return;
    await _sendPaths(paths);
  }

  /// Ze schowka wprost do rozmowy. [report] włącza komunikat „nic tam nie ma":
  /// ma sens po wybraniu pozycji w karcie, nie ma po Ctrl+V, gdzie pustym
  /// schowkiem plików zajmuje się zwykłe wklejanie tekstu.
  Future<void> _pasteFiles({bool report = false}) async {
    final teksty = context.l10n;
    final paths = await pasteClipboardFiles(imageName: teksty.pastedImageName);
    if (!mounted) return;
    if (paths.isEmpty) {
      if (report) showToast(teksty.pasteNothing);
      return;
    }
    await _sendPaths(paths);
  }

  /// Obrazek, GIF albo naklejka wstawione z klawiatury. Na telefonie to jest
  /// najkrótsza droga do wysłania obrazka, a bez tej obsługi Android odmawia
  /// wstawienia i pokazuje, że pole nie przyjmuje takiej treści. Bajty
  /// przynosi silnik Fluttera, więc nie ma tu dostawcy treści ani uprawnień.
  Future<void> _insertFromKeyboard(KeyboardInsertedContent content) async {
    final teksty = context.l10n;
    final bytes = content.data;
    if (bytes == null || bytes.isEmpty) return;
    final path = await saveInsertedContent(bytes,
        mimeType: content.mimeType, name: teksty.pastedImageName);
    if (path == null || !mounted) return;
    await _sendPaths([path]);
  }

  Future<void> _sendPaths(Iterable<String> paths) {
    _zglosUzycie();
    return ref
        .read(appServicesProvider)
        .sendFiles(widget.conversationId, paths);
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.read(appServicesProvider);
    final messages = ref.watch(messagesProvider(widget.conversationId));
    // Podglądy stron: czytamy na żywo, żeby przestawienie przełącznika
    // w Ustawieniach było widać w otwartej rozmowie bez wchodzenia w nią
    // od nowa.
    final podgladyOdnosnikow =
        ref.watch(settingsProvider).value?.linkPreviews ?? false;
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
    final wszystkie = messages.valueOrNull;
    if (wszystkie != null) _zauwazNowe(wszystkie, _search.text.trim());
    final ruch = ChattMotion.of(context);

    final szeroko = czyDwupanel(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.l10n.searchHint,
                  // Bez ramki i tła, ale na wysokość celu dotyku (48 dp).
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              )
            : Row(
                children: [
                  InitialsAvatar(name: peer.displayName, header: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(peer.displayName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                switch (_online) {
                                  null => peerAddressLabel(peer,
                                      radio: ref
                                          .read(appServicesProvider)
                                          .bluetoothAddon
                                          .value),
                                  true => context.l10n.peerOnline,
                                  false => context.l10n.peerOffline,
                                },
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: switch (_online) {
                                        true =>
                                          ChattTokens.of(context).presence,
                                        false =>
                                          Theme.of(context).colorScheme.error,
                                        null => null,
                                      },
                                    ),
                              ),
                            ),
                            ProtocolBadge(
                              peer: peer,
                              padding: const EdgeInsets.only(left: 8),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          // Na telefonie na wierzchu stoją tylko tarcza i menu, oba z celem
          // dotyku 48 dp; szukanie i klawiatura z PC są w menu. Na szerokim
          // oknie obsługiwanym myszą miejsca nie brakuje i zostają obok.
          if (szeroko || _searching)
            IconButton(
              tooltip:
                  _searching ? context.l10n.close : context.l10n.searchTooltip,
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: _toggleSearch,
            ),
          // Dodatek „Klawiatura z PC". Wyłączony nie zajmuje miejsca; pisać
          // wolno tylko na urządzenie z potwierdzoną tożsamością.
          if (szeroko)
            ValueListenableBuilder<bool>(
              valueListenable: services.keyboardAddon,
              builder: (context, dodatek, _) => dodatek
                  ? IconButton(
                      tooltip: peer.verified
                          ? context.l10n.remoteKeyboardOpen
                          : context.l10n.remoteKeyboardNeedsVerified,
                      icon: const Icon(Icons.keyboard_alt_outlined),
                      onPressed:
                          peer.verified ? () => _piszNaTamtym(peer) : null,
                    )
                  : const SizedBox.shrink(),
            ),
          // Cztery stany, bo od protokołu 5 szyfrowanie i potwierdzenie
          // tożsamości to dwie różne rzeczy:
          //   klucz nieznany:  rozmowy jeszcze nie było; klucz przyjdzie
          //                      z `/info` przy pierwszym kontakcie,
          //   bez klucza:      `/info` odpowiedziało bez niego, po drugiej
          //                      stronie starsza wersja i nie ma jak rozmawiać,
          //   klucz jest:      ruch szyfrowany, ale nie wiadomo, czyj to
          //                      klucz,
          //   potwierdzony:    porównaliście kod, wiadomo z kim rozmawiacie.
          ValueListenableBuilder<Set<String>>(
            valueListenable: services.peersWithoutKey,
            builder: (context, bezKlucza, _) {
              final maKlucz = peer.publicKey != null;
              final k = ChattTokens.of(context);
              final (ikona, kolory, opis) = switch ((
                maKlucz,
                peer.verified,
                bezKlucza.contains(peer.guid),
              )) {
                (false, _, true) => (
                    Icons.gpp_bad_outlined,
                    k.dangerNote,
                    context.l10n.shieldNoEncryption,
                  ),
                (false, _, false) => (
                    Icons.shield_outlined,
                    k.warningNote,
                    context.l10n.shieldKeyUnknown,
                  ),
                (true, false, _) => (
                    Icons.gpp_maybe_outlined,
                    k.warningNote,
                    context.l10n.shieldEncrypted,
                  ),
                (true, true, _) => (
                    Icons.verified_user,
                    k.verifiedNote,
                    context.l10n.shieldVerified,
                  ),
              };
              // Tarcza na tle w kolorze stanu: widać ją kątem oka, bez
              // czytania podpowiedzi.
              return IconButton(
                tooltip: opis,
                style: IconButton.styleFrom(backgroundColor: kolory.background),
                icon: Icon(ikona, color: kolory.icon),
                // Zawsze otwiera panel, także po potwierdzeniu: odciski mają
                // dać się porównać w dowolnym momencie.
                onPressed: () {
                  // Klucz, którego jeszcze nie ma, dociąga się w tle; panel
                  // zmieni stan, gdy tylko `/info` odpowie.
                  unawaited(services
                      .ensurePeerKey(peer)
                      .catchError((Object _) {}));
                  showSecuritySheet(
                    context,
                    peer: peer,
                    onPair: _startPairing,
                    onScan: _scanQr,
                  );
                },
              );
            },
          ),
          // Menu rozmowy: historia (issue #36), a na telefonie także szukanie
          // i klawiatura z PC.
          PopupMenuButton<_MenuRozmowy>(
            tooltip: context.l10n.historyMenu,
            onSelected: (akcja) => switch (akcja) {
              _MenuRozmowy.szukaj => _toggleSearch(),
              _MenuRozmowy.klawiatura => _piszNaTamtym(peer),
              _MenuRozmowy.udostepnij => showShareHistoryDialog(
                  context,
                  services: services,
                  peer: peer,
                  conversationId: widget.conversationId,
                ),
              _MenuRozmowy.popros => requestHistoryFrom(
                  context,
                  services: services,
                  peer: peer,
                  conversationId: widget.conversationId,
                ),
            },
            itemBuilder: (menu) => [
              // Przy otwartym szukaniu w nagłówku stoi X; pozycja w menu
              // zamykałaby je pod nazwą „Szukaj".
              if (!szeroko && !_searching)
                PopupMenuItem(
                  value: _MenuRozmowy.szukaj,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.search),
                    title: Text(menu.l10n.searchTooltip),
                  ),
                ),
              if (!szeroko) ...[
                // Bez zielonej tarczy pozycja zostaje, wyszarzona i z
                // powodem: tak samo jak przycisk na szerokim oknie.
                if (services.keyboardAddon.value)
                  PopupMenuItem(
                    value: _MenuRozmowy.klawiatura,
                    enabled: peer.verified,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      enabled: peer.verified,
                      leading: const Icon(Icons.keyboard_alt_outlined),
                      title: Text(menu.l10n.remoteKeyboardOpen),
                      subtitle: peer.verified
                          ? null
                          : Text(menu.l10n.remoteKeyboardNeedsVerified),
                    ),
                  ),
              ],
              PopupMenuItem(
                value: _MenuRozmowy.udostepnij,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text(menu.l10n.historyShare),
                ),
              ),
              PopupMenuItem(
                value: _MenuRozmowy.popros,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restore),
                  title: Text(menu.l10n.historyRequest),
                ),
              ),
            ],
          ),
        ],
      ),
      // Dwie drogi na skróty, obie omijają spinacz: przeciągnięcie plików
      // z pulpitu na okno i Ctrl+V. Na Androidzie nie ma ani skąd przeciągać,
      // ani czym wcisnąć Ctrl, więc tam zostaje spinacz i klawiatura.
      body: PasteShortcut(
        onPaste: () => unawaited(_pasteFiles()),
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (detail) async {
            setState(() => _dragging = false);
            await _sendPaths(detail.files.map((f) => f.path));
          },
          child: Stack(
            children: [
              Column(
        children: [
          Expanded(
            // Start i koniec wysyłki muszą przerysować dymki, żeby pasek
            // postępu pojawił się także wtedy, gdy wiadomość trafiła na
            // ekran ułamek sekundy przed rejestracją transferu.
            // Przywracanie historii też: wpis pliku przestaje „czekać na
            // przesłanie", gdy przywracanie się skończy.
            child: ListenableBuilder(
              listenable: Listenable.merge(
                  [services.transfersRevision, services.incomingHistory]),
              builder: (context, _) => messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text(context.l10n.errorWithDetails('$error'))),
              data: (all) {
                final query = _search.text.trim();
                final items = query.isEmpty
                    ? all
                    : all.where((m) => messageMatches(m, query)).toList();
                if (items.isEmpty && query.isNotEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        context.l10n.searchNothingFound(query),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  );
                }
                // Wiersz ma klucz wiadomości: nowa na dole przesuwa indeksy,
                // a stan (wejście, podgląd strony) zostaje przy swojej.
                final indeksy = {
                  for (var i = 0; i < items.length; i++)
                    items[i].id: items.length - 1 - i,
                };
                final lista = ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: items.length,
                  findChildIndexCallback: (klucz) => klucz is ValueKey<int>
                      ? indeksy[klucz.value]
                      : null,
                  itemBuilder: (context, index) {
                    // reverse: true -> element 0 na dole, czytamy od końca.
                    final pozycja = items.length - 1 - index;
                    final message = items[pozycja];
                    final dymek = _MessageBubble(
                      message: message,
                      services: ref.read(appServicesProvider),
                      query: query,
                      linkPreviews: podgladyOdnosnikow,
                      onRetry: () => ref
                          .read(appServicesProvider)
                          .retryMessage(message.id),
                      onDelete: () => _deleteMessage(message),
                    );
                    // Dymki pokazują samą godzinę, więc pierwszy dymek
                    // każdego dnia dostaje nad sobą datę. Bez tego
                    // przywrócona historia z kilku miesięcy zlewa się w jedno.
                    final starsza = pozycja > 0 ? items[pozycja - 1] : null;
                    final zData = starsza == null ||
                        !_tenSamDzien(starsza.createdAt, message.createdAt);
                    // Nowy dymek wjeżdża w górę, data nad nim razem z nim.
                    return EnterOnce(
                      key: ValueKey(message.id),
                      animate: _wjezdzaja.contains(message.id),
                      duration: ruch.bubble,
                      curve: ruch.bubbleCurve,
                      shift: ruch.bubbleShift,
                      child: zData
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _DateSeparator(date: message.createdAt),
                                dymek,
                              ],
                            )
                          : dymek,
                    );
                  },
                );
                // Na pulpicie zaznacza się myszą, przez kilka dymków naraz.
                // Na dotyku `SelectionArea` przechwyciłaby przytrzymanie
                // i menu dymka (kopiuj, usuń) przestałoby się otwierać, więc
                // tam zaznaczanie idzie osobną pozycją w tym menu.
                return dotykowy ? lista : SelectionArea(child: lista);
              },
              ),
            ),
          ),
          HistoryProgressBar(
            services: services,
            conversationId: widget.conversationId,
          ),
          // Pliki, które właśnie do nas płyną (po akceptacji), z postępem.
          ValueListenableBuilder<Map<String, IncomingTransfer>>(
            valueListenable: services.incomingTransfers,
            builder: (context, transfers, _) {
              final here = transfers.values
                  .where((t) => t.conversationId == widget.conversationId)
                  .toList(growable: false);
              if (here.isEmpty) return const SizedBox.shrink();
              // Klucz pliku: pasek pamięta, gdzie jest, i po końcu jednego
              // pliku drugi nie przejmuje jego paska.
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final t in here)
                    _IncomingTransferTile(
                        key: ValueKey(t.messageGuid), transfer: t),
                ],
              );
            },
          ),
          if (_udostepnione != null)
            _PasekUdostepnionych(
              udostepnione: _udostepnione!,
              onRemove: _odrzucUdostepnione,
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
                    // Własny węzeł semantyki: bez niego czytnik ekranu
                    // ogłaszał całą treść ekranu jako pole tekstowe, z listą
                    // wiadomości i przyciskami w środku.
                    child: Semantics(
                      container: true,
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        // Przycisk „wstaw obrazek" na klawiaturze (GIF-y,
                        // naklejki, zrzuty). Bez tego Android odmawia wstawienia,
                        // bo domyślnie pole nie deklaruje żadnego typu treści.
                        contentInsertionConfiguration:
                            ContentInsertionConfiguration(
                                onContentInserted: _insertFromKeyboard),
                        decoration: InputDecoration(
                          hintText: context.l10n.messageHint,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
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
              if (_dragging) _DropHint(),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MenuRozmowy { szukaj, klawiatura, udostepnij, popros }

/// Pliki udostępnione z innej aplikacji, czekające na „Wyślij". Liczba jest
/// od razu, kopie dopiero po skopiowaniu.
class _Udostepnione {
  final IncomingShare share;
  final Future<List<SharedFile>> files;

  /// Gotowe kopie; null, dopóki kopiowanie trwa.
  List<SharedFile>? ready;

  _Udostepnione(this.share, this.files);
}

/// Pasek nad polem wiadomości: ile plików czeka, ich nazwy i łączny rozmiar,
/// krzyżyk do rezygnacji. Wysyła je „Wyślij" razem z tekstem z pola.
class _PasekUdostepnionych extends StatelessWidget {
  final _Udostepnione udostepnione;
  final VoidCallback onRemove;

  const _PasekUdostepnionych(
      {required this.udostepnione, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final k = ChattTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final pliki = udostepnione.ready;
    final opis = pliki == null
        ? context.l10n.sharePreparing(udostepnione.share.fileCount)
        : '${context.l10n.shareFiles(pliki.length)} · '
            '${formatFileSize(pliki.fold<int>(0, (suma, plik) => suma + plik.size))}';
    final nazwy = pliki?.map((plik) => plik.name).join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: k.surface2,
          borderRadius: BorderRadius.circular(k.radiusCard),
          border: Border.all(color: k.outline),
        ),
        child: Row(
          children: [
            if (pliki == null)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.attach_file, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(opis, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (nazwy != null && nazwy.isNotEmpty)
                    Text(
                      nazwy,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: k.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.l10n.shareDontSend,
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

bool _tenSamDzien(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Data nad pierwszym dymkiem dnia: „Dzisiaj", „Wczoraj" albo pełna data.
class _DateSeparator extends StatelessWidget {
  final DateTime date;

  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final k = ChattTokens.of(context);
    final teraz = DateTime.now();
    final wczoraj = DateTime(teraz.year, teraz.month, teraz.day - 1);
    final napis = _tenSamDzien(date, teraz)
        ? context.l10n.dateToday
        : _tenSamDzien(date, wczoraj)
            ? context.l10n.dateYesterday
            : context.l10n.dateSeparator(date);
    final etykieta = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: k.separatorBackground,
        borderRadius: BorderRadius.circular(k.separatorLine ? 4 : 999),
        border: k.separatorLine ? Border.all(color: k.outline) : null,
        boxShadow: k.separatorShadow,
      ),
      child: Text(
        k.overlineText(napis),
        style: k.separator.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
    // Precyzja: linia przez całą szerokość z etykietą w środku.
    return Padding(
      padding: EdgeInsets.only(
          top: k.separatorLine ? 10 : 12, bottom: k.separatorLine ? 4 : 6),
      child: k.separatorLine
          ? Row(
              children: [
                Expanded(child: Divider(color: k.outline)),
                const SizedBox(width: 8),
                etykieta,
                const SizedBox(width: 8),
                Expanded(child: Divider(color: k.outline)),
              ],
            )
          : Center(child: etykieta),
    );
  }
}

/// Przykrywka pokazywana, gdy nad oknem wiszą przeciągane pliki.
class _DropHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.primary, width: 2),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.file_download_outlined,
                  size: 48, color: scheme.onPrimaryContainer),
              const SizedBox(height: 12),
              Text(
                context.l10n.dropFilesHint,
                style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 16,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final AppServices services;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  /// Szukany napis do podświetlenia. Pusty znaczy „nikt nie szuka".
  final String query;

  /// Czy pod dymkiem wolno pokazać kartę z podglądem strony. Bierze się
  /// wprost z przełącznika w Ustawieniach, więc jego zmiana widać od razu.
  final bool linkPreviews;

  const _MessageBubble({
    required this.message,
    required this.services,
    required this.onRetry,
    required this.onDelete,
    required this.linkPreviews,
    this.query = '',
  });

  /// Ścieżka do zdjęcia, jeśli ta wiadomość niesie obrazek leżący na dysku.
  /// null znaczy „to nie jest zdjęcie, które umiemy pokazać sami": zwykły
  /// plik, plik jeszcze nieodebrany albo skasowany po odebraniu.
  String? _imagePath() {
    final path = message.filePath;
    if (path == null || !isImageFile(message.fileName)) return null;
    return File(path).existsSync() ? path : null;
  }

  /// Stuknięcie w kafelek pliku. Zdjęcie otwiera się w podglądzie w
  /// aplikacji, reszta systemowym skojarzeniem.
  void _tapFile(BuildContext context) {
    final image = _imagePath();
    if (image == null) {
      unawaited(_openFile(context));
      return;
    }
    _openImage(context, image);
  }

  /// Podgląd zdjęcia na pełnym ekranie. Akcje w jego pasku to te same, co w
  /// menu dymka, bo po obejrzeniu zdjęcia chce się zwykle z nim coś zrobić,
  /// a cofanie się do rozmowy po to samo menu byłoby drogą naokoło.
  void _openImage(BuildContext context, String path) {
    Navigator.of(context).push(ChattPageRoute<void>(
      builder: (podglad) => ImageViewScreen(
        path: path,
        name: message.fileName,
        actions: [
          if (canCopyImage)
            IconButton(
              tooltip: podglad.l10n.copyImage,
              icon: const Icon(Icons.image_outlined),
              onPressed: () => _copyImage(podglad),
            ),
          if (message.direction == MessageDirection.incoming)
            IconButton(
              tooltip: podglad.l10n.saveFile,
              icon: const Icon(Icons.save_alt),
              onPressed: () => _saveFile(podglad),
            ),
          IconButton(
            tooltip: Platform.isAndroid
                ? podglad.l10n.shareFile
                : podglad.l10n.showFolder,
            icon: Icon(Platform.isAndroid ? Icons.share : Icons.folder_open),
            onPressed: () => _revealFile(podglad),
          ),
          IconButton(
            tooltip: podglad.l10n.openFile,
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openFile(podglad),
          ),
        ],
      ),
    ));
  }

  /// Otwarcie pliku systemowym skojarzeniem; komunikat tylko wtedy, gdy się
  /// nie udało. Ścieżka do skopiowania zostaje na wypadek systemu, w którym
  /// nie ma czym otworzyć pliku: na Androidzie znaczy to brak kanału, bo
  /// samo otwieranie idzie przez dostawcę treści i melduje się osobno.
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

  /// Wyniesienie pliku z katalogu aplikacji tam, gdzie użytkownik go szuka.
  /// Komunikat mówi gdzie, bo inaczej „zapisano" nic nie znaczy.
  Future<void> _saveFile(BuildContext context) async {
    final teksty = context.l10n;
    final wynik = await services.saveFileFromMessage(message);
    final napis = switch (wynik.result) {
      SaveResult.saved => teksty.savedTo(wynik.where ?? ''),
      // Zamknięte okno zapisu to decyzja użytkownika, nie błąd.
      SaveResult.cancelled => null,
      SaveResult.missing => teksty.fileGone,
      SaveResult.unsupported => teksty.saveUnsupported,
      SaveResult.failed => teksty.saveFailed,
    };
    if (napis == null) return;
    showToast(napis);
  }

  void _report(BuildContext context, FileActionResult result) {
    final path = message.filePath ?? '';
    switch (result) {
      case FileActionResult.ok:
        break;
      case FileActionResult.missing:
        showToast(context.l10n.fileGone);
      // Android/iOS: bez wtyczki platformowej zostaje ścieżka do skopiowania.
      case FileActionResult.unsupported:
        showToast(
          path,
          actionLabel: context.l10n.copy,
          onAction: () => Clipboard.setData(ClipboardData(text: path)),
        );
      case FileActionResult.failed:
        showToast(context.l10n.fileOpenFailed);
    }
  }

  /// Obraz do schowka: tylko na pulpicie i tylko dla obrazków, bo tylko tam
  /// jest co wkleić. Na Androidzie tę rolę pełni „Udostępnij".
  Future<void> _copyImage(BuildContext context) async {
    final teksty = context.l10n;
    final path = message.filePath;
    final ok = path != null && await copyImageToClipboard(path);
    showToast(ok ? teksty.imageCopied : teksty.imageCopyFailed);
  }

  void _fileMenu(BuildContext context) {
    final path = message.filePath ?? '';
    showChattSheet<void>(
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
              // Android nie ma menedżera plików do pokazania, tam ta sama
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
            if (canCopyImage && isImageFile(message.fileName))
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(context.l10n.copyImage),
                onTap: () {
                  Navigator.pop(sheet);
                  _copyImage(context);
                },
              ),
            if (message.direction == MessageDirection.incoming)
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: Text(context.l10n.saveFile),
                subtitle: Text(context.l10n.saveFileHint),
                onTap: () {
                  Navigator.pop(sheet);
                  _saveFile(context);
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
            _deleteTile(context, sheet),
          ],
        ),
      ),
    );
  }

  void _menu(BuildContext context) => message.kind == MessageKind.file
      ? _fileMenu(context)
      : _textMenu(context);

  /// Menu tekstowego dymka: skopiowanie treści, zaznaczenie fragmentu
  /// i skasowanie wpisu u siebie.
  void _textMenu(BuildContext context) {
    // Odnośniki z treści dostają własne pozycje. To pewna droga do strony
    // tam, gdzie dotknięcie samego napisu bywa przechwycone przez
    // zaznaczanie tekstu (pulpit, `SelectionArea`).
    final links = findLinks(message.body);
    showChattSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Wrap(
          children: [
            for (final link in links.take(5))
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text(context.l10n.linkOpenTitle),
                subtitle: Text(shortenLink(link.uri),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(sheet);
                  confirmAndOpenLink(context, link.uri);
                },
              ),
            if (links.isNotEmpty) const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(context.l10n.copyText),
              onTap: () {
                Navigator.pop(sheet);
                Clipboard.setData(ClipboardData(text: message.body));
              },
            ),
            // Na pulpicie tej pozycji nie ma: tam zaznacza się wprost
            // w rozmowie, kursorem, i to działa przez kilka dymków naraz.
            if (dotykowy)
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: Text(context.l10n.selectText),
                onTap: () {
                  Navigator.pop(sheet);
                  _selectText(context);
                },
              ),
            _deleteTile(context, sheet),
          ],
        ),
      ),
    );
  }

  /// Zaznaczanie fragmentu na telefonie. Osobna karta, bo w liście dymków
  /// zaznaczanie i przytrzymanie otwierające menu biją się o ten sam gest,
  /// a menu jest jedyną drogą do skasowania wiadomości.
  void _selectText(BuildContext context) {
    showChattSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.selectTextHint,
                style: TextStyle(
                  color: Theme.of(sheet).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(message.body,
                      style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kasowanie dotyczy tylko tego urządzenia: protokół nie ma jak kazać
  /// drugiej stronie zapomnieć czegoś, co już dostała. Mówi o tym napis pod
  /// pozycją, żeby nikt nie liczył na cofnięcie wysłanej wiadomości.
  Widget _deleteTile(BuildContext context, BuildContext sheet) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.delete_outline, color: scheme.error),
      title: Text(context.l10n.deleteMessage,
          style: TextStyle(color: scheme.error)),
      subtitle: Text(context.l10n.deleteMessageHint),
      onTap: () {
        Navigator.pop(sheet);
        onDelete();
      },
    );
  }

  /// Treść z podświetlonym szukanym napisem i klikalnymi odnośnikami.
  /// Kolor podświetlenia bierze się z palety, więc czyta się i na własnym
  /// dymku, i na cudzym, w obu motywach.
  ///
  /// [linkify] gasimy dla nazwy pliku: „odnośnik" w nazwie pliku prowadziłby
  /// donikąd i tylko mylił.
  Widget _highlighted(BuildContext context, String text, TextStyle style,
      {bool linkify = true}) {
    final k = ChattTokens.of(context);
    return LinkedText(
      text: text,
      style: style,
      query: query,
      linkify: linkify,
      highlightStyle: TextStyle(
        backgroundColor: k.searchHit,
        color: k.onSearchHit,
        fontWeight: FontWeight.w700,
      ),
      onTapLink: (uri) => confirmAndOpenLink(context, uri),
    );
  }

  /// Treść dymka: tekst albo kafelek pliku (nazwa, rozmiar, pasek postępu
  /// podczas trwającej wysyłki). Kafelek pliku otwiera go po kliknięciu,
  /// przytrzymanie daje menu (otwórz / pokaż folder / kopiuj ścieżkę).
  Widget _content(BuildContext context, bool mine, ColorScheme scheme) {
    final k = ChattTokens.of(context);
    final textColor = mine ? k.onBubbleMine : k.onBubbleTheirs;
    final metaColor = mine ? k.bubbleMineMeta : k.bubbleTheirsMeta;
    final tresc = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    if (message.kind != MessageKind.file) {
      // Przytrzymanie łapie cały dymek (patrz `build`), a nie sam napis:
      // inaczej menu otwierałoby się tylko dokładnie na literach.
      final tekst = _highlighted(
          context, message.body, tresc.copyWith(color: textColor));
      // Podgląd tylko dla pierwszego odnośnika w wiadomości. Karta pod każdym
      // adresem z wklejonej listy zamieniłaby dymek w tablicę ogłoszeń,
      // a każdy adres to osobne pytanie do obcego serwera.
      final links = linkPreviews ? findLinks(message.body) : const <LinkSpan>[];
      if (links.isEmpty) return tekst;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          tekst,
          LinkPreviewCard(
            url: links.first.uri,
            service: services.linkPreviews,
            mine: mine,
          ),
        ],
      );
    }
    final progress = services.progressOf(message.id);
    final thumbnail = _thumbnail(context);
    final path = message.filePath;
    final dostepny = path != null && File(path).existsSync();
    // Przywrócony wpis bez treści czeka na bajty, dopóki trwa przywracanie
    // tej rozmowy; potem plik jest po prostu niedostępny.
    final przywracanie = services.incomingHistory.value;
    final czeka = path == null &&
        message.restoredAt != null &&
        przywracanie != null &&
        !przywracanie.finished &&
        przywracanie.conversationId == message.conversationId;
    return InkWell(
      onTap: () => _tapFile(context),
      hoverDuration: ChattMotion.of(context).hover,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (thumbnail != null) ...[thumbnail, const SizedBox(height: 8)],
          Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              thumbnail != null
                  ? Icons.image_outlined
                  : Icons.insert_drive_file_outlined,
              color: textColor),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _highlighted(
                  context,
                  message.fileName ?? context.l10n.fileFallbackName,
                  tresc.copyWith(
                      color: textColor, fontWeight: FontWeight.w600),
                  linkify: false,
                ),
                // Rozmiar to wartość techniczna: font o stałej szerokości.
                Text(formatFileSize(message.fileSize),
                    style: k.mono.copyWith(color: metaColor)),
                if (!dostepny)
                  Text(
                    czeka
                        ? context.l10n.fileAwaiting
                        : context.l10n.fileUnavailable,
                    style: k.caption.copyWith(
                        color: metaColor, fontStyle: FontStyle.italic),
                  ),
                if (progress != null) ...[
                  const SizedBox(height: 6),
                  ValueListenableBuilder<double>(
                    valueListenable: progress,
                    builder: (_, value, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SmoothProgress(
                        value: value,
                        minHeight: 5,
                        backgroundColor: textColor.withValues(alpha: 0.22),
                        color: mine ? k.onBubbleMine : scheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Zapisanie odebranego pliku jednym dotknięciem. Przy własnym
          // pliku nie ma czego zapisywać, leży u nas od początku.
          if (message.direction == MessageDirection.incoming && dostepny) ...[
            const SizedBox(width: 4),
            // Gęstość z motywu: na telefonie pełne 48 dp celu dotyku.
            IconButton(
              tooltip: context.l10n.saveFile,
              icon: Icon(Icons.save_alt, size: 20, color: textColor),
              onPressed: () => _saveFile(context),
            ),
          ],
        ],
          ),
        ],
      ),
    );
  }

  /// Miniatura obrazka. Dekodujemy dopiero to, co leży na dysku, czyli plik
  /// **już przyjęty** przez użytkownika, zapowiedź od obcego nie trafia do
  /// dekodera. Uszkodzony albo spreparowany obrazek kończy się pustym
  /// miejscem, a nie wywrotką listy.
  Widget? _thumbnail(BuildContext context) {
    final path = _imagePath();
    if (path == null) return null;
    final file = File(path);
    final k = ChattTokens.of(context);
    return ClipRRect(
      borderRadius:
          BorderRadius.circular((k.bubbleRadius - 4).clamp(4, 10).toDouble()),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220, maxWidth: 260),
        child: Image.file(
          file,
          cacheWidth: 520,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final k = ChattTokens.of(context);
    final mine = message.direction == MessageDirection.outgoing;
    final failed = mine && message.status == MessageStatus.failed;
    final meta = mine ? k.bubbleMineMeta : k.bubbleTheirsMeta;
    final duzy = Radius.circular(k.bubbleRadius);
    final ogon = Radius.circular(k.bubbleTail);

    // Przytrzymanie dowolnego miejsca w dymku otwiera menu: kopiowanie,
    // a przy pliku także otwieranie i pokazanie w katalogu.
    final bubble = GestureDetector(
      // Bez `opaque` dotyk liczyłby się tylko dokładnie na literach: domyślne
      // `deferToChild` przepuszcza tło i marginesy dymka.
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _menu(context),
      // Na pulpicie naturalnym gestem jest prawy przycisk, a nie trzymanie
      // wciśniętego lewego. Przytrzymanie zostaje, bo nikomu nie przeszkadza.
      onSecondaryTap: dotykowy ? null : () => _menu(context),
      child: Container(
      // Górna granica w pikselach, nie tylko ułamek szerokości: na monitorze
      // dymek ciągnący się przez pół metra jest nie do czytania.
      constraints: BoxConstraints(
          maxWidth: math.min(
              MediaQuery.sizeOf(context).width * k.bubbleMaxFraction, 560)),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: k.bubblePadding,
      decoration: BoxDecoration(
        color: mine ? k.bubbleMine : k.bubbleTheirs,
        border: !mine && k.bubbleTheirsBorder != null
            ? Border.all(color: k.bubbleTheirsBorder!)
            : null,
        boxShadow: k.bubbleShadow,
        borderRadius: BorderRadius.only(
          topLeft: duzy,
          topRight: duzy,
          bottomLeft: mine ? duzy : ogon,
          bottomRight: mine ? ogon : duzy,
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
              // Przywrócona z kopii rozmówcy: jego słowo, nic jej nie
              // podpisuje, więc to widać przy każdym dymku.
              if (message.restoredAt != null) ...[
                Tooltip(
                  message: context.l10n.messageRestored(message.restoredAt!),
                  child: Icon(
                    Icons.history,
                    size: 13,
                    semanticLabel:
                        context.l10n.messageRestored(message.restoredAt!),
                    color: meta,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                formatClock(message.createdAt),
                style: k.caption.copyWith(color: meta),
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
                  // Błąd ma własny kształt ikony; kolor napisu dymka trzyma
                  // kontrast w każdym stylu (czerwień na dymku go nie ma).
                  color: failed ? k.onBubbleMine : meta,
                ),
              ],
            ],
          ),
        ],
      ),
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

/// Plik, który właśnie do nas płynie (zgoda już wydana), pasek postępu nad
/// polem tekstowym. Wpis znika, gdy plik jest kompletny i staje się dymkiem.
class _IncomingTransferTile extends StatelessWidget {
  final IncomingTransfer transfer;

  const _IncomingTransferTile({super.key, required this.transfer});

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
                child: SmoothProgress(value: value, minHeight: 5),
              ),
            ],
          );
        },
      ),
    );
  }
}
