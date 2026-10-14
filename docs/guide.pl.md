# Instrukcja obsługi

*English version: [guide.md](guide.md)*

Chatt łączy dwa urządzenia: komputer z Windows i telefon z Androidem. Nie ma
konta, logowania ani serwera pośredniczącego: wiadomości i pliki idą prosto
z jednego urządzenia do drugiego.

Drogą jest **sieć lokalna**, gdy oba urządzenia siedzą w tej samej sieci
Wi‑Fi. Dodatek **Bluetooth**, domyślnie wyłączony, dokłada drugą drogę dla
urządzeń w zasięgu radia (około 10 metrów). Z włączonym dodatkiem obie drogi
działają naraz, a aplikacja sama wybiera, którą pójdzie.

## Pierwsze uruchomienie

1. Uruchom Chatt na obu urządzeniach i podłącz je do **tej samej sieci Wi‑Fi**.
   Komputer może być na kablu, o ile jest w tej samej podsieci co telefon.
   Bez wspólnej sieci zostaje dodatek Bluetooth, opisany niżej.
2. Na Windows przy pierwszym starcie zapora zapyta o zgodę na ruch
   przychodzący. Zaznacz sieć prywatną i pozwól, bo bez tego drugie urządzenie
   nie ma jak się połączyć.
3. Wejdź w **Ustawienia** i ustaw nick, po którym rozpoznasz to urządzenie
   na liście u rozmówcy.

Numer wersji stoi w pasku nad listą rozmów, a Ustawienia powtarzają go
w sekcji „To urządzenie". Przydaje się przy zgłaszaniu problemu.

## Znajdowanie drugiego urządzenia

Przycisk **W pobliżu** → **Szukaj urządzeń w sieci**. Skan rozsyła po sieci
jedno zapytanie i zbiera odpowiedzi przez dwie sekundy. Jeden skan uczy obie
strony nawzajem: urządzenie, które odpowiedziało, też zapamiętuje szukającego.

Ekran otwiera się bez listy. Pojawia się na nim to, co odpowiedziało na
ostatni skan, więc opisuje sieć taką, jaka jest w tej chwili.

<img src="screenshots/produkt/android_urzadzenia_w_poblizu.png" alt="Urządzenia w pobliżu" width="260">

Gdy skan nic nie znajduje:

- sprawdź, czy oba urządzenia są w tej samej sieci (nie: telefon na LTE);
- niektóre routery i sieci gościnne izolują klientów od siebie, wtedy
  rozgłoszenia nie przechodzą i trzeba dodać urządzenie ręcznie;
- **Dodaj po adresie IP**: adres i port drugiego urządzenia znajdziesz u niego
  w Ustawieniach, w sekcji „To urządzenie".

**Szukanie przez Bluetooth.** Ekran „W pobliżu" pyta najpierw o drogę: Sieć
albo Bluetooth. To pytanie pojawia się tylko z włączonym dodatkiem Bluetooth,
a sam Bluetooth jest do wzięcia, gdy radio działa. Radio samo z siebie nie
mówi, które urządzenie ma Chatta, więc
aplikacja próbuje się połączyć po kolei z tymi, które się odezwały, i zostawia
na liście te, które odpowiedziały jak Chatt. Idzie to dokładnie tą samą drogą
co ręczne dodanie po adresie IP. Szukanie trwa do półtorej minuty i zagłusza
radio na cały swój czas, więc rusza dopiero po Twoim kliknięciu.
Komputery i telefony są pytane najpierw, słuchawki na końcu, a urządzenie
trafia na listę w chwili, gdy odpowie, więc komputer obok zwykle widać po pół
minuty, jeszcze w trakcie szukania.

Na Androidzie szukanie wymaga włączonych usług lokalizacji. Chatt nie pyta,
gdzie jesteś, ale bez nich Android nie oddaje żadnych wyników; ekran „W
pobliżu" mówi o tym wprost i daje przycisk „Włącz lokalizację". Kiedy to nie
wchodzi w grę, „Dodaj po adresie radia" (ikona łącza na pasku) łączy się od
razu z adresem w rodzaju `70:D8:C2:64:D9:B1`, który drugie urządzenie pokazuje
w ustawieniach Bluetooth. Komputer pokazuje swój także na karcie dodatku
w Ustawieniach Chatta.

