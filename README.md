# Chatt

Komunikator P2P dla urządzeń w jednej sieci Wi‑Fi (PC ⇄ telefon z Androidem):
wiadomości — a docelowo też pliki — przesyłane **bezpośrednio między
urządzeniami**, bez żadnego serwera pośredniczącego.

Aplikacja jest napisana we **Flutterze** i mieszka w katalogu [`app/`](app/).
Katalogi C#/.NET (`Chatt`, `Chatt.Entities`, `Chatt.grpc`, …) to poprzednie
podejście w .NET MAUI — zostają jako referencja do czasu pełnego parytetu
funkcji, potem znikną. Plan prac i stan projektu: [ROADMAP.md](ROADMAP.md).

## Jak to działa

- Każda instancja ma trwały **GUID**, nick i wiadomość powitalną.
- **Discovery**: broadcast UDP na porcie 47777 — jedno zapytanie, urządzenia
  odpowiadają tożsamością; jeden skan uczy obie strony nawzajem. Gdy broadcast
  nie przechodzi (izolacja AP, emulator), jest ręczne „Dodaj po adresie IP".
- **Wiadomości**: każda instancja hostuje mały serwer HTTP (`GET /info`,
  `POST /message`) na porcie 47780 (konfigurowalny; zajęty ⇒ próbowane są
  kolejne). Wysyłka: zapis lokalny → dostarczenie → potwierdzenie; nieudane
  można ponowić jednym dotknięciem.
- **Baza**: SQLite (drift) — rozmówcy, konwersacje, wiadomości ze statusami
  dostarczenia i licznikiem nieprzeczytanych.

| Skan sieci | Rozmowa | Lista konwersacji |
|---|---|---|
| ![Skan](docs/screenshots/b3_po_skanie.png) | ![Czat](docs/screenshots/b5_czat_pelna_rozmowa.png) | ![Lista](docs/screenshots/a1_lista_nieprzeczytane.png) |

*Zrzuty z automatycznego testu E2E: dwie instancje aplikacji znajdują się
przez UDP i rozmawiają ze sobą po HTTP.*

## Uruchomienie u siebie (Windows)

1. Zainstaluj [Flutter SDK](https://docs.flutter.dev/get-started/install/windows)
   i sprawdź `flutter doctor`.
2. ```
   cd app
   flutter run -d windows
   ```
   (albo `flutter build windows` i uruchom
   `app\build\windows\x64\runner\Release\chatt.exe`).

**Dwie instancje na jednym komputerze** (do testów bez drugiego urządzenia) —
druga musi dostać własny katalog danych; port znajdzie sobie sama:

```powershell
$env:CHATT_DATA_DIR = "$env:TEMP\chatt-b"
$env:CHATT_INSTANCE_NAME = "Instancja B"
.\build\windows\x64\runner\Release\chatt.exe
```

## Android

Telefon z włączonym debugowaniem USB: `flutter run -d <urządzenie>` albo
`flutter build apk --debug` i zainstaluj APK.

**Emulator Androida**: nada się do pracy nad UI i — z ograniczeniami — do
wiadomości, ale **automatyczne wykrywanie nie zadziała** (emulator siedzi za
NAT-em, broadcast UDP nie przechodzi w żadną stronę). Obejście dla wiadomości:

- w aplikacji na emulatorze dodaj PC ręcznie jako `10.0.2.2:47780`
  (tak emulator widzi hosta);
- żeby PC mógł wysyłać do emulatora: `adb forward tcp:47781 tcp:47780`
  i na PC dodaj ręcznie `127.0.0.1:47781`.

Pełny test discovery i realne warunki Wi‑Fi wymagają fizycznego telefonu
w tej samej sieci co PC.

## Development i testy

```
cd app
flutter test        # dane, discovery, E2E dwóch stosów w jednym procesie
flutter analyze
dart run build_runner build   # po zmianach schematu bazy (lib/data/db.dart)
```

Struktura `app/lib/`:

- `core/` — tożsamość urządzenia, nadpisania środowiskowe
- `data/db.dart` — schemat SQLite (drift) i zapytania
- `network/` — protokół, discovery UDP, serwer HTTP, klient
- `services/` — `AppServices` (korzeń łączący wszystko) i providery Riverpod
- `ui/screens/` — konwersacje, czat, urządzenia w pobliżu, ustawienia

Na Linuksie jest też scenariusz E2E na żywym UI (dwie instancje pod Xvfb,
sterowane xdotool, ze zrzutami ekranu): `app/tool/ui_e2e.sh` — tego używa
sesja chmurowa do samodzielnego testowania aplikacji.
