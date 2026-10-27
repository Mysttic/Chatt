import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/share_intake.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/ui/screens/chat_screen.dart';
import 'package:chatt/ui/screens/conversations_screen.dart';
import 'package:chatt/ui/screens/send_to_screen.dart';
import 'package:chatt/ui/widgets/motion.dart';
import 'package:chatt/ui/widgets/toasts.dart';

/// Strona natywna kanału `chatt/share` na niby: skrzynka z zapowiedzią,
/// kopie plików do oddania i zapis każdego wywołania.
class _Natywna {
  _Natywna(this.kanal) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, _obsluz);
  }

  final MethodChannel kanal;
  Map<String, Object?>? skrzynka;
  final kopie = <String, List<Map<String, Object?>>>{};
  final wywolania = <MethodCall>[];

  List<Object?> argumenty(String metoda) => [
        for (final c in wywolania)
          if (c.method == metoda) (c.arguments as Map)['id'],
      ];

  Future<Object?> _obsluz(MethodCall call) async {
    wywolania.add(call);
    switch (call.method) {
      case 'take':
        final zapowiedz = skrzynka;
        skrzynka = null;
        return zapowiedz;
      case 'files':
        return kopie[(call.arguments as Map)['id']] ?? const [];
      case 'setTargets':
        return true;
    }
    return null;
  }

  /// Natywna strona woła Darta: przyszło coś nowego.
  Future<void> zapowiedz(Map<String, Object?> zapowiedz) async {
    skrzynka = zapowiedz;
    final wiadomosc = const StandardMethodCodec()
        .encodeMethodCall(const MethodCall('incoming'));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(kanal.name, wiadomosc, (_) {});
  }

  void odepnij() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(kanal, null);
}

Map<String, Object?> _udostepnienie(String id,
        {String? text, int count = 0, int skipped = 0, String? peer}) =>
    {
      'kind': 'share',
      'id': id,
      'text': text,
      'count': count,
      'skipped': skipped,
      'peer': peer,
    };

