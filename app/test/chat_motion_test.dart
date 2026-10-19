import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/ui/screens/chat_screen.dart';
import 'package:chatt/ui/styles.dart';
import 'package:chatt/ui/widgets/motion.dart';
import 'package:chatt/ui/widgets/security_sheet.dart';

/// Ruch w rozmowie (issue #54): nowy dymek wjeżdża w czasie stylu, a już
/// pokazane stoją na miejscu; pasek odbieranego pliku idzie między próbkami
/// po swojemu; panel bezpieczeństwa to na telefonie arkusz od dołu, w oknie
/// okno na środku.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final teksty = lookupAppLocalizations(const Locale('en'));

  late Directory katalog;

  setUp(() => katalog = Directory.systemTemp.createTempSync('chatt_ruch_'));
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

  /// Aplikacja w stylu [styl]; [ogranicz]: „ogranicz animacje” w systemie.
  Widget aplikacja(AppServices services,
          {required AppStyle styl,
          required Widget ekran,
          bool ogranicz = false}) =>
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          theme: chattTheme(styl, Brightness.light),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: ogranicz
              ? (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: true),
                    child: child!,
                  )
              : null,
          home: ekran,
        ),
      );

  /// Rozmowa z Alicją z wczorajszymi wiadomościami (najstarsza to
  /// „wczorajsza”): pierwsza dzisiejsza dostaje nad sobą datę.
  Future<(int, Peer)> rozmowa(WidgetTester tester, AppServices s,
          {int ile = 1}) async =>
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
        final wczoraj = DateTime(teraz.year, teraz.month, teraz.day - 1, 12);
        for (var i = 0; i < ile; i++) {
          await s.db.insertIncoming(
            conversationId: id,
            messageGuid: 'm-wczoraj-$i',
            body: i == 0 ? 'wczorajsza' : 'wczorajsza $i',
            sentAt: wczoraj.add(Duration(minutes: i)),
          );
        }
        return (id, (await s.db.peerByGuid('guid-alicja'))!);
      }))!;

  /// Czeka, aż [co] pojawi się na ekranie. Zegar testu przy tym stoi, więc
  /// wejście dymka zaczyna się w klatce, w której dymek się zbudował.
  Future<void> czekajNa(WidgetTester tester, Finder co) async {
    for (var i = 0; i < 50 && co.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(co, findsOneWidget);
  }

  /// Zapis do bazy przy otwartym ekranie. Ekran czyta i zapisuje bazę
  /// w fałszywym czasie testu (oznaczanie przeczytanych), zapis idzie
  /// w prawdziwym, a oba stoją w kolejce do tej samej bazy: na zmianę dajemy
  /// pochodzić jednemu i drugiemu, aż zapis się skończy. Zegar testu stoi.
  Future<T?> zapisz<T>(WidgetTester tester, Future<T> Function() zapis) async {
    late Future<T> wynik;
    var gotowe = false;
    await tester.runAsync(() async {
      wynik = zapis();
      wynik.then((_) => gotowe = true, onError: (_) => gotowe = true);
    });
    for (var i = 0; i < 100 && !gotowe; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(gotowe, isTrue, reason: 'zapis do bazy nie doszedł');
    return tester.runAsync(() => wynik);
  }

  Future<void> nadejdzie(
      WidgetTester tester, AppServices s, int id, String tresc) async {
    await zapisz(
        tester,
        () => s.db.insertIncoming(
              conversationId: id,
              messageGuid: 'm-$tresc',
              body: tresc,
              sentAt: DateTime.now(),
            ));
    await czekajNa(tester, find.text(tresc));
  }

  /// Klatka po końcu przejścia: kontroler kończy się dopiero po swoim czasie.
  const klatka = Duration(milliseconds: 16);

  Widget ekranRozmowy(int id, Peer alicja) =>
      ChatScreen(conversationId: id, peer: alicja);

  Finder wejscieDymka(String tresc) => find.ancestor(
      of: find.text(tresc), matching: find.byType(MotionTransition));

  // Wewnątrz MotionTransition: Opacity, przesunięcie, skala.
  double przezroczystosc(WidgetTester tester, Finder wejscie) => tester
      .widget<Opacity>(
          find.descendant(of: wejscie, matching: find.byType(Opacity)).first)
      .opacity;

  double przesuniecie(WidgetTester tester, Finder wejscie) => tester
      .widget<Transform>(
          find.descendant(of: wejscie, matching: find.byType(Transform)).first)
      .transform
      .getTranslation()
      .y;

  double skala(WidgetTester tester, Finder wejscie) => tester
      .widget<Transform>(
          find.descendant(of: wejscie, matching: find.byType(Transform)).at(1))
      .transform
      .entry(0, 0);

  double pasek(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
      .value!;

  for (final styl in AppStyle.values) {
    final m = chattMotion(styl);

    testWidgets(
        '${styl.name}: nowy dymek wjeżdża w górę w czasie stylu, pokazane '
        'stoją, zmiana statusu wejścia nie powtarza', (tester) async {
      // Wartości z tabeli w issue #54.
      final (czas, krzywa, wjazd) = switch (styl) {
        AppStyle.cisza => (220, const Cubic(0.2, 0, 0, 1), 8.0),
        AppStyle.precyzja => (140, const Cubic(0.2, 0, 0, 1), 6.0),
        AppStyle.cieplo => (200, Curves.easeOut, 8.0),
      };
      expect(m.bubble, Duration(milliseconds: czas));
      expect(m.bubbleCurve, krzywa);
      expect(m.bubbleShift, wjazd);

      final services = await uruchom(tester);
      final (id, alicja) = await rozmowa(tester, services);
      await tester.pumpWidget(
          aplikacja(services, styl: styl, ekran: ekranRozmowy(id, alicja)));
      await czekajNa(tester, find.text('wczorajsza'));
      expect(wejscieDymka('wczorajsza'), findsNothing,
          reason: 'była na liście przy otwarciu');

      await nadejdzie(tester, services, id, 'dzień dobry');
      final wejscie = wejscieDymka('dzień dobry');
      expect(wejscie, findsOneWidget);
      final przejscie = tester.widget<MotionTransition>(wejscie);
      final kontroler = przejscie.animation as AnimationController;
      expect(kontroler.duration, m.bubble);
      expect(przejscie.curve, m.bubbleCurve);
      expect(przejscie.fadeCurve, m.bubbleCurve);
      expect(przejscie.shift, m.bubbleShift);
      expect(przejscie.scale, 1);
      expect(
          // Precyzja pisze datę wersalikami.
          find.descendant(
              of: wejscie,
              matching: find.textContaining(
                  RegExp('^${teksty.dateToday}\$', caseSensitive: false))),
          findsOneWidget,
          reason: 'data wjeżdża razem z pierwszym dymkiem dnia');
      expect(przezroczystosc(tester, wejscie), 0);
      expect(przesuniecie(tester, wejscie), m.bubbleShift);

      await tester.pump(m.bubble ~/ 2);
      expect(kontroler.value, closeTo(0.5, 0.01));
      final polowa = krzywa.transform(kontroler.value);
      expect(przezroczystosc(tester, wejscie), closeTo(polowa, 0.001));
      expect(przesuniecie(tester, wejscie),
          closeTo(wjazd * (1 - polowa), 0.001));
      expect(przesuniecie(tester, wejscie), greaterThan(0),
          reason: 'lista stoi do góry nogami: dymek przychodzi z dołu');

      await tester.pump(m.bubble - m.bubble ~/ 2);
      expect(przezroczystosc(tester, wejscie), 1);
      expect(przesuniecie(tester, wejscie), 0);
      await tester.pump(klatka);
      expect(kontroler.isCompleted, isTrue);
      expect(wejscieDymka('wczorajsza'), findsNothing);

      // Własna wiadomość wysłana przy otwartej rozmowie też wjeżdża; zmiana
      // statusu (czeka, doręczona) jej nie powtarza.
      final mojaId = (await zapisz(
          tester,
          () => services.db.insertOutgoing(
                conversationId: id,
                messageGuid: 'm-moja',
                body: 'moja',
              )))!;
      await czekajNa(tester, find.text('moja'));
      final mojeWejscie = wejscieDymka('moja');
      final mojKontroler = tester.widget<MotionTransition>(mojeWejscie).animation
          as AnimationController;
      expect(mojKontroler.duration, m.bubble);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      await tester.pump(m.bubble + klatka);
      expect(mojKontroler.isCompleted, isTrue);

      await zapisz(tester,
          () => services.db.setMessageStatus(mojaId, MessageStatus.delivered));
      await czekajNa(tester, find.byIcon(Icons.done_all));
      expect(tester.widget<MotionTransition>(mojeWejscie).animation,
          same(mojKontroler),
          reason: 'ten sam wiersz, wejście się nie zaczyna od nowa');
      expect(mojKontroler.isCompleted, isTrue);
      expect(przezroczystosc(tester, mojeWejscie), 1);
      expect(przesuniecie(tester, mojeWejscie), 0);
      expect(wejscieDymka('wczorajsza'), findsNothing);

      await sprzatnij(tester, services);
    });

    testWidgets(
        '${styl.name}: pasek odbieranego pliku idzie między próbkami w ruchu '
        'stylu', (tester) async {
      final (czas, krzywa) = switch (styl) {
        AppStyle.cisza =>
          (const Duration(milliseconds: 400), const Cubic(0.2, 0, 0, 1)),
        AppStyle.precyzja => (Duration.zero, Curves.linear),
        AppStyle.cieplo => (const Duration(milliseconds: 250), Curves.linear),
      };
      expect(m.progress, czas);
      expect(m.progressCurve, krzywa);

      final services = await uruchom(tester);
      final (id, alicja) = await rozmowa(tester, services);
      await tester.pumpWidget(
          aplikacja(services, styl: styl, ekran: ekranRozmowy(id, alicja)));
      await czekajNa(tester, find.text('wczorajsza'));

      final odbior = IncomingTransfer(
        messageGuid: 'm-film',
        conversationId: id,
        peerName: 'Alicja',
        fileName: 'film.mp4',
        fileSize: 1000,
        received: 0,
      );
      services.incomingTransfers.value = {'m-film': odbior};
      await tester.pump();
      expect(find.text(teksty.receivingFile('film.mp4')), findsOneWidget);
      expect(pasek(tester), 0, reason: 'pierwsza próbka od razu');

      odbior.receivedBytes.value = 500;
      await tester.pump();
      if (czas == Duration.zero) {
        expect(pasek(tester), 0.5, reason: 'Precyzja idzie wprost za próbkami');
        odbior.receivedBytes.value = 900;
        await tester.pump();
        expect(pasek(tester), 0.9);
      } else {
        expect(pasek(tester), 0);
        await tester.pump(czas ~/ 2);
        final polowa = pasek(tester);
        expect(polowa, closeTo(0.5 * krzywa.transform(0.5), 0.001));
        if (styl == AppStyle.cisza) {
          expect(polowa, greaterThan(0.25),
              reason: 'Cisza zwalnia pod koniec, Ciepło idzie równo');
        }

        // Kolejna próbka w trakcie ruchu: pasek rusza bez skoku z miejsca,
        // w którym jest, i dochodzi do niej w czasie stylu.
        odbior.receivedBytes.value = 900;
        await tester.pump();
        expect(pasek(tester), closeTo(polowa, 0.001));
        await tester.pump(czas ~/ 2);
        expect(pasek(tester), allOf(greaterThan(polowa), lessThan(0.9)));
        await tester.pump(czas - czas ~/ 2);
        expect(pasek(tester), closeTo(0.9, 0.001));

        // Próbka po spoczynku znów idzie krzywą stylu.
        await tester.pump(klatka);
        odbior.receivedBytes.value = 1000;
        await tester.pump();
        await tester.pump(czas ~/ 2);
        expect(pasek(tester), closeTo(0.9 + 0.1 * krzywa.transform(0.5), 0.001));
        await tester.pump(czas - czas ~/ 2);
        expect(pasek(tester), closeTo(1, 0.001));
      }

      services.incomingTransfers.value = const {};
      await sprzatnij(tester, services);
    });

    // Prawdziwy odbiór daje próbkę co kawałek, czyli co klatkę.
    testWidgets(
        '${styl.name}: próbka co klatkę, pasek zostaje w tyle najwyżej o czas '
        'stylu', (tester) async {
      final services = await uruchom(tester);
      final (id, alicja) = await rozmowa(tester, services);
      await tester.pumpWidget(
          aplikacja(services, styl: styl, ekran: ekranRozmowy(id, alicja)));
      await czekajNa(tester, find.text('wczorajsza'));

      // Plik idzie sekundę: 62 klatki po 10 bajtów.
      const klatek = 62;
      final odbior = IncomingTransfer(
        messageGuid: 'm-film',
        conversationId: id,
        peerName: 'Alicja',
        fileName: 'film.mp4',
        fileSize: klatek * 10,
        received: 0,
      );
      services.incomingTransfers.value = {'m-film': odbior};
      await tester.pump();
      // W czasie stylu pasek przejdzie tyle, ile plik w tym samym czasie.
      final granica = m.progress.inMicroseconds / klatka.inMicroseconds / klatek;
      for (var i = 1; i <= klatek; i++) {
        odbior.receivedBytes.value = i * 10;
        await tester.pump(klatka);
        expect(i / klatek - pasek(tester), lessThanOrEqualTo(granica + 0.001),
            reason: 'klatka $i');
      }

      services.incomingTransfers.value = const {};
      await sprzatnij(tester, services);
    });

    testWidgets(
        '${styl.name}: dwa pliki naraz, po końcu pierwszego drugi pasek stoi '
        'przy swojej próbce', (tester) async {
      final services = await uruchom(tester);
      final (id, alicja) = await rozmowa(tester, services);
      await tester.pumpWidget(
          aplikacja(services, styl: styl, ekran: ekranRozmowy(id, alicja)));
      await czekajNa(tester, find.text('wczorajsza'));

      IncomingTransfer plik(String nazwa, int doszlo) => IncomingTransfer(
            messageGuid: 'm-$nazwa',
            conversationId: id,
            peerName: 'Alicja',
            fileName: nazwa,
            fileSize: 1000,
            received: doszlo,
          );
      List<double?> paski() => [
            for (final p in tester.widgetList<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator)))
              p.value,
          ];
      final duzy = plik('duzy.mp4', 1000);
      final maly = plik('maly.png', 100);
      services.incomingTransfers.value = {
        duzy.messageGuid: duzy,
        maly.messageGuid: maly,
      };
      await tester.pump();
      expect(paski(), [1.0, 0.1]);

      services.incomingTransfers.value = {maly.messageGuid: maly};
      await tester.pump();
      expect(find.text(teksty.receivingFile('duzy.mp4')), findsNothing);
      expect(paski(), [0.1], reason: 'bez przejęcia paska po pierwszym pliku');
      await tester.pump(m.progress ~/ 2);
      expect(paski(), [0.1]);

      services.incomingTransfers.value = const {};
      await sprzatnij(tester, services);
    });

    testWidgets(
        '${styl.name}: ograniczone animacje, nowy dymek tylko przenika '
        'w 100 ms, pasek idzie wprost za próbkami', (tester) async {
      final services = await uruchom(tester);
      final (id, alicja) = await rozmowa(tester, services);
      await tester.pumpWidget(aplikacja(services,
          styl: styl, ogranicz: true, ekran: ekranRozmowy(id, alicja)));
      await czekajNa(tester, find.text('wczorajsza'));
      expect(wejscieDymka('wczorajsza'), findsNothing);

      await nadejdzie(tester, services, id, 'po cichu');
      final wejscie = wejscieDymka('po cichu');
      final przejscie = tester.widget<MotionTransition>(wejscie);
      final kontroler = przejscie.animation as AnimationController;
      expect(kontroler.duration, const Duration(milliseconds: 100));
      expect(przejscie.shift, 0);
      expect(przejscie.curve, Curves.linear);
      await tester.pump(const Duration(milliseconds: 50));
      expect(przezroczystosc(tester, wejscie), closeTo(0.5, 0.01));
      expect(przesuniecie(tester, wejscie), 0);
      await tester.pump(const Duration(milliseconds: 50) + klatka);
      expect(kontroler.isCompleted, isTrue);
      expect(przezroczystosc(tester, wejscie), 1);

      final odbior = IncomingTransfer(
        messageGuid: 'm-film',
        conversationId: id,
        peerName: 'Alicja',
        fileName: 'film.mp4',
        fileSize: 1000,
        received: 0,
      );
      services.incomingTransfers.value = {'m-film': odbior};
      await tester.pump();
      odbior.receivedBytes.value = 500;
      await tester.pump();
      expect(pasek(tester), 0.5);

      services.incomingTransfers.value = const {};
      await sprzatnij(tester, services);
    });
  }

  testWidgets(
      'przywrócona historia, wiadomość w trakcie szukania i ponowne '
      'otwarcie rozmowy stoją od razu na miejscu', (tester) async {
    final services = await uruchom(tester);
    final (id, alicja) = await rozmowa(tester, services);
    // Szerokie okno buduje ekran rozmowy od nowa przy każdym wyborze
    // (ValueKey), tu tak samo.
    final klucz = ValueNotifier(0);
    addTearDown(klucz.dispose);
    await tester.pumpWidget(aplikacja(services,
        styl: AppStyle.cisza,
        ekran: ValueListenableBuilder<int>(
          valueListenable: klucz,
          builder: (_, k, _) => ChatScreen(
              key: ValueKey(k), conversationId: id, peer: alicja),
        )));
    await czekajNa(tester, find.text('wczorajsza'));

    // Przywracanie wpisuje wiele wierszy naraz.
    final teraz = DateTime.now();
    await zapisz(
        tester,
        () => services.db.importHistory(
              conversationId: id,
              restoredAt: teraz,
              notAfter: teraz.add(const Duration(minutes: 10)),
              items: [
                for (var i = 0; i < 3; i++)
                  RestoredMessage(
                    messageGuid: 'm-przywrocona-$i',
                    direction: MessageDirection.incoming,
                    sentAt: teraz.subtract(Duration(days: 3, minutes: 3 - i)),
                    body: 'przywrócona $i',
                  ),
              ],
            ));
    await czekajNa(tester, find.text('przywrócona 0'));
    for (var i = 0; i < 3; i++) {
      expect(find.text('przywrócona $i'), findsOneWidget);
      expect(wejscieDymka('przywrócona $i'), findsNothing,
          reason: 'przywrócona historia nie wjeżdża');
    }

    // Szukanie filtruje listę: to, co przyjdzie w trakcie, nie wjeżdża.
    await tester.tap(find.byTooltip(teksty.historyMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text(teksty.searchTooltip));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AppBar), matching: find.byType(TextField)),
        'szukam');
    await tester.pump();
    await nadejdzie(tester, services, id, 'szukam dalej');
    expect(wejscieDymka('szukam dalej'), findsNothing);
    expect(find.text('wczorajsza'), findsNothing, reason: 'nie pasuje');

    await tester.tap(find.byTooltip(teksty.close));
    await tester.pumpAndSettle();
    expect(find.text('wczorajsza'), findsOneWidget);
    expect(find.byType(MotionTransition), findsNothing,
        reason: 'po zamknięciu szukania nic nie wjeżdża');

    // Po szukaniu nowa znów wjeżdża.
    await nadejdzie(tester, services, id, 'po szukaniu');
    expect(wejscieDymka('po szukaniu'), findsOneWidget);
    await tester.pump(chattMotion(AppStyle.cisza).bubble);

    // Ekran zbudowany od nowa: wszystko było już widać.
    klucz.value++;
    await tester.pump();
    await czekajNa(tester, find.text('po szukaniu'));
    expect(find.byType(MotionTransition), findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets('dymek, który już wjechał, po przewinięciu wraca bez wejścia',
      (tester) async {
    final services = await uruchom(tester);
    final (id, alicja) = await rozmowa(tester, services, ile: 60);
    await tester.pumpWidget(aplikacja(services,
        styl: AppStyle.cisza, ekran: ekranRozmowy(id, alicja)));
    await czekajNa(tester, find.text('wczorajsza 59'));

    await nadejdzie(tester, services, id, 'najnowsza');
    expect(wejscieDymka('najnowsza'), findsOneWidget);
    await tester.pump(chattMotion(AppStyle.cisza).bubble);

    final lista = tester.state<ScrollableState>(find
        .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
        .first);
    lista.position.jumpTo(lista.position.maxScrollExtent);
    await tester.pump();
    expect(find.text('najnowsza', skipOffstage: false), findsNothing,
        reason: 'wiersz daleko poza listą nie istnieje');

    lista.position.jumpTo(0);
    await tester.pump();
    expect(find.text('najnowsza'), findsOneWidget);
    expect(wejscieDymka('najnowsza'), findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets(
      'nowa wiadomość w trakcie wejścia poprzedniej: poprzednia jedzie dalej '
      'w swoim wierszu, nowa ma własne wejście', (tester) async {
    final m = chattMotion(AppStyle.cisza);
    final services = await uruchom(tester);
    final (id, alicja) = await rozmowa(tester, services);
    await tester.pumpWidget(aplikacja(services,
        styl: AppStyle.cisza, ekran: ekranRozmowy(id, alicja)));
    await czekajNa(tester, find.text('wczorajsza'));

    await nadejdzie(tester, services, id, 'pierwsza');
    final kontroler =
        tester.widget<MotionTransition>(wejscieDymka('pierwsza')).animation
            as AnimationController;
    await tester.pump(m.bubble ~/ 2);
    final wPolowie = kontroler.value;
    expect(wPolowie, closeTo(0.5, 0.01));
    final wjazd = przesuniecie(tester, wejscieDymka('pierwsza'));
    expect(wjazd, greaterThan(0));

    // Druga staje na dole listy (indeks 0) i przesuwa pierwszą o jeden.
    await nadejdzie(tester, services, id, 'druga');
    expect(wejscieDymka('pierwsza'), findsOneWidget,
        reason: 'wejście pierwszej trwa dalej');
    expect(tester.widget<MotionTransition>(wejscieDymka('pierwsza')).animation,
        same(kontroler),
        reason: 'wiersz został przy swojej wiadomości');
    expect(kontroler.value, closeTo(wPolowie, 0.001));
    expect(przesuniecie(tester, wejscieDymka('pierwsza')), closeTo(wjazd, 0.001));
    expect(
        find.descendant(
            of: wejscieDymka('pierwsza'),
            matching: find.textContaining(
                RegExp('^${teksty.dateToday}\$', caseSensitive: false))),
        findsOneWidget,
        reason: 'data zostaje nad pierwszym dymkiem dnia');

    final drugi = tester.widget<MotionTransition>(wejscieDymka('druga')).animation
        as AnimationController;
    expect(drugi, isNot(same(kontroler)));
    expect(drugi.value, 0);
    expect(przezroczystosc(tester, wejscieDymka('druga')), 0);

    await tester.pump(m.bubble - m.bubble ~/ 2 + klatka);
    expect(kontroler.isCompleted, isTrue);
    expect(drugi.isAnimating, isTrue);
    await tester.pump(m.bubble);
    expect(drugi.isCompleted, isTrue);
    expect(przesuniecie(tester, wejscieDymka('pierwsza')), 0);
    expect(przesuniecie(tester, wejscieDymka('druga')), 0);

    await sprzatnij(tester, services);
  });

  Future<void> otworzPanel(WidgetTester tester, AppServices s,
      {required AppStyle styl, bool ogranicz = false}) async {
    final alicja = (await tester.runAsync(() async {
      await s.db.upsertPeer(
        guid: 'guid-alicja',
        name: 'Alicja',
        welcomeMessage: '',
        host: '',
        port: 0,
      );
      return s.db.peerByGuid('guid-alicja');
    }))!;
    await tester.pumpWidget(aplikacja(
      s,
      styl: styl,
      ogranicz: ogranicz,
      ekran: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showSecuritySheet(
                context,
                peer: alicja,
                onPair: () {},
                onScan: () {},
              ),
              child: const Text('panel'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('panel'));
    await tester.pump();
  }

  ModalRoute<Object?> trasaPanelu(WidgetTester tester) =>
      ModalRoute.of(tester.element(find.text(teksty.fingerprintMine)))!;

  Size ekran(WidgetTester tester) =>
      tester.view.physicalSize / tester.view.devicePixelRatio;

  for (final styl in AppStyle.values) {
    final m = chattMotion(styl);
    final motyw = chattTheme(styl, Brightness.light);
    final zaslona = motyw.colorScheme.scrim;

    testWidgets(
        '${styl.name}: panel bezpieczeństwa na telefonie to arkusz od dołu '
        'w czasie stylu', (tester) async {
      final services = await uruchom(tester);
      await otworzPanel(tester, services, styl: styl);

      final trasa = trasaPanelu(tester);
      expect(trasa, isA<ModalBottomSheetRoute<void>>());
      final arkusz = trasa as ModalBottomSheetRoute<void>;
      expect(arkusz.transitionDuration, m.panelIn);
      expect(arkusz.reverseTransitionDuration, m.panelOut);
      expect(arkusz.sheetAnimationStyle?.curve, m.enter);
      expect(
          arkusz.sheetAnimationStyle?.reverseCurve,
          isA<FlippedCurve>()
              .having((krzywa) => krzywa.curve, 'wyjście stylu', m.exit));
      expect(arkusz.barrierColor, zaslona);
      expect(arkusz.showDragHandle, isTrue);
      expect(arkusz.isScrollControlled, isTrue);
      expect(find.byType(Dialog), findsNothing);

      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(find.byType(BottomSheet)).dy,
          ekran(tester).height);
      expect(
          find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(SingleChildScrollView)),
          findsOneWidget,
          reason: 'przewijany');

      await sprzatnij(tester, services);
    });

    testWidgets(
        '${styl.name}: panel bezpieczeństwa w oknie to okno na środku, '
        'najwyżej 460 dp, w czasie panelu i z zasłoną stylu', (tester) async {
      final services = await uruchom(tester);
      await otworzPanel(tester, services, styl: styl);

      final trasa = trasaPanelu(tester);
      expect(trasa, isA<ChattDialogRoute<void>>());
      final okno = trasa as ChattDialogRoute<void>;
      expect(okno.panel, isTrue);
      expect(okno.transitionDuration, m.panelIn);
      expect(okno.reverseTransitionDuration, m.panelOut);
      expect(okno.barrierColor, zaslona);
      expect(okno.barrierColor, motyw.dialogTheme.barrierColor);
      expect(find.byType(BottomSheet), findsNothing, reason: 'bez uchwytu');

      final wejscie = find.ancestor(
          of: find.byType(Dialog), matching: find.byType(MotionTransition));
      final przejscie = tester.widget<MotionTransition>(wejscie);
      expect(przejscie.scale, m.panelScale);
      expect(przejscie.shift, 0, reason: 'w oknie ze środka');
      expect(przejscie.curve, m.enter);
      expect(skala(tester, wejscie), closeTo(m.panelScale, 0.001));

      await tester.pump(m.panelIn ~/ 2);
      expect(okno.animation!.value, closeTo(0.5, 0.01));
      expect(
          skala(tester, wejscie),
          closeTo(
              m.panelScale +
                  (1 - m.panelScale) * m.enter.transform(okno.animation!.value),
              0.001));
      await tester.pumpAndSettle();
      expect(skala(tester, wejscie), 1);

      final powierzchnia = find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first;
      final rozmiar = tester.getSize(powierzchnia);
      expect(rozmiar.width, lessThanOrEqualTo(460));
      expect(rozmiar.width, greaterThan(400));
      final srodek = tester.getCenter(powierzchnia);
      expect(srodek.dx, closeTo(ekran(tester).width / 2, 0.5));
      expect(srodek.dy, closeTo(ekran(tester).height / 2, 0.5));
      expect(
          find.descendant(
              of: find.byType(Dialog),
              matching: find.byType(SingleChildScrollView)),
          findsOneWidget,
          reason: 'przewijany');

      // Rogi arkusza; obrys tylko w Precyzji, jak w oknach.
      final k = chattTokens(styl, Brightness.light);
      final ksztalt =
          tester.widget<Material>(powierzchnia).shape! as RoundedRectangleBorder;
      expect(ksztalt.borderRadius, BorderRadius.circular(k.radiusSheet));
      expect(
          ksztalt.side,
          styl == AppStyle.precyzja
              ? BorderSide(color: k.outlineStrong)
              : BorderSide.none);

      await sprzatnij(tester, services);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets(
      'ograniczone animacje: panel bezpieczeństwa tylko przenika w 100 ms',
      (tester) async {
    final services = await uruchom(tester);
    await otworzPanel(tester, services, styl: AppStyle.cieplo, ogranicz: true);
    final trasa = trasaPanelu(tester);
    expect(trasa.transitionDuration, const Duration(milliseconds: 100));
    expect(trasa.reverseTransitionDuration, const Duration(milliseconds: 100));
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final przejscie = tester.widget<MotionTransition>(find.ancestor(
          of: find.byType(Dialog), matching: find.byType(MotionTransition)));
      expect(przejscie.scale, 1);
      expect(przejscie.shift, 0);
      expect(przejscie.curve, Curves.linear);
    } else {
      // Arkusz stoi od razu na miejscu, przenika sama treść.
      final arkusz = trasa as ModalBottomSheetRoute<void>;
      expect(arkusz.sheetAnimationStyle?.curve, isA<Threshold>());
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getBottomLeft(find.byType(BottomSheet)).dy,
          ekran(tester).height);
      final przenikanie = tester.widget<FadeTransition>(find
          .ancestor(
              of: find.byType(BottomSheet),
              matching: find.byType(FadeTransition))
          .first);
      expect(przenikanie.opacity.value, closeTo(0.5, 0.01));
    }
    await tester.pumpAndSettle();
    await sprzatnij(tester, services);
  },
      variant: TargetPlatformVariant(
          {TargetPlatform.android, TargetPlatform.windows}));
}
