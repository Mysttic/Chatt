// Klawiatura z PC na żywo, na jednym komputerze: ten proces jest nadawcą,
// a odbiorcą jest zwykła aplikacja Chatt uruchomiona obok.
//
// Pisze stąd, bez ekranu nadawcy: paruje się z aplikacją kodem, prosi
// o sesję i wysyła tekst, Backspace, Enter i długie wklejenie. Tester w tym
// czasie klika w aplikacji i wyciąga na wierzch Notatnik. Skrypt pisze
// wyłącznie wtedy, gdy cel to `notepad.exe`, a przy CHATT_W_CHATT=1 także
// w polu tekstowym Chatt (krok 5): każda paczka jest sprawdzana, więc tekst
// nie trafi do przypadkowego okna.
//
// Przygotowanie: aplikacja Chatt z dodatkiem „Klawiatura z PC" i przełącznikiem
// „Pozwól pisać na tym urządzeniu" włączonymi (Ustawienia → Dodatki). Jej port
// to CHATT_KLAWIATURA_PORT (domyślnie 47780).
//
//   cd app
//   flutter test tool/klawiatura_e2e_test.dart
//
// Przebieg, który ma wyjść:
//   1. w aplikacji karta parowania z tym samym kodem, który wypisze skrypt:
//      „Zgadza się";
//   2. karta „Nadawca e2e chce pisać na tym urządzeniu", fokus na Odrzuć:
//      „Akceptuj"; okno schowane w zasobniku wychodzi na wierzch na czas
//      karty i potem wraca;
//   3. pływający pasek „Pisze: Nadawca e2e" ze Stopem i inna ikona
//      w zasobniku;
//   4. w ciągu minuty kliknąć w Notatnik: pojawi się `Chatt ąęł 123`, nowa
//      linia, `koniec`, a w trzeciej linii długi wiersz cyfr (wklejenie);
//   5. kliknąć w okno Chatt: cel to `ownApp`, a pisanie dalej możliwe; przy
//      CHATT_W_CHATT=1 (tylko z instancją testową) kliknąć jeszcze w pole
//      tekstowe Chatt, np. szukanie: skrypt wpisuje tam `do Chatt` i po
//      10 s kasuje to Backspace'em;
//   6. Stop na pływającym pasku: pasek i ikona znikają, nadawca dostaje
//      `no_grant`. Przy CHATT_STOP_W_TRAKCIE=1 najpierw jeszcze raz kliknąć
//      w Notatnik: skrypt wysyła 3000 piątek jedną paczką (pół minuty
//      pisania), a Stop wciśnięty w trakcie ma je od razu uciąć.
//
// Notatnik uruchomiony jako administrator daje odmowę (`elevated`); skrypt
// wypisuje cel po każdej paczce.
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';

final int portAplikacji =
    int.tryParse(Platform.environment['CHATT_KLAWIATURA_PORT'] ?? '') ?? 47780;

/// Pisanie w polu samej aplikacji Chatt, tylko na życzenie: odbiorcą ma być
/// wtedy instancja testowa (CHATT_DATA_DIR), żeby tekst nie trafił
/// w prawdziwą rozmowę.
final bool wChatt = Platform.environment['CHATT_W_CHATT'] == '1';

/// Stop w trakcie długiej paczki: pisanie ma się urwać od razu.
final bool stopWTrakcie = Platform.environment['CHATT_STOP_W_TRAKCIE'] == '1';

void wypisz(String linia) => stdout.writeln(linia);

