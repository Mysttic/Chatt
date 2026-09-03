# Google Play

Wszystko, co trzeba mieć pod ręką przy wypełnianiu Play Console, żeby zrobić to
za jednym razem. Materiały graficzne generuje `app/tool/store_assets.py`
do `docs/publikacja/materialy/google-play/`.

## Zanim zaczniesz: konto

- **Konto założone po 13 listopada 2023** musi przejść **test zamknięty:
  co najmniej 20 testerów przez 14 kolejnych dni**, zanim dostanie zgodę na
  produkcję. Starsze konta tego nie mają. Sprawdź w konsoli, czy przy
  aplikacji pojawia się wymaganie „Apply for production access".
- Play przyjmuje wyłącznie **AAB** (App Bundle), nie APK. Workflow wydania
  buduje AAB obok APK, podpisany tym samym kluczem.
- **Play App Signing**: przy pierwszym wgraniu nasz klucz z `chatt-release.jks`
  staje się kluczem *przesyłania*, a Google zakłada osobny klucz podpisu. To
  dobrze: zgubiony klucz przesyłania da się zresetować przez pomoc Google,
  zgubionego klucza podpisu nie.
- Docelowe API 36 spełnia wymóg „nie starsze niż rok od najnowszego".

## Wpis w sklepie

Limity: tytuł 30 znaków, krótki opis 80, pełny opis 4000.

### Tytuł
- PL: `Chatt: czat w sieci lokalnej` (28)
- EN: `Chatt: local network chat` (25)

Przed rezerwacją sprawdź, czy sam „Chatt" nie jest zajęty jako nazwa.

### Krótki opis
- PL: `Wiadomości i pliki między komputerem a telefonem. Bez serwera, szyfrowane.` (74)
- EN: `Messages and files between your PC and phone. No server, no cloud, encrypted.` (77)

### Pełny opis, PL

```
Chatt łączy Twój komputer i telefon w jednej rozmowie. Wiadomości i pliki
idą prosto z jednego urządzenia na drugie po Wi‑Fi w domu, bez serwera,
konta i chmury.

WYSYŁASZ SAM SOBIE? JUŻ NIE MUSISZ PRZEZ CUDZY SERWER
Link z telefonu na komputer, zdjęcie z komputera na telefon, plik na drugie
urządzenie. Zamiast wysyłać sobie przez komunikator albo mailem, wysyłasz
prosto: dwa urządzenia w tej samej sieci Wi‑Fi i tyle. Bez limitów rozmiaru,
bez kompresji zdjęć, bez internetu.

ROZMOWA, NIE TYLKO PRZERZUCANIE PLIKÓW
Historia zostaje, da się ją przeszukać, a telefon i komputer widzą to samo.
Pliki lądują w rozmowie razem z miniaturą i jednym dotknięciem zapisują się
do Zdjęć albo Pobranych.

SZYFROWANE ZAWSZE, NIE „PO SPAROWANIU"
Każde połączenie dostaje własny klucz, a pierwsza wiadomość do obcego
urządzenia jest tak samo zaszyfrowana jak setna do sparowanego. Nagrany dziś
ruch nie odszyfruje się po kradzieży urządzenia. Historia na dysku też jest
zaszyfrowana, a klucz trzyma system.

WIESZ, Z KIM ROZMAWIASZ
Zeskanuj kod QR z drugiego ekranu albo porównaj sześć cyfr i od tej chwili
wiadomo, że po drugiej stronie jest to urządzenie, o którym myślisz. Nazwę
każdy może sobie wpisać dowolną; klucza nie.

NIC NIE WYCHODZI Z TWOJEJ SIECI
Zero serwera, zero konta, zero telemetrii, zero reklam. Aplikacja nie
potrzebuje internetu i nie łączy się z niczym poza urządzeniami w Twojej
sieci lokalnej.

DZIAŁA W TLE
Telefon odbiera wiadomości i pliki przy zamkniętym oknie i zgaszonym
ekranie. Na komputerze aplikacja siedzi w zasobniku.

DO TEGO
• Pliki wznawiają się od miejsca przerwania i są sprawdzane sumą kontrolną
• Kilka plików naraz, na komputerze także przeciągnięciem na okno
• Kasowanie wiadomości starszych niż wybrana liczba dni
• Tła do wyboru, motyw jasny i ciemny, polski i angielski

Chatt potrzebuje drugiego urządzenia z Chattem w tej samej sieci Wi‑Fi:
komputera z Windows albo innego telefonu z Androidem. Nie rozmawia przez
internet i tego nie udaje.
```

### Pełny opis, EN

