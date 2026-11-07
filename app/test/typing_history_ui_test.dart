import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/services/typing_journal.dart';
import 'package:chatt/ui/screens/settings/keyboard_addon_card.dart';
import 'package:chatt/ui/screens/settings/settings_category_row.dart';
import 'package:chatt/ui/screens/settings/settings_widgets.dart'
    show SettingsPage;
import 'package:chatt/ui/screens/settings_screen.dart';
import 'package:chatt/ui/screens/typing_history_screen.dart';
import 'package:chatt/ui/widgets/toasts.dart';

/// Historia pisania na ekranie (issue #50): przełącznik w karcie dodatku,
/// lista sesji z kierunkiem i wynikiem słowami, podgląd sesji z odtworzonym
/// tekstem, ukryte pola jako kropki i czyszczenie z pytaniem. Do tego jej
/// miejsce w Ustawieniach w kategoriach (issue #71): lista kategorii,
/// wejście z Klawiatury z PC i Dane i diagnostyka bez historii pisania.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final teksty = lookupAppLocalizations(const Locale('en'));

  late Directory katalog;

  setUp(() =>
      katalog = Directory.systemTemp.createTempSync('chatt_pisanie_ui_'));
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
        // Dziennik pisania powstaje przy pierwszym użyciu. Utworzony
        // w fałszywym czasie testu miałby tam swoją kolejkę zapisów,
        // a zamknięcie stosu czekałoby na nią w prawdziwym bez końca.
        await services.typingJournal.flush();
        return services;
      }))!;

  /// Drzewo schodzi przed zamknięciem stosu. Zamknięcie idzie na zmianę
  /// w prawdziwym i fałszywym czasie: kolejki zapisów dziennika i historii
  /// pisania mogły dostać kolejne kroki ze stuknięć, czyli z fałszywej
  /// strefy, i tylko tam da się je dokończyć.
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

  Widget aplikacja(AppServices services, Widget ekran) => ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ekran,
        ),
      );

  /// Zapis do bazy i strumienie żyją w prawdziwym czasie, ekran w fałszywym.
  /// Na zmianę dajemy pochodzić jednemu i drugiemu, aż [warunek] się spełni.
  Future<void> dokoncz(WidgetTester tester, bool Function() warunek) async {
    for (var i = 0; i < 100 && !warunek(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(warunek(), isTrue, reason: 'ekran nie doszedł do oczekiwanego stanu');
  }

  /// Sesja w bazie, z kawałkami. Zwraca jej numer.
  Future<int> sesja(
    WidgetTester tester,
    AppServices services, {
    required MessageDirection direction,
    required String peer,
    required String result,
    required DateTime start,
    DateTime? end,
    String? reason,
    List<({String status, String field, String label, List<TypingOp> ops})>
        kawalki = const [],
  }) async =>
      (await tester.runAsync(() async {
        final id = await services.db.insertTypingSession(
          TypingSessionsCompanion.insert(
            inputId: 'input-$peer-${start.millisecondsSinceEpoch}',
            direction: direction,
            peerGuid: 'guid-$peer',
            peerName: peer,
            startedAt: start,
            result: result,
            endedAt: Value(end),
            endReason: Value(reason),
          ),
        );
        await services.db.insertTypingEntries([
          for (final (i, k) in kawalki.indexed)
            TypingEntriesCompanion.insert(
              sessionId: id,
              at: start.add(Duration(seconds: i + 1)),
              appLabel: Value(k.label),
              field: k.field,
              status: k.status,
              ops: TypingOp.encode(k.ops),
              chars: Value(k.ops.fold(0, (suma, op) => suma + op.chars)),
              masked: Value(k.ops.any((op) => op.hidden)),
            ),
        ]);
        return id;
      }))!;

  /// Stuknięcie w wiersz [kategoria] na liście Ustawień, najpierw
  /// przewiniętej do niego. Kategoria wjeżdża ruchem stylu, a po wjeździe
  /// lista chowa się pod nią i jej wiersze znikają z wyszukiwania.
  Future<void> otworz(WidgetTester tester, SettingsSection kategoria) async {
    final wiersz = find.byKey(ValueKey(kategoria));
    await dokoncz(tester, () => wiersz.evaluate().isNotEmpty);
    await tester.ensureVisible(wiersz);
    await tester.pump();
    await tester.tap(wiersz);
    await dokoncz(tester, () => wiersz.evaluate().isEmpty);
  }

  /// Systemowe Wstecz z kategorii: kategoria odjeżdża i zostaje sama lista.
  Future<void> doListy(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await dokoncz(tester, () => find.byType(SettingsPage).evaluate().isEmpty);
  }

  /// Przewijanie otwartej kategorii. Lista kategorii zostaje w drzewie pod
  /// kategorią, a w czasie przejścia widać obie, więc pierwsze przewijanie
  /// w drzewie bywa przewijaniem listy.
  Finder przewijanieKategorii() => find
      .descendant(
          of: find.byType(SettingsPage), matching: find.byType(Scrollable))
      .first;

  /// Lista kategorii tak, jak stoi na ekranie: karty od góry, a w każdej
  /// tytuły wierszy od góry.
  List<List<String>> kartyListy(WidgetTester tester) {
    final wiersze = find.byType(SettingsCategoryRow);
    final odGory = [
      for (var i = 0; i < wiersze.evaluate().length; i++) wiersze.at(i),
    ]..sort(
        (a, b) => tester.getTopLeft(a).dy.compareTo(tester.getTopLeft(b).dy));
    final karty = <Element, List<String>>{};
    for (final wiersz in odGory) {
      final karta = tester.element(
          find.ancestor(of: wiersz, matching: find.byType(Card)).first);
      final tytul = tester.widget<Text>(
          find.descendant(of: wiersz, matching: find.byType(Text)).first);
      (karty[karta] ??= []).add(tytul.data!);
    }
    return [...karty.values];
  }

  testWidgets('przełącznik „Zapisuj historię pisania" jest tylko z dodatkiem '
      'i zapisuje się w bazie', (tester) async {
    final services = await uruchom(tester);
    await tester.pumpWidget(aplikacja(
      services,
      const Scaffold(body: SingleChildScrollView(child: KeyboardAddonCard())),
    ));
    await tester.pump();

    final przelacznik =
        find.widgetWithText(SwitchListTile, teksty.typingHistorySwitch);
    expect(przelacznik, findsNothing, reason: 'historia należy do dodatku');
    expect(find.text(teksty.typingHistory), findsNothing);

    services.keyboardAddon.value = true;
    await tester.pump();
    expect(przelacznik, findsOneWidget);
    expect(find.text(teksty.typingHistoryHelp), findsOneWidget);
    expect(tester.widget<SwitchListTile>(przelacznik).value, isTrue,
        reason: 'domyślnie włączony');

    Future<bool?> wBazie() async =>
        (await tester.runAsync(services.db.getSettings))?.typingHistory;

    await tester.tap(przelacznik);
    await tester.pump();
    expect(services.typingHistory.value, isFalse);
    expect(tester.widget<SwitchListTile>(przelacznik).value, isFalse);
    var zapisane = await wBazie();
    for (var i = 0; i < 50 && zapisane != false; i++) {
      await tester.pump();
      zapisane = await wBazie();
    }
    expect(zapisane, isFalse);

    await tester.tap(przelacznik);
    await tester.pump();
    expect(services.typingHistory.value, isTrue);
    expect(services.typingJournal.enabled, isTrue);
    zapisane = await wBazie();
    for (var i = 0; i < 50 && zapisane != true; i++) {
      await tester.pump();
      zapisane = await wBazie();
    }
    expect(zapisane, isTrue);

    // Bez dodatku historia nic nie zapisuje, choć przełącznik stoi.
    services.keyboardAddon.value = false;
    await tester.pump();
    expect(przelacznik, findsNothing);
    expect(services.typingJournal.enabled, isFalse);

    await sprzatnij(tester, services);
  });

  testWidgets('przycisk w karcie dodatku otwiera pustą historię',
      (tester) async {
    final services = await uruchom(tester);
    services.keyboardAddon.value = true;
    await tester.pumpWidget(aplikacja(
      services,
      const Scaffold(body: SingleChildScrollView(child: KeyboardAddonCard())),
    ));
    await tester.pump();

    await tester.tap(find.text(teksty.typingHistory));
    await dokoncz(tester,
        () => find.text(teksty.typingHistoryEmptyTitle).evaluate().isNotEmpty);
    expect(find.byType(TypingHistoryScreen), findsOneWidget);
    expect(find.text(teksty.typingHistoryEmptyBody), findsOneWidget);
    // Zapis włączony: bez uwagi o wyłączonym zapisie.
    expect(find.text(teksty.typingHistoryOff), findsNothing);
    final wyczysc =
        find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined);
    expect(tester.widget<IconButton>(wyczysc).onPressed, isNull,
        reason: 'nie ma czego czyścić');

    services.typingHistory.value = false;
    await tester.pump();
    expect(find.text(teksty.typingHistoryOff), findsOneWidget);

    await sprzatnij(tester, services);
  });

  testWidgets('lista: od najnowszej, kierunek i wynik słowami, odmowa '
      'osobno', (tester) async {
    final services = await uruchom(tester);
    await sesja(
      tester,
      services,
      direction: MessageDirection.outgoing,
      peer: 'Alicja',
      result: TypingResult.accepted,
      start: DateTime(2026, 10, 18, 10, 0, 0),
      end: DateTime(2026, 10, 18, 10, 3, 5),
      reason: TypingEnd.stoppedHere,
      kawalki: [
        (
          status: TypingStatus.typed.name,
          field: RemoteInputField.text.name,
          label: 'Notatnik',
          ops: const [TypingOp.insert('Cześć'), TypingOp.action()],
        ),
      ],
    );
    await sesja(
      tester,
      services,
      direction: MessageDirection.incoming,
      peer: 'Celina',
      result: TypingResult.rejected,
      start: DateTime(2026, 10, 18, 11, 0, 0),
      end: DateTime(2026, 10, 18, 11, 0, 0),
    );
    await sesja(
      tester,
      services,
      direction: MessageDirection.incoming,
      peer: 'Darek',
      result: TypingResult.automatic,
      start: DateTime(2026, 10, 18, 9, 0, 0),
    );

    await tester.pumpWidget(aplikacja(services, const TypingHistoryScreen()));
    await dokoncz(tester,
        () => find.text('This device typed on Alicja').evaluate().isNotEmpty);

    expect(find.text('Celina typed on this device'), findsOneWidget);
    expect(find.text('Darek typed on this device'), findsOneWidget);
    expect(find.text(teksty.typingResultRejected), findsOneWidget);
    expect(
        find.text('${teksty.typingResultAccepted} · '
            '${teksty.typingEndStoppedHere}'),
        findsOneWidget);
    expect(
        find.text('${teksty.typingResultAutomatic} · '
            '${teksty.typingHistoryNotEnded}'),
        findsOneWidget);
    expect(find.text('18.10.2026 10:00 · 3 min 05 s · 5 characters'),
        findsOneWidget);
    expect(find.text('Notatnik'), findsOneWidget);
    // Odmowa ma własną ikonę i bez czasu trwania czy liczby znaków.
    expect(find.byIcon(Icons.block), findsOneWidget);
    expect(find.text('18.10.2026 11:00'), findsOneWidget);

    // Od najnowszej: Celina (11:00), Alicja (10:00), Darek (9:00).
    double y(String tekst) => tester.getTopLeft(find.text(tekst)).dy;
    expect(y('Celina typed on this device'),
        lessThan(y('This device typed on Alicja')));
    expect(y('This device typed on Alicja'),
        lessThan(y('Darek typed on this device')));

    await sprzatnij(tester, services);
  });

  testWidgets('podgląd: odtworzony tekst, ukryte pole jako kropki, klawisze '
      'jako znaczki, nigdy tekst hasła', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final services = await uruchom(tester);
    services.keyboardAddon.value = true;

    // Prawdziwa droga: dziennik pisania tak, jak woła go odbiorca.
    await tester.runAsync(() async {
      const notatnik = RemoteInputTarget(
          active: true, field: RemoteInputField.text, appLabel: 'Notatnik');
      const bank = RemoteInputTarget(
          active: true, field: RemoteInputField.password, appLabel: 'Bank');
      final dziennik = services.typingJournal;
      final s = dziennik.begin(
        direction: MessageDirection.incoming,
        inputId: 'input-1',
        peerGuid: 'guid-alicja',
        peerName: 'Alicja',
        result: TypingResult.accepted,
      );
      dziennik.record(s, const [RemoteInputOp.insert('Hej!')],
          status: TypingStatus.typed, before: notatnik, after: notatnik);
      dziennik.record(
          s, const [RemoteInputOp.backspace(), RemoteInputOp.action()],
          status: TypingStatus.typed, before: notatnik, after: notatnik);
      dziennik.record(s, const [RemoteInputOp.insert('tajne123')],
          status: TypingStatus.typed, before: bank, after: bank);
      dziennik.record(s, const [RemoteInputOp.delete(2)],
          status: TypingStatus.typed, before: notatnik, after: notatnik);
      // Wstrzymane nie dotarło do pola: nie wchodzi do tekstu.
      dziennik.record(s, const [RemoteInputOp.insert('czeka')],
          status: TypingStatus.paused, before: notatnik, after: notatnik);
      dziennik.end(s, TypingEnd.stoppedByPeer);
      await dziennik.flush();
    });
    final wpisy = await tester.runAsync(services.db.allTypingEntries);
    expect(wpisy, hasLength(4));
    expect(wpisy!.any((e) => e.ops.contains('tajne')), isFalse,
        reason: 'tekst hasła nie trafia do bazy');

    await tester.pumpWidget(aplikacja(services, const TypingHistoryScreen()));
    await dokoncz(tester,
        () => find.text('Alicja typed on this device').evaluate().isNotEmpty);
    expect(
        find.text('${teksty.typingResultAccepted} · '
            '${teksty.typingEndStoppedByPeer}'),
        findsOneWidget);

    await tester.tap(find.text('Alicja typed on this device'));
    // Odtworzony tekst stoi dopiero, gdy kawałki przyszły z bazy.
    final odtworzony = find.byWidgetPredicate(
        (w) => w is SelectableText && w.data == 'Hej\n••••••••');
    await dokoncz(tester, () => odtworzony.evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TypingSessionScreen), findsOneWidget);

    // Nagłówek.
    expect(find.text(teksty.typingHistoryStarted), findsOneWidget);
    expect(find.text(teksty.typingResultAccepted), findsOneWidget);
    expect(find.text(teksty.typingEndStoppedByPeer), findsOneWidget);
    expect(find.text('Notatnik, Bank'), findsOneWidget);
    expect(find.text('17 characters'), findsOneWidget,
        reason: 'Hej! (4), hasło (8), czeka (5)');
    expect(
        find.byWidgetPredicate(
            (w) => w is SelectableText && w.data == 'input-1'),
        findsOneWidget);

    // Odtworzony tekst: Backspace zabrał wykrzyknik, Enter to nowa linia,
    // hasło to kropki, Delete nie zmienia tekstu, wstrzymane nie weszło.
    expect(odtworzony, findsOneWidget);
    expect(find.byTooltip(teksty.copyText), findsOneWidget);
    expect(find.text(teksty.typingHistoryTextNote), findsOneWidget);

    // Przebieg: tekst, znaczki klawiszy, kropki z liczbą znaków, rodzaj
    // pola i skutek słowami.
    await tester.scrollUntilVisible(find.text('czeka'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Hej!'), findsOneWidget);
    expect(find.byTooltip(teksty.typingKeyBackspace), findsOneWidget);
    expect(find.byTooltip(teksty.typingKeyEnter), findsOneWidget);
    expect(find.byTooltip(teksty.typingKeyDelete), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'Delete razy dwa');
    expect(find.text('•••••••• 8'), findsOneWidget);
    expect(find.byTooltip(teksty.typingHistoryHidden), findsOneWidget);
    expect(find.text(teksty.typingFieldPassword), findsOneWidget);
    expect(find.text(teksty.typingStatusPaused), findsOneWidget);
    expect(find.text(teksty.typingStatusTyped), findsNWidgets(3));
    expect(find.text('Bank'), findsOneWidget);
    expect(find.textContaining('tajne'), findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets('„Wyczyść historię pisania" pyta i czyści', (tester) async {
    final services = await uruchom(tester);
    await sesja(
      tester,
      services,
      direction: MessageDirection.outgoing,
      peer: 'Alicja',
      result: TypingResult.accepted,
      start: DateTime(2026, 10, 18, 10),
      end: DateTime(2026, 10, 18, 10, 1),
      reason: TypingEnd.linkLost,
      kawalki: [
        (
          status: TypingStatus.unconfirmed.name,
          field: RemoteInputField.text.name,
          label: '',
          ops: const [TypingOp.insert('abc')],
        ),
      ],
    );
    await tester.pumpWidget(aplikacja(services, const TypingHistoryScreen()));
    await dokoncz(tester,
        () => find.text('This device typed on Alicja').evaluate().isNotEmpty);

    final wyczysc = find.byTooltip(teksty.typingHistoryClear);
    await tester.tap(wyczysc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(teksty.typingHistoryClearTitle), findsOneWidget);

    // Najpierw rezygnacja: nic nie znika.
    await tester.tap(find.text(teksty.cancel));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('This device typed on Alicja'), findsOneWidget);

    await tester.tap(wyczysc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, teksty.delete));
    await dokoncz(tester,
        () => find.text(teksty.typingHistoryEmptyTitle).evaluate().isNotEmpty);
    expect(find.text('This device typed on Alicja'), findsNothing);
    expect(await tester.runAsync(services.db.allTypingSessions), isEmpty);
    expect(await tester.runAsync(services.db.allTypingEntries), isEmpty);
    expect(chattToasts.value.map((t) => t.text),
        contains(teksty.typingHistoryCleared(1)));

    await sprzatnij(tester, services);
  });

  testWidgets('„Wyczyść historię" w Ustawieniach zabiera też historię '
      'pisania', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final services = await uruchom(tester);
    await tester.runAsync(() async {
      final alicja = await services.db.upsertPeer(
        guid: 'guid-alicja',
        name: 'Alicja',
        welcomeMessage: '',
        host: '',
        port: 0,
      );
      final rozmowa = await services.db.ensureConversation(alicja.id);
      await services.db.insertIncoming(
        conversationId: rozmowa,
        messageGuid: 'm-1',
        body: 'cześć',
        sentAt: DateTime.now(),
      );
    });
    await sesja(
      tester,
      services,
      direction: MessageDirection.incoming,
      peer: 'Alicja',
      result: TypingResult.noAnswer,
      start: DateTime(2026, 10, 18, 10),
      end: DateTime(2026, 10, 18, 10),
    );

    await tester.pumpWidget(aplikacja(services, const SettingsScreen()));
    // Prywatność: u góry opis kasowania starych wiadomości, który mówi
    // o historii pisania, a Wyczyść historię na samym końcu.
    await otworz(tester, SettingsSection.privacy);
    expect(find.text(teksty.retentionHelp), findsOneWidget);
    await tester.scrollUntilVisible(find.text(teksty.clearHistory), 300,
        scrollable: przewijanieKategorii());
    await tester.pump();
    await tester.tap(find.text(teksty.clearHistory));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(teksty.clearHistoryBody), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, teksty.delete));
    await dokoncz(tester, () => chattToasts.value.isNotEmpty);

    expect(chattToasts.value.map((t) => t.text),
        contains(teksty.historyClearedWithTyping(1, 1)));
    expect(await tester.runAsync(services.db.allTypingSessions), isEmpty);

    await sprzatnij(tester, services);
  });

  testWidgets('lista Ustawień: kategorie od góry w kolejności SettingsSection, '
      'w trzech kartach; na Linuksie bez Nasłuchu w tle', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final services = await uruchom(tester);

    // Od Ciebie, przez łączenie z innymi urządzeniami, do samej aplikacji.
    final naWindows = [
      [teksty.profileSection],
      [
        teksty.connectionSection,
        teksty.backgroundListening,
        teksty.keyboardAddon,
      ],
      [teksty.appearance, teksty.privacy, teksty.dataSection, teksty.updates],
    ];
    expect([for (final karta in naWindows) ...karta],
        [for (final k in SettingsSection.values) k.title(teksty)]);

    Future<void> lista(TargetPlatform platforma) async {
      // Nowe drzewo: platforma ekranu ustala się przy jego powstaniu.
      await tester.pumpWidget(KeyedSubtree(
        key: ValueKey(platforma),
        child: aplikacja(services, SettingsScreen(platform: platforma)),
      ));
      await dokoncz(tester,
          () => find.byType(SettingsCategoryRow).evaluate().isNotEmpty);
    }

    await lista(TargetPlatform.windows);
    expect(kartyListy(tester), naWindows);

    // Na Linuksie proces żyje tak długo jak okno, więc Nasłuch w tle nie ma
    // czego ustawiać i znika z listy.
    await lista(TargetPlatform.linux);
    expect(find.byKey(const ValueKey(SettingsSection.backgroundListening)),
        findsNothing);
    expect(find.text(teksty.backgroundListening), findsNothing);
    expect(kartyListy(tester), [
      naWindows[0],
      [teksty.connectionSection, teksty.keyboardAddon],
      naWindows[2],
    ]);

    await sprzatnij(tester, services);
  });

  testWidgets('„Klawiatura z PC": wejście do historii pisania pod kartą tylko '
      'bez dodatku i z sesjami, na żywo; „Dane i diagnostyka" to eksport '
      'i dziennik', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final services = await uruchom(tester);
    double y(Finder f) => tester.getTopLeft(f).dy;

    await tester.pumpWidget(aplikacja(
        services, const SettingsScreen(platform: TargetPlatform.android)));
    await otworz(tester, SettingsSection.keyboard);
    // Nazwa kategorii w pasku, ta sama w tytule przełącznika dodatku.
    expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.text(teksty.keyboardAddon)),
        findsOneWidget);
    final karta = find.byType(KeyboardAddonCard);
    final wejscie = find.widgetWithText(OutlinedButton, teksty.typingHistory);
    expect(karta, findsOneWidget);

    // Bez dodatku i bez sesji: sama karta.
    expect(find.text(teksty.typingHistory), findsNothing);

    // Pierwsza sesja w historii: wejście pojawia się pod kartą od razu,
    // choć dodatek jest wyłączony.
    await sesja(
      tester,
      services,
      direction: MessageDirection.incoming,
      peer: 'Alicja',
      result: TypingResult.rejected,
      start: DateTime(2026, 10, 18, 10),
      end: DateTime(2026, 10, 18, 10),
    );
    await dokoncz(tester, () => wejscie.evaluate().isNotEmpty);
    expect(services.keyboardAddon.value, isFalse);
    expect(find.descendant(of: karta, matching: wejscie), findsNothing);
    expect(y(karta), lessThan(y(wejscie)));
    expect(find.text(teksty.typingHistoryEntryHelp(1)), findsOneWidget);

    // Włączony dodatek ma ten przycisk w swojej karcie: wejście pod kartą
    // znika i przycisk zostaje jeden.
    services.keyboardAddon.value = true;
    await tester.pump();
    expect(wejscie, findsOneWidget);
    expect(find.descendant(of: karta, matching: wejscie), findsOneWidget);
    expect(find.text(teksty.typingHistoryEntryHelp(1)), findsNothing);
    services.keyboardAddon.value = false;
    await tester.pump();
    expect(wejscie, findsOneWidget);
    expect(find.descendant(of: karta, matching: wejscie), findsNothing);

    await tester.tap(wejscie);
    await dokoncz(tester,
        () => find.text('Alicja typed on this device').evaluate().isNotEmpty);
    expect(find.byType(TypingHistoryScreen), findsOneWidget);

    // Wstecz: z historii do kategorii, z kategorii do listy.
    await tester.binding.handlePopRoute();
    await dokoncz(
        tester, () => find.byType(TypingHistoryScreen).evaluate().isEmpty);
    expect(karta, findsOneWidget);
    await doListy(tester);

    // Dane i diagnostyka: eksport, pod nim dziennik, każdy z opisem pod
    // spodem. Historii pisania tu nie ma, także z sesjami.
    await otworz(tester, SettingsSection.data);
    final eksport = find.widgetWithText(OutlinedButton, teksty.exportData);
    final dziennik = find.widgetWithText(OutlinedButton, teksty.appLog);
    expect(eksport, findsOneWidget);
    expect(dziennik, findsOneWidget);
    expect(y(eksport), lessThan(y(find.text(teksty.exportDataHelp))));
    expect(y(find.text(teksty.exportDataHelp)), lessThan(y(dziennik)));
    expect(y(dziennik), lessThan(y(find.text(teksty.appLogHelp))));
    expect(find.text(teksty.typingHistory), findsNothing);

    await sprzatnij(tester, services);
  });

  test('napisy: stałe nazwy po polsku i słowa dla każdego wyniku, końca '
      'i skutku w obu językach', () {
    final pl = lookupAppLocalizations(const Locale('pl'));
    expect(pl.typingHistorySwitch, 'Zapisuj historię pisania');
    expect(pl.typingHistory, 'Historia pisania');
    expect(pl.typingHistoryClear, 'Wyczyść historię pisania');
    expect(pl.dataSection, 'Dane i diagnostyka');
    expect(pl.exportData, 'Eksportuj dane');
    expect(pl.appLog, 'Dziennik aplikacji');
    expect(teksty.typingHistorySwitch, 'Save typing history');
    expect(teksty.typingHistory, 'Typing history');
    expect(teksty.typingHistoryClear, 'Clear typing history');
    expect(teksty.dataSection, 'Data and diagnostics');
    expect(teksty.exportData, 'Export data');
    expect(teksty.appLog, 'App log');

    const wyniki = [
      TypingResult.accepted,
      TypingResult.acceptedAlways,
      TypingResult.automatic,
      TypingResult.rejected,
      TypingResult.noAnswer,
      TypingResult.busy,
      TypingResult.notEnabled,
      TypingResult.cancelled,
      TypingResult.unreachable,
      TypingResult.olderPeer,
    ];
    const konce = [
      TypingEnd.stoppedHere,
      TypingEnd.stoppedByPeer,
      TypingEnd.expired,
      TypingEnd.receiveOff,
      TypingEnd.addonOff,
      TypingEnd.replaced,
      TypingEnd.peerRemoved,
      TypingEnd.notAllowed,
      TypingEnd.linkLost,
      TypingEnd.appClosed,
    ];
    for (final l10n in [pl, teksty]) {
      final slowaWynikow = {for (final w in wyniki) typingResultLabel(l10n, w)};
      expect(slowaWynikow, hasLength(wyniki.length));
      expect(slowaWynikow.intersection(wyniki.toSet()), isEmpty,
          reason: 'każdy wynik ma swoje słowa');
      final slowaKoncow = {for (final k in konce) typingEndLabel(l10n, k)};
      expect(slowaKoncow, hasLength(konce.length));
      expect(slowaKoncow.intersection(konce.toSet()), isEmpty);
      expect(typingEndLabel(l10n, null), l10n.typingHistoryNotEnded);
      final slowaSkutkow = {
        for (final s in TypingStatus.values) typingStatusLabel(l10n, s),
      };
      expect(slowaSkutkow, hasLength(TypingStatus.values.length));
    }
    // Nieznany napis z nowszego Chatta idzie dosłownie.
    expect(typingResultLabel(teksty, 'nowyWynik'), 'nowyWynik');
    expect(typingEndLabel(teksty, 'nowyKoniec'), 'nowyKoniec');
    // Bez rodzaju: kierunek po polsku nie odmienia czasownika.
    expect(pl.typingHistoryIncoming('Alicja'), 'Pisanie tutaj z: Alicja');
    expect(pl.typingHistoryOutgoing('Alicja'), 'Pisanie stąd na: Alicja');
  });
}