Na Androidzie 11 i starszym szukanie wymaga do tego zgody na lokalizację,
o którą Chatt nie prosi. Tam drugie urządzenie dodaje się po adresie radia.

Przytrzymanie wpisu na liście usuwa urządzenie. Przycisk „Wyczyść nieużywane
urządzenia" w Ustawieniach sprząta wpisy, z którymi nie ma żadnej wiadomości
i których nie widać od godziny.

## Dodatek Bluetooth

Bluetooth jest dodatkiem. W Ustawieniach, w sekcji **Dodatki**, stoi
przełącznik **Bluetooth**, wyłączony od początku. Dopóki jest wyłączony,
poza tą sekcją Bluetootha w aplikacji nie ma: żaden inny ekran o nim nie
wspomina, nic nie nasłuchuje na radiu, a sieć lokalna jest jedyną drogą.

Po włączeniu karta dodatku pokazuje resztę: czy radio jest wyłączone
w systemie, czy brakuje zgody (przycisk do jej wydania stoi obok), adres radia
tego urządzenia, o ile system go podaje, i przełącznik **Sieć lokalna** na
wypadek, gdy radio ma być jedyną drogą. Gdy sieć jest zgaszona, a radio nie
działa, karta ostrzega, że to urządzenie z nikim się nie połączy. Radio
włączone później w systemie albo zgoda wydana później podnoszą Bluetooth same,
w ciągu około dziesięciu sekund.

Na Androidzie o zgodę na Bluetooth aplikacja pyta w chwili włączania
dodatku, a potem już tylko przyciskiem na karcie dodatku, gdy zgodę cofnięto.
Parowania w systemie robić nie trzeba: Chatt łączy się także
z urządzeniem niesparowanym.

Na Windowsie włączony dodatek podnosi **wykrywalność komputera**: dopóki
dodatek stoi, komputer widzi każdy, kto rozgląda się w pobliżu za
urządzeniami. Domyślnie Windows pokazuje się tylko przy otwartym oknie „Dodaj
urządzenie". Wyłączenie dodatku gasi wykrywalność z powrotem. Karta dodatku
mówi o tym wprost.

**Którą drogą.** Aplikacja próbuje po kolei: najpierw ta, którą udało się
ostatnio, potem sieć, potem Bluetooth, i zapamiętuje tę, która zadziałała.
Sieć idzie pierwsza, bo jest kilkadziesiąt razy szybsza. Ręcznego przełącznika
drogi przy rozmówcy nie ma, wybór dzieje się sam.

**Ile to trwa.** Przez Bluetooth leci od 90 do 165 kB/s, czyli od 50 do 100
razy wolniej niż przez Wi‑Fi: megabajt idzie od 6 do 12 sekund. Krótka
wiadomość wraca w 22 do 25 ms, więc pisania nie odróżnisz od tego przez sieć.
Bolą dopiero pliki.

## Wiadomości

Kliknięcie urządzenia otwiera rozmowę. Pod nazwą rozmówcy widać, czy jest
w tej chwili dostępny.

Wpisy na liście rozmów niosą zieloną kropkę na awatarze, dopóki urządzenie
odpowiada w sieci, i zieloną tarczę przy nazwie, gdy jego tożsamość jest
potwierdzona. Z włączonym dodatkiem Bluetooth dochodzi ikona drogi (Wi‑Fi
albo Bluetooth), którą poszła ostatnia wymiana; w nagłówku rozmowy ta sama
ikona stoi z podpisem. Lista pyta każde znane urządzenie co 30 sekund, tylko
przy otwartym ekranie.

<img src="screenshots/produkt/android_rozmowa_z_plikiem.png" alt="Rozmowa" width="260">

Statusy przy wysłanej wiadomości:

| Ikona | Znaczenie |
|---|---|
| zegarek | zapisana u Ciebie, jeszcze niedostarczona |
| podwójny check | rozmówca potwierdził odbiór |
| „Nie dostarczono, ponów" | próba się nie udała, kliknij, żeby powtórzyć |

Wiadomość nigdy nie ginie po drodze: najpierw zapisuje się lokalnie, a dopiero
potem leci do rozmówcy. Jeśli w międzyczasie zmienił mu się adres IP,
aplikacja sama przeszuka sieć po jego identyfikatorze i ponowi wysyłkę pod
nowym adresem.

