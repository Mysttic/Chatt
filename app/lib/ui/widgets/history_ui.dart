import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../services/app_services.dart';
import '../l10n_context.dart';
import '../styles.dart';
import 'common.dart';
import 'motion.dart';
import 'toasts.dart';

// Udostępnianie historii rozmowy (issue #36): okno wyboru, karty zgody
// i paski postępu. Logika żyje w `services/history.dart`.

/// Napis dla wyniku udostępniania.
String historyShareMessage(
        AppLocalizations l10n, HistoryShareResult wynik, String name) =>
    switch (wynik) {
      HistoryShareResult.done => l10n.historyShareDone,
      HistoryShareResult.needsVerified => l10n.historyNeedsVerified,
      HistoryShareResult.nothingToShare => l10n.historyNothing,
      HistoryShareResult.rejected => l10n.historyShareRejected(name),
      HistoryShareResult.noAnswer => l10n.historyNoAnswer,
      HistoryShareResult.busy => l10n.historyBusy,
      HistoryShareResult.olderVersion => l10n.historyOlderVersion,
      HistoryShareResult.unreachable => l10n.historyUnreachable,
      HistoryShareResult.cancelled => l10n.historyCancelled,
      HistoryShareResult.failed => l10n.historyFailed,
    };

/// Napis dla wyniku prośby o historię.
String historyRequestMessage(
        AppLocalizations l10n, HistoryRequestResult wynik, String name) =>
    switch (wynik) {
      HistoryRequestResult.accepted => l10n.historyRequestAccepted(name),
      HistoryRequestResult.empty => l10n.historyRequestEmpty(name),
      HistoryRequestResult.rejected => l10n.historyRequestRejected(name),
      HistoryRequestResult.noAnswer => l10n.historyNoAnswer,
      HistoryRequestResult.busy => l10n.historyBusy,
      HistoryRequestResult.olderVersion => l10n.historyOlderVersion,
      HistoryRequestResult.unreachable => l10n.historyUnreachable,
    };

/// Liczby z zapowiedzi w jednej linii: wiadomości, pliki z rozmiarem, zakres.
String historySummaryLine(AppLocalizations l10n, HistorySummaryView s) {
  final pliki = s.files == 0
      ? l10n.historyCountFiles(0)
      : '${l10n.historyCountFiles(s.files)} (${formatFileSize(s.bytes)})';
  final czesci = [l10n.historyCountMessages(s.messages), pliki];
  final first = s.first;
  final last = s.last;
  if (first != null && last != null) {
    czesci.add(l10n.historyRange(first, last));
  }
  return czesci.join(', ');
}

/// Liczby do pokazania, wspólne dla podglądu i zapowiedzi.
class HistorySummaryView {
  final int messages;
  final int files;
  final int bytes;
  final DateTime? first;
  final DateTime? last;

  const HistorySummaryView({
    required this.messages,
    required this.files,
    required this.bytes,
    this.first,
    this.last,
  });
}

/// Okno „Udostępnij historię": zakres (całość albo od daty), pliki albo bez,
/// i liczby, zanim cokolwiek pójdzie. Udostępnianie biegnie po zamknięciu
/// okna, a jego postęp pokazuje [HistoryProgressBar]. Okno wjeżdża jak karta
/// zgody, na zasłonie stylu.
Future<void> showShareHistoryDialog(
  BuildContext context, {
  required AppServices services,
  required Peer peer,
  required int conversationId,
}) async {
  final wybor = await showChattDialog<_Wybor>(
    context: context,
    builder: (_) => _ShareHistoryDialog(
      services: services,
      peer: peer,
      conversationId: conversationId,
    ),
  );
  if (wybor == null || !context.mounted) return;
  final l10n = context.l10n;
  final wynik = await services.shareHistory(conversationId,
      since: wybor.since,
      withFiles: wybor.withFiles,
      sourceConversationId: wybor.source);
  showToast(historyShareMessage(l10n, wynik, peer.displayName));
  final zrodlo = wybor.source;
  if (wynik == HistoryShareResult.done && wybor.merge && zrodlo != null) {
    await services.mergeConversations(from: zrodlo, into: conversationId);
    showToast(l10n.historyMerged);
  }
}

