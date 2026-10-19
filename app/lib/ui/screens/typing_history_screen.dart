import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../network/protocol.dart' show RemoteInputField, RemoteInputOpKind;
import '../../services/providers.dart';
import '../../services/typing_journal.dart';
import '../l10n_context.dart';
import '../styles.dart';
import '../widgets/common.dart';
import '../widgets/toasts.dart';

// Historia pisania zdalną klawiaturą (issue #50): lista sesji od najnowszej
// i podgląd jednej sesji z odtworzonym tekstem i przebiegiem. Wiersze
// zapisuje `services/typing_journal.dart`; tekst z pól haseł i pól
// nieznanego rodzaju nigdy do bazy nie trafia, więc ten ekran nie ma czego
// zasłaniać: pokazuje kropki i liczbę znaków.

/// Jak skończyła się prośba o sesję, słowami (patrz [TypingResult]).
/// Napis spoza listy (zapisany przez nowszy Chatt) idzie dosłownie.
String typingResultLabel(AppLocalizations l10n, String result) =>
    switch (result) {
      TypingResult.accepted => l10n.typingResultAccepted,
      TypingResult.acceptedAlways => l10n.typingResultAcceptedAlways,
      TypingResult.automatic => l10n.typingResultAutomatic,
      TypingResult.rejected => l10n.typingResultRejected,
      TypingResult.noAnswer => l10n.typingResultNoAnswer,
      TypingResult.busy => l10n.typingResultBusy,
      TypingResult.notEnabled => l10n.typingResultNotEnabled,
      TypingResult.cancelled => l10n.typingResultCancelled,
      TypingResult.unreachable => l10n.typingResultUnreachable,
      TypingResult.olderPeer => l10n.typingResultOlderPeer,
      _ => result,
    };

/// Dlaczego sesja się skończyła, słowami (patrz [TypingEnd]). `null` to
/// sesja bez zapisanego końca: trwa albo aplikacja zniknęła bez sygnału.
String typingEndLabel(AppLocalizations l10n, String? reason) =>
    switch (reason) {
      null => l10n.typingHistoryNotEnded,
      TypingEnd.stoppedHere => l10n.typingEndStoppedHere,
      TypingEnd.stoppedByPeer => l10n.typingEndStoppedByPeer,
      TypingEnd.expired => l10n.typingEndExpired,
      TypingEnd.receiveOff => l10n.typingEndReceiveOff,
      TypingEnd.addonOff => l10n.typingEndAddonOff,
      TypingEnd.replaced => l10n.typingEndReplaced,
      TypingEnd.peerRemoved => l10n.typingEndPeerRemoved,
      TypingEnd.notAllowed => l10n.typingEndNotAllowed,
      TypingEnd.linkLost => l10n.typingEndLinkLost,
      TypingEnd.appClosed => l10n.typingEndAppClosed,
      final inny => inny,
    };

/// Co stało się z kawałkiem pisania, słowami.
String typingStatusLabel(AppLocalizations l10n, TypingStatus status) =>
    switch (status) {
      TypingStatus.typed => l10n.typingStatusTyped,
      TypingStatus.notTyped => l10n.typingStatusNotTyped,
      TypingStatus.paused => l10n.typingStatusPaused,
      TypingStatus.refused => l10n.typingStatusRefused,
      TypingStatus.unconfirmed => l10n.typingStatusUnconfirmed,
      TypingStatus.unsent => l10n.typingStatusUnsent,
    };

/// Kto na kim pisał: „Pisanie stąd na: Alicja" albo „Pisanie tutaj z:
/// Alicja". Formy bezosobowe, bo rozmówca nie ma w Chatcie rodzaju.
String typingDirectionLabel(AppLocalizations l10n, TypingSession session) =>
    session.direction == MessageDirection.outgoing
        ? l10n.typingHistoryOutgoing(session.peerName)
        : l10n.typingHistoryIncoming(session.peerName);

/// Tekst sesji odtworzony z kawałków, które dotarły do pola (wpisane
/// i wpisane częściowo). Tak samo liczy go eksport historii pisania.
String typingTranscript(Iterable<TypingEntry> entries) => reconstructTyping([
      for (final kawalek in entries)
        if (kawalek.status == TypingStatus.typed.name ||
            kawalek.status == TypingStatus.notTyped.name)
          ...TypingOp.decode(kawalek.ops),
    ]);

