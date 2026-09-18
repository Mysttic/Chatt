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
import '../../data/db.dart';
import '../../services/app_services.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../widgets/common.dart';
import '../widgets/link_confirm.dart';
import '../widgets/link_preview_card.dart';
import '../widgets/linked_text.dart';
import '../widgets/paste_shortcut.dart';
import '../widgets/security_sheet.dart';
import '../widgets/toasts.dart';
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

  /// Szukanie filtruje listę dymków w miejscu. Pusty napis znaczy „nie szukam",
  /// wtedy pole w pasku w ogóle się nie pokazuje.
  final _search = TextEditingController();
  bool _searching = false;

  /// Pliki wiszą nad oknem (przeciąganie z pulpitu). Podpowiedź pokazuje się
  /// tylko wtedy, bo poza tym nie ma o czym mówić.
  bool _dragging = false;

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
    _search.dispose();
    super.dispose();
  }

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

  Future<void> _send() async {
    final text = _input.text;
    _input.clear();
    await ref.read(appServicesProvider).sendText(widget.conversationId, text);
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


  /// Skanowanie kodu z drugiego urządzenia. Po udanym skanie tożsamość jest
  /// potwierdzona po tej stronie od razu: widzieliśmy tamten ekran.
  Future<void> _scanQr() async {
    final peer = await Navigator.of(context).push<Peer>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
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
  Future<bool?> _askWhereFrom() => showModalBottomSheet<bool>(
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

  Future<void> _sendPaths(Iterable<String> paths) => ref
      .read(appServicesProvider)
      .sendFiles(widget.conversationId, paths);

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
                  border: InputBorder.none,
                ),
              )
            : Row(
                children: [
                  InitialsAvatar(name: peer.displayName, radius: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(peer.displayName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          switch (_online) {
                            null => '${peer.host}:${peer.port}',
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
            tooltip: _searching ? context.l10n.close : context.l10n.searchTooltip,
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
          // Trzy stany, bo od protokołu 5 szyfrowanie i potwierdzenie
          // tożsamości to dwie różne rzeczy:
          //   brak klucza:   po drugiej stronie starsza wersja, nie ma jak
          //                    rozmawiać (i nie udajemy, że jest inaczej),
          //   klucz jest:    ruch szyfrowany, ale nie wiadomo, czyj to
          //                    klucz,
          //   potwierdzony:  porównaliście kod, wiadomo z kim rozmawiacie.
          Builder(builder: (context) {
            final maKlucz = peer.publicKey != null;
            final (ikona, kolor, opis) = switch ((maKlucz, peer.verified)) {
              (false, _) => (
                  Icons.gpp_bad_outlined,
                  Theme.of(context).colorScheme.error,
                  context.l10n.shieldNoEncryption,
                ),
              (true, false) => (
                  Icons.lock_outline,
                  null,
                  context.l10n.shieldEncrypted,
                ),
              (true, true) => (
                  Icons.verified_user,
                  Colors.green,
                  context.l10n.shieldVerified,
                ),
            };
            return IconButton(
              tooltip: opis,
              icon: Icon(ikona, color: kolor),
              // Zawsze otwiera panel, także po potwierdzeniu: odciski mają
              // dać się porównać w dowolnym momencie, a nie tylko raz.
              onPressed: () => showSecuritySheet(
                context,
                peer: peer,
                onPair: _startPairing,
                onScan: _scanQr,
              ),
            );
          }),
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
            child: ValueListenableBuilder<int>(
              valueListenable: services.transfersRevision,
              builder: (context, _, _) => messages.when(
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
                final lista = ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    // reverse: true -> element 0 na dole, czytamy od końca.
                    final message = items[items.length - 1 - index];
                    return _MessageBubble(
                      message: message,
                      services: ref.read(appServicesProvider),
                      query: query,
                      linkPreviews: podgladyOdnosnikow,
                      onRetry: () => ref
                          .read(appServicesProvider)
                          .retryMessage(message.id),
                      onDelete: () => _deleteMessage(message),
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
          // Pliki, które właśnie do nas płyną (po akceptacji), z postępem.
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
                      // Przycisk „wstaw obrazek" na klawiaturze (GIF-y,
                      // naklejki, zrzuty). Bez tego Android odmawia wstawienia,
                      // bo domyślnie pole nie deklaruje żadnego typu treści.
                      contentInsertionConfiguration:
                          ContentInsertionConfiguration(
                              onContentInserted: _insertFromKeyboard),
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
              if (_dragging) _DropHint(),
            ],
          ),
        ),
      ),
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
    showModalBottomSheet<void>(
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
    showModalBottomSheet<void>(
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
    final scheme = Theme.of(context).colorScheme;
    return LinkedText(
      text: text,
      style: style,
      query: query,
      linkify: linkify,
      highlightStyle: TextStyle(
        backgroundColor: scheme.tertiaryContainer,
        color: scheme.onTertiaryContainer,
        fontWeight: FontWeight.w700,
      ),
      onTapLink: (uri) => confirmAndOpenLink(context, uri),
    );
  }

  /// Treść dymka: tekst albo kafelek pliku (nazwa, rozmiar, pasek postępu
  /// podczas trwającej wysyłki). Kafelek pliku otwiera go po kliknięciu,
  /// przytrzymanie daje menu (otwórz / pokaż folder / kopiuj ścieżkę).
  Widget _content(BuildContext context, bool mine, ColorScheme scheme) {
    final textColor = mine ? scheme.onPrimary : scheme.onSurface;
    if (message.kind != MessageKind.file) {
      // Przytrzymanie łapie cały dymek (patrz `build`), a nie sam napis:
      // inaczej menu otwierałoby się tylko dokładnie na literach.
      final tekst = _highlighted(
          context, message.body, TextStyle(color: textColor, fontSize: 15));
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
    final thumbnail = _thumbnail();
    return InkWell(
      onTap: () => _openFile(context),
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
                  TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w500),
                  linkify: false,
                ),
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
          // Zapisanie odebranego pliku jednym dotknięciem. Przy własnym
          // pliku nie ma czego zapisywać, leży u nas od początku.
          if (message.direction == MessageDirection.incoming) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: context.l10n.saveFile,
              visualDensity: VisualDensity.compact,
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
  Widget? _thumbnail() {
    final path = message.filePath;
    if (path == null || !isImageFile(message.fileName)) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
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
    final mine = message.direction == MessageDirection.outgoing;
    final failed = mine && message.status == MessageStatus.failed;

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
          maxWidth: math.min(MediaQuery.sizeOf(context).width * 0.75, 560)),
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
