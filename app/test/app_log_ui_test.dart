import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/services/app_log.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/ui/screens/app_log_screen.dart';
import 'package:chatt/ui/screens/settings_screen.dart';
import 'package:chatt/ui/widgets/export_dialog.dart';
import 'package:chatt/ui/widgets/toasts.dart';

/// Dziennik aplikacji na ekranie (issue #50): wpisy od najnowszego z datą,
/// wagą, obszarem i wiadomością, filtr ostrzeżeń i błędów, szczegóły po
/// stuknięciu, kopiowanie, czyszczenie z pytaniem i eksport samego dziennika.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final teksty = lookupAppLocalizations(const Locale('en'));

  late Directory katalog;
  late List<String> schowek;

  setUp(() {
    katalog = Directory.systemTemp.createTempSync('chatt_dziennik_ui_');
    schowek = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        schowek.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    chattToasts.clear();
    katalog.deleteSync(recursive: true);
  });

  /// Stos z pustym dziennikiem i trzema wpisami: informacja, ostrzeżenie
  /// i błąd ze śladem stosu, po minucie odstępu.
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
        // Wpisy ze startu stosu nie należą do tego testu.
        await services.log.flush();
        await services.db.clearLog();
        AppLogEntriesCompanion wpis(DateTime at, LogLevel level, String area,
                String message, [String? details]) =>
            AppLogEntriesCompanion.insert(
              atMs: at.millisecondsSinceEpoch,
              level: level,
              area: area,
              message: message,
              details: Value(details),
            );
        await services.db.insertLogEntries([
          wpis(DateTime(2026, 10, 18, 15, 30, 12, 345), LogLevel.info,
              LogArea.net, 'Server listening'),
          wpis(DateTime(2026, 10, 18, 15, 31, 0, 7), LogLevel.warning,
              LogArea.file, 'Transfer stalled'),
          wpis(DateTime(2026, 10, 18, 15, 32, 5, 120), LogLevel.error,
              LogArea.error, 'Unhandled exception',
              'StateError: boom\n#0      main (file:///app.dart:1:1)'),
        ]);
        return services;
      }))!;

  /// Drzewo schodzi przed zamknięciem stosu. Zamknięcie idzie na zmianę
  /// w prawdziwym i fałszywym czasie: zapisy do dziennika ze stuknięć
  /// (np. z okna eksportu) mają swoją kolejkę w fałszywej strefie testu.
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

  Widget aplikacja(AppServices services, Widget ekran,
          {Locale locale = const Locale('en')}) =>
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ekran,
        ),
      );

  /// Strumienie z bazy żyją w prawdziwym czasie, ekran w fałszywym. Na
  /// zmianę dajemy pochodzić jednemu i drugiemu, aż [warunek] się spełni.
  Future<void> dokoncz(WidgetTester tester, bool Function() warunek) async {
    for (var i = 0; i < 100 && !warunek(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(warunek(), isTrue, reason: 'ekran nie doszedł do oczekiwanego stanu');
  }

  bool widac(String tekst) => find.text(tekst).evaluate().isNotEmpty;

  testWidgets('wpisy od najnowszego z datą, wagą i obszarem; szczegóły '
      'po stuknięciu', (tester) async {
    final services = await uruchom(tester);
    await tester.pumpWidget(aplikacja(services, const AppLogScreen()));
    await dokoncz(tester, () => widac('Server listening'));

    expect(find.text(teksty.appLog), findsOneWidget, reason: 'tytuł');
    expect(find.text('Transfer stalled'), findsOneWidget);
    expect(find.text('Unhandled exception'), findsOneWidget);
    expect(find.text('18.10.2026 15:30:12 · net'), findsOneWidget);
    expect(find.text('18.10.2026 15:31:00 · file'), findsOneWidget);
    expect(find.text('18.10.2026 15:32:05 · error'), findsOneWidget);
    expect(find.byTooltip(teksty.appLogLevelInfo), findsOneWidget);
    expect(find.byTooltip(teksty.appLogLevelWarning), findsOneWidget);
    expect(find.byTooltip(teksty.appLogLevelError), findsOneWidget);

    // Od najnowszego.
    double y(String tekst) => tester.getTopLeft(find.text(tekst)).dy;
    expect(y('Unhandled exception'), lessThan(y('Transfer stalled')));
    expect(y('Transfer stalled'), lessThan(y('Server listening')));

    // Kolor wagi z motywu: błąd w kolorze zagrożenia, ostrzeżenie
    // w kolorze ostrzeżenia, informacja stonowana.
    Color? kolorIkony(String waga) => tester
        .widget<Icon>(find.descendant(
            of: find.byTooltip(waga), matching: find.byType(Icon)))
        .color;
    expect(kolorIkony(teksty.appLogLevelError),
        isNot(kolorIkony(teksty.appLogLevelInfo)));
    expect(kolorIkony(teksty.appLogLevelWarning),
        isNot(kolorIkony(teksty.appLogLevelError)));

    // Szczegóły zwinięte; stuknięcie rozwija je do zaznaczania, drugie
    // zwija.
    bool szczegoly() => find
        .byWidgetPredicate((w) =>
            w is SelectableText && (w.data ?? '').startsWith('StateError'))
        .evaluate()
        .isNotEmpty;
    expect(szczegoly(), isFalse);
    expect(find.byTooltip(teksty.appLogDetails), findsOneWidget,
        reason: 'tylko wpis ze szczegółami da się rozwinąć');
    await tester.tap(find.text('Unhandled exception'));
    await tester.pump();
    expect(szczegoly(), isTrue);
    await tester.tap(find.text('Unhandled exception'));
    await tester.pump();
    expect(szczegoly(), isFalse);

    await sprzatnij(tester, services);
  });

  testWidgets('filtr „Ostrzeżenia i błędy" chowa informacje', (tester) async {
    final services = await uruchom(tester);
    await tester.pumpWidget(aplikacja(services, const AppLogScreen()));
    await dokoncz(tester, () => widac('Server listening'));

    await tester.tap(find.text(teksty.appLogFilterProblems));
    await dokoncz(tester, () => !widac('Server listening'));
    expect(find.text('Transfer stalled'), findsOneWidget);
    expect(find.text('Unhandled exception'), findsOneWidget);

    await tester.tap(find.text(teksty.appLogFilterAll));
    await dokoncz(tester, () => widac('Server listening'));
    expect(find.text('Transfer stalled'), findsOneWidget);

    await sprzatnij(tester, services);
  });

  testWidgets('kopiowanie oddaje widoczne wpisy jako tekst, od najstarszego',
      (tester) async {
    final services = await uruchom(tester);
    await tester.pumpWidget(aplikacja(services, const AppLogScreen()));
    await dokoncz(tester, () => widac('Server listening'));

    await tester.tap(find.byTooltip(teksty.appLogCopy));
    await tester.pump();
    expect(schowek, hasLength(1));
    final tekst = schowek.single;
    const info = '2026-10-18 15:30:12.345 INFO  net  Server listening';
    const ostrzezenie = '2026-10-18 15:31:00.007 WARN  file  Transfer stalled';
    const blad = '2026-10-18 15:32:05.120 ERROR error  Unhandled exception\n'
        '    StateError: boom\n'
        '    #0      main (file:///app.dart:1:1)';
    expect(tekst, contains(info));
    expect(tekst, contains(ostrzezenie));
    expect(tekst, contains(blad));
    expect(tekst.indexOf(info), lessThan(tekst.indexOf(ostrzezenie)));
    expect(tekst.indexOf(ostrzezenie), lessThan(tekst.indexOf(blad)));
    expect(chattToasts.value.map((t) => t.text), contains(teksty.copied));

    // Z filtrem kopiują się tylko widoczne.
    await tester.tap(find.text(teksty.appLogFilterProblems));
    await dokoncz(tester, () => !widac('Server listening'));
    await tester.tap(find.byTooltip(teksty.appLogCopy));
    await tester.pump();
    expect(schowek, hasLength(2));
    expect(schowek.last, isNot(contains('Server listening')));
    expect(schowek.last, contains('Transfer stalled'));

    await sprzatnij(tester, services);
  });

  testWidgets('„Wyczyść dziennik" pyta i czyści', (tester) async {
    final services = await uruchom(tester);
    await tester.pumpWidget(aplikacja(services, const AppLogScreen()));
    await dokoncz(tester, () => widac('Server listening'));

    final wyczysc = find.byTooltip(teksty.appLogClear);
    await tester.tap(wyczysc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(teksty.appLogClearTitle), findsOneWidget);
    expect(find.text(teksty.appLogClearBody), findsOneWidget);

    // Najpierw rezygnacja: nic nie znika.
    await tester.tap(find.text(teksty.cancel));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Server listening'), findsOneWidget);

    await tester.tap(wyczysc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, teksty.delete));
    await dokoncz(tester, () => !widac('Unhandled exception'));
    expect(find.text('Server listening'), findsNothing);
    expect(find.text('Transfer stalled'), findsNothing);
    expect(
        chattToasts.value.map((t) => t.text),
        contains(predicate<String>((t) => [
              for (var n = 3; n < 100; n++) teksty.appLogCleared(n),
            ].contains(t))));
    final zostalo = (await tester.runAsync(services.db.allLogEntries))!;
    expect(
        zostalo.map((e) => e.message),
        isNot(anyOf(
            contains('Server listening'), contains('Unhandled exception'))));

    await sprzatnij(tester, services);
  });

  testWidgets('pusty dziennik i pusty filtr mają swoje napisy',
      (tester) async {
    final services = await uruchom(tester);
    await tester.runAsync(services.db.clearLog);
    await tester.pumpWidget(aplikacja(services, const AppLogScreen()));
    await dokoncz(tester, () => widac(teksty.appLogEmpty));
    final kopiuj = find.widgetWithIcon(IconButton, Icons.copy_all_outlined);
    expect(tester.widget<IconButton>(kopiuj).onPressed, isNull,
        reason: 'nie ma czego kopiować');

    await tester.tap(find.text(teksty.appLogFilterProblems));
    await dokoncz(tester, () => widac(teksty.appLogEmptyProblems));

    await sprzatnij(tester, services);
  });

  testWidgets('eksport z dziennika otwiera okno z samym dziennikiem',
      (tester) async {
    final services = await uruchom(tester);
    await tester.pumpWidget(aplikacja(services, const AppLogScreen()));
    await dokoncz(tester, () => widac('Server listening'));

    await tester.tap(find.byTooltip(teksty.appLogExport));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ExportDialog), findsOneWidget);
    bool? zaznaczone(String tytul) => tester
        .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, tytul))
        .value;
    expect(zaznaczone(teksty.appLog), isTrue);
    expect(zaznaczone(teksty.exportDataConversations), isFalse);
    expect(zaznaczone(teksty.exportDataFiles), isFalse);

    await tester.tap(find.text(teksty.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ExportDialog), findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets('Ustawienia: przycisk „Dziennik aplikacji" w kategorii „Dane '
      'i diagnostyka" otwiera ekran, po polsku', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final pl = lookupAppLocalizations(const Locale('pl'));
    final services = await uruchom(tester);
    await tester.pumpWidget(aplikacja(services, const SettingsScreen(),
        locale: const Locale('pl')));
    await dokoncz(tester, () => widac('Dane i diagnostyka'));
    expect(find.text(pl.appLogHelp), findsNothing,
        reason: 'na liście jest sam wiersz kategorii');

    // Kategoria wjeżdża ruchem stylu, a po wjeździe lista chowa się pod
    // nią: jej wiersze znikają z wyszukiwania.
    final wiersz = find.byKey(const ValueKey(SettingsSection.data));
    expect(
        find.descendant(
            of: wiersz, matching: find.text('Dane i diagnostyka')),
        findsOneWidget);
    await tester.ensureVisible(wiersz);
    await tester.pump();
    await tester.tap(find.text('Dane i diagnostyka'));
    await dokoncz(tester, () => wiersz.evaluate().isEmpty);
    expect(find.text('Dane i diagnostyka'), findsOneWidget,
        reason: 'nazwa kategorii w pasku');
    expect(find.text(pl.appLogHelp), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Dziennik aplikacji'));
    await dokoncz(tester, () => widac('Server listening'));
    expect(find.byType(AppLogScreen), findsOneWidget);
    expect(find.text(pl.appLogFilterProblems), findsOneWidget);
    expect(find.text('18.10.2026 15:30:12 · net'), findsOneWidget);

    await sprzatnij(tester, services);
  });
}