/// Udostępnianie do Chatta na ekranie (issue #60): wybór rozmowy, treść
/// czekająca w rozmowie na „Wyślij", rozmówca wskazany wprost w oknie
/// systemu, skrót rozmowy z ekranu głównego.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final teksty = lookupAppLocalizations(const Locale('en'));
  const kanal = MethodChannel('test/share');

  late Directory katalog;
  late _Natywna natywna;
  late ShareIntake intake;

  setUp(() {
    katalog = Directory.systemTemp.createTempSync('chatt_udostepnij_');
    natywna = _Natywna(kanal);
    intake = ShareIntake(channel: kanal);
    chattToasts.clear();
  });
  tearDown(() {
    natywna.odepnij();
    chattToasts.clear();
    katalog.deleteSync(recursive: true);
  });

  /// Bez sieci: wysyłka do rozmówcy kończy się od razu jako nieudana, a
  /// wiadomość i tak ląduje w bazie.
  Future<AppServices> uruchom(WidgetTester tester) async {
    final services = (await tester.runAsync(() => AppServices.start(
          executor: NativeDatabase.memory(),
          portOverride: 0,
          nameOverride: 'Celina',
          enableDiscovery: false,
          receivedDirOverride: '${katalog.path}/Celina',
        )))!;
    services.client.useWifi(false);
    return services;
  }

  Future<void> sprzatnij(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(services.dispose);
  }

  Widget aplikacja(AppServices services, Widget ekran,
          {GlobalKey<NavigatorState>? navigator}) =>
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          shareIntakeProvider.overrideWithValue(intake),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
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

  /// Rozmowy z Alicją (w Chatcie nazwaną „Ala z pracy") i Bartkiem, bez
  /// adresów: obecność odpowiada od razu, bez sieci.
  Future<Map<String, int>> rozmowy(
          WidgetTester tester, AppServices services) async =>
      (await tester.runAsync(() async {
        final wynik = <String, int>{};
        for (final nazwa in ['Alicja', 'Bartek']) {
          final peer = await services.db.upsertPeer(
            guid: 'guid-${nazwa.toLowerCase()}',
            name: nazwa,
            welcomeMessage: '',
            host: '',
            port: 0,
          );
          wynik[nazwa] = await services.db.ensureConversation(peer.id);
        }
        await services.db.setPeerAlias(
            (await services.db.peerByGuid('guid-alicja'))!.id, 'Ala z pracy');
        return wynik;
      }))!;

  Future<void> dokoncz(WidgetTester tester, bool Function() warunek,
      {String? powod}) async {
    for (var i = 0; i < 100 && !warunek(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(warunek(), isTrue, reason: powod);
  }

  /// Kopie „udostępnionych" plików: prawdziwe pliki, bo wysyłka je czyta.
  List<Map<String, Object?>> kopie(List<String> nazwy) => [
        for (final (i, nazwa) in nazwy.indexed)
          {
            'path': (File('${katalog.path}/udostepnione/$i/$nazwa')
                  ..createSync(recursive: true)
                  ..writeAsBytesSync(List.filled(1000 * (i + 1), 7)))
                .path,
            'name': nazwa,
            'size': 1000 * (i + 1),
          },
      ];

  TextField pole(WidgetTester tester) =>
      tester.widget<TextField>(find.descendant(
          of: find.byType(ChatScreen), matching: find.byType(TextField)));

  List<String> komunikaty() => [for (final t in chattToasts.value) t.text];

  testWidgets(
      'bez rozmówcy: wybór rozmowy, w rozmowie tekst i pliki, Wyślij wysyła '
      'wszystko', (tester) async {
    final services = await uruchom(tester);
    final id = await rozmowy(tester, services);
    natywna.kopie['s1'] = kopie(['foto.jpg', 'umowa.pdf']);
    await tester.pumpWidget(aplikacja(services, const ConversationsScreen()));
    await dokoncz(tester, () => find.byType(ListTile).evaluate().length == 2);

    await tester.runAsync(intake.attach);
    await tester.runAsync(() => natywna
        .zapowiedz(_udostepnienie('s1', text: 'Zobacz to', count: 2)));
    await dokoncz(tester, () => find.byType(SendToScreen).evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(teksty.shareSendToTitle), findsOneWidget);
    expect(find.text('Zobacz to'), findsOneWidget);
    expect(find.text(teksty.shareFiles(2)), findsOneWidget);

    // Szukanie łapie także nazwę nadaną w Chatcie.
    await tester.enterText(
        find.descendant(
            of: find.byType(SendToScreen), matching: find.byType(TextField)),
        'pracy');
    await tester.pump();
    expect(find.text('Bartek'), findsNothing);
    await tester.tap(find.text('Ala z pracy'));
    await dokoncz(tester, () => find.byType(ChatScreen).evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SendToScreen), findsNothing);

    // Tekst w polu, pliki na pasku nad nim; nic jeszcze nie poszło.
    expect(pole(tester).controller!.text, 'Zobacz to');
    await dokoncz(tester,
        () => find.text('${teksty.shareFiles(2)} · 2.9 KB').evaluate().isNotEmpty);
    expect(find.text('foto.jpg, umowa.pdf'), findsOneWidget);
    expect(natywna.argumenty('discard'), isEmpty);
    final przed = (await tester.runAsync(
        () => services.db.watchMessages(id['Alicja']!).first))!;
    expect(przed, isEmpty);

    await tester.tap(find.byTooltip(teksty.sendTooltip));
    var wyslane = <Message>[];
    for (var i = 0; i < 100 && wyslane.length < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
      wyslane = (await tester.runAsync(
          () => services.db.watchMessages(id['Alicja']!).first))!;
    }
    expect(wyslane.map((m) => (m.kind, m.fileName ?? m.body)), [
      (MessageKind.text, 'Zobacz to'),
      (MessageKind.file, 'foto.jpg'),
      (MessageKind.file, 'umowa.pdf'),
    ]);
    expect(wyslane.every((m) => m.direction == MessageDirection.outgoing),
        isTrue);
    expect(natywna.argumenty('keep'), ['s1']);
    expect(natywna.argumenty('discard'), isEmpty);
    expect(natywna.argumenty('reportUsed'), ['guid-alicja']);
    expect(find.text('foto.jpg, umowa.pdf'), findsNothing);
    expect(pole(tester).controller!.text, isEmpty);

    // Bez sieci wysyłka kończy się niepowodzeniem. Czekamy na nie, bo do
    // tego czasu wysyłka trzyma pliki otwarte, a tych Windows nie skasuje.
    for (var i = 0;
        i < 200 && wyslane.any((m) => m.status == MessageStatus.pending);
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
      wyslane = (await tester.runAsync(
          () => services.db.watchMessages(id['Alicja']!).first))!;
    }
    expect(wyslane.map((m) => m.status), everyElement(MessageStatus.failed));

    await sprzatnij(tester, services);
  });

  testWidgets('rozmówca wskazany w oknie systemu dostaje rozmowę od razu',
      (tester) async {
    final services = await uruchom(tester);
    await rozmowy(tester, services);
    await tester.pumpWidget(aplikacja(services, const ConversationsScreen()));
    await dokoncz(tester, () => find.byType(ListTile).evaluate().length == 2);

    await tester.runAsync(intake.attach);
    await tester.runAsync(() => natywna.zapowiedz(
        _udostepnienie('s2', text: 'https://example.com', peer: 'guid-bartek')));
    await dokoncz(tester, () => find.byType(ChatScreen).evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SendToScreen), findsNothing);
    expect(tester.widget<ChatScreen>(find.byType(ChatScreen)).peer.guid,
        'guid-bartek');
    expect(pole(tester).controller!.text, 'https://example.com');
    // Sam tekst: paska z plikami nie ma.
    expect(find.byTooltip(teksty.shareDontSend), findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets(
      'rozmówca, którego już nie ma: wybór rozmowy; skrót do rozmowy, '
      'której już nie ma: komunikat', (tester) async {
    final services = await uruchom(tester);
    await rozmowy(tester, services);
    await tester.pumpWidget(aplikacja(services, const ConversationsScreen()));
    await dokoncz(tester, () => find.byType(ListTile).evaluate().length == 2);
    await tester.runAsync(intake.attach);

    await tester.runAsync(() => natywna.zapowiedz(
        _udostepnienie('s3', text: 'hej', peer: 'guid-usuniety')));
    await dokoncz(tester, () => find.byType(SendToScreen).evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));

    // Zamknięcie bez wyboru odrzuca treść.
    await tester.tap(find.byTooltip(teksty.close));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SendToScreen), findsNothing);
    expect(natywna.argumenty('discard'), ['s3']);

    await tester.runAsync(() =>
        natywna.zapowiedz({'kind': 'open', 'peer': 'guid-usuniety'}));
    await dokoncz(tester, () => komunikaty().isNotEmpty);
    expect(komunikaty(), [teksty.conversationGone]);
    expect(find.byType(ChatScreen), findsNothing);

    await sprzatnij(tester, services);
  });

  testWidgets('skrót rozmowy z ekranu głównego zdejmuje to, co otwarte',
      (tester) async {
    final services = await uruchom(tester);
    await rozmowy(tester, services);
    await tester.pumpWidget(aplikacja(services, const ConversationsScreen()));
    await dokoncz(tester, () => find.byType(ListTile).evaluate().length == 2);
    await tester.runAsync(intake.attach);

    await tester.tap(find.text('Bartek'));
    await dokoncz(tester, () => find.byType(ChatScreen).evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));

    await tester.runAsync(
        () => natywna.zapowiedz({'kind': 'open', 'peer': 'guid-alicja'}));
    await dokoncz(
        tester,
        () =>
            find.byType(ChatScreen).evaluate().length == 1 &&
            tester.widget<ChatScreen>(find.byType(ChatScreen)).peer.guid ==
                'guid-alicja');
    await tester.pump(const Duration(seconds: 1));
    // Pod rozmową jest lista rozmów, rozmowa z Bartkiem zeszła.
    expect(find.byType(ChatScreen), findsOneWidget);

    await sprzatnij(tester, services);
  });

  testWidgets('nic do wysłania: komunikat, bez wyboru rozmowy',
      (tester) async {
    final services = await uruchom(tester);
    await rozmowy(tester, services);
    await tester.pumpWidget(aplikacja(services, const ConversationsScreen()));
    await dokoncz(tester, () => find.byType(ListTile).evaluate().length == 2);
    await tester.runAsync(intake.attach);

    await tester.runAsync(
        () => natywna.zapowiedz(_udostepnienie('s4', skipped: 2)));
    await dokoncz(tester, () => komunikaty().isNotEmpty);
    expect(komunikaty(), [teksty.shareNothing]);
    expect(find.byType(SendToScreen), findsNothing);
    expect(natywna.argumenty('discard'), ['s4']);

    // Część plików pominięta: komunikat i wybór rozmowy dla reszty.
    await tester.runAsync(() => natywna
        .zapowiedz(_udostepnienie('s5', count: 1, skipped: 1)));
    await dokoncz(tester, () => find.byType(SendToScreen).evaluate().isNotEmpty);
    expect(komunikaty().last, teksty.shareSkipped(1));

    await sprzatnij(tester, services);
  });

  testWidgets('krzyżyk na pasku i wyjście z rozmowy odrzucają pliki',
      (tester) async {
    final services = await uruchom(tester);
    await rozmowy(tester, services);
    natywna.kopie['s6'] = kopie(['a.txt']);
    natywna.kopie['s7'] = kopie(['b.txt']);
    await tester.pumpWidget(aplikacja(services, const ConversationsScreen()));
    await dokoncz(tester, () => find.byType(ListTile).evaluate().length == 2);
    await tester.runAsync(intake.attach);

    await tester.runAsync(() => natywna
        .zapowiedz(_udostepnienie('s6', count: 1, peer: 'guid-alicja')));
    await dokoncz(tester, () => find.textContaining('a.txt').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip(teksty.shareDontSend));
    await tester.pump();
    expect(find.textContaining('a.txt'), findsNothing);
    expect(natywna.argumenty('discard'), ['s6']);

    await tester.runAsync(() => natywna
        .zapowiedz(_udostepnienie('s7', count: 1, peer: 'guid-alicja')));
    await dokoncz(tester, () => find.textContaining('b.txt').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ChatScreen), findsNothing);
    expect(natywna.argumenty('discard'), ['s6', 's7']);
    expect(natywna.argumenty('keep'), isEmpty);

    await sprzatnij(tester, services);
  });

  testWidgets('szerokie okno: treść trafia do rozmowy otwartej w panelu',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = await uruchom(tester);
    await rozmowy(tester, services);
    await tester.pumpWidget(aplikacja(services, const ConversationsScreen()));
    await dokoncz(tester, () => find.byType(ListTile).evaluate().length == 2);
    await tester.runAsync(intake.attach);

    await tester.tap(find.text('Ala z pracy'));
    await dokoncz(tester, () => find.byType(ChatScreen).evaluate().isNotEmpty);
    await tester.enterText(
        find.descendant(
            of: find.byType(ChatScreen), matching: find.byType(TextField)),
        'Patrz:');
    final ekran = tester.state(find.byType(ChatScreen));

    await tester.runAsync(() => natywna.zapowiedz(
        _udostepnienie('s8', text: 'https://example.com', peer: 'guid-alicja')));
    await dokoncz(tester,
        () => pole(tester).controller!.text == 'Patrz:\nhttps://example.com');
    // Ten sam ekran rozmowy: tekst dopisał się do tego, co już było w polu.
    expect(tester.state(find.byType(ChatScreen)), same(ekran));

    // Wybór z ekranu „Wyślij do" zamyka go i otwiera rozmowę w panelu.
    await tester.runAsync(
        () => natywna.zapowiedz(_udostepnienie('s9', text: 'drugie')));
    await dokoncz(tester, () => find.byType(SendToScreen).evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.descendant(
        of: find.byType(SendToScreen), matching: find.text('Bartek')));
    await dokoncz(
        tester,
        () =>
            find.byType(SendToScreen).evaluate().isEmpty &&
            tester.widget<ChatScreen>(find.byType(ChatScreen)).peer.guid ==
                'guid-bartek');
    await tester.pump(const Duration(seconds: 1));
    expect(pole(tester).controller!.text, 'drugie');
    expect(find.byType(ChatScreen), findsOneWidget);

    await sprzatnij(tester, services);
  });

  testWidgets('„Wyślij do" bez żadnej rozmowy prowadzi do „W pobliżu"',
      (tester) async {
    final services = await uruchom(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(aplikacja(services, const SizedBox(),
        navigator: navigator));
    navigator.currentState!.push(ChattPageRoute<void>(
      builder: (_) => SendToScreen(
        share: const IncomingShare(id: 's10', fileCount: 3),
        onChosen: (_, _) => fail('nie ma czego wybrać'),
      ),
    ));
    await dokoncz(tester,
        () => find.text(teksty.shareNoConversations).evaluate().isNotEmpty);
    expect(find.text(teksty.shareFiles(3)), findsOneWidget);
    expect(find.text(teksty.nearbyButton), findsOneWidget);

    await sprzatnij(tester, services);
    expect(natywna.argumenty('discard'), ['s10']);
  });
}
