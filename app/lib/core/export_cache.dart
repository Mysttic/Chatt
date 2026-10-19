import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;

/// Podkatalog pamięci podręcznej, w którym Android składa archiwum eksportu
/// przed skopiowaniem do Pobranych albo oddaniem do „Udostępnij". Ta sama
/// nazwa stoi w `res/xml/file_paths.xml`: bez niej FileProvider nie wypuści
/// archiwum do innej aplikacji.
const String exportCacheDir = 'eksport';

/// Katalog nadrzędny dla [exportCacheDir] w testach. Ustawiony włącza
/// sprzątanie także poza Androidem.
@visibleForTesting
Future<Directory> Function()? debugExportCacheRoot;

/// Usuwa archiwa eksportu czekające w pamięci podręcznej aplikacji. Każde
/// to pełna, niezaszyfrowana kopia wybranych danych, a po „Udostępnij"
/// zostaje tam, bo aplikacja, która je przyjęła, czyta je dopiero później.
/// Z [olderThan] znikają tylko starsze od podanego wieku. Poza Androidem
/// nic nie robi: tam archiwum od razu powstaje w miejscu wybranym przez
/// użytkownika. Nic nie rzuca.
Future<void> clearExportCache({Duration? olderThan}) async {
  final korzen = debugExportCacheRoot;
  if (korzen == null && !Platform.isAndroid) return;
  try {
    final katalog = Directory(
      p.join((await (korzen ?? getTemporaryDirectory)()).path, exportCacheDir),
    );
    if (!katalog.existsSync()) return;
    final granica = olderThan == null
        ? null
        : DateTime.now().subtract(olderThan);
    for (final stare in katalog.listSync()) {
      try {
        if (granica == null || stare.statSync().modified.isBefore(granica)) {
          stare.deleteSync(recursive: true);
        }
      } catch (_) {
        // Plik zajęty: posprząta go następne wywołanie.
      }
    }
  } catch (_) {
    // Brak pamięci podręcznej albo kanału platformy: nie ma czego sprzątać.
  }
}
