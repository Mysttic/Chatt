# Architektura

Dokument dla kogoś, kto ma w tym kodzie coś zmienić. Instrukcja obsługi jest
w [instrukcja.md](instrukcja.md), a polecenia budowania w
[budowanie.md](budowanie.md).

## Skąd taki kształt

Aplikacja nie ma serwera, więc **każdy egzemplarz jest jednocześnie klientem
i serwerem**. Każde urządzenie hostuje mały serwer HTTP (`shelf`) i odzywa się
na rozgłoszenia UDP. Dokładnie tak działa LocalSend i to jest jedyny układ,
który daje bezpośrednie połączenie bez niczyjej infrastruktury.

Tożsamością urządzenia jest **para kluczy X25519**, a nie adres IP i nie
losowy napis. Identyfikator (`guid`) jest liczony ze skrótu klucza publicznego,
więc nie da się podać cudzego bez jego klucza prywatnego: kto ogłasza cudzy
identyfikator, ten nie dokończy uścisku dłoni. IP zmienia się po restarcie
routera, tożsamość nie — dlatego wszystko (rozmowy, sesje, deduplikacja) wisi
na identyfikatorze, a adres jest tylko podpowiedzią, gdzie go ostatnio
widziano.

## Warstwy

```
lib/
  core/      tożsamość, kryptografia, kanały platformowe, nadpisania środowiskowe
  data/      schemat SQLite (drift) i zapytania
  network/   protokół, discovery UDP, serwer HTTP, klient HTTP
  services/  AppServices — korzeń łączący wszystko + providery Riverpod
  ui/        ekrany i widgety
```

Sercem jest **`AppServices`**: trzyma bazę, serwer, klienta i responder
discovery, i to on decyduje, co zrobić z każdym przychodzącym zapytaniem.
`AppServices.start()` tworzy kompletny, samodzielny stos — dlatego testy
podnoszą dwie takie instancje w jednym procesie i każą im rozmawiać ze sobą
po prawdziwym gnieździe (patrz [testy.md](testy.md)).

UI nie rozmawia z siecią. Ekrany czytają **strumienie z bazy**, więc każda
zmiana (nowa wiadomość, zmiana statusu) sama dopływa do widoku. Wyjątkiem są
rzeczy, których w bazie nie ma, bo są chwilowe: postęp transferu i prośby
o zgodę — te idą przez `ValueNotifier`.

## Protokół

Wersja protokołu: **5** (`lib/network/protocol.dart`, stała
`protocolVersion`). Podbijamy przy zmianach niekompatybilnych.

**Od wersji 5 nie ma w protokole jawnego tekstu.** Każde zapytanie poza
`GET /info`, `POST /handshake` i `POST /pair` przychodzi w kopercie związanej
z sesją; wszystko inne dostaje 409 i prośbę o uścisk dłoni.

### Discovery (UDP 47777)

Skaner wysyła rozgłoszenie `chatt_discover` ze **swoją tożsamością i losowym
nonce**, każde urządzenie odpowiada unicastem `chatt_here`. Dzięki temu, że
zapytanie niesie tożsamość pytającego, **jeden skan uczy obie strony**.

Adresy rozgłoszeniowe: globalny `255.255.255.255` plus kierowany per interfejs,
liczony jak dla /24 (`dart:io` nie zdradza maski podsieci). Zapytanie leci dwa
razy w odstępie 400 ms, bo pojedynczy datagram w Wi‑Fi łatwo ginie.

Pakiet niesie też klucz publiczny nadawcy, a odbiorca sprawdza, czy zgadza się
on z ogłoszonym identyfikatorem — niezgodne tożsamości nie wchodzą do żadnej
listy. Dzięki temu klucz do pierwszej sesji jest znany, zanim padnie pierwsze
słowo.

Odpowiedź od **znanego** urządzenia niesie `tag`: HMAC-SHA256 z guida, portu
i nonce'a z zapytania, kluczem wyprowadzonym z uzgodnienia samych kluczy
statycznych (liczy się bez żywej sesji). Skaner wyrzuca z wyniku każdą
odpowiedź, która twierdzi, że jest znanym urządzeniem, a nie ma pasującego
podpisu. Bez tego ktoś, kto zna czyjś publiczny klucz, mógłby zająć jego
miejsce na liście — a stamtąd bierzemy adres, gdy rozmówcy zmieni się IP.

### Wiadomości i pliki (TCP 47780, konfigurowalny)

