# Pozycjonowanie

Dokument roboczy przed publikacją. Odpowiada na trzy pytania: dla kogo to jest,
czym różni się od tego, co już istnieje, i jakimi słowami ludzie tego szukają.
Z niego wynikają treści do sklepów ([google-play.md](google-play.md),
[microsoft-store.md](microsoft-store.md)) i README.

## Jedno zdanie

**PL:** Chatt łączy Twój komputer i telefon w jednej rozmowie: wiadomości
i pliki idą prosto między urządzeniami, zawsze zaszyfrowane, bez serwera,
konta i chmury.

**EN:** Chatt puts your PC and your phone in one conversation: messages and
files go straight from device to device, always encrypted, with no server,
no account and no cloud.

## Dla kogo

W kolejności od największej grupy do najbardziej zaangażowanej:

1. **Ludzie, którzy „wysyłają sami sobie".** Link z telefonu na komputer przez
   WhatsAppa do siebie, zdjęcie przez Messengera, plik mailem na własny adres.
   Ból: wszystko idzie przez cudzy serwer, limity rozmiaru, kompresja zdjęć,
   potrzebny internet. Chatt: to samo, tylko po Wi‑Fi w domu i bez pośrednika.
   To jest główna grupa i pod nią piszemy opisy w sklepach.
2. **Dbający o prywatność** (r/privacy, użytkownicy F-Droida, ludzie po
   lekturze o Signalu). Ból: „szyfrowane" u większości znaczy „do serwera
   i z powrotem". Chatt: nie ma serwera, więc nie ma czego podsłuchać
   pośrodku; forward secrecy; historia zaszyfrowana na dysku. Ta grupa czyta
   źródło, więc dla niej liczy się publiczne repozytorium i opisany model
   zagrożeń.
3. **Sieci bez internetu albo z odciętym internetem**: warsztat, laboratorium,
   szkoła, plener, statek, sieć gościnna w firmie. Ból: nic „chmurowego" nie
   działa. Chatt działa, bo potrzebuje tylko Wi‑Fi.
4. **Polska**: rodzimy program z polskim interfejsem i dokumentacją. Mała
   grupa, ale łatwa do dotarcia (Wykop, polskie subreddity, grupy FB o Androidzie).

Nie celujemy w: firmy szukające komunikatora zespołowego (to Slack/Teams),
osoby chcące rozmawiać przez internet (Chatt tego nie robi i nie będzie).

## Czym się różni

Konkurencja, z którą użytkownik nas porówna, w chwili pisania (wrzesień 2026):

| | Chatt | LocalSend | KDE Connect | PairDrop / Snapdrop |
|---|---|---|---|---|
| Rozmowa z historią | tak | nie, tylko przesyłanie | nie (schowek, powiadomienia, SMS telefonu) | nie |
| Szyfrowanie ruchu | zawsze, klucz na sesję, forward secrecy | TLS z własnym certyfikatem | TLS po sparowaniu | TLS przez przeglądarkę |
| Historia na dysku | zaszyfrowana, klucz w Keystore / DPAPI | brak historii | brak historii | brak historii |
| Serwer | żaden | żaden | żaden | serwer sygnalizacyjny |
| Odbiór przy zamkniętym oknie | tak (usługa na Androidzie, zasobnik na Windows) | ograniczony | tak | nie |
| Potwierdzenie, z kim rozmawiasz | kod QR albo porównanie cyfr | brak | parowanie | brak |
| Wznawianie przerwanego pliku | tak | nie | nie | nie |

Trzy rzeczy, których nie ma nikt z tej tabeli naraz, i to one idą na początek
każdego opisu:

1. **Rozmowa, nie tylko przerzucanie plików.** Historia zostaje, da się ją
   przeszukać, telefon i komputer widzą to samo.
2. **Szyfrowane zawsze, nie „po sparowaniu".** Pierwsza wiadomość do obcego
   urządzenia jest tak samo zaszyfrowana jak setna do sparowanego.
3. **Nic nie wychodzi z sieci lokalnej.** Zero serwera, zero konta, zero
   telemetrii. Da się to sprawdzić w źródle.

Czego **nie** obiecujemy, żeby nie łapać złych opinii: rozmów przez internet,
grup, iPhone'a, synchronizacji historii między urządzeniami.

## Słowa kluczowe

Pod wyszukiwarki sklepów i pod tytuły postów. Kolejność według tego, jak
ludzie naprawdę piszą, a nie jak my nazywamy funkcje.

**PL:** przesyłanie plików z telefonu na komputer, wysyłanie plików przez wifi,
komunikator w sieci lokalnej, czat bez internetu, szyfrowany czat, wiadomości
z telefonu na komputer, alternatywa dla localsend, zdjęcia z telefonu na pc bez
kabla, bez chmury.

**EN:** send files from phone to PC, wifi file transfer, local network chat,
LAN messenger, offline messenger, encrypted chat no server, airdrop for
windows and android, localsend alternative, phone to computer messages,
no cloud.

## Gdzie o tym mówić

Po upublicznieniu, w tej kolejności:

1. **Show HN** (Hacker News) z tytułem w stylu „Show HN: Chatt, a LAN
   messenger for PC and phone with no server and always-on E2E". Ta grupa
   docenia model zagrożeń i forward secrecy, więc link do
   `docs/architektura.md` w komentarzu.
2. **r/selfhosted, r/privacy, r/androidapps, r/opensource** — każdy z innym
   pierwszym zdaniem (self-hosted: „nie ma czego hostować"; privacy: „nie ma
   serwera"; androidapps: „zdjęcia na PC bez kabla i chmury").
3. **Wykop** (tag #android, #programowanie) i polskie grupy — po polsku,
   z podkreśleniem polskiego interfejsu.
4. **Wpis w porównaniach**: strona LocalSend ma listę alternatyw, AlternativeTo
   przyjmuje zgłoszenia.

Jeden post to jedna rzecz do pokazania: GIF z wysłaniem zdjęcia z telefonu
i pojawieniem się go na komputerze w sekundę. Nie lista funkcji.

## Nazwa

„Chatt" jest krótkie, ale w sklepach będzie obok setek aplikacji ze słowem
„chat" w nazwie i wyszukiwarka nie odróżni. Tytuł w sklepie dostaje dopisek
(„Chatt: czat w sieci lokalnej"), a przed rezerwacją nazwy w obu konsolach
trzeba sprawdzić, czy „Chatt" jest wolne — obie platformy wymagają
unikalnego tytułu.
