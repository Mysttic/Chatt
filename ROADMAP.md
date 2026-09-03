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
- [x] CI/CD na GitHubie: `testy.yml` (analiza i cały zestaw testów wyłącznie przy pull requeście do `master`, żeby nie mielić runnerów przy każdym commicie) oraz `wydanie.yml` (scalenie do `master` buduje Windows i podpisany APK, zakłada tag `v<wersja>` i wystawia Release). Numer wydania stoi w `VERSION.md` i to on jest wyzwalaczem: workflow rusza tylko wtedy, gdy ten plik był w scalanych zmianach, a druga bramka sprawdza, czy taki tag już nie istnieje. Zgodności `VERSION.md` z `pubspec.yaml` pilnuje workflow, a podnosi je razem `app/tool/wersja.py`. Brak sekretów z kluczem przerywa wydanie zamiast wypuścić APK podpisany kluczem debug
- [x] Podpisywanie buildu release własnym kluczem (RSA 4096, alias `chatt`): keystore poza repozytorium, hasła w gitignorowanym `android/key.properties`, a przy ich braku build nadal przechodzi kluczem debug z ostrzeżeniem. Sprawdzone: `apksigner verify` pokazuje `CN=Chatt, O=Mysttic, C=PL` i „Verifies" (schemat v2, bo `minSdk` to 24), podpisany APK instaluje się i działa na emulatorze

## 3a. Wydanie 0.2.0 — „szyfrowane zawsze"

> **Teza wydania:** nikt w sieci nie ma jak podsłuchać rozmowy, niezależnie od
> tego, czy urządzenia zdążyły się sparować.
>
> Stan wyjściowy po 0.1.0 tej tezy nie spełnia: szyfrowanie włącza się dopiero
> po sparowaniu, więc do tego czasu wszystko leci jawnym tekstem po LAN‑ie.
> Do tego klucz sesji jest jeden na zawsze (kto go kiedyś zdobędzie, odszyfruje
> też nagrany wcześniej ruch), a baza z historią leży na dysku bez szyfrowania.

**Decyzje podjęte przed rozpoczęciem (02.09.2026):**

1. **Tożsamością urządzenia jest klucz, nie losowy GUID.** GUID przestaje być
   losowany i zaczyna być liczony z klucza publicznego: `sha256(klucz)`,
   pierwsze 16 bajtów, sformatowane jak UUID (żeby nic w kodzie, bazie i logach
   nie pękło). Dzięki temu nie da się podać cudzego identyfikatora bez jego
   klucza prywatnego — podszywanie się przestaje być kwestią wpisania cudzego
   napisu. **Koszt, przyjęty świadomie:** wszystkie urządzenia dostają nowe
   identyfikatory, więc istniejące rozmowy i parowania trzeba założyć od nowa.
   Migracja do schematu v6 czyści listę urządzeń i historię, a nie zostawia
   wpisów, z którymi nie da się już rozmawiać.
2. **Pełny zakres**, czyli fazy 8–11 razem z szyfrowaniem bazy na dysku.

### Faza 8 — Szyfrowanie domyślne ✅ (02.09.2026)
- [x] Trwała para kluczy X25519 przy pierwszym starcie, w bazie (schemat v6);
      GUID liczony z klucza publicznego (patrz decyzja 1)
- [x] Klucz publiczny w `GET /info` i w pakietach discovery, żeby druga strona
      mogła zaszyfrować **pierwszą** wiadomość, bez rundy „przywitaj się jawnie"
- [x] **Uścisk dłoni per sesja** (`POST /handshake`) w schemacie Noise KK: obie
      strony znają nawzajem swój klucz statyczny, dorzucają efemeryczne
      i z połączonych uzgodnień wychodzi klucz ważny tylko na tę sesję.
      Odpowiedź niesie identyfikator sesji; kolejne zapytania podają go
      w kopercie, a nieznana albo wygasła sesja to 409 i ponowny uścisk dłoni
- [x] **Forward secrecy**: klucze efemeryczne żyją tylko w pamięci i giną
      z sesją, więc nagrany dziś ruch nie odszyfruje się po późniejszej
      kradzieży urządzenia
- [x] Klucz pliku wyprowadzany z klucza sesji, a w zapowiedzi jedzie jego
      **znacznik** zapisywany obok `.part`. Niezgodność znacznika (część
      z poprzedniej sesji) każe zacząć transfer od zera, zamiast cicho
      odszyfrować śmieci nowym kluczem na starych bajtach
- [x] Jawny tekst **zniknął z protokołu** (wersja 5). Niesparowany rozmówca
      jest szyfrowany dokładnie tak samo jak sparowany, a zapytanie bez koperty
      dostaje 409 zamiast odpowiedzi
