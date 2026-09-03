# Polityka prywatności Chatt

Ostatnia zmiana: 3 września 2026. Wersja angielska:
[privacy-policy.md](privacy-policy.md).

## W skrócie

Chatt nie zbiera żadnych danych. Nie ma serwera, konta, logowania, analityki
ani raportów o błędach. Wszystko, co wpiszesz albo wyślesz, idzie prosto
z jednego urządzenia na drugie w Twojej sieci lokalnej i zostaje na tych dwóch
urządzeniach.

## Jakie dane aplikacja przetwarza i gdzie

| Dane | Gdzie są | Kto je widzi |
|---|---|---|
| Wiadomości i pliki, które wysyłasz | na Twoim urządzeniu i na urządzeniu odbiorcy | tylko wy dwoje |
| Nazwa urządzenia i wiadomość powitalna | rozgłaszane w Twojej sieci lokalnej | każde urządzenie w tej samej sieci Wi‑Fi |
| Klucz tożsamości urządzenia (część publiczna) | rozgłaszany w sieci lokalnej | każde urządzenie w tej samej sieci |
| Klucz tożsamości (część prywatna), historia rozmów | na Twoim urządzeniu, w zaszyfrowanej bazie | tylko Ty |
| Adres IP w sieci lokalnej | widoczny dla urządzeń, z którymi rozmawiasz | urządzenia w tej samej sieci |

Nic z powyższego nie jest wysyłane do autora aplikacji ani do kogokolwiek poza
Twoją siecią lokalną.

## Szyfrowanie

- Ruch między urządzeniami jest szyfrowany zawsze, od pierwszej wiadomości,
  kluczem uzgadnianym osobno na każde połączenie (X25519, AES‑GCM,
  AES‑CTR dla plików).
- Historia rozmów leży na dysku w zaszyfrowanej bazie. Klucz do niej
  przechowuje system: Android Keystore na telefonie, DPAPI na Windows.
- Odebrane pliki są zapisywane bez dodatkowego szyfrowania w katalogu
  aplikacji, a na Twoje życzenie kopiowane do Zdjęć lub Pobranych.

## Uprawnienia

| Uprawnienie (Android) | Po co |
|---|---|
| Internet, stan sieci, stan Wi‑Fi, multicast | rozmowa i wykrywanie urządzeń w sieci lokalnej; aplikacja nie łączy się z internetem |
| Aparat | tylko do zeskanowania kodu QR z drugiego urządzenia, wyłącznie gdy o to poprosisz; obraz nie opuszcza urządzenia |
| Powiadomienia | informacja o nowej wiadomości i o działającym nasłuchu |
| Usługa pierwszoplanowa | odbieranie wiadomości przy zamkniętym oknie |
| Wyjątek od optymalizacji baterii | opcjonalny, żeby system nie odcinał sieci przy zgaszonym ekranie |

Na Windows aplikacja pyta zaporę systemową o zgodę na ruch przychodzący
w sieci prywatnej; poza tym nie wymaga uprawnień.

## Usługi zewnętrzne

Skanowanie kodu QR na Androidzie używa biblioteki Google ML Kit działającej
**na urządzeniu**; obraz z aparatu nie jest nigdzie wysyłany. Aplikacja nie
zawiera reklam, analityki, śledzenia ani zewnętrznych usług raportowania
błędów.

## Usuwanie danych

Wszystkie dane są na Twoim urządzeniu i Ty nimi dysponujesz:

- „Wyczyść historię" w ustawieniach kasuje wszystkie wiadomości,
- kasowanie wiadomości starszych niż wybrana liczba dni działa samo, gdy je
  włączysz,
- odinstalowanie aplikacji usuwa jej dane (na Windows baza w Dokumentach
  zostaje do ręcznego skasowania, bo to Twoje dokumenty).

Nie ma niczego do usunięcia po stronie autora, bo autor niczego nie ma.

## Dzieci

Aplikacja nie jest kierowana do dzieci i nie zbiera żadnych danych, więc nie
ma tu nic do osobnego uregulowania.

## Zmiany

Zmiany tej polityki są publikowane razem z nową wersją aplikacji, w tym samym
repozytorium co kod.

## Kontakt

[adres kontaktowy do uzupełnienia przed publikacją]