```
Chatt puts your PC and your phone in one conversation. Messages and files
go straight from one device to the other over your home Wi‑Fi, with no
server, no account and no cloud.

SENDING THINGS TO YOURSELF? NOT THROUGH SOMEONE ELSE'S SERVER ANYMORE
A link from your phone to your PC, a photo from your PC to your phone, a
file to the other device. Instead of messaging yourself or emailing your own
address, you send it directly: two devices on the same Wi‑Fi, done. No size
limits, no photo compression, no internet needed.

A CONVERSATION, NOT JUST A FILE DROP
History stays, you can search it, and your phone and PC see the same thing.
Files land in the conversation with a thumbnail and save to Pictures or
Downloads with one tap.

ALWAYS ENCRYPTED, NOT "ONCE PAIRED"
Every connection gets its own key, and the first message to an unknown
device is encrypted exactly like the hundredth to a paired one. Traffic
recorded today cannot be decrypted after a device is stolen. History on disk
is encrypted too, with the key held by the operating system.

KNOW WHO YOU ARE TALKING TO
Scan a QR code from the other screen or compare six digits, and from then on
you know the device on the other side is the one you think it is. Anyone can
type any name; nobody can fake the key.

NOTHING LEAVES YOUR NETWORK
No server, no account, no telemetry, no ads. The app needs no internet and
connects to nothing except devices on your local network.

WORKS IN THE BACKGROUND
Your phone receives messages and files with the window closed and the screen
off. On the PC the app sits in the tray.

ALSO
• Files resume where they stopped and are verified with a checksum
• Several files at once, on the PC also by dragging them onto the window
• Automatic deletion of messages older than a chosen number of days
• Backgrounds, light and dark themes, English and Polish

Chatt needs another device running Chatt on the same Wi‑Fi: a Windows PC or
another Android phone. It does not talk over the internet and does not
pretend to.
```

### Klasyfikacja
- Kategoria: **Komunikacja**.
- Tagi: komunikator, przesyłanie plików, sieć lokalna, prywatność.

## Grafika

| Element | Wymiar | Format | Skąd |
|---|---|---|---|
| Ikona | 512×512 | PNG 32‑bit | `materialy/google-play/ikona-512.png` |
| Grafika promocyjna | 1024×500 | PNG lub JPEG | `materialy/google-play/promo-1024x500.png` |
| Zrzuty telefonu | 2 do 8, każdy bok 320 do 3840 px, **dłuższy bok najwyżej dwa razy dłuższy od krótszego** | PNG 24‑bit bez alfy lub JPEG | `materialy/google-play/zrzuty/{pl,en}/` |

Zrzuty z emulatora mają 1280×2856 (proporcja 2,23), więc skrypt skaluje je do
wysokości 1920 i dokłada tło po bokach do 1080×1920 (9:16). Osobny zestaw po
polsku i po angielsku, bo Play pokazuje wpis w języku użytkownika.

## Ankiety w konsoli

| Ankieta | Odpowiedź |
|---|---|
| Polityka prywatności | adres URL do `privacy-policy.md` (po upublicznieniu repozytorium: GitHub Pages albo raw.githubusercontent.com) |
| Dostęp do aplikacji | wszystkie funkcje dostępne bez logowania |
| Reklamy | nie zawiera reklam |
| Klasyfikacja treści (IARC) | komunikator; użytkownicy wymieniają się treściami między sobą; brak treści od aplikacji |
| Grupa docelowa | 18+ (najprościej; aplikacja nie jest dla dzieci) |
| Bezpieczeństwo danych | **nie zbiera i nie udostępnia żadnych danych**; dane szyfrowane w tranzycie: tak; użytkownik może usunąć dane: tak (lokalnie) |
| Aplikacje rządowe, zdrowie, finanse | nie |

Przy „Bezpieczeństwo danych" liczy się definicja Google: „zbierane" znaczy
przesyłane poza urządzenie do dewelopera lub usług. Wiadomości idą do
drugiego urządzenia użytkownika, nie do nas, więc odpowiedź „nie zbiera" jest
zgodna z prawdą. Warto to napisać w polu opisu.

## Automatyzacja wgrywania

Po pierwszym ręcznym wgraniu (Play wymaga, żeby pierwsza wersja weszła przez
konsolę) kolejne mogą iść z workflow:

1. W Google Cloud konto serwisowe z dostępem do Play Console (rola „Release
   manager" dla tej aplikacji), klucz JSON.
2. Sekret repozytorium `PLAY_SERVICE_ACCOUNT_JSON`.
3. Krok w `wydanie.yml` po zbudowaniu AAB, na przykład
   `r0adkll/upload-google-play@v1` z `track: internal` (albo `closed`),
   `releaseFiles: app/build/app/outputs/bundle/release/app-release.aab`.

Ścieżkę internal → closed → production przechodzi się w konsoli, więc
automatyzacja wgrywa na `internal`, a promocja dalej jest kliknięciem.
