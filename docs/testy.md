# Testy

Podział jest prosty: **69 testów `flutter test`** sprawdzają wszystko, co da się
sprawdzić bez sprzętu, a osobne scenariusze w `app/tool/` sterują żywą
aplikacją na urządzeniu. Rzeczy, których nie sprawdzi ani jedno, ani drugie,
są wypisane na końcu.

## Uruchamianie

```
cd app
C:\Users\mystt\dev\flutter\bin\flutter.bat test
C:\Users\mystt\dev\flutter\bin\flutter.bat analyze
```

Scenariusze na urządzeniu (wymagają `adb` i zainstalowanej aplikacji):

```
set ADB=C:\Users\mystt\AppData\Local\Android\Sdk\platform-tools\adb.exe
C:\Users\mystt\dev\flutter\bin\flutter.bat test tool/android_e2e_test.dart
C:\Users\mystt\dev\flutter\bin\flutter.bat test tool/wifi_discovery_check.dart
C:\Users\mystt\dev\flutter\bin\flutter.bat test tool/product_shots.dart
```

Zmienne: `ADB` (ścieżka do adb), `CHATT_DEVICE` (identyfikator z `adb devices`,
domyślnie `emulator-5554`).

## Jak testujemy komunikację bez dwóch urządzeń

Kluczowa sztuczka: `AppServices.start()` tworzy **kompletny stos aplikacji**
(baza w pamięci, serwer HTTP na losowym porcie, klient, discovery). Test
podnosi dwie takie instancje w jednym procesie i każe im rozmawiać ze sobą po
prawdziwym gnieździe TCP — nie ma tu żadnych atrap sieci. Dlatego testy łapią
też rzeczy, które w atrapach by przeszły: kolejność zapytań, kody odpowiedzi,
zachowanie przy zerwanym połączeniu.

Do trudniejszych scenariuszy testy stawiają między instancjami własny serwer
pośredniczący: raz jako podsłuch (sprawdzenie, że treść naprawdę nie leci
jawnym tekstem), raz jako łącze, które urywa się po N bajtach (wznawianie
transferu).

## Co jest pokryte

### Baza (`test/data_test.dart`, 7 testów)
- `ensureSettings` tworzy wiersz raz i zachowuje GUID
- `upsertPeer` aktualizuje adres po GUID, pusty host nie nadpisuje ostatniego dobrego
- wiadomości: dedupe po `messageGuid` i liczenie nieprzeczytanych
- status wiadomości: pending → failed → delivered
- usunięcie rozmówcy zabiera rozmowę i wiadomości
- kasowanie jednej wiadomości nie rusza reszty rozmowy ani rozmówcy
- sprzątanie zabiera tylko martwe wpisy bez historii

### Discovery (`test/discovery_test.dart`, 3 testy)
- skan znajduje drugą instancję i uczy ją o skanującym
- od znanego urządzenia przyjmujemy tylko podpisaną odpowiedź (podszycie się
  pod nie wypada z wyniku skanu)
- rozmówca ze zmienionym adresem jest odnajdywany po GUID

### Wiadomości (`test/messaging_e2e_test.dart`, 5 testów)
- parowanie po adresie, wymiana wiadomości w obie strony, dedupe
- odbiorca offline: failed, po powrocie retry dostarcza
- ręczne dodanie zapisuje adres, pod którym urządzenie **odpowiedziało**
  (a nie ten, którym się przedstawia — to była prawdziwa pluskwa, znaleziona
  dopiero na urządzeniu za NAT-em)
- nie rozmawiamy sami ze sobą (pętla na własny adres)
- serwer odrzuca śmieci bez wywracania się

### Pliki (`test/file_transfer_test.dart`, 9 testów)
- kilka plików naraz idzie po kolei, każdy z własnym pytaniem o zgodę (tą samą
  drogą co przeciągnięcie ich na okno)
