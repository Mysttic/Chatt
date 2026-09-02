# Budowanie i wydawanie wersji

Cały kod aplikacji leży w [`app/`](../app/). Poza nim w repozytorium są już
tylko dokumentacja i zrzuty.

## Środowisko

| Element | Wersja / miejsce |
|---|---|
| Flutter | 3.47.2 stable (Dart 3.13.2) |
| SDK na maszynie właściciela | `C:\Users\mystt\dev\flutter` — **poza PATH-em** |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk` |
| Windows | Visual Studio z workloadem „Desktop development with C++" + tryb dewelopera |

Flutter celowo nie jest w PATH, więc w poleceniach niżej pojawia się pełna
ścieżka. Jeśli dodasz go do PATH, wystarczy `flutter`.

Tryb dewelopera na Windows (`start ms-settings:developers`) jest potrzebny,
bo build desktopowy tworzy dowiązania symboliczne do wtyczek.

## Codzienna praca

```
cd app
C:\Users\mystt\dev\flutter\bin\flutter.bat pub get
C:\Users\mystt\dev\flutter\bin\flutter.bat run -d windows
```

Po zmianie schematu bazy (`lib/data/db.dart`) trzeba przegenerować kod drifta:

```
C:\Users\mystt\dev\flutter\bin\flutter.bat pub run build_runner build --delete-conflicting-outputs
```

Po zmianie tekstów w `lib/l10n/*.arb`:

```
C:\Users\mystt\dev\flutter\bin\flutter.bat gen-l10n
```

Ikony (launcher Androida, ikona adaptacyjna, ikona powiadomień, `.ico` dla
Windows) generuje jeden skrypt w Pythonie — wymaga biblioteki Pillow:

```
cd app
python tool/make_icons.py
```

## Build: Windows

```
cd app
C:\Users\mystt\dev\flutter\bin\flutter.bat build windows --release
```

Wynik: `app\build\windows\x64\runner\Release\`. Do przeniesienia na inny
komputer potrzebny jest **cały ten katalog** (exe plus biblioteki DLL i katalog
`data`), a na docelowej maszynie „Microsoft Visual C++ Redistributable".

Częsty błąd przy przebudowie: `LNK1168: cannot open chatt.exe` — to znaczy, że
poprzednia instancja aplikacji jeszcze działa. Zamknij ją i powtórz build.

Przy pierwszym uruchomieniu zapora Windows pyta o zgodę na ruch przychodzący.
Reguły powstają osobno dla TCP i UDP i osobno dla ścieżki debug i release, więc
po przejściu na build release zapora zapyta jeszcze raz. Sprawdzenie, co jest
przepuszczone:

```
netsh advfirewall firewall show rule name=chatt verbose
```

## Build: Android

```
cd app
C:\Users\mystt\dev\flutter\bin\flutter.bat build apk --release
```

Wynik: `app\build\app\outputs\flutter-apk\app-release.apk`.

Instalacja na podłączonym urządzeniu:

```
adb install -r app\build\app\outputs\flutter-apk\app-release.apk
```

### Podpisywanie

Build release jest podpisywany własnym kluczem. Dwa pliki, oba **poza gitem**:

| Plik | Gdzie | Co w środku |
|---|---|---|
| `chatt-release.jks` | `C:\Users\mystt\keys\` | klucz (RSA 4096, alias `chatt`, ważny do 2053) |
| `key.properties` | `app/android/` | ścieżka do keystore, alias i hasła |

`app/android/.gitignore` wyrzuca `key.properties`, `*.jks` i `*.keystore`, a sam
keystore leży poza katalogiem projektu — tak radzi dokumentacja Fluttera, żeby
nie dało się go przypadkiem dodać do repozytorium.

**Kopia zapasowa obu plików jest obowiązkowa.** Android wiąże aktualizacje
z podpisem: po zgubieniu klucza nie da się wydać nowej wersji dla nikogo, kto
ma już zainstalowaną starą — zostaje odinstalowanie i instalacja od zera,
z utratą rozmów i parowań.

Sprawdzenie, czym naprawdę podpisany jest zbudowany APK:

```
set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr
%LOCALAPPDATA%\Android\Sdk\build-tools\37.0.0\apksigner.bat verify --print-certs app\build\app\outputs\flutter-apk\app-release.apk
```

Powinno wypisać `CN=Chatt, O=Mysttic, C=PL` i „Verifies". Podpis jest
w schemacie v2; v1 (JAR signing) jest wyłączony, bo `minSdk` wynosi 24, a v1
dotyczy starszych systemów.

Gdy `key.properties` albo keystore'a nie ma (świeży klon, sesja chmurowa),
build release **nadal przechodzi**, tylko podpisany kluczem debug — Gradle
wypisuje wtedy ostrzeżenie. Taki APK nadaje się do testów, ale nie do
rozdawania.

**Zmiana klucza w już zainstalowanej aplikacji**: pierwsza instalacja APK
podpisanego nowym kluczem na urządzeniu, gdzie stoi wersja debugowa, kończy
się błędem `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Trzeba raz odinstalować starą
wersję (`adb uninstall com.mysttic.chatt`), co kasuje jej dane.

Uprawnienia w manifeście i po co są:

| Uprawnienie | Do czego |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | serwer i klient HTTP w sieci lokalnej |
| `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE` | MulticastLock — bez niego układ Wi‑Fi odsiewa rozgłoszenia i ginie discovery |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE` | nasłuch przy zamkniętym oknie |
| `POST_NOTIFICATIONS` | powiadomienia o wiadomościach |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | prośba o wyjątek, wołana tylko z ustawień |

## Numer wersji

Jedno miejsce: `app/pubspec.yaml`, linia `version: 0.1.0+1`. Część przed `+`
to wersja widoczna dla użytkownika (Android `versionName`), część po `+` to
numer builda (`versionCode`), który przy każdym wydaniu na Androida musi
rosnąć. Flutter przepisuje obie wartości do projektów natywnych, więc nie
trzeba nic zmieniać w Gradle ani w plikach Windows.

## Gałęzie i automatyzacja na GitHubie

Repozytorium: [github.com/Mysttic/Chatt](https://github.com/Mysttic/Chatt).

```
feature/coś ──┐
              ├─→ develop ──(pull request)──→ master ──→ wydanie
claude/coś ───┘        ▲                          │
                       └── testy przy każdym      └── build Windows + APK,
                           pchnięciu i przy PR         tag i Release
```

- **`develop`** — tu trafia bieżąca praca. Każde pchnięcie uruchamia
  [`.github/workflows/testy.yml`](../.github/workflows/testy.yml): `flutter
  analyze` i cały zestaw testów. Wynik jest więc znany, zanim otworzysz PR.
- **Pull request `develop` → `master`** — te same testy odpalają się jeszcze
  raz na scalonym wyniku.
- **Scalenie do `master`** uruchamia
  [`.github/workflows/wydanie.yml`](../.github/workflows/wydanie.yml): build
  Windows i podpisanego APK, tag i Release na GitHubie.

### Skąd bierze się numer wydania

Z `app/pubspec.yaml`. Workflow czyta linię `version:`, obcina część po `+`
i szuka taga `v<wersja>`:

- **taga nie ma** → buduje, tworzy tag i Release z dwoma plikami:
  `chatt-<wersja>-android.apk` i `chatt-<wersja>-windows.zip`;
- **tag już jest** → kończy bieg bez robienia niczego.

W praktyce: żeby wydać wersję, podbijasz `version:` w `pubspec.yaml` na
`develop` i scalasz PR do `master`. Scalenie bez podbicia wersji niczego nie
wyda i nie jest błędem — tak wygląda zwykła poprawka do dokumentacji.

### Sekrety do podpisania APK

Workflow wydania **przerywa się z błędem**, jeśli ich nie ma — inaczej
wypuściłby APK podpisany kluczem debug, bo taka jest awaryjna ścieżka
w `build.gradle.kts`. Cztery sekrety w *Settings → Secrets and variables →
Actions*:

| Sekret | Wartość |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | keystore zakodowany base64 (polecenie niżej) |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` z `app/android/key.properties` |
| `ANDROID_KEY_ALIAS` | `chatt` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` z `key.properties` (u nas to samo hasło) |

Keystore do base64 (PowerShell, wynik ląduje w schowku):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\keys\chatt-release.jks")) | Set-Clipboard
```

Hasła są w `app/android/key.properties` — plik jest w `.gitignore`, więc nie
ma go w repozytorium ani w historii.

Po każdym buildzie workflow sprawdza `apksigner verify --print-certs`
i kasuje klucz z maszyny, także gdy build się wywrócił.

### Wymuszenie testów przed scaleniem

Same workflow nie blokują scalenia — trzeba to włączyć w ustawieniach
repozytorium: *Settings → Branches → Add branch ruleset* dla `master`,
z **Require status checks to pass** i checkiem `analyze i flutter test`.
Warto dołożyć to samo dla `develop`.

### Pierwsze uruchomienie

Gałęzi `develop` jeszcze nie ma. Z gałęzi, na której są zmiany:

```
git checkout -b develop
git push -u origin develop
```

Potem PR `develop` → `master` przez GitHuba. Pierwsze scalenie wyda `v0.1.0`,
bo taki numer stoi w `pubspec.yaml` i nie ma jeszcze takiego taga.

### Wersja Fluttera w CI

Oba workflow mają przypiętą wersję `3.47.2` — tę samą, na której stoi projekt
lokalnie. Przypadkowa aktualizacja Fluttera nie ma prawa wywrócić buildu.
Przy podbiciu SDK trzeba zmienić ją w obu plikach w `.github/workflows/`.

## Wydanie wersji: lista kroków

Buildem i tagiem zajmuje się CI, po twojej stronie zostaje reszta:

1. Podbij `version:` w `app/pubspec.yaml` na gałęzi `develop`.
2. Odśwież zrzuty do dokumentacji, jeśli zmienił się UI:
   `flutter test tool/product_shots.dart` (wymaga uruchomionego emulatora).
3. Otwórz PR `develop` → `master` i poczekaj, aż testy zaświecą się na zielono.
4. Scal PR. Workflow wydania zbuduje Windows i podpisany APK, założy tag
   `v<wersja>` i wystawi Release z oboma plikami.
5. Pobierz APK z Release, zainstaluj na telefonie i przejdź
   [krótką listę kontrolną](#lista-kontrolna-po-wydaniu).

Polecenia buildu wyżej zostają do pracy lokalnej i do sprawdzenia czegoś przed
wysłaniem na GitHuba.

### Lista kontrolna po wydaniu

Rzeczy, których nie sprawdzi żaden test automatyczny, bo wymagają dwóch
prawdziwych urządzeń w jednej sieci:

- [ ] skan znajduje drugie urządzenie w obie strony;
- [ ] wiadomość dochodzi w obie strony i dostaje podwójny check;
- [ ] plik kilku megabajtów dochodzi po akceptacji, suma się zgadza;
- [ ] parowanie: kody na obu ekranach są takie same, po zgodzie tarcza zielona;
- [ ] telefon z zamkniętą aplikacją i zgaszonym ekranem nadal odbiera;
- [ ] po restarcie aplikacji rozmowy i ustawienia są na miejscu.

## Sesje chmurowe

Kontener sesji ma Fluttera i buduje Linuksa oraz web, ale **nie zbuduje APK**:
polityka sieci blokuje `dl.google.com` i `maven.google.com`, gdzie mieszkają
Android SDK i artefakty Gradle. Żeby to odblokować: claude.ai → Environments →
dopuść oba adresy.
