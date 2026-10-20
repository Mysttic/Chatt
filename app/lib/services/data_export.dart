import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart'
    show BooleanExpressionOperators, OrderingTerm;
import 'package:file_selector/file_selector.dart'
    show XTypeGroup, getSaveLocation;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;

import '../core/export_cache.dart';
import '../core/file_actions.dart';
import '../core/received_paths.dart' show diskToken;
import '../core/version.dart';
import '../core/zip_writer.dart';
import '../data/db.dart';
import '../network/transport.dart' show PeerProtocol;
import 'app_log.dart';
import 'app_services.dart';
import 'typing_journal.dart';

// Eksport danych aplikacji do jednego pliku ZIP (issue #50): rozmowy
// i urządzenia, ustawienia, historia pisania, dziennik aplikacji i, na
// życzenie, odebrane pliki. Bez kluczy: ani klucza tożsamości, ani kluczy
// sesji, ani klucza bazy. Plik eksportu nie jest zaszyfrowany.
//
// Podział pracy: odczyt z bazy idzie w izolacie głównym (drift i tak
// trzyma połączenie w swoim tle), a z wierszy powstają zwykłe dane: napisy,
// liczby, daty i ścieżki plików. Całą resztę, czyli JSON, wersje tekstowe,
// kompresję, czytanie odebranych plików i CRC, robi osobny izolat
// (`Isolate.run`), więc interfejs nie przycina się nawet przy gigabajtach.

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

/// Powody pominięcia odebranego pliku, w `skippedFiles` manifestu. Napisy,
/// bo czyta je narzędzie do analizy: nowe tylko dopisywać.
abstract final class ExportSkipReason {
  /// Pliku nie ma już na dysku.
  static const missing = 'missing';

  /// Plik nie mieści się w granicach formatu ZIP (4 GB na plik i na całe
  /// archiwum, 65 535 wpisów).
  static const tooLarge = 'tooLarge';

  /// Plik jest, ale odczyt się nie udał.
  static const readError = 'readError';

  /// Ścieżka z bazy wskazuje miejsce poza katalogiem odebranych plików.
  /// Eksport bierze wyłącznie pliki z tego katalogu: obok niego leżą baza
  /// i jej klucz.
  static const outsideReceivedDir = 'outsideReceivedDir';
}

/// Nazwa pliku eksportu z chwili [now]: `chatt-export-2026-10-18-1530.zip`.
String exportFileName(DateTime now) {
  String dwa(int n) => n.toString().padLeft(2, '0');
  return 'chatt-export-${now.year}-${dwa(now.month)}-${dwa(now.day)}-'
      '${dwa(now.hour)}${dwa(now.minute)}.zip';
}

/// Liczy, ile czego jest do eksportu.
Future<ExportEstimate> estimateExport(AppServices services) async {
  await services.typingJournal.flush();
  await services.log.flush();
  final db = services.db;

  Future<int> ile(String tabela) async => (await db
          .customSelect('SELECT COUNT(*) AS n FROM $tabela')
          .getSingle())
      .read<int>('n');

  var pliki = 0;
  var bajty = 0;
  final policzone = <String>{};
  for (final plik in await _odebranePliki(services)) {
    if (!_wKatalogu(services.receivedDir, plik.path)) continue;
    if (!policzone.add(p.canonicalize(plik.path))) continue;
    final stat = await FileStat.stat(plik.path);
    if (stat.type != FileSystemEntityType.file) continue;
    pliki++;
    bajty += stat.size;
  }

  return ExportEstimate(
    peers: await ile('peers'),
    conversations: await ile('conversations'),
    messages: await ile('messages'),
    typingSessions: await ile('typing_sessions'),
    logEntries: await ile('app_log'),
    files: pliki,
    fileBytes: bajty,
  );
}

/// Zapisuje archiwum z częściami [parts] pod [zipPath].
///
/// Najpierw zapisuje do bazy to, co historia pisania i dziennik trzymają
/// jeszcze w pamięci, żeby eksport miał wszystko. [maxBytes] i [maxEntries]
/// to granice formatu ZIP; testy podają mniejsze. Nieudany zapis kasuje
/// niedokończone archiwum, trafia do dziennika i leci dalej wyjątkiem.
Future<ExportResult> writeExport(
  AppServices services,
  String zipPath,
  ExportParts parts, {
  DateTime? now,
  int maxBytes = zipMaxBytes,
  int maxEntries = zipMaxEntries,
}) async {
  try {
    await services.typingJournal.flush();
    await services.log.flush();
    final zadanie = await _zbierz(
        services, zipPath, parts, now ?? DateTime.now(), maxBytes, maxEntries);
    final wynik = await _wIzolacie(zadanie);
    services.log.info(LogArea.app, _wpisDoDziennika(parts, wynik));
    return ExportResult(
      path: zipPath,
      bytes: wynik.bytes,
      files: wynik.files,
      skippedFiles: List.unmodifiable(wynik.skippedNames),
    );
  } catch (blad, slad) {
    services.log
        .error(LogArea.app, 'Data export failed', error: blad, stack: slad);
    rethrow;
  }
}