- [x] Guid nadawcy zniknął też z jawnej części koperty — zostaje sam numer
      sesji, zmieniany przy każdym uścisku dłoni, więc podsłuchujący nie widzi
      już nawet tego, kto z kim rozmawia
- [x] Parowanie zmieniło rolę: nie ustala klucza (ten jest efemeryczny), tylko
      potwierdza tożsamość. Do kodu do porównania wchodzą oba klucze statyczne
- [x] Tarcza w trzech stanach: brak szyfrowania (starsza wersja po drugiej
      stronie), szyfrowane niepotwierdzone, potwierdzone
- [x] Testy: podsłuch na łączu nie widzi treści **przed** sparowaniem; dwie
      sesje tego samego rozmówcy mają różne klucze; podmieniony klucz statyczny
      psuje uzgodnienie; część transferu z poprzedniej sesji nie jest
      dopisywana. Razem 42 zielone, plus 3 E2E na żywym Androidzie

**Ostrzeżenie o zmianie klucza wypadło z planu.** Skoro identyfikator wynika
z klucza, to inny klucz znaczy inny identyfikator, czyli po prostu inne
urządzenie na liście. Stan „to samo urządzenie, nowy klucz" nie istnieje.

**Znany koszt:** restart którejkolwiek strony w trakcie transferu kasuje
postęp, bo klucz pliku wisi na kluczu sesji. Zerwanie sieci na sekundy czy
minuty wznawia się normalnie (sesja żyje godzinę). Alternatywą byłoby
wyprowadzanie klucza pliku z kluczy statycznych, ale wtedy kradzież tożsamości
odszyfrowuje wszystkie nagrane wcześniej pliki — czyli dokładnie to, przed czym
to wydanie ma chronić.

### Faza 9 — Weryfikacja bez przepisywania ✅ (02.09.2026)
- [x] **Panel bezpieczeństwa** pod tarczą: stan szyfrowania opisany słowami
      plus odciski obu kluczy, własnego i rozmówcy. Otwiera się także po
      potwierdzeniu tożsamości, bo odcisk ma dać się sprawdzić w dowolnym
      momencie, a nie tylko raz (`docs/screenshots/android/and17_panel_bezpieczenstwa.png`)
- [x] Własny odcisk również w ustawieniach — to jego dyktuje się przez telefon
- [x] **Potwierdzanie kodem QR**: urządzenie pokazuje kod z kluczem publicznym
      i adresem (`chatt://pair?...`), drugie skanuje. Skanujący ma pewność od
      razu, bo widział tamten ekran; skanowany dostaje pytanie „czy to Ty
      właśnie skanowałeś", bo kod z ekranu mógł zobaczyć ktoś jeszcze
      (`and18_kod_qr.png`, `and19_potwierdzenie_skanu.png`)
- [x] Kod z cudzym kluczem pod czyimś adresem odpada: przed przypięciem
      sprawdzamy w `GET /info`, czy pod tym adresem naprawdę stoi urządzenie
      z tym kluczem
- [x] Porównanie sześciu cyfr zostaje jako droga awaryjna tam, gdzie nie ma
      aparatu (komputer z komputerem)
- [x] ~~Ostrzeżenie przy zmianie klucza~~ — niepotrzebne, patrz uwaga
      w fazie 8

Nowe zależności: `qr_flutter` (rysowanie kodu) i `mobile_scanner` (aparat,
uprawnienie `CAMERA` dokłada sama wtyczka). Build Windows przechodzi bez
zmian — przycisk skanowania pokazuje się tylko tam, gdzie jest aparat.

### Faza 10 — Dane w spoczynku ✅ (03.09.2026)
- [x] **Baza szyfrowana**, klucz w Android Keystore i Windows DPAPI. Zamiast
      SQLCipher poszedł **SQLite3MultipleCiphers**: `package:sqlite3` w wersji
      3 wybiera silnik przez build hooks (`hooks.user_defines`), a sqlite3mc
      jest tam gotowy na wszystkie platformy natywne. SQLCipher linkuje
      OpenSSL na Windowsie, Linuksie i Androidzie i ciągnie starszy silnik —
      przy identycznym efekcie dla nas był po prostu droższy
- [x] Klucz bazy (32 losowe bajty) leży w `chatt.key` owinięty przez schowek
      systemowy: AES-GCM z Keystore na Androidzie, DPAPI na Windowsie, przez
      wspólny kanał `chatt/sekrety`. Utrata klucza systemowego to błąd, a nie
      ciche założenie pustej bazy
- [x] Migracja istniejącej bazy: przepisanie do zaszyfrowanej i skasowanie
      jawnej, z zachowaniem historii. Sprawdzone na obu platformach na
      **prawdziwej bazie sprzed zmiany** (schemat v5, nick `BEEMYSTTIC`):
      po starcie plik nie ma czytelnego nagłówka, a ustawienia są na miejscu