**Zaznaczanie tekstu.** Na komputerze przeciągnij kursorem po wiadomości albo
po kilku naraz i skopiuj przez Ctrl+C. Na telefonie ten gest jest zajęty przez
menu, więc zaznaczanie siedzi w środku: przytrzymaj dymek i wybierz „Zaznacz
tekst".

**Przytrzymanie dymka** daje menu: skopiowanie całej treści, zaznaczenie
fragmentu i skasowanie wiadomości. Na komputerze to samo menu otwiera prawy
przycisk myszy. Kasowanie działa tylko u Ciebie: protokół nie ma jak kazać drugiej stronie
zapomnieć czegoś, co już dostała, i aplikacja mówi to wprost.

<img src="screenshots/produkt/android_menu_wiadomosci.png" alt="Menu wiadomości" width="260">

**Lupa w pasku** szuka w otwartej rozmowie: lista zostawia same pasujące
wiadomości, a trafienie jest podświetlone. Ta sama lupa na liście rozmów
filtruje ją po nazwie rozmówcy i ostatniej wiadomości.

<img src="screenshots/produkt/android_szukanie_w_rozmowie.png" alt="Szukanie" width="260">

## Odnośniki w wiadomościach

Adres w wiadomości staje się **klikalnym odnośnikiem**, ale nic nie otwiera się
samo. Kliknięcie podnosi kartę z pytaniem, czy na pewno chcesz tam przejść, a
na tej karcie **nazwa serwera stoi osobno**, nad pełnym adresem, bo to ona
jedna decyduje, czyja to strona. Niżej dochodzą ostrzeżenia, gdy jest o czym
mówić: znak `@` w adresie (to, co widać przed nim, nie jest nazwą serwera),
litery spoza alfabetu łacińskiego w nazwie serwera, połączenie bez szyfrowania
oraz adres w Twojej własnej sieci lokalnej. Jest też „Kopiuj adres", gdy wolisz
najpierw mu się przyjrzeć.

Odnośnikiem stają się wyłącznie adresy `http` i `https`. Wszystko inne —
`javascript:`, `data:`, `file:` — zostaje zwykłym tekstem, bo kliknięcie w to
znaczyłoby „uruchom coś", a nie „pokaż stronę". Te same odnośniki pojawiają się
w menu dymka (przytrzymanie, na komputerze prawy przycisk); to pewniejsza droga
na komputerze, gdzie kliknięcie należy do zaznaczania tekstu.

**Podglądy stron** to osobna sprawa i domyślnie są wyłączone. Po włączeniu ich
w Ustawieniach, w sekcji **Odnośniki**, pod wiadomością pojawia się karta
z tytułem, opisem i obrazkiem strony, tak jak w innych komunikatorach. Warto
wiedzieć o dwóch rzeczach:

- Pobranie podglądu znaczy **połączenie z tą stroną**, więc jej serwer zobaczy
  adres IP tego urządzenia i moment, w którym wiadomość dotarła. Adres wybiera
  nadawca wiadomości, nie Ty. Dlatego przełącznik stoi wyłączony.
- Podgląd to **sam tekst i jeden obrazek**. Aplikacja nie otwiera strony, nie
  uruchamia z niej żadnych skryptów i nigdy nie pobiera podglądów spod adresów
  w Twojej sieci lokalnej, więc wiadomością nie da się wysłać Chatta na Twój
  router. Kartę dostaje tylko pierwszy odnośnik w wiadomości.

Wyłączenie przełącznika zatrzymuje pobieranie od razu i wyrzuca podglądy, które
zdążyły przyjść.

## Pliki

Spinacz przy polu tekstowym otwiera systemowy wybór pliku; **można zaznaczyć
kilka naraz**. Na komputerze pliki da się też po prostu **przeciągnąć na okno
rozmowy**. Odbiorca **najpierw dostaje pytanie**, czy chce ten plik przyjąć,
i dopiero po zgodzie lecą bajty.