| Endpoint | Do czego |
|---|---|
| `GET /info` | tożsamość urządzenia **z kluczem publicznym**; używane też jako „czy żyjesz" |
| `POST /handshake` | nawiązanie sesji (niżej) |
| `POST /message` | dostarczenie wiadomości; 200 = potwierdzenie, 409 = odnów sesję |
| `POST /pair` | potwierdzenie tożsamości (cztery akcje, niżej) |
| `POST /file-offer` | zapowiedź pliku: nazwa, rozmiar, sha256, znacznik klucza |
| `POST /file` | surowe bajty od podanego offsetu, z numerem sesji w nagłówku |

### Sesja

```
A → B   POST /handshake   { from: <tożsamość A z kluczem>, e: <efemeryczny A> }
A ← B                     { sessionId, e: <efemeryczny B>, from: <tożsamość B> }
```

Obie strony liczą klucz sesji z czterech uzgodnień X25519 (schemat Noise KK):
`ee` daje forward secrecy, `ss` wiąże sesję z tożsamościami, `es` i `se` wiążą
każdy klucz efemeryczny z tożsamością drugiej strony. Do wyprowadzenia wchodzi
cały zapis rozmowy, więc podmiana czegokolwiek po drodze daje po prostu inny
klucz i ruch się nie odszyfruje.

Sesja żyje **godzinę bezczynności i tylko w pamięci**. Restart ją kasuje,
a przy kolejnej wysyłce powstaje nowa — to jest cała mechanika forward
secrecy: nie ma czego wykraść z dysku po fakcie.

Koperta niesie jawnie **wyłącznie numer sesji**. Guid nadawcy z niej zniknął,
więc podsłuchujący nie widzi nawet tego, kto z kim rozmawia. Nieznany numer
(restart drugiej strony, wygaśnięcie) to 409: nadawca kasuje swoją sesję,
robi uścisk dłoni raz jeszcze i ponawia zapytanie jeden raz.

Transfer pliku jest **dwuetapowy**: najpierw zapowiedź, którą odbiorca
zatwierdza lub odrzuca, dopiero potem bajty. Odmowa oznacza zero przesłanych
danych. Metadane transferu jadą w nagłówkach `x-chatt-*` (muszą być ASCII,
stąd base64 i percent-encoding), a treść strumieniowo w obie strony — duży
plik nigdy nie przechodzi przez pamięć.

Wznawianie: część transferu leży w `received/.incomplete/<guid>.part` z opisem
obok. Kolejna próba podaje `x-chatt-file-offset` i dostaje tylko brakujący
kawałek, a po złożeniu całości liczona jest suma sha256. Porzucone części są
sprzątane po siedmiu dniach.

## Baza

`drift` (SQLite), schemat w wersji **6**. Tabele: `settings`, `peers`,
`conversations`, `messages`. Migracje są napisane po kolei, więc baza
z wcześniejszej wersji aplikacji doczytuje się bez utraty danych — z jednym
wyjątkiem, opisanym niżej:

| Wersja | Co doszło |
|---|---|
| 2 | pliki (kolumny transferu w `messages`) |
| 3 | `peers.sessionKey`; migracja kasuje `verified` przy parowaniach bez klucza |
| 4 | `settings.theme` |
| 5 | `settings.language` |
| 6 | `settings.identityKey`, `peers.publicKey`; **czyści listę urządzeń i historię** |

Czyszczenie przy v6 jest świadome: identyfikatory przestały być losowane
i zaczęły wynikać z kluczy, więc wszystkie urządzenia dostały nowe. Zapisani
rozmówcy przestali pasować do czegokolwiek w sieci, a zostawienie ich
znaczyłoby listę wpisów, do których nie da się już napisać.

Po każdej zmianie w `lib/data/db.dart` trzeba przegenerować kod (`build_runner`,
patrz [budowanie.md](budowanie.md)) i **podbić `schemaVersion` razem
z migracją** — inaczej użytkownik z poprzedniej wersji dostanie wywrotkę przy
starcie.

Schemat wywodzi się z modelu z pierwszej wersji projektu:
[`makiety/schemat_bazy.png`](makiety/schemat_bazy.png).

## Bezpieczeństwo

### Model zagrożeń

Zakładamy napastnika **w tej samej sieci lokalnej**: może podsłuchiwać,
wysyłać własne pakiety i podawać się za kogo chce. Nie zakładamy napastnika
z dostępem do odblokowanego urządzenia — baza i klucze leżą w katalogu
aplikacji bez dodatkowego szyfrowania.

