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
  String get noKnownDevices => 'Nie znasz jeszcze żadnych urządzeń.';

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
  String get peerOnline => 'dostępny';

  @override
  String get peerOffline => 'niedostępny';

  @override
  String get pairTooltipPaired => 'Urządzenie sparowane kodem';

  @override
  String get pairTooltip => 'Sparuj przez porównanie kodu';

  @override
  String get sendFileTooltip => 'Wyślij plik';

  @override
  String get sendTooltip => 'Wyślij';

  @override
  String get messageHint => 'Napisz wiadomość…';

  @override
  String get notDeliveredRetry => 'Nie dostarczono — ponów';

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
  String get fileGone => 'Tego pliku już nie ma na dysku.';

  @override
  String get fileOpenFailed => 'Nie udało się otworzyć pliku.';

  @override
  String receivingFile(Object name) {
    return 'Odbieram: $name';
  }

  @override
  String get pairStartFailed =>
      'Nie udało się zacząć parowania: urządzenie nie odpowiada.';

  @override
  String get pairAgainWarning =>
      'To urządzenie jest już sparowane. Zgoda zastąpi klucz, którym się z nim porozumiewasz. Prośbę mógł przysłać ktoś inny pod tą samą nazwą, więc rób to tylko, jeśli sam o to poprosiłeś.';

  @override
  String pairRequest(Object name) {
    return '$name chce się sparować';
  }

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
  String fileOfferTitle(Object name) {
    return '$name chce wysłać plik';
  }

  @override
  String fileOfferResume(Object size, Object have) {
    return '$size — wznowienie, masz już $have';
  }

  @override
  String get unpairedWarning =>
      'Urządzenie niesparowane — nazwę można sobie ustawić dowolną';

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
  String get thisDevice => 'To urządzenie';

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
  String get backgroundServiceTitle => 'Chatt nasłuchuje';

  @override
  String get backgroundServiceBody =>
      'Odbiera wiadomości i pliki z tej sieci Wi-Fi';
}
