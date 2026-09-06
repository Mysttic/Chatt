import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'updates.dart';

/// Pobranie nowego wydania i oddanie go instalatorowi systemu.
///
/// Aplikacja nigdy nie podmienia się sama. Na Windowsie uruchamia instalator,
/// który zna swoje miejsce z poprzedniej instalacji, na Androidzie oddaje APK
/// systemowemu instalatorowi pakietów i to on pyta użytkownika o zgodę.
const MethodChannel _pliki = MethodChannel('chatt/files');

/// Czy tę instalację da się zaktualizować z poziomu aplikacji.
///
/// Wersja przenośna z zipa odpada: instalator wgrałby drugą kopię w innym
/// miejscu, a katalog, z którego program właśnie chodzi, zostałby stary.
/// Poznajemy ją po braku `unins000.exe`, który Inno Setup kładzie obok
/// pliku wykonywalnego przy każdej prawdziwej instalacji.
bool canInstallUpdate() {
  if (Platform.isAndroid) return true;
  if (!Platform.isWindows) return false;
  final katalog = File(Platform.resolvedExecutable).parent.path;
  return File(p.join(katalog, 'unins000.exe')).existsSync();
}

/// Katalog na pobrane wydania.
///
/// Na Androidzie musi leżeć pod `files/Chatt/`, bo tylko stamtąd FileProvider
/// wypuszcza plik jako `content://` (patrz `res/xml/file_paths.xml`), a bez
/// tego systemowy instalator nie miałby jak przeczytać APK.
Future<Directory> updateDirectory() async {
  final base = (Platform.isAndroid || Platform.isIOS)
      ? await getApplicationSupportDirectory()
      : await getTemporaryDirectory();
  return Directory(p.join(base.path, 'Chatt', 'updates'))
    ..createSync(recursive: true);
}

/// Pobiera plik wydania, zgłaszając postęp przez [onProgress] jako liczbę
/// odebranych bajtów i całość, jeśli serwer ją podał.
///
/// Ściąga do pliku obok, a na miejsce docelowe przenosi dopiero komplet:
/// przerwane pobieranie ma zostawić brak pliku, a nie instalator w połowie.
Future<File> downloadRelease(
  Release wydanie, {
  void Function(int odebrane, int? razem)? onProgress,
  http.Client? client,
}) async {
  final url = wydanie.assetUrl;
  final nazwa = wydanie.assetName;
  if (url == null || nazwa == null) {
    throw StateError('To wydanie nie ma pliku dla tej platformy.');
  }

  final katalog = await updateDirectory();
  // Poprzednie próby nie mają się zbierać: aktualizacja jest jednorazowa,
  // a APK waży kilkadziesiąt megabajtów.
  for (final stary in katalog.listSync()) {
    if (stary is File) stary.deleteSync();
  }

  final cel = File(p.join(katalog.path, nazwa));
  final czesc = File('${cel.path}.part');
  final polaczenie = client ?? http.Client();
  try {
    final odpowiedz =
        await polaczenie.send(http.Request('GET', Uri.parse(url)));
    if (odpowiedz.statusCode != 200) {
      throw HttpException('Serwer odpowiedział ${odpowiedz.statusCode}', uri: Uri.parse(url));
    }

    final razem = odpowiedz.contentLength ?? wydanie.assetSize;
    var odebrane = 0;
    final wyjscie = czesc.openWrite();
    try {
      await for (final kawalek in odpowiedz.stream) {
        wyjscie.add(kawalek);
        odebrane += kawalek.length;
        onProgress?.call(odebrane, razem);
      }
    } finally {
      await wyjscie.close();
    }

    if (razem != null && odebrane != razem) {
      czesc.deleteSync();
      throw StateError('Pobrano $odebrane z $razem bajtów.');
    }
    czesc.renameSync(cel.path);
    return cel;
  } finally {
    if (client == null) polaczenie.close();
  }
}

/// Oddaje pobrany plik instalatorowi.
///
/// Na Windowsie uruchamia instalator po cichu i każe mu zamknąć działającą
/// aplikację: `AppId` jest stałe, więc wgra się w to samo miejsce i zostawi
/// bazę w Dokumentach. Wywołujący ma po tym zakończyć proces.
///
/// Na Androidzie otwiera systemowy ekran instalacji. Podmiana pakietu jest
/// stamtąd, aplikacja niczego sama nie nadpisuje.
Future<bool> launchInstaller(File plik) async {
  if (Platform.isWindows) {
    await Process.start(
      plik.path,
      const ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    return true;
  }
  if (Platform.isAndroid) {
    try {
      final ok = await _pliki.invokeMethod<bool>(
        'installApk',
        {'path': plik.path},
      );
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
  return false;
}