**Kilka plików to jedno pytanie.** Karta wymienia wszystkie nazwy z paczki
i podaje łączny rozmiar, a jedno „Przyjmij wszystkie" obejmuje całość; pliki
i tak idą po kolei, każdy z własnym paskiem postępu. Odmowa dotyczy całej
paczki, a reszty nadawca nawet nie zapowiada. Wynikają z tego dwie rzeczy, obie
świadomie: zgody nie da się cofnąć, gdy pliki już idą, a plik, który przestał
się zgadzać z zapowiedzią (urósł po drodze albo nie było go na liście), dostaje
osobne pytanie. Więcej niż sto plików naraz przychodzi paczkami po sto, każda
z własnym pytaniem.

**Wklejanie.** To, co leży w schowku, trafia do rozmowy wprost, bez szukania
tego wcześniej w katalogu. Na komputerze robi to **Ctrl+V** na ekranie
rozmowy: plik skopiowany w Eksploratorze, zrzut ekranu zrobiony przez
Win+Shift+S, obrazek skopiowany na stronie. Plik z Eksploratora idzie taki,
jaki leży; obrazek bez własnego pliku zapisuje się najpierw jako PNG
w katalogu tymczasowym i to ta kopia jedzie dalej.

Tekst wkleja się do pola wiadomości tak jak zawsze i tekst wygrywa:
zaznaczenie komórek w Excelu albo akapitu w Wordzie niesie w schowku także
swój obrazek, a Chatt zostawia go w spokoju, zamiast wysyłać rozmówcy zrzut,
o który nikt nie prosił. Ctrl+V w polu szukania należy do tego pola: wkleja
się tam sam tekst.

Gdy w schowku coś jest, spinacz pyta, o którą z dwóch dróg chodzi; gdy nie ma
nic, otwiera wybór pliku od razu, tak jak wcześniej.

Na telefonie nie ma Ctrl+V, więc zostaje spinacz. Drugą drogą jest klawiatura:
przyciski od obrazków i GIF-ów w Gboardzie wysyłają teraz prosto do rozmowy.

<img src="screenshots/produkt/android_prosba_o_plik.png" alt="Prośba o plik" width="260">

- Odmowa oznacza zero przesłanych danych; nadawca widzi „nie dostarczono"
  i może spróbować później.
- Brak odpowiedzi przez dwie minuty liczy się jak odmowa.
- Przerwany transfer (zerwane Wi‑Fi, uśpiony telefon) zostaje na dysku jako
  część. Kolejna próba **dokłada tylko brakujący kawałek**, a po złożeniu
  całości aplikacja sprawdza sumę kontrolną. Gdy coś się nie zgadza, plik
  jest odrzucany.
- Ponowienie po zgubionym potwierdzeniu nie pyta o zgodę drugi raz i nie
  przesyła ani bajtu: odbiorca odpowiada „już to mam".

Odebrane pliki lądują w katalogu aplikacji. Kliknięcie w dymek otwiera plik,
a przytrzymanie daje „Pokaż folder", „Udostępnij", „Kopiuj ścieżkę"
i „Usuń wiadomość". Na Windowsie obrazek dostaje dodatkowo **„Kopiuj obraz"**,
które kładzie go do schowka i jako obraz (wkleisz do dokumentu albo do edytora
grafiki), i jako plik (wkleisz w Eksploratorze).

Strzałka w dół przy odebranym pliku **zapisuje jego kopię tam, gdzie będziesz
go szukać**: na Androidzie obrazki trafiają do `Pictures/Chatt` (widzi je
galeria), reszta do `Pobrane`; na komputerze otwiera się systemowe okno
zapisu. Bez tego plik siedzi w katalogu aplikacji, którego nie widzi żaden
menedżer plików i który znika przy odinstalowaniu.

Obrazki dostają w rozmowie **miniaturę**, ale dopiero po przyjęciu pliku.
Dekodowanie obrazka od obcego to powierzchnia ataku, więc dekoder dostaje
wyłącznie to, na co sam się zgodziłeś i co już leży na dysku.

<img src="screenshots/produkt/android_miniatura_obrazka.png" alt="Miniatura obrazka" width="260">

**Stuknięcie w miniaturę otwiera zdjęcie na pełnym ekranie.** Powiększasz
szczypaniem albo kółkiem myszy, przesuwasz palcem, dwuklik przybliża w to
miejsce, w które stuknąłeś, a kolejny wraca do całości; przycisk w rogu obraca
co ćwierć obrotu. Obrót dotyczy tego, na co patrzysz, nigdy pliku — ten zostaje
dokładnie taki, jaki przyszedł. W górnym pasku są te same akcje co w rozmowie,
więc zdjęcie da się zapisać albo udostępnić bez cofania się, a na komputerze
Esc zamyka podgląd.

