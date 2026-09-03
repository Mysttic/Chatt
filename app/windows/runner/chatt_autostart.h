#ifndef RUNNER_CHATT_AUTOSTART_H_
#define RUNNER_CHATT_AUTOSTART_H_

#include <flutter/flutter_engine.h>

// Instaluje kanał "chatt/autostart": włączanie i wyłączanie uruchamiania
// aplikacji razem z Windowsem. Pod spodem jest wpis w rejestrze użytkownika
// (HKCU\...\CurrentVersion\Run), a nie usługa — nie potrzeba uprawnień
// administratora, a użytkownik może go skasować sam.
void RegisterChattAutostart(flutter::FlutterEngine* engine);

#endif  // RUNNER_CHATT_AUTOSTART_H_