- [x] „Wyczyść historię" w ustawieniach (z pytaniem, bo to nieodwracalne)
      i kasowanie wiadomości starszych niż 7, 30, 90 albo 365 dni. Domyślnie
      wyłączone. Urządzenia i potwierdzone tożsamości zostają
      (`docs/screenshots/android/and20_prywatnosc.png`,
      `and21_wyczysc_historie.png`)
- [x] Testy: plik bazy nie zawiera treści wiadomości; bez hasła nie da się jej
      otworzyć; migracja zachowuje historię i potwierdzenie tożsamości; klucz
      trafia na dysk owinięty; granica wieku kasuje tylko to, co starsze.
      Razem 56 zielonych

**Znany koszt:** klucz bazy odwinie każdy proces działający jako ten sam
użytkownik systemu (na Windowsie wprost przez DPAPI). Ochrona jest przed
skopiowaniem dysku albo samego pliku, nie przed cudzym kodem uruchomionym
na koncie użytkownika.

### Faza 11 — UI i wygoda ✅ (03.09.2026)
- [x] **Windows: ikona w zasobniku, start zminimalizowany, autostart.**
      Krzyżyk chowa okno zamiast kończyć nasłuch, a wyjście z programu jest
      w menu ikony. Autostart to wpis w rejestrze użytkownika
      (`HKCU\...\CurrentVersion\Run`) z argumentem `--minimized`, zakładany
      przez własny kanał `chatt/autostart` — bez uprawnień administratora
      i bez kolejnej zależności
- [x] Wysyłka wielu plików naraz (`openFiles`) i przeciąganie ich na okno
      (`desktop_drop`). Idą po kolei, bo każdy z osobna pyta odbiorcę o zgodę;
      katalogi odpadają same
- [x] Miniatury obrazków w rozmowie, dopiero **po** przyjęciu pliku: dekoder
      dostaje wyłącznie to, co już leży na dysku, a uszkodzony obrazek kończy
      się pustym miejscem, nie wywrotką listy
      (`docs/screenshots/produkt/android_miniatura_obrazka.png`)
- [x] Szukanie: w rozmowie (filtrowanie dymków z podświetleniem trafienia)
      i na liście rozmów (nazwa rozmówcy, ostatnia wiadomość)
      (`android_szukanie_w_rozmowie.png`)
- [x] Usuwanie pojedynczych wiadomości przez przytrzymanie dymka, razem
      z kopiowaniem treści. Napis mówi wprost, że wiadomość znika **tylko
      z tego urządzenia** (`android_menu_wiadomosci.png`)
- [x] Testy: 69 zielonych, w tym wysyłka wielu plików, pomijanie katalogów,
      filtrowanie rozmów i rozpoznawanie obrazków po rozszerzeniu

**Sprawdzone na Windowsie, nie tylko w kodzie:** zamknięcie okna zostawia
proces przy życiu i `/info` dalej odpowiada; start z `--minimized` nie tworzy
okna w ogóle; wpis autostartu powstaje i znika razem z przełącznikiem; Windows
zapisał ikonę w swojej liście zasobnika razem z poprawną podpowiedzią.

**Znany koszt:** ikona ląduje w schowku „pokaż ukryte ikony" — Windows 11 tak
traktuje każdą nową. Przypięcie jej na stałe to decyzja użytkownika, aplikacja
nie ma jak jej wymusić.

## 3b. Wydanie 0.3.0 — „wygodniej i ładniej"

> **Teza wydania:** aplikacja ma się dobrze czuć na dużym monitorze i na
> telefonie z gestami, a odebrany plik ma dać się zapisać tam, gdzie
> użytkownik go szuka.

Zgłoszone po obejrzeniu 0.2.0 na obu platformach.

**Decyzje podjęte przed rozpoczęciem (03.09.2026):**

1. **Dwa panele na szerokim oknie** (wybór użytkownika spośród trzech
   wariantów) razem z zagęszczeniem odstępów i ograniczeniem szerokości
   treści. Sam podział bez zagęszczenia zostawiłby połowę problemu.
2. **Instalator z Inno Setup**, nie MSIX. MSIX wymaga certyfikatu do
   podpisu, a bez niego Windows i tak każe użytkownikowi ręcznie zaufać
   paczce — czyli gorzej niż zwykły instalator. Wersja przenośna (zip)
   zostaje obok, bo nie każdy chce cokolwiek instalować.
3. **Tła to gotowe zestawy**, nie dowolny kolor z palety. Dowolny kolor przy
   dymkach z motywu Material daje kombinacje nie do czytania; zestaw
   przygotowanych gradientów da się sprawdzić w jasnym i ciemnym motywie.

