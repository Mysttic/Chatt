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
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/app.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart' show defaultTcpPort;
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';

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
  // przycisku i obrysowuje go — zdejmujemy fokus przed zrzutem.
  tester.binding.focusManager.primaryFocus?.unfocus();
  await tester.pump();

  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(klucz));
  // Cienie tylko na czas zrzutu. W testach są wyłączone, a uniesione
  // powierzchnie (karty, przycisk pływający) dostają zamiast nich grubą
  // ciemną obwódkę — zrzut ma wyglądać jak aplikacja. Flagę oddajemy od razu,
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

Future<AppServices> rozmowca(String nazwa, Directory work) =>
    AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: nazwa,
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'received-$nazwa'),
      fileOfferPolicy: acceptAllFileOffers,
    );

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
      ja = await AppServices.start(
        executor: NativeDatabase.memory(),
        portOverride: 0,
        nameOverride: t['ja'],
        enableDiscovery: false,
        receivedDirOverride: p.join(work.path, 'received'),
      );
      await ja.db.saveLanguage(
          jezyk == 'en' ? AppLanguage.english : AppLanguage.polish);
      await ja.db.saveTheme(AppTheme.light);
      // Stos stoi na porcie losowym (portOverride: 0), a pole w ustawieniach
      // pokazuje to, co w bazie — na zrzucie do sklepu „0" wyglądałoby jak
      // usterka, więc wpisujemy port domyślny.
      await ja.db.saveSettings(
        nickname: t['ja']!,
        welcomeMessage: '',
        tcpPort: defaultTcpPort,
      );

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
      // w zwykłych testach ta sama droga zajmuje milisekundy — udawany zegar
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
        overrides: [appServicesProvider.overrideWithValue(ja)],
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
}
