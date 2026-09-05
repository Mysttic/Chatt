import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as p;

/// Ścieżki plików odebranych i częściowych.
///
/// Wydzielone z [AppServices], bo to jedyne miejsce, gdzie napis **z sieci**
/// staje się nazwą pliku na dysku, a to jest miejsce, w którym łatwo zrobić
/// dziurę. Identyfikator wiadomości i nazwa pliku przychodzą od nadawcy;
/// „../../../cokolwiek" znaczyłoby zapis albo skasowanie pliku poza katalogiem
/// aplikacji, na pulpicie wszędzie tam, gdzie sięga użytkownik.
///
/// Dwie zapory: protokół odsiewa identyfikatory nie w kształcie UUID
/// (`isSafeMessageGuid`), a tutaj i tak nie używamy identyfikatora wprost,
/// tylko jego skrótu: ze skrótu nie da się zrobić ścieżki.

/// Podkatalog na transfery w trakcie.
const String incompleteSubdir = '.incomplete';

/// Nazwa pliku wyprowadzona z identyfikatora. Sam identyfikator nie trafia
/// nigdy do ścieżki.
String diskToken(String messageGuid) =>
    sha256.convert(utf8.encode('chatt-part|$messageGuid')).toString();

String partPath(String receivedDir, String messageGuid) =>
    p.join(receivedDir, incompleteSubdir, '${diskToken(messageGuid)}.part');

String partMetaPath(String receivedDir, String messageGuid) =>
    p.join(receivedDir, incompleteSubdir, '${diskToken(messageGuid)}.json');

/// Docelowa ścieżka odebranego pliku: skrót identyfikatora (żeby dwa pliki
/// o tej samej nazwie się nie nadpisały) plus nazwa oczyszczona ze wszystkiego,
/// co jest separatorem albo znakiem zakazanym w nazwach na Windows.
String receivedFilePath(
    String receivedDir, String messageGuid, String fileName) {
  final safeName =
      p.basename(fileName).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  return p.join(receivedDir, '${diskToken(messageGuid).substring(0, 8)}_$safeName');
}
