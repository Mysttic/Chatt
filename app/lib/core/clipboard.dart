import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;

/// Schowek systemowy w obie strony.
///
/// Flutterowy `Clipboard` umie wyłącznie tekst, więc i „skopiuj obraz",
/// i „wklej plik" muszą zejść do platformy kanałem `chatt/clipboard`.
///
/// **Kopiowanie** obsługuje Windows (`windows/runner/chatt_clipboard.cpp`):
/// dekoduje plik przez WIC i kładzie do schowka `CF_DIB` (wkleja się do edytora
/// grafiki i do dokumentu) oraz `CF_HDROP` (wkleja się jako plik w Eksploratorze).
/// Na Androidzie tego nie ma i nie jest potrzebne: tam od odebranego pliku jest
/// „Udostępnij", które prowadzi do tych samych aplikacji.
///
/// **Wklejanie** obsługują Windows i Android; gdzie indziej (Linux, testy
/// widgetowe) kanału po prostu nie ma i wszystko poniżej odpowiada „schowek
/// pusty", więc pytający nie musi sprawdzać platformy. Windows oddaje ścieżki
/// z `CF_HDROP` (plik skopiowany w Eksploratorze), a obrazek bez pliku
/// źródłowego (Ctrl+C na obrazku w przeglądarce) zapisuje jako PNG w katalogu
/// tymczasowym. Android kopiuje każde `content://` ze schowka do swojego cache
/// (`ChattClipboard.kt`), bo prawo do cudzego URI ginie razem z zawartością
/// schowka, a wysyłka czyta plik zwykłą ścieżką, także przy ponowieniu.
const MethodChannel _kanal = MethodChannel('chatt/clipboard');

/// Czy na tej platformie w ogóle warto pokazywać pozycję „Kopiuj obraz".
bool get canCopyImage => Platform.isWindows;

/// Kopiuje obrazek spod [path] do schowka. `false` znaczy, że się nie udało:
/// schowek zajęty przez inny proces, nieczytelny plik albo platforma bez
/// implementacji kanału. Wywołanie nigdy nie rzuca, komunikat dla użytkownika
/// wychodzi z wyniku, a nie z wyjątku w środku menu.
Future<bool> copyImageToClipboard(String path) async {
  if (!canCopyImage) return false;
  try {
    final ok = await _kanal.invokeMethod<bool>('copyImage', {'path': path});
    return ok ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Czy w schowku leży coś, co da się dołączyć do wiadomości.
///
/// Pytanie jest tanie i celowo nie czyta zawartości: na Androidzie ogląda sam
/// opis schowka (`getPrimaryClipDescription`), którego system nie liczy jako
/// odczytu, więc nie pokazuje powiadomienia „aplikacja wkleiła ze schowka".
/// Na Windowsie to sprawdzenie dostępnych formatów, bez otwierania schowka.
///
/// Odpowiedź bywa fałszywie przecząca i tak ma być. Na Androidzie skopiowany
/// plik tekstowy jest w opisie schowka nie do odróżnienia od skopiowanego
/// napisu. Na Windowsie napis w schowku wygrywa z leżącym obok obrazkiem, bo
/// zaznaczenie komórek w arkuszu niesie jedno i drugie, a wysłanie rozmówcy
/// zrzutu tych komórek nie jest tym, o co prosił. W obu razach zostaje zwykły
/// wybór pliku.
Future<bool> clipboardHasFiles() async {
  try {
    return await _kanal.invokeMethod<bool>('hasFiles') ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Wyjmuje zawartość schowka na dysk i oddaje ścieżki do wysłania.
///
/// [imageName] to nazwa dla obrazka, który w schowku nie ma swojego pliku
/// (zrzut ekranu, „kopiuj obraz" w przeglądarce). Pliki skopiowane
/// w menedżerze plików zachowują własne nazwy.
///
/// Pusta lista znaczy „nic z tego": schowek pusty, sam tekst, cofnięte prawo
/// do cudzego URI albo brak kanału. Zawsze pusta lista, nigdy wyjątek, bo to
/// jest wywoływane wprost ze skrótu klawiszowego.
Future<List<String>> pasteClipboardFiles({required String imageName}) async {
  try {
    final paths = await _kanal.invokeListMethod<String>(
        'pasteFiles', {'name': p.basename(imageName)});
    return paths ?? const [];
  } on PlatformException {
    return const [];
  } on MissingPluginException {
    return const [];
  }
}

/// Licznik wstawień w tym uruchomieniu; rozróżnia katalogi, gdy dwa
/// wstawienia trafią na ten sam odczyt zegara.
int _wklejek = 0;

/// Zapisuje treść wstawioną z klawiatury (Gboard: obraz, GIF, naklejka) jako
/// plik w katalogu tymczasowym i oddaje jego ścieżkę.
///
/// Na telefonie to jest *ta* droga do wklejenia obrazka: klawiatura ma własny
/// przycisk i nie rusza schowka. Bajty przynosi silnik Fluttera, więc nie ma
/// tu dostawcy treści ani uprawnień; zostaje tylko nazwa, a tę składamy
/// z [name] i rozszerzenia wyprowadzonego z [mimeType], bo klawiatura żadnej
/// nie podaje.
///
/// `null` znaczy, że zapis się nie udał (brak miejsca, katalog nie do zapisu).
Future<String?> saveInsertedContent(
  Uint8List bytes, {
  required String mimeType,
  required String name,
}) async {
  try {
    final base = await getTemporaryDirectory();
    // Osobny katalog na każdy plik, bo dwie naklejki nazywają się tak samo.
    // Licznik obok znacznika czasu, bo zegar bywa gruboziarnisty i dwa
    // wstawienia z rzędu potrafią wypaść w tej samej chwili.
    final dir = Directory(p.join(base.path, 'wklejone',
        '${DateTime.now().microsecondsSinceEpoch}-${++_wklejek}'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, _named(name, mimeType)));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

/// Nazwa pliku z rozszerzeniem pasującym do [mimeType]. Nieznany typ zostawia
/// nazwę taką, jaka przyszła: lepiej wysłać plik z mylącym rozszerzeniem niż
/// nie wysłać go wcale.
String _named(String name, String mimeType) {
  const rozszerzenia = {
    'image/png': '.png',
    'image/jpeg': '.jpg',
    'image/jpg': '.jpg',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'image/bmp': '.bmp',
    'image/tiff': '.tiff',
  };
  final rozszerzenie = rozszerzenia[mimeType.toLowerCase()];
  final baza = p.basename(name);
  return rozszerzenie == null ? baza : p.setExtension(baza, rozszerzenie);
}
