#ifndef RUNNER_CHATT_REMOTE_INPUT_H_
#define RUNNER_CHATT_REMOTE_INPUT_H_

#include <flutter/flutter_engine.h>

// Instaluje kanał "chatt/remoteinput": ujście dodatku "Klawiatura z PC" na
// Windows, czyli wpisywanie do okna, które ma fokus, przez SendInput.
//
//   status          stan celu: program na pierwszym planie, rodzaj pola
//                   (UI Automation), ownApp, locked, elevated,
//   apply {ops}     wpisuje paczkę operacji (insert, bs, del, action) i oddaje
//                   cel razem z `applied`; odmawia przy Chatcie na wierzchu,
//                   zablokowanym ekranie i oknie z uprawnieniami
//                   administratora,
//   setSession      początek i koniec zgody; koniec chowa pływający pasek,
//   setImeEnabled   na Windows nie ma czego włączać, odpowiada {ok: true},
//   showIndicator   pływający pasek "Pisze: …" ze Stopem, teksty z Darta,
//   hideIndicator   chowa pasek.
//
// W drugą stronę idzie jedno wywołanie: "stopRequested", gdy ktoś stuknie
// Stop na pasku.
//
// Sama rejestracja niczego nie uruchamia: wątek UI Automation wstaje przy
// pierwszym pytaniu o cel, a o cel pyta wyłącznie zgoda, której przy
// wyłączonym dodatku nie ma.
void RegisterChattRemoteInput(flutter::FlutterEngine* engine);

#endif  // RUNNER_CHATT_REMOTE_INPUT_H_