### Potwierdzenie tożsamości (dawniej „parowanie")

Od protokołu 5 ten rytuał **nie ustala klucza do szyfrowania** — ten bierze się
z sesji i zmienia co godzinę. Odpowiada wyłącznie na pytanie „czy ten klucz
należy do osoby, o której myślę", więc jego wynikiem jest zielona tarcza.

```
A → B   commit   sha256(pkA)              zobowiązanie do klucza
A ← B   odpowiedź z pkB                   B losuje własną parę
A → B   reveal   pkA                      B sprawdza zgodność ze skrótem
        obie strony liczą sześciocyfrowy kod z uzgodnienia, do którego
        wchodzą też oba klucze statyczne, i pokazują go na ekranie
A ⇄ B   confirm  (po kliknięciu na każdym urządzeniu)
```

Tarcza robi się zielona dopiero, gdy potwierdzą **oba** końce. Zgodny kod
dowodzi przy okazji, że po drugiej stronie siedzi właściciel klucza prywatnego
od tej tożsamości — klucze statyczne wchodzą do wyprowadzenia kodu.

### Kod QR

Szybsza i pewniejsza droga do tego samego. Urządzenie pokazuje
`chatt://pair?k=<klucz>&h=<adres>&p=<port>&n=<nazwa>`, drugie skanuje.

W kodzie nie ma nic tajnego. Wartość bierze się z **kanału**: kto go
zeskanował, ten patrzył na tamten ekran, więc wie, że klucz pochodzi stąd,
a nie od kogoś po drodze. Napastnik nie ma tu szansy jednej na milion, jak
przy sześciu cyfrach — ma zero, bo nie ma jak podstawić swojego klucza.

Asymetria jest tu nieunikniona i dlatego jest widoczna w UI:

- **skanujący** ma pewność od razu i jego tarcza robi się zielona,
- **skanowany** dostaje tylko powiadomienie (`pairScanned`) i pyta swojego
  użytkownika „czy to Ty właśnie skanowałeś", bo kod z ekranu mógł zobaczyć
  ktoś jeszcze. Człowiek potwierdza to, czego maszyna nie wie: że skanowanie
  właśnie się odbyło i to on je zrobił.

Przed przypięciem klucza z kodu sprawdzamy jeszcze w `GET /info`, czy pod
adresem z kodu naprawdę stoi urządzenie z tym kluczem — inaczej dałoby się
podsunąć kod ze swoim kluczem, a cudzym adresem.

Po co zobowiązanie: bez niego napastnik w środku (osobne uzgodnienie z każdą
stroną) mógłby losować własne klucze aż do zrównania obu kodów. Skrót wysłany
przed poznaniem klucza drugiej strony to uniemożliwia — zostaje mu jedno
trafienie na milion, w dodatku widoczne od razu, bo użytkownicy zobaczą różne
kody.

Poprzednia wersja mieszała przepisywany PIN do HKDF jako sól. Miało to słabe
miejsce: napastnik obecny przy parowaniu mógł potem sprawdzić offline
wszystkie sześciocyfrowe kody. Teraz kod nie bierze udziału w wyprowadzeniu
klucza, więc nie ma czego łamać.

Pełnego PAKE (SPAKE2, CPace) świadomie nie ma: `package:cryptography` daje
X25519 tylko jako gotowe uzgodnienie, bez operacji na punktach i bez
hash-to-curve, a własna arytmetyka krzywej to prosta droga do cichego błędu.

### Szyfrowanie ruchu

- **Wiadomości i zapowiedzi plików**: koperta AES-GCM. Jawny zostaje sam numer
  sesji, po którym odbiorca znajduje klucz; `from` ze środka musi się zgadzać
  z właścicielem tej sesji, inaczej rozmówca mógłby pisać w cudzym imieniu
  we własnej, poprawnie zaszyfrowanej wiadomości.
- **Treść plików**: strumień AES-CTR, bo tylko tak da się wznowić transfer od
  dowolnego bajtu. Klucz jest osobny na każdy plik, wyprowadzony z klucza
  sesji i guida wiadomości. Nonce liczony z guida **i sumy kontrolnej treści** —
  sam guid nie wystarcza, bo ponowienie po podmianie pliku pod tą samą ścieżką
  użyłoby drugi raz tego samego strumienia klucza.
- **Wznowienie po wymianie sesji**: zapowiedź niesie znacznik klucza pliku,
  a odbiorca trzyma go obok części transferu. Niezgodność znaczy, że część
  jest zaszyfrowana czymś innym — wtedy transfer rusza od zera zamiast dokleić
  bajty, których nie da się odszyfrować razem z resztą.