Future<void> czekaj(bool Function() warunek, Duration ile, String co) async {
  final koniec = DateTime.now().add(ile);
  while (!warunek()) {
    if (DateTime.now().isAfter(koniec)) fail('nie doczekano: $co');
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

String opis(OutgoingRemoteInput? stan) {
  if (stan == null) return 'brak sesji';
  final cel = stan.target;
  return '${stan.state.name} applied=${stan.applied} rtt=${stan.rtt?.inMilliseconds}ms '
      'cel: ${cel.app} "${cel.appLabel}" active=${cel.active} '
      'field=${cel.field.name} ownApp=${cel.ownApp} locked=${cel.locked} '
      'elevated=${cel.elevated}';
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('klawiatura z PC: ten proces pisze w aplikacji obok', () async {
    final katalog = Directory.systemTemp.createTempSync('chatt_klawiatura_e2e');
    final nadawca = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Nadawca e2e',
      enableDiscovery: false,
      receivedDirOverride: p.join(katalog.path, 'odebrane'),
    );
    addTearDown(() async {
      await nadawca.dispose();
      katalog.deleteSync(recursive: true);
    });

    final aplikacja =
        await nadawca.addPeerByAddress('127.0.0.1', portAplikacji);
    expect(aplikacja, isNotNull,
        reason: 'pod 127.0.0.1:$portAplikacji nie odpowiada Chatt');
    wypisz('aplikacja: ${aplikacja!.name}');

    final kod = await nadawca.startPairing(aplikacja);
    expect(kod, isNotNull, reason: 'aplikacja nie przyjęła parowania');
    wypisz('KOD PAROWANIA: $kod  (w aplikacji: „Zgadza się")');
    await nadawca.confirmPairing(aplikacja.guid);
    await czekaj(
      () => nadawca.pendingPairings.value.isEmpty,
      const Duration(minutes: 3),
      'potwierdzenie parowania w aplikacji',
    );
    final sparowana = (await nadawca.db.peerByGuid(aplikacja.guid))!;
    expect(sparowana.verified, isTrue, reason: 'parowanie nie doszło');

    await nadawca.setKeyboardAddon(true);
    wypisz('proszę o sesję: w aplikacji karta, „Akceptuj"');
    final start = await nadawca.startRemoteInput(sparowana);
    wypisz('start: ${start.name}');
    expect(start, RemoteInputStart.accepted);
    wypisz(opis(nadawca.outgoingRemoteInput.value));

    bool wNotatniku() {
      final cel = nadawca.outgoingRemoteInput.value?.target;
      return cel != null &&
          cel.active &&
          cel.app.toLowerCase() == 'notepad.exe';
    }

    wypisz('kliknij w Notatnik (czekam do minuty)');
    await czekaj(wNotatniku, const Duration(minutes: 1), 'Notatnik na wierzchu');
    wypisz(opis(nadawca.outgoingRemoteInput.value));

    Future<void> wyslij(List<RemoteInputOp> ops) async {
      if (!wNotatniku()) fail('cel to nie Notatnik, nic nie wysyłam');
      final przed = nadawca.outgoingRemoteInput.value!.typedReplies;
      expect(nadawca.sendRemoteInput(ops), isTrue);
      await czekaj(
        () => (nadawca.outgoingRemoteInput.value?.typedReplies ?? przed) > przed,
        const Duration(seconds: 30),
        'odpowiedź na paczkę',
      );
      wypisz(opis(nadawca.outgoingRemoteInput.value));
    }

    await wyslij(const [RemoteInputOp.insert('Chatt ąęł 124')]);
    await wyslij(const [RemoteInputOp.backspace()]);
    await wyslij(const [RemoteInputOp.insert('3x')]);
    await wyslij(const [RemoteInputOp.backspace()]);
    await wyslij(const [RemoteInputOp.action()]);
    await wyslij(const [RemoteInputOp.insert('koniec')]);
    await wyslij(const [RemoteInputOp.action()]);
    // Wklejenie: jeden długi tekst, który nadawca dzieli na paczki.
    final wklejenie = List.generate(600, (i) => '${i % 10}').join();
    final zegar = Stopwatch()..start();
    await wyslij([RemoteInputOp.insert(wklejenie)]);
    wypisz('wklejenie 600 znaków: ${zegar.elapsedMilliseconds} ms, '
        'paczek z tekstem: ${nadawca.outgoingRemoteInput.value!.typedReplies}');

    wypisz('kliknij w okno Chatt (czekam do minuty)');
    await czekaj(
      () => nadawca.outgoingRemoteInput.value?.target.ownApp ?? false,
      const Duration(minutes: 1),
      'Chatt na wierzchu',
    );
    wypisz('Chatt na wierzchu: ${opis(nadawca.outgoingRemoteInput.value)}');
    expect(nadawca.outgoingRemoteInput.value!.target.active, isTrue,
        reason: 'okno Chatt przyjmuje pisanie jak każde inne');

    if (wChatt) {
      bool wPoluChatt() {
        final cel = nadawca.outgoingRemoteInput.value?.target;
        return cel != null &&
            cel.active &&
            cel.ownApp &&
            cel.field == RemoteInputField.text;
      }

      wypisz('kliknij w pole tekstowe Chatt (czekam do minuty)');
      await czekaj(wPoluChatt, const Duration(minutes: 1), 'pole Chatt');
      Future<void> wyslijDoChatt(List<RemoteInputOp> ops) async {
        if (!wPoluChatt()) fail('cel to nie pole Chatt, nic nie wysyłam');
        final przed = nadawca.outgoingRemoteInput.value!.typedReplies;
        expect(nadawca.sendRemoteInput(ops), isTrue);
        await czekaj(
          () =>
              (nadawca.outgoingRemoteInput.value?.typedReplies ?? przed) > przed,
          const Duration(seconds: 30),
          'odpowiedź z pola Chatt',
        );
        wypisz('pole Chatt: ${opis(nadawca.outgoingRemoteInput.value)}');
        expect(nadawca.outgoingRemoteInput.value!.applied, isTrue,
            reason: 'pole Chatt przyjmuje pisanie');
      }

      await wyslijDoChatt(const [RemoteInputOp.insert('do Chatt')]);
      wypisz('w polu Chatt powinno być „do Chatt"; za 10 s kasuję');
      await Future<void>.delayed(const Duration(seconds: 10));
      await wyslijDoChatt(const [RemoteInputOp.backspace(8)]);
    }

    if (stopWTrakcie) {
      wypisz('kliknij w Notatnik (czekam do minuty), potem Stop w trakcie '
          'pisania piątek');
      await czekaj(
          wNotatniku, const Duration(minutes: 1), 'Notatnik na wierzchu');
      expect(nadawca.sendRemoteInput([RemoteInputOp.insert('5' * 3000)]),
          isTrue);
    }
    wypisz('przez minutę można wcisnąć Stop na pasku');
    final koniec = DateTime.now().add(const Duration(minutes: 1));
    while (DateTime.now().isBefore(koniec) &&
        nadawca.outgoingRemoteInput.value?.state !=
            OutgoingRemoteInputState.disconnected) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    wypisz('stan: ${opis(nadawca.outgoingRemoteInput.value)}');
    await nadawca.stopRemoteInput();
    wypisz('koniec');
  });
}
