import 'dart:io';

import 'package:file_selector/file_selector.dart' show getSaveLocation;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path/path.dart' as p;

/// Wynik próby otwarcia pliku.
enum FileActionResult {
  ok,

  /// Pliku nie ma na dysku (skasowany po odebraniu).
  missing,

  /// Platforma bez systemowego "otwórz" dostępnego bez wtyczki (Android/iOS).
  unsupported,

  /// Nie udało się uruchomić procesu (brak xdg-open itp.).
  failed,
}

/// Wynik zapisania kopii odebranego pliku poza katalogiem aplikacji.
enum SaveResult {
  saved,

  /// Użytkownik zamknął okno zapisu.
  cancelled,

  /// Pliku nie ma na dysku.
  missing,

  /// Platforma nie ma gdzie zapisać (Android starszy niż 10).
  unsupported,

  /// Kopiowanie się wywaliło (brak miejsca, brak praw do katalogu).
  failed,
}

/// Rozszerzenia, dla których pokazujemy miniaturę. Lista jest krótka
/// świadomie: dekodowanie obrazka od obcego to powierzchnia ataku, więc
/// zostają tylko formaty, które Flutter obsługuje sam.
const _imageExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'};

/// Czy pod tą nazwą kryje się obrazek. Decyduje samo rozszerzenie, zawartość
/// czyta dopiero dekoder, i to wyłącznie dla plików, które użytkownik już
/// przyjął i ma na dysku.
bool isImageFile(String? name) =>
    name != null && _imageExtensions.contains(p.extension(name).toLowerCase());

/// Otwieranie odebranych plików systemowym skojarzeniem. Desktop: proces
/// systemowy. Android: własny kanał do [MainActivity], która wystawia plik
/// przez FileProvider jako content:// (zwykłej ścieżki od API 24 nie wolno
/// podać innej aplikacji). Bez wtyczek z pub.dev.
///
/// Na Androidzie ten sam kanał obsługuje też wybór plików do wysłania
/// ([pickFiles]).
class FileActions {
  static const MethodChannel _android = MethodChannel('chatt/files');

  static bool get supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid;

  /// Wybór plików do wysłania na Androidzie: systemowe okno, po nim kopia
  /// każdego zaznaczonego pliku w katalogu cache aplikacji i lista ścieżek
  /// do tych kopii. Pusta lista to anulowanie albo odmowa dostawcy treści.
  ///
  /// Własny kanał (`ChattFilePicker.kt` po stronie Kotlina), bo
  /// `file_selector` na Androidzie wczytuje cały zaznaczony plik do pamięci
  /// i przesyła bajty do Darta: przy 150 MB kończyło się to
  /// `OutOfMemoryError` i zabiciem aplikacji. Pulpit dalej używa `openFiles`
  /// z `file_selector`, tam okno zwraca same ścieżki.
  static Future<List<String>> pickFiles() async {
    try {
      final paths = await _android.invokeListMethod<String>('pick');
      return paths ?? const [];
    } catch (_) {
      // Brak kanału (test widgetowy), zamknięte okno albo wybór już otwarty.
      return const [];
    }
  }

  /// Otwiera plik domyślną aplikacją systemu.
  static Future<FileActionResult> open(String path) async {
    if (!File(path).existsSync()) return FileActionResult.missing;
    if (Platform.isAndroid) return _viaAndroid('open', path);
    if (Platform.isWindows) return _start('explorer.exe', [path]);
    if (Platform.isMacOS) return _start('open', [path]);
    if (Platform.isLinux) return _start('xdg-open', [path]);
    return FileActionResult.unsupported;
  }

  /// Desktop: pokazuje plik w menedżerze plików (otwieramy jego katalog, bo
  /// `explorer /select,` psuje się na ścieżkach ze spacjami).
  /// Android: nie ma menedżera plików do pokazania, więc udostępniamy plik
  /// dalej (share sheet).
  static Future<FileActionResult> revealInFolder(String path) async {
    if (!File(path).existsSync()) return FileActionResult.missing;
    if (Platform.isAndroid) return _viaAndroid('share', path);
    final dir = p.dirname(path);
    if (Platform.isWindows) return _start('explorer.exe', [dir]);
    if (Platform.isMacOS) return _start('open', ['-R', path]);
    if (Platform.isLinux) return _start('xdg-open', [dir]);
    return FileActionResult.unsupported;
  }

  /// Zapisuje kopię odebranego pliku tam, gdzie użytkownik będzie go szukał.
  ///
  /// Odebrane pliki leżą w katalogu aplikacji: żadna galeria ich nie widzi,
  /// a po odinstalowaniu znikają. Tutaj robimy z nich zwykły plik użytkownika:
  /// na Androidzie przez MediaStore (obrazki do Zdjęć, reszta do Pobranych,
  /// bez uprawnień od Androida 10), na pulpicie przez systemowe okno zapisu.
  ///
  /// [where] to miejsce do pokazania w komunikacie.
  static Future<({SaveResult result, String? where})> saveCopy(
      String path) async {
    if (!File(path).existsSync()) {
      return (result: SaveResult.missing, where: null);
    }

    if (Platform.isAndroid) {
      try {
        final katalog = await _android.invokeMethod<String>('save', {'path': path});
        return katalog == null
            // Android starszy niż 10 albo odmowa dostawcy treści. Zostaje
            // „Udostępnij", które i tak potrafi zapisać plik gdzie indziej.
            ? (result: SaveResult.unsupported, where: null)
            : (result: SaveResult.saved, where: katalog);
      } catch (_) {
        return (result: SaveResult.unsupported, where: null);
      }
    }

    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return (result: SaveResult.unsupported, where: null);
    }

    try {
      final gdzie = await getSaveLocation(suggestedName: p.basename(path));
      if (gdzie == null) return (result: SaveResult.cancelled, where: null);
      await File(path).copy(gdzie.path);
      return (result: SaveResult.saved, where: gdzie.path);
    } catch (_) {
      return (result: SaveResult.failed, where: null);
    }
  }

  static Future<FileActionResult> _viaAndroid(String method, String path) async {
    try {
      final ok = await _android.invokeMethod<bool>(method, {'path': path});
      return ok == true ? FileActionResult.ok : FileActionResult.failed;
    } catch (_) {
      // Brak kanału (np. test widgetowy) albo wyjątek po stronie Androida.
      return FileActionResult.unsupported;
    }
  }

  /// Odpalamy i zapominamy: explorer.exe potrafi zwrócić kod błędu mimo
  /// poprawnego otwarcia pliku, więc kod wyjścia nic nam nie mówi.
  static Future<FileActionResult> _start(
      String executable, List<String> arguments) async {
    try {
      await Process.start(executable, arguments,
          mode: ProcessStartMode.detached);
      return FileActionResult.ok;
    } catch (_) {
      return FileActionResult.failed;
    }
  }
}