/// Ikona kierunku sesji, wspólna dla listy i podglądu. Prośba bez sesji
/// ma własny znak w kolorze zagrożenia.
({IconData icon, Color color}) _znakSesji(
    BuildContext context, TypingSession session) {
  final scheme = Theme.of(context).colorScheme;
  if (!TypingResult.started(session.result)) {
    return (icon: Icons.block, color: ChattTokens.of(context).danger);
  }
  return session.direction == MessageDirection.outgoing
      ? (icon: Icons.call_made, color: scheme.primary)
      : (icon: Icons.call_received, color: scheme.primary);
}

/// Lista sesji pisania, od najnowszej. Wejście z karty dodatku „Klawiatura
/// z PC" w Ustawieniach.
class TypingHistoryScreen extends ConsumerStatefulWidget {
  const TypingHistoryScreen({super.key});

  @override
  ConsumerState<TypingHistoryScreen> createState() =>
      _TypingHistoryScreenState();
}

class _TypingHistoryScreenState extends ConsumerState<TypingHistoryScreen> {
  /// Jeden strumień na życie ekranu: przebudowa nie zakłada nowego
  /// zapytania w bazie.
  late final Stream<List<TypingSessionSummary>> _sesje =
      ref.read(appServicesProvider).db.watchTypingSessionSummaries();

  /// Wyczyszczenie jest nieodwracalne, więc pytamy wprost.
  Future<void> _wyczysc() async {
    final zgoda = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.typingHistoryClearTitle),
        content: Text(context.l10n.typingHistoryClearBody),
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
    final usuniete =
        await ref.read(appServicesProvider).clearTypingHistory();
    showToast(usuniete == 0
        ? teksty.nothingToCleanUp
        : teksty.typingHistoryCleared(usuniete));
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.read(appServicesProvider);
    final l10n = context.l10n;

    return StreamBuilder<List<TypingSessionSummary>>(
      stream: _sesje,
      builder: (context, snapshot) {
        final sesje = snapshot.data;
        final Widget tresc;
        if (snapshot.hasError) {
          tresc = Center(
              child: Text(l10n.errorWithDetails('${snapshot.error}')));
        } else if (sesje == null) {
          tresc = const Center(child: CircularProgressIndicator());
        } else {
          tresc = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Zapis wyłączony: lista pokazuje to, co już jest, a nowe
              // sesje tu nie trafią. Lepiej powiedzieć to tutaj, zanim ktoś
              // zacznie szukać brakującej sesji.
              ListenableBuilder(
                listenable: Listenable.merge(
                    [services.keyboardAddon, services.typingHistory]),
                builder: (context, _) => services.keyboardAddon.value &&
                        services.typingHistory.value
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _Uwaga(
                            icon: Icons.info_outline,
                            text: l10n.typingHistoryOff),
                      ),
              ),
              Expanded(
                child: sesje.isEmpty
                    ? const _Pusto()
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                            12, 12, 12, 12 + bottomSystemInset(context)),
                        itemCount: sesje.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _WierszSesji(summary: sesje[index]),
                      ),
              ),
            ],
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.typingHistory),
            actions: [
              IconButton(
                tooltip: l10n.typingHistoryClear,
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: (sesje == null || sesje.isEmpty) ? null : _wyczysc,
              ),
            ],
          ),
          body: ContentColumn(child: tresc),
        );
      },
    );
  }
}

/// Jedna sesja na liście: kierunek z rozmówcą, początek, czas trwania,
/// liczba znaków, aplikacje i wynik słowami. Prośba bez sesji (odmowa,
/// cisza na karcie) ma własną ikonę i wynik w kolorze zagrożenia.
class _WierszSesji extends StatelessWidget {
  final TypingSessionSummary summary;

  const _WierszSesji({required this.summary});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final k = ChattTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final sesja = summary.session;
    final zaczeta = TypingResult.started(sesja.result);
    final znak = _znakSesji(context, sesja);
    final koniec = sesja.endedAt;

