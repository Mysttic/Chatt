# Chatt — analiza stanu projektu i plan dokończenia

> Cel aplikacji: komunikacja między urządzeniami w tej samej sieci Wi‑Fi (np. PC ⇄ smartfon z Androidem) — wymiana wiadomości i plików **bezpośrednio (P2P)**, bez żadnego serwera pośredniczącego.
>
> Dokument roboczy — aktualizujemy checklisty w miarę postępów.

## 1. Stan obecny (sierpień 2026)

Rozwiązanie .NET MAUI (net7.0) z 5 projektami:

| Projekt | Rola | Stan |
|---|---|---|
| `Chatt` | UI MAUI (Shell, widoki: lista konwersacji, konwersacja, urządzenia w pobliżu, ustawienia) | Szkielet UI jest, ale widoki działają na danych zaszytych na sztywno w ViewModelach |
| `Chatt.Entities` | Modele + repozytoria (sqlite-net-pcl + SQLiteNetExtensions) | Repozytoria działają; relacje między modelami źle zamapowane |
| `Chatt.DataContext` | EF Core + migracja + seed ustawień | **Duplikat** warstwy danych — aplikacja go nie używa (używa sqlite-net) |
| `Chatt.Network` | `Discovery` (ping-sweep + skan portów TCP), `FirewallRuleManager` (PowerShell/UAC) | Discovery działa, ale wolne i tylko koncepcyjnie; firewall tylko Windows, a wywoływany wszędzie |
| `Chatt.grpc` | Serwer+klient gRPC (Grpc.Core), serwisy testowe Greet/Test | Prototyp "hello world"; brak właściwego serwisu wiadomości i plików |

Co już **przemyślane i wartościowe**: diagram przepływów w `Prototype/` (obsługa niedostarczonych wiadomości, ponawianie, weryfikacja czy odbiorca wciąż istnieje w sieci), makiety UI, model danych z polami `Created/Received/Resend` i flagą `Verified` u użytkownika, filtry IP/portów w ustawieniach (`192.168.0.1-192.168.0.255;192.168.10.*`, `50001-50010`) wraz z parserami.

## 2. Krytyczne problemy do naprawy

1. **Crash przy pierwszym uruchomieniu** — `App.xaml.cs` rzuca `Exception("Settings not found")`, bo seed ustawień istnieje tylko w migracji EF Core, której aplikacja nigdy nie odpala (używa sqlite-net). Trzeba tworzyć domyślne ustawienia w kodzie.
2. **Android w ogóle nie wystartuje** — `FirewallRuleManager` (cmd.exe/PowerShell/UAC) jest wywoływany bezwarunkowo w konstruktorze `App`. Musi być za `#if WINDOWS` / `OperatingSystem.IsWindows()`.
3. **`Grpc.Core` jest martwe** — biblioteka wycofana (EOL), natywne biblioteki nie działają na współczesnym net-android. To główny blocker całej komunikacji na telefonie.
4. **`Ping` na Androidzie jest zawodny** — `System.Net.NetworkInformation.Ping` na Androidzie często nie działa (ICMP wymaga uprawnień raw socket). Obecne discovery oparte o ping-sweep nie zadziała na telefonie.
5. **Discovery jest sekwencyjne i ekstremalnie wolne** — zakres /24 × timeouty 1–5 s = minuty skanowania; `TcpClient` po `Task.WhenAny` nie jest anulowany (wycieki + unobserved exceptions). Wyniki discovery lądują tylko w `Debug.WriteLine` — nie zasilają listy `Users` w UI ani bazy.
6. **Dwie równoległe warstwy danych** (sqlite-net i EF Core) na tej samej bazie `chatt.db`, ze zduplikowanym `Constants.cs` — do konsolidacji.
7. **Złe mapowanie relacji** — atrybut `[ManyToMany]` na polach `int ConversationId`/`UserId` w `MessageModel`/`ConversationModel`; faktyczna relacja to 1‑do‑wielu (konwersacja→wiadomości) i powinna być `[ForeignKey]`/`[OneToMany]`. Obecnie `GetItemsWithChildren` nie złoży poprawnie obiektów.
8. **`MessageModel.Message` ma `MaxLength(255)`** — za mało na czat; brak w modelu czegokolwiek pod pliki (typ wiadomości, ścieżka, rozmiar, postęp).
9. **UI konwersacji nie ma pola do wpisania wiadomości** — `ConversationView.xaml` zawiera tylko listę; brak Entry + przycisku wyślij, brak rozróżnienia moje/cudze dymki.
10. **ViewModele na danych testowych** — `ConversationsViewModel` (zaszyte 3 konwersacje), `SettingsViewModel`/`UsersNearbyViewModel` (zaszyty `SettingsModel`, nic nie zapisują przez `SettingsRepository`).
11. **`GrpcFactor`** — singleton z dziwnymi niezmiennikami (port 44444 na sztywno, klient do własnego serwera), do zastąpienia wraz z wymianą transportu.
12. **net7.0 jest poza wsparciem** — obecnie wspierane MAUI to .NET 10 (LTS); migracja net7→net10 jest w tym projekcie mało inwazyjna.