Zdjęcie rysuje sam Chatt i nie oddaje go żadnej innej aplikacji, więc otworzy
się niezależnie od tego, czy w systemie jest czym oglądać obrazki. Pozostałe
pliki dalej otwierają się tym, co system ma do nich skojarzone.

## Szyfrowanie i potwierdzanie tożsamości

**Rozmowa jest szyfrowana od pierwszej wiadomości**, także z urządzeniem,
którego jeszcze nie potwierdziłeś. Potwierdzenie odpowiada na jedno pytanie:
czy po drugiej stronie jest ta osoba, o której myślę. Treści i tak nikt inny
nie przeczyta.

Tarcza w nagłówku rozmowy otwiera panel bezpieczeństwa: stan szyfrowania
i odciski obu kluczy. Odcisk wynika z klucza urządzenia i nigdy się nie
zmienia, więc możesz go odczytać na głos i sprawdzić na drugim ekranie
w dowolnym momencie.

Do potwierdzenia tożsamości są dwie drogi:

- **Kod QR** (szybsza i pewniejsza). Jedno urządzenie pokazuje kod, drugie go
  skanuje. Skanujący ma pewność od razu, bo widział tamten ekran. Urządzenie,
  które kod pokazywało, zapyta jeszcze „czy to Ty właśnie skanowałeś":
  potwierdź tylko wtedy, gdy faktycznie Ty.
- **Porównanie kodu** (gdy nie ma aparatu, np. komputer z komputerem). **Oba
  urządzenia pokazują ten sam sześciocyfrowy kod.** Porównaj je wzrokiem
  i kliknij „Zgadza się" na obu.

<img src="screenshots/android/and16_kod_do_porownania.png" alt="Kod do porównania" width="260">

- Kod nie jest hasłem i nie idzie przez sieć: wychodzi z uzgodnienia kluczy,
  które robią między sobą oba urządzenia. W kodzie QR też nie ma nic tajnego,
  liczy się to, że drugie urządzenie zobaczyło go na Twoim ekranie.
- Jeśli kody się **różnią**, ktoś siedzi w środku połączenia. Kliknij „Nie
  zgadza się" i sprawdź sieć.
- Po potwierdzeniu tarcza robi się zielona. Szyfrowanie działało już wcześniej;
  zmienia się to, że od teraz wiadomo, do kogo należy klucz po drugiej
  stronie.
- Nazwa urządzenia to tylko napis, który każdy może sobie ustawić dowolnie.
  Dlatego prośba o plik od urządzenia bez potwierdzonej tożsamości wyświetla
  ostrzeżenie, a prośba o ponowne potwierdzenie znanego już urządzenia jest
  oznaczona na czerwono.

**Przez Bluetooth jest tak samo.** Łącze radiowe niesie ten sam uścisk dłoni,
te same zaszyfrowane koperty i ten sam strumień pliku co połączenie w sieci,
więc pytanie o paczkę plików, kod do porównania i kod QR działają bez różnicy.
Radio jest tu zwykłym kablem: parowanie w systemie niczego nie dokłada,
a zielona tarcza dalej bierze się wyłącznie z porównanego kodu albo ze
skanu QR.

Z włączonym dodatkiem dochodzi nowy napastnik: ktoś w zasięgu radia, około
10 metrów. Jawne zostają wtedy nazwa urządzenia i adres jego radia, dokładnie
tak jak dziś jawne jest rozgłoszenie po sieci lokalnej.

Adres radia ląduje w bazie obok adresu IP i jest wskazówką, gdzie szukać
rozmówcy. Rozpoznanie idzie po kluczu, a adres nadpisuje się przy każdym
kontakcie. Po co ta ostrożność, widać na sprzęcie: ten sam komputer potrafi
pokazać się telefonowi pod dwoma różnymi adresami radia, zależnie od tego, czy
telefon był z nim sparowany.

W tym samym panelu siedzą dwie rzeczy, które należą do rozmówcy:

