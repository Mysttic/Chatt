// Zrzuty okna Windows do sklepu i dokumentacji, bez klikania po pulpicie.
//
// Aplikacja renderuje się w harnessie flutter_test w rozmiarze 1600×900,
// z własnym stosem w pamięci i dwoma rozmówcami w tym samym procesie, którzy
// rozmawiają z nią po prawdziwym gnieździe. Obraz wychodzi prosto z silnika
// (RepaintBoundary.toImage), więc na zrzutach nie ma cudzych rozmów ani
// niczego z pulpitu, a wynik jest taki sam na każdej maszynie.
//
// Uruchomienie (z katalogu app/):
//   flutter test tool/windows_shots.dart
//   set CHATT_SHOTS_LANG=en && flutter test tool/windows_shots.dart
//
// Same zrzuty dodatku „Klawiatura z PC":
//   flutter test tool/windows_shots.dart --plain-name klawiatury
//
// Wynik: docs/screenshots/windows/{pl,en}/*.png
//
// ignore_for_file: avoid_print
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/app.dart';
import 'package:chatt/core/remote_input.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/presence.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/ui/screens/remote_keyboard_screen.dart';
import 'package:chatt/ui/screens/settings_screen.dart';

const Map<String, String> _pl = {
  'ja': 'Mój komputer',
  'anna': 'Laptop Anny',
  'biuro': 'Komputer w biurze',
  'hej': 'Cześć! Widzisz mnie w sieci?',
  'zdjecia': 'Wysyłam Ci za chwilę zdjęcia z wyjazdu.',
  'raport': 'Raport gotowy, leci do Ciebie.',
  'dzieki': 'Mam, dzięki!',
  'png': 'zachod-slonca.png',
  'ustawienia': 'Ustawienia',
  'telefon': 'Telefon Anny',
  'notatki': 'Notatki',
  'notatnik': 'Notatnik',
  'pisanie': 'Spotkanie przesunięte na 15:00, sala 2',
};

const Map<String, String> _en = {
  'ja': 'My PC',
  'anna': "Anna's laptop",
  'biuro': 'Office PC',
  'hej': 'Hi! Can you see me on the network?',
  'zdjecia': 'Sending you the trip photos in a moment.',
  'raport': 'Report is ready, coming your way.',
  'dzieki': 'Got it, thanks!',
  'png': 'sunset.png',
  'ustawienia': 'Settings',
  'telefon': "Anna's phone",
  'notatki': 'Notes',
  'notatnik': 'Notepad',
  'pisanie': 'Meeting moved to 3 pm, room 2',
};

final String jezyk = Platform.environment['CHATT_SHOTS_LANG'] ?? 'pl';
final Map<String, String> t = jezyk == 'en' ? _en : _pl;

late Directory shots;

/// Kilka klatek z prawdziwym czasem między nimi: strumienie z bazy i obrazki
/// z dysku dochodzą asynchronicznie, a zwykły `pump` działa na udawanym
/// zegarze i nigdy by ich nie doczekał.
Future<void> odczekaj(WidgetTester tester,
    [Duration ile = const Duration(milliseconds: 600)]) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(ile ~/ 4));
    // Z czasem, nie „pusty" pump: przejścia między ekranami i animacje
    // liczą udawany zegar testu, a ten bez podanego czasu stoi w miejscu.
    await tester.pump(ile ~/ 4);
  }
}

Future<void> zrzut(WidgetTester tester, GlobalKey klucz, String nazwa) async {
  await odczekaj(tester);
  // Bez myszy i bez dotyku harness trzyma fokus klawiatury na pierwszym
  // przycisku i obrysowuje go, zdejmujemy fokus przed zrzutem.
  tester.binding.focusManager.primaryFocus?.unfocus();
  await tester.pump();

  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(klucz));
  // Cienie tylko na czas zrzutu. W testach są wyłączone, a uniesione
  // powierzchnie (karty, przycisk pływający) dostają zamiast nich grubą
  // ciemną obwódkę, a zrzut ma wyglądać jak aplikacja. Flagę oddajemy od razu,
  // bo framework sprawdza jej stan po ciele testu, jeszcze przed tearDown.
  ByteData? bajty;
  try {
    debugDisableShadows = false;
    boundary.markNeedsPaint();
    await tester.pump();
    bajty = await tester.runAsync(() async {
      final obraz = await boundary.toImage();
      return (await obraz.toByteData(format: ui.ImageByteFormat.png))!;
    });
  } finally {
    debugDisableShadows = true;
    boundary.markNeedsPaint();
    await tester.pump();
  }
  final plik = File(p.join(shots.path, '$nazwa.png'))
    ..writeAsBytesSync(bajty!.buffer.asUint8List());
  print('zapisano ${plik.path}');
}

