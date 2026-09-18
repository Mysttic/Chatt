#ifndef RUNNER_CHATT_CLIPBOARD_H_
#define RUNNER_CHATT_CLIPBOARD_H_

#include <flutter/flutter_engine.h>

// Instaluje kanał "chatt/clipboard", czyli schowek Windows w obie strony,
// bo flutterowy `Clipboard` umie wyłącznie tekst.
//
//   copyImage   obrazek z dysku do schowka: i do edytora grafiki (CF_DIB),
//               i do Eksploratora (CF_HDROP),
//   hasFiles    czy w schowku jest plik albo obrazek,
//   pasteFiles  ścieżki do wysłania: pliki z CF_HDROP wprost, obrazek bez
//               pliku źródłowego zapisany jako PNG w katalogu tymczasowym.
void RegisterChattClipboard(flutter::FlutterEngine* engine);

#endif  // RUNNER_CHATT_CLIPBOARD_H_
