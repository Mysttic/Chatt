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

### Faza 0 — Szkielet projektu
- [ ] `flutter create app` (platformy: linux, windows, android, web) + struktura `lib/{core,data,network,ui}` + lints
- [ ] Baza `drift`: tabele users/conversations/messages/settings + repozytoria + testy
- [ ] Tożsamość: GUID przy pierwszym starcie, ekran ustawień zapisujący nick/wiadomość/port do bazy
- [ ] Smoke: `flutter test` zielone w sesji chmurowej; build linux przechodzi

### Faza 1 — Discovery
- [ ] Responder UDP (nasłuch + odpowiedź z tożsamością) uruchamiany ze startem aplikacji
- [ ] Skaner: broadcast + zbieranie odpowiedzi → lista urządzeń (GUID, nick, IP, port)
- [ ] Zapis znalezionych do bazy; ręczne dodanie po IP:port; opcjonalne filtry IP/portów (przepisać parsery z C#)
- [ ] Testy: dwie instancje stosu w jednym procesie znajdują się nawzajem

### Faza 2 — Wiadomości (rdzeń)
- [ ] Serwer `shelf`: `GET /info`, `POST /message` (+ ack), WebSocket zdarzeń
- [ ] Klient + kolejka wysyłki: zapis→wysłanie→ack→status; oznaczanie niedostarczonych i ponowienie (przepływ z diagramu)
- [ ] Odbiór: wiadomość → znajdź/utwórz konwersację → zapis → zdarzenie do UI
- [ ] **Test E2E w sesji chmurowej: dwie pełne instancje na Linuksie wymieniają wiadomości** (uruchamiane i weryfikowane przez Claude)

### Faza 3 — Pełny UI
- [ ] Lista konwersacji z bazy (ostatnia wiadomość, inicjały, nieprzeczytane) — wg `ListOfConversation.PNG`
- [ ] Ekran konwersacji: dymki moje/cudze, pole tekstowe, statusy dostarczenia, retry — wg `Conversation.PNG`
- [ ] Urządzenia w pobliżu + przejście do rozmowy — wg `ListOfNearbyDevices.PNG`; ustawienia — wg `EditConfiguration.PNG`
- [ ] Weryfikacja obecności rozmówców przy starcie (ping `GET /info`)
- [ ] Golden testy / screenshoty z sesji do oceny wyglądu
- [ ] **Kamień milowy: kompletna aplikacja działa na Linux desktop → usuwamy kod C#**

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

Faza 0 w całości — po niej w repo jest szkielet aplikacji z bazą i ustawieniami, testy przechodzą w chmurze, a build Linux działa. Potem od razu Faza 1 (discovery), bo to pierwszy „efekt wow" do zobaczenia na Twoim sprzęcie.