- **Zmień nazwę.** Urządzenie rozgłasza własną nazwę, więc komputer trafia na
  listę jako coś w rodzaju `DESKTOP-8F2A1C`. Nadaj mu swoją i to ją zobaczysz
  wszędzie. Nazwa zostaje na tym urządzeniu, nigdzie nie jedzie, a rozgłaszana
  wyświetla się pod nią, żeby dało się zauważyć, że druga strona się
  przemianowała. Puste pole wraca do rozgłaszanej.
- **Przyjmuj pliki bez pytania.** Pliki od tego urządzenia trafiają wtedy prosto
  do rozmowy, bez karty z pytaniem. Przełącznik działa wyłącznie przy zielonej
  tarczy i gaśnie sam, gdy potwierdzenie zniknie: zgoda dotyczyła potwierdzonej
  tożsamości.

## Nasłuch w tle na Androidzie

Zamknięcie okna nie wyłącza odbierania. Aplikacja trzyma usługę
pierwszoplanową ze stałym powiadomieniem „Chatt nasłuchuje", dzięki czemu
wiadomości i pliki dochodzą też przy zgaszonym ekranie, a o nowej wiadomości
dostajesz powiadomienie.

W Ustawieniach, w sekcji **Nasłuch w tle**, aplikacja mówi, czy system jej nie
usypia. Jeśli ostrzega, kliknij „Wyłącz optymalizację baterii". Na większości
telefonów usługa pierwszoplanowa wystarcza sama z siebie, ale część
producentów dokłada własne mechanizmy ubijania aplikacji.

Nasłuch przez Bluetooth przy zgaszonym ekranie nie był jeszcze sprawdzony na
sprzęcie.

<img src="screenshots/produkt/android_ustawienia.png" alt="Ustawienia" width="260">

## Nasłuch w tle na Windowsie