/// Eksport od początku do końca na tej platformie: Windows i Linux pytają,
/// gdzie zapisać, i piszą archiwum prosto tam; Android składa je w pamięci
/// podręcznej aplikacji i kopiuje do Pobranych (Android 10 i nowszy) albo
/// udostępnia, gdy kopiowanie nie jest dostępne. `where` jak w
/// [FileActions.saveCopy].
///
/// Wyniki:
/// - `saved` z `where`: archiwum leży w `where` (pulpit: pełna ścieżka,
///   Android: katalog w Pobranych);
/// - `saved` bez `where`: Android bez zapisu do Pobranych (starszy niż 10
///   albo odmowa dostawcy treści), archiwum poszło do systemowego okna
///   „Udostępnij";
/// - `cancelled`: użytkownik zamknął okno zapisu;
/// - `unsupported`: platforma bez eksportu;
/// - `failed`: zapis się nie udał (szczegóły w dzienniku aplikacji).
///
/// [confirmOverwrite] pyta, czy zastąpić istniejący plik, o który okno
/// zapisu nie zapytało (dopisane „.zip", Linux); bez niego taki plik zostaje,
/// a wynik to `cancelled`.
///
/// Parametry nazwane podmieniają kawałki platformy w testach: [android]
/// wybiera drogę, [chooseLocation] to okno zapisu na pulpicie (`null` to
/// anulowanie), [temporaryDirectory], [saveCopy] i [share] to Android.
Future<({SaveResult result, String? where, ExportResult? export})>
    exportAndSave(
  AppServices services,
  ExportParts parts, {
  DateTime? now,
  bool? android,
  Future<String?> Function(String suggestedName)? chooseLocation,
  Future<Directory> Function()? temporaryDirectory,
  Future<({SaveResult result, String? where})> Function(String path)?
      saveCopy,
  Future<FileActionResult> Function(String path)? share,
  Future<bool> Function(String path)? confirmOverwrite,
}) async {
  final kiedy = now ?? DateTime.now();
  if (android ?? Platform.isAndroid) {
    return _eksportNaAndroidzie(
      services,
      parts,
      kiedy,
      temporaryDirectory ?? getTemporaryDirectory,
      saveCopy ?? FileActions.saveCopy,
      share ?? FileActions.revealInFolder,
    );
  }
  if (android == null &&
      !Platform.isWindows &&
      !Platform.isLinux &&
      !Platform.isMacOS) {
    return (result: SaveResult.unsupported, where: null, export: null);
  }

  String? cel;
  try {
    cel = await (chooseLocation ?? _zapytajGdzie)(exportFileName(kiedy));
  } catch (blad, slad) {
    services.log.error(LogArea.app, 'Export save dialog failed',
        error: blad, stack: slad);
    return (result: SaveResult.failed, where: null, export: null);
  }
  if (cel == null || cel.isEmpty) {
    return (result: SaveResult.cancelled, where: null, export: null);
  }
  final dopisane = !cel.toLowerCase().endsWith('.zip');
  if (dopisane) cel = '$cel.zip';
  // Okno zapisu na Windows pyta o nadpisanie pliku pod nazwą bez „.zip";
  // plik z dopisanym rozszerzeniem widzi dopiero ta funkcja. Okno GTK na
  // Linuksie o nadpisanie nie pyta wcale.
  if ((dopisane || Platform.isLinux) &&
      FileSystemEntity.typeSync(cel) != FileSystemEntityType.notFound) {
    final zgoda = await (confirmOverwrite ?? (_) async => false)(cel);
    if (!zgoda) {
      return (result: SaveResult.cancelled, where: null, export: null);
    }
  }

  try {
    final wynik = await writeExport(services, cel, parts, now: kiedy);
    return (result: SaveResult.saved, where: cel, export: wynik);
  } catch (_) {
    // Błąd jest już w dzienniku (writeExport), niedokończony plik
    // skasowany.
    return (result: SaveResult.failed, where: null, export: null);
  }
}

/// Systemowe okno zapisu z podpowiedzianą nazwą i filtrem ZIP.
Future<String?> _zapytajGdzie(String nazwa) async => (await getSaveLocation(
      suggestedName: nazwa,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'ZIP', extensions: ['zip']),
      ],
    ))
        ?.path;

Future<({SaveResult result, String? where, ExportResult? export})>
    _eksportNaAndroidzie(
  AppServices services,
  ExportParts parts,
  DateTime kiedy,
  Future<Directory> Function() temporaryDirectory,
  Future<({SaveResult result, String? where})> Function(String path)
      saveCopy,
  Future<FileActionResult> Function(String path) share,
) async {
  const porazka = (result: SaveResult.failed, where: null, export: null);
  final Directory katalog;
  try {
    katalog =
        Directory(p.join((await temporaryDirectory()).path, exportCacheDir));
    // Poprzednie archiwa: skopiowane albo udostępnione już dawno, a każde
    // to pełna kopia danych w niezaszyfrowanym pliku.
    if (katalog.existsSync()) {
      for (final stare in katalog.listSync()) {
        _usun(stare);
      }
    }
    katalog.createSync(recursive: true);
  } catch (blad, slad) {
    services.log.error(LogArea.app, 'Export folder unavailable',
        error: blad, stack: slad);
    return porazka;
  }

  final sciezka = p.join(katalog.path, exportFileName(kiedy));
  final ExportResult wynik;
  try {
    wynik = await writeExport(services, sciezka, parts, now: kiedy);
  } catch (_) {
    // Błąd jest już w dzienniku (writeExport).
    return porazka;
  }

  final zapis = await saveCopy(sciezka);
  switch (zapis.result) {
    case SaveResult.saved:
      _usun(File(sciezka));
      return (result: SaveResult.saved, where: zapis.where, export: wynik);
    case SaveResult.unsupported:
      // Android starszy niż 10 albo odmowa dostawcy treści: archiwum idzie
      // do „Udostępnij" i zostaje w pamięci podręcznej, bo aplikacja, która
      // je przyjmie, czyta je dopiero po wyborze. Sprząta je następny
      // eksport, „Wyczyść historię", „Wyczyść historię pisania" i start
      // aplikacji, gdy ma ponad godzinę (patrz `clearExportCache`).
      final udostepnione = await share(sciezka);
      if (udostepnione == FileActionResult.ok) {
        return (result: SaveResult.saved, where: null, export: wynik);
      }
      services.log.warning(
          LogArea.app, 'Export share failed: ${udostepnione.name}');
      _usun(File(sciezka));
      return porazka;
    case SaveResult.cancelled:
    case SaveResult.missing:
    case SaveResult.failed:
      services.log
          .warning(LogArea.app, 'Export copy failed: ${zapis.result.name}');
      _usun(File(sciezka));
      return (
        result: zapis.result == SaveResult.cancelled
            ? SaveResult.cancelled
            : SaveResult.failed,
        where: null,
        export: null,
      );
  }
}