    final fakty = [
      formatDateTime(sesja.startedAt),
      if (zaczeta && koniec != null)
        formatDuration(koniec.difference(sesja.startedAt)),
      if (zaczeta) l10n.typingHistoryChars(summary.chars),
    ].join(' · ');
    final wynik = zaczeta
        ? '${typingResultLabel(l10n, sesja.result)} · '
            '${typingEndLabel(l10n, sesja.endReason)}'
        : typingResultLabel(l10n, sesja.result);
    final drobny = k.caption.copyWith(color: scheme.onSurfaceVariant);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: k.rowPadding,
        leading: Icon(znak.icon, color: znak.color),
        title: Text(
          typingDirectionLabel(l10n, sesja),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 2),
            Text(fakty, style: drobny),
            if (summary.apps.isNotEmpty)
              Text(
                summary.apps.join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: drobny,
              ),
            Text(
              wynik,
              style: zaczeta ? null : TextStyle(color: k.danger),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TypingSessionScreen(sessionId: sesja.id),
          ),
        ),
      ),
    );
  }
}

/// Podgląd jednej sesji: fakty z nagłówka, tekst odtworzony z klawiszy
/// i przebieg kawałek po kawałku. Trwająca sesja dopisuje się na żywo.
class TypingSessionScreen extends ConsumerStatefulWidget {
  final int sessionId;

  const TypingSessionScreen({super.key, required this.sessionId});

  @override
  ConsumerState<TypingSessionScreen> createState() =>
      _TypingSessionScreenState();
}

class _TypingSessionScreenState extends ConsumerState<TypingSessionScreen> {
  late final ChattDb _db = ref.read(appServicesProvider).db;

  late final Stream<TypingSession?> _sesja = (_db.select(_db.typingSessions)
        ..where((s) => s.id.equals(widget.sessionId)))
      .watchSingleOrNull();

  late final Stream<List<TypingEntry>> _kawalki =
      _db.watchTypingEntries(widget.sessionId);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.typingHistory)),
      body: ContentColumn(
        child: StreamBuilder<TypingSession?>(
          stream: _sesja,
          builder: (context, sesjaSnapshot) {
            if (sesjaSnapshot.connectionState == ConnectionState.waiting &&
                !sesjaSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final sesja = sesjaSnapshot.data;
            // Wiersza już nie ma: historię wyczyszczono albo przycięło ją
            // przechowywanie, gdy ekran był otwarty.
            if (sesja == null) return const _Pusto();
            return StreamBuilder<List<TypingEntry>>(
              stream: _kawalki,
              builder: (context, snapshot) =>
                  _tresc(context, sesja, snapshot.data),
            );
          },
        ),
      ),
    );
  }

  Widget _tresc(
      BuildContext context, TypingSession sesja, List<TypingEntry>? kawalki) {
    final l10n = context.l10n;
    final k = ChattTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final zaczeta = TypingResult.started(sesja.result);
    final wszystkie = kawalki ?? const <TypingEntry>[];
    final tekst = typingTranscript(wszystkie);

    final naglowek = <Widget>[
      _Naglowek(session: sesja, entries: kawalki),
      if (zaczeta) ...[
        _Tytul(
          l10n.typingHistoryText,
          action: kawalki == null ? null : _KopiujTekst(text: tekst),
        ),
        if (kawalki == null)
          const LinearProgressIndicator()
        else
          _OdtworzonyTekst(text: tekst),
        const SizedBox(height: 6),
        Text(
          l10n.typingHistoryTextNote,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        _Tytul(l10n.typingHistoryTimeline),
        if (kawalki != null && kawalki.isEmpty)
          Text(l10n.typingHistoryNoEntries,
              style: TextStyle(color: scheme.onSurfaceVariant)),
      ],
    ];

    // Kawałków bywa kilkaset: lista buduje je leniwie, nagłówek idzie
    // pierwszymi pozycjami tej samej listy.
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomSystemInset(context)),
      itemCount: naglowek.length + (zaczeta ? wszystkie.length : 0),
      itemBuilder: (context, index) {
        if (index < naglowek.length) return naglowek[index];
        final kawalek = wszystkie[index - naglowek.length];
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: k.outline)),
          ),
          child: _Kawalek(entry: kawalek),
        );
      },
    );
  }
}