### Faza 12 — Wygoda i wygląd ✅ (03.09.2026)
- [x] **Android: nic nie chowa się pod paskiem gestów.** Od API 35 system
      rysuje paski **na** aplikacji i nie zwęża jej okna. Przewijane listy
      dostały dolny margines wysokości paska (`bottomSystemInset`), a podgląd
      z aparatu odsunięcie podpowiedzi. Widać to było na dole ustawień:
      ostatnia karta kończyła się dokładnie na krawędzi ekranu
- [x] **Zapisanie odebranego pliku** tam, gdzie użytkownik go szuka: przycisk
      w dymku (jedno dotknięcie) i pozycja w menu. Na Androidzie obrazki idą
      do `Pictures/Chatt`, reszta do `Download` — przez MediaStore, więc bez
      żadnego uprawnienia od Androida 10. Na pulpicie systemowe okno zapisu
- [x] **Dwa panele od 900 px szerokości**: lista rozmów obok rozmowy, bez
      przeskakiwania między ekranami. Poniżej tej szerokości wszystko działa
      jak dotąd
- [x] **Zagęszczenie**: `VisualDensity.adaptivePlatformDensity`, dymki
      ograniczone do 560 px, formularze do 760 px
- [x] **Tła do wyboru**: cztery gradienty plus „bez tła", każdy w wariancie
      jasnym i ciemnym, zapisywane w ustawieniach (schemat v8)
- [x] **Instalator Windows** (Inno Setup) obok wersji przenośnej, budowany
      w tym samym workflow wydania. Instalacja per użytkownik, więc bez UAC;
      odinstalowanie sprząta wpis autostartu, ale **nie rusza bazy** — to dane
      użytkownika
- [x] Testy: 71 jednostkowych i 4 E2E na Androidzie, w tym nowy sprawdzający,
      że zapisany obrazek naprawdę ląduje w `/sdcard/Pictures/Chatt`, a nie
      tylko w katalogu aplikacji

**Znalezione przy okazji:** przezroczysty pasek aplikacji (potrzebny pod tło)
psuł jasność ikon paska systemowego — Flutter liczy ją z koloru paska, a ten
przestał mieć kolor. Ikony robiły się białe na jasnym tle. Podajemy ją teraz
wprost z jasności motywu.

**Znany koszt:** instalatora nie da się sprawdzić lokalnie bez Inno Setup
(`choco install innosetup`); na maszynie właściciela go nie ma, więc skrypt
kompiluje się dopiero na CI przy wydaniu.

## 4. Podział pracy

- **Claude (sesje chmurowe, branch `claude/wifi-device-communication-npzb1g`)**: cały kod + testy jednostkowe + testy E2E dwóch instancji na Linuksie + golden/screenshoty UI. Realnie ~90% weryfikacji dzieje się bez Twojego udziału.
- **Właściciel**: buildy i testy na Windows/Androidzie (czyli to, czego kontener nie ma: fizyczna sieć Wi‑Fi między dwoma realnymi urządzeniami, zachowanie Androida — doze, uprawnienia, WebView'a nie używamy). Do każdej porcji zmian dostajesz krótką checklistę „co sprawdzić".
- **Nauka Darta**: przy każdej większej porcji kodu krótkie objaśnienie idiomów Dart/Flutter dla kogoś z C# (async/await niemal identyczne; `final`/`var`, metody kolekcji zamiast LINQ, pub zamiast NuGet, widgety zamiast XAML).

## 5. Następny krok

Wersja **0.1.0 jest wydana** (fazy 0–7): 34 testy `flutter test` zielone, `flutter analyze` bez uwag, 3 testy E2E na żywej aplikacji na Androidzie, rozmowa i transfer pliku PC ⇄ telefon w domowym Wi‑Fi, dokumentacja w `docs/`, podpisany APK i wydanie z GitHub Actions.

Następne wydanie to **0.2.0 „szyfrowane zawsze"** — plan w sekcji 3a. Rdzeniem jest faza 8: dziś szyfrowanie włącza się dopiero po sparowaniu, więc teza „nikt nie podsłucha" jeszcze nie jest spełniona.

Poza tym zostało:

1. Build APK w chmurze jest zablokowany polityką sieci (`dl.google.com` — tam mieszka Android SDK i artefakty Gradle); lokalnie buduje się bez problemu. Jeśli sesje chmurowe mają budować APK: claude.ai → Environments → dopuść `dl.google.com` i `maven.google.com`.

Uruchamianie testów lokalnie (Flutter nie jest w PATH):

```
cd app
C:\Users\mystt\dev\flutter\bin\flutter.bat test
set ADB=C:\Users\mystt\AppData\Local\Android\Sdk\platform-tools\adb.exe
C:\Users\mystt\dev\flutter\bin\flutter.bat test tool/android_e2e_test.dart   # wymaga zainstalowanej aplikacji na emulatorze
```
