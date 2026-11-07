#ifndef RUNNER_CHATT_BLUETOOTH_H_
#define RUNNER_CHATT_BLUETOOTH_H_

#include <flutter/flutter_engine.h>

// Instaluje kanal "chatt/bluetooth": Bluetooth Classic (RFCOMM) jako druga
// droga dla bajtow Chatta (issue #27). Odpowiednik na Androidzie:
// android/.../ChattBluetooth.kt.
//
// Sama rejestracja niczego nie uruchamia. Kanal wola wylacznie dodatek
// Bluetooth (Ustawienia, kategoria Polaczenie); przy wylaczonym dodatku radio,
// Winsock i wykrywalnosc komputera zostaja nietkniete.
//
// Metody: status, openSettings, openLocationSettings, discoverable, scan,
// scanResults, rodzina link* (transport) i bench* (pomiar z rozpoznania,
// wola je tylko tool/bt_spike.dart).
//
// Pod spodem jest Win32 Winsock (AF_BTH/BTHPROTO_RFCOMM). WinRT
// wymagaloby C++20 i wyjatkow, ktore runner ma wylaczone, a jego
// nasluch w tle (RfcommConnectionTrigger) i tak potrzebuje tozsamosci
// pakietu, ktorej zwykly .exe nie ma.
//
// Rodziny link* i scan* wracaja natychmiast: nasluch, laczenie i szukanie
// ida wlasnymi watkami i melduja sie przez linkPoll i scanResults. Blokuja
// tylko bench*, ktore wola skrypt pomiarowy bez interfejsu.
void RegisterChattBluetooth(flutter::FlutterEngine* engine);

#endif  // RUNNER_CHATT_BLUETOOTH_H_