/// Obrazek na demo miniatury, rysowany zamiast dołączanego do repozytorium.
Future<List<int>> demoObrazek() async {
  const szer = 720.0;
  const wys = 480.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, szer, wys));
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, szer, wys),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(szer, wys),
        const [Color(0xFF2E6BE6), Color(0xFF35C4C4)],
      ),
  );
  canvas.drawCircle(const Offset(520, 140), 70,
      Paint()..color = const Color(0xFFFFE082));
  final obraz = await recorder.endRecording().toImage(szer.toInt(), wys.toInt());
  return (await obraz.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
}

/// Harness testowy nie wczytuje czcionek z pubspec: bez tego każdy napis
/// renderuje się jako kwadraty. Te same pliki, które dołączamy do aplikacji.
Future<void> wczytajCzcionki() async {
  Future<ByteData> plik(String nazwa) async =>
      File(p.join('fonts', nazwa)).readAsBytesSync().buffer.asByteData();
  final roboto = FontLoader('Roboto')
    ..addFont(plik('Roboto-Regular.ttf'))
    ..addFont(plik('Roboto-Medium.ttf'))
    ..addFont(plik('Roboto-Bold.ttf'));
  await roboto.load();
  final ikony = FontLoader('MaterialIcons')
    ..addFont(plik('MaterialIcons-Regular.otf'));
  await ikony.load();
}

Future<AppServices> rozmowca(
  String nazwa,
  Directory work, {
  RemoteInputSink? ujscie,
  RemoteInputPolicy? zgodaNaPisanie,
}) =>
    AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: nazwa,
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'received-$nazwa'),
      fileOfferPolicy: acceptAllFileOffers,
      remoteInputSink: ujscie,
      remoteInputPolicy: zgodaNaPisanie,
    );

/// Komputer, którego okno oglądamy: język, jasny motyw i port domyślny
/// w ustawieniach (na zrzucie do sklepu „0" wyglądałoby jak usterka).
Future<AppServices> mojKomputer(Directory work, {RemoteInputSink? ujscie}) async {
  final ja = await AppServices.start(
    executor: NativeDatabase.memory(),
    portOverride: 0,
    nameOverride: t['ja'],
    enableDiscovery: false,
    receivedDirOverride: p.join(work.path, 'received'),
    remoteInputSink: ujscie,
  );
  await ja.db.saveLanguage(
      jezyk == 'en' ? AppLanguage.english : AppLanguage.polish);
  await ja.db.saveTheme(AppTheme.light);
  await ja.db.saveSettings(
    nickname: t['ja']!,
    welcomeMessage: '',
    tcpPort: defaultTcpPort,
  );
  return ja;
}

/// Pole z fokusem po drugiej stronie, jak zgłosiłaby je strona natywna.
class _Ujscie implements RemoteInputSink {
  final RemoteInputTarget cel;

  _Ujscie(this.cel);

  @override
  bool get supported => true;

  @override
  Future<RemoteInputTarget> status() async => cel;

  @override
  Future<RemoteInputApplied> apply(List<RemoteInputOp> ops) async =>
      (applied: true, target: cel);

  @override
  Future<void> holdOwnApp(bool on) async {}

  @override
  Future<void> setSession({required bool active, String peerName = ''}) async {}

  @override
  Future<bool> setImeEnabled(bool on) async => true;
}

/// Sesja już ruszyła (prośbę i zgodę załatwia prawdziwa droga przed
/// zrzutem), a tekst w polu jest na pokaz: wysyłka spod udawanego zegara
/// harnessu wisiałaby do limitu klienta.
class _GotowaSesja implements RemoteKeyboardLink {
  final AppServices services;

  _GotowaSesja(this.services);

  @override
  ValueListenable<OutgoingRemoteInput?> get state =>
      services.outgoingRemoteInput;

  @override
  Future<RemoteInputStart> start() async => RemoteInputStart.accepted;

  @override
  bool send(List<RemoteInputOp> ops) => true;

  @override
  Future<void> stop() async {}
}

