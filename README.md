# Chatt

Komunikator P2P dla urządzeń w jednej sieci Wi‑Fi (PC ⇄ telefon z Androidem):
wiadomości i pliki przesyłane **bezpośrednio między urządzeniami**, bez
żadnego serwera pośredniczącego, konta i logowania.

| Rozmowa | Prośba o plik | Urządzenia w pobliżu |
|---|---|---|
| ![Rozmowa](docs/screenshots/produkt/android_rozmowa_z_plikiem.png) | ![Plik](docs/screenshots/produkt/android_prosba_o_plik.png) | ![Skan](docs/screenshots/produkt/android_urzadzenia_w_poblizu.png) |

## Co to potrafi

- **Znajduje samo**: jedno rozgłoszenie UDP w sieci i urządzenia widzą się
  nawzajem. Gdy router izoluje klientów, zostaje ręczne dodanie po adresie IP.
- **Wiadomości z potwierdzeniem**: zapis lokalny → dostarczenie → potwierdzenie.
  Nieudane można ponowić jednym dotknięciem, a gdy rozmówcy zmieni się IP,
  aplikacja sama go odnajdzie po identyfikatorze.
- **Pliki z pytaniem o zgodę**: odbiorca najpierw widzi nazwę, rozmiar i sumę
  kontrolną, dopiero potem lecą bajty. Przerwany transfer wznawia się od
  miejsca przerwania, a całość jest weryfikowana sumą sha256.
- **Szyfrowane zawsze**: klucz sesji uzgadniany na każde połączenie, jawnego
  tekstu w protokole nie ma. Nagrany dziś ruch nie odszyfruje się po
  późniejszej kradzieży urządzenia.
- **Potwierdzanie tożsamości**: kodem QR albo porównaniem sześciu cyfr.
  Szyfrowanie działa i bez tego; potwierdzenie odpowiada na pytanie „czy po
  drugiej stronie jest ta osoba, o której myślę".
- **Historia zaszyfrowana na dysku**, klucz w schowku systemowym (Android
  Keystore, Windows DPAPI). Do tego „wyczyść historię" i kasowanie wiadomości
  starszych niż wybrana liczba dni.
- **Nasłuch w tle na Androidzie**: wiadomości dochodzą przy zamkniętym oknie
  i zgaszonym ekranie, z powiadomieniem.
- **Na Windowsie ikona w zasobniku**: krzyżyk chowa okno zamiast kończyć
  nasłuch, a aplikacja może wstawać razem z systemem.
- **Wygoda**: wiele plików naraz (także przeciągniętych na okno), miniatury
  obrazków, zapisanie odebranego pliku do Zdjęć/Pobranych jednym dotknięciem,
  szukanie w rozmowach, kasowanie pojedynczych wiadomości.
- **Dwa panele na szerokim oknie** (lista obok rozmowy) i tła do wyboru.
- **Polski i angielski**, motyw jasny/ciemny/systemowy, jedno i drugie zapisane
  w bazie.

Platformy: **Windows** i **Android** produkcyjnie, Linux desktop i web do
rozwoju i testów.

## Szybki start

```
cd app
flutter run -d windows
```

Na telefonie: `flutter build apk --release` i zainstaluj APK. Oba urządzenia
muszą być w tej samej sieci, a na Windows trzeba przepuścić ruch przychodzący,
gdy zapyta o to zapora.

Szczegóły: [instrukcja obsługi](docs/instrukcja.md) ·
[budowanie i wydawanie wersji](docs/budowanie.md)

## Dokumentacja

| Dokument | Dla kogo |
|---|---|
| [docs/instrukcja.md](docs/instrukcja.md) | użytkownik: parowanie, pliki, nasłuch w tle, rozwiązywanie problemów |
| [docs/budowanie.md](docs/budowanie.md) | build Windows i Androida, podpisywanie, gałęzie i wydania na GitHubie |
| [docs/testy.md](docs/testy.md) | co jest testowane, jak to uruchomić, czego testy nie łapią |
| [docs/architektura.md](docs/architektura.md) | protokół, baza, model zagrożeń, nasłuch w tle na Androidzie |
| [ROADMAP.md](ROADMAP.md) | plan prac i stan projektu |

Wcześniejsze podejście w .NET MAUI zostało usunięte po osiągnięciu parytetu
funkcji; jest w historii gita, a makiety i diagramy z tamtego etapu leżą
w [`docs/makiety/`](docs/makiety/).

## Development

```
cd app
flutter test        # 71 testów: baza, discovery, wiadomości, pliki, tożsamość, szyfrowanie
flutter analyze
```

Struktura `app/lib/`:

- `core/` — tożsamość urządzenia, kryptografia, kanały platformowe
- `data/db.dart` — schemat SQLite (drift) i zapytania
- `network/` — protokół, discovery UDP, serwer HTTP, klient
- `services/` — `AppServices` (korzeń łączący wszystko) i providery Riverpod
- `ui/screens/` — rozmowy, czat, urządzenia w pobliżu, ustawienia

Scenariusze na żywym sprzęcie (`app/tool/`) opisuje [docs/testy.md](docs/testy.md).
