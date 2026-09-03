# Publikacja w sklepach — odłożona

**Decyzja (3 września 2026): zostajemy przy wydaniach na GitHubie.**

Google Play i Microsoft Store wymagają utrzymywania konta, a nie tylko
jednorazowego wgrania: ankiety do przeklikania przy zmianach polityk, wymóg
aktualizacji pod nowe API, a przy nowych kontach Play dodatkowo test zamknięty
z 20 testerami przez 14 dni. Dla aplikacji pokazowej to koszt bez zwrotu.

Chatt wydaje się więc przez [GitHub Releases](../../../../releases): APK,
instalator Windows i wersja przenośna. Workflow wydania nie buduje ani AAB,
ani paczki MSIX.

## Co tu zostaje i po co

| Plik | Status |
|---|---|
| [pozycjonowanie.md](pozycjonowanie.md) | **żywe** — dla kogo to jest i czym różni się od LocalSend czy KDE Connect; z tego wychodzi treść README |
| [polityka-prywatnosci.md](polityka-prywatnosci.md), [privacy-policy.md](privacy-policy.md) | **żywe** — uczciwy opis tego, co aplikacja robi z danymi; przydaje się każdemu, kto ją uruchomi, niezależnie od sklepów |
| [google-play.md](google-play.md) | odłożone — gotowe treści, wymiary grafik i odpowiedzi do ankiet |
| [microsoft-store.md](microsoft-store.md) | odłożone — j.w., plus uwagi o MSIX |
| [lista-kontrolna.md](lista-kontrolna.md) | odłożone — kolejność kroków przy publikacji |

Materiały graficzne generuje `app/tool/store_assets.py`; ich wynik jest poza
repozytorium (`docs/publikacja/materialy/` w `.gitignore`). Nagłówek do README
(`docs/promo.png`) powstaje tym samym skryptem i **jest** w repozytorium.

## Gdyby decyzja się zmieniła

Trzy rzeczy do zrobienia, zanim cokolwiek pójdzie do sklepu:

1. Repozytorium musi być publiczne — polityka prywatności potrzebuje stałego
   adresu, a bez tego nie da się wypełnić żadnej z ankiet.
2. Wrócić do workflow wydania build AAB (Play nie przyjmuje APK) i krok MSIX.
   Oba były zrobione i sprawdzone; siedzą w historii gita przy fazie 13.
3. **Autostart pod MSIX nie zadziała**: paczka wirtualizuje rejestr HKCU, więc
   wpis w `Run` nie dojdzie do systemu. Trzeba go przełożyć na `StartupTask`
   w manifeście albo ukryć przełącznik w wersji ze Store.