void _usun(FileSystemEntity cel) {
  try {
    cel.deleteSync(recursive: true);
  } catch (_) {
    // Plik zajęty albo już skasowany: posprząta go następny eksport.
  }
}

/// Jeden wpis w dzienniku o udanym eksporcie: części, liczby i rozmiar.
/// Bez nazw plików i ścieżek.
String _wpisDoDziennika(ExportParts parts, _Wynik wynik) {
  final czesci = [
    if (parts.conversations) 'conversations',
    if (parts.typing) 'typing',
    if (parts.appLog) 'appLog',
    if (parts.files) 'files',
  ];
  final liczby = [
    for (final MapEntry(:key, :value) in wynik.counts.entries) '$key=$value',
    if (parts.files) 'skippedFiles=${wynik.skippedNames.length}',
  ];
  return [
    'Data export written:',
    'parts=${czesci.isEmpty ? 'none' : czesci.join(',')}',
    ...liczby,
    'bytes=${wynik.bytes}',
  ].join(' ');
}

// --- Odczyt z bazy (izolat główny) -----------------------------------------

/// Kandydaci do części „odebrane pliki": przychodzące wiadomości-pliki ze
/// ścieżką na dysku, od najstarszej.
Future<List<_Plik>> _odebranePliki(AppServices services) async {
  final db = services.db;
  final wiersze = await (db.select(db.messages)
        ..where((m) =>
            m.direction.equalsValue(MessageDirection.incoming) &
            m.kind.equalsValue(MessageKind.file) &
            m.filePath.isNotNull())
        ..orderBy([
          (m) => OrderingTerm.asc(m.createdAt),
          (m) => OrderingTerm.asc(m.id),
        ]))
      .get();
  return [
    for (final m in wiersze)
      _Plik(
        messageGuid: m.messageGuid,
        name: (m.fileName == null || m.fileName!.isEmpty)
            ? _ostatniCzlon(m.filePath!)
            : m.fileName!,
        path: m.filePath!,
      ),
  ];
}

/// Czy [sciezka] leży w katalogu odebranych plików.
bool _wKatalogu(String katalog, String sciezka) =>
    p.isWithin(p.canonicalize(katalog), p.canonicalize(sciezka));

String _ostatniCzlon(String sciezka) =>
    sciezka.split(RegExp(r'[\\/]')).lastWhere((c) => c.isNotEmpty,
        orElse: () => sciezka);

Future<_Zadanie> _zbierz(
  AppServices services,
  String zipPath,
  ExportParts parts,
  DateTime kiedy,
  int maxBytes,
  int maxEntries,
) async {
  final db = services.db;

  Map<String, Object?>? ustawienia;
  var urzadzenia = const <Map<String, Object?>>[];
  var rozmowy = const <Map<String, Object?>>[];
  var wiadomosci = 0;
  if (parts.conversations) {
    final setting = await db.getSettings();
    ustawienia = setting == null ? null : _ustawienia(setting);
    final peers = await (db.select(db.peers)
          ..orderBy([(p) => OrderingTerm.asc(p.id)]))
        .get();
    urzadzenia = [for (final peer in peers) _urzadzenie(peer)];
    final rozmowcy = {for (final peer in peers) peer.id: peer};
    final konwersacje = await (db.select(db.conversations)
          ..orderBy([(c) => OrderingTerm.asc(c.id)]))
        .get();
    final wiersze = await (db.select(db.messages)
          ..orderBy([
            (m) => OrderingTerm.asc(m.createdAt),
            (m) => OrderingTerm.asc(m.id),
          ]))
        .get();
    wiadomosci = wiersze.length;
    final poRozmowie = <int, List<Map<String, Object?>>>{};
    for (final m in wiersze) {
      (poRozmowie[m.conversationId] ??= []).add(_wiadomosc(m));
    }
    rozmowy = [
      for (final c in konwersacje)
        {
          'id': c.id,
          'peer': switch (rozmowcy[c.peerId]) {
            final peer? => {
                'guid': peer.guid,
                'name': peer.name,
                'alias': peer.alias,
              },
            null => null,
          },
          'createdAt': c.createdAt,
          'updatedAt': c.updatedAt,
          'messages': poRozmowie[c.id] ?? const <Map<String, Object?>>[],
        },
    ];
  }

  var sesje = const <_Sesja>[];
  if (parts.typing) {
    final kawalki = <int, List<_Kawalek>>{};
    for (final e in await db.allTypingEntries()) {
      (kawalki[e.sessionId] ??= []).add(_Kawalek(
        at: e.at,
        app: e.app,
        appLabel: e.appLabel,
        field: e.field,
        status: e.status,
        chars: e.chars,
        hidden: e.masked,
        ops: e.ops,
      ));
    }
    sesje = [
      for (final s in await db.allTypingSessions())
        _Sesja(
          inputId: s.inputId,
          direction: s.direction.name,
          peerGuid: s.peerGuid,
          peerName: s.peerName,
          startedAt: s.startedAt,
          endedAt: s.endedAt,
          result: s.result,
          endReason: s.endReason,
          entries: kawalki[s.id] ?? const [],
        ),
    ];
  }

  var dziennik = const <_WpisDziennika>[];
  if (parts.appLog) {
    dziennik = [
      for (final e in await db.allLogEntries())
        _WpisDziennika(
          atMs: e.atMs,
          level: e.level.name,
          area: e.area,
          message: e.message,
          details: e.details,
        ),
    ];
  }

  final pliki = parts.files ? await _odebranePliki(services) : const <_Plik>[];

  return _Zadanie(
    zipPath: zipPath,
    maxBytes: maxBytes,
    maxEntries: maxEntries,
    now: kiedy,
    appVersion: appVersion,
    deviceGuid: services.identity.guid,
    deviceName: services.identity.name,
    conversations: parts.conversations,
    typing: parts.typing,
    appLog: parts.appLog,
    files: parts.files,
    settings: ustawienia,
    devices: urzadzenia,
    chats: rozmowy,
    messageCount: wiadomosci,
    typingSessions: sesje,
    log: dziennik,
    receivedDir: services.receivedDir,
    candidates: pliki,
  );
}

