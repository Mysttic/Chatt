<p align="center">
  <img src="docs/promo.png" alt="Chatt" width="640">
</p>

<p align="center">
  Komputer i telefon w jednej rozmowie. Wiadomości i pliki idą prosto
  z jednego urządzenia na drugie po sieci lokalnej.
  <br>
  <b>Bez serwera, bez konta, bez chmury, zawsze zaszyfrowane.</b>
</p>

<p align="center">
  <a href="LICENSE"><img alt="Licencja: Apache-2.0" src="https://img.shields.io/badge/license-Apache--2.0-blue.svg"></a>
  <a href="https://github.com/Mysttic/Chatt/releases"><img alt="Najnowsze wydanie" src="https://img.shields.io/github/v/release/Mysttic/Chatt"></a>
  <a href="https://github.com/Mysttic/Chatt/actions/workflows/testy.yml"><img alt="Testy" src="https://github.com/Mysttic/Chatt/actions/workflows/testy.yml/badge.svg"></a>
</p>

<p align="center">
  <i>English version: <a href="README.md">README.md</a></i>
</p>

---

| Rozmowa | Prośba o plik | Urządzenia w pobliżu |
|---|---|---|
| <img src="docs/screenshots/produkt/android_rozmowa_z_plikiem.png" alt="Rozmowa" width="230"> | <img src="docs/screenshots/produkt/android_prosba_o_plik.png" alt="Prośba o plik" width="230"> | <img src="docs/screenshots/produkt/android_urzadzenia_w_poblizu.png" alt="Urządzenia w pobliżu" width="230"> |

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

Platformy: **Windows** i **Android**. Oba urządzenia muszą być w tej samej
sieci. Trybu przez internet nie ma i nie będzie: cały sens polega na tym, że
nic nie wychodzi poza Twoją sieć.

## Szybki start

```
cd app
flutter run -d windows
```

Na telefonie: `flutter build apk --release` i zainstaluj APK. Oba urządzenia
muszą być w tej samej sieci, a na Windows trzeba przepuścić ruch przychodzący,
gdy zapyta o to zapora.

Szczegóły: [instrukcja obsługi](docs/guide.pl.md) ·
[budowanie i wydawanie wersji](docs/building.md)

## Dokumentacja

Po polsku są dwa pliki: ten i instrukcja obsługi. Reszta jest po angielsku,
żeby istniała w jednej wersji i nie rozjeżdżała się przy każdej zmianie
w kodzie. Sama aplikacja mówi po polsku i po angielsku.

Spis całej dokumentacji jest w [docs/](docs/README.md). Dla użytkownika:
[instrukcja obsługi](docs/guide.pl.md). Dla pracujących nad kodem:
[budowanie i wydawanie](docs/building.md), [architektura](docs/architecture.md),
[testy](docs/testing.md) i [jak wysłać zmianę](docs/CONTRIBUTING.md).

Historia wydań jest w [CHANGELOG.md](CHANGELOG.md).

## Development

```
cd app
flutter test        # 94 testy: baza, discovery, wiadomości, pliki, tożsamość, szyfrowanie
flutter analyze
```

Struktura `app/lib/`:

- `core/`: tożsamość urządzenia, kryptografia, kanały platformowe
- `data/db.dart`: schemat SQLite (drift) i zapytania
- `network/`: protokół, discovery UDP, serwer HTTP, klient
- `services/`: `AppServices` (korzeń łączący wszystko) i providery Riverpod
- `ui/screens/`: rozmowy, czat, urządzenia w pobliżu, ustawienia

Scenariusze na żywym sprzęcie (`app/tool/`) opisuje
[docs/testing.md](docs/testing.md).

## Licencja

Apache License 2.0, patrz [LICENSE](LICENSE) i [NOTICE](NOTICE). Komponenty,
które jadą razem z aplikacją, wymienia [lista licencji](docs/THIRD-PARTY-NOTICES.md).

Znalazłeś błąd bezpieczeństwa? Najpierw przeczytaj [SECURITY.md](docs/SECURITY.md);
prosi o zgłoszenie prywatne, nie przez publiczne issue.
