import 'dart:io' show Platform;

import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;

/// Kopiowanie obrazka do schowka systemowego.
///
/// Flutterowy `Clipboard` umie wyłącznie tekst, więc "skopiuj obraz" musi zejść
/// do platformy. Na Windows robi to runner (`windows/runner/chatt_clipboard.cpp`):
/// dekoduje plik przez WIC i kładzie do schowka `CF_DIB` (wkleja się do edytora
/// grafiki i do dokumentu) oraz `CF_HDROP` (wkleja się jako plik w Eksploratorze).
///
/// Na Androidzie tego nie ma i nie jest potrzebne: tam od odebranego pliku jest
/// „Udostępnij", które prowadzi do tych samych aplikacji, a schowek na obrazy
/// bywa zależny od producenta.
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