/// Ustawienia wypisane pole po polu. Lista jest zamknięta celowo: nowa
/// kolumna (choćby kolejny klucz) trafia do eksportu dopiero wtedy, gdy ktoś
/// ją tu świadomie dopisze. Klucza tożsamości tu nie ma i nie będzie.
Map<String, Object?> _ustawienia(Setting s) => {
      'deviceGuid': s.deviceGuid,
      'nickname': s.nickname,
      'welcomeMessage': s.welcomeMessage,
      'theme': s.theme.name,
      'style': s.style.name,
      'language': s.language.name,
      'tcpPort': s.tcpPort,
      'background': s.background,
      'retentionDays': s.retentionDays,
      'updateChecks': s.updateChecks,
      'lastUpdateCheck': s.lastUpdateCheck,
      'linkPreviews': s.linkPreviews,
      'wifiEnabled': s.wifiEnabled,
      'bluetoothEnabled': s.bluetoothEnabled,
      'keyboardEnabled': s.keyboardEnabled,
      'remoteInputReceive': s.remoteInputReceive,
      'typingHistory': s.typingHistory,
    };

/// Urządzenie wypisane pole po polu, z tego samego powodu co ustawienia.
/// Bez klucza sesji z dawnych parowań; klucz publiczny jest jawny z natury.
Map<String, Object?> _urzadzenie(Peer peer) => {
      'id': peer.id,
      'guid': peer.guid,
      'name': peer.name,
      'alias': peer.alias,
      'welcomeMessage': peer.welcomeMessage,
      'host': peer.host,
      'port': peer.port,
      'btAddress': peer.btAddress,
      'lastProtocol': switch (peer.lastProtocol) {
        final i? when i >= 0 && i < PeerProtocol.values.length =>
          PeerProtocol.values[i].name,
        _ => null,
      },
      'verified': peer.verified,
      'publicKey': peer.publicKey,
      'autoAccept': peer.autoAccept,
      'remoteInput': peer.remoteInput,
      'firstSeen': peer.firstSeen,
      'lastSeen': peer.lastSeen,
    };

Map<String, Object?> _wiadomosc(Message m) => {
      'guid': m.messageGuid,
      'direction': m.direction.name,
      'status': m.status.name,
      'kind': m.kind.name,
      'body': m.body,
      if (m.kind == MessageKind.file || m.fileName != null)
        'file': <String, Object?>{
          'name': m.fileName,
          'size': m.fileSize,
          'path': m.filePath,
        },
      'createdAt': m.createdAt,
      'deliveredAt': m.deliveredAt,
      'readAt': m.readAt,
      'restoredAt': m.restoredAt,
    };

// --- Dane dla izolatu --------------------------------------------------------
//
// Same napisy, liczby, flagi, daty i listy: wszystko przechodzi do izolatu
// kopią, bez obiektów bazy, bez wyliczeń i bez [AppServices].

final class _Plik {
  final String messageGuid;
  final String name;
  final String path;

  const _Plik({
    required this.messageGuid,
    required this.name,
    required this.path,
  });
}

final class _Kawalek {
  final DateTime at;
  final String app;
  final String appLabel;
  final String field;
  final String status;
  final int chars;
  final bool hidden;

  /// Operacje tak, jak leżą w bazie (JSON z `TypingOp.encode`).
  final String ops;

  const _Kawalek({
    required this.at,
    required this.app,
    required this.appLabel,
    required this.field,
    required this.status,
    required this.chars,
    required this.hidden,
    required this.ops,
  });
}

final class _Sesja {
  final String inputId;
  final String direction;
  final String peerGuid;
  final String peerName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String result;
  final String? endReason;
  final List<_Kawalek> entries;

  const _Sesja({
    required this.inputId,
    required this.direction,
    required this.peerGuid,
    required this.peerName,
    required this.startedAt,
    required this.endedAt,
    required this.result,
    required this.endReason,
    required this.entries,
  });
}

final class _WpisDziennika {
  final int atMs;
  final String level;
  final String area;
  final String message;
  final String? details;

  const _WpisDziennika({
    required this.atMs,
    required this.level,
    required this.area,
    required this.message,
    required this.details,
  });
}

final class _Zadanie {
  final String zipPath;
  final int maxBytes;
  final int maxEntries;
  final DateTime now;
  final String appVersion;
  final String deviceGuid;
  final String deviceName;
  final bool conversations;
  final bool typing;
  final bool appLog;
  final bool files;
  final Map<String, Object?>? settings;
  final List<Map<String, Object?>> devices;

  /// Rozmowy gotowe do JSON; daty zostają obiektami [DateTime] i zamieniają
  /// się w napisy dopiero w izolacie.
  final List<Map<String, Object?>> chats;
  final int messageCount;
  final List<_Sesja> typingSessions;
  final List<_WpisDziennika> log;
  final String receivedDir;
  final List<_Plik> candidates;

  const _Zadanie({
    required this.zipPath,
    required this.maxBytes,
    required this.maxEntries,
    required this.now,
    required this.appVersion,
    required this.deviceGuid,
    required this.deviceName,
    required this.conversations,
    required this.typing,
    required this.appLog,
    required this.files,
    required this.settings,
    required this.devices,
    required this.chats,
    required this.messageCount,
    required this.typingSessions,
    required this.log,
    required this.receivedDir,
    required this.candidates,
  });
}

final class _Wynik {
  final int bytes;
  final int files;
  final List<String> skippedNames;
  final Map<String, int> counts;

  const _Wynik({
    required this.bytes,
    required this.files,
    required this.skippedNames,
    required this.counts,
  });
}

/// Osobna funkcja, żeby domknięcie dla izolatu trzymało wyłącznie
/// [zadanie]: domknięcie z [writeExport] ciągnęłoby za sobą jego kontekst,
/// a w nim [AppServices], którego nie da się przesłać.
Future<_Wynik> _wIzolacie(_Zadanie zadanie) =>
    Isolate.run(() => _zapiszArchiwum(zadanie), debugName: 'chatt-export');

