import 'dart:io';

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

/// Rozszerzenia, dla których pokazujemy miniaturę. Lista jest krótka
/// świadomie: dekodowanie obrazka od obcego to powierzchnia ataku, więc
/// zostają tylko formaty, które Flutter obsługuje sam.
const _imageExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'};

/// Czy pod tą nazwą kryje się obrazek. Decyduje samo rozszerzenie — zawartość
/// czyta dopiero dekoder, i to wyłącznie dla plików, które użytkownik już
/// przyjął i ma na dysku.
bool isImageFile(String? name) =>
    name != null && _imageExtensions.contains(p.extension(name).toLowerCase());

/// Otwieranie odebranych plików systemowym skojarzeniem. Desktop: proces
/// systemowy. Android: własny kanał do [MainActivity], która wystawia plik
/// przez FileProvider jako content:// (zwykłej ścieżki od API 24 nie wolno
/// podać innej aplikacji). Bez wtyczek z pub.dev.
class FileActions {
  static const MethodChannel _android = MethodChannel('chatt/files');

  static bool get supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid;

  /// Otwiera plik domyślną aplikacją systemu.
  static Future<FileActionResult> open(String path) async {
    if (!File(path).existsSync()) return FileActionResult.missing;
    if (Platform.isAndroid) return _viaAndroid('open', path);
    if (Platform.isWindows) return _start('explorer.exe', [path]);
    if (Platform.isMacOS) return _start('open', [path]);
    if (Platform.isLinux) return _start('xdg-open', [path]);
    return FileActionResult.unsupported;
  }

  /// Desktop: pokazuje plik w menedżerze plików (otwieramy jego katalog —
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