- Integralności pliku pilnuje sha256 z **zaszyfrowanej** zapowiedzi, a nie
  z nagłówka.

### Reguła, na której to wszystko stoi

Jawnego tekstu **nie ma w protokole**. Zapytanie bez koperty związanej z żywą
sesją dostaje 409, niezależnie od tego, kim się przedstawia. Wcześniej ta
reguła obowiązywała tylko wobec sparowanych i wystarczyło jeden jawny pakiet
z cudzym identyfikatorem, żeby podszyć się pod zieloną tarczę; trzy testy
w `test/downgrade_test.dart` odgrywają dokładnie ten atak.

### Co zostaje otwarte

- `POST /pair` nie jest uwierzytelniony, więc każdy może wywołać kartę
  potwierdzenia, podszywając się nazwą pod znajomego. Zielonej tarczy to nie
  da (kody muszą się zgodzić na obu ekranach), ale karta dla znanego już
  urządzenia jest wyraźnie oznaczona na czerwono.
- **Restart w trakcie transferu kasuje postęp**, bo klucz pliku wisi na kluczu
  sesji. Zerwanie sieci na sekundy czy minuty wznawia się normalnie. Klucz
  wyprowadzany z kluczy statycznych naprawiłby to kosztem odszyfrowania
  wszystkich nagranych wcześniej transferów po kradzieży tożsamości — czyli
  kosztem tego, po co jest to wydanie.
- Discovery jest jawne. Nazwa urządzenia i port są widoczne dla każdego w tej
  sieci. Zaszyfrować tego się nie da: rozgłoszenie idzie do kogoś, kogo się
  jeszcze nie zna.
- Rotacja kluczy sesji: świadomie odłożona, bo wznawianie transferu wymaga
  tego samego klucza między sesjami.
- Baza i klucze leżą na dysku bez szyfrowania.

## Android: nasłuch w tle

Zwykły proces Fluttera ginie zaraz po zamknięciu okna — zmierzone: wiadomość
wysłana do zamkniętej aplikacji nie dochodziła wcale. Dlatego:

- silnik Fluttera siedzi w cache'u aplikacji (`ChattApplication`), a nie
  w aktywności, więc kanały platformowe działają też przy zamkniętym oknie;
- `ChattService` (usługa pierwszoplanowa typu `connectedDevice`) trzyma proces
  przy życiu i pokazuje stałe powiadomienie;
- usługa trzyma **MulticastLock** — bez niego układ Wi‑Fi odsiewa rozgłoszenia,
  zanim dojdą do aplikacji, i ginie discovery przy zgaszonym ekranie;
- **WifiLock** bierzemy tylko do Androida 12 włącznie. Od 13 system przyjmuje
  `WIFI_MODE_FULL_HIGH_PERF` i go ignoruje (widać w `dumpsys wifi` jako
  „0 full high perf"), a `LOW_LATENCY` działa wyłącznie dla aplikacji na
  wierzchu, więc do tła jest bezużyteczny.

W trybie Doze system chciałby odciąć aplikacji sieć, ale usługa pierwszoplanowa
to znosi. Widać to wprost w `dumpsys netpolicy`:

```
UID=... state={procState=FGS}
blocked_state={blocked=DOZE|APP_BACKGROUND, allowed=FOREGROUND, effective=NONE}
```

Wyjątek od optymalizacji baterii (przycisk w ustawieniach) nie jest do tego
potrzebny na czystym Androidzie; zostaje jako zabezpieczenie na producentów
z własnymi mechanizmami ubijania aplikacji.

Pliki wychodzą do innych aplikacji przez FileProvider jako `content://`
(własny kanał `chatt/files`, bez wtyczek z pub.dev), bo od API 24 zwykła
ścieżka kończy się `FileUriExposedException`.

## Skąd wziął się wygląd

Ekrany są robione według makiet z pierwszej wersji projektu, które leżą
w [`makiety/`](makiety/): [lista rozmów](makiety/lista_rozmow.png),
[rozmowa](makiety/rozmowa.png),
[urządzenia w pobliżu](makiety/urzadzenia_w_poblizu.png),
[ustawienia](makiety/ustawienia.png),
[dodawanie po adresie](makiety/dodaj_po_adresie.png). Przepływy (ponawianie
niedostarczonych, sprawdzanie obecności) są na [diagramie](makiety/przeplywy.png).