// --- Zapis archiwum (izolat eksportu) ----------------------------------------

/// Odebrany plik zaplanowany do archiwum.
final class _Zaplanowany {
  final _Plik plik;
  final String archiveName;
  final int size;

  /// Wiadomości wskazujące ten sam plik na dysku.
  final List<String> guids;

  _Zaplanowany(this.plik, this.archiveName, this.size)
      : guids = [plik.messageGuid];
}

_Wynik _zapiszArchiwum(_Zadanie z) {
  final zip =
      ZipWriter(z.zipPath, maxBytes: z.maxBytes, maxEntries: z.maxEntries);
  try {
    final kiedy = z.now;
    final liczby = <String, int>{};

    zip.addText('README.txt', _readme(z), modified: kiedy);

    if (z.conversations) {
      zip.addText('settings.json', _json(z.settings), modified: kiedy);
      zip.addText('devices.json', _json(z.devices), modified: kiedy);
      liczby['devices'] = z.devices.length;
      liczby['conversations'] = z.chats.length;
      liczby['messages'] = z.messageCount;
    }

    if (z.typing) {
      final sesje = [for (final s in z.typingSessions) _sesjaJson(s)];
      zip.addText('typing-history.json', _json(sesje), modified: kiedy);
      zip.addText('typing-history.txt', _historiaTekstem(z), modified: kiedy);
      liczby['typingSessions'] = z.typingSessions.length;
      liczby['typingEntries'] =
          z.typingSessions.fold(0, (suma, s) => suma + s.entries.length);
    }

    if (z.appLog) {
      zip.addText('app-log.json', _json([for (final e in z.log) _wpisJson(e)]),
          modified: kiedy);
      zip.addText('app-log.txt', _dziennikTekstem(z.log), modified: kiedy);
      liczby['logEntries'] = z.log.length;
    }

    // Odebrane pliki. Ich wynik decyduje o `archivePath` w rozmowach
    // i o `skippedFiles` w manifeście, więc te dwa wpisy idą po nich,
    // a miejsce na nie jest zarezerwowane z góry.
    final pominiete = <({String name, String reason})>[];
    final zaplanowane = <_Zaplanowany>[];
    if (z.files) _zaplanujPliki(z, zaplanowane, pominiete);

    final sciezkiWArchiwum = <String, String>{};
    for (final plan in zaplanowane) {
      for (final guid in plan.guids) {
        sciezkiWArchiwum[guid] = plan.archiveName;
      }
    }
    List<int>? rozmowy =
        z.conversations ? utf8.encode(_rozmowyJson(z, sciezkiWArchiwum)) : null;

    var dolaczone = 0;
    var bajtyPlikow = 0;
    if (z.files) {
      // Najgorszy manifest: wszystkie zaplanowane pliki pominięte z
      // najdłuższym powodem, a liczby w pełnej długości.
      final najgorszyManifest = utf8.encode(_manifest(z, {
        ...liczby,
        'files': zaplanowane.length,
        'fileBytes': zaplanowane.fold(0, (suma, plan) => suma + plan.size),
      }, [
        ...pominiete,
        for (final plan in zaplanowane)
          (name: plan.plik.name, reason: ExportSkipReason.outsideReceivedDir),
      ])).length;
      final rezerwa = (rozmowy == null
              ? 0
              : ZipWriter.entryBound('conversations.json', rozmowy.length,
                  compress: true)) +
          ZipWriter.entryBound('manifest.json', najgorszyManifest + 64,
              compress: true);
      final wpisyPo = (rozmowy == null ? 0 : 1) + 1;

      final nieudane = <String>{};
      for (final plan in zaplanowane) {
        String? powod;
        try {
          zip.addFile(plan.archiveName, plan.plik.path,
              reserveBytes: rezerwa, reserveEntries: wpisyPo);
          dolaczone++;
          bajtyPlikow += plan.size;
        } on ZipLimitExceeded {
          powod = ExportSkipReason.tooLarge;
        } on ZipSourceException {
          powod = File(plan.plik.path).existsSync()
              ? ExportSkipReason.readError
              : ExportSkipReason.missing;
        }
        if (powod != null) {
          pominiete.add((name: plan.plik.name, reason: powod));
          nieudane.addAll(plan.guids);
        }
      }
      liczby['files'] = dolaczone;
      liczby['fileBytes'] = bajtyPlikow;

      if (nieudane.isNotEmpty && rozmowy != null) {
        sciezkiWArchiwum.removeWhere((guid, _) => nieudane.contains(guid));
        rozmowy = utf8.encode(_rozmowyJson(z, sciezkiWArchiwum));
      }
    }

    if (rozmowy != null) {
      zip.addBytes('conversations.json', rozmowy, modified: kiedy);
    }
    zip.addText('manifest.json', _manifest(z, liczby, pominiete),
        modified: kiedy);
    final bajty = zip.close();

    return _Wynik(
      bytes: bajty,
      files: dolaczone,
      skippedNames: [for (final s in pominiete) s.name],
      counts: liczby,
    );
  } catch (_) {
    zip.abort();
    rethrow;
  }
}

/// Plan części „odebrane pliki": co jest na dysku, w katalogu odebranych,
/// i pod jaką nazwą trafi do archiwum. Resztę od razu dopisuje do
/// [pominiete]. Kilka wiadomości ze ścieżką do tego samego pliku daje jeden
/// wpis w archiwum.
void _zaplanujPliki(
  _Zadanie z,
  List<_Zaplanowany> zaplanowane,
  List<({String name, String reason})> pominiete,
) {
  final poSciezce = <String, _Zaplanowany>{};
  final zajete = <String>{};
  for (final plik in z.candidates) {
    final klucz = p.canonicalize(plik.path);
    final juz = poSciezce[klucz];
    if (juz != null) {
      juz.guids.add(plik.messageGuid);
      continue;
    }
    if (!_wKatalogu(z.receivedDir, plik.path)) {
      pominiete
          .add((name: plik.name, reason: ExportSkipReason.outsideReceivedDir));
      continue;
    }
    final stat = FileStat.statSync(plik.path);
    if (stat.type != FileSystemEntityType.file) {
      pominiete.add((name: plik.name, reason: ExportSkipReason.missing));
      continue;
    }
    final plan = _Zaplanowany(
        plik, _nazwaWArchiwum(plik, zajete), stat.size);
    poSciezce[klucz] = plan;
    zaplanowane.add(plan);
  }
}

