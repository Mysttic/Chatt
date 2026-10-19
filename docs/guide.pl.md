# Instrukcja obsługi

*English version: [guide.md](guide.md)*

Chatt łączy dwa urządzenia: komputer z Windows i telefon z Androidem. Nie ma
konta, logowania ani serwera pośredniczącego: wiadomości i pliki idą prosto
z jednego urządzenia do drugiego.

Drogą jest **sieć lokalna**, gdy oba urządzenia siedzą w tej samej sieci
Wi‑Fi. Dodatek **Bluetooth**, domyślnie wyłączony, dokłada drugą drogę dla
urządzeń w zasięgu radia (około 10 metrów). Z włączonym dodatkiem obie drogi
działają naraz, a aplikacja sama wybiera, którą pójdzie.

Drugi dodatek, **Klawiatura z PC**, też domyślnie wyłączony, pozwala pisać
klawiaturą komputera w polu na telefonie albo na innym komputerze.

## Pierwsze uruchomienie

1. Uruchom Chatt na obu urządzeniach i podłącz je do **tej samej sieci Wi‑Fi**.
   Komputer może być na kablu, o ile jest w tej samej podsieci co telefon.
   Bez wspólnej sieci zostaje dodatek Bluetooth, opisany niżej.
2. Na Windows przy pierwszym starcie zapora zapyta o zgodę na ruch
   przychodzący. Zaznacz sieć prywatną i pozwól, bo bez tego drugie urządzenie
   nie ma jak się połączyć.
3. Wejdź w **Ustawienia** i ustaw nick, po którym rozpoznasz to urządzenie
   na liście u rozmówcy.

Na górze listy rozmów stoi nazwa tego urządzenia. Numer wersji jest
w Ustawieniach, w sekcji **Aktualizacje**. Na samym dole Ustawień panel **To
urządzenie** zbiera adresy, pod którymi urządzenie słucha, adres Bluetooth
(przy włączonym dodatku, gdy system go podaje), identyfikator i odcisk klucza.
Każdą wartość kopiuje przycisk obok. Przydaje się przy zgłaszaniu problemu
i przy dodawaniu po adresie IP.

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

**Telefon musi się pokazać.** Android jest widoczny przez radio tylko przy
otwartym ekranie parowania w ustawieniach Bluetooth, więc szukanie samo
telefonu nie znajdzie. Na telefonie, który ma zostać znaleziony, otwórz „W
pobliżu", wybierz Bluetooth i stuknij **Pokaż ten telefon w pobliżu**. Android
zapyta własnym okienkiem, a potem telefon jest widoczny przez około dwie
minuty i w miejscu przycisku stoi napis. W tym czasie uruchom szukanie na
drugim urządzeniu. Komputer tego nie potrzebuje: dodatek trzyma go widocznym.

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

Przeszkadza jedno: stare parowanie, które pamięta tylko jedna strona. Telefon
ma komputer na liście sparowanych, a komputer o telefonie już zapomniał.
Android prosi wtedy o ponowne parowanie i zrywa łącze. Wystarczy usunąć
komputer z listy w ustawieniach Bluetooth telefonu (albo sparować urządzenia
od nowa) i Chatt się połączy.

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

## Dodatek „Klawiatura z PC”

Dodatek ma własną stronę, krok po kroku, z obrazkami z Windows i z Androida:
[Klawiatura z PC](keyboard.pl.md). Niżej jest wersja skrócona.

Telefon, tablet albo komputer obsługiwany samym dotykiem nie ma porządnej
klawiatury. Dodatek **Klawiatura z PC** pożycza mu klawiaturę komputera:
wskazujesz pole na tamtym urządzeniu stuknięciem albo kliknięciem, a to, co
piszesz na komputerze, trafia do tego pola, w dowolnej aplikacji. Chatt nie
pokazuje tamtego ekranu i niczym na nim nie rusza; patrzysz na samo
urządzenie.

