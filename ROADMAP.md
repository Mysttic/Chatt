# Chatt — plan projektu (v2: Flutter)

> Cel aplikacji: komunikacja między urządzeniami w tej samej sieci Wi‑Fi (np. PC ⇄ smartfon z Androidem) — wymiana wiadomości i plików **bezpośrednio (P2P)**, bez żadnego serwera pośredniczącego.
>
> **Decyzja (31.08.2026):** przepisujemy aplikację na **Flutter/Dart**. Powody: (1) Claude może w sesjach chmurowych samodzielnie budować, uruchamiać i testować całą aplikację — łącznie z UI — więc pętla iteracji jest wielokrotnie szybsza; (2) `dart:io` daje identyczne API sieciowe (serwer TCP/HTTP, UDP broadcast) na Androidzie, Windows i Linuksie bez hacków, w przeciwieństwie do sytuacji z gRPC/Kestrelem w MAUI; (3) to sprawdzony stack dla tej klasy aplikacji (LocalSend). Właściciel projektu przy okazji uczy się Dart/Flutter.
>
> Dokument roboczy — odhaczamy w miarę postępów. Poprzednia wersja planu (kontynuacja w .NET MAUI) jest w historii gita.

## 1. Zweryfikowane środowisko sesji chmurowych

Wszystko poniżej zostało **sprawdzone empirycznie** w kontenerze sesji (31.08.2026):

- ✅ Flutter 3.47.2 stable + Dart 3.13.2 instalują się (klon z GitHuba, Dart SDK i artefakty z `storage.googleapis.com` przechodzą przez proxy); `pub.dev` działa
- ✅ `flutter test` (testy jednostkowe i widgetowe) działa headless
- ✅ `dart:io`: serwer+klient TCP oraz **pełny cykl discovery po UDP** (broadcast 255.255.255.255 → responder → odpowiedź unicast) działają wewnątrz kontenera
- ✅ `flutter build linux` przechodzi, a zbudowana aplikacja **uruchamia się** pod `xvfb`
- ✅ Chromium jest preinstalowany (`CHROME_EXECUTABLE=/opt/pw-browsers/chromium`) — wariant web + Playwright do klikania po UI i screenshotów
- ❌ Brak Android SDK/emulatora — buildy i testy na Androidzie zostają po stronie właściciela