/// Wybór z okna udostępniania. [source] to starsza rozmowa z innym wpisem,
/// null znaczy „ta rozmowa".
typedef _Wybor = ({DateTime? since, bool withFiles, int? source, bool merge});

/// Prośba o historię do rozmówcy z tej rozmowy.
Future<void> requestHistoryFrom(
  BuildContext context, {
  required AppServices services,
  required Peer peer,
  required int conversationId,
}) async {
  final l10n = context.l10n;
  showToast(l10n.historyRequestSent);
  final wynik = await services.requestHistory(conversationId);
  showToast(historyRequestMessage(l10n, wynik, peer.displayName));
}

class _ShareHistoryDialog extends StatefulWidget {
  final AppServices services;
  final Peer peer;
  final int conversationId;

  const _ShareHistoryDialog({
    required this.services,
    required this.peer,
    required this.conversationId,
  });

  @override
  State<_ShareHistoryDialog> createState() => _ShareHistoryDialogState();
}

class _ShareHistoryDialogState extends State<_ShareHistoryDialog> {
  DateTime? _since;
  bool _withFiles = true;
  HistoryPreview? _preview;

  /// Starsze rozmowy z innymi wpisami: to samo urządzenie po reinstalacji
  /// przychodzi pod nowym. Wybór tylko przy zielonej tarczy.
  List<({int conversationId, Peer peer, int messages})> _inne = const [];
  int? _zrodlo;
  bool _polacz = true;

  @override
  void initState() {
    super.initState();
    _przelicz();
    widget.services.otherConversations(widget.conversationId).then((inne) {
      if (mounted) setState(() => _inne = inne);
    });
  }

  Future<void> _przelicz() async {
    final podglad = await widget.services.previewHistory(
        widget.conversationId,
        since: _since,
        withFiles: _withFiles,
        sourceConversationId: _zrodlo);
    if (mounted) setState(() => _preview = podglad);
  }