- katalog podany razem z plikami jest pomijany bez wywrotki
- plik 3 MB dochodzi w całości, bajt w bajt
- odbiorca offline: failed, retry po powrocie dostarcza
- odmowa odbiorcy: żaden bajt nie leci, po zgodzie retry dostarcza
- uszkodzenie w locie (łącze przekręcające bajt): plik odrzucony, nic nie
  ląduje w odebranych
- część transferu z poprzedniej sesji nie jest dopisywana, transfer rusza od
  zera i składa się bajt w bajt
- nadawca wznawia po zerwaniu sieci: druga próba dosyła tylko resztę
- uszkodzone metadane → 400, serwer żyje dalej

### Kod QR (`test/pair_link_test.dart`, 3 testy)
- kod obchodzi całą drogę tam i z powrotem
- śmieci i cudze kody odpadają (aparat widzi mnóstwo kodów nie naszych)
- base64url bez wyrównania też się czyta

### Parowanie (`test/pairing_test.dart`, 8 testów)
- obie strony widzą **ten sam** kod, dopiero zgoda obu weryfikuje
- „nie zgadza się" po jednej stronie zrywa parowanie po obu
- klucz niezgodny ze zobowiązaniem jest odrzucany (tak wyglądałby napastnik
  dobierający klucze pod kod)
- ponowne potwierdzanie znanego urządzenia jest wyraźnie oznaczone
- pierwsze potwierdzenie nie straszy ostrzeżeniem
- zeskanowanie kodu potwierdza od razu u skanującego, a drugiej stronie
  stawia pytanie „czy to Ty skanowałeś"
- kod z cudzym kluczem pod czyimś adresem jest odrzucany
- parowanie z niedostępnym urządzeniem zwraca null

### Tożsamość i sesje (`test/identity_crypto_test.dart`, 8 testów)
- identyfikator liczy się z klucza publicznego i jest powtarzalny
- tożsamość przeżywa zapis i odczyt klucza prywatnego
- obie strony uścisku dłoni wyliczają ten sam klucz sesji
- **inne klucze efemeryczne dają inny klucz sesji** — to jest forward secrecy
  zapisane jako asercja, a nie obietnica w komentarzu
- podmieniony klucz statyczny psuje uzgodnienie
- klucz pliku wisi na kluczu sesji i guidzie wiadomości
- urządzenie rozgłasza klucz, a jego identyfikator z niego wynika

### Szyfrowanie (`test/encryption_test.dart`, 4 testy)
- sparowani: treść wiadomości nie leci jawnym tekstem (sprawdzane przez
  podsłuch na łączu, nie przez zaufanie kodowi)
- **niesparowani: treść też nie leci jawnym tekstem** — teza wydania 0.2.0
- sparowani: plik jedzie zaszyfrowany i składa się bajt w bajt
- sparowani: wznowienie zaszyfrowanego pliku dosyła tylko resztę

### Szukanie i miniatury (`test/search_test.dart`, 10 testów)
- szukanie nie patrzy na wielkość liter, a pusty napis pasuje do wszystkiego
- plik szuka się po nazwie, bo to ją widać w dymku
- lista rozmów filtruje się po nazwie rozmówcy i ostatniej wiadomości; rozmowa
  bez żadnej wiadomości nie wywala filtrowania
- miniaturę dostają tylko obrazki po rozszerzeniu, `zdjecie.png.exe` nie

### Baza na dysku (`test/encrypted_db_test.dart`, 9 testów)
- build naprawdę ma SQLite3MultipleCiphers (`PRAGMA cipher` coś zwraca)
  i `PRAGMA key` szyfruje: napisu z bazy nie widać w bajtach pliku
- zaszyfrowanej bazy nie da się otworzyć bez hasła
- jawna baza po starszej wersji przepisuje się z historią: wiadomości,
  rozmówcy i **potwierdzenie tożsamości** przeżywają, a drugi start nie ma
  już czego przepisywać
