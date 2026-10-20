import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/ui/screens/chat_screen.dart';
import 'package:chatt/ui/styles.dart';
import 'package:chatt/ui/widgets/history_ui.dart';
import 'package:chatt/ui/widgets/motion.dart';
import 'package:chatt/ui/widgets/prompt_overlay.dart';
import 'package:chatt/ui/widgets/toasts.dart';

/// Jedna klatka. Animacja kończy się w pierwszej klatce po swoim czasie:
/// w samym czasie stoi już u celu, ale z drzewa schodzi klatkę później.
const _klatka = Duration(milliseconds: 16);

/// Krzywa Ciszy: wejścia Ciszy i Precyzji, wyjścia Ciszy.
const _cisza = Cubic(0.2, 0, 0, 1);
const _cieplo = Cubic(0.2, 0.8, 0.2, 1);

/// Karta zgody w każdym stylu według issue #54: wejście i wyjście, krzywa
/// ruchu, przenikania i znikania, początek ruchu na telefonie i w oknie.
/// Przesunięcie dodatnie: z dołu, ujemne: z góry.
const _karty = {
  AppStyle.cisza: (
    wejscie: Duration(milliseconds: 280),
    wyjscie: Duration(milliseconds: 180),
    ruch: _cisza,
    przenikanie: _cisza,
    znikanie: _cisza,
    telefon: (skala: 1.0, przesuniecie: 24.0),
    okno: (skala: 0.96, przesuniecie: 0.0),
  ),
  AppStyle.precyzja: (
    wejscie: Duration(milliseconds: 180),
    wyjscie: Duration(milliseconds: 180),
    ruch: _cisza,
    przenikanie: _cisza,
    znikanie: Cubic(0.3, 0, 1, 1),
    telefon: (skala: 0.98, przesuniecie: 0.0),
    okno: (skala: 0.98, przesuniecie: 0.0),
  ),
  AppStyle.cieplo: (
    wejscie: Duration(milliseconds: 260),
    wyjscie: Duration(milliseconds: 180),
    // Sprężynka tylko w ruchu, przenikanie bez przestrzelenia.
    ruch: Cubic(0.2, 0.9, 0.3, 1.15),
    przenikanie: _cieplo,
    znikanie: _cieplo,
    telefon: (skala: 0.97, przesuniecie: -10.0),
    okno: (skala: 0.97, przesuniecie: -10.0),
  ),
};

