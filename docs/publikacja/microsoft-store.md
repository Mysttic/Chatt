# Microsoft Store

Wszystko, co trzeba mieć pod ręką w Partner Center. Materiały graficzne
generuje `app/tool/store_assets.py` do `docs/publikacja/materialy/microsoft-store/`.

## Dlaczego Store, skoro jest instalator

Store **sam podpisuje paczkę**. To załatwia ostrzeżenie SmartScreen, które
dziś dostaje każdy, kto pobierze instalator z GitHuba — bez kupowania
certyfikatu do podpisu kodu. Do tego aktualizacje idą same, a odinstalowanie
jest czyste.

## Zanim zaczniesz: konto i tożsamość paczki

1. W Partner Center: **Apps and games → New product → MSIX or PWA app**,
   zarezerwuj nazwę „Chatt" (sprawdź, czy wolna).
2. Z zakładki **Product identity** przepisz trzy wartości:
   - `Package/Identity/Name` (np. `12345Mysttic.Chatt`),
   - `Package/Identity/Publisher` (postać `CN=xxxxxxxx-xxxx-...`),
   - `Package/Properties/PublisherDisplayName`.
3. Wpisz je jako **zmienne repozytorium** na GitHubie (Settings → Secrets and
   variables → Actions → Variables): `MSIX_IDENTITY_NAME`, `MSIX_PUBLISHER`,
   `MSIX_PUBLISHER_DISPLAY_NAME`. Krok „MSIX" w workflow wydania buduje paczkę
   tylko wtedy, gdy są ustawione — bez nich wydanie przechodzi jak dotąd.

Paczka pod Store jest **niepodpisana** (`--store`); podpis dokłada Store.

## Co w MSIX działa inaczej niż w instalatorze

Do sprawdzenia na pierwszej paczce, zanim pójdzie do certyfikacji:

- **Autostart.** Aplikacja zakłada wpis w `HKCU\...\Run`, a MSIX
  wirtualizuje zapis do rejestru — wpis trafi do kontenera paczki i Windows go
  nie zobaczy. Paczka potrzebuje deklaracji `StartupTask` w manifeście
  (pakiet `msix` ma do tego opcję `startup_task`), a przełącznik w ustawieniach
  musi wtedy wołać API `StartupTask` zamiast rejestru. Do czasu zrobienia
  tego: przełącznik w wersji ze Store nie zadziała i trzeba go tam ukryć.
- **Sieć.** Manifest musi deklarować `internetClient`,
  `internetClientServer` i `privateNetworkClientServer` — bez ostatniego
  serwer nasłuchujący w sieci lokalnej nie przyjmie połączeń.
- **Zapora.** Paczka ze Store dostaje osobną regułę zapory; przy pierwszym
  starcie system zapyta jeszcze raz.
- **DPAPI, zasobnik, pliki w Dokumentach** — działają bez zmian (aplikacja
  jest „full trust").

## Wpis w sklepie

Store ma jedno pole opisu (do 10 000 znaków), bez osobnego krótkiego opisu.
Treść taka sama jak dla Google Play ([google-play.md](google-play.md),
sekcja „Pełny opis"), z jedną zmianą w ostatnim akapicie:

- PL: `Chatt potrzebuje drugiego urządzenia z Chattem w tej samej sieci Wi‑Fi: telefonu z Androidem albo innego komputera z Windows.`
- EN: `Chatt needs another device running Chatt on the same Wi‑Fi: an Android phone or another Windows PC.`

Pola:

| Pole | Wartość |
|---|---|
| Kategoria | Social |
| Podkategoria | brak |
| Funkcje produktu (do 20 punktów) | pierwsze siedem nagłówków z pełnego opisu, jako krótkie zdania |
| Słowa kluczowe (do 7) | patrz [pozycjonowanie.md](pozycjonowanie.md), po jednym zestawie na język |
| Polityka prywatności | adres URL do `privacy-policy.md` |
| Strona wsparcia | adres repozytorium (po upublicznieniu) |
| Klasyfikacja wiekowa | ankieta IARC, ta sama co w Play |

## Grafika

| Element | Wymiar | Skąd |
|---|---|---|
| Logo w sklepie (1:1) | 1080×1080, PNG | `materialy/microsoft-store/logo-1080.png` |
| Zrzuty pulpitu | co najmniej jeden, **min. 1366×768**, PNG | `materialy/microsoft-store/zrzuty/{pl,en}/` |
| Ikony w paczce (Square44, Square150, Wide310, StoreLogo…) | generuje pakiet `msix` z jednej ikony | automatycznie |

Zrzuty pulpitu robi `app/tool/windows_shots.dart`: podnosi osobną instancję
aplikacji z pustym profilem, dokłada do niej demonstracyjną rozmowę i zrzuca
samo okno w 1600×900. Dzięki temu na zrzutach nie ma cudzych rozmów.

## Certyfikacja: co Store sprawdza

- Aplikacja uruchamia się i działa bez internetu — tak.
- Nie wywraca się przy pierwszym starcie na czystym koncie — sprawdzić
  paczkę na czystym profilu użytkownika.
- Wszystkie funkcje z opisu są dostępne — nie obiecujemy nic ponad to, co jest.
- Polityka prywatności pod działającym adresem.
- Jeśli aplikacja nasłuchuje w sieci, opis ma o tym mówić — mówi.

## Automatyzacja

Microsoft Store Developer CLI (`msstore`) umie wgrać paczkę i utworzyć
zgłoszenie. Potrzebne:

1. W Azure AD aplikacja z dostępem do Partner Center (tenant id, client id,
   client secret) — instrukcja w Partner Center → Account settings → User
   management → Azure AD applications.
2. Sekrety repozytorium: `MSSTORE_TENANT_ID`, `MSSTORE_CLIENT_ID`,
   `MSSTORE_CLIENT_SECRET`, plus `MSSTORE_SELLER_ID`.
3. W workflow: `microsoft/setup-msstore-cli`, potem
   `msstore publish <ścieżka.msix> --appId <id ze Store>`.

Pierwsze zgłoszenie z wpisem, grafikami i ankietami robi się ręcznie
w Partner Center; automatyzacja podmienia paczkę w kolejnych.