- klucz bazy: bez schowka systemowego zapisuje się jawnie, ale się nie zmienia
  między startami; ze schowkiem na dysk trafia co innego niż hasło; schowek,
  który przestał odwijać klucz, to błąd, a nie cicha pusta baza
- „wyczyść historię" zostawia urządzenia razem z potwierdzeniem
- granica wieku kasuje tylko wiadomości sprzed niej, a wyłączona (0 dni) nie
  kasuje niczego

### Odporność na obniżenie zabezpieczeń (`test/downgrade_test.dart`, 3 testy)
Napastnik zna identyfikator rozmówcy, ale nie zna jego klucza prywatnego:
- jawna wiadomość podszyta pod znanego rozmówcę jest odrzucana
- jawna zapowiedź pliku od znanego rozmówcy jest odrzucana
- jawny transfer nie podmieni pliku zapowiedzianego szyfrem

Te trzy testy powstały po tym, jak przegląd kodu znalazł dokładnie takie
dziury w pierwszej wersji szyfrowania. Od protokołu 5 broni ich już sam
protokół (jawnego tekstu nie ma), ale zostają jako świadek: gdyby kiedyś wrócił
awaryjny tryb bez szyfrowania, te testy zapalą się na czerwono.

## Scenariusze na żywym sprzęcie

### `tool/android_e2e_test.dart`
Instancja hosta na komputerze rozmawia z **aplikacją zainstalowaną na
urządzeniu** przez tunele adb (emulator siedzi za NAT-em, więc zwykła sieć
odpada):

```
adb forward tcp:47781 tcp:47780    host -> aplikacja na urządzeniu
adb reverse tcp:47790 tcp:47790    urządzenie -> instancja hosta
```

Trzy testy: `/info` z wiadomością i potwierdzeniem, plik z akceptacją klikniętą
na ekranie i sprawdzoną sumą, odmowa kończąca się statusem „nie dostarczono".
Test sam restartuje aplikację na starcie, klika przyciski znalezione po
etykiecie w drzewie dostępności i wysyła pliki o świeżej treści przy każdym
przebiegu — inaczej kolejne uruchomienia trafiały na stan po poprzednim.

### `tool/wifi_discovery_check.dart`
Rozgłasza zapytanie discovery w prawdziwej sieci i wypisuje, kto odpowiedział.
Tego jednego nie da się sprawdzić na emulatorze.

### `tool/product_shots.dart`
Zakłada demonstracyjną rozmowę i robi zrzuty do `docs/screenshots/produkt/`.
Po wszystkim czyści dane aplikacji, żeby na urządzeniu nie zostało demo.

### `tool/podglad_bazy.dart`
Mówi, ile czego jest w bazie, i czy plik w ogóle da się otworzyć bez hasła.
Po wydaniu 0.2.0 na zaszyfrowanej bazie odpowiada „nie da się odczytać" —
i o to chodzi.

### `tool/ui_e2e.sh`
Linuksowy scenariusz z dwiema instancjami pod Xvfb, sterowanymi xdotool —
używany w sesjach chmurowych, gdzie nie ma Androida.

## Czego testy nie sprawdzą

Świadome dziury w pokryciu, do sprawdzenia ręcznie przy wydaniu:

- **Zachowanie routera**: izolacja klientów w sieci gościnnej, rozgłoszenia
  między pasmami 2,4 i 5 GHz, maski inne niż /24 (skaner liczy adres
  rozgłoszeniowy jak dla /24 i dokłada globalny 255.255.255.255).
- **Producenckie ubijanie aplikacji** na Androidzie poza czystym systemem.
- **Tryb Doze** — sprawdzony ręcznie na telefonie (wiadomości dochodzą, bo
  usługa pierwszoplanowa znosi blokadę sieci), ale nie ma na to testu
  automatycznego.
- **UI na Windows** — nie ma testów widgetowych; sprawdzane jest klikaniem.
- **Bardzo duże pliki i słabe łącza** — testy jadą po pętli zwrotnej, więc nie
  łapią timeoutów typowych dla dalekiego Wi‑Fi.