/// `files/<8 znaków hex>_<nazwa>`: przedrostek to ten sam skrót
/// identyfikatora wiadomości, którym zaczyna się nazwa pliku na dysku.
/// Nazwa jest oczyszczona ze znaków zakazanych na Windows i skrócona do
/// rozsądnej długości; powtórka dostaje numer.
String _nazwaWArchiwum(_Plik plik, Set<String> zajete) {
  final przedrostek = diskToken(plik.messageGuid).substring(0, 8);
  final nazwa = _bezpiecznaNazwa(plik.name);
  final kropka = nazwa.lastIndexOf('.');
  final rdzen = kropka > 0 ? nazwa.substring(0, kropka) : nazwa;
  final rozszerzenie = kropka > 0 ? nazwa.substring(kropka) : '';
  var kandydat = 'files/${przedrostek}_$nazwa';
  for (var n = 2; !zajete.add(kandydat.toLowerCase()); n++) {
    kandydat = 'files/${przedrostek}_$rdzen ($n)$rozszerzenie';
  }
  return kandydat;
}

String _bezpiecznaNazwa(String nazwa) {
  var czysta = _ostatniCzlon(nazwa)
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f\x7f]'), '_')
      .trim();
  // Windows obcina kropki i spacje na końcu nazwy.
  czysta = czysta.replaceAll(RegExp(r'[. ]+$'), '');
  if (czysta.isEmpty) czysta = 'file';
  // Systemy plików trzymają do 255 bajtów na nazwę, a przedrostek zajmuje
  // dziewięć. Skracamy rdzeń, rozszerzenie zostaje.
  const najwiecej = 200;
  if (utf8.encode(czysta).length <= najwiecej) return czysta;
  final kropka = czysta.lastIndexOf('.');
  final rozszerzenie =
      kropka > 0 && czysta.length - kropka <= 16 ? czysta.substring(kropka) : '';
  final znaki = czysta
      .substring(0, czysta.length - rozszerzenie.length)
      .runes
      .toList();
  final budzet = najwiecej - utf8.encode(rozszerzenie).length;
  var dlugosc = 0;
  var ile = 0;
  for (final znak in znaki) {
    final bajty = utf8.encode(String.fromCharCode(znak)).length;
    if (dlugosc + bajty > budzet) break;
    dlugosc += bajty;
    ile++;
  }
  return String.fromCharCodes(znaki.take(ile)) + rozszerzenie;
}

// --- JSON ---------------------------------------------------------------------

final _koder = JsonEncoder.withIndent('  ', _doJson);

Object? _doJson(dynamic wartosc) => wartosc is DateTime
    ? _iso(wartosc)
    : throw JsonUnsupportedObjectError(wartosc);

String _json(Object? wartosc) => _koder.convert(wartosc);

/// Rozmowy z `archivePath` przy plikach, które są w archiwum.
String _rozmowyJson(_Zadanie z, Map<String, String> sciezkiWArchiwum) {
  for (final rozmowa in z.chats) {
    for (final m in rozmowa['messages']! as List<Map<String, Object?>>) {
      final plik = m['file'];
      if (plik is! Map<String, Object?>) continue;
      final wArchiwum = sciezkiWArchiwum[m['guid']];
      if (wArchiwum == null) {
        plik.remove('archivePath');
      } else {
        plik['archivePath'] = wArchiwum;
      }
    }
  }
  return _json(z.chats);
}

String _manifest(_Zadanie z, Map<String, int> liczby,
        List<({String name, String reason})> pominiete) =>
    _json({
      'format': 'chatt-export',
      'formatVersion': 1,
      'appVersion': z.appVersion,
      'exportedAt': z.now,
      'device': {'guid': z.deviceGuid, 'name': z.deviceName},
      'parts': {
        'conversations': z.conversations,
        'typing': z.typing,
        'appLog': z.appLog,
        'files': z.files,
      },
      'counts': liczby,
      'skippedFiles': [
        for (final s in pominiete) {'name': s.name, 'reason': s.reason},
      ],
    });

/// Operacje kawałka; wiersz, którego nie da się odczytać, daje pustą listę.
List<TypingOp> _operacje(_Kawalek k) => TypingOp.decode(k.ops);

/// Kawałki, które coś wpisały (albo próbowały), składają się na odtworzony
/// tekst sesji.
bool _doTranskrypcji(_Kawalek k) =>
    k.status == TypingStatus.typed.name ||
    k.status == TypingStatus.notTyped.name;

String _transkrypcja(_Sesja s) => reconstructTyping([
      for (final k in s.entries)
        if (_doTranskrypcji(k)) ..._operacje(k),
    ]);

Map<String, Object?> _sesjaJson(_Sesja s) => {
      'inputId': s.inputId,
      'direction': s.direction,
      'peer': {'guid': s.peerGuid, 'name': s.peerName},
      'startedAt': s.startedAt,
      'endedAt': s.endedAt,
      'result': s.result,
      'endReason': s.endReason,
      'entries': [for (final k in s.entries) _kawalekJson(k)],
      'transcript': _transkrypcja(s),
    };

Map<String, Object?> _kawalekJson(_Kawalek k) {
  final ops = _operacje(k);
  return {
    'at': k.at,
    'app': k.app,
    'appLabel': k.appLabel,
    'field': k.field,
    'status': k.status,
    'chars': k.chars,
    'hidden': k.hidden,
    'ops': [for (final op in ops) op.toJson()],
    'text': describeTypingOps(ops),
  };
}