## 3. Decyzje architektoniczne (rekomendacje)

### 3.1 Transport: raw TCP + ramki Protobuf (zamiast gRPC) — REKOMENDOWANE

- gRPC wymaga po stronie serwera ASP.NET Core/Kestrel, które **nie jest oficjalnie wspierane na net-android** — a w P2P każde urządzenie musi nasłuchiwać. To fundament aplikacji, nie miejsce na kruchy hack.
- Zamiast tego: jeden `TcpListener` na urządzenie + trwałe połączenie duplex per rozmówca. Ramka: `[4B długość][1B typ][payload protobuf]`. Definicje wiadomości **zostają w .proto** (Hello/HelloAck, ChatMessage, MessageAck, FileOffer/FileChunk/FileDone, Ping/Pong) — serializacja przez `Google.Protobuf`, wyrzucamy tylko runtime gRPC.
- Zaleta dla nas: cała logika protokołu to czysta biblioteka .NET — testowalna jednostkowo bez emulatora i bez MAUI.

### 3.2 Discovery: broadcast UDP (zamiast ping-sweep)

- Każda instancja nasłuchuje na stałym porcie UDP (np. 50000) i odpowiada na zapytanie `CHATT_DISCOVER` pakietem z tożsamością (GUID urządzenia, nick, welcome message, port TCP). Skan całej sieci = 1 broadcast + ~2 s zbierania odpowiedzi, działa na Androidzie bez ICMP.
- Zostawiamy **ręczne dodanie po IP:port** jako fallback (jest w makietach `ManuallyFindDevice.PNG`) — przydatne, gdy router blokuje broadcast (izolacja AP).
- Filtry IP/portów z ustawień zachowujemy jako opcjonalne zawężenie wyników.

### 3.3 Tożsamość i dane

- Tożsamość urządzenia = trwały GUID generowany przy pierwszym uruchomieniu (pole `UniqueIdentifier` już istnieje w `UserModel`) — IP może się zmieniać (DHCP), GUID nie.
- Baza: **zostaje sqlite-net-pcl**, projekt `Chatt.DataContext` (EF Core) usuwamy. Seed domyślnych ustawień w kodzie przy starcie. Naprawa relacji (FK zamiast ManyToMany), zdjęcie limitu 255, dodanie pól pod pliki i status dostarczenia.

### 3.4 Platforma

- Migracja na **.NET 10 / MAUI 10** (aktualny LTS). Cele: `net10.0-windows` + `net10.0-android` (iOS/Mac odkładamy).
- UI: dołożyć `CommunityToolkit.Mvvm` (ObservableProperty, RelayCommand, WeakReferenceMessenger do pchania odebranych wiadomości do UI), rejestracja ViewModeli w DI zamiast tworzenia w code-behind.
- Bezpieczeństwo: MVP jawnym tekstem w LAN (świadomie); w fazie 5 parowanie z kodem PIN + szyfrowanie (flaga `Verified` już na to czeka).

## 4. Plan — fazy

