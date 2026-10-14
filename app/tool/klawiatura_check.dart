// Sprawdzenie ujścia klawiatury z PC na żywym runnerze Windows.
//
// Kanał `chatt/remoteinput` żyje po stronie platformy
// (`windows/runner/chatt_remote_input.cpp`), więc `flutter test` go nie widzi.
// Ten skrypt podnosi prawdziwy runner i woła kanał wprost, z pominięciem
// zgody: dodatek, karta i sieć nie biorą w tym udziału.
//
//   cd app
//   flutter run -d windows -t tool/klawiatura_check.dart
//
// Po starcie skrypt co sekundę wypisuje stan celu (program na wierzchu,
// rodzaj pola, ownApp, locked, elevated). Wystarczy wyciągnąć na wierzch
// Notatnik (albo inny program z polem tekstowym): wtedy skrypt pokazuje
// pływający pasek, wpisuje `Chatt ąęł 123`, cofa i dopisuje ostatnią cyfrę,
// wciska Enter i dopisuje `koniec`. Notatnik ma pokazać:
//
//   Chatt ąęł 123
//   koniec
//
// Potem czeka 30 sekund na Stop na pasku: stuknięcie ma wypisać „STOP"
// i schować pasek, a pole w Notatniku ma zostać z fokusem.
//
// Zmienna CHATT_KLAWIATURA_CEL wskazuje inny program niż notepad.exe (nazwa
// pliku, bez ścieżki), np. `cmd.exe`, `msedge.exe`.
//
// Ręcznie przy okazji: okno Chatta na wierzchu ma dać `ownApp: true`
// i `applied: false`, Notatnik uruchomiony jako administrator
// `elevated: true`, a pole hasła na stronie WWW `field: password`.

import 'dart:async';
import 'dart:io';

import 'package:chatt/core/remote_input.dart';
import 'package:chatt/network/protocol.dart';
import 'package:flutter/widgets.dart';

void wypisz(String linia) => debugPrint(linia);

String opis(RemoteInputTarget cel) => 'app=${cel.app} '
    'label="${cel.appLabel}" active=${cel.active} field=${cel.field.name} '
    'ownApp=${cel.ownApp} locked=${cel.locked} elevated=${cel.elevated}';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());

  final docelowy =
      (Platform.environment['CHATT_KLAWIATURA_CEL'] ?? 'notepad.exe')
          .toLowerCase();
  const kanal = RemoteInputChannel();
  final stop = Completer<void>();
  RemoteInputChannel.listen(onStop: () {
    wypisz('STOP');
    if (!stop.isCompleted) stop.complete();
  });

  wypisz('--- klawiatura z PC: czekam na $docelowy na wierzchu ---');
  RemoteInputTarget cel = RemoteInputTarget.none;
  final koniec = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(koniec)) {
    cel = await kanal.status();
    wypisz('status: ${opis(cel)}');
    if (cel.app.toLowerCase() == docelowy) break;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  if (cel.app.toLowerCase() != docelowy) {
    wypisz('nie doczekano $docelowy');
    exit(1);
  }

  wypisz('pasek: ${await RemoteInputChannel.showIndicator(
    text: 'Pisze: Test → ${cel.appLabel}',
    stop: 'Stop',
  )}');
  await Future<void>.delayed(const Duration(milliseconds: 500));

  final wynik = await kanal.apply(const [
    RemoteInputOp.insert('Chatt ąęł 124'),
    RemoteInputOp.backspace(),
    RemoteInputOp.insert('3'),
    RemoteInputOp.action(),
    RemoteInputOp.insert('koniec'),
  ]);
  wypisz('apply: applied=${wynik.applied} ${opis(wynik.target)}');

  wypisz('czekam 30 s na Stop na pasku');
  await stop.future
      .timeout(const Duration(seconds: 30), onTimeout: () => wypisz('bez Stopu'));
  await kanal.setSession(active: false);
  wypisz('--- koniec ---');
  exit(0);
}