/// Udostępnianie historii na ekranie: znacznik przywróconych dymków,
/// separatory dat, wpis pliku bez treści, menu rozmowy, karty zgody i paski
/// postępu. Do tego ruch kart zgody, okna i paska w trzech stylach
/// (issue #54).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final teksty = lookupAppLocalizations(const Locale('en'));

  late Directory katalog;

  setUp(() => katalog = Directory.systemTemp.createTempSync('chatt_hist_ui_'));
  tearDown(() => katalog.deleteSync(recursive: true));

  Future<AppServices> uruchom(WidgetTester tester) async =>
      (await tester.runAsync(() => AppServices.start(
            executor: NativeDatabase.memory(),
            portOverride: 0,
            nameOverride: 'Bartek',
            enableDiscovery: false,
            receivedDirOverride: '${katalog.path}/Bartek',
          )))!;

  Future<void> sprzatnij(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(services.dispose);
  }

  Widget aplikacja(AppServices services,
          {Widget? ekran, TransitionBuilder? builder, ThemeData? theme}) =>
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          theme: theme,
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: builder,
          home: ekran ?? const Scaffold(body: SizedBox.expand()),
        ),
      );

  /// Rozmowa z Alicją: zwykła wiadomość dziś i przywrócone z trzech dni,
  /// w tym plik bez treści.
  Future<(int, Peer)> rozmowa(WidgetTester tester, AppServices s) async =>
      (await tester.runAsync(() async {
        final alicja = await s.db.upsertPeer(
          guid: 'guid-alicja',
          name: 'Alicja',
          welcomeMessage: '',
          host: '',
          port: 0,
        );
        final id = await s.db.ensureConversation(alicja.id);
        final teraz = DateTime.now();
        await s.db.importHistory(
          conversationId: id,
          restoredAt: teraz,
          notAfter: teraz.add(const Duration(minutes: 10)),
          items: [
            RestoredMessage(
              messageGuid: 'm-stara',
              direction: MessageDirection.incoming,
              sentAt: DateTime(2025, 1, 6, 12),
              body: 'bardzo stara',
            ),
            RestoredMessage(
              messageGuid: 'm-wczoraj',
              direction: MessageDirection.outgoing,
              sentAt: DateTime(teraz.year, teraz.month, teraz.day - 1, 12),
              body: 'wczorajsza',
            ),
            RestoredMessage(
              messageGuid: 'm-plik',
              direction: MessageDirection.incoming,
              sentAt: DateTime(teraz.year, teraz.month, teraz.day - 1, 13),
              body: '📎 umowa.pdf',
              fileName: 'umowa.pdf',
              fileSize: 1200,
            ),
          ],
        );
        await s.db.insertIncoming(
          conversationId: id,
          messageGuid: 'm-dzis',
          body: 'dzisiejsza',
          sentAt: teraz,
        );
        return (id, (await s.db.peerByGuid('guid-alicja'))!);
      }))!;

  testWidgets('przywrócone dymki mają znacznik, a dni swoje daty',
      (tester) async {
    final services = await uruchom(tester);
    final (id, alicja) = await rozmowa(tester, services);
    await tester.pumpWidget(aplikacja(services,
        ekran: ChatScreen(conversationId: id, peer: alicja)));
    await tester.pump();
    await tester.pump();

    expect(find.text('dzisiejsza'), findsOneWidget);
    expect(find.byIcon(Icons.history), findsNWidgets(3),
        reason: 'trzy przywrócone, jedna zwykła');
    expect(find.text(teksty.dateToday), findsOneWidget);
    expect(find.text(teksty.dateYesterday), findsOneWidget);
    expect(find.text(teksty.dateSeparator(DateTime(2025, 1, 6))),
        findsOneWidget);
    expect(find.text(teksty.fileUnavailable), findsOneWidget);
    expect(find.byIcon(Icons.save_alt), findsNothing,
        reason: 'nie ma czego zapisać');

    await sprzatnij(tester, services);
  });

  testWidgets('menu rozmowy prowadzi do okna udostępniania z liczbami',
      (tester) async {
    final services = await uruchom(tester);
    final (id, alicja) = await rozmowa(tester, services);
    await tester.pumpWidget(aplikacja(services,
        ekran: ChatScreen(conversationId: id, peer: alicja)));
    await tester.pump();

    await tester.tap(find.byTooltip(teksty.historyMenu));
    await tester.pumpAndSettle();
    expect(find.text(teksty.historyRequest), findsOneWidget);
    await tester.tap(find.text(teksty.historyShare));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 200)));
    await tester.pump();

    expect(find.text(teksty.historyShareTitle), findsOneWidget);
    expect(find.textContaining(teksty.historyCountMessages(4)), findsOneWidget);
    expect(find.text(teksty.historyMissingFiles(1)), findsOneWidget,
        reason: 'plik bez treści pójdzie bez treści');
    await tester.tap(find.text(teksty.cancel));
    await tester.pumpAndSettle();
    expect(find.text(teksty.historyShareTitle), findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets('starsza rozmowa do wyboru tylko przy zielonej tarczy',
      (tester) async {
    final services = await uruchom(tester);
    final (id, alicja) = await rozmowa(tester, services);
    final staraId = (await tester.runAsync(() async {
      final stara = await services.db.upsertPeer(
        guid: 'guid-alicja-stara',
        name: 'Alicja (stary telefon)',
        welcomeMessage: '',
        host: '',
        port: 0,
      );
      final staraId = await services.db.ensureConversation(stara.id);
      await services.db.insertIncoming(
        conversationId: staraId,
        messageGuid: 'm-stary-telefon',
        body: 'ze starego telefonu',
        sentAt: DateTime.now().subtract(const Duration(days: 40)),
      );
      return staraId;
    }))!;
    expect(staraId, isNot(id));

    // Okno wprost, bez ekranu rozmowy: drogę przez menu sprawdza test wyżej.
    Future<void> otworzOkno(Peer peer) async {
      await tester.pumpWidget(aplikacja(services,
          ekran: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShareHistoryDialog(context,
                    services: services, peer: peer, conversationId: id),
                child: const Text('otwórz'),
              ),
            ),
          )));
      await tester.tap(find.text('otwórz'));
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }

    await otworzOkno(alicja);
    expect(find.text(teksty.historyShareTitle), findsOneWidget);
    expect(find.text(teksty.historySourceNeedsShield), findsOneWidget);
    expect(find.text(teksty.historySource), findsNothing);
    await tester.tap(find.text(teksty.cancel));
    await tester.pump(const Duration(milliseconds: 500));

    final zweryfikowana = (await tester.runAsync(() async {
      await services.db.setPeerVerified(alicja.id, true);
      return services.db.peerByGuid(alicja.guid);
    }))!;
    await otworzOkno(zweryfikowana);
    expect(find.text(teksty.historySourceNeedsShield), findsNothing);
    expect(find.text(teksty.historySource), findsOneWidget);
    expect(find.text(teksty.historyMergeLocally), findsNothing,
        reason: 'połączenie dopiero przy starszej rozmowie');
    await tester.tap(find.text(teksty.historySourceThis));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(
        find.text(teksty.historySourceOther('Alicja (stary telefon)', 1)).last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text(teksty.historyMergeLocally), findsOneWidget);
    expect(find.textContaining(teksty.historyCountMessages(1)), findsOneWidget);

    await sprzatnij(tester, services);
  });

  PendingHistory karta(PendingHistoryKind kind,
          {bool verified = false, int files = 2, int retention = 0}) =>
      PendingHistory(
        id: 'guid-alicja|h1',
        kind: kind,
        peerGuid: 'guid-alicja',
        peerName: 'Alicja',
        fromVerifiedPeer: verified,
        conversationId: 1,
        retentionDays: retention,
        summary: HistorySummary(
          count: 12,
          files: files,
          bytes: files == 0 ? 0 : 2048,
          first: DateTime(2026, 1, 1),
          last: DateTime(2026, 3, 1),
        ),
      );

  testWidgets('karta zapowiedzi: liczby, ostrzeżenia, fokus na Odrzuć',
      (tester) async {
    final services = await uruchom(tester);
    await tester.pumpWidget(aplikacja(services,
        builder: (context, child) => PromptOverlay(child: child!)));
    services.pendingHistory.value = [
      karta(PendingHistoryKind.offer, retention: 30),
    ];
    await tester.pump();
    await tester.pump();

    expect(find.text(teksty.historyOfferTitle('Alicja')), findsOneWidget);
    expect(find.textContaining(teksty.historyCountMessages(12)), findsOneWidget);
    expect(find.text(teksty.historyOfferDeleted), findsOneWidget);
    expect(find.text(teksty.historyOfferMarked), findsOneWidget);
    expect(find.text(teksty.historyOfferUnverified), findsOneWidget);
    expect(find.text(teksty.historyOfferRetention(30)), findsOneWidget);
    expect(find.text(teksty.historyWithoutFiles), findsNothing,
        reason: 'przy zapowiedzi pliki wybrał udostępniający');
    final odrzuc = find.widgetWithText(TextButton, teksty.reject);
    expect(Focus.of(tester.element(find.text(teksty.reject))).hasFocus, isTrue);

    await tester.tap(odrzuc);
    await tester.pump();
    // Karta odjeżdża w czasie stylu (goły MaterialApp: Cisza).
    await tester.pump(_karty[AppStyle.cisza]!.wyjscie + _klatka);
    expect(find.text(teksty.historyOfferTitle('Alicja')), findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets('karta prośby: „bez plików" tylko wtedy, gdy są pliki',
      (tester) async {
    final services = await uruchom(tester);
    await tester.pumpWidget(aplikacja(services,
        builder: (context, child) => PromptOverlay(child: child!)));
    services.pendingHistory.value = [
      karta(PendingHistoryKind.request, verified: true),
    ];
    await tester.pump();
    await tester.pump();
    expect(find.text(teksty.historyRequestTitle('Alicja')), findsOneWidget);
    expect(find.text(teksty.historyWithoutFiles), findsOneWidget);
    expect(find.text(teksty.historyShareAction), findsOneWidget);
    expect(find.text(teksty.historyOfferUnverified), findsNothing);

    services.pendingHistory.value = [
      karta(PendingHistoryKind.request, verified: true, files: 0),
    ];
    await tester.pump();
    await tester.pump();
    expect(find.text(teksty.historyWithoutFiles), findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets('paski postępu: Przerwij po obu stronach, Zamknij po '
      'przywróceniu', (tester) async {
    final services = await uruchom(tester);
    await tester.pumpWidget(aplikacja(services,
        ekran: Scaffold(
          body: HistoryProgressBar(services: services, conversationId: 7),
        )));
    services.outgoingHistory.value = const HistoryTransfer(
      peerName: 'Alicja',
      conversationId: 7,
      messagesTotal: 4,
      messagesDone: 2,
      filesTotal: 1,
    );
    await tester.pump();
    expect(find.text(teksty.historySharing('Alicja')), findsOneWidget);
    expect(find.text(teksty.historyProgressMessages(2, 4)), findsOneWidget);
    expect(find.text(teksty.historyProgressFiles(0, 1)), findsOneWidget);
    expect(find.text(teksty.historyStop), findsOneWidget);

    // Inna rozmowa nie widzi cudzego paska.
    services.outgoingHistory.value = const HistoryTransfer(
      peerName: 'Cezary',
      conversationId: 8,
      messagesTotal: 4,
      filesTotal: 0,
    );
    await tester.pump();
    expect(find.text(teksty.historySharing('Cezary')), findsNothing);
    services.outgoingHistory.value = null;

    // W trakcie przywracania odbierający też ma Przerwij: bez zgody na
    // zapisanie czegokolwiek więcej (pasek z ręki, bez zgody w serwisie,
    // więc samo przyciśnięcie niczego tu nie zmienia).
    services.incomingHistory.value = const HistoryTransfer(
      peerName: 'Alicja',
      conversationId: 7,
      messagesTotal: 4,
      messagesDone: 1,
      filesTotal: 0,
    );
    await tester.pump();
    expect(find.text(teksty.historyRestoring('Alicja')), findsOneWidget);
    expect(find.text(teksty.historyStop), findsOneWidget);
    expect(find.text(teksty.close), findsNothing);

    services.incomingHistory.value = const HistoryTransfer(
      peerName: 'Alicja',
      conversationId: 7,
      messagesTotal: 4,
      messagesDone: 4,
      filesTotal: 0,
      skipped: 1,
      finished: true,
    );
    await tester.pump();
    expect(find.text(teksty.historyRestored('Alicja')), findsOneWidget);
    expect(find.text(teksty.historySkipped(1)), findsOneWidget);
    await tester.tap(find.text(teksty.close));
    await tester.pump();
    expect(services.incomingHistory.value, isNull);
    expect(find.text(teksty.historyRestored('Alicja')), findsNothing);

    await sprzatnij(tester, services);
  });

  // --- Ruch stylów (issue #54) ---------------------------------------------

  /// Zapowiedź historii od [kto], bez ostrzeżeń: sama karta z przyciskami.
  PendingHistory prosba(String id, String kto) => PendingHistory(
        id: id,
        kind: PendingHistoryKind.offer,
        peerGuid: 'guid-$kto',
        peerName: kto,
        fromVerifiedPeer: true,
        conversationId: 1,
        summary: HistorySummary(
          count: 3,
          files: 0,
          bytes: 0,
          first: DateTime(2026, 1, 1),
          last: DateTime(2026, 3, 1),
        ),
      );

  /// Nakładka z kartami jak w aplikacji, w motywie [styl]. Platforma motywu
  /// (telefon albo okno) jest ta z chwili wywołania. [bezAnimacji]:
  /// „ogranicz animacje” w MediaQuery nad nakładką.
  Widget nakladka(AppServices services, AppStyle styl,
          {bool bezAnimacji = false}) =>
      aplikacja(
        services,
        theme: chattTheme(styl, Brightness.light),
        builder: (context, child) {
          final warstwa = PromptOverlay(child: child!);
          return bezAnimacji
              ? MediaQuery(
                  data: MediaQuery.of(context).copyWith(disableAnimations: true),
                  child: warstwa,
                )
              : warstwa;
        },
      );

  /// [cialo] na platformie okna (Windows). Platforma wraca jeszcze w samym
  /// teście: flutter_test sprawdza ją zaraz po nim, przed tearDown.
  Future<void> wOknie(Future<void> Function() cialo) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await cialo();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// Ile widać z [co]: iloczyn przezroczystości nad nim.
  double widac(WidgetTester tester, Finder co) => tester
      .widgetList<Opacity>(
          find.ancestor(of: co, matching: find.byType(Opacity)))
      .fold(1.0, (iloczyn, o) => iloczyn * o.opacity);

  /// Węzeł fokusu przycisku z napisem [napis] na karcie [karta].
  FocusNode fokus(WidgetTester tester, Finder karta, String napis) => tester
      .widget<ButtonStyleButton>(find.ancestor(
        of: find.descendant(of: karta, matching: find.text(napis)),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ))
      .focusNode!;

  /// Karta historii na nakładce w stylu [styl]: wjeżdża (ćwierć wejścia
  /// i koniec), po Odrzuć odjeżdża i w drodze nie słucha dotyku ani Entera.
  Future<void> wjazdIOdjazd(
      WidgetTester tester, AppServices services, AppStyle styl,
      {required bool telefon}) async {
    final w = _karty[styl]!;
    final start = telefon ? w.telefon : w.okno;
    final opis = '${styl.name}, ${telefon ? 'telefon' : 'okno'}';
    final karta = find.byKey(const ValueKey('h1'));
    final tytul = find.text(teksty.historyOfferTitle('Alicja'));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(nakladka(services, styl));
    expect(Theme.of(tester.element(find.byType(PromptOverlay))).platform,
        telefon ? TargetPlatform.android : TargetPlatform.windows,
        reason: opis);

    services.pendingHistory.value = [prosba('h1', 'Alicja')];
    await tester.pump();
    expect(widac(tester, tytul), 0, reason: '$opis: startuje niewidoczna');
    await tester.pump(w.wejscie ~/ 4);
    final cwierc = tester.getRect(karta);
    final widacCwierc = widac(tester, tytul);
    await tester.pump(w.wejscie - w.wejscie ~/ 4);
    final naMiejscu = tester.getRect(karta);
    expect(widac(tester, tytul), 1, reason: '$opis: po wejściu widać całą');
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getRect(karta), naMiejscu,
        reason: '$opis: po wejściu stoi na miejscu');

    final ruch = w.ruch.transform(0.25);
    expect(widacCwierc, inExclusiveRange(0, 1), reason: opis);
    expect(widacCwierc, closeTo(w.przenikanie.transform(0.25), 0.01),
        reason: '$opis: przenikanie');
    expect(cwierc.center.dy - naMiejscu.center.dy,
        closeTo(start.przesuniecie * (1 - ruch), 0.1),
        reason: '$opis: przesunięcie');
    expect(cwierc.width / naMiejscu.width,
        closeTo(start.skala + (1 - start.skala) * ruch, 0.001),
        reason: '$opis: skala');
    expect(cwierc.center.dx, closeTo(naMiejscu.center.dx, 0.01),
        reason: opis);

    var odpowiedzi = 0;
    void licz() => odpowiedzi++;
    services.pendingHistory.addListener(licz);
    final odrzuc = fokus(tester, karta, teksty.reject);
    expect(odrzuc.hasPrimaryFocus, isTrue, reason: '$opis: fokus na Odrzuć');
    final przyjmij =
        find.descendant(of: karta, matching: find.text(teksty.accept));

    await tester
        .tap(find.descendant(of: karta, matching: find.text(teksty.reject)));
    await tester.pump();
    expect(odpowiedzi, 1, reason: opis);
    expect(services.pendingHistory.value, isEmpty, reason: opis);
    // Od pierwszej klatki odjazdu karta nie słucha ani dotyku, ani Entera.
    expect(karta, findsOneWidget, reason: '$opis: karta odjeżdża');
    expect(odrzuc.hasFocus, isFalse, reason: opis);
    expect(odrzuc.canRequestFocus, isFalse, reason: opis);
    await tester.tap(przyjmij, warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(odpowiedzi, 1, reason: '$opis: odjeżdżająca karta nie odpowiada');

    await tester.pump(w.wyjscie ~/ 2);
    final polowa = tester.getRect(karta);
    final znika = w.znikanie.transform(0.5);
    expect(widac(tester, tytul), closeTo(1 - znika, 0.01),
        reason: '$opis: znikanie');
    expect(polowa.center.dy - naMiejscu.center.dy,
        closeTo(start.przesuniecie * znika, 0.1),
        reason: '$opis: przesunięcie przy odjeździe');
    expect(polowa.width / naMiejscu.width,
        closeTo(start.skala + (1 - start.skala) * (1 - znika), 0.001),
        reason: '$opis: skala przy odjeździe');
    await tester.tap(przyjmij, warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(odpowiedzi, 1, reason: '$opis: odjeżdżająca karta nie odpowiada');

    await tester.pump(
        w.wyjscie - w.wyjscie ~/ 2 - const Duration(milliseconds: 1));
    expect(karta, findsOneWidget, reason: '$opis: jeszcze odjeżdża');
    expect(widac(tester, tytul), greaterThan(0),
        reason: '$opis: jeszcze odjeżdża');
    await tester.pump(const Duration(milliseconds: 1));
    expect(widac(tester, tytul), 0,
        reason: '$opis: odjechała w ${w.wyjscie.inMilliseconds} ms');
    await tester.pump(_klatka);
    expect(karta, findsNothing, reason: '$opis: zeszła z drzewa');
    services.pendingHistory.removeListener(licz);
  }

  testWidgets('karta zgody na telefonie wjeżdża i odjeżdża w ruchu każdego '
      'stylu, a odjeżdżając nie słucha dotyku ani Entera', (tester) async {
    final services = await uruchom(tester);
    for (final styl in AppStyle.values) {
      await wjazdIOdjazd(tester, services, styl, telefon: true);
    }
    await sprzatnij(tester, services);
  });

  testWidgets('karta zgody w oknie na komputerze wjeżdża i odjeżdża w ruchu '
      'każdego stylu', (tester) async {
    final services = await uruchom(tester);
    for (final styl in AppStyle.values) {
      await wOknie(
          () => wjazdIOdjazd(tester, services, styl, telefon: false));
    }
    await sprzatnij(tester, services);
  });

  testWidgets('druga prośba w miejsce pierwszej: stara odjeżdża bez fokusu, '
      'nowa wjeżdża i bierze fokus, w każdym stylu', (tester) async {
    final services = await uruchom(tester);
    final pierwsza = find.byKey(const ValueKey('h1'));
    final druga = find.byKey(const ValueKey('h2'));
    final tytulPierwszej = find.text(teksty.historyOfferTitle('Alicja'));
    final tytulDrugiej = find.text(teksty.historyOfferTitle('Cezary'));
    for (final styl in AppStyle.values) {
      final w = _karty[styl]!;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(nakladka(services, styl));
      services.pendingHistory.value = [prosba('h1', 'Alicja')];
      await tester.pump();
      await tester.pump(w.wejscie + _klatka);
      final odrzucPierwsza = fokus(tester, pierwsza, teksty.reject);
      expect(odrzucPierwsza.hasPrimaryFocus, isTrue, reason: styl.name);

      services.pendingHistory.value = [prosba('h2', 'Cezary')];
      await tester.pump();
      // Fokus przychodzi klatkę po pokazaniu karty.
      await tester.pump();
      expect(pierwsza, findsOneWidget, reason: '${styl.name}: stara odjeżdża');
      expect(druga, findsOneWidget, reason: styl.name);
      expect(odrzucPierwsza.hasFocus, isFalse, reason: styl.name);
      expect(odrzucPierwsza.canRequestFocus, isFalse, reason: styl.name);
      final odrzucDrugiej = fokus(tester, druga, teksty.reject);
      expect(odrzucDrugiej.hasPrimaryFocus, isTrue,
          reason: '${styl.name}: fokus na nowej karcie');

      // Ćwierć wejścia nowej: stara już blednie, nowa się pojawia.
      final cwierc = w.wejscie ~/ 4;
      final wDrodzeStarej = cwierc.inMicroseconds / w.wyjscie.inMicroseconds;
      await tester.pump(cwierc);
      expect(widac(tester, tytulPierwszej),
          closeTo(1 - w.znikanie.transform(wDrodzeStarej), 0.01),
          reason: styl.name);
      expect(widac(tester, tytulDrugiej),
          closeTo(w.przenikanie.transform(0.25), 0.01),
          reason: styl.name);

      final dluzej = w.wejscie > w.wyjscie ? w.wejscie : w.wyjscie;
      await tester.pump(dluzej - cwierc + _klatka);
      expect(pierwsza, findsNothing, reason: styl.name);
      expect(widac(tester, tytulDrugiej), 1, reason: styl.name);
      expect(odrzucDrugiej.hasPrimaryFocus, isTrue, reason: styl.name);

      // Enter odpowiada nowej karcie.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(services.pendingHistory.value, isEmpty, reason: styl.name);
      await tester.pump();
      await tester.pump(w.wyjscie + _klatka);
      expect(druga, findsNothing, reason: styl.name);
    }
    await sprzatnij(tester, services);
  });

  testWidgets('przy „ogranicz animacje” karta w każdym stylu tylko się '
      'przenika przez 100 ms, bez przesunięcia i skali', (tester) async {
    final services = await uruchom(tester);
    final karta = find.byKey(const ValueKey('h1'));
    final tytul = find.text(teksty.historyOfferTitle('Alicja'));
    const polowa = Duration(milliseconds: 50);
    expect(ChattMotion.reducedDuration, polowa * 2);

    Future<void> sprawdz(AppStyle styl, String opis) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(nakladka(services, styl, bezAnimacji: true));
      services.pendingHistory.value = [prosba('h1', 'Alicja')];
      await tester.pump();
      await tester.pump(polowa);
      final wPolowie = tester.getRect(karta);
      expect(widac(tester, tytul), closeTo(0.5, 0.01),
          reason: '$opis: przenikanie liniowe');
      await tester.pump(polowa);
      expect(widac(tester, tytul), 1, reason: '$opis: weszła w 100 ms');
      expect(tester.getRect(karta), wPolowie,
          reason: '$opis: bez przesunięcia i skali');
      await tester.pump(_klatka);

      services.pendingHistory.value = const [];
      await tester.pump();
      await tester.pump(polowa);
      expect(widac(tester, tytul), closeTo(0.5, 0.01), reason: opis);
      expect(tester.getRect(karta), wPolowie,
          reason: '$opis: bez przesunięcia i skali');
      await tester.pump(polowa);
      expect(widac(tester, tytul), 0, reason: '$opis: odeszła w 100 ms');
      await tester.pump(_klatka);
      expect(karta, findsNothing, reason: opis);
    }

    for (final styl in AppStyle.values) {
      await sprawdz(styl, '${styl.name}, telefon');
      await wOknie(() => sprawdz(styl, '${styl.name}, okno'));
    }

    // Flaga z systemu włącza ten sam ruch: w każdej klatce wejścia i wyjścia
    // karta stoi na miejscu i tylko się przenika, przez pełne 100 ms. Zwykły
    // kontroler Flutter skróciłby przy tej fladze do 5% czasu; karty mają
    // kontrolery z zachowanym czasem. Bez ruchu „ogranicz animacje” karta
    // byłaby w połowie drogi przesunięta albo pomniejszona.
    final pol = ChattMotion.reducedDuration ~/ 2;
    const krok = Duration(milliseconds: 1);
    Future<void> zSystemu(AppStyle styl, String opis) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(nakladka(services, styl));
      services.pendingHistory.value = [prosba('h1', 'Alicja')];
      await tester.pump();
      await tester.pump(pol);
      final wDrodze = tester.getRect(karta);
      expect(widac(tester, tytul), closeTo(0.5, 0.01),
          reason: '$opis: w połowie przenikania');
      await tester.pump(pol + krok);
      expect(widac(tester, tytul), 1, reason: '$opis: weszła');
      expect(tester.getRect(karta), wDrodze,
          reason: '$opis: wejście bez przesunięcia i skali');

      services.pendingHistory.value = const [];
      await tester.pump();
      await tester.pump(pol);
      expect(widac(tester, tytul), closeTo(0.5, 0.01),
          reason: '$opis: w połowie wyjścia');
      expect(tester.getRect(karta), wDrodze,
          reason: '$opis: wyjście bez przesunięcia i skali');
      await tester.pump(pol + krok);
      await tester.pump();
      expect(karta, findsNothing, reason: '$opis: odeszła');
    }

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    for (final styl in AppStyle.values) {
      await zSystemu(styl, '${styl.name}, telefon, system');
      await wOknie(() => zSystemu(styl, '${styl.name}, okno, system'));
    }
    await sprzatnij(tester, services);
  });

  testWidgets('każde miejsce na nakładce (parowanie, plik, historia, '
      'klawiatura) zmienia karty w ruchu stylu', (tester) async {
    final services = await uruchom(tester);
    final w = _karty[AppStyle.cisza]!;
    await tester.pumpWidget(nakladka(services, AppStyle.cisza));
    services.pendingPairings.value = const [
      PendingPairing(peerGuid: 'guid-alicja', peerName: 'Alicja', code: '123456'),
    ];
    services.pendingOffers.value = const [
      PendingFileOffer(
        messageGuid: 'plik-1',
        peerName: 'Alicja',
        fileName: 'umowa.pdf',
        fileSize: 1024,
        resumeFrom: 0,
        conversationId: 1,
      ),
    ];
    services.pendingHistory.value = [prosba('h1', 'Alicja')];
    services.pendingRemoteInput.value = const [
      PendingRemoteInput(
          id: 'guid-alicja|k1', peerGuid: 'guid-alicja', peerName: 'Alicja'),
    ];
    final tytuly = [
      find.text(teksty.pairRequest('Alicja')),
      find.text(teksty.fileOfferTitle('Alicja')),
      find.text(teksty.historyOfferTitle('Alicja')),
      find.text(teksty.remoteInputRequestTitle('Alicja')),
    ];
    await tester.pump();
    for (final tytul in tytuly) {
      expect(find.ancestor(of: tytul, matching: find.byType(CardSwitcher)),
          findsOneWidget);
      expect(widac(tester, tytul), 0);
    }
    await tester.pump(w.wejscie);
    for (final tytul in tytuly) {
      expect(widac(tester, tytul), 1);
    }

    // Nowy kod od tego samego urządzenia: nowa karta w miejsce starej.
    services.pendingPairings.value = const [
      PendingPairing(peerGuid: 'guid-alicja', peerName: 'Alicja', code: '654321'),
    ];
    await tester.pump();
    expect(find.text('1 2 3 4 5 6'), findsOneWidget, reason: 'stara odjeżdża');
    expect(find.text('6 5 4 3 2 1'), findsOneWidget);
    await tester.pump(w.wejscie);
    expect(find.text('1 2 3 4 5 6'), findsNothing);
    expect(widac(tester, find.text('6 5 4 3 2 1')), 1);

    services.pendingPairings.value = const [];
    services.pendingOffers.value = const [];
    services.pendingHistory.value = const [];
    services.pendingRemoteInput.value = const [];
    await tester.pump();
    await tester.pump(w.wyjscie - const Duration(milliseconds: 1));
    for (final tytul in tytuly) {
      expect(tytul, findsOneWidget, reason: 'jeszcze odjeżdża');
      expect(widac(tester, tytul), greaterThan(0), reason: 'jeszcze odjeżdża');
    }
    await tester.pump(const Duration(milliseconds: 1));
    for (final tytul in tytuly) {
      expect(widac(tester, tytul), 0, reason: 'odjechała w czasie stylu');
    }
    await tester.pump(_klatka);
    for (final tytul in tytuly) {
      expect(tytul, findsNothing);
    }

    await sprzatnij(tester, services);
  });

  testWidgets('karta parowania po zgodzie odjeżdża tak, jak była '
      '(„Czekam…”), a komunikat o parowaniu i tak przychodzi', (tester) async {
    final services = await uruchom(tester);
    final w = _karty[AppStyle.cisza]!;
    await tester.runAsync(() => services.db.upsertPeer(
          guid: 'guid-alicja',
          name: 'Alicja',
          welcomeMessage: '',
          host: '',
          port: 0,
        ));
    chattToasts.clear();
    addTearDown(chattToasts.clear);
    await tester.pumpWidget(nakladka(services, AppStyle.cisza));
    // Po zeskanowaniu wystarczy zgoda tej strony: karta schodzi z listy
    // w chwili odpowiedzi, bez sieci.
    services.pendingPairings.value = const [
      PendingPairing(
        peerGuid: 'guid-alicja',
        peerName: 'Alicja',
        code: '123456',
        fromScan: true,
      ),
    ];
    await tester.pump();
    await tester.pump(w.wejscie + _klatka);
    final karta = find.byKey(const ValueKey(('guid-alicja', '123456')));
    expect(karta, findsOneWidget);
    final rozmiar = tester.getSize(karta);

    await tester.tap(find.text(teksty.pairScannedConfirm));
    await tester.pump();
    expect(find.text(teksty.pairChecking), findsOneWidget);
    // Zgoda zapisuje się w bazie w prawdziwym czasie.
    for (var i = 0; i < 100 && services.pendingPairings.value.isNotEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(services.pendingPairings.value, isEmpty);
    await tester.pump();

    expect(karta, findsOneWidget, reason: 'karta odjeżdża');
    expect(find.text(teksty.pairChecking), findsOneWidget,
        reason: 'w drodze napis się nie zmienia');
    expect(find.text(teksty.pairScannedConfirm), findsNothing);
    expect(tester.getSize(karta), rozmiar, reason: 'w drodze nie rośnie');
    expect(chattToasts.value.map((t) => t.text),
        contains(teksty.pairedWith('Alicja')));

    await tester.pump(w.wyjscie + _klatka);
    expect(karta, findsNothing);
    await sprzatnij(tester, services);
  });

  testWidgets('okno udostępniania historii wjeżdża jak karta zgody, na '
      'zasłonie stylu', (tester) async {
    final services = await uruchom(tester);
    final (id, alicja) = await rozmowa(tester, services);
    final tytul = find.text(teksty.historyShareTitle);
    for (final styl in AppStyle.values) {
      final w = _karty[styl]!;
      final motyw = chattTheme(styl, Brightness.light);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(aplikacja(services,
          theme: motyw,
          ekran: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShareHistoryDialog(context,
                    services: services, peer: alicja, conversationId: id),
                child: const Text('otwórz'),
              ),
            ),
          )));
      await tester.tap(find.text('otwórz'));
      await tester.pump();
      final trasa = ModalRoute.of(tester.element(tytul))!;
      expect(trasa, isA<ChattDialogRoute<Object?>>(), reason: styl.name);
      expect(trasa.transitionDuration, w.wejscie, reason: styl.name);
      expect(trasa.reverseTransitionDuration, w.wyjscie, reason: styl.name);
      expect(trasa.barrierColor, motyw.colorScheme.scrim,
          reason: '${styl.name}: zasłona stylu');
      expect(widac(tester, tytul), 0, reason: styl.name);
      await tester.pump(w.wejscie ~/ 4);
      expect(widac(tester, tytul), closeTo(w.przenikanie.transform(0.25), 0.01),
          reason: styl.name);
      await tester.pump(w.wejscie - w.wejscie ~/ 4);
      expect(widac(tester, tytul), 1, reason: styl.name);
      // Podgląd liczy się w prawdziwym czasie.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();

      await tester.tap(find.text(teksty.cancel));
      await tester.pump();
      await tester.pump(w.wyjscie - const Duration(milliseconds: 1));
      expect(tytul, findsOneWidget, reason: '${styl.name}: jeszcze odjeżdża');
      await tester.pump(const Duration(milliseconds: 1));
      expect(widac(tester, tytul), 0,
          reason: '${styl.name}: zamknięte w ${w.wyjscie.inMilliseconds} ms');
      await tester.pump(_klatka);
      expect(tytul, findsNothing, reason: styl.name);
    }
    await sprzatnij(tester, services);
  });

  testWidgets('pasek historii przechodzi między próbkami w ruchu stylu, '
      'w Precyzji i przy „ogranicz animacje” wprost za próbkami',
      (tester) async {
    final services = await uruchom(tester);
    const miedzyProbkami = {
      AppStyle.cisza: (czas: Duration(milliseconds: 400), krzywa: _cisza),
      AppStyle.precyzja: (czas: Duration.zero, krzywa: Curves.linear),
      AppStyle.cieplo: (czas: Duration(milliseconds: 250), krzywa: Curves.linear),
    };
    HistoryTransfer probka(int zrobione) => HistoryTransfer(
          peerName: 'Alicja',
          conversationId: 7,
          messagesTotal: 4,
          messagesDone: zrobione,
          filesTotal: 0,
        );
    double pasek() => tester
        .widget<LinearProgressIndicator>(find.descendant(
            of: find.byType(HistoryProgressBar),
            matching: find.byType(LinearProgressIndicator)))
        .value!;

    Future<void> postaw(AppStyle styl) async {
      services.outgoingHistory.value = null;
      services.incomingHistory.value = null;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(aplikacja(services,
          theme: chattTheme(styl, Brightness.light),
          ekran: Scaffold(
            body: HistoryProgressBar(services: services, conversationId: 7),
          )));
    }

    Future<void> pokaz(AppStyle styl) async {
      await postaw(styl);
      services.outgoingHistory.value = probka(1);
      await tester.pump();
      expect(pasek(), 0.25, reason: '${styl.name}: pierwsza próbka od razu');
      services.outgoingHistory.value = probka(3);
      await tester.pump();
    }

    for (final MapEntry(key: styl, value: p) in miedzyProbkami.entries) {
      await pokaz(styl);
      if (p.czas == Duration.zero) {
        expect(pasek(), 0.75, reason: '${styl.name}: wprost za próbką');
        continue;
      }
      expect(pasek(), 0.25, reason: styl.name);
      await tester.pump(p.czas ~/ 2);
      expect(pasek(), closeTo(0.25 + 0.5 * p.krzywa.transform(0.5), 0.001),
          reason: '${styl.name}: w połowie drogi');
      await tester.pump(p.czas - p.czas ~/ 2);
      expect(pasek(), 0.75, reason: '${styl.name}: na miejscu po ${p.czas}');

      // Nowe przywracanie w miejsce skończonego (pasek „Przywrócono” czeka
      // na Zamknij): pasek startuje od pierwszej próbki nowego i dalej
      // idzie w ruchu stylu.
      await postaw(styl);
      services.incomingHistory.value = probka(4).copyWith(finished: true);
      await tester.pump();
      expect(pasek(), 1.0, reason: styl.name);
      services.incomingHistory.value = probka(0);
      await tester.pump();
      expect(pasek(), 0.0, reason: '${styl.name}: nowe przywracanie od zera');
      services.incomingHistory.value = probka(2);
      await tester.pump();
      await tester.pump(p.czas ~/ 2);
      expect(pasek(), closeTo(0.5 * p.krzywa.transform(0.5), 0.001),
          reason: '${styl.name}: nowe w ruchu stylu');
      await tester.pump(p.czas - p.czas ~/ 2);
      expect(pasek(), 0.5, reason: styl.name);

      // Inne liczby to też następne przesłanie, nawet gdy pasek rośnie.
      services.incomingHistory.value = const HistoryTransfer(
        peerName: 'Alicja',
        conversationId: 7,
        messagesTotal: 8,
        messagesDone: 6,
        filesTotal: 0,
      );
      await tester.pump();
      expect(pasek(), 0.75, reason: '${styl.name}: inne liczby od razu');
    }

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    for (final styl in AppStyle.values) {
      await pokaz(styl);
      expect(pasek(), 0.75,
          reason: '${styl.name}: ogranicz animacje, wprost za próbką');
    }

    services.outgoingHistory.value = null;
    services.incomingHistory.value = null;
    await sprzatnij(tester, services);
  });
}
