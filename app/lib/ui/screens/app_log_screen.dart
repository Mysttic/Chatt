import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../services/data_export.dart' show ExportParts;
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../styles.dart';
import '../widgets/common.dart';
import '../widgets/export_dialog.dart';
import '../widgets/toasts.dart';

// Dziennik aplikacji (issue #50): wpisy od najnowszego, filtr ostrzeżeń
// i błędów, szczegóły po stuknięciu, kopiowanie, czyszczenie i eksport.
// Wpisy zapisuje `services/app_log.dart`; treści wiadomości, wpisywanego
// tekstu i kluczy w nich nie ma.

/// Ile najnowszych wpisów pokazuje ekran. Pełny dziennik idzie eksportem.
const int _limit = 2000;

/// Wpis jako linia tekstu, jak w `app-log.txt` z eksportu:
/// `2026-10-18 15:30:12.345 WARN  net  wiadomość`, szczegóły pod spodem
/// z wcięciem.
String _linia(AppLogEntry wpis) {
  final t = DateTime.fromMillisecondsSinceEpoch(wpis.atMs);
  String dwa(int v) => v.toString().padLeft(2, '0');
  final czas = '${t.year}-${dwa(t.month)}-${dwa(t.day)} '
      '${dwa(t.hour)}:${dwa(t.minute)}:${dwa(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
  final poziom = switch (wpis.level) {
    LogLevel.info => 'INFO',
    LogLevel.warning => 'WARN',
    LogLevel.error => 'ERROR',
  };
  final linia = '$czas ${poziom.padRight(5)} ${wpis.area}  ${wpis.message}';
  final szczegoly = wpis.details;
  if (szczegoly == null || szczegoly.isEmpty) return linia;
  final wciete = szczegoly.split('\n').map((l) => '    $l').join('\n');
  return '$linia\n$wciete';
}

/// Ekran „Dziennik aplikacji". Wejście z Ustawień, z sekcji „Dane
/// i diagnostyka".
class AppLogScreen extends ConsumerStatefulWidget {
  const AppLogScreen({super.key});

  @override
  ConsumerState<AppLogScreen> createState() => _AppLogScreenState();
}

class _AppLogScreenState extends ConsumerState<AppLogScreen> {
  /// Tylko ostrzeżenia i błędy.
  bool _problemy = false;

  late Stream<List<AppLogEntry>> _wpisy = _strumien();

  /// Wpisy ze szczegółami rozwiniętymi stuknięciem, po numerze.
  final Set<int> _rozwiniete = {};

  Stream<List<AppLogEntry>> _strumien() =>
      ref.read(appServicesProvider).db.watchLogEntries(
            limit: _limit,
            minLevel: _problemy ? LogLevel.warning : LogLevel.info,
          );

  void _filtruj(bool problemy) {
    if (problemy == _problemy) return;
    setState(() {
      _problemy = problemy;
      _wpisy = _strumien();
    });
  }

  /// Kopiuje to, co widać, od najstarszego, tak jak leży w pliku eksportu:
  /// do zgłoszenia błędu czyta się dziennik po kolei.
  Future<void> _kopiuj(List<AppLogEntry> wpisy) async {
    final teksty = context.l10n;
    final tekst = wpisy.reversed.map(_linia).join('\n');
    await Clipboard.setData(ClipboardData(text: tekst));
    showToast(teksty.copied);
  }

  Future<void> _wyczysc() async {
    final zgoda = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.appLogClearTitle),
        content: Text(context.l10n.appLogClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (zgoda != true || !mounted) return;

    final teksty = context.l10n;
    final usuniete = await ref.read(appServicesProvider).clearLog();
    if (mounted) setState(_rozwiniete.clear);
    showToast(usuniete == 0
        ? teksty.nothingToCleanUp
        : teksty.appLogCleared(usuniete));
  }

