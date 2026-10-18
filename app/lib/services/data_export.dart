import '../core/file_actions.dart';
import 'app_services.dart';

// Eksport danych aplikacji do jednego pliku ZIP (issue #50): rozmowy
// i urządzenia, ustawienia, historia pisania, dziennik aplikacji i, na
// życzenie, odebrane pliki. Bez kluczy: ani klucza tożsamości, ani kluczy
// sesji, ani klucza bazy. Plik eksportu nie jest zaszyfrowany.

/// Które części trafiają do eksportu.
class ExportParts {
  /// Ustawienia (bez klucza tożsamości), urządzenia i rozmowy z wiadomościami.
  final bool conversations;

  /// Historia pisania zdalną klawiaturą.
  final bool typing;

  /// Dziennik aplikacji.
  final bool appLog;

  /// Odebrane pliki, które jeszcze leżą na dysku.
  final bool files;

  const ExportParts({
    this.conversations = true,
    this.typing = true,
    this.appLog = true,
    this.files = false,
  });

  bool get isEmpty => !conversations && !typing && !appLog && !files;
}

/// Ile czego jest do eksportu, do okna wyboru.
class ExportEstimate {
  final int peers;
  final int conversations;
  final int messages;
  final int typingSessions;
  final int logEntries;

  /// Odebrane pliki, które jeszcze leżą na dysku, i ich łączny rozmiar.
  final int files;
  final int fileBytes;

  const ExportEstimate({
    required this.peers,
    required this.conversations,
    required this.messages,
    required this.typingSessions,
    required this.logEntries,
    required this.files,
    required this.fileBytes,
  });
}

/// Wynik zapisu archiwum.
class ExportResult {
  /// Gdzie leży archiwum.
  final String path;

  /// Rozmiar archiwum w bajtach.
  final int bytes;

  /// Ile odebranych plików weszło do archiwum.
  final int files;

  /// Pliki, które nie weszły (zniknęły z dysku, za duże, błąd odczytu),
  /// po nazwie.
  final List<String> skippedFiles;

  const ExportResult({
    required this.path,
    required this.bytes,
    required this.files,
    required this.skippedFiles,
  });
}

/// Nazwa pliku eksportu z chwili [now]: `chatt-export-2026-10-18-1530.zip`.
String exportFileName(DateTime now) {
  String dwa(int n) => n.toString().padLeft(2, '0');
  return 'chatt-export-${now.year}-${dwa(now.month)}-${dwa(now.day)}-'
      '${dwa(now.hour)}${dwa(now.minute)}.zip';
}

/// Liczy, ile czego jest do eksportu.
Future<ExportEstimate> estimateExport(AppServices services) =>
    throw UnimplementedError('estimateExport');

/// Zapisuje archiwum z częściami [parts] pod [zipPath].
Future<ExportResult> writeExport(
  AppServices services,
  String zipPath,
  ExportParts parts, {
  DateTime? now,
}) =>
    throw UnimplementedError('writeExport');

/// Eksport od początku do końca na tej platformie: Windows pyta, gdzie
/// zapisać, i pisze archiwum prosto tam; Android składa je w pamięci
/// podręcznej aplikacji i kopiuje do Pobranych (Android 10 i nowszy) albo
/// udostępnia, gdy kopiowanie nie jest dostępne. `where` jak w
/// [FileActions.saveCopy].
Future<({SaveResult result, String? where, ExportResult? export})>
    exportAndSave(AppServices services, ExportParts parts) =>
        throw UnimplementedError('exportAndSave');