Map<String, Object?> _wpisJson(_WpisDziennika e) => {
      'at': _iso(DateTime.fromMillisecondsSinceEpoch(e.atMs), millis: true),
      'level': e.level,
      'area': e.area,
      'message': e.message,
      if (e.details != null) 'details': e.details,
    };

// --- Wersje tekstowe ------------------------------------------------------------

String _dwa(int n) => n.toString().padLeft(2, '0');

String _przesuniecie(DateTime t) {
  final minuty = t.timeZoneOffset.inMinutes;
  final znak = minuty < 0 ? '-' : '+';
  final ile = minuty.abs();
  return '$znak${_dwa(ile ~/ 60)}:${_dwa(ile % 60)}';
}

String _dataICzas(DateTime t, String separator, bool millis) =>
    '${t.year.toString().padLeft(4, '0')}-${_dwa(t.month)}-${_dwa(t.day)}'
    '$separator${_dwa(t.hour)}:${_dwa(t.minute)}:${_dwa(t.second)}'
    '${millis ? '.${t.millisecond.toString().padLeft(3, '0')}' : ''}';

/// ISO-8601 w czasie lokalnym z przesunięciem względem UTC:
/// `2026-10-18T15:30:12+02:00`, z [millis] `2026-10-18T15:30:12.345+02:00`.
String _iso(DateTime kiedy, {bool millis = false}) {
  final t = kiedy.toLocal();
  return '${_dataICzas(t, 'T', millis)}${_przesuniecie(t)}';
}

/// Czas lokalny do plików .txt: `2026-10-18 15:30:12`.
String _lokalnie(DateTime kiedy, {bool millis = false}) =>
    _dataICzas(kiedy.toLocal(), ' ', millis);

String _wciecie(String tekst, String wciecie) =>
    tekst.split('\n').map((wiersz) => '$wciecie$wiersz').join('\n');

String _historiaTekstem(_Zadanie z) {
  final b = StringBuffer()
    ..writeln('Chatt typing history')
    ..writeln('Device: ${z.deviceName} (${z.deviceGuid})')
    ..writeln('Exported: ${_lokalnie(z.now)} ${_przesuniecie(z.now.toLocal())}')
    ..writeln('Times are local time of this device. Hidden text (password '
        'fields and fields of unknown kind) appears as • with the number of '
        'characters.')
    ..writeln('Sessions: ${z.typingSessions.length}');
  final ile = z.typingSessions.length;
  for (var i = 0; i < ile; i++) {
    final s = z.typingSessions[i];
    final rozmowca = _jednaLinia(s.peerName);
    final kierunek = s.direction == MessageDirection.outgoing.name
        ? 'outgoing: this device typed on $rozmowca'
        : 'incoming: $rozmowca typed on this device';
    final koniec = s.endedAt == null
        ? 'still open'
        : '${_lokalnie(s.endedAt!)}'
            '${s.endReason == null ? '' : ' (${s.endReason})'}';
    b
      ..writeln()
      ..writeln('Session ${i + 1} of $ile')
      ..writeln('  Started:    ${_lokalnie(s.startedAt)}')
      ..writeln('  Ended:      $koniec')
      ..writeln('  Direction:  $kierunek')
      ..writeln('  Peer:       $rozmowca (${s.peerGuid})')
      ..writeln('  Input:      ${s.inputId}')
      ..writeln('  Result:     ${s.result}');
    if (s.entries.isEmpty) {
      b.writeln('  Entries:    none');
      continue;
    }
    b.writeln('  Entries:');
    for (final k in s.entries) {
      final etykieta = _jednaLinia(k.appLabel);
      final pakiet = _jednaLinia(k.app);
      final aplikacja = switch ((etykieta.isNotEmpty, pakiet.isNotEmpty)) {
        (true, true) => '$etykieta ($pakiet)',
        (true, false) => etykieta,
        (false, true) => pakiet,
        (false, false) => '(unknown app)',
      };
      b
        ..writeln('    ${_lokalnie(k.at)}  $aplikacja  field ${k.field}  '
            '${k.status}  ${k.chars} chars${k.hidden ? '  hidden' : ''}')
        ..writeln(_wciecie(describeTypingOps(_operacje(k)), '      '));
    }
    final tekst = _transkrypcja(s);
    if (tekst.isNotEmpty) {
      b
        ..writeln('  Transcript:')
        ..writeln(_wciecie(tekst, '    '));
    }
  }
  return b.toString();
}

const _poziomy = {'info': 'INFO', 'warning': 'WARN', 'error': 'ERROR'};

/// Napis z sieci (nazwa rozmówcy, nazwa aplikacji) albo z dziennika w jednej
/// linii wersji tekstowej: znak sterujący, zwłaszcza nowa linia, udawałby
/// osobny wpis albo osobne pole.
String _jednaLinia(String tekst) =>
    tekst.replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ');

String _dziennikTekstem(List<_WpisDziennika> wpisy) {
  final b = StringBuffer();
  for (final e in wpisy) {
    final kiedy = DateTime.fromMillisecondsSinceEpoch(e.atMs);
    final poziom = _poziomy[e.level] ?? e.level.toUpperCase();
    b.writeln('${_lokalnie(kiedy, millis: true)} ${poziom.padRight(5)} '
        '${e.area}  ${_jednaLinia(e.message)}');
    final szczegoly = e.details;
    if (szczegoly != null && szczegoly.isNotEmpty) {
      b.writeln(_wciecie(szczegoly.trimRight(), '    '));
    }
  }
  return b.toString();
}

