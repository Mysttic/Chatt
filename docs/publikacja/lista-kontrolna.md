# Lista kontrolna publikacji

Kolejność ma znaczenie: sklepy potrzebują adresu polityki prywatności, a ten
istnieje dopiero po upublicznieniu repozytorium.

## Przed upublicznieniem

- [ ] Kontakt w [polityce prywatności](polityka-prywatnosci.md)
      i [privacy-policy.md](privacy-policy.md) — dziś placeholder.
- [ ] Sprawdzenie nazwy „Chatt" w Play Console i Partner Center (rezerwacja
      nazwy nie wymaga publikacji).
- [ ] Ostatni przegląd README po angielsku: czy pierwsze zdanie mówi, dla
      kogo to jest.
- [ ] Odświeżone zrzuty w obu językach:
      `flutter test tool/product_shots.dart` (Android, PL),
      `set CHATT_SHOTS_LANG=en` i jeszcze raz (Android, EN),
      `flutter test tool/windows_shots.dart` w obu językach (Windows),
      potem `python tool/store_assets.py`.
      Zrzuty źródłowe siedzą w gicie, a `docs/publikacja/materialy/` **nie** —
      to wynik skryptu i powstaje na żądanie.
- [ ] Historia gita nie zawiera niczego, czego nie chcesz pokazać
      (`git log --all --oneline | head`, szukanie po hasłach: `git log -p -S`).
- [ ] `key.properties`, keystore i `chatt.key` **nie są** w repozytorium
      (`git ls-files | grep -iE "jks|keystore|key.properties"` ma nic nie zwrócić).

## Upublicznienie

- [ ] Settings → General → Danger Zone → Change visibility → Public.
- [ ] GitHub Pages z katalogu `docs/` (Settings → Pages), żeby polityka
      prywatności dostała stały adres. Alternatywa: link do pliku w `master`.
- [ ] Wpisanie adresu polityki w obu wpisach sklepowych.

## Google Play

Szczegóły w [google-play.md](google-play.md).

- [ ] Utworzenie aplikacji, wpis w dwóch językach (PL domyślny, EN).
- [ ] Ikona 512, grafika promocyjna, po 2 do 8 zrzutów na język
      (`docs/publikacja/materialy/google-play/`).
- [ ] Ankiety: polityka, dostęp, reklamy, klasyfikacja, grupa docelowa,
      bezpieczeństwo danych.
- [ ] Pierwsze wgranie AAB ręcznie (z wydania na GitHubie), na ścieżkę
      **internal testing**.
- [ ] Jeśli konto tego wymaga: test zamknięty z 20 testerami przez 14 dni.
- [ ] Konto serwisowe i sekret `PLAY_SERVICE_ACCOUNT_JSON`, krok wgrywania
      w workflow.

## Microsoft Store

Szczegóły w [microsoft-store.md](microsoft-store.md).

- [ ] Rezerwacja nazwy, przepisanie tożsamości paczki do zmiennych
      repozytorium `MSIX_IDENTITY_NAME`, `MSIX_PUBLISHER`,
      `MSIX_PUBLISHER_DISPLAY_NAME`.
- [ ] Wydanie z workflow zbuduje `chatt-<wersja>-store.msix`; pierwsze
      zgłoszenie ręcznie w Partner Center.
- [ ] Sprawdzenie paczki na czystym koncie Windows przed wysłaniem do
      certyfikacji: start, zapora, odbiór wiadomości, zasobnik.
- [ ] Autostart w wersji ze Store: albo `StartupTask` w manifeście, albo
      ukryty przełącznik (patrz uwagi w microsoft-store.md).
- [ ] Aplikacja Azure AD i sekrety `MSSTORE_*`, krok `msstore publish`
      w workflow.

## Po publikacji

- [ ] Show HN, r/selfhosted, r/privacy, Wykop — każdy post z innym pierwszym
      zdaniem ([pozycjonowanie.md](pozycjonowanie.md)).
- [ ] Zgłoszenie na AlternativeTo jako alternatywa dla LocalSend.
- [ ] winget (`wingetcreate` w workflow) i IzzyOnDroid — obie drogi darmowe,
      obie wymagają tylko publicznych wydań.
