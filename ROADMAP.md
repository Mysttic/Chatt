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

### Faza 4 — Pliki ✅ (31.08.2026, dokończona 01.09.2026)
- [x] Protokół: `POST /file` — streaming w obie strony (bez ładowania do pamięci), metadane w nagłówkach, weryfikacja rozmiaru, plik tymczasowy + rename (nigdy pół pliku), dedupe po GUID
- [x] UI: spinacz → systemowy wybór pliku (file_selector), dymek pliku z nazwą/rozmiarem, pasek postępu wysyłki, retry jak przy tekście; odbiór do katalogu dokumentów aplikacji
- [x] Testy E2E: 3 MB bajt w bajt, offline→failed→retry, uszkodzone metadane→400; scenariusz na żywym UI (b6/a5 w `docs/screenshots/`)
- [x] Akceptacja odbioru przed transferem: `POST /file-offer` z nazwą/rozmiarem/sha256, prośba widoczna na każdym ekranie (overlay nad aplikacją), odmowa = 403 i zero przesłanych bajtów, brak odpowiedzi przez 2 min = odmowa
- [x] Suma kontrolna (sha256 liczone strumieniowo) i wznawianie: część transferu leży w `received/.incomplete/<guid>.part` z opisem obok, kolejna próba dokłada tylko brakujący kawałek (`x-chatt-file-offset`), po złożeniu weryfikacja sumy; porzucone części sprzątane po 7 dniach
- [x] Zapowiedź wykrywa też duplikat („już to mam") — ponowienie po zgubionym ACK-u nie przesyła ani bajtu i nie pyta użytkownika drugi raz
- [x] Otwieranie odebranego pliku z czatu: klik w dymek otwiera plik systemowym skojarzeniem, przytrzymanie daje „pokaż folder"/„udostępnij" i „kopiuj ścieżkę"
- [x] Android: własny kanał platformowy (`chatt/files` + FileProvider w `MainActivity.kt`) zamiast wtyczki z pub.dev — otwieranie i udostępnianie sprawdzone na emulatorze (`docs/screenshots/android/and5_otwieranie_pliku.png`)
- [x] Testy: odmowa→failed→zgoda→retry, zła suma kontrolna→plik odrzucony, wznowienie po zerwaniu sieci składa plik bajt w bajt (obie strony), jedno ponowienie = jedno pytanie o zgodę

### Faza 5 — Sprzęt właściciela (Windows + Android) — w toku (01.09.2026)
- [x] Flutter SDK 3.47.2 na Windows (`C:\Users\mystt\dev\flutter`, poza PATH-em — patrz README)
- [x] Build i instalacja `app-debug.apk`; aplikacja startuje na emulatorze (AVD `Pixel_9_Pro`, Android 17)
- [x] **Automatyczny E2E na żywym Androidzie** (`app/tool/android_e2e_test.dart`): host ⇄ aplikacja na urządzeniu przez tunele adb — `/info`, wiadomość z ACK, plik z akceptacją i sumą kontrolną, odmowa. Zrzuty w `docs/screenshots/android/`
- [x] Poprawki znalezione dopiero na urządzeniu: ręczne dodanie po adresie zapisuje port osiągalny (a nie rozgłaszany), odrzucanie pętli na samego siebie, sensowny domyślny nick na Androidzie (`localHostname` zwraca tam „localhost")
- [x] Build Windows: workload „Desktop development with C++" + tryb dewelopera, `flutter build windows` przechodzi, aplikacja startuje (motyw ciemny bierze z systemu)
- [x] **Rozmowa PC ⇄ Android na dwóch prawdziwych aplikacjach**: wiadomości w obie strony (z ACK i ponowieniem) oraz plik 6,8 MB z akceptacją na telefonie, sha256 zgodne co do bajtu. Przez tunele adb, bo emulator jest za NAT-em
- [x] Nasłuch w tle na Androidzie: silnik Fluttera w cache'u aplikacji + usługa pierwszoplanowa (`ChattService`, typ `connectedDevice`) i powiadomienia o wiadomościach przy zamkniętym oknie. Zmierzone przed i po: zwykły proces po zmieceniu z listy zadań nie odbierał nic, teraz przyjmuje wiadomości i pokazuje powiadomienie (`docs/screenshots/android/and7_powiadomienie.png`)
- [ ] To samo w fizycznej sieci Wi‑Fi z prawdziwym telefonem (dopiero to sprawdzi discovery UDP; możliwy MulticastLock)
- [ ] Zachowanie w trybie Doze (głęboki sen urządzenia) — nie sprawdzone
- [ ] **Kamień milowy: pierwsza prawdziwa rozmowa i transfer pliku PC ⇄ telefon w fizycznej sieci Wi‑Fi**

### Faza 6 — Szlif
- [x] Parowanie kodem PIN: `POST /pair`, sześciocyfrowy kod losowany i pokazywany na jednym urządzeniu, przepisywany na drugim, ważny 2 minuty i jednorazowy. Zgodny kod ustawia `verified` po obu stronach; w czacie jest tarcza (zielona = sparowane), a prośba o plik od niesparowanego urządzenia ostrzega, że nazwę można sobie ustawić dowolną. Sprawdzone Windows ⇄ Android (`docs/screenshots/android/and8_kod_parowania.png`, `and9_sparowane.png`)
- [x] Szyfrowanie ruchu między sparowanymi: klucz z parowania (X25519 + HKDF z kodem jako solą, kod nie idzie przez sieć), wiadomości i zapowiedzi plików w kopercie AES-GCM, treść plików strumieniem AES-CTR (żeby wznawianie dalej działało), suma kontrolna z zaszyfrowanej zapowiedzi. Od sparowanego urządzenia przyjmujemy **wyłącznie** ruch zaszyfrowany — inaczej dałoby się podszyć jawnym pakietem pod zieloną tarczę (`app/test/downgrade_test.dart`)
- [ ] Do rozważenia: pełny PAKE zamiast obecnego schematu (aktywny napastnik w oknie parowania może po fakcie łamać sześciocyfrowy kod offline), rotacja kluczy, szyfrowanie discovery
- [x] Obsługa zmiany IP rozmówcy: nieudana wysyłka uruchamia skan i szuka tego samego GUID-a pod nowym adresem, zapisuje go i ponawia (dotyczy wiadomości i plików)
- [x] Sprzątanie listy urządzeń: przy starcie znikają wpisy bez ani jednej wiadomości, niewidziane od tygodnia (sparowanych i rozmów nie rusza); w ustawieniach jest przycisk „wyczyść nieużywane" (próg godziny), a przytrzymanie wpisu na liście urządzeń albo rozmów usuwa go ręcznie razem z historią
- [x] Tryb ciemny: wybór systemowy/jasny/ciemny w ustawieniach, zapisany w bazie (schemat v4), więc przeżywa restart
- [x] Ikona aplikacji: dwa dymki na fiolecie z motywu, generowane `app/tool/make_icons.py` (launcher Androida, ikona adaptacyjna dla Androida 8+, `.ico` dla Windows)
- [x] i18n PL/EN: teksty w `app/lib/l10n/*.arb`, wybór języka w ustawieniach (systemowy/polski/angielski, zapisany w bazie, schemat v5). Teksty powiadomienia usługi w tle idą z Darta do Kotlina, więc też są w języku aplikacji, a nie systemu
- [x] Ikona powiadomień na Androidzie: własna biała sylwetka dwóch dymków (`res/drawable-*/ic_notification.png`, generowana tym samym skryptem co reszta ikon)

## 4. Podział pracy

- **Claude (sesje chmurowe, branch `claude/wifi-device-communication-npzb1g`)**: cały kod + testy jednostkowe + testy E2E dwóch instancji na Linuksie + golden/screenshoty UI. Realnie ~90% weryfikacji dzieje się bez Twojego udziału.
- **Właściciel**: buildy i testy na Windows/Androidzie (czyli to, czego kontener nie ma: fizyczna sieć Wi‑Fi między dwoma realnymi urządzeniami, zachowanie Androida — doze, uprawnienia, WebView'a nie używamy). Do każdej porcji zmian dostajesz krótką checklistę „co sprawdzić".
- **Nauka Darta**: przy każdej większej porcji kodu krótkie objaśnienie idiomów Dart/Flutter dla kogoś z C# (async/await niemal identyczne; `final`/`var`, metody kolekcji zamiast LINQ, pub zamiast NuGet, widgety zamiast XAML).

## 5. Następny krok

Fazy 0–4 są zrobione i zweryfikowane: 17 testów `flutter test` (zielone), `flutter analyze` bez uwag, oraz 3 testy E2E na żywej aplikacji na Androidzie. Zostało:

1. **Właściciel, żeby odblokować Windows**: w Visual Studio Installerze dołożyć workload „Desktop development with C++" i włączyć tryb dewelopera (`start ms-settings:developers`, potrzebne do symlinków wtyczek). Wtedy `cd app && flutter run -d windows` i pierwszy realny test PC ⇄ telefon w domowym Wi‑Fi.
2. **Faza 5 do dokończenia**: nasłuch w tle na Androidzie (foreground service + powiadomienia), discovery na fizycznym Wi‑Fi, zachowanie przy zmianie IP.
3. **Faza 6**: parowanie PIN (kolumna `verified` w bazie już czeka), szyfrowanie, tryb ciemny, ikona, i18n.
4. Build APK w chmurze jest zablokowany polityką sieci (`dl.google.com` — tam mieszka Android SDK i artefakty Gradle); lokalnie buduje się bez problemu. Jeśli sesje chmurowe mają budować APK: claude.ai → Environments → dopuść `dl.google.com` i `maven.google.com`.

Uruchamianie testów lokalnie (Flutter nie jest w PATH):

```
cd app
C:\Users\mystt\dev\flutter\bin\flutter.bat test
C:\Users\mystt\dev\flutter\bin\flutter.bat test tool/android_e2e_test.dart   # wymaga uruchomionej aplikacji na emulatorze
```
