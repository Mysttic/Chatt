# Architektura

Dokument dla kogoś, kto ma w tym kodzie coś zmienić. Instrukcja obsługi jest
w [instrukcja.md](instrukcja.md), a polecenia budowania w
[budowanie.md](budowanie.md).

## Skąd taki kształt

Aplikacja nie ma serwera, więc **każdy egzemplarz jest jednocześnie klientem
i serwerem**. Każde urządzenie hostuje mały serwer HTTP (`shelf`) i odzywa się
na rozgłoszenia UDP. Dokładnie tak działa LocalSend i to jest jedyny układ,
który daje bezpośrednie połączenie bez niczyjej infrastruktury.

Tożsamością urządzenia jest **GUID** losowany przy pierwszym starcie, a nie
adres IP. IP zmienia się po restarcie routera, GUID nie — dlatego wszystko
(rozmowy, klucze, deduplikacja) wisi na GUID-zie, a adres jest tylko
podpowiedzią, gdzie tego GUID-a ostatnio widziano.

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

Wersja protokołu: **4** (`lib/network/protocol.dart`, stała
`protocolVersion`). Podbijamy przy zmianach niekompatybilnych.

### Discovery (UDP 47777)

Skaner wysyła rozgłoszenie `chatt_discover` ze **swoją tożsamością i losowym
nonce**, każde urządzenie odpowiada unicastem `chatt_here`. Dzięki temu, że
zapytanie niesie tożsamość pytającego, **jeden skan uczy obie strony**.

Adresy rozgłoszeniowe: globalny `255.255.255.255` plus kierowany per interfejs,
liczony jak dla /24 (`dart:io` nie zdradza maski podsieci). Zapytanie leci dwa
razy w odstępie 400 ms, bo pojedynczy datagram w Wi‑Fi łatwo ginie.

Odpowiedź od **sparowanego** urządzenia niesie `tag`: HMAC-SHA256 kluczem
sesji z guida, portu i nonce'a z zapytania. Skaner wyrzuca z wyniku każdą
odpowiedź, która twierdzi, że jest znanym urządzeniem, a nie ma pasującego
podpisu. Bez tego ktoś znający sam GUID mógłby zająć jego miejsce na liście —
a stamtąd bierzemy adres, gdy rozmówcy zmieni się IP.

### Wiadomości i pliki (TCP 47780, konfigurowalny)

| Endpoint | Do czego |
|---|---|
| `GET /info` | tożsamość urządzenia; używane też jako „czy żyjesz" |
| `POST /message` | dostarczenie wiadomości; 200 = potwierdzenie |
| `POST /pair` | parowanie (cztery akcje, niżej) |
| `POST /file-offer` | zapowiedź pliku: nazwa, rozmiar, sha256 |
| `POST /file` | surowe bajty od podanego offsetu |

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

`drift` (SQLite), schemat w wersji **5**. Tabele: `settings`, `peers`,
`conversations`, `messages`. Migracje są napisane po kolei, więc baza
z wcześniejszej wersji aplikacji doczytuje się bez utraty danych:

| Wersja | Co doszło |
|---|---|
| 2 | pliki (kolumny transferu w `messages`) |
| 3 | `peers.sessionKey`; migracja kasuje `verified` przy parowaniach bez klucza |
| 4 | `settings.theme` |
| 5 | `settings.language` |

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

### Parowanie (protokół 4)

```
A → B   commit   sha256(pkA)              zobowiązanie do klucza
A ← B   odpowiedź z pkB                   B losuje własną parę
A → B   reveal   pkA                      B sprawdza zgodność ze skrótem
        obie strony liczą klucz sesji i sześciocyfrowy kod z X25519
        i pokazują kod na ekranie; użytkownicy porównują wzrokiem
A ⇄ B   confirm  (po kliknięciu na każdym urządzeniu)
```

Klucz zapisujemy dopiero, gdy potwierdzą **oba** końce.

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

- **Wiadomości i zapowiedzi plików**: koperta AES-GCM. Jawny zostaje sam GUID
  nadawcy, żeby odbiorca wiedział, którym kluczem odszyfrować; `from` ze środka
  musi się zgadzać z tym jawnym, inaczej sparowany rozmówca mógłby pisać
  w cudzym imieniu.
- **Treść plików**: strumień AES-CTR, bo tylko tak da się wznowić transfer od
  dowolnego bajtu. Nonce liczony z guida wiadomości **i sumy kontrolnej
  treści** — sam guid nie wystarcza, bo ponowienie po podmianie pliku pod tą
  samą ścieżką użyłoby drugi raz tego samego strumienia klucza.
- Integralności pliku pilnuje sha256 z **zaszyfrowanej** zapowiedzi, a nie
  z nagłówka.

### Reguła, na której to wszystko stoi

Od urządzenia, z którym mamy klucz, przyjmujemy **wyłącznie** ruch
zaszyfrowany (`_authenticated` w `app_services.dart`). Bez tego wystarczyłby
jeden jawny pakiet z cudzym GUID-em, żeby podszyć się pod zieloną tarczę. Trzy
testy w `test/downgrade_test.dart` odgrywają dokładnie ten atak.

### Co zostaje otwarte

- `POST /pair` nie jest uwierzytelniony, więc każdy może wywołać kartę
  parowania podszywając się nazwą pod znajomego. Klucza to nie podmieni (kody
  muszą się zgodzić na obu ekranach), ale karta ponownego parowania jest
  wyraźnie oznaczona na czerwono.
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
