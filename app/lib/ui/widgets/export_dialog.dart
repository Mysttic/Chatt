import 'package:flutter/material.dart';

import '../../core/file_actions.dart' show SaveResult;
import '../../l10n/app_localizations.dart';
import '../../services/app_log.dart' show LogArea;
import '../../services/app_services.dart';
import '../../services/data_export.dart';
import '../l10n_context.dart';
import 'common.dart';
import 'toasts.dart';

// Okno „Eksportuj dane" (issue #50): wybór części archiwum z liczbami,
// ostrzeżenie o braku szyfrowania i sam eksport z komunikatem o wyniku.
// Archiwum składa `services/data_export.dart`.

/// Liczenie danych do okna wyboru, jak [estimateExport].
typedef ExportEstimator = Future<ExportEstimate> Function(
    AppServices services);

/// Eksport z zapisem na tej platformie, jak [exportAndSave].
typedef ExportRunner
    = Future<({SaveResult result, String? where, ExportResult? export})>
        Function(AppServices services, ExportParts parts);

/// Pokazuje okno eksportu. [initial] to części zaznaczone na start (z
/// dziennika aplikacji: sam dziennik). [estimate] i [exportData] podmieniają
/// testy.
Future<void> showExportDialog(
  BuildContext context, {
  required AppServices services,
  ExportParts initial = const ExportParts(),
  ExportEstimator estimate = estimateExport,
  ExportRunner exportData = exportAndSave,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => ExportDialog(
        services: services,
        initial: initial,
        estimate: estimate,
        exportData: exportData,
      ),
    );

/// Napis do komunikatu po eksporcie. `null`: bez komunikatu, bo użytkownik
/// sam zamknął okno zapisu.
String? exportResultMessage(AppLocalizations l10n,
        ({SaveResult result, String? where, ExportResult? export}) wynik) =>
    switch (wynik.result) {
      SaveResult.saved => switch (wynik.where) {
          final gdzie? when gdzie.isNotEmpty => l10n.exportDataSaved(gdzie),
          _ => l10n.exportDataDone,
        },
      SaveResult.cancelled => null,
      SaveResult.unsupported => l10n.exportDataUnsupported,
      SaveResult.missing || SaveResult.failed => l10n.exportDataFailed,
    };

/// Okno wyboru części eksportu. Zostaje otwarte na czas eksportu: przyciski
/// gasną, a zamknięcie wstecz i stuknięciem obok nie działa, bo archiwum
/// powstaje w tle i komunikat o wyniku ma do czego się odnieść.
class ExportDialog extends StatefulWidget {
  final AppServices services;
  final ExportParts initial;
  final ExportEstimator estimate;
  final ExportRunner exportData;

  const ExportDialog({
    super.key,
    required this.services,
    this.initial = const ExportParts(),
    this.estimate = estimateExport,
    this.exportData = exportAndSave,
  });

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  late bool _rozmowy = widget.initial.conversations;
  late bool _pisanie = widget.initial.typing;
  late bool _dziennik = widget.initial.appLog;
  late bool _pliki = widget.initial.files;

  ExportEstimate? _szacunek;

  /// Liczenie się nie udało: okno pokazuje wszystkie części bez liczb,
  /// a eksport i tak da się zrobić.
  bool _szacunekPadl = false;
  bool _zajete = false;

  @override
  void initState() {
    super.initState();
    // Future.sync: funkcja może rzucić od razu, zanim zwróci Future.
    Future.sync(() => widget.estimate(widget.services)).then(
      (szacunek) {
        if (mounted) setState(() => _szacunek = szacunek);
      },
      onError: (Object blad, StackTrace slad) {
        widget.services.log.warning(
            LogArea.app, 'Export estimate failed',
            error: blad, stack: slad);
        if (mounted) setState(() => _szacunekPadl = true);
      },
    );
  }

  bool get _policzone => _szacunek != null || _szacunekPadl;

  /// Historia pisania jest do wyboru tylko wtedy, gdy ma jakąś sesję.
  bool get _pisanieDostepne =>
      _szacunekPadl || (_szacunek?.typingSessions ?? 0) > 0;

  bool get _plikiDostepne => _szacunekPadl || (_szacunek?.files ?? 0) > 0;

  ExportParts get _czesci => ExportParts(
        conversations: _rozmowy,
        typing: _pisanie && _pisanieDostepne,
        appLog: _dziennik,
        files: _pliki && _plikiDostepne,
      );

  Future<void> _eksportuj() async {
    final l10n = context.l10n;
    final czesci = _czesci;
    setState(() => _zajete = true);
    final komunikaty = <String>[];
    try {
      final wynik = await widget.exportData(widget.services, czesci);
      final napis = exportResultMessage(l10n, wynik);
      if (napis != null) komunikaty.add(napis);
      final pominiete = wynik.export?.skippedFiles.length ?? 0;
      if (wynik.result == SaveResult.saved && pominiete > 0) {
        komunikaty.add(l10n.exportDataSkipped(pominiete));
      }
    } catch (blad, slad) {
      widget.services.log
          .error(LogArea.app, 'Data export failed', error: blad, stack: slad);
      komunikaty.add(l10n.exportDataFailed);
    }
    if (mounted) Navigator.of(context).pop();
    // Komunikat zostaje na ekranie po zamknięciu okna.
    for (final napis in komunikaty) {
      showToast(napis, duration: const Duration(seconds: 6));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final s = _szacunek;
    final drobny = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);

    CheckboxListTile czesc({
      required bool value,
      required ValueChanged<bool> onChanged,
      required String title,
      String? subtitle,
      bool enabled = true,
    }) =>
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          onChanged: (_zajete || !enabled)
              ? null
              : (wybor) => setState(() => onChanged(wybor ?? false)),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
        );

    return PopScope(
      canPop: !_zajete,
      child: AlertDialog(
        title: Text(l10n.exportData),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_policzone) const LinearProgressIndicator(),
              if (_szacunekPadl)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(l10n.exportDataEstimateFailed, style: drobny),
                ),
              czesc(
                value: _rozmowy,
                onChanged: (v) => _rozmowy = v,
                title: l10n.exportDataConversations,
                subtitle: s == null
                    ? null
                    : [
                        l10n.exportDataCountConversations(s.conversations),
                        l10n.historyCountMessages(s.messages),
                        l10n.exportDataCountDevices(s.peers),
                      ].join(', '),
              ),
              if (_policzone && _pisanieDostepne)
                czesc(
                  value: _pisanie,
                  onChanged: (v) => _pisanie = v,
                  title: l10n.typingHistory,
                  subtitle: s == null
                      ? null
                      : l10n.typingHistorySessions(s.typingSessions),
                ),
              czesc(
                value: _dziennik,
                onChanged: (v) => _dziennik = v,
                title: l10n.appLog,
                subtitle: s == null ? null : l10n.appLogEntries(s.logEntries),
              ),
              czesc(
                value: _pliki && _plikiDostepne,
                onChanged: (v) => _pliki = v,
                enabled: _policzone && _plikiDostepne,
                title: l10n.exportDataFiles,
                subtitle: s == null
                    ? null
                    : s.files == 0
                        ? l10n.historyCountFiles(0)
                        : '${l10n.historyCountFiles(s.files)} '
                            '(${formatFileSize(s.fileBytes)})',
              ),
              const SizedBox(height: 8),
              SecurityNote(
                l10n.exportDataWarning,
                icon: Icons.lock_open_outlined,
                dense: true,
              ),
              if (_zajete) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 6),
                Text(l10n.exportDataBusy, style: drobny),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _zajete ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: (_zajete || !_policzone || _czesci.isEmpty)
                ? null
                : _eksportuj,
            child: Text(l10n.exportDataAction),
          ),
        ],
      ),
    );
  }
}