### Faza 0 — Reanimacja fundamentów (projekt się buduje i odpala na obu platformach)
- [ ] Migracja net7.0 → net10.0 (TFM-y, pakiety, workload MAUI)
- [ ] Usunięcie `Chatt.DataContext`, jeden `Constants.cs`
- [ ] Seed domyślnych ustawień w kodzie zamiast `throw` przy starcie
- [ ] `FirewallRuleManager` tylko na Windows; start bez UAC gdy reguła już istnieje
- [ ] Generowanie i zapis GUID urządzenia przy pierwszym starcie
- [ ] `SettingsView` realnie czyta/zapisuje przez `SettingsRepository`

### Faza 1 — Nowy transport (biblioteka `Chatt.Protocol`)
- [ ] Nowe .proto: Hello/HelloAck, ChatMessage, MessageAck, Ping/Pong (+ rezerwacja typów pod pliki)
- [ ] Framing TCP (długość+typ+payload), `PeerListener` i `PeerConnection` (duplex, auto-reconnect)
- [ ] Testy jednostkowe protokołu (handshake, wymiana wiadomości, zerwanie połączenia)
- [ ] Usunięcie `Chatt.grpc` i pakietów Grpc.*

### Faza 2 — Discovery v2
- [ ] Responder UDP (nasłuch + odpowiedź z tożsamością) i skaner (broadcast + zbieranie odpowiedzi)
- [ ] `UsersNearbyView` pokazuje realne wyniki, zapis znalezionych do `Users` w bazie
- [ ] Ręczne dodanie urządzenia po IP:port (fallback)
- [ ] Testy jednostkowe (dwie instancje w jednym procesie znajdują się nawzajem)

### Faza 3 — Wiadomości end‑to‑end (serce aplikacji)
- [ ] Naprawa modeli/relacji + pola statusu dostarczenia
- [ ] `ConversationView`: pole tekstowe + wyślij, dymki moje/cudze, autoscroll
- [ ] Wysyłka: zapis do bazy → wysłanie → ack → aktualizacja statusu; oznaczanie niedostarczonych i ręczne ponowienie (przepływ z diagramu w `Prototype/`)
- [ ] Odbiór: przychodząca wiadomość → znajdź/utwórz konwersację → zapis → powiadomienie UI (WeakReferenceMessenger)
- [ ] Lista konwersacji z bazy (koniec mocków), licznik nieprzeczytanych, weryfikacja obecności rozmówców (Ping) przy starcie
- [ ] **Kamień milowy: pierwsza prawdziwa rozmowa PC ⇄ Android**

### Faza 4 — Pliki
- [ ] Protokół: FileOffer → Accept/Reject → FileChunk (strumieniowo) → FileDone (+ suma kontrolna, wznawianie)
- [ ] Wybór pliku (FilePicker), zapis w katalogu aplikacji + "udostępnij/otwórz"; uprawnienia Androida
- [ ] UI: wiadomość-plik z paskiem postępu, akceptacja odbioru
- [ ] Testy transferu na dużych plikach

### Faza 5 — Szlif
- [ ] Parowanie/weryfikacja urządzeń (PIN na obu ekranach → `Verified`), potem szyfrowanie transmisji
- [ ] Nasłuch w tle na Androidzie (foreground service) + powiadomienia lokalne
- [ ] Obsługa zmiany IP rozmówcy (ponowne discovery po GUID)
- [ ] Porządki UI (style, tryb ciemny, ikony zamiast dotnet_bot)

## 5. Jak pracujemy razem

- **Sesje Claude (to repo, branch `claude/wifi-device-communication-npzb1g`)**: cała logika nie-UI (protokół, discovery, warstwa danych) powstaje jako zwykłe biblioteki .NET z testami — da się je budować i testować w chmurze bez Windows/Androida. Kod MAUI też piszę tutaj, ale nie mam jak go uruchomić.
- **Ty (Visual Studio + PC z Windows + telefon z Androidem w jednej sieci Wi‑Fi)**: build MAUI, uruchomienie na sprzęcie, testy ręczne wg krótkiej checklisty dołączanej do każdej porcji zmian, feedback (logi/screeny).
- Rytm: jedna faza (lub jej wycinek) na iterację; po Twoich testach odhaczamy pozycje tutaj i jedziemy dalej.

## 6. Pierwszy krok

Faza 0 w całości + szkielet Fazy 1 — po tym projekt buduje się na net10, odpala na Windows i Androidzie bez crasha, a w repo jest przetestowana biblioteka protokołu gotowa pod messaging.