/// Fakty o sesji w karcie: kierunek, początek, koniec, czas trwania, znaki,
/// aplikacje, wynik prośby, powód końca i identyfikator do zestawienia
/// z historią drugiej strony. Znaki i aplikacje liczy z kawałków, więc
/// pojawiają się, gdy [entries] już przyszły z bazy.
class _Naglowek extends StatelessWidget {
  final TypingSession session;
  final List<TypingEntry>? entries;

  const _Naglowek({required this.session, required this.entries});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final k = ChattTokens.of(context);
    final zaczeta = TypingResult.started(session.result);
    final znak = _znakSesji(context, session);
    final koniec = session.endedAt;
    final kawalki = entries;
    final aplikacje = <String>{
      for (final e in kawalki ?? const <TypingEntry>[])
        if (e.appLabel.isNotEmpty)
          e.appLabel
        else if (e.app.isNotEmpty)
          e.app,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(znak.icon, color: znak.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    typingDirectionLabel(l10n, session),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Fakt(
              label: l10n.typingHistoryStarted,
              value: formatDateTime(session.startedAt, seconds: true),
            ),
            if (zaczeta) ...[
              _Fakt(
                label: l10n.typingHistoryEnded,
                value: koniec == null
                    ? l10n.typingHistoryNotEnded
                    : formatDateTime(koniec, seconds: true),
              ),
              if (koniec != null)
                _Fakt(
                  label: l10n.typingHistoryDuration,
                  value: formatDuration(koniec.difference(session.startedAt)),
                ),
              if (kawalki != null)
                _Fakt(
                  label: l10n.typingHistoryCharsLabel,
                  value: l10n.typingHistoryChars(
                      kawalki.fold(0, (suma, e) => suma + e.chars)),
                ),
              if (aplikacje.isNotEmpty)
                _Fakt(
                  label: l10n.typingHistoryApps,
                  value: aplikacje.join(', '),
                ),
            ],
            _Fakt(
              label: l10n.typingHistoryRequest,
              value: typingResultLabel(l10n, session.result),
              color: zaczeta ? null : k.danger,
            ),
            if (zaczeta)
              _Fakt(
                label: l10n.typingHistoryEndReason,
                value: typingEndLabel(l10n, session.endReason),
              ),
            _Fakt(
              label: l10n.typingHistorySessionId,
              value: session.inputId,
              mono: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// Podpis i wartość w nagłówku sesji.
class _Fakt extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  /// Wartość techniczna: font o stałej szerokości i zaznaczanie.
  final bool mono;

  const _Fakt({
    required this.label,
    required this.value,
    this.color,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final k = ChattTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: mono
                ? SelectableText(value,
                    style: k.mono.copyWith(color: color ?? scheme.onSurface))
                : Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

/// Nagłówek części podglądu w stylu sekcji Ustawień, z opcjonalnym
/// przyciskiem po prawej.
class _Tytul extends StatelessWidget {
  final String title;
  final Widget? action;

  const _Tytul(this.title, {this.action});

  @override
  Widget build(BuildContext context) {
    final k = ChattTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k.overlineText(title),
              style: k.overline.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Odtworzony tekst sesji: font o stałej szerokości, do zaznaczania.
class _OdtworzonyTekst extends StatelessWidget {
  final String text;

  const _OdtworzonyTekst({required this.text});

  @override
  Widget build(BuildContext context) {
    final k = ChattTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: text.isEmpty
              ? Text(context.l10n.typingHistoryNoText,
                  style: TextStyle(color: scheme.onSurfaceVariant))
              : SelectableText(text,
                  style: k.mono.copyWith(color: scheme.onSurface)),
        ),
      ),
    );
  }
}

class _KopiujTekst extends StatelessWidget {
  final String text;

  const _KopiujTekst({required this.text});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: context.l10n.copyText,
        icon: const Icon(Icons.copy_outlined, size: 20),
        onPressed: text.isEmpty
            ? null
            : () async {
                final teksty = context.l10n;
                await Clipboard.setData(ClipboardData(text: text));
                showToast(teksty.copied);
              },
      );
}

/// Jeden kawałek pisania: godzina z sekundami, aplikacja, rodzaj pola przy
/// ukrytym tekście, skutek słowami i operacje w jednym ciągu.
class _Kawalek extends StatelessWidget {
  final TypingEntry entry;

  const _Kawalek({required this.entry});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final k = ChattTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final status = TypingStatus.parse(entry.status);
    final kolorStatusu = switch (status) {
      TypingStatus.typed => scheme.onSurfaceVariant,
      TypingStatus.refused => k.danger,
      _ => k.warning,
    };
    final aplikacja = entry.appLabel.isNotEmpty ? entry.appLabel : entry.app;
    final drobny = k.caption.copyWith(color: scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(formatClockSeconds(entry.at),
                  style: k.mono.copyWith(color: scheme.onSurfaceVariant)),
              if (aplikacja.isNotEmpty)
                Text(aplikacja,
                    style: Theme.of(context).textTheme.labelMedium),
              if (entry.masked)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_off_outlined,
                        size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      entry.field == RemoteInputField.password.name
                          ? l10n.typingFieldPassword
                          : l10n.typingFieldUnknown,
                      style: drobny,
                    ),
                  ],
                ),
              Text(typingStatusLabel(l10n, status),
                  style: drobny.copyWith(color: kolorStatusu)),
            ],
          ),
          const SizedBox(height: 6),
          _Operacje(ops: TypingOp.decode(entry.ops)),
        ],
      ),
    );
  }
}