Hook `.claude/hooks/session-start.sh` instaluje to wszystko automatycznie na starcie każdej sesji webowej (stan kontenera jest cache'owany, więc kolejne sesje startują szybko).

## 2. Architektura docelowa

- **Jedna aplikacja Flutter** w katalogu `app/` (do utworzenia w Fazie 0). Platformy: **Windows + Android** (produkcyjnie, buduje właściciel), **Linux desktop + web** (do rozwoju i testów w sesjach Claude).
- **Tożsamość urządzenia**: trwały GUID generowany przy pierwszym starcie + nick + wiadomość powitalna (IP może się zmieniać po DHCP, GUID nie).
- **Discovery**: responder UDP na stałym porcie (np. 47777) odpowiadający na `CHATT_DISCOVER` pakietem z tożsamością i portem TCP; skan = 1 broadcast + ~2 s zbierania odpowiedzi. Fallback: ręczne dodanie po `IP:port` (makieta `ManuallyFindDevice.PNG`). Opcjonalne filtry IP/portów jak w prototypie C#.
- **Transport**: każdy egzemplarz aplikacji hostuje lekki serwer HTTP (`shelf`) — `GET /info`, `POST /message`, potem endpointy plików — oraz WebSocket do pchania zdarzeń na żywo. Format: JSON. (W `dart:io` serwer działa też na Androidzie — dokładnie tak robi LocalSend.)
- **Baza**: `drift` (SQLite, typowane zapytania, działa na wszystkich platformach i w testach na Linuksie). Schemat przenosimy koncepcyjnie z modeli C#: users, conversations, messages (ze statusem dostarczenia: created/sent/delivered/failed), settings.
- **Stan/UI**: Riverpod + ekrany wg istniejących makiet z `Prototype/` (lista konwersacji, konwersacja, urządzenia w pobliżu, ustawienia) i diagramu przepływów (ponawianie niedostarczonych, weryfikacja obecności rozmówców).
- **Bezpieczeństwo**: MVP jawnym tekstem w LAN; w Fazie 6 parowanie kodem PIN (odpowiednik flagi `Verified`) i szyfrowanie.

### Los kodu C#/MAUI

Zostaje w repo **jako referencja** (modele danych, parsery filtrów IP/portów z `SettingsModel.cs`, diagramy i makiety w `Prototype/`) do czasu osiągnięcia parytetu funkcji (koniec Fazy 3), potem go usuniemy. Nie rozwijamy go i nie budujemy.

## 3. Fazy

### Faza 0 — Szkielet projektu ✅ (31.08.2026)
- [x] `flutter create app` (platformy: linux, windows, android) + struktura `lib/{core,data,network,services,ui}` + lints
- [x] Baza `drift`: tabele settings/peers/conversations/messages + zapytania + testy
- [x] Tożsamość: GUID przy pierwszym starcie, ekran ustawień zapisujący nick/wiadomość/port do bazy
- [x] Smoke: `flutter test` zielone w sesji chmurowej; build linux przechodzi

### Faza 1 — Discovery ✅ (31.08.2026)
- [x] Responder UDP (nasłuch + odpowiedź z tożsamością) uruchamiany ze startem aplikacji; zapytanie niesie tożsamość skanującego, więc jeden skan uczy obie strony
- [x] Skaner: broadcast (globalny + kierowane /24) z powtórką → lista urządzeń (GUID, nick, IP, port)
- [x] Zapis znalezionych do bazy; ręczne dodanie po IP:port (dialog + `GET /info`)
- [ ] Opcjonalne filtry IP/portów z prototypu C# (świadomie odłożone — broadcast czyni je mniej potrzebnymi; wrócą, jeśli zajdzie potrzeba)
- [x] Testy: dwie instancje stosu w jednym procesie znajdują się nawzajem

### Faza 2 — Wiadomości (rdzeń) ✅ (31.08.2026)
- [x] Serwer `shelf`: `GET /info`, `POST /message` (+ ack, dedupe po GUID wiadomości, odporność na śmieci); WebSocket zdarzeń niepotrzebny — UI aktualizują strumienie z bazy
- [x] Wysyłka: zapis(pending)→dostarczenie→ack→delivered/failed; ponowienie niedostarczonych z UI (przepływ z diagramu)
- [x] Odbiór: upsert nadawcy (IP z połączenia, port z payloadu) → znajdź/utwórz konwersację → zapis → strumień do UI
- [x] **Test E2E w sesji chmurowej: dwie pełne instancje wymieniają wiadomości w obie strony, offline→failed→retry→delivered, dedupe** (`app/test/`)

### Faza 3 — Pełny UI ✅ (31.08.2026)
- [x] Lista konwersacji z bazy (ostatnia wiadomość, inicjały, czas, badge nieprzeczytanych) — wg `ListOfConversation.PNG`
- [x] Ekran konwersacji: dymki moje/cudze, pole tekstowe, statusy (zegarek/podwójny check/błąd), przycisk „ponów" — wg `Conversation.PNG`
- [x] Urządzenia w pobliżu (skan na żywo + znane urządzenia) — wg `ListOfNearbyDevices.PNG`; ustawienia z adresami do ręcznego parowania — wg `EditConfiguration.PNG`
- [x] Weryfikacja obecności rozmówcy („dostępny/niedostępny") przy otwarciu rozmowy
- [x] Screenshoty z żywej aplikacji (`docs/screenshots/`, generowane przez `app/tool/ui_e2e.sh` — dwie instancje pod Xvfb sterowane xdotool)
- [x] **Kamień milowy: kompletna aplikacja działa na Linux desktop** (usunięcie kodu C# — po potwierdzeniu działania na Windows/Androidzie przez właściciela)

### Faza 4 — Pliki
- [ ] Protokół: oferta pliku → akceptacja → streaming HTTP z postępem → suma kontrolna
- [ ] UI: wybór pliku, wiadomość-plik z paskiem postępu, katalog docelowy
- [ ] Test E2E na dużym pliku między dwiema instancjami

### Faza 5 — Sprzęt właściciela (Windows + Android)
- [ ] Instalacja Flutter SDK na Windows + Android Studio (instrukcja w README)
- [ ] Build Windows `.exe` i Android `.apk`; poprawki platformowe (uprawnienia sieciowe/storage Androida, firewall Windows przy pierwszym uruchomieniu)
- [ ] Nasłuch w tle na Androidzie (foreground service) + powiadomienia lokalne
- [ ] **Kamień milowy: pierwsza prawdziwa rozmowa i transfer pliku PC ⇄ telefon w fizycznej sieci Wi‑Fi**

### Faza 6 — Szlif
- [ ] Parowanie/weryfikacja PIN, potem szyfrowanie transmisji
- [ ] Obsługa zmiany IP rozmówcy (ponowne odnalezienie po GUID)
- [ ] Tryb ciemny, ikona aplikacji, i18n PL/EN

## 4. Podział pracy

- **Claude (sesje chmurowe, branch `claude/wifi-device-communication-npzb1g`)**: cały kod + testy jednostkowe + testy E2E dwóch instancji na Linuksie + golden/screenshoty UI. Realnie ~90% weryfikacji dzieje się bez Twojego udziału.
- **Właściciel**: buildy i testy na Windows/Androidzie (czyli to, czego kontener nie ma: fizyczna sieć Wi‑Fi między dwoma realnymi urządzeniami, zachowanie Androida — doze, uprawnienia, WebView'a nie używamy). Do każdej porcji zmian dostajesz krótką checklistę „co sprawdzić".
- **Nauka Darta**: przy każdej większej porcji kodu krótkie objaśnienie idiomów Dart/Flutter dla kogoś z C# (async/await niemal identyczne; `final`/`var`, metody kolekcji zamiast LINQ, pub zamiast NuGet, widgety zamiast XAML).

## 5. Następny krok

Fazy 0–3 są zrobione i zweryfikowane w chmurze (testy + żywe E2E dwóch instancji ze zrzutami ekranu). Teraz:

1. **Właściciel**: uruchomienie na Windows (`cd app && flutter run -d windows`; instrukcje w README.md) i na telefonie — pierwszy test w fizycznej sieci Wi‑Fi. Zgłoszenie, co nie działa/przeszkadza.
2. **Równolegle (sesje chmurowe)**: Faza 4 — przesyłanie plików.
3. Build APK w chmurze jest zablokowany polityką sieci (`dl.google.com` niedostępny — tam mieszka Android SDK i artefakty Gradle). Jeśli chcesz, żeby sesje mogły budować APK do sideloadu: w ustawieniach środowiska Claude Code (claude.ai → Environments) dopuść domeny `dl.google.com` i `maven.google.com`.