  Widget _zrodla(BuildContext context) {
    final l10n = context.l10n;
    final drobny = TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12);
    if (!widget.peer.verified) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(l10n.historySourceNeedsShield, style: drobny),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int?>(
          initialValue: _zrodlo,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.historySource),
          items: [
            DropdownMenuItem<int?>(
                value: null, child: Text(l10n.historySourceThis)),
            for (final inna in _inne)
              DropdownMenuItem<int?>(
                value: inna.conversationId,
                child: Text(
                  l10n.historySourceOther(
                      inna.peer.displayName, inna.messages),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            setState(() => _zrodlo = value);
            _przelicz();
          },
        ),
        const SizedBox(height: 4),
        Text(l10n.historySourceHint, style: drobny),
        if (_zrodlo != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _polacz,
            onChanged: (value) => setState(() => _polacz = value ?? false),
            title: Text(l10n.historyMergeLocally),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _wybierzDate() async {
    final teraz = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: _since ?? teraz.subtract(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: teraz,
    );
    if (data == null || !mounted) return;
    setState(() => _since = data);
    await _przelicz();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final podglad = _preview;
    final pusto = podglad != null && podglad.messages == 0;
    return AlertDialog(
      title: Text(l10n.historyShareTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.historyShareBody(widget.peer.displayName)),
            const SizedBox(height: 12),
            if (_inne.isNotEmpty) _zrodla(context),
            RadioGroup<bool>(
              groupValue: _since == null,
              onChanged: (calosc) {
                if (calosc == true) {
                  setState(() => _since = null);
                  _przelicz();
                } else {
                  _wybierzDate();
                }
              },
              child: Column(
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    title: Text(l10n.historyRangeAll),
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: Text(_since == null
                        ? l10n.historyPickDate
                        : l10n.historyRangeSince(_since!)),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _withFiles,
              title: Text(l10n.historyWithFiles),
              onChanged: (value) {
                setState(() => _withFiles = value);
                _przelicz();
              },
            ),
            const SizedBox(height: 8),
            if (podglad == null)
              const LinearProgressIndicator()
            else if (pusto)
              Text(l10n.historyNothing,
                  style: TextStyle(color: scheme.onSurfaceVariant))
            else ...[
              Text(
                historySummaryLine(
                  l10n,
                  HistorySummaryView(
                    messages: podglad.messages,
                    files: podglad.files,
                    bytes: podglad.bytes,
                    first: podglad.first,
                    last: podglad.last,
                  ),
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (podglad.missingFiles > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.historyMissingFiles(podglad.missingFiles),
                    style:
                        TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: podglad == null || pusto
              ? null
              : () => Navigator.pop<_Wybor>(context, (
                    since: _since,
                    withFiles: _withFiles,
                    source: _zrodlo,
                    merge: _zrodlo != null && _polacz,
                  )),
          child: Text(l10n.historyShareAction),
        ),
      ],
    );
  }
}

/// Karta zgody nad aplikacją: rozmówca chce oddać nam historię albo prosi
/// o naszą. Fokus na Odrzuć, jak przy innych kartach.
class HistoryCard extends StatefulWidget {
  final PendingHistory ask;
  final AppServices services;

  const HistoryCard({super.key, required this.ask, required this.services});

  @override
  State<HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<HistoryCard> {
  final _rejectFocus = FocusNode(debugLabel: 'odrzuć historię');

  @override
  void initState() {
    super.initState();
    // `autofocus` nie sięga poddrzewa z `MaterialApp.builder`, więc fokus
    // bierzemy ręcznie, jak pozostałe karty.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rejectFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _rejectFocus.dispose();
    super.dispose();
  }

  void _odpowiedz(HistoryDecision decyzja) =>
      widget.services.respondToHistory(widget.ask.id, decyzja);

  @override
  Widget build(BuildContext context) {
    final ask = widget.ask;
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final zapowiedz = ask.kind == PendingHistoryKind.offer;
    final summary = ask.summary;
    final drobny = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
    return Card(
      elevation: 6,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    zapowiedz
                        ? l10n.historyOfferTitle(ask.peerName)
                        : l10n.historyRequestTitle(ask.peerName),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (ask.fromVerifiedPeer)
                  Icon(Icons.verified_user,
                      color: ChattTokens.of(context).verified, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            if (summary != null)
              Text(historySummaryLine(
                l10n,
                HistorySummaryView(
                  messages: summary.count,
                  files: summary.files,
                  bytes: summary.bytes,
                  first: summary.first.toLocal(),
                  last: summary.last.toLocal(),
                ),
              )),
            const SizedBox(height: 6),
            if (zapowiedz) ...[
              Text(l10n.historyOfferMarked, style: drobny),
              Text(l10n.historyOfferDeleted, style: drobny),
              if (ask.retentionDays > 0)
                Text(l10n.historyOfferRetention(ask.retentionDays),
                    style: drobny),
            ] else
              Text(l10n.historyRequestBody, style: drobny),
            if (!ask.fromVerifiedPeer)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SecurityNote(l10n.historyOfferUnverified, dense: true),
              ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  focusNode: _rejectFocus,
                  onPressed: () => _odpowiedz(HistoryDecision.reject),
                  child: Text(l10n.reject),
                ),
                if (!zapowiedz && (summary?.files ?? 0) > 0)
                  OutlinedButton(
                    onPressed: () =>
                        _odpowiedz(HistoryDecision.acceptWithoutFiles),
                    child: Text(l10n.historyWithoutFiles),
                  ),
                FilledButton(
                  onPressed: () => _odpowiedz(HistoryDecision.accept),
                  child: Text(zapowiedz ? l10n.accept : l10n.historyShareAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Paski postępu historii tej rozmowy, nad polem pisania: własne
/// udostępnianie (z Przerwij) i przywracanie od rozmówcy (z Zamknij po
/// zakończeniu).
class HistoryProgressBar extends StatelessWidget {
  final AppServices services;
  final int conversationId;

  const HistoryProgressBar({
    super.key,
    required this.services,
    required this.conversationId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<HistoryTransfer?>(
          valueListenable: services.outgoingHistory,
          builder: (context, postep, _) =>
              postep == null || postep.conversationId != conversationId
                  ? const SizedBox.shrink()
                  : _Pasek(
                      transfer: postep,
                      title: context.l10n.historySharing(postep.peerName),
                      action: TextButton(
                        onPressed: services.cancelHistoryShare,
                        child: Text(context.l10n.historyStop),
                      ),
                    ),
        ),
        ValueListenableBuilder<HistoryTransfer?>(
          valueListenable: services.incomingHistory,
          builder: (context, postep, _) =>
              postep == null || postep.conversationId != conversationId
                  ? const SizedBox.shrink()
                  : _Pasek(
                      transfer: postep,
                      title: postep.finished
                          ? context.l10n.historyRestored(postep.peerName)
                          : context.l10n.historyRestoring(postep.peerName),
                      // Przerwać może także odbierający: przy własnej
                      // prośbie karty nie było, więc to jedyne miejsce,
                      // gdzie da się powiedzieć „dość".
                      action: postep.finished
                          ? TextButton(
                              onPressed: services.dismissIncomingHistory,
                              child: Text(context.l10n.close),
                            )
                          : TextButton(
                              onPressed: services.stopIncomingHistory,
                              child: Text(context.l10n.historyStop),
                            ),
                    ),
        ),
      ],
    );
  }
}

class _Pasek extends StatefulWidget {
  final HistoryTransfer transfer;
  final String title;
  final Widget? action;

  const _Pasek({required this.transfer, required this.title, this.action});

  @override
  State<_Pasek> createState() => _PasekState();
}

class _PasekState extends State<_Pasek> {
  /// Które to przesłanie w tym miejscu. Postęp jednego przesłania stoi albo
  /// rośnie, przy stałych liczbach, więc spadek albo inne liczby znaczą
  /// następne przesłanie (nowe przywracanie w miejsce skończonego). Jego
  /// pasek startuje od własnej pierwszej próbki.
  int _przeslanie = 0;

  static double _wartosc(HistoryTransfer t) {
    final razem = t.messagesTotal + t.filesTotal;
    final zrobione = t.messagesDone + t.filesDone;
    return t.finished || razem == 0
        ? 1.0
        : (zrobione / razem).clamp(0.0, 1.0).toDouble();
  }

  @override
  void didUpdateWidget(_Pasek old) {
    super.didUpdateWidget(old);
    final bylo = old.transfer;
    final jest = widget.transfer;
    if (jest.messagesTotal != bylo.messagesTotal ||
        jest.filesTotal != bylo.filesTotal ||
        _wartosc(jest) < _wartosc(bylo)) {
      _przeslanie++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final transfer = widget.transfer;
    final title = widget.title;
    final action = widget.action;
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styl = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final wartosc = _wartosc(transfer);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: styl),
              ),
              ?action,
            ],
          ),
          Wrap(
            spacing: 12,
            children: [
              Text(
                  l10n.historyProgressMessages(
                      transfer.messagesDone, transfer.messagesTotal),
                  style: styl),
              if (transfer.filesTotal > 0)
                Text(
                    l10n.historyProgressFiles(
                        transfer.filesDone, transfer.filesTotal),
                    style: styl),
              if (transfer.finished && transfer.skipped > 0)
                Text(l10n.historySkipped(transfer.skipped), style: styl),
            ],
          ),
          const SizedBox(height: 4),
          // Między próbkami pasek przechodzi w ruchu stylu.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SmoothProgress(
              key: ValueKey(_przeslanie),
              value: wartosc,
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}