String _readme(_Zadanie z) {
  final kiedy = '${_lokalnie(z.now)} ${_przesuniecie(z.now.toLocal())}';
  String takNie(bool v, String tak, String nie) => v ? tak : nie;

  final zawartoscEn = <(String, String)>[
    ('README.txt', 'this file'),
    ('manifest.json',
        'format, app version, export time, device, chosen parts, counts and skipped files'),
    if (z.conversations) ...[
      ('settings.json', 'settings of this device'),
      ('devices.json', 'known devices (contacts)'),
      ('conversations.json', 'conversations with their messages'),
    ],
    if (z.typing) ...[
      ('typing-history.json', 'remote keyboard sessions with every typing step'),
      ('typing-history.txt', 'the same in readable form'),
    ],
    if (z.appLog) ...[
      ('app-log.json', 'app log for diagnostics (up to 30 days)'),
      ('app-log.txt', 'the same, one line per entry'),
    ],
    if (z.files)
      ('files/',
          z.conversations
              ? 'received files; conversations.json points to each one with "archivePath"'
              : 'received files'),
  ];
  final zawartoscPl = <(String, String)>[
    ('README.txt', 'ten plik'),
    ('manifest.json',
        'format, wersja aplikacji, czas eksportu, urządzenie, wybrane części, liczby i pominięte pliki'),
    if (z.conversations) ...[
      ('settings.json', 'ustawienia tego urządzenia'),
      ('devices.json', 'znane urządzenia (kontakty)'),
      ('conversations.json', 'rozmowy z wiadomościami'),
    ],
    if (z.typing) ...[
      ('typing-history.json', 'sesje zdalnej klawiatury z każdym krokiem pisania'),
      ('typing-history.txt', 'to samo w czytelnej postaci'),
    ],
    if (z.appLog) ...[
      ('app-log.json', 'dziennik aplikacji do diagnostyki (do 30 dni)'),
      ('app-log.txt', 'to samo, jeden wiersz na wpis'),
    ],
    if (z.files)
      ('files/',
          z.conversations
              ? 'odebrane pliki; conversations.json wskazuje każdy z nich polem "archivePath"'
              : 'odebrane pliki'),
  ];
  String lista(List<(String, String)> pozycje) => pozycje
      .map((pozycja) => '  ${pozycja.$1.padRight(21)} ${pozycja.$2}')
      .join('\n');

  return '''
Chatt data export
App version: ${z.appVersion}
Exported: $kiedy
Device: ${z.deviceName} (${z.deviceGuid})

THIS FILE IS NOT ENCRYPTED. Anyone who opens it can read everything inside.
Keep it in a safe place and delete it when it is no longer needed. Private
keys stay on the device: the identity key, session keys and the database key
are never part of an export.

Parts in this export:
  conversations, devices and settings: ${takNie(z.conversations, 'yes', 'no')}
  typing history: ${takNie(z.typing, 'yes', 'no')}
  app log: ${takNie(z.appLog, 'yes', 'no')}
  received files: ${takNie(z.files, 'yes', 'no')}

Contents:
${lista(zawartoscEn)}

Format notes:
  All text files are UTF-8. JSON dates follow ISO-8601 with the UTC offset of
  this device; app log entries carry milliseconds. The .txt files show local
  time.
  Enumerations appear as names, for example "incoming", "delivered",
  "password".
  Typing history: "direction" outgoing means this device typed on the other
  device, incoming means the other device typed on this one. "ops" lists the
  operations: {"t":"insert","s":"text"}, {"t":"insert","hidden":5} for five
  hidden characters, {"t":"bs","n":2} for Backspace, {"t":"del","n":1} for
  Delete, {"t":"action"} for Enter. Text typed into password fields and
  fields of unknown kind is stored as a character count and appears as •.
  "transcript" rebuilds the typed text from the operations with status typed
  or notTyped. It is an approximation: the field may have held text before
  the session and the cursor may have moved.
  Skipped files ("skippedFiles" in manifest.json) carry a reason: missing
  (gone from the disk), tooLarge (over the ZIP limits of 4 GB or 65535
  entries), readError, outsideReceivedDir (a path outside the folder of
  received files).


Eksport danych Chatt
Wersja aplikacji: ${z.appVersion}
Data eksportu: $kiedy
Urządzenie: ${z.deviceName} (${z.deviceGuid})

TEN PLIK NIE JEST ZASZYFROWANY. Każdy, kto go otworzy, przeczyta całą
zawartość. Trzymaj go w bezpiecznym miejscu i usuń, gdy przestanie być
potrzebny. Klucze prywatne zostają na urządzeniu: klucz tożsamości, klucze
sesji i klucz bazy nigdy nie trafiają do eksportu.

Części w tym eksporcie:
  rozmowy, urządzenia i ustawienia: ${takNie(z.conversations, 'tak', 'nie')}
  historia pisania: ${takNie(z.typing, 'tak', 'nie')}
  dziennik aplikacji: ${takNie(z.appLog, 'tak', 'nie')}
  odebrane pliki: ${takNie(z.files, 'tak', 'nie')}

Zawartość:
${lista(zawartoscPl)}

Uwagi o formacie:
  Wszystkie pliki tekstowe są w UTF-8. Daty w JSON mają format ISO-8601
  z przesunięciem względem UTC tego urządzenia; wpisy dziennika mają
  milisekundy. Pliki .txt pokazują czas lokalny.
  Wartości wyliczeniowe są zapisane nazwami, na przykład "incoming",
  "delivered", "password".
  Historia pisania: "direction" outgoing to pisanie z tego urządzenia na
  innym, incoming to pisanie innego urządzenia na tym. "ops" to lista
  operacji: {"t":"insert","s":"tekst"}, {"t":"insert","hidden":5} to pięć
  ukrytych znaków, {"t":"bs","n":2} to Backspace, {"t":"del","n":1} to
  Delete, {"t":"action"} to Enter. Tekst wpisany w pole hasła albo pole
  nieznanego rodzaju jest zapisany jako liczba znaków i widać go jako •.
  "transcript" odtwarza wpisany tekst z operacji o statusie typed albo
  notTyped. To przybliżenie: pole mogło mieć treść sprzed sesji, a kursor
  mógł się przesunąć.
  Pominięte pliki ("skippedFiles" w manifest.json) mają powód: missing
  (zniknął z dysku), tooLarge (ponad granice formatu ZIP: 4 GB albo 65535
  wpisów), readError (błąd odczytu), outsideReceivedDir (ścieżka poza
  katalogiem odebranych plików).
''';
}
