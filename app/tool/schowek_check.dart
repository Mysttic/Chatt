// Sprawdzenie wklejania ze schowka na żywym runnerze.
//
// Kanał `chatt/clipboard` żyje po stronie platformy (Windows:
// `windows/runner/chatt_clipboard.cpp`, Android: `ChattClipboard.kt`), więc
// `flutter test` go nie widzi: tam kanału po prostu nie ma. Ten skrypt
// podnosi prawdziwą aplikację, pyta schowek i wypisuje, co z niego wyszło.
//
//   cd app
//   flutter run -d windows -t tool/schowek_check.dart
//   flutter run -d emulator-5554 -t tool/schowek_check.dart
//
// Przed uruchomieniem trzeba coś do schowka włożyć. Na Windowsie:
//
//   plik z Eksploratora      Ctrl+C na pliku (albo: Set-Clipboard -Path plik)
//   obrazek bez pliku        Win+Shift+S, czyli wycinek ekranu
//   obrazek z przeglądarki   „Kopiuj obraz" na zdjęciu na stronie
//   zaznaczenie z arkusza    Ctrl+C na komórkach w Excelu
//
// Plik z Eksploratora ma wyjść ze ścieżką oryginału, bez kopiowania. Obrazek
// ma wyjść jako PNG w katalogu tymczasowym. Zaznaczenie z arkusza niesie
// w schowku bitmapę obok napisu i ma **nie** wyjść nic: inaczej zwykłe
// wklejenie liczb wysyłałoby rozmówcy ich zrzut.
//
// Na Androidzie do schowka wkłada się plik przez „Kopiuj" w aplikacji Pliki
// albo obrazek przez „Kopiuj obraz" w przeglądarce. Wszystko, co wyjdzie, jest
// kopią w `cache/wklejone/`, bo prawo do cudzego `content://` nie przeżywa
// zmiany zawartości schowka.
//
// Skrypt wypisuje nazwę, rozmiar i pierwsze bajty każdego pliku, żeby pusty
// plik albo obrazek pod mylącym rozszerzeniem było widać od razu.

import 'dart:io';

import 'package:chatt/core/clipboard.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show Clipboard, MethodChannel;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

/// Wypisanie widoczne wszędzie: `stdout` na Androidzie nie dociera do konsoli
/// `flutter run`, a `debugPrint` dociera na każdej platformie.
void wypisz(String linia) => debugPrint(linia);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Od Androida 10 schowek czyta wyłącznie aplikacja, której okno ma
  // skupienie, więc najpierw pokazujemy okno i czekamy, aż system je uzna.
  runApp(const SizedBox.shrink());
  await SchedulerBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(seconds: 2));

  wypisz('--- schowek ---');
  // „Nie ma kanału" i „nie ma czego wklejać" wyglądają z Darta tak samo:
  // jedno i drugie kończy się pustą listą. Tu rozróżniamy je wprost, bo
  // inaczej nieudana rejestracja kanału przeszłaby za pusty schowek.
  try {
    await const MethodChannel('chatt/clipboard').invokeMethod<bool>('hasFiles');
    wypisz('kanał chatt/clipboard:  odpowiada');
  } catch (blad) {
    wypisz('kanał chatt/clipboard:  ${blad.runtimeType}');
  }
  // Tekst czytamy flutterowym `Clipboard`, czyli tą samą drogą co zwykłe
  // wklejanie. Od Androida 10 to wraca puste, gdy okno nie ma skupienia,
  // więc widać po tym, czy w ogóle wolno nam zaglądać do schowka.
  final tekst = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  wypisz('tekst w schowku:        ${tekst == null ? 'brak' : '„$tekst”'}');
  wypisz('jest co wkleić:         ${await clipboardHasFiles()}');

  final paths = await pasteClipboardFiles(imageName: 'obraz.png');
  wypisz('ścieżek:                ${paths.length}');
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      wypisz('  BRAK PLIKU  $path');
      continue;
    }
    final bytes = file.readAsBytesSync();
    final head = bytes
        .take(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    wypisz('  ${p.basename(path)}  ${bytes.length} B  [$head]');
    wypisz('  $path');
  }
  wypisz('--- koniec ---');

  exit(0);
}
