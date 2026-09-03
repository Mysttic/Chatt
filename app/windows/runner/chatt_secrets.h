#ifndef RUNNER_CHATT_SECRETS_H_
#define RUNNER_CHATT_SECRETS_H_

#include <flutter/flutter_engine.h>

// Instaluje kanał "chatt/sekrety": owijanie i odwijanie bajtów przez DPAPI,
// czyli kluczem konta Windows. Odpowiednik Android Keystore po stronie
// pulpitu — służy do ochrony klucza zaszyfrowanej bazy.
void RegisterChattSecrets(flutter::FlutterEngine* engine);

#endif  // RUNNER_CHATT_SECRETS_H_