  void _eksportuj() => showExportDialog(
        context,
        services: ref.read(appServicesProvider),
        initial: const ExportParts(
          conversations: false,
          typing: false,
          appLog: true,
          files: false,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return StreamBuilder<List<AppLogEntry>>(
      stream: _wpisy,
      builder: (context, snapshot) {
        final wpisy = snapshot.data;
        final Widget lista;
        if (snapshot.hasError) {
          lista = Center(
              child: Text(l10n.errorWithDetails('${snapshot.error}')));
        } else if (wpisy == null) {
          lista = const Center(child: CircularProgressIndicator());
        } else if (wpisy.isEmpty) {
          lista = _Pusto(problemy: _problemy);
        } else {
          lista = Padding(
            padding: EdgeInsets.fromLTRB(
                12, 0, 12, 12 + bottomSystemInset(context)),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListView.separated(
                itemCount: wpisy.length + (wpisy.length >= _limit ? 1 : 0),
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == wpisy.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.appLogLimit(_limit),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12),
                      ),
                    );
                  }
                  final wpis = wpisy[index];
                  return _Wpis(
                    entry: wpis,
                    expanded: _rozwiniete.contains(wpis.id),
                    onToggle: () => setState(() {
                      if (!_rozwiniete.remove(wpis.id)) {
                        _rozwiniete.add(wpis.id);
                      }
                    }),
                  );
                },
              ),
            ),
          );
        }

        final widoczne = wpisy ?? const <AppLogEntry>[];
        final sa = widoczne.isNotEmpty;
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.appLog),
            actions: [
              IconButton(
                tooltip: l10n.appLogCopy,
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: sa ? () => _kopiuj(widoczne) : null,
              ),
              IconButton(
                tooltip: l10n.appLogExport,
                icon: const Icon(Icons.archive_outlined),
                onPressed: _eksportuj,
              ),
              IconButton(
                tooltip: l10n.appLogClear,
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: sa || _problemy ? _wyczysc : null,
              ),
            ],
          ),
          body: ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(l10n.appLogFilterAll),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.warning_amber_outlined),
                        label: Text(l10n.appLogFilterProblems),
                      ),
                    ],
                    selected: {_problemy},
                    onSelectionChanged: (wybor) => _filtruj(wybor.first),
                  ),
                ),
                Expanded(child: lista),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Jeden wpis: ikona i kolor wagi z motywu, data z sekundami, obszar
/// i wiadomość. Stuknięcie rozwija szczegóły błędu, gdy są.
class _Wpis extends StatelessWidget {
  final AppLogEntry entry;
  final bool expanded;
  final VoidCallback onToggle;

  const _Wpis({
    required this.entry,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final k = ChattTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (ikona, kolor, waga) = switch (entry.level) {
      LogLevel.info => (
          Icons.info_outline,
          scheme.onSurfaceVariant,
          l10n.appLogLevelInfo,
        ),
      LogLevel.warning => (
          Icons.warning_amber_outlined,
          k.warning,
          l10n.appLogLevelWarning,
        ),
      LogLevel.error => (Icons.error_outline, k.danger, l10n.appLogLevelError),
    };
    final szczegoly = entry.details;
    final maSzczegoly = szczegoly != null && szczegoly.isNotEmpty;
    final czas = DateTime.fromMillisecondsSinceEpoch(entry.atMs);

    return InkWell(
      onTap: maSzczegoly ? onToggle : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Tooltip(
                message: waga,
                child: Icon(ikona, size: 20, color: kolor),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatDateTime(czas, seconds: true)} · ${entry.area}',
                    style: k.caption.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: entry.level == LogLevel.info ? null : kolor),
                  ),
                  if (maSzczegoly && expanded) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      szczegoly,
                      style: k.mono.copyWith(
                          color: scheme.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            if (maSzczegoly)
              Tooltip(
                message: l10n.appLogDetails,
                child: Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pusto extends StatelessWidget {
  final bool problemy;

  const _Pusto({required this.problemy});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 72, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              problemy
                  ? context.l10n.appLogEmptyProblems
                  : context.l10n.appLogEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