/// Operacje w jednym ciągu: tekst jako tekst, ukryty tekst jako kropki
/// z liczbą znaków, klawisze jako małe znaczki z ikoną i krotnością. Ikony
/// z fontu Materiala: strzałek i symboli klawiszy fonty stylów nie mają.
class _Operacje extends StatelessWidget {
  final List<TypingOp> ops;

  const _Operacje({required this.ops});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final k = ChattTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final op in ops)
          switch (op.kind) {
            RemoteInputOpKind.insert when op.hidden => _Znaczek(
                tooltip: l10n.typingHistoryHidden,
                label: '${'•' * math.min(op.count, 8)} ${op.count}',
              ),
            RemoteInputOpKind.insert => Text(op.text,
                style: k.mono.copyWith(color: scheme.onSurface)),
            RemoteInputOpKind.backspace => _Znaczek(
                tooltip: l10n.typingKeyBackspace,
                icon: Icons.backspace_outlined,
                count: op.count,
              ),
            // Delete kasuje za kursorem: lustrzane odbicie Backspace.
            RemoteInputOpKind.delete => _Znaczek(
                tooltip: l10n.typingKeyDelete,
                icon: Icons.backspace_outlined,
                mirrored: true,
                count: op.count,
              ),
            RemoteInputOpKind.action => _Znaczek(
                tooltip: l10n.typingKeyEnter,
                icon: Icons.keyboard_return,
              ),
            _ => const SizedBox.shrink(),
          },
      ],
    );
  }
}

/// Mały znaczek w ciągu operacji: klawisz z krotnością albo ukryty tekst.
class _Znaczek extends StatelessWidget {
  final String tooltip;
  final IconData? icon;
  final String? label;
  final int count;
  final bool mirrored;

  const _Znaczek({
    required this.tooltip,
    this.icon,
    this.label,
    this.count = 1,
    this.mirrored = false,
  });

  @override
  Widget build(BuildContext context) {
    final k = ChattTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ikona = icon;
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: k.surface2,
          borderRadius: BorderRadius.circular(math.min(k.radiusBadge, 8)),
          border: Border.all(color: k.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ikona != null)
              Transform.flip(
                flipX: mirrored,
                child: Icon(ikona, size: 14, color: scheme.onSurfaceVariant),
              ),
            if (label != null)
              Text(label!,
                  style: k.caption.copyWith(color: scheme.onSurfaceVariant)),
            if (ikona != null && count > 1) ...[
              const SizedBox(width: 3),
              Text('$count',
                  style: k.caption.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wiersz z ikoną i drobnym tekstem, jak uwagi w kartach Ustawień.
class _Uwaga extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Uwaga({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _Pusto extends StatelessWidget {
  const _Pusto();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.manage_history_outlined,
                size: 72, color: scheme.outline),
            const SizedBox(height: 16),
            Text(context.l10n.typingHistoryEmptyTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              context.l10n.typingHistoryEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