Zamknięcie okna krzyżykiem **chowa Chatta do zasobnika**: nasłuch działa
dalej, a okno wraca kliknięciem ikony. Wyjście
z programu jest w menu tej ikony (prawy przycisk → „Zamknij Chatt").

Windows 11 chowa nowe ikony pod strzałkę „pokaż ukryte ikony". Żeby Chatt
siedział widocznie na pasku, przeciągnij go stamtąd na pasek albo przypnij
w ustawieniach zasobnika systemu.

W Ustawieniach, w sekcji **Windows**, jest przełącznik **„Uruchamiaj razem
z Windowsem"**. Włączony sprawia, że aplikacja wstaje po zalogowaniu i od razu
siada w zasobniku, bez otwierania okna. Pod spodem to zwykły wpis autostartu
konta użytkownika: bez usług i bez uprawnień administratora, więc da się go
skasować także ręcznie.

## Okno na komputerze

Od 900 pikseli szerokości okno pokazuje **dwa panele**: listę rozmów po lewej
i otwartą rozmowę po prawej, bez przeskakiwania między ekranami. Węższe okno
działa jak dotąd, jeden ekran naraz.

<img src="screenshots/windows/pl/04_plik_z_miniatura.png" alt="Dwa panele na Windows" width="760">

Treść ma górną granicę szerokości: dymki do 560 pikseli, formularze do 760.
Na monitorze 27 cali linia ciągnąca się przez pół metra jest nie do czytania,
a oko gubi początek następnej.

## Instalacja na Windowsie

Wydanie daje dwie rzeczy do wyboru:

- **`chatt-X.Y.Z-windows-instalator.exe`**: zwykły instalator, ze skrótem
  w menu Start, odinstalowaniem z ustawień systemu i jednym miejscem na
  aktualizację. Instaluje dla Twojego konta, więc nie pyta o hasło
  administratora.
- **`chatt-X.Y.Z-windows.zip`**: wersja przenośna. Rozpakuj gdziekolwiek
  i uruchom `chatt.exe`. Nic nie zapisuje w systemie poza własnymi danymi.

Odinstalowanie kasuje wpis autostartu, ale **nie rusza historii rozmów**:
baza leży w Dokumentach i po ponownej instalacji jest na miejscu. Żeby
naprawdę się jej pozbyć, użyj „Wyczyść historię" przed odinstalowaniem.

## Nadążanie za wersjami

W Ustawieniach jest sekcja **Aktualizacje**. Przy pierwszym wejściu stoi
wyłączona i dopóki taka jest, aplikacja nie odzywa się nigdzie poza Twoją
sieć. Włączona pyta GitHuba raz na dobę, czy wyszło nowsze wydanie, a przycisk
**Sprawdź teraz** pyta od razu, niezależnie od przełącznika.

Gdy coś nowszego jest, pokazuje się numer, opis wydania i przycisk **Pobierz
i zainstaluj**. Na Windowsie rusza instalator, a Chatt zamyka się, żeby mu nie
przeszkadzać, i wraca sam. Na Androidzie pobrany plik trafia do systemowego
instalatora, który pyta o zgodę. Wersja przenośna z zipa dostaje zamiast
przycisku adres strony wydania, bo instalator zostawiłby katalog, z którego
właśnie chodzi, bez zmian.

Historia rozmów i odebrane pliki zostają nietknięte w obu przypadkach.

Gdy coś zawiedzie przed pokazaniem okna, Chatt mówi to na własnym ekranie
i zapisuje `chatt-startup-error.txt` obok bazy w Dokumentach. Historia rozmów
i odebrane pliki zostają nietknięte, a treść tego pliku jest tym, co warto
dołączyć do zgłoszenia.

Instalator nie jest podpisany certyfikatem, więc SmartScreen pokaże
ostrzeżenie „Windows chronił Twój komputer". „Więcej informacji" → „Uruchom
mimo to". Certyfikat do podpisu kodu kosztuje kilkaset złotych rocznie i nie
zmieniłby nic w tym, co robi program.

## Wygląd i język

W Ustawieniach wybierasz motyw (systemowy, jasny, ciemny), **tło** i język
(systemowy, polski, angielski). Wszystkie wybory siedzą w bazie, więc
przeżywają restart. Świeża instalacja startuje po angielsku, polski jest
o jedno dotknięcie dalej.

Krótkie komunikaty („Skopiowano", „Usunięto rozmowę") pokazują się w prawym
górnym rogu, z paskiem odliczającym czas do zniknięcia. Kliknięcie zamyka je od
razu. Na górze nie zasłaniają przycisku ani pola tekstowego, którego przed
chwilą użyłeś.

Tła to gotowe zestawy: „Bez tła" (zwykły kolor motywu), Zmierzch, Ocean,
Las i Piasek. Każdy ma osobne kolory na motyw jasny i ciemny, a wszystkie są
celowo przygaszone: na tle leżą dymki i karty, które muszą zostać czytelne.
Powiadomienia usługi w tle też idą za językiem aplikacji.

<img src="screenshots/produkt/android_lista_rozmow_ciemny.png" alt="Tryb ciemny" width="260">

## Prywatność: co leży na dysku

Historia rozmów leży na dysku **zaszyfrowana**, a klucz do niej trzyma schowek
systemowy (Keystore na Androidzie, DPAPI na Windowsie). Skopiowanie samego
pliku bazy nic nie daje. Ustawienia mówią o tym wprost, razem z ostrzeżeniem,
gdyby na danym urządzeniu schowek nie zadziałał.

<img src="screenshots/android/and20_prywatnosc.png" alt="Prywatność" width="260">

Tam samym są dwie rzeczy do zrobienia ręcznie:

- **Kasuj wiadomości starsze niż**: do wyboru 7, 30, 90 albo 365 dni.
  Domyślnie wyłączone. Aplikacja sprząta przy starcie, po zmianie ustawienia
  i co sześć godzin.
- **Wyczyść historię**: kasuje wszystkie wiadomości i rozmowy od razu.
  Nieodwracalne, więc pyta o potwierdzenie. Urządzenia razem z potwierdzoną
  tożsamością zostają, więc nie trzeba się parować od nowa.

<img src="screenshots/android/and21_wyczysc_historie.png" alt="Wyczyść historię" width="260">

W obu przypadkach **odebrane pliki zostają na dysku**. Aplikacja kasuje własne
wpisy; pliki, które otwierasz innymi programami, zostają.

## Dwie instancje na jednym komputerze

Do testów bez drugiego urządzenia: druga instancja musi dostać własny katalog
danych, port dobierze sobie sama.

```powershell
$env:CHATT_DATA_DIR = "$env:TEMP\chatt-b"
$env:CHATT_INSTANCE_NAME = "Instancja B"
.\build\windows\x64\runner\Release\chatt.exe
```
