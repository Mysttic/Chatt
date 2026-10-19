import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
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
import 'package:chatt/ui/screens/chat_screen.dart';
import 'package:chatt/ui/widgets/history_ui.dart';
import 'package:chatt/ui/widgets/prompt_overlay.dart';

/// Udostępnianie historii na ekranie: znacznik przywróconych dymków,
/// separatory dat, wpis pliku bez treści, menu rozmowy, karty zgody i paski
/// postępu.
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
          {Widget? ekran, TransitionBuilder? builder}) =>
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
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
}
