#ifndef RUNNER_CHATT_LINKS_H_
#define RUNNER_CHATT_LINKS_H_

#include <flutter/flutter_engine.h>

// Instaluje kanal "chatt/links": otwieranie adresu strony w domyslnej
// przegladarce. Adres trafia do ShellExecuteW jako jeden napis, bez wiersza
// polecen, wiec zaden znak w nim nie dzieli go na argumenty (issue #31).
void RegisterChattLinks(flutter::FlutterEngine* engine);

#endif  // RUNNER_CHATT_LINKS_H_
