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
- **Discovery**: responder UDP na stałym porcie (np. 47777) odpowiadający na `CHATT_DISCOVER` pakietem z tożsamością i portem TCP; skan = 1 broadcast + ~2 s zbierania odpowiedzi. Fallback: ręczne dodanie po `IP:port` (makieta `docs/makiety/dodaj_po_adresie.png`). Opcjonalne filtry IP/portów jak w prototypie C#.
- **Transport**: każdy egzemplarz aplikacji hostuje lekki serwer HTTP (`shelf`) — `GET /info`, `POST /message`, potem endpointy plików — oraz WebSocket do pchania zdarzeń na żywo. Format: JSON. (W `dart:io` serwer działa też na Androidzie — dokładnie tak robi LocalSend.)
- **Baza**: `drift` (SQLite, typowane zapytania, działa na wszystkich platformach i w testach na Linuksie). Schemat przenosimy koncepcyjnie z modeli C#: users, conversations, messages (ze statusem dostarczenia: created/sent/delivered/failed), settings.
- **Stan/UI**: Riverpod + ekrany wg istniejących makiet z `docs/makiety/` (lista konwersacji, konwersacja, urządzenia w pobliżu, ustawienia) i diagramu przepływów (ponawianie niedostarczonych, weryfikacja obecności rozmówców).
- **Bezpieczeństwo**: MVP jawnym tekstem w LAN; w Fazie 6 parowanie kodem PIN (odpowiednik flagi `Verified`) i szyfrowanie.

### Los kodu C#/MAUI

