// Klawiatura z PC na żywo, na jednym komputerze: ten proces jest nadawcą,
// a odbiorcą jest zwykła aplikacja Chatt uruchomiona obok.
//
// Nadawca nie ma jeszcze ekranu (to faza 4), więc pisze stąd: paruje się
// z aplikacją kodem, prosi o sesję i po odliczeniu wysyła tekst, Backspace,
// Delete, Enter i długie wklejenie. Tester w tym czasie klika w aplikacji
// i wyciąga na wierzch okno, do którego ma trafić pisanie.
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
//   4. w ciągu 10 sekund wyciągnąć na wierzch Notatnik (albo cmd, albo pole
//      w przeglądarce): pojawi się `Chatt ąęł 123`, nowa linia, `koniec`,
//      a w trzeciej linii długi wiersz cyfr (wklejenie);
//   5. Stop na pasku albo koniec skryptu: pasek i ikona znikają.
//
// Okno samego Chatta na wierzchu daje odmowę (`ownApp`), Notatnik
// uruchomiony jako administrator też (`elevated`); skrypt wypisuje cel po
// każdej paczce.
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

    for (var i = 10; i > 0; i--) {
      wypisz('wyciągnij okno docelowe na wierzch: $i');
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    Future<void> wyslij(List<RemoteInputOp> ops) async {
      expect(nadawca.sendRemoteInput(ops), isTrue);
      // Jedna paczka w locie: czekamy, aż kolejka nadawcy opustoszeje.
      await Future<void>.delayed(const Duration(milliseconds: 300));
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
    await wyslij([RemoteInputOp.insert(wklejenie)]);
    await czekaj(
      () =>
          nadawca.outgoingRemoteInput.value?.state !=
              OutgoingRemoteInputState.active ||
          nadawca.outgoingRemoteInput.value?.applied == true,
      const Duration(minutes: 1),
      'wklejenie',
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    wypisz(opis(nadawca.outgoingRemoteInput.value));

    wypisz('przez 30 s można wcisnąć Stop na pasku');
    final koniec = DateTime.now().add(const Duration(seconds: 30));
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