/// Parowanie kodem, obie strony potwierdzają. Zwraca [druga] tak, jak widzi
/// ją [pierwsza].
Future<Peer> sparuj(AppServices pierwsza, AppServices druga) async {
  final drugaUPierwszej =
      await pierwsza.addPeerByAddress('127.0.0.1', druga.server.port!);
  await pierwsza.startPairing(drugaUPierwszej!);
  await pierwsza.confirmPairing(druga.identity.guid);
  await druga.confirmPairing(pierwsza.identity.guid);
  return (await pierwsza.db.peerByGuid(druga.identity.guid))!;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('zrzuty okna Windows', (tester) async {
    // Harness widgetów podmienia HttpClient na atrapę odpowiadającą 400
    // (żeby testy nie chodziły do sieci). Tu sieć jest celowa: rozmówcy piszą
    // do aplikacji po pętli zwrotnej, więc przywracamy prawdziwego klienta.
    HttpOverrides.global = null;
    // Bez myszy harness rysuje grube obwódki fokusu klawiatury na każdym
    // przycisku, którego przy zwykłym używaniu nikt nie widzi.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final work = Directory.systemTemp.createTempSync('chatt_windows_shots');
    shots = Directory(p.join(
        Directory.current.path, '..', 'docs', 'screenshots', 'windows', jezyk))
      ..createSync(recursive: true);

    late AppServices ja;
    late AppServices anna;
    late AppServices biuro;
    late int rozmowaAnny;

    // Cały stos i rozmówcy wstają w prawdziwym czasie, poza udawanym zegarem
    // testu. Aplikacja jest tą instancją, którą oglądamy; Anna i biuro piszą
    // do niej po pętli zwrotnej tak, jak robiłyby to z drugiego końca sieci.
    await tester.runAsync(() async {
      await wczytajCzcionki();
      ja = await mojKomputer(work);

      anna = await rozmowca(t['anna']!, work);
      biuro = await rozmowca(t['biuro']!, work);

      final jaUAnny = await anna.addPeerByAddress('127.0.0.1', ja.server.port!);
      rozmowaAnny = await anna.openConversationWith(jaUAnny!);
      await anna.sendText(rozmowaAnny, t['hej']!);
      await anna.sendText(rozmowaAnny, t['zdjecia']!);

      final jaWBiurze = await biuro.addPeerByAddress('127.0.0.1', ja.server.port!);
      final rozmowaBiura = await biuro.openConversationWith(jaWBiurze!);
      await biuro.sendText(rozmowaBiura, t['raport']!);

      // Odpowiedź z komputera tutaj, zanim harness zacznie pompować klatki:
      // wysyłka wołana po `pumpWidget` trwała 30 s (limit klienta), choć
      // w zwykłych testach ta sama droga zajmuje milisekundy: udawany zegar
      // harnessu i prawdziwe gniazda nie lubią się w jednej ścieżce.
      final annaUMnie = await ja.db.peerByGuid(anna.identity.guid);
      final rozmowaZAnna = await ja.db.ensureConversation(annaUMnie!.id);
      await ja.sendText(rozmowaZAnna, t['dzieki']!);
    });
    addTearDown(() => work.deleteSync(recursive: true));

    final klucz = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: klucz,
      child: ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(ja),
          // Obecność wpisana z ręki. Zwykle bierze się z odpytania sieci, ale
          // ta droga pod udawanym zegarem harnessu wisi do limitu klienta
          // (patrz uwaga wyżej). Oba komputery naprawdę tu nasłuchują, więc
          // zielona kropka na zrzucie mówi to samo, co powiedziałaby sonda.
          presenceProvider.overrideWith((ref) => Stream.value({
                anna.identity.guid: true,
                biuro.identity.guid: true,
              })),
        ],
        child: const ChattApp(),
      ),
    ));
    await zrzut(tester, klucz, '01_lista_rozmow');

    // Dwa panele: kliknięcie w rozmowę otwiera ją po prawej.
    await tester.tap(find.text(t['anna']!).first);
    await zrzut(tester, klucz, '02_rozmowa');

    print('etap: obrazek demo');
    // Prośba o plik: karta nad aplikacją, zanim poleci choćby bajt.
    final obrazek = File(p.join(work.path, t['png']!))
      ..writeAsBytesSync(await tester.runAsync(demoObrazek) as List<int>);
    print('etap: zapowiedź pliku');
    Future<void>? wysylka;
    await tester.runAsync(() async {
      // Wysyłka we własnej strefie: klient próbuje raz, dostaje 409 (zgoda
      // jeszcze nie wydana), ponawia i kończy sukcesem, ale licznik limitu
      // z pierwszej próby zostaje i odpala się 30 s później. W aplikacji to
      // nieszkodliwe (sprawdzone osobnym testem z odczekaniem 35 s), a tu
      // harness uznałby spóźniony wyjątek za błąd testu.
      wysylka = runZonedGuarded(
        () => anna.sendFile(rozmowaAnny, obrazek.path),
        (error, _) => print('spóźniony błąd klienta po transferze: $error'),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await zrzut(tester, klucz, '03_prosba_o_plik');

    print('etap: zgoda na plik');
    // Zgoda i miniatura po przyjęciu.
    await tester.runAsync(() async {
      final oferta = ja.pendingOffers.value.single;
      ja.respondToOffer(oferta.messageGuid, accept: true);
      await wysylka!.timeout(const Duration(seconds: 60));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    // Miniatura dekoduje się z dysku w tle: bez dłuższej przerwy zrzut łapie
    // sam kafelek pliku, jeszcze bez obrazka.
    await odczekaj(tester, const Duration(seconds: 3));
    await zrzut(tester, klucz, '04_plik_z_miniatura');

    print('etap: ustawienia');
    // Ustawienia na szerokim oknie.
    await tester.tap(find.byTooltip(t['ustawienia']!));
    await zrzut(tester, klucz, '05_ustawienia');

    // Zamknięcie stosu jeszcze w ciele testu, nie w tearDown: klient HTTP
    // trzyma połączenia w puli z licznikiem podtrzymania, a framework
    // sprawdza „czy nie zostały tykające liczniki" zaraz po ciele testu.
    await tester.runAsync(() async {
      await anna.dispose();
      await biuro.dispose();
      await ja.dispose();
    });
    await tester.pump(const Duration(seconds: 20));
  });

  // Dodatek „Klawiatura z PC". Cała sieć (parowanie, prośba, zgoda) idzie
  // przed `pumpWidget`, w prawdziwym czasie: prośba wysłana spod udawanego
  // zegara harnessu potrafi paść na połączeniu z puli, choć ten sam przebieg
  // poza harnessem trwa milisekundy. Stąd dwa testy, każdy z siecią na start.

  /// Wspólny początek: harness, katalog na zrzuty i katalog roboczy.
  Future<Directory> przygotuj(WidgetTester tester) async {
    HttpOverrides.global = null;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    shots = Directory(p.join(
        Directory.current.path, '..', 'docs', 'screenshots', 'windows', jezyk))
      ..createSync(recursive: true);
    final work = Directory.systemTemp.createTempSync('chatt_windows_shots');
    addTearDown(() => work.deleteSync(recursive: true));
    await tester.runAsync(wczytajCzcionki);
    return work;
  }

  Future<void> aplikacja(WidgetTester tester, GlobalKey klucz, AppServices ja,
          List<AppServices> obecni) =>
      tester.pumpWidget(RepaintBoundary(
        key: klucz,
        child: ProviderScope(
          overrides: [
            appServicesProvider.overrideWithValue(ja),
            presenceProvider.overrideWith((ref) => Stream.value({
                  for (final s in obecni) s.identity.guid: true,
                })),
          ],
          child: const ChattApp(),
        ),
      ));

  testWidgets('zrzuty klawiatury z PC: nadawca', (tester) async {
    final work = await przygotuj(tester);
    late AppServices ja;
    late AppServices telefon;
    late Peer telefonUMnie;

    // Telefon przyjmuje pisanie bez pytania, z polem notatek na wierzchu.
    await tester.runAsync(() async {
      ja = await mojKomputer(work);
      telefon = await rozmowca(t['telefon']!, work,
          ujscie: _Ujscie(RemoteInputTarget(
            active: true,
            field: RemoteInputField.text,
            app: 'com.google.android.keep',
            appLabel: t['notatki']!,
          )),
          zgodaNaPisanie: acceptAllRemoteInput);
      telefonUMnie = await sparuj(ja, telefon);
      await ja.openConversationWith(telefonUMnie);
      await ja.setKeyboardAddon(true);
      await telefon.setKeyboardAddon(true);
      await telefon.setRemoteInputReceive(true);
      final sesja = await ja.startRemoteInput(telefonUMnie);
      if (sesja != RemoteInputStart.accepted) {
        throw StateError('telefon nie przyjął sesji: $sesja');
      }
    });

    final klucz = GlobalKey();
    await aplikacja(tester, klucz, ja, [telefon]);
    await odczekaj(tester);

    // Rozmowa z telefonem, a nad nią ekran pisania.
    await tester.tap(find.text(t['telefon']!).first);
    await odczekaj(tester);
    Navigator.of(tester.element(find.byType(Scaffold).first),
            rootNavigator: true)
        .push(MaterialPageRoute<void>(
      builder: (_) =>
          RemoteKeyboardScreen(peer: telefonUMnie, link: _GotowaSesja(ja)),
    ));
    await odczekaj(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(RemoteKeyboardScreen),
        matching: find.byType(TextField),
      ),
      t['pisanie']!,
    );
    await zrzut(tester, klucz, '06_klawiatura_pisanie');

    await tester.runAsync(() async {
      await ja.stopRemoteInput();
      await telefon.dispose();
      await ja.dispose();
    });
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('zrzuty klawiatury z PC: odbiorca', (tester) async {
    final work = await przygotuj(tester);
    late AppServices ja;
    late AppServices anna;
    late Future<RemoteInputStart> prosba;

    // Laptop Anny prosi o pisanie na tym komputerze, z Notatnikiem na
    // wierzchu. Karta czeka, zanim aplikacja w ogóle stanie.
    await tester.runAsync(() async {
      ja = await mojKomputer(work,
          ujscie: _Ujscie(RemoteInputTarget(
            active: true,
            field: RemoteInputField.text,
            app: 'notepad.exe',
            appLabel: t['notatnik']!,
          )));
      anna = await rozmowca(t['anna']!, work);
      final jaUAnny = await sparuj(anna, ja);
      final annaUMnie = await ja.db.peerByGuid(anna.identity.guid);
      await ja.openConversationWith(annaUMnie!);
      await anna.setKeyboardAddon(true);
      await ja.setKeyboardAddon(true);
      await ja.setRemoteInputReceive(true);
      prosba = anna.startRemoteInput(jaUAnny);
      final koniec = DateTime.now().add(const Duration(seconds: 15));
      while (ja.pendingRemoteInput.value.isEmpty) {
        if (DateTime.now().isAfter(koniec)) {
          throw StateError('karta nie przyszła');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });

    final klucz = GlobalKey();
    await aplikacja(tester, klucz, ja, [anna]);
    await zrzut(tester, klucz, '07_klawiatura_zgoda');

    // Zgoda: pasek „Pisze" u góry, a w ustawieniach karta dodatku.
    await tester.runAsync(() async {
      if (ja.pendingRemoteInput.value.isEmpty) {
        final wynik = await prosba.timeout(const Duration(seconds: 2),
            onTimeout: () => RemoteInputStart.cancelled);
        throw StateError('karta zniknęła przed zgodą, prośba Anny: $wynik');
      }
      ja.respondToRemoteInput(ja.pendingRemoteInput.value.single.id,
          accept: true);
      final wynik = await prosba;
      if (wynik != RemoteInputStart.accepted) {
        throw StateError('zgoda nie doszła do Anny: $wynik');
      }
    });
    await tester.tap(find.byTooltip(t['ustawienia']!));
    await odczekaj(tester);
    // Lista ustawień buduje się leniwie: karty dodatków nie ma, dopóki nie
    // dojedzie się do niej przewijaniem.
    await tester.scrollUntilVisible(
      find.byType(KeyboardAddonCard),
      400,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // Karta przy dolnej krawędzi kadru: niżej jest sekcja „To urządzenie"
    // z adresami IP komputera, na którym powstaje zrzut, a wyżej czerwona
    // karta o głuchym wykrywaniu (stos zrzutów działa bez wykrywania).
    // Przesunięcie o 100 px chowa jedno i drugie.
    final karta = tester.element(find.byType(KeyboardAddonCard));
    await Scrollable.ensureVisible(karta, alignment: 1.0);
    final pozycja = Scrollable.of(karta).position;
    pozycja.jumpTo(pozycja.pixels + 100);
    await zrzut(tester, klucz, '08_klawiatura_odbior');

    await tester.runAsync(() async {
      await anna.stopRemoteInput();
      await anna.dispose();
      await ja.dispose();
    });
    await tester.pump(const Duration(seconds: 20));
  });
}
