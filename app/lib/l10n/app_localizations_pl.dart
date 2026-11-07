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
  String get securityKeyUnknownTitle => 'Klucz jeszcze nieznany';

  @override
  String get securityKeyUnknownBody =>
      'Chatt nie rozmawiał jeszcze z tym urządzeniem. Pobierze jego klucz przy pierwszym kontakcie i niczego nie wyśle bez szyfrowania.';

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
  String get shieldKeyUnknown =>
      'Klucz jeszcze nieznany: przyjdzie przy pierwszym kontakcie';

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
      'Kasowanie dotyczy wpisów w rozmowach i historii pisania. Odebrane pliki zostają na dysku.';

  @override
  String get clearHistory => 'Wyczyść historię';

  @override
  String get clearHistoryTitle => 'Wyczyścić całą historię?';

  @override
  String get clearHistoryBody =>
      'Znikną wszystkie wiadomości, rozmowy i historia pisania. Urządzenia razem z potwierdzoną tożsamością zostają, odebrane pliki też zostają na dysku.';

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
      'Raz na dobę Chatt pyta GitHuba, czy wyszło nowsze wydanie. Pytanie wychodzi poza Twoją sieć, więc stoi wyłączone, dopóki go nie włączysz.';

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
  String get transportWifi => 'Sieć lokalna';

  @override
  String get transportInternet => 'Internet';

  @override
  String get transportBluetooth => 'Bluetooth';

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
  String get remoteInputReceive => 'Pozwól pisać na tym urządzeniu';

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
      'Android ostrzeże, że klawiatura może zbierać wpisywany tekst. Klawiatura Chatt niczego z Twoich pól nie wysyła: wpisuje to, co przyjdzie od urządzenia, któremu pozwolisz pisać.';

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
  String get remoteInputDontAskAgain => 'Nie pytaj więcej dla tego urządzenia';

  @override
  String remoteInputBannerTarget(Object name, Object app) {
    return '$name pisze do: $app';
  }

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
  String get viaInternet => 'przez internet';

  @override
  String get protocolWifi => 'Sieć';

  @override
  String get protocolBluetooth => 'Bluetooth';

  @override
  String get protocolInternet => 'Internet';

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
      'Nie znaleziono urządzeń przez Bluetooth. Sprawdź, czy Chatt działa na drugim urządzeniu i ma włączony dodatek Bluetooth, i czy stoi najwyżej kilka metrów dalej. Telefon z Androidem trzeba najpierw pokazać: na nim w „W pobliżu” przy wybranym Bluetoothcie stuknij „Pokaż ten telefon w pobliżu”. Możesz też dodać urządzenie po adresie radia.';

  @override
  String get searchBluetoothNoLocation =>
      'Android nie odda wyników szukania przy wyłączonych usługach lokalizacji. Do samego połączenia nie są potrzebne i Chatt o położenie nie pyta.';

  @override
  String get turnOnLocation => 'Włącz lokalizację';

  @override
  String get showThisPhone => 'Pokaż ten telefon w pobliżu';

  @override
  String get showThisPhoneHint =>
      'Android pokazuje telefon innym urządzeniom tylko na żądanie. Gdy drugie urządzenie ma znaleźć ten telefon, stuknij przycisk, potwierdź w okienku i uruchom szukanie tam.';

  @override
  String get thisPhoneVisible =>
      'Ten telefon jest teraz widoczny dla urządzeń w pobliżu, przez około dwie minuty. Uruchom szukanie na drugim urządzeniu.';

  @override
  String get showThisPhoneFailed =>
      'Android nie pokazał pytania o widoczność. Ten sam skutek daje otwarty ekran parowania w ustawieniach Bluetooth telefonu.';

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

  @override
  String get historyMenu => 'Więcej';

  @override
  String get historyShare => 'Udostępnij historię';

  @override
  String get historyRequest => 'Poproś o historię';

  @override
  String get historyShareTitle => 'Udostępnij historię rozmowy';

  @override
  String historyShareBody(Object name) {
    return '$name dostanie kopię waszej rozmowy, oznaczoną jako przywrócona. Najpierw zobaczy kartę z pytaniem.';
  }

  @override
  String get historyRangeAll => 'Całość';

  @override
  String historyRangeSince(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Od $dateString';
  }

  @override
  String get historyPickDate => 'Wybierz datę';

  @override
  String get historyWithFiles => 'Z plikami';

  @override
  String get historyWithoutFiles => 'Bez plików';

  @override
  String historyCountMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wiadomości',
      many: '$count wiadomości',
      few: '$count wiadomości',
      one: '$count wiadomość',
    );
    return '$_temp0';
  }

  @override
  String historyCountFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plików',
      many: '$count plików',
      few: '$count pliki',
      one: '$count plik',
      zero: 'bez plików',
    );
    return '$_temp0';
  }

  @override
  String historyRange(DateTime from, DateTime to) {
    final intl.DateFormat fromDateFormat = intl.DateFormat.yMMMd(localeName);
    final String fromString = fromDateFormat.format(from);
    final intl.DateFormat toDateFormat = intl.DateFormat.yMMMd(localeName);
    final String toString = toDateFormat.format(to);

    return 'od $fromString do $toString';
  }

  @override
  String historyMissingFiles(int count) {
    return 'Plików, których już tu nie ma, pójdzie bez treści: $count';
  }

  @override
  String get historyNothing => 'W tej rozmowie nie ma czego udostępnić.';

  @override
  String get historyShareAction => 'Udostępnij';

  @override
  String get historyShareDone => 'Historia udostępniona.';

  @override
  String historyShareRejected(Object name) {
    return '$name nie przyjmuje historii.';
  }

  @override
  String get historyNoAnswer =>
      'Nikt nie odpowiedział na karcie po drugiej stronie.';

  @override
  String get historyBusy =>
      'Trwa już inne przesyłanie historii. Spróbuj później.';

  @override
  String get historyOlderVersion =>
      'Tamto urządzenie ma starszą wersję Chatt, bez udostępniania historii.';

  @override
  String get historyUnreachable => 'Tamto urządzenie nie odpowiada.';

  @override
  String get historyCancelled =>
      'Udostępnianie przerwane. To, co doszło, zostaje po drugiej stronie.';

  @override
  String get historyFailed =>
      'Udostępnianie się nie udało. Spróbuj jeszcze raz: to, co doszło, się nie zdubluje.';

  @override
  String get historyRequestSent => 'Prośba wysłana, czekam na odpowiedź.';

  @override
  String historyRequestAccepted(Object name) {
    return '$name: zgoda. Historia zaraz zacznie spływać.';
  }

  @override
  String historyRequestRejected(Object name) {
    return '$name: odmowa.';
  }

  @override
  String historyRequestEmpty(Object name) {
    return '$name nie ma u siebie tej rozmowy.';
  }

  @override
  String historyOfferTitle(Object name) {
    return '$name chce przywrócić historię waszej rozmowy';
  }

  @override
  String get historyOfferDeleted =>
      'Wróci także to, co zostało tu wcześniej usunięte.';

  @override
  String get historyOfferMarked =>
      'Przywrócone wiadomości są oznaczone: to kopia rozmówcy i nikt jej nie podpisuje.';

  @override
  String get historyOfferUnverified =>
      'Tożsamość niepotwierdzona: historię może przysyłać ktoś, kto podaje się za tę osobę.';

  @override
  String historyOfferRetention(int days) {
    return 'Wiadomości starsze niż $days dni nie wejdą, bo tyle trzyma je ustawienie przechowywania.';
  }

  @override
  String historyRequestTitle(Object name) {
    return '$name prosi o historię waszej rozmowy';
  }

  @override
  String get historyRequestBody =>
      'Dostanie kopię tego, co jest tutaj w tej rozmowie, oznaczoną jako przywrócona.';

  @override
  String historySharing(Object name) {
    return 'Udostępnianie historii: $name';
  }

  @override
  String historyRestoring(Object name) {
    return 'Przywracanie historii od: $name';
  }

  @override
  String historyRestored(Object name) {
    return 'Historia od $name przywrócona';
  }

  @override
  String historyProgressMessages(int done, int total) {
    return 'Wiadomości: $done z $total';
  }

  @override
  String historyProgressFiles(int done, int total) {
    return 'Pliki: $done z $total';
  }

  @override
  String historySkipped(int count) {
    return 'Pominięte, bo już były albo są za stare: $count';
  }

  @override
  String get historyStop => 'Przerwij';

  @override
  String messageRestored(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Przywrócona $dateString z kopii rozmówcy';
  }

  @override
  String get fileUnavailable => 'Plik niedostępny';

  @override
  String get fileAwaiting => 'Czeka na przesłanie';

  @override
  String get dateToday => 'Dzisiaj';

  @override
  String get dateYesterday => 'Wczoraj';

  @override
  String dateSeparator(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMEEEEd(
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get historySource => 'Skąd';

  @override
  String get historySourceThis => 'Ta rozmowa';

  @override
  String historySourceOther(Object name, int count) {
    return 'Starsza rozmowa z: $name ($count)';
  }

  @override
  String get historySourceHint =>
      'Po reinstalacji albo na nowym telefonie to samo urządzenie przychodzi pod nowym wpisem. Starszą rozmowę z dawnym wpisem możesz oddać tutaj.';

  @override
  String get historySourceNeedsShield =>
      'Starszą rozmowę z innym wpisem można oddać tylko urządzeniu z zieloną tarczą. Najpierw potwierdź jego tożsamość.';

  @override
  String get historyMergeLocally => 'Połącz u mnie tamtą rozmowę z tą';

  @override
  String get historyNeedsVerified =>
      'Najpierw potwierdź tożsamość tego urządzenia (zielona tarcza).';

  @override
  String get historyMerged => 'Rozmowy połączone.';

  @override
  String get profileSection => 'Profil';

  @override
  String get styleLabel => 'Styl';

  @override
  String get styleCisza => 'Cisza';

  @override
  String get stylePrecyzja => 'Precyzja';

  @override
  String get styleCieplo => 'Ciepło';

  @override
  String get themeLabel => 'Motyw';

  @override
  String get addonBluetoothShort => 'Rozmowy bez wspólnej sieci Wi-Fi';

  @override
  String get addonInternetShort => 'Rozmowy między różnymi sieciami';

  @override
  String get addonInternetBody =>
      'Połączenie z potwierdzonym urządzeniem w innej sieci, bez serwera pośredniczącego. Drogę pomagają znaleźć publiczne serwery STUN i sieć DHT BitTorrenta; widzą one twój adres IP i moment połączenia. Treści nie widzi żaden z nich. Nie przechodzi przez każdą sieć: zatrzymuje je symetryczny NAT (pokaże go „Sprawdź osiągalność”) albo sieć, która blokuje UDP. Domyślnie wyłączone.';

  @override
  String get internetAddonExperimental =>
      'Eksperymentalne. Działa bezpośrednio między urządzeniami, przebijając dziurę w NAT; udaje się około siedmiu połączeń na dziesięć.';

  @override
  String get internetBatteryWarning =>
      'Żeby być osiągalnym, to urządzenie nasłuchuje w tle, co minutę sprawdza, czy dzwoni do niego potwierdzone urządzenie, i co dziesięć minut odświeża swój adres. Zużywa to więcej baterii niż samo Wi-Fi.';

  @override
  String internetPublicAddressLabel(String address) {
    return 'To urządzenie widać pod: $address';
  }

  @override
  String get internetPublicAddressUnknown =>
      'Adres publiczny jeszcze nieznany.';

  @override
  String get internetCheckNat => 'Sprawdź osiągalność';

  @override
  String get internetNatOpen =>
      'NAT niezależny od celu: przebicie dziury powinno działać.';

  @override
  String get internetNatSymmetric =>
      'NAT symetryczny: przebicie dziury zwykle tu zawodzi.';

  @override
  String get internetNatNone => 'Brak NAT: urządzenie jest osiągalne wprost.';

  @override
  String get internetNatUnknown => 'Nie udało się połączyć z serwerami STUN.';

  @override
  String get addonKeyboardShort => 'Pisanie z klawiatury komputera';

  @override
  String historyClearedWithTyping(int messages, int sessions) {
    return 'Usunięto wiadomości: $messages, sesje pisania: $sessions';
  }

  @override
  String get typingHistorySwitch => 'Zapisuj historię pisania';

  @override
  String get typingHistoryHelp =>
      'Zapisuje na tym urządzeniu sesje w obu kierunkach: pisanie stąd i pisanie tutaj. Drugie urządzenie prowadzi własną historię według swojego przełącznika. Tekst z pól haseł i pól nieznanego rodzaju zostaje ukryty: zapisuje się sama liczba znaków. Historia leży zaszyfrowana.';

  @override
  String get typingHistory => 'Historia pisania';

  @override
  String typingHistoryEntryHelp(int count) {
    return 'Sesje zdalnej klawiatury zapisane na tym urządzeniu: $count. Wyczyścić je można na ekranie historii.';
  }

  @override
  String get typingHistoryOff =>
      'Zapisywanie historii pisania jest wyłączone. Włącza się je w Ustawieniach, w dodatku „Klawiatura z PC”.';

  @override
  String get typingHistoryEmptyTitle => 'Brak historii pisania';

  @override
  String get typingHistoryEmptyBody =>
      'Tutaj pojawią się sesje zdalnej klawiatury w obu kierunkach: pisanie stąd na innych urządzeniach i pisanie innych urządzeń tutaj.';

  @override
  String get typingHistoryClear => 'Wyczyść historię pisania';

  @override
  String get typingHistoryClearTitle => 'Wyczyścić historię pisania?';

  @override
  String get typingHistoryClearBody =>
      'Znikną wszystkie zapisane sesje pisania. Rozmowy i dziennik aplikacji zostają.';

  @override
  String typingHistoryCleared(int count) {
    return 'Usunięto sesje pisania: $count';
  }

  @override
  String typingHistoryOutgoing(Object name) {
    return 'Pisanie stąd na: $name';
  }

  @override
  String typingHistoryIncoming(Object name) {
    return 'Pisanie tutaj z: $name';
  }

  @override
  String typingHistorySessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesji',
      many: '$count sesji',
      few: '$count sesje',
      one: '$count sesja',
    );
    return '$_temp0';
  }

  @override
  String typingHistoryChars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count znaku',
      many: '$count znaków',
      few: '$count znaki',
      one: '$count znak',
    );
    return '$_temp0';
  }

  @override
  String get typingHistoryStarted => 'Początek';

  @override
  String get typingHistoryEnded => 'Koniec';

  @override
  String get typingHistoryDuration => 'Czas trwania';

  @override
  String get typingHistoryCharsLabel => 'Znaki';

  @override
  String get typingHistoryApps => 'Aplikacje';

  @override
  String get typingHistoryRequest => 'Prośba';

  @override
  String get typingHistoryEndReason => 'Powód końca';

  @override
  String get typingHistorySessionId => 'Identyfikator sesji';

  @override
  String get typingHistoryNotEnded => 'Koniec jeszcze niezapisany';

  @override
  String get typingHistoryText => 'Odtworzony tekst';

  @override
  String get typingHistoryTextNote =>
      'Tekst odtworzony z klawiszy. Ukryte pola widać jako kropki.';

  @override
  String get typingHistoryNoText => 'Odtworzony tekst jest pusty.';

  @override
  String get typingHistoryTimeline => 'Przebieg';

  @override
  String get typingHistoryNoEntries => 'W tej sesji nic nie pisano.';

  @override
  String get typingHistoryHidden => 'Ukryty tekst';

  @override
  String get typingFieldPassword => 'pole hasła';

  @override
  String get typingFieldUnknown => 'pole nieznanego rodzaju';

  @override
  String get typingKeyEnter => 'Enter';

  @override
  String get typingKeyBackspace => 'Backspace';

  @override
  String get typingKeyDelete => 'Delete';

  @override
  String get typingResultAccepted => 'Zgoda z karty';

  @override
  String get typingResultAcceptedAlways => 'Zgoda z karty, „Nie pytaj więcej”';

  @override
  String get typingResultAutomatic => 'Bez karty: zapamiętana zgoda';

  @override
  String get typingResultRejected => 'Odmowa';

  @override
  String get typingResultNoAnswer => 'Brak odpowiedzi na karcie';

  @override
  String get typingResultBusy => 'Zajęte przez inną sesję';

  @override
  String get typingResultNotEnabled =>
      'Pisanie wyłączone na urządzeniu odbiorcy';

  @override
  String get typingResultCancelled => 'Prośba wycofana';

  @override
  String get typingResultUnreachable => 'Brak połączenia z urządzeniem';

  @override
  String get typingResultOlderPeer => 'Starsza wersja Chatt po drugiej stronie';

  @override
  String get typingEndStoppedHere => 'Zakończona na tym urządzeniu';

  @override
  String get typingEndStoppedByPeer => 'Zakończona przez drugą stronę';

  @override
  String get typingEndExpired => 'Zgoda wygasła';

  @override
  String get typingEndReceiveOff => 'Wyłączone pisanie na tym urządzeniu';

  @override
  String get typingEndAddonOff => 'Wyłączony dodatek klawiatury';

  @override
  String get typingEndReplaced => 'Zastąpiona nową sesją';

  @override
  String get typingEndPeerRemoved => 'Urządzenie usunięte z listy';

  @override
  String get typingEndNotAllowed => 'Zgoda cofnięta w trakcie sesji';

  @override
  String get typingEndLinkLost => 'Połączenie zerwane';

  @override
  String get typingEndAppClosed => 'Aplikacja zamknięta';

  @override
  String get typingStatusTyped => 'Wpisane';

  @override
  String get typingStatusNotTyped => 'Wpisane częściowo albo wcale';

  @override
  String get typingStatusPaused => 'Wstrzymane: czekała karta z pytaniem';

  @override
  String get typingStatusRefused => 'Odrzucone: zgoda już się skończyła';

  @override
  String get typingStatusUnconfirmed => 'Bez potwierdzenia odbioru';

  @override
  String get typingStatusUnsent => 'Niewysłane';

  @override
  String get dataSection => 'Dane i diagnostyka';

  @override
  String get exportData => 'Eksportuj dane';

  @override
  String get exportDataHelp =>
      'Jeden plik ZIP z wybranymi danymi: rozmowy, urządzenia, ustawienia, historia pisania, dziennik aplikacji i odebrane pliki. Do archiwum albo do analizy w innym programie.';

  @override
  String get exportDataConversations => 'Rozmowy, urządzenia i ustawienia';

  @override
  String exportDataCountConversations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rozmowy',
      many: '$count rozmów',
      few: '$count rozmowy',
      one: '$count rozmowa',
    );
    return '$_temp0';
  }

  @override
  String exportDataCountDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count urządzenia',
      many: '$count urządzeń',
      few: '$count urządzenia',
      one: '$count urządzenie',
    );
    return '$_temp0';
  }

  @override
  String get exportDataFiles => 'Odebrane pliki';

  @override
  String exportDataWarning(String parts) {
    String _temp0 = intl.Intl.selectLogic(parts, {
      'both': 'Plik eksportu nie jest zaszyfrowany i zawiera treść wiadomości oraz wpisywany tekst.',
      'messages':
          'Plik eksportu nie jest zaszyfrowany i zawiera treść wiadomości.',
      'typing':
          'Plik eksportu nie jest zaszyfrowany i zawiera wpisywany tekst.',
      'other': 'Plik eksportu nie jest zaszyfrowany.',
    });
    return '$_temp0 Trzymaj go w bezpiecznym miejscu. Klucze tego urządzenia zostają poza eksportem.';
  }

  @override
  String get exportDataReplaceTitle => 'Zastąpić plik?';

  @override
  String exportDataReplaceBody(Object name) {
    return 'Plik $name już istnieje. Eksport go zastąpi.';
  }

  @override
  String get exportDataReplace => 'Zastąp';

  @override
  String get exportDataAction => 'Eksportuj';

  @override
  String get exportDataBusy => 'Eksportuję…';

  @override
  String get exportDataEstimateFailed =>
      'Nie udało się policzyć danych do eksportu.';

  @override
  String exportDataSaved(Object where) {
    return 'Eksport zapisany w $where';
  }

  @override
  String get exportDataDone => 'Eksport gotowy.';

  @override
  String get exportDataFailed => 'Nie udało się wyeksportować danych.';

  @override
  String get exportDataUnsupported =>
      'Ten system nie ma gdzie zapisać pliku eksportu.';

  @override
  String exportDataSkipped(int count) {
    return 'Pominięte pliki: $count';
  }

  @override
  String get appLog => 'Dziennik aplikacji';

  @override
  String get appLogHelp =>
      'Zdarzenia sieci, parowania i plików oraz błędy z ostatnich 30 dni, do diagnostyki. Bez treści wiadomości, wpisywanego tekstu i kluczy.';

  @override
  String appLogEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wpisu',
      many: '$count wpisów',
      few: '$count wpisy',
      one: '$count wpis',
    );
    return '$_temp0';
  }

  @override
  String get appLogFilterAll => 'Wszystko';

  @override
  String get appLogFilterProblems => 'Ostrzeżenia i błędy';

  @override
  String get appLogEmpty => 'Dziennik jest pusty.';

  @override
  String get appLogEmptyProblems => 'Brak ostrzeżeń i błędów.';

  @override
  String appLogLimit(int count) {
    return 'Widać najnowsze wpisy: $count. Pełny dziennik jest w eksporcie.';
  }

  @override
  String get appLogCopy => 'Kopiuj widoczne wpisy';

  @override
  String get appLogExport => 'Eksportuj dziennik';

  @override
  String get appLogClear => 'Wyczyść dziennik';

  @override
  String get appLogClearTitle => 'Wyczyścić dziennik aplikacji?';

  @override
  String get appLogClearBody =>
      'Znikną wszystkie wpisy dziennika. Rozmowy i historia pisania zostają.';

  @override
  String appLogCleared(int count) {
    return 'Usunięto wpisy dziennika: $count';
  }

  @override
  String get appLogDetails => 'Szczegóły';

  @override
  String get appLogLevelInfo => 'Informacja';

  @override
  String get appLogLevelWarning => 'Ostrzeżenie';

  @override
  String get appLogLevelError => 'Błąd';

  @override
  String get shareSendToTitle => 'Wyślij do';

  @override
  String shareFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pliku',
      many: '$count plików',
      few: '$count pliki',
      one: '$count plik',
    );
    return '$_temp0';
  }

  @override
  String get shareNoConversations =>
      'Nie masz jeszcze żadnej rozmowy. Znajdź urządzenie przyciskiem „W pobliżu”, żeby mu to wysłać.';

  @override
  String sharePreparing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Przygotowuję $count pliku…',
      many: 'Przygotowuję $count plików…',
      few: 'Przygotowuję $count pliki…',
      one: 'Przygotowuję plik…',
    );
    return '$_temp0';
  }

  @override
  String get shareDontSend => 'Nie wysyłaj';

  @override
  String get shareNothing =>
      'Chatt nie dostał nic do wysłania: ani tekstu, ani pliku, który umie odczytać.';

  @override
  String shareSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Pominięte $count pliku: Chatt nie przyjmuje plików podanych zwykłą ścieżką.',
      many:
          'Pominiętych $count plików: Chatt nie przyjmuje plików podanych zwykłą ścieżką.',
      few:
          'Pominięte $count pliki: Chatt nie przyjmuje plików podanych zwykłą ścieżką.',
      one:
          'Pominięty $count plik: Chatt nie przyjmuje plików podanych zwykłą ścieżką.',
    );
    return '$_temp0';
  }

  @override
  String shareFilesMissing(int missing, int total) {
    return 'Nie udało się wczytać $missing z $total udostępnionych plików.';
  }

  @override
  String get conversationGone => 'Tej rozmowy już nie ma.';
}
