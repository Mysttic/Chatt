// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appTitle => 'Chatt';

  @override
  String get cancel => 'Anuluj';

  @override
  String get delete => 'Usuń';

  @override
  String get confirm => 'Potwierdź';

  @override
  String get close => 'Zamknij';

  @override
  String get copy => 'Kopiuj';

  @override
  String errorWithDetails(Object details) {
    return 'Błąd: $details';
  }

  @override
  String get settingsTitle => 'Ustawienia';

  @override
  String get nearbyButton => 'W pobliżu';

  @override
  String get noConversationsTitle => 'Brak rozmów';

  @override
  String get noConversationsBody =>
      'Znajdź urządzenia w tej samej sieci Wi-Fi przyciskiem „W pobliżu” i napisz pierwszą wiadomość.';

  @override
  String deleteConversationTitle(Object name) {
    return 'Usunąć rozmowę z $name?';
  }

  @override
  String get deleteConversationBody =>
      'Znikną wiadomości i samo urządzenie z listy znanych. Odebrane pliki zostają na dysku.';

  @override
  String conversationDeleted(Object name) {
    return 'Usunięto rozmowę z $name';
  }

  @override
  String get pickConversation => 'Wybierz rozmowę z listy';

  @override
  String get nearbyTitle => 'Urządzenia w pobliżu';

  @override
  String get addByAddress => 'Dodaj po adresie IP';

  @override
  String scanRunning(int count) {
    return 'Szukam… (znaleziono $count)';
  }

  @override
  String get scanStart => 'Szukaj urządzeń w sieci';

  @override
  String get scanNothingFound =>
      'Nie znaleziono urządzeń. Sprawdź, czy Chatt działa na drugim urządzeniu w tej samej sieci, albo dodaj je ręcznie po adresie.';

  @override
  String scanFound(int count) {
    return 'Znaleziono: $count';
  }

  @override
  String get nearbyBeforeScan =>
      'Wyszukaj urządzenia, żeby zobaczyć, które odpowiadają w tej chwili.';

  @override
  String get longPressToDelete => 'Przytrzymaj urządzenie, żeby je usunąć';

  @override
  String lastSeen(Object when) {
    return 'widziano $when';
  }

  @override
  String deleteDeviceTitle(Object name) {
    return 'Usunąć $name?';
  }

  @override
  String get deleteDeviceBody =>
      'Urządzenie zniknie z listy razem z rozmową i jej wiadomościami. Odebrane pliki zostają na dysku.';

  @override
  String deviceDeleted(Object name) {
    return 'Usunięto $name';
  }

  @override
  String get manualAddTitle => 'Dodaj urządzenie po adresie';

  @override
  String get ipLabel => 'Adres IP';

  @override
  String get ipHint => 'np. 192.168.1.20';

  @override
  String get portLabel => 'Port';

  @override
  String get connect => 'Połącz';

  @override
  String noChattAtAddress(Object host, int port) {
    return 'Pod $host:$port nie odpowiada żaden Chatt.';
  }

  @override
  String get copied => 'Skopiowano';

  @override
  String get securityNoEncryptionTitle => 'Bez szyfrowania';

  @override
  String get securityNoEncryptionBody =>
      'Po drugiej stronie działa starsza wersja Chatta, która nie umie szyfrować. Dopóki jej nie zaktualizujesz, ta rozmowa nie ruszy.';

  @override
  String get securityEncryptedTitle => 'Szyfrowane, tożsamość niepotwierdzona';

  @override
  String get securityEncryptedBody =>
      'Nikt w sieci nie przeczyta tej rozmowy. Nie masz jeszcze potwierdzenia, że po drugiej stronie jest ta osoba, o której myślisz: nazwę urządzenia każdy może sobie ustawić dowolnie.';

  @override
  String get securityVerifiedTitle => 'Szyfrowane i potwierdzone';

  @override
  String get securityVerifiedBody =>
      'Porównaliście kod, więc wiadomo, do kogo należy klucz po drugiej stronie.';

  @override
  String get fingerprintMine => 'Odcisk tego urządzenia';

  @override
  String fingerprintOf(Object name) {
    return 'Odcisk urządzenia $name';
  }

  @override
  String get fingerprintHelp =>
      'Odcisk wynika z klucza urządzenia i nigdy się nie zmienia. Odczytaj go na głos i sprawdź, czy druga strona widzi to samo. Jeśli tak, nikt nie siedzi w środku rozmowy.';

  @override
  String get peerOnline => 'dostępny';

  @override
  String get peerOffline => 'niedostępny';

  @override
  String get shieldNoEncryption =>
      'Bez szyfrowania: druga strona ma starszą wersję';

  @override
  String get shieldEncrypted =>
      'Szyfrowane, ale tożsamość niepotwierdzona. Kliknij, żeby porównać kod';

  @override
  String get shieldVerified => 'Szyfrowane i potwierdzone';

  @override
  String get pairTooltip => 'Sparuj przez porównanie kodu';

  @override
  String get sendFileTooltip => 'Wyślij plik';

  @override
  String get sendTooltip => 'Wyślij';

  @override
  String get messageHint => 'Napisz wiadomość…';

  @override
  String get notDeliveredRetry => 'Nie dostarczono, ponów';

  @override
  String get fileFallbackName => 'plik';

  @override
  String get openFile => 'Otwórz';

  @override
  String get showFolder => 'Pokaż folder';

  @override
  String get shareFile => 'Udostępnij';

  @override
  String get copyPath => 'Kopiuj ścieżkę';

  @override
  String get saveFile => 'Zapisz na urządzeniu';

  @override
  String get saveFileHint =>
      'Kopia w Zdjęciach albo Pobranych, poza katalogiem aplikacji';

  @override
  String savedTo(Object where) {
    return 'Zapisano w $where';
  }

  @override
  String get saveFailed => 'Nie udało się zapisać pliku.';

  @override
  String get saveUnsupported =>
      'Ten system nie ma gdzie zapisać pliku bez dodatkowych uprawnień. Użyj „Udostępnij”.';

  @override
  String get fileGone => 'Tego pliku już nie ma na dysku.';

  @override
  String get fileOpenFailed => 'Nie udało się otworzyć pliku.';

  @override
  String get imageLoadFailed => 'Nie udało się wczytać obrazu.';

  @override
  String get rotate => 'Obróć';

  @override
  String receivingFile(Object name) {
    return 'Odbieram: $name';
  }

  @override
  String get pairStartFailed =>
      'Nie udało się zacząć parowania: urządzenie nie odpowiada.';

  @override
  String get pairAgainWarning =>
      'Tożsamość tego urządzenia jest już potwierdzona. Prośbę mógł przysłać ktoś inny pod tą samą nazwą, więc potwierdzaj tylko wtedy, gdy sam o to poprosiłeś.';

  @override
  String pairRequest(Object name) {
    return '$name chce się sparować';
  }

  @override
  String get qrShowTitle => 'Pokaż kod QR';

  @override
  String get qrShowBody =>
      'Zeskanuj ten kod drugim urządzeniem. Kod nie zawiera nic tajnego. Liczy się to, że drugie urządzenie widziało go na tym ekranie.';

  @override
  String get qrOtherAddress => 'Inny adres';

  @override
  String get qrScanTitle => 'Zeskanuj kod QR';

  @override
  String get qrScanHint => 'Wyceluj w kod pokazany na drugim urządzeniu';

  @override
  String get qrScanFailed =>
      'Pod adresem z kodu nie ma urządzenia z tym kluczem. Kod może być nieaktualny, pokaż go jeszcze raz.';

  @override
  String pairScannedTitle(Object name) {
    return '$name zeskanował kod z tego ekranu';
  }

  @override
  String get pairScannedBody =>
      'Potwierdź tylko wtedy, gdy to Ty właśnie skanowałeś. Kod z ekranu mógł zobaczyć ktoś jeszcze, a aplikacja nie ma jak tego rozstrzygnąć.';

  @override
  String get pairScannedConfirm => 'To ja skanowałem';

  @override
  String get pairCompareHint =>
      'Sprawdź, czy drugie urządzenie pokazuje ten sam kod:';

  @override
  String get pairCodesMatch => 'Zgadza się';

  @override
  String get pairCodesDiffer => 'Nie zgadza się';

  @override
  String get pairChecking => 'Czekam…';

  @override
  String pairedWith(Object name) {
    return 'Sparowano z $name';
  }

  @override
  String get pairRejected => 'Drugie urządzenie przerwało parowanie';

  @override
  String get pairCodeExpired => 'Parowanie straciło ważność, zacznij od nowa';

  @override
  String get pairPeerUnreachable => 'Drugie urządzenie nie odpowiada';

  @override
  String get dropFilesHint => 'Upuść pliki, żeby je wysłać';

  @override
  String get attachFromDevice => 'Plik z urządzenia';

  @override
  String get attachFromClipboard => 'Wklej ze schowka';

  @override
  String get pasteNothing => 'Nie udało się nic wziąć ze schowka';

  @override
  String get pastedImageName => 'obraz.png';

  @override
  String get copyText => 'Kopiuj tekst';

  @override
  String get deleteMessage => 'Usuń wiadomość';

  @override
  String get deleteMessageHint => 'Zniknie tylko z tego urządzenia';

  @override
  String get messageDeleted => 'Wiadomość usunięta z tego urządzenia';

  @override
  String get searchTooltip => 'Szukaj w rozmowie';

  @override
  String get searchHint => 'Szukaj w rozmowie…';

  @override
  String get searchConversationsTooltip => 'Szukaj rozmowy';

  @override
  String get searchConversationsHint => 'Szukaj rozmowy…';

  @override
  String searchNothingFound(Object query) {
    return 'Nic nie pasuje do „$query”';
  }

  @override
  String fileOfferTitle(Object name) {
    return '$name chce wysłać plik';
  }

  @override
  String fileOfferResume(Object size, Object have) {
    return '$size, wznowienie: masz już $have';
  }

  @override
  String get unpairedWarning =>
      'Tożsamość niepotwierdzona: nazwę można sobie ustawić dowolną';

  @override
  String fileOfferBatchTitle(Object name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'chce wysłać $count plików',
      few: 'chce wysłać $count pliki',
      one: 'chce wysłać $count plik',
    );
    return '$name $_temp0';
  }

  @override
  String get acceptAll => 'Przyjmij wszystkie';

  @override
  String moreFilesWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Czeka jeszcze $count plików',
      few: 'Czekają jeszcze $count pliki',
      one: 'Czeka jeszcze $count plik',
    );
    return '$_temp0';
  }

  @override
  String get reject => 'Odrzuć';

  @override
  String get accept => 'Akceptuj';

  @override
  String get nicknameLabel => 'Twój nick';

  @override
  String get nicknameRequired => 'Podaj nick';

  @override
  String get welcomeLabel => 'Wiadomość powitalna';

  @override
  String get welcomeHelper => 'Widoczna dla innych przy wyszukiwaniu';

  @override
  String get portFieldLabel => 'Preferowany port nasłuchu';

  @override
  String get portRange => 'Port z zakresu 1024 do 65535';

  @override
  String get save => 'Zapisz';

  @override
  String get saved => 'Zapisano.';

  @override
  String get savedRestartNeeded =>
      'Zapisano. Nowy port zacznie działać po ponownym uruchomieniu aplikacji.';

  @override
  String get appearance => 'Wygląd';

  @override
  String get themeSystem => 'Systemowy';

  @override
  String get themeLight => 'Jasny';

  @override
  String get themeDark => 'Ciemny';

  @override
  String get background => 'Tło';

  @override
  String get backgroundNone => 'Bez tła';

  @override
  String get backgroundDusk => 'Zmierzch';

  @override
  String get backgroundOcean => 'Ocean';

  @override
  String get backgroundForest => 'Las';

  @override
  String get backgroundSand => 'Piasek';

  @override
  String get language => 'Język';

  @override
  String get languageSystem => 'Systemowy';

  @override
  String get languagePolish => 'Polski';

  @override
  String get languageEnglish => 'Angielski';

  @override
  String get backgroundListening => 'Nasłuch w tle';

  @override
  String get batteryExemptOk =>
      'System nie usypia Chatta. Wiadomości i pliki dochodzą też przy zgaszonym ekranie.';

  @override
  String get batteryOptimizedWarning =>
      'Android usypia Chatta przy zgaszonym ekranie i potrafi odciąć mu sieć. Bez wyjątku wiadomości mogą nie dochodzić, dopóki nie otworzysz aplikacji.';

  @override
  String get batteryExemptButton => 'Wyłącz optymalizację baterii';

  @override
  String get batteryExemptUnavailable =>
      'To urządzenie nie ma ekranu z optymalizacją baterii. Poszukaj jej w ustawieniach systemu.';

  @override
  String get cleanUpDevices => 'Wyczyść nieużywane urządzenia';

  @override
  String get cleanUpHelp =>
      'Usuwa z listy urządzenia, z którymi nie ma żadnej wiadomości i których nie widać od godziny. Sparowanych i rozmów nie rusza.';

  @override
  String get nothingToCleanUp => 'Nie było czego usuwać.';

  @override
  String cleanedUp(int count) {
    return 'Usunięto z listy: $count';
  }

  @override
  String get privacy => 'Prywatność';

  @override
  String get dbKeyProtected =>
      'Historia leży na dysku zaszyfrowana, a klucz do niej trzyma schowek systemowy. Skopiowanie samego pliku bazy nic nie da.';

  @override
  String get dbKeyUnprotected =>
      'Historia jest zaszyfrowana, ale schowek systemowy nie przyjął klucza, więc leży on obok bazy. Chroni to sam plik bazy; kopia całego katalogu aplikacji zawiera też klucz.';

  @override
  String get retentionLabel => 'Kasuj wiadomości starsze niż';

  @override
  String get retentionNever => 'Nie kasuj';

  @override
  String retentionDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dni',
      many: '$count dni',
      few: '$count dni',
      one: '$count dzień',
    );
    return '$_temp0';
  }

  @override
  String get retentionHelp =>
      'Kasowanie dotyczy wpisów w rozmowach. Odebrane pliki zostają na dysku.';

  @override
  String get clearHistory => 'Wyczyść historię';

  @override
  String get clearHistoryTitle => 'Wyczyścić całą historię?';

  @override
  String get clearHistoryBody =>
      'Znikną wszystkie wiadomości i rozmowy. Urządzenia razem z potwierdzoną tożsamością zostają, odebrane pliki też zostają na dysku.';

  @override
  String historyCleared(int count) {
    return 'Usunięto wiadomości: $count';
  }

  @override
  String get links => 'Odnośniki';

  @override
  String get linkPreviewsLabel => 'Pokazuj podglądy stron';

  @override
  String get linkPreviewsHelp =>
      'Pod odnośnikiem w rozmowie pojawia się karta z tytułem, opisem i obrazkiem strony. Żeby ją pobrać, aplikacja łączy się z tą stroną, więc jej serwer zobaczy adres IP tego urządzenia i moment, w którym wiadomość dotarła. Domyślnie wyłączone.';

  @override
  String get linkPreviewsSafety =>
      'Podgląd to sam tekst i obrazek. Aplikacja nie otwiera strony, nie uruchamia żadnych skryptów z niej i nie pobiera podglądów spod adresów w Twojej sieci lokalnej. Kliknięcie w odnośnik zawsze najpierw pyta o potwierdzenie.';

  @override
  String linkPreviewOf(Object site) {
    return 'Podgląd strony: $site';
  }

  @override
  String get linkConfirmTitle => 'Czy na pewno chcesz przejść do tej strony?';

  @override
  String get linkConfirmHost => 'Adres prowadzi do serwera';

  @override
  String get linkConfirmFull => 'Pełny adres';

  @override
  String get linkOpen => 'Otwórz';

  @override
  String get linkOpenTitle => 'Otwórz odnośnik';

  @override
  String get linkCopy => 'Kopiuj adres';

  @override
  String get linkCopied => 'Skopiowano adres.';

  @override
  String get linkOpenFailed => 'Nie udało się otworzyć przeglądarki.';

  @override
  String get linkWarnUserInfo =>
      'W adresie stoi znak @: to, co widać przed nim, nie jest nazwą serwera. Liczy się nazwa pokazana wyżej.';

  @override
  String get linkWarnNonAscii =>
      'Nazwa serwera zawiera litery spoza alfabetu łacińskiego. Bywają nie do odróżnienia od zwykłych, a prowadzą gdzie indziej.';

  @override
  String get linkWarnInsecure =>
      'Połączenie bez szyfrowania (http). Ktoś w tej samej sieci może podejrzeć i podmienić treść strony.';

  @override
  String get linkWarnLocal =>
      'Adres wskazuje na urządzenie w Twojej sieci lokalnej, na przykład na router.';

  @override
  String get updates => 'Aktualizacje';

  @override
  String get updateChecksLabel => 'Sprawdzaj aktualizacje automatycznie';

  @override
  String get updateChecksHelp =>
      'Raz na dobę Chatt pyta GitHuba, czy wyszło nowsze wydanie. To jedyna rzecz, którą aplikacja wysyła poza Twoją sieć, i stoi wyłączona, dopóki jej nie włączysz.';

  @override
  String get updateCheckNow => 'Sprawdź teraz';

  @override
  String get updateChecking => 'Sprawdzam…';

  @override
  String get updateUpToDate => 'To najnowsze wydanie.';

  @override
  String updateAvailable(Object version) {
    return 'Wyszła wersja $version';
  }

  @override
  String get updateDownload => 'Pobierz i zainstaluj';

  @override
  String updateDownloading(int percent) {
    return 'Pobieram… $percent%';
  }

  @override
  String get updatePortableHint =>
      'Ta kopia chodzi z zipa, więc nową trzeba rozpakować ręcznie. Strona wydania:';

  @override
  String get updateNoAsset =>
      'To wydanie nie ma pliku dla tej platformy. Strona wydania:';

  @override
  String get updateInstallFailed => 'Nie udało się uruchomić instalatora.';

  @override
  String get updateDownloadFailed => 'Nie udało się pobrać pliku.';

  @override
  String get updateClosingForInstall =>
      'Chatt zamyka się teraz, dalej pracuje instalator.';

  @override
  String updateLastChecked(Object when) {
    return 'Ostatnio sprawdzano $when';
  }

  @override
  String get thisDevice => 'To urządzenie';

  @override
  String get version => 'Wersja';

  @override
  String get listeningOn => 'Nasłuch';

  @override
  String get deviceIdentifier => 'Identyfikator';

  @override
  String listeningPort(int port) {
    return 'port $port';
  }

  @override
  String get manualPairingHint =>
      'Ten adres wpisujesz na drugim urządzeniu w „Dodaj po adresie IP”, gdy automatyczne wykrywanie nie działa.';

  @override
  String get windowsSection => 'Windows';

  @override
  String get startWithWindows => 'Uruchamiaj razem z Windowsem';

  @override
  String get startWithWindowsHelp =>
      'Chatt wstaje po zalogowaniu i od razu siada w zasobniku, więc wiadomości dochodzą bez otwierania okna.';

  @override
  String get startWithWindowsFailed => 'Nie udało się zmienić autostartu.';

  @override
  String get trayHint =>
      'Zamknięcie okna chowa Chatt do zasobnika i nie przerywa nasłuchu. Wyjście z programu jest w menu ikony.';

  @override
  String get trayTooltip => 'Chatt: nasłuchuje w sieci lokalnej';

  @override
  String get trayShow => 'Pokaż Chatt';

  @override
  String get trayQuit => 'Zamknij Chatt';

  @override
  String get backgroundServiceTitle => 'Chatt nasłuchuje';

  @override
  String get backgroundServiceBody =>
      'Odbiera wiadomości i pliki z tej sieci Wi-Fi';

  @override
  String get copyImage => 'Kopiuj obraz';

  @override
  String get imageCopied => 'Obraz skopiowany do schowka';

  @override
  String get imageCopyFailed => 'Nie udało się skopiować obrazu';

  @override
  String get renamePeer => 'Zmień nazwę';

  @override
  String get renamePeerTitle => 'Twoja nazwa tego urządzenia';

  @override
  String get renamePeerHelp =>
      'Nazwa zostaje na tym urządzeniu i nigdzie nie jedzie. Puste pole wraca do nazwy, którą rozgłasza samo urządzenie.';

  @override
  String peerRenamed(String name) {
    return 'Nazwa zmieniona na $name';
  }

  @override
  String get peerRenameCleared => 'Wróciła nazwa rozgłaszana';

  @override
  String broadcastName(String name) {
    return 'Nazwa rozgłaszana: $name';
  }

  @override
  String get autoAcceptTitle => 'Przyjmuj pliki bez pytania';

  @override
  String get autoAcceptBody =>
      'Pliki od tego urządzenia trafiają prosto do rozmowy, bez karty z pytaniem. Działa tylko przy potwierdzonej tożsamości, a przełącznik gaśnie sam, gdy potwierdzenie zniknie.';

  @override
  String get autoAcceptNeedsVerified => 'Najpierw potwierdź tożsamość';

  @override
  String get selectText => 'Zaznacz tekst';

  @override
  String get selectTextHint => 'Przytrzymaj, żeby zaznaczyć fragment';

  @override
  String get discoveryDeaf =>
      'To urządzenie nie odpowiada na skany. Inni znajdą je dopiero po ręcznym dodaniu adresu. Najczęstsza przyczyna: port 47777 zajęty przez inny program.';

  @override
  String get addons => 'Dodatki';

  @override
  String get addonsHelp =>
      'Funkcje, których większość osób nie potrzebuje. Wyłączony dodatek nie wychodzi poza tę sekcję: nie widać go na żadnym innym ekranie i niczego nie uruchamia.';

  @override
  String get transportsHelp =>
      'Dwie drogi, obie mogą być włączone naraz. Sieć jest kilkadziesiąt razy szybsza, Bluetooth działa bez żadnej sieci, gdy urządzenia są obok siebie.';

  @override
  String get transportWifi => 'Sieć lokalna';

  @override
  String get transportWifiHelp =>
      'Wiadomości i pliki przez Wi-Fi albo kabel. Wymaga, żeby oba urządzenia były w tej samej sieci.';

  @override
  String get transportBluetooth => 'Bluetooth';

  @override
  String get transportBluetoothHelp =>
      'Wiadomości i pliki przez radio, bez routera, adresu i wspólnej sieci. Kilkadziesiąt razy wolniej niż Wi-Fi, więc duży plik potrwa. Włączenie dodaje szukanie przez Bluetooth w „W pobliżu” i znacznik drogi w rozmowach.';

  @override
  String get transportBluetoothUnsupported =>
      'Na tym systemie nie ma Bluetootha w Chatcie.';

  @override
  String get transportBluetoothRadioOff =>
      'Włącz Bluetooth w ustawieniach systemu.';

  @override
  String get transportBluetoothNoPermission =>
      'Chatt nie ma zgody na urządzenia w pobliżu.';

  @override
  String get transportBluetoothGrant => 'Otwórz ustawienia';

  @override
  String get transportBluetoothFailed => 'Nie udało się włączyć Bluetootha.';

  @override
  String get transportBothOff =>
      'Sieć wyłączona, a Bluetooth nie działa: to urządzenie z nikim się nie skontaktuje.';

  @override
  String get transportBluetoothDiscoverable =>
      'Przy włączonym dodatku ten komputer jest widoczny dla urządzeń w pobliżu. Gaśnie razem z przełącznikiem.';

  @override
  String get keyboardAddon => 'Klawiatura z PC';

  @override
  String get keyboardAddonHelp =>
      'Pisanie z klawiatury komputera w polu, które ma fokus na drugim urządzeniu, w dowolnej aplikacji. Tylko między urządzeniami z potwierdzoną tożsamością, tym samym szyfrowanym kanałem co rozmowy.';

  @override
  String get remoteInputReceive => 'Pozwól pisać na tym urządzeniu';

  @override
  String get remoteInputReceiveHelp =>
      'Potwierdzone urządzenie może poprosić o pisanie tutaj. Każda sesja zaczyna się od pytania na tym ekranie.';

  @override
  String get remoteInputSafety =>
      'Drugie urządzenie pisze tu jak zwykła klawiatura: może wysłać wiadomość, zatwierdzić formularz, wpisać hasło. Sesja trwa do Stopu albo do pół godziny bez pisania.';

  @override
  String get remoteInputUnsupported =>
      'Pisanie z innego urządzenia przyjmują Android i Windows.';

  @override
  String remoteInputRequestTitle(Object name) {
    return '$name chce pisać na tym urządzeniu';
  }

  @override
  String get remoteInputRequestBody =>
      'Tekst trafi do pola, które ma fokus, w dowolnej aplikacji, aż do Stopu.';

  @override
  String remoteInputActive(Object name) {
    return 'Pisze: $name';
  }

  @override
  String get remoteInputStop => 'Stop';

  @override
  String remoteInputBarTarget(Object name, Object app) {
    return 'Pisze: $name → $app';
  }

  @override
  String get trayRemoteInputStop => 'Zatrzymaj zdalną klawiaturę';

  @override
  String get remoteInputSwitchTitle => 'Przełącz klawiaturę na Chatt';

  @override
  String remoteInputSwitchBody(Object name) {
    return '$name pisze na tym urządzeniu. Dotknij i wybierz klawiaturę Chatt.';
  }

  @override
  String get remoteInputImeOff =>
      'Pisanie z innego urządzenia przechodzi przez klawiaturę Chatt. Włącz ją raz w ustawieniach systemu.';

  @override
  String get remoteInputImeWarning =>
      'Android ostrzeże, że klawiatura może zbierać wpisywany tekst. Klawiatura Chatt nie czyta pól: wpisuje to, co przyjdzie od urządzenia, któremu pozwolisz pisać.';

  @override
  String get remoteInputImeEnable => 'Włącz klawiaturę Chatt';

  @override
  String get remoteInputImeNotSelected =>
      'Na czas pisania wybierz klawiaturę Chatt. Po sesji wraca poprzednia.';

  @override
  String get remoteInputImePick => 'Wybierz klawiaturę';

  @override
  String get remoteInputImeReady => 'Klawiatura Chatt jest włączona.';

  @override
  String get remoteInputSendHint =>
      'Żeby pisać na innym urządzeniu, otwórz z nim rozmowę i wybierz klawiaturę u góry ekranu.';

  @override
  String get remoteInputDontAskAgain => 'Nie pytaj więcej dla tego urządzenia';

  @override
  String remoteInputBannerTarget(Object name, Object app) {
    return '$name pisze do: $app';
  }

  @override
  String get remoteInputOwnAppNote =>
      'Nic się nie wpisze, dopóki Chatt jest na wierzchu.';

  @override
  String get remoteInputAllowTitle => 'Pisanie bez pytania';

  @override
  String get remoteInputAllowBody =>
      'To urządzenie zaczyna pisać tutaj bez karty zgody. Pasek „Pisze” ze Stopem pokazuje się jak zawsze. Działa tylko przy potwierdzonej tożsamości i włączonym pisaniu w dodatku „Klawiatura z PC”.';

  @override
  String get remoteKeyboardOpen => 'Pisz na tamtym urządzeniu';

  @override
  String get remoteKeyboardNeedsVerified =>
      'Pisanie na tamtym urządzeniu wymaga potwierdzonej tożsamości';

  @override
  String remoteKeyboardTitle(Object name) {
    return 'Piszesz na: $name';
  }

  @override
  String remoteKeyboardWaiting(Object name) {
    return 'Czekam na zgodę na urządzeniu $name. Otwórz tam Chatt.';
  }

  @override
  String get remoteKeyboardWaitingHint =>
      'Telefon z Androidem pokaże powiadomienie, jeśli Chatt ma zgodę na powiadomienia.';

  @override
  String remoteKeyboardTarget(Object app) {
    return 'Pisze do: $app';
  }

  @override
  String remoteKeyboardTargetPassword(Object app) {
    return 'Pisze do: $app · pole hasła';
  }

  @override
  String get remoteKeyboardNoField =>
      'Brak pola do pisania. Stuknij pole na tamtym urządzeniu; na Androidzie z wybraną klawiaturą Chatt.';

  @override
  String get remoteKeyboardOwnApp =>
      'Na tamtym urządzeniu na wierzchu jest Chatt. Przejdź tam do aplikacji, w której chcesz pisać.';

  @override
  String get remoteKeyboardElevated =>
      'Okno z uprawnieniami administratora. Tam nic się nie wpisze.';

  @override
  String get remoteKeyboardLocked =>
      'Tamto urządzenie jest zablokowane albo ma wygaszony ekran.';

  @override
  String get remoteKeyboardPaused =>
      'Wstrzymane: na tamtym urządzeniu czeka pytanie. Pisanie wróci po odpowiedzi.';

  @override
  String get remoteKeyboardLocalCard =>
      'Odpowiedz na pytanie u góry, potem pisz dalej.';

  @override
  String remoteKeyboardEnded(Object name) {
    return 'Sesję zakończono na urządzeniu $name.';
  }

  @override
  String get remoteKeyboardLost => 'Połączenie zerwane.';

  @override
  String get remoteKeyboardReconnect => 'Połącz ponownie';

  @override
  String get remoteKeyboardModeLive => 'Znak po znaku';

  @override
  String get remoteKeyboardModeCompose => 'Całość naraz';

  @override
  String get remoteKeyboardLiveHint =>
      'Pisz tutaj. Każdy znak od razu trafia na tamto urządzenie.';

  @override
  String get remoteKeyboardKeysHint =>
      'Enter zatwierdza pole, Shift+Enter to nowa linia, Backspace i Delete kasują na tamtym urządzeniu.';

  @override
  String get remoteKeyboardComposeHint => 'Napisz tekst i wyślij go w całości.';

  @override
  String get remoteKeyboardSend => 'Wyślij';

  @override
  String get remoteKeyboardThenEnter => 'Potem Enter';

  @override
  String get remoteKeyboardPaste => 'Wklej ze schowka';

  @override
  String get remoteKeyboardClipboardEmpty => 'W schowku nie ma tekstu.';

  @override
  String get remoteKeyboardTooLong =>
      'Za dużo tekstu naraz. Wyślij go w częściach.';

  @override
  String remoteKeyboardRejected(Object name) {
    return 'Urządzenie $name odmówiło.';
  }

  @override
  String remoteKeyboardNotEnabled(Object name) {
    return 'Na urządzeniu $name pisanie jest wyłączone. Włącza się je w Ustawieniach, w dodatku „Klawiatura z PC”.';
  }

  @override
  String remoteKeyboardNoAnswer(Object name) {
    return 'Urządzenie $name nie odpowiedziało na prośbę.';
  }

  @override
  String remoteKeyboardBusy(Object name) {
    return 'Na urządzeniu $name pisze już ktoś inny.';
  }

  @override
  String remoteKeyboardOlderPeer(Object name) {
    return 'Urządzenie $name ma starszą wersję Chatt, bez zdalnej klawiatury.';
  }

  @override
  String remoteKeyboardUnreachable(Object name) {
    return 'Nie udało się połączyć z urządzeniem $name.';
  }

  @override
  String get remoteKeyboardNotVerified =>
      'Najpierw potwierdź tożsamość tego urządzenia.';

  @override
  String get remoteKeyboardAddonOff =>
      'Dodatek „Klawiatura z PC” jest wyłączony.';

  @override
  String get viaWifi => 'przez sieć';

  @override
  String get viaBluetooth => 'przez Bluetooth';

  @override
  String get protocolWifi => 'Sieć';

  @override
  String get protocolBluetooth => 'Bluetooth';

  @override
  String get searchWhere => 'Gdzie szukać';

  @override
  String get searchBluetoothHint =>
      'Szukanie przez radio trwa do półtorej minuty i na ten czas zwalnia otwarte rozmowy.';

  @override
  String get searchBluetoothOff =>
      'Bluetooth nie działa. Sprawdź radio i zgodę w Ustawieniach, w sekcji Dodatki.';

  @override
  String get searchingBluetooth => 'Szukam przez Bluetooth…';

  @override
  String get scanStartBluetooth => 'Szukaj przez Bluetooth';

  @override
  String get nearbyBeforeScanBluetooth =>
      'Wyszukaj przez Bluetooth, żeby zobaczyć, które urządzenia obok odpowiadają.';

  @override
  String get nearbyScanningBluetooth =>
      'Jeszcze nikt nie odpowiedział. Urządzenia pojawiają się tu po kolei, gdy tylko odpowiedzą.';

  @override
  String get scanNothingFoundBluetooth =>
      'Nie znaleziono urządzeń przez Bluetooth. Sprawdź, czy Chatt działa na drugim urządzeniu i ma włączony dodatek Bluetooth, i czy stoi najwyżej kilka metrów dalej. Możesz też dodać je po adresie radia.';

  @override
  String get searchBluetoothNoLocation =>
      'Android nie odda wyników szukania przy wyłączonych usługach lokalizacji. Do samego połączenia nie są potrzebne i Chatt o położenie nie pyta.';

  @override
  String get turnOnLocation => 'Włącz lokalizację';

  @override
  String get addByBtAddress => 'Dodaj po adresie radia';

  @override
  String get manualAddBtTitle => 'Dodaj po adresie Bluetooth';

  @override
  String get manualAddBtHelp =>
      'Adres drugiego urządzenia znajdziesz w jego ustawieniach Bluetooth. Komputer pokazuje swój także w Ustawieniach Chatta, w sekcji Dodatki.';

  @override
  String get btAddressLabel => 'Adres Bluetooth';

  @override
  String get btAddressHint => 'AA:BB:CC:DD:EE:FF';

  @override
  String noChattAtBtAddress(String address) {
    return 'Pod $address nie odpowiada Chatt';
  }

  @override
  String myBtAddress(String address) {
    return 'Adres tego radia: $address';
  }
}