Przechodzi tekst (z polskimi znakami i nowymi liniami), Backspace, Delete,
Enter, a na Androidzie także akcja pola (Szukaj, Wyślij, Dalej, Gotowe), oraz
tekst ze schowka komputera. Skróty z Ctrl, Alt i Win, Tab, Esc, strzałki, Home
i End oraz mysz zostają w domu. Komputer pisze na telefonie albo tablecie
z Androidem i na innym komputerze z Windows, przez sieć, a przy włączonym
dodatku Bluetooth także przez radio.

<img src="screenshots/windows/pl/06_klawiatura_pisanie.png" alt="Pisanie z komputera na telefonie" width="760">

**Włączenie.** Ustawienia, **Dodatki**, **Klawiatura z PC**, wyłączony od
początku. Na komputerze, z którego się pisze, ten jeden przełącznik
wystarcza. Na urządzeniu, na którym ma się pisać, karta dodatku ma drugi
przełącznik, **Pozwól pisać na tym urządzeniu**, też wyłączony od początku:
włączenie dodatku na Twoim komputerze nikogo nie wpuszcza do pisania na tym
komputerze. Dopóki dodatek jest wyłączony, żaden inny ekran go nie pokazuje.

Oba urządzenia muszą mieć nawzajem potwierdzoną tożsamość (zielona tarcza,
patrz [Szyfrowanie i potwierdzanie tożsamości](#szyfrowanie-i-potwierdzanie-tożsamości)).
Pisanie obejmuje hasła, więc idzie wyłącznie między urządzeniami, które
sprawdziły nawzajem swoje klucze.

**Klawiatura Chatt na Androidzie.** Android pozwala aplikacji pisać w polach
innych aplikacji przez klawiaturę, więc dodatek przynosi własną: klawiaturę
Chatt, która nie ma klawiszy. Na systemowej liście klawiatur stoi wyłącznie
przy włączonym dodatku, a w systemie trzeba ją raz włączyć: przycisk **Włącz
klawiaturę Chatt** na karcie dodatku otwiera systemowe ustawienia klawiatur.
Android ostrzega po drodze dwa razy:

- że klawiatura może zbierać wszystko, co się nią pisze, także hasła.
  Klawiatura Chatt niczego z Twoich pól nie wysyła: wpisuje to, co przyjdzie
  od urządzenia, któremu pozwolisz pisać, w trakcie sesji, na którą się
  zgodzisz;
- że po ponownym uruchomieniu telefonu aplikacja nie wystartuje, dopóki go
  nie odblokujesz.

Na co klawiatura patrzy, opisuje [polityka prywatności](privacy-policy.md)
(po angielsku).

Na co dzień piszesz dalej swoją klawiaturą. Klawiatura Chatt przejmuje
miejsce na czas sesji i oddaje je, gdy sesja się skończy.

**Początek.** Otwórz rozmowę z drugim urządzeniem i wybierz przycisk
klawiatury u góry (na telefonie: menu **⋮**, **Pisz na tamtym urządzeniu**).
Jest tam tylko przy włączonym dodatku i działa tylko przy zielonej tarczy.
Ekran **Piszesz na: X** prosi drugie urządzenie i czeka. Tam
pojawia się karta „X chce pisać na tym urządzeniu” z przyciskami **Odrzuć**
i **Akceptuj** oraz polem **Nie pytaj więcej dla tego urządzenia**. Fokus stoi
na Odrzuć, więc przypadkowy Enter odmawia. Bez odpowiedzi prośba gaśnie po
dwóch minutach.

<img src="screenshots/windows/pl/07_klawiatura_zgoda.png" alt="Karta zgody na komputerze" width="760">

**Na telefonie z Androidem** **Akceptuj** otwiera okno wyboru klawiatury, o ile
klawiatura Chatt nie jest już wybrana: wybierz **Klawiatura Chatt**. Chatt schodzi wtedy na bok, do aplikacji, w której
byłeś, a Ty stukasz pole do wypełnienia. Tam, gdzie była klawiatura, pojawia
się pasek z tym, kto pisze i do jakiej aplikacji („Pisze: PC → Kontakty”),
z przyciskami **Przełącz klawiaturę** i **Stop**. Po końcu sesji wraca sama
poprzednia klawiatura. Przy zaznaczonym „Nie pytaj więcej” i Chatcie w tle
przychodzi powiadomienie „Przełącz klawiaturę na Chatt”; dotknij go. Pisanie
idzie za Tobą z aplikacji do aplikacji, także do Chatt, aż do końca sesji.
Przy zablokowanym albo wygaszonym ekranie nic się nie wpisuje. Ekran blokady
z PIN-em zostawia klawiaturę Chatt; ekran z hasłem tekstowym dostaje zwykłą
klawiaturę, żeby dało się wpisać hasło, a po odblokowaniu znów przychodzi
„Przełącz klawiaturę na Chatt”: jedno dotknięcie i pisanie trwa dalej. Stałe powiadomienie
Chatt mówi przez całą sesję, kto pisze.

**Na komputerze z Windows** tekst trafia do okna na wierzchu, tam, gdzie stoi
jego kursor. Pole wskazujesz kliknięciem, a na ekranie dotykowym palcem. Przez
całą sesję na wierzchu ekranu stoi pasek ze **Stopem**, który nigdy nie zabiera
fokusu Twojemu polu, a ikona w zasobniku dostaje plakietkę i pozycję
**Zatrzymaj zdalną klawiaturę** w menu. Karta, która przyjdzie, gdy Chatt siedzi
w zasobniku, wyciąga okno i chowa je z powrotem po odpowiedzi. Na komputerze
z ekranem dotykowym po stuknięciu w pole może wysunąć się klawiatura dotykowa;
nie przeszkadza, a zamknąć ją możesz.

W samym Chatcie nad każdym ekranem stoi pasek z tym, kto pisze, i ze Stopem.

<img src="screenshots/windows/pl/08_klawiatura_odbior.png" alt="Pasek „Pisze” i karta dodatku" width="760">

**Na komputerze, z którego piszesz**, ekran ma dwa tryby:

- **Znak po znaku** wysyła każdy znak w chwili pisania. Enter to Enter pola
  (albo Szukaj, Wyślij, Dalej na Androidzie), Shift+Enter nowa linia, Backspace
  i Delete kasują po tamtej stronie, Ctrl+V wkleja. Pole na Twoim ekranie
  pokazuje echo tego, co poszło od ostatniego Entera, z kursorem przypiętym na
  końcu; przesunięcie go nie przesunęłoby kursora po tamtej stronie.
- **Całość naraz** pozwala najpierw napisać cały tekst i wysłać go przyciskiem
  **Wyślij** albo Ctrl+Enter, z zaznaczonym **Potem Enter**, gdy pole ma zostać
  zatwierdzone.

**Wklej ze schowka** wysyła tekst ze schowka komputera w obu trybach.

Nowa linia to jedyna rzecz, która na komputerze z Windows ląduje inaczej:
przychodzi tam jako zwykły Enter. W edytorze tekstu to nowa linia,
a w komunikatorze, który wysyła Enterem, wysyła wiadomość.

Wiersz u góry mówi, dokąd idzie pisanie („Pisze do: Notatki”), albo czemu nic
się nie wpisze: zablokowany ekran, okno z uprawnieniami administratora, brak
pola, pytanie czekające na którymś z urządzeń. Dopóki tekst nie ma dokąd trafić, pole nie przyjmuje pisania.
Dopóki druga strona nie zgłosi zwykłego pola tekstowego, echo i pole „Całość
naraz” pokazują kropki: przy polu hasła i przy polu, którego rodzaju Chatt nie
rozpozna, co zdarza się w niektórych programach na Windowsie. To, co wpisałeś
pod kropkami, zostaje pod nimi, dopóki nie zniknie z pola.

**Koniec.** Stop na pasku, na klawiaturze Chatt, w menu zasobnika albo
w aplikacji, po każdej stronie; zamknięcie ekranu pisania na komputerze;
wyłączenie dodatku albo **Pozwól pisać na tym urządzeniu**. Sesja kończy się
też sama po pół godzinie bez pisania i w każdym razie po ośmiu godzinach. Sesja,
która się zerwała (padło łącze, Stop po tamtej stronie), zostawia ekran
otwarty z przyciskiem **Połącz ponownie**.

**Bez pytania.** „Nie pytaj więcej” na karcie albo **Pisanie bez pytania**
w panelu bezpieczeństwa rozmowy (widoczne tylko przy włączonym dodatku)
pozwala temu jednemu urządzeniu zacząć pisać bez karty. Paski i Stop pokazują
się jak zawsze. Działa wyłącznie przy zielonej tarczy i znika razem
z urządzeniem, gdy usuniesz z listy rozmowę z nim (a z nią urządzenie).

**Czego nie ma.** Ekranu blokady, a na Androidzie także wygaszonego ekranu. Na
Windowsie okien
z uprawnieniami administratora, okien Kontroli konta użytkownika i ekranu
logowania: Windows nie pozwala zwykłemu programowi tam pisać, a komputer,
z którego piszesz, mówi o tym. Kart z pytaniami Chatt: gdy któraś czeka na
którymkolwiek z urządzeń, nic się nie wpisuje, więc zdalny Enter nigdy nie
odpowie na kartę. Pola tekstowe samego Chatt przyjmują pisanie jak pola każdej
innej aplikacji.

**Historia pisania.** Przy włączonym **Zapisuj historię pisania** (przełącznik
na karcie dodatku, włączony od początku) oba urządzenia zapisują każdą sesję
w swojej zaszyfrowanej bazie: co wpisano, do której aplikacji, kiedy i czy
dotarło. Tekst wpisany w pole hasła albo w pole, którego rodzaju Chatt nie
rozpozna, zostaje zapisany jako liczba znaków. Historię znajdziesz
w Ustawieniach: **Dane i diagnostyka**, **Historia pisania** (patrz
[Dane i diagnostyka](#dane-i-diagnostyka)). Sam tekst jedzie zaszyfrowany,
tak jak wiadomości, i wyłącznie między tymi dwoma urządzeniami.

## Wiadomości

Kliknięcie urządzenia otwiera rozmowę. Pod nazwą rozmówcy widać, czy jest
w tej chwili dostępny.

Wpisy na liście rozmów niosą zieloną kropkę na awatarze, dopóki urządzenie
odpowiada w sieci, i zieloną tarczę przy nazwie, gdy jego tożsamość jest
potwierdzona. Z włączonym dodatkiem Bluetooth dochodzi ikona drogi (Wi‑Fi
albo Bluetooth), którą poszła ostatnia wymiana; w nagłówku rozmowy stoi ta
sama ikona, a jej podpis pokazuje się po najechaniu albo przytrzymaniu. Lista
pyta każde znane urządzenie co 30 sekund, tylko przy otwartym ekranie.

Na telefonie nagłówek rozmowy ma tylko tarczę i menu **⋮**. Tarcza stoi na
tle w kolorze stanu: zielonym przy potwierdzonej tożsamości, w kolorze
ostrzeżenia przy niepotwierdzonej. Szukanie i klawiatura z PC siedzą w menu.
Na szerokim oknie oba przyciski stoją w nagłówku obok tarczy.

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

**Szukaj w rozmowie** (lupa w pasku na szerokim oknie, menu **⋮** na
telefonie) szuka w otwartej rozmowie: lista zostawia same pasujące
wiadomości, a trafienie jest podświetlone. Ta sama lupa na liście rozmów
filtruje ją po nazwie rozmówcy i ostatniej wiadomości.

<img src="screenshots/produkt/android_szukanie_w_rozmowie.png" alt="Szukanie" width="260">

Dymki pokazują samą godzinę. Pierwsza wiadomość każdego dnia dostaje nad sobą
datę: „Dzisiaj", „Wczoraj" albo pełną datę.

## Odzyskiwanie historii rozmowy

Rozmowa żyje na obu urządzeniach. Gdy Twoje ją straci (reinstalacja, nowy
telefon, **Wyczyść historię**, samoczynne kasowanie), druga strona może oddać
swoją kopię. Menu **⋮** w rozmowie ma dwie pozycje:

- **Udostępnij historię**, na urządzeniu, które ją ma: całość albo od daty,
  z plikami albo bez, z liczbami, zanim cokolwiek pójdzie;
- **Poproś o historię**, na urządzeniu, które ją straciło: karta na drugim
  urządzeniu pyta, czy oddać, z plikami, bez nich, czy wcale.

Strona przyjmująca zawsze dostaje najpierw kartę: kto wysyła, ile wiadomości
i plików, z jakiego okresu, ostrzeżenie, gdy tożsamość tamtego urządzenia nie
jest potwierdzona, i uwaga, gdy samoczynne kasowanie pominie starsze
wiadomości. Wracają także wiadomości usunięte tu celowo i karta mówi o tym
wprost. Odpowiedź na Twoje własne **Poproś o historię** wchodzi bez drugiej
karty.

Przywrócone wiadomości mają oryginalne godziny i kierunki, wchodzą jako
przeczytane i nie wywołują powiadomień. Każda ma przy godzinie małą ikonę
historii, a w podpowiedzi datę przywrócenia: kopia rozmówcy to jego słowo,
a wiadomości nic nie podpisuje.

Pliki jadą po wiadomościach. Obie strony widzą pasek postępu nad polem
pisania, każda z **Przerwij**. Plik, którego bajtów druga strona
już nie ma, przychodzi jako „Plik niedostępny"; odebrany plik, który wciąż
leży u Ciebie na dysku, podpina się bez ponownego przesyłania. Drugie
udostępnienie wznawia: nic się nie dubluje, a brakujące pliki dojeżdżają.

**Po reinstalacji albo na nowym telefonie** tożsamość bierze się z nowego
klucza, więc druga strona widzi nowe urządzenie, a stara rozmowa zostaje pod
starym wpisem. Gdy to nowe urządzenie ma zieloną tarczę, okno udostępniania
pokazuje **Skąd**: ta rozmowa albo starsza, z innym wpisem. Wybierz starszą
i, jeśli chcesz, **Połącz u mnie tamtą rozmowę z tą**: po udostępnieniu obie
staną się jedną po stronie udostępniającej, a stary wpis zostaje na liście
urządzeń. Bez tarczy pójść może tylko ta rozmowa, więc nikt, kto pożyczy imię
znajomego, nie dostanie jego rozmowy z Tobą.

Oba urządzenia potrzebują tej wersji; o starszym Chatcie aplikacja mówi
wprost.

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

W tym samym panelu siedzą rzeczy, które należą do rozmówcy:

- **Zmień nazwę.** Urządzenie rozgłasza własną nazwę, więc komputer trafia na
  listę jako coś w rodzaju `DESKTOP-8F2A1C`. Nadaj mu swoją i to ją zobaczysz
  wszędzie. Nazwa zostaje na tym urządzeniu, nigdzie nie jedzie, a rozgłaszana
  wyświetla się pod nią, żeby dało się zauważyć, że druga strona się
  przemianowała. Puste pole wraca do rozgłaszanej.
- **Przyjmuj pliki bez pytania.** Pliki od tego urządzenia trafiają wtedy prosto
  do rozmowy, bez karty z pytaniem. Przełącznik działa wyłącznie przy zielonej
  tarczy i gaśnie sam, gdy potwierdzenie zniknie: zgoda dotyczyła potwierdzonej
  tożsamości.
- **Pisanie bez pytania**, widoczne tylko przy włączonym dodatku Klawiatura
  z PC: to urządzenie zaczyna pisać tutaj bez karty, na tych samych zasadach
  (patrz [Dodatek „Klawiatura z PC”](#dodatek-klawiatura-z-pc)).

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
dołączyć do zgłoszenia. Gdy okno już działa, tę rolę pełni dziennik
aplikacji: patrz [Dane i diagnostyka](#dane-i-diagnostyka).

Instalator nie jest podpisany certyfikatem, więc SmartScreen pokaże
ostrzeżenie „Windows chronił Twój komputer". „Więcej informacji" → „Uruchom
mimo to". Certyfikat do podpisu kodu kosztuje kilkaset złotych rocznie i nie
zmieniłby nic w tym, co robi program.

## Wygląd i język

W Ustawieniach, w sekcji **Wygląd**, wybierasz **styl**, motyw (systemowy,
jasny, ciemny), **tło** i język (systemowy, polski, angielski). Wszystkie
wybory siedzą w bazie, więc przeżywają restart. Świeża instalacja startuje po
angielsku, polski jest o jedno dotknięcie dalej.

Style są trzy i różnią się wyłącznie wyglądem: te same ekrany, te same
informacje, te same przyciski.

- **Cisza** (domyślny): miękkie powierzchnie, okrągłe awatary, zaokrąglone
  dymki, font Figtree.
- **Precyzja**: gęsta lista w panelu z obrysem, kwadratowe awatary, ostrzejsze
  rogi, daty z linią przez całą szerokość, nagłówki sekcji wersalikami, font
  IBM Plex Sans.
- **Ciepło**: każda rozmowa na osobnej karcie z cieniem, duże zaokrąglenia,
  font Nunito.

Każdy styl ma wariant jasny i ciemny oraz własny font o stałej szerokości do
wartości technicznych: adresów, identyfikatora, odcisku klucza, kodu
parowania i rozmiarów plików. Ostrzeżenie o niepotwierdzonej tożsamości jest
czerwone w Ciszy i bursztynowe w Precyzji i Cieple; brak szyfrowania jest
czerwony w każdym stylu.

Krótkie komunikaty („Skopiowano", „Usunięto rozmowę") pokazują się w prawym
górnym rogu, z paskiem odliczającym czas do zniknięcia. Kliknięcie zamyka je od
razu. Na górze nie zasłaniają przycisku ani pola tekstowego, którego przed
chwilą użyłeś.

Tła to gotowe zestawy: „Bez tła" (zwykły kolor motywu), Zmierzch, Ocean,
Las i Piasek. Każde ma kolory dobrane do stylu i do motywu jasnego
i ciemnego, a wszystkie są celowo przygaszone: na tle leżą dymki i karty,
które muszą zostać czytelne.
Powiadomienia usługi w tle też idą za językiem aplikacji.

<img src="screenshots/produkt/android_lista_rozmow_ciemny.png" alt="Tryb ciemny" width="260">

## Prywatność: co leży na dysku

Historia rozmów leży na dysku **zaszyfrowana**, a klucz do niej trzyma schowek
systemowy (Keystore na Androidzie, DPAPI na Windowsie). W tej samej bazie leżą
historia pisania i dziennik aplikacji. Skopiowanie samego pliku bazy nic nie
daje. Ustawienia mówią o tym wprost, razem z ostrzeżeniem, gdyby na danym
urządzeniu schowek nie zadziałał.

<img src="screenshots/android/and20_prywatnosc.png" alt="Prywatność" width="260">

Tam samym są dwie rzeczy do zrobienia ręcznie:

- **Kasuj wiadomości starsze niż**: do wyboru 7, 30, 90 albo 365 dni.
  Domyślnie wyłączone. Aplikacja sprząta przy starcie, po zmianie ustawienia
  i co sześć godzin. Razem z wiadomościami znika historia pisania w tym samym
  wieku.
- **Wyczyść historię**: kasuje wszystkie wiadomości i rozmowy od razu, a z nimi
  historię pisania. Po tej stronie nieodwracalne, więc pyta o potwierdzenie.
  Urządzenia razem z potwierdzoną tożsamością zostają, więc nie trzeba się
  parować od nowa. Druga strona ma swoją kopię i może ją oddać
  ([Odzyskiwanie historii rozmowy](#odzyskiwanie-historii-rozmowy)).

<img src="screenshots/android/and21_wyczysc_historie.png" alt="Wyczyść historię" width="260">

W obu przypadkach **odebrane pliki zostają na dysku**. Aplikacja kasuje własne
wpisy; pliki, które otwierasz innymi programami, zostają. Dziennik aplikacji
też zostaje: nie ma w nim treści, wpisy starsze niż 30 dni kasuje sam,
a **Wyczyść dziennik** na jego ekranie kasuje go od razu.

## Dane i diagnostyka

W Ustawieniach, między sekcjami Prywatność i Dodatki, stoi sekcja **Dane
i diagnostyka** z **Dziennikiem aplikacji** i **Eksportem danych**.
**Historia pisania** pojawia się nad nimi, gdy zapisze się choć jedna sesja
pisania. Przy włączonym dodatku klawiatury ten sam ekran otwiera przycisk
**Historia pisania** na jego karcie.

**Historia pisania** wymienia sesje Klawiatury z PC na tym urządzeniu: które
urządzenie pisało na którym, kiedy, jak sesja się skończyła i co wpisano,
kawałek po kawałku, z aplikacją, do której trafiło, i z tym, czy dotarło.
Tekst do pola hasła albo do pola, którego rodzaju Chatt nie rozpozna,
pokazuje się jako kropki z liczbą znaków. **Wyczyść historię pisania** kasuje
całość. Zapis działa, gdy włączone są i dodatek klawiatury, i jego
przełącznik **Zapisuj historię pisania**, a każde urządzenie prowadzi własną
historię według swojego przełącznika; szczegóły są na stronie
[Klawiatura z PC](keyboard.pl.md#historia-pisania).

**Dziennik aplikacji** pokazuje, co aplikacja robiła i co się nie udało:
połączenia i drogę, którą poszły, parowanie, przesyłanie plików, Bluetooth,
sesje pisania i błędy, każdy wpis z godziną i wagą (informacja, ostrzeżenie,
błąd). Nigdy nie ma w nim treści wiadomości, wpisywanego tekstu, kodów
parowania ani kluczy. Trzyma 30 dni i najwyżej 20 000 wpisów, a starsze
kasuje sam. **Wyczyść dziennik** kasuje całość.

**Eksportuj dane** zapisuje to, co Chatt przechowuje, w jednym pliku ZIP,
jako kopię do przeczytania albo do analizy w innych narzędziach. Okno pyta,
które części zabrać:

- rozmowy razem z urządzeniami i ustawieniami;
- historię pisania;
- dziennik aplikacji;
- odebrane pliki, z podanym łącznym rozmiarem, bo bywają duże.

Plik nazywa się na przykład `chatt-export-2026-10-18-1530.zip`. Na
Androidzie 10 i nowszym trafia do Pobranych; na starszym Androidzie, albo gdy
zapis do Pobranych się nie uda, otwiera się okno udostępniania i to w nim
wybierasz, dokąd pójdzie. Na komputerze systemowe okno zapisu pyta, gdzie go
położyć, a gdy plik o tej nazwie już tam leży i okno o niego nie zapytało,
Chatt pyta przed jego zastąpieniem. Nieudany eksport nie zostawia
niedokończonego pliku, a starszy plik o tej samej nazwie zostaje. W środku są
pliki JSON dla programów, pliki tekstowe do czytania i `README.txt`, który je
opisuje.

**Eksport nie jest zaszyfrowany.** Każdy, kto dostanie plik, przeczyta to, co
do niego trafiło, razem z historią pisania. Nigdy nie ma w nim klucza
prywatnego, klucza sesji ani klucza bazy, więc nie da się nim podszyć pod to
urządzenie ani otworzyć jego bazy. Usuń go, gdy przestanie być potrzebny. Po
udostępnieniu Chatt trzyma własną kopię w pamięci podręcznej aplikacji: kasuje
ją następny eksport, **Wyczyść historię**, **Wyczyść historię pisania** albo
następny start, gdy kopia ma ponad godzinę.

**Do zgłoszenia błędu** wyeksportuj dane z zaznaczonym tylko polem **Dziennik
aplikacji** i dołącz plik. Ostrzeżenie w oknie nie wspomina wtedy o treści
wiadomości ani o wpisywanym tekście. Oprócz dziennika są w pliku nazwa
i identyfikator tego urządzenia. Dziennik zawiera nazwy urządzeń, adresy
i rozmiary plików, bez treści wiadomości, wpisywanego tekstu i kluczy.

## Dwie instancje na jednym komputerze

Do testów bez drugiego urządzenia: druga instancja musi dostać własny katalog
danych, port dobierze sobie sama.

```powershell
$env:CHATT_DATA_DIR = "$env:TEMP\chatt-b"
$env:CHATT_INSTANCE_NAME = "Instancja B"
.\build\windows\x64\runner\Release\chatt.exe
```
