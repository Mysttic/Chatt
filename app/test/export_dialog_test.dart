import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/file_actions.dart' show SaveResult;
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/data_export.dart';
import 'package:chatt/ui/widgets/export_dialog.dart';
import 'package:chatt/ui/widgets/toasts.dart';

/// Okno „Eksportuj dane" (issue #50) z podstawionym liczeniem i eksportem:
/// liczby przy częściach, historia pisania tylko z sesjami, pliki domyślnie
/// wyłączone, eksport z wybranymi częściami, stan zajęty i komunikat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final teksty = lookupAppLocalizations(const Locale('en'));

  late Directory katalog;

  setUp(() =>
      katalog = Directory.systemTemp.createTempSync('chatt_eksport_okno_'));
  tearDown(() {
    chattToasts.clear();
    katalog.deleteSync(recursive: true);
  });

  Future<AppServices> uruchom(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final services = await AppServices.start(
          executor: NativeDatabase.memory(),
          portOverride: 0,
          nameOverride: 'Bartek',
          enableDiscovery: false,
          receivedDirOverride: '${katalog.path}/Bartek',
        );
        // Dziennik pisania powstaje przy pierwszym użyciu: niech powstanie
        // w prawdziwym czasie, razem z resztą stosu.
        await services.typingJournal.flush();
        return services;
      }))!;

  /// Drzewo schodzi przed zamknięciem stosu. Okno zapisuje w dzienniku
  /// aplikacji nieudane liczenie i eksport, a te zapisy idą w fałszywym
  /// czasie testu, więc zamknięcie przeplata prawdziwy z fałszywym.
  Future<void> sprzatnij(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    var zamkniete = false;
    unawaited(services.dispose().whenComplete(() => zamkniete = true));
    for (var i = 0; i < 300 && !zamkniete; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(zamkniete, isTrue, reason: 'stos się nie zamknął');
  }

  ExportEstimate szacunek({int sesje = 2, int pliki = 3}) => ExportEstimate(
        peers: 4,
        conversations: 3,
        messages: 120,
        typingSessions: sesje,
        logEntries: 57,
        files: pliki,
        fileBytes: pliki == 0 ? 0 : 5 * 1024 * 1024,
      );

  /// Ekran z jednym przyciskiem, który otwiera okno eksportu.
  Future<void> otworz(
    WidgetTester tester,
    AppServices services, {
    required ExportEstimator estimate,
    ExportRunner? exportData,
    ExportParts initial = const ExportParts(),
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showExportDialog(
                context,
                services: services,
                initial: initial,
                estimate: estimate,
                exportData: exportData ??
                    (_, _) => throw StateError('eksport nie był oczekiwany'),
              ),
              child: const Text('otwórz'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('otwórz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  CheckboxListTile pole(WidgetTester tester, String tytul) =>
      tester.widget<CheckboxListTile>(
          find.widgetWithText(CheckboxListTile, tytul));

  FilledButton eksportuj(WidgetTester tester) => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, teksty.exportDataAction));

  testWidgets('liczby przy częściach, pliki domyślnie wyłączone, ostrzeżenie '
      'o braku szyfrowania', (tester) async {
    final services = await uruchom(tester);
    final liczenie = Completer<ExportEstimate>();
    await otworz(tester, services, estimate: (_) => liczenie.future);

    expect(find.text(teksty.exportData), findsOneWidget, reason: 'tytuł');
    // Przed policzeniem: pasek postępu, historia pisania jeszcze ukryta,
    // eksport nieaktywny.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, teksty.typingHistory),
        findsNothing);
    expect(eksportuj(tester).onPressed, isNull);

    liczenie.complete(szacunek());
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('3 conversations, 120 messages, 4 devices'),
        findsOneWidget);
    expect(find.text('2 sessions'), findsOneWidget);
    expect(find.text('57 entries'), findsOneWidget);
    expect(find.text('3 files (5.0 MB)'), findsOneWidget);

    expect(pole(tester, teksty.exportDataConversations).value, isTrue);
    expect(pole(tester, teksty.typingHistory).value, isTrue);
    expect(pole(tester, teksty.appLog).value, isTrue);
    expect(pole(tester, teksty.exportDataFiles).value, isFalse,
        reason: 'odebrane pliki tylko na życzenie');
    expect(pole(tester, teksty.exportDataFiles).onChanged, isNotNull);
    expect(find.text(teksty.exportDataWarning), findsOneWidget);
    expect(eksportuj(tester).onPressed, isNotNull);

    // Nic nie wybrane: nie ma czego eksportować.
    for (final tytul in [
      teksty.exportDataConversations,
      teksty.typingHistory,
      teksty.appLog,
    ]) {
      await tester.tap(find.widgetWithText(CheckboxListTile, tytul));
      await tester.pump();
    }
    expect(eksportuj(tester).onPressed, isNull);

    // Anuluj zamyka okno bez eksportu i bez komunikatu.
    await tester.tap(find.text(teksty.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ExportDialog), findsNothing);
    expect(chattToasts.value, isEmpty);

    await sprzatnij(tester, services);
  });

  testWidgets('bez sesji pisania nie ma pola historii, bez plików pole plików '
      'jest nieaktywne', (tester) async {
    final services = await uruchom(tester);
    ExportParts? wybrane;
    await otworz(
      tester,
      services,
      estimate: (_) async => szacunek(sesje: 0, pliki: 0),
      exportData: (_, czesci) async {
        wybrane = czesci;
        return (result: SaveResult.saved, where: 'Downloads', export: null);
      },
    );
    await tester.pump();

    expect(find.widgetWithText(CheckboxListTile, teksty.typingHistory),
        findsNothing);
    expect(find.text(teksty.historyCountFiles(0)), findsOneWidget);
    expect(pole(tester, teksty.exportDataFiles).onChanged, isNull);
    expect(pole(tester, teksty.exportDataFiles).value, isFalse);

    await tester.tap(find.text(teksty.exportDataAction));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(wybrane, isNotNull);
    expect(wybrane!.conversations, isTrue);
    expect(wybrane!.typing, isFalse, reason: 'nie ma czego eksportować');
    expect(wybrane!.appLog, isTrue);
    expect(wybrane!.files, isFalse);

    await sprzatnij(tester, services);
  });

  testWidgets('eksport idzie z wybranymi częściami, okno czeka zajęte, '
      'potem komunikat z miejscem zapisu', (tester) async {
    final services = await uruchom(tester);
    final eksport =
        Completer<({SaveResult result, String? where, ExportResult? export})>();
    final wywolania = <ExportParts>[];
    await otworz(
      tester,
      services,
      estimate: (_) async => szacunek(),
      exportData: (s, czesci) {
        expect(s, same(services));
        wywolania.add(czesci);
        return eksport.future;
      },
    );
    await tester.pump();

    await tester.tap(
        find.widgetWithText(CheckboxListTile, teksty.exportDataConversations));
    await tester
        .tap(find.widgetWithText(CheckboxListTile, teksty.exportDataFiles));
    await tester.pump();
    await tester.tap(find.text(teksty.exportDataAction));
    await tester.pump();

    expect(wywolania, hasLength(1));
    final czesci = wywolania.single;
    expect(czesci.conversations, isFalse);
    expect(czesci.typing, isTrue);
    expect(czesci.appLog, isTrue);
    expect(czesci.files, isTrue);

    // Zajęte: wszystko zgaszone, postęp z napisem, okno nie daje się
    // zamknąć ani przyciskiem wstecz, ani stuknięciem obok.
    expect(find.text(teksty.exportDataBusy), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(eksportuj(tester).onPressed, isNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, teksty.cancel))
            .onPressed,
        isNull);
    expect(pole(tester, teksty.appLog).onChanged, isNull);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 300));
    final nawigator = tester.state<NavigatorState>(find.byType(Navigator));
    await nawigator.maybePop();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ExportDialog), findsOneWidget);
    expect(wywolania, hasLength(1), reason: 'jeden eksport naraz');

    const gdzie = r'C:\Users\Bartek\Downloads\chatt-export-2026-10-19-1530.zip';
    eksport.complete((
      result: SaveResult.saved,
      where: gdzie,
      export: const ExportResult(
        path: gdzie,
        bytes: 4096,
        files: 2,
        skippedFiles: ['zniknal.txt'],
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ExportDialog), findsNothing);
    expect(chattToasts.value.map((t) => t.text), [
      teksty.exportDataSaved(gdzie),
      teksty.exportDataSkipped(1),
    ]);

    await sprzatnij(tester, services);
  });

  testWidgets('nieudany eksport, zamknięte okno zapisu i brak miejsca '
      'na zapis', (tester) async {
    final services = await uruchom(tester);

    Future<void> eksportZ(
        Future<({SaveResult result, String? where, ExportResult? export})>
                Function()
            wynik) async {
      chattToasts.clear();
      await otworz(
        tester,
        services,
        estimate: (_) async => szacunek(),
        exportData: (_, _) => wynik(),
      );
      await tester.pump();
      await tester.tap(find.text(teksty.exportDataAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ExportDialog), findsNothing);
    }

    await eksportZ(() async => throw const FileSystemException('pełny dysk'));
    expect(chattToasts.value.map((t) => t.text), [teksty.exportDataFailed]);

    // Użytkownik sam zamknął okno zapisu: bez komunikatu.
    await eksportZ(() async =>
        (result: SaveResult.cancelled, where: null, export: null));
    expect(chattToasts.value, isEmpty);

    await eksportZ(() async =>
        (result: SaveResult.unsupported, where: null, export: null));
    expect(chattToasts.value.map((t) => t.text),
        [teksty.exportDataUnsupported]);

    await eksportZ(() async =>
        (result: SaveResult.failed, where: null, export: null));
    expect(chattToasts.value.map((t) => t.text), [teksty.exportDataFailed]);

    await eksportZ(
        () async => (result: SaveResult.saved, where: null, export: null));
    expect(chattToasts.value.map((t) => t.text), [teksty.exportDataDone]);

    await sprzatnij(tester, services);
  });

  testWidgets('liczenie się nie udało: wszystkie części do wyboru, eksport '
      'dalej możliwy', (tester) async {
    final services = await uruchom(tester);
    await otworz(
      tester,
      services,
      estimate: (_) => throw StateError('baza zamknięta'),
      initial: const ExportParts(
          conversations: false, typing: false, appLog: true, files: false),
    );
    await tester.pump();

    expect(find.text(teksty.exportDataEstimateFailed), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(pole(tester, teksty.typingHistory).value, isFalse);
    expect(pole(tester, teksty.exportDataConversations).value, isFalse);
    expect(pole(tester, teksty.appLog).value, isTrue);
    expect(pole(tester, teksty.exportDataFiles).onChanged, isNotNull);
    expect(eksportuj(tester).onPressed, isNotNull);

    await sprzatnij(tester, services);
  });

  testWidgets('okno po polsku', (tester) async {
    final pl = lookupAppLocalizations(const Locale('pl'));
    final services = await uruchom(tester);
    await otworz(
      tester,
      services,
      estimate: (_) async => szacunek(sesje: 5, pliki: 22),
      locale: const Locale('pl'),
    );
    await tester.pump();

    expect(find.text('Eksportuj dane'), findsOneWidget);
    expect(find.text(pl.exportDataAction), findsOneWidget);
    expect(find.text(pl.exportDataWarning), findsOneWidget);
    expect(find.text('3 rozmowy, 120 wiadomości, 4 urządzenia'),
        findsOneWidget);
    expect(find.text('Historia pisania'), findsOneWidget);
    expect(find.text('5 sesji'), findsOneWidget);
    expect(find.text('Dziennik aplikacji'), findsOneWidget);
    expect(find.text('57 wpisów'), findsOneWidget);
    expect(find.text('22 pliki (5.0 MB)'), findsOneWidget);

    await sprzatnij(tester, services);
  });
}