Usunięty (02.09.2026), po potwierdzeniu parytetu funkcji na Windows i Androidzie. Był w repo jako referencja: modele danych, parsery filtrów IP/portów z `SettingsModel.cs`, projekty gRPC. Jest w historii gita, gdyby kiedyś czegoś stamtąd brakowało. Z prototypu zostały tylko makiety i diagramy, przeniesione do `docs/makiety/`.

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
- [x] Lista konwersacji z bazy (ostatnia wiadomość, inicjały, czas, badge nieprzeczytanych) — wg `docs/makiety/lista_rozmow.png`
- [x] Ekran konwersacji: dymki moje/cudze, pole tekstowe, statusy (zegarek/podwójny check/błąd), przycisk „ponów" — wg `docs/makiety/rozmowa.png`
- [x] Urządzenia w pobliżu (skan na żywo + znane urządzenia) — wg `docs/makiety/urzadzenia_w_poblizu.png`; ustawienia z adresami do ręcznego parowania — wg `docs/makiety/ustawienia.png`
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
- [x] **Automatyczny E2E na żywym Androidzie** (`app/tool/android_e2e_test.dart`): host ⇄ aplikacja na urządzeniu przez tunele adb — `/info`, wiadomość z ACK, plik z akceptacją i sumą kontrolną, odmowa. Zrzuty w `docs/screenshots/android/`. Test sam restartuje aplikację na starcie (inaczej kolejny przebieg zastawał kartę z poprzedniego, bo prośba o plik wisi dwie minuty), klika w przyciski znalezione po etykiecie zamiast po współrzędnych i czyta wyjście adb jako UTF‑8 — bez tego „Odrzuć" wracało jako „OdrzuÄ‡" i test odmowy nie trafiał w nic
- [x] Poprawki znalezione dopiero na urządzeniu: ręczne dodanie po adresie zapisuje port osiągalny (a nie rozgłaszany), odrzucanie pętli na samego siebie, sensowny domyślny nick na Androidzie (`localHostname` zwraca tam „localhost")
- [x] Build Windows: workload „Desktop development with C++" + tryb dewelopera, `flutter build windows` przechodzi, aplikacja startuje (motyw ciemny bierze z systemu)
- [x] **Rozmowa PC ⇄ Android na dwóch prawdziwych aplikacjach**: wiadomości w obie strony (z ACK i ponowieniem) oraz plik 6,8 MB z akceptacją na telefonie, sha256 zgodne co do bajtu. Przez tunele adb, bo emulator jest za NAT-em
- [x] Nasłuch w tle na Androidzie: silnik Fluttera w cache'u aplikacji + usługa pierwszoplanowa (`ChattService`, typ `connectedDevice`) i powiadomienia o wiadomościach przy zamkniętym oknie. Zmierzone przed i po: zwykły proces po zmieceniu z listy zadań nie odbierał nic, teraz przyjmuje wiadomości i pokazuje powiadomienie (`docs/screenshots/android/and7_powiadomienie.png`)
- [x] Utwardzenie nasłuchu w tle: usługa trzyma MulticastLock (bez niego układ Wi‑Fi odsiewa pakiety rozgłoszeniowe, zanim dojdą do aplikacji, czyli ginie discovery), a w ustawieniach jest prośba o wyjątek od optymalizacji baterii — w trybie Doze system odcina sieć aplikacjom bez wyjątku, a tu nie ma żadnego serwera push, który mógłby aplikację obudzić (`docs/screenshots/android/and14_nasluch_w_tle.png`). WifiLock bierzemy tylko do Androida 12 włącznie: od 13 system przyjmuje HIGH_PERF i go ignoruje (zmierzone w `dumpsys wifi`), a LOW_LATENCY działa wyłącznie dla aplikacji na wierzchu, więc do nasłuchu w tle jest bezużyteczny
- [x] **Tryb Doze na prawdziwym telefonie** (moto g84 5G, Android 15; `dumpsys deviceidle force-idle`, ekran zgaszony, zasilanie odłączone, aplikacja zmieciona z wierzchu). Wiadomości z PC dochodzą po prawdziwym Wi‑Fi przez cały czas snu: pięć prób w ciągu ośmiu minut, każda HTTP 200 w ~0,2 s, z powiadomieniem. Mechanizm widać wprost w `dumpsys netpolicy`: `blocked=DOZE|APP_BACKGROUND, allowed=FOREGROUND, effective=NONE` — Doze chciałby odciąć sieć, ale procState `FGS` (usługa pierwszoplanowa) to znosi. Wyjątek od optymalizacji baterii **nie był** potrzebny; zostaje jako zabezpieczenie na producentów, którzy dokładają własne ubijanie aplikacji
- [x] **Discovery UDP w fizycznej sieci Wi‑Fi** (PC po kablu 192.168.68.147/25, telefon po Wi‑Fi 192.168.68.140/25). Działa w obie strony: skan z PC znajduje telefon także przy **zgaszonym ekranie i aplikacji w tle** (MulticastLock trzymany przez usługę), a skan z telefonu znajduje aplikację na Windows. Na Windows trzeba mieć przepuszczony ruch przychodzący dla `chatt.exe` osobno dla TCP i UDP; ręczny sprawdzian: `app/tool/wifi_discovery_check.dart`
- [x] **Kamień milowy: pierwsza prawdziwa rozmowa i transfer pliku PC ⇄ telefon w fizycznej sieci Wi‑Fi** (02.09.2026). Bez tuneli i bez adb: telefon znalazł aplikację na Windows skanem, wysłał wiadomość (dostarczona, podwójny check), a plik 6,5 MB z komputera doszedł po akceptacji na telefonie z sumą `93e19974…cb1` zgodną co do bajtu po obu stronach

### Faza 6 — Szlif
- [x] **Parowanie przez porównanie kodu** (protokół 4): inicjator wysyła najpierw skrót swojego klucza publicznego (zobowiązanie), dostaje klucz drugiej strony i dopiero wtedy odsłania własny. Obie strony liczą z uzgodnienia X25519 ten sam sześciocyfrowy kod i **pokazują go u siebie**; użytkownicy porównują wzrokiem i potwierdzają na obu urządzeniach, a klucz zapisujemy dopiero po obu potwierdzeniach. Sprawdzone na żywo, PC ⇄ telefon po Wi-Fi: kod na obu ekranach ten sam (`docs/screenshots/android/and16_kod_do_porownania.png`)
- [x] Szyfrowanie ruchu między sparowanymi: klucz sesji z uzgodnienia X25519, wiadomości i zapowiedzi plików w kopercie AES-GCM, treść plików strumieniem AES-CTR (żeby wznawianie dalej działało), suma kontrolna z zaszyfrowanej zapowiedzi. Od sparowanego urządzenia przyjmujemy **wyłącznie** ruch zaszyfrowany — inaczej dałoby się podszyć jawnym pakietem pod zieloną tarczę (`app/test/downgrade_test.dart`)
- [x] Ostrzeżenie przy ponownym parowaniu: `POST /pair` nie jest niczym uwierzytelniony, więc prośbę z cudzym guid-em i cudzą nazwą może przysłać każdy z tej sieci. Klucza to nie podmieni (kody muszą się zgodzić na obu ekranach), ale karta parowania od znanego już urządzenia wyglądała dokładnie jak pierwsza. Teraz ma czerwoną tarczę i mówi wprost, że zgoda zastąpi klucz (`docs/screenshots/android/and15_ponowne_parowanie.png`)
- [x] **Podpisane odpowiedzi discovery**: skan niesie losowy nonce, a sparowane urządzenie dokłada do odpowiedzi HMAC kluczem sesji. Odpowiedź od sparowanego bez pasującego podpisu wypada z wyniku skanu — bez tego ktoś ze znanym GUID-em mógł zająć jego miejsce na liście i przejąć ruch przy zmianie IP (ta sama weryfikacja działa przy szukaniu rozmówcy pod nowym adresem)
- [ ] Rotacja kluczy sesji — **świadomie odłożona**. Wznawianie transferu wymaga, żeby klucz był ten sam między sesjami (AES-CTR liczy strumień od offsetu), więc ratchet trzeba by omijać dla plików albo trzymać stare klucze, a to kasuje sens rotacji. Wróci, jeśli dojdzie osobny mechanizm wznawiania
- [ ] Szyfrowanie samego discovery — **nie planowane**. Rozgłoszenia nie da się zaszyfrować do kogoś, kogo się jeszcze nie zna. Sensowną część tego problemu (podszywanie się pod znane urządzenie) zamykają podpisane odpowiedzi
- [x] Obsługa zmiany IP rozmówcy: nieudana wysyłka uruchamia skan i szuka tego samego GUID-a pod nowym adresem, zapisuje go i ponawia (dotyczy wiadomości i plików)
- [x] Sprzątanie listy urządzeń: przy starcie znikają wpisy bez ani jednej wiadomości, niewidziane od tygodnia (sparowanych i rozmów nie rusza); w ustawieniach jest przycisk „wyczyść nieużywane" (próg godziny), a przytrzymanie wpisu na liście urządzeń albo rozmów usuwa go ręcznie razem z historią
- [x] Tryb ciemny: wybór systemowy/jasny/ciemny w ustawieniach, zapisany w bazie (schemat v4), więc przeżywa restart
- [x] Ikona aplikacji: dwa dymki na fiolecie z motywu, generowane `app/tool/make_icons.py` (launcher Androida, ikona adaptacyjna dla Androida 8+, `.ico` dla Windows)
- [x] i18n PL/EN: teksty w `app/lib/l10n/*.arb`, wybór języka w ustawieniach (systemowy/polski/angielski, zapisany w bazie, schemat v5). Teksty powiadomienia usługi w tle idą z Darta do Kotlina, więc też są w języku aplikacji, a nie systemu
- [x] Ikona powiadomień na Androidzie: własna biała sylwetka dwóch dymków (`res/drawable-*/ic_notification.png`, generowana tym samym skryptem co reszta ikon)

### Faza 7 — Dokumentacja ✅ (02.09.2026)
- [x] `docs/instrukcja.md` — obsługa dla użytkownika: znajdowanie urządzeń, wiadomości i statusy, pliki z akceptacją i wznawianiem, parowanie przez porównanie kodu, nasłuch w tle, co robić gdy skan nic nie znajduje
- [x] `docs/budowanie.md` — środowisko, build Windows i Androida, uprawnienia w manifeście i po co są, numer wersji w jednym miejscu, lista kroków przy wydaniu i lista kontrolna do sprawdzenia ręcznie
- [x] `docs/testy.md` — co pokrywa każdy z 34 testów, scenariusze na żywym sprzęcie, świadome dziury w pokryciu
- [x] `docs/architektura.md` — protokół, schemat bazy z migracjami, model zagrożeń i to, co w nim zostaje otwarte, nasłuch w tle na Androidzie
- [x] README jako wizytówka: zrzuty, szybki start, tabela „który dokument do czego"
- [x] Zrzuty produktu generowane skryptem (`app/tool/product_shots.dart`), żeby dało się je odświeżyć po zmianie UI zamiast klikać ręcznie

## 4. Podział pracy

- **Claude (sesje chmurowe, branch `claude/wifi-device-communication-npzb1g`)**: cały kod + testy jednostkowe + testy E2E dwóch instancji na Linuksie + golden/screenshoty UI. Realnie ~90% weryfikacji dzieje się bez Twojego udziału.
- **Właściciel**: buildy i testy na Windows/Androidzie (czyli to, czego kontener nie ma: fizyczna sieć Wi‑Fi między dwoma realnymi urządzeniami, zachowanie Androida — doze, uprawnienia, WebView'a nie używamy). Do każdej porcji zmian dostajesz krótką checklistę „co sprawdzić".
- **Nauka Darta**: przy każdej większej porcji kodu krótkie objaśnienie idiomów Dart/Flutter dla kogoś z C# (async/await niemal identyczne; `final`/`var`, metody kolekcji zamiast LINQ, pub zamiast NuGet, widgety zamiast XAML).

## 5. Następny krok

Fazy 0–7 są zrobione i zweryfikowane na sprzęcie: 34 testy `flutter test` (zielone), `flutter analyze` bez uwag, 3 testy E2E na żywej aplikacji na Androidzie oraz rozmowa i transfer pliku PC ⇄ telefon w domowym Wi‑Fi. Dokumentacja jest w `docs/` (instrukcja, budowanie i wydania, testy, architektura).

Zostało:

1. **Podpisywanie APK własnym kluczem** — build release używa na razie klucza debug, co wystarcza na własne urządzenia, ale nie do dystrybucji.
2. Build APK w chmurze jest zablokowany polityką sieci (`dl.google.com` — tam mieszka Android SDK i artefakty Gradle); lokalnie buduje się bez problemu. Jeśli sesje chmurowe mają budować APK: claude.ai → Environments → dopuść `dl.google.com` i `maven.google.com`.

Uruchamianie testów lokalnie (Flutter nie jest w PATH):

```
cd app
C:\Users\mystt\dev\flutter\bin\flutter.bat test
set ADB=C:\Users\mystt\AppData\Local\Android\Sdk\platform-tools\adb.exe
C:\Users\mystt\dev\flutter\bin\flutter.bat test tool/android_e2e_test.dart   # wymaga zainstalowanej aplikacji na emulatorze
```
