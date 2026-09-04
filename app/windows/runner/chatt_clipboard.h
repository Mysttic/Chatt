#ifndef RUNNER_CHATT_CLIPBOARD_H_
#define RUNNER_CHATT_CLIPBOARD_H_

#include <flutter/flutter_engine.h>

// Instaluje kanał "chatt/clipboard": kopiowanie obrazka z dysku do schowka
// Windows. Flutterowy `Clipboard` umie wyłącznie tekst, a "skopiuj obraz" ma
// się wkleić i do edytora grafiki (CF_DIB), i do Eksploratora (CF_HDROP).
void RegisterChattClipboard(flutter::FlutterEngine* engine);

#endif  // RUNNER_CHATT_CLIPBOARD_H_
