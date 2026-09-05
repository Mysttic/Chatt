import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pl'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In pl, this message translates to:
  /// **'Chatt'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In pl, this message translates to:
  /// **'Anuluj'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In pl, this message translates to:
  /// **'Usuń'**
  String get delete;

  /// No description provided for @confirm.
  ///
  /// In pl, this message translates to:
  /// **'Potwierdź'**
  String get confirm;

  /// No description provided for @close.
  ///
  /// In pl, this message translates to:
  /// **'Zamknij'**
  String get close;

  /// No description provided for @copy.
  ///
  /// In pl, this message translates to:
  /// **'Kopiuj'**
  String get copy;

  /// No description provided for @errorWithDetails.
  ///
  /// In pl, this message translates to:
  /// **'Błąd: {details}'**
  String errorWithDetails(Object details);

  /// No description provided for @settingsTitle.
  ///
  /// In pl, this message translates to:
  /// **'Ustawienia'**
  String get settingsTitle;

  /// No description provided for @nearbyButton.
  ///
  /// In pl, this message translates to:
  /// **'W pobliżu'**
  String get nearbyButton;

  /// No description provided for @noConversationsTitle.
  ///
  /// In pl, this message translates to:
  /// **'Brak rozmów'**
  String get noConversationsTitle;

  /// No description provided for @noConversationsBody.
  ///
  /// In pl, this message translates to:
  /// **'Znajdź urządzenia w tej samej sieci Wi-Fi przyciskiem „W pobliżu” i napisz pierwszą wiadomość.'**
  String get noConversationsBody;

  /// No description provided for @deleteConversationTitle.
  ///
  /// In pl, this message translates to:
  /// **'Usunąć rozmowę z {name}?'**
  String deleteConversationTitle(Object name);

  /// No description provided for @deleteConversationBody.
  ///
  /// In pl, this message translates to:
  /// **'Znikną wiadomości i samo urządzenie z listy znanych. Odebrane pliki zostają na dysku.'**
  String get deleteConversationBody;

  /// No description provided for @conversationDeleted.
  ///
  /// In pl, this message translates to:
  /// **'Usunięto rozmowę z {name}'**
  String conversationDeleted(Object name);

  /// No description provided for @pickConversation.
  ///
  /// In pl, this message translates to:
  /// **'Wybierz rozmowę z listy'**
  String get pickConversation;

  /// No description provided for @nearbyTitle.
  ///
  /// In pl, this message translates to:
  /// **'Urządzenia w pobliżu'**
  String get nearbyTitle;

  /// No description provided for @addByAddress.
  ///
  /// In pl, this message translates to:
  /// **'Dodaj po adresie IP'**
  String get addByAddress;

  /// No description provided for @scanRunning.
  ///
  /// In pl, this message translates to:
  /// **'Szukam… (znaleziono {count})'**
  String scanRunning(int count);

  /// No description provided for @scanStart.
  ///
  /// In pl, this message translates to:
  /// **'Szukaj urządzeń w sieci'**
  String get scanStart;

  /// No description provided for @scanNothingFound.
  ///
  /// In pl, this message translates to:
  /// **'Nie znaleziono urządzeń. Sprawdź, czy Chatt działa na drugim urządzeniu w tej samej sieci, albo dodaj je ręcznie po adresie.'**
  String get scanNothingFound;

  /// No description provided for @scanFound.
  ///
  /// In pl, this message translates to:
  /// **'Znaleziono: {count}'**
  String scanFound(int count);

  /// No description provided for @nearbyBeforeScan.
  ///
  /// In pl, this message translates to:
  /// **'Wyszukaj urządzenia, żeby zobaczyć, które odpowiadają w tej chwili.'**
  String get nearbyBeforeScan;

  /// No description provided for @longPressToDelete.
  ///
  /// In pl, this message translates to:
  /// **'Przytrzymaj urządzenie, żeby je usunąć'**
  String get longPressToDelete;

  /// No description provided for @lastSeen.
  ///
  /// In pl, this message translates to:
  /// **'widziano {when}'**
  String lastSeen(Object when);

  /// No description provided for @deleteDeviceTitle.
  ///
  /// In pl, this message translates to:
  /// **'Usunąć {name}?'**
  String deleteDeviceTitle(Object name);

  /// No description provided for @deleteDeviceBody.
  ///
  /// In pl, this message translates to:
  /// **'Urządzenie zniknie z listy razem z rozmową i jej wiadomościami. Odebrane pliki zostają na dysku.'**
  String get deleteDeviceBody;

  /// No description provided for @deviceDeleted.
  ///
  /// In pl, this message translates to:
  /// **'Usunięto {name}'**
  String deviceDeleted(Object name);

  /// No description provided for @manualAddTitle.
  ///
  /// In pl, this message translates to:
  /// **'Dodaj urządzenie po adresie'**
  String get manualAddTitle;

  /// No description provided for @ipLabel.
  ///
  /// In pl, this message translates to:
  /// **'Adres IP'**
  String get ipLabel;

  /// No description provided for @ipHint.
  ///
  /// In pl, this message translates to:
  /// **'np. 192.168.1.20'**
  String get ipHint;

  /// No description provided for @portLabel.
  ///
  /// In pl, this message translates to:
  /// **'Port'**
  String get portLabel;

  /// No description provided for @connect.
  ///
  /// In pl, this message translates to:
  /// **'Połącz'**
  String get connect;

  /// No description provided for @noChattAtAddress.
  ///
  /// In pl, this message translates to:
  /// **'Pod {host}:{port} nie odpowiada żaden Chatt.'**
  String noChattAtAddress(Object host, int port);

  /// No description provided for @copied.
  ///
  /// In pl, this message translates to:
  /// **'Skopiowano'**
  String get copied;

  /// No description provided for @securityNoEncryptionTitle.
  ///
  /// In pl, this message translates to:
  /// **'Bez szyfrowania'**
  String get securityNoEncryptionTitle;

  /// No description provided for @securityNoEncryptionBody.
  ///
  /// In pl, this message translates to:
  /// **'Po drugiej stronie działa starsza wersja Chatta, która nie umie szyfrować. Dopóki jej nie zaktualizujesz, ta rozmowa nie ruszy.'**
  String get securityNoEncryptionBody;

  /// No description provided for @securityEncryptedTitle.
  ///
  /// In pl, this message translates to:
  /// **'Szyfrowane, tożsamość niepotwierdzona'**
  String get securityEncryptedTitle;

  /// No description provided for @securityEncryptedBody.
  ///
  /// In pl, this message translates to:
  /// **'Nikt w sieci nie przeczyta tej rozmowy. Nie masz jeszcze potwierdzenia, że po drugiej stronie jest ta osoba, o której myślisz: nazwę urządzenia każdy może sobie ustawić dowolnie.'**
  String get securityEncryptedBody;

  /// No description provided for @securityVerifiedTitle.
  ///
  /// In pl, this message translates to:
  /// **'Szyfrowane i potwierdzone'**
  String get securityVerifiedTitle;

  /// No description provided for @securityVerifiedBody.
  ///
  /// In pl, this message translates to:
  /// **'Porównaliście kod, więc wiadomo, do kogo należy klucz po drugiej stronie.'**
  String get securityVerifiedBody;

  /// No description provided for @fingerprintMine.
  ///
  /// In pl, this message translates to:
  /// **'Odcisk tego urządzenia'**
  String get fingerprintMine;

  /// No description provided for @fingerprintOf.
  ///
  /// In pl, this message translates to:
  /// **'Odcisk urządzenia {name}'**
  String fingerprintOf(Object name);

  /// No description provided for @fingerprintHelp.
  ///
  /// In pl, this message translates to:
  /// **'Odcisk wynika z klucza urządzenia i nigdy się nie zmienia. Odczytaj go na głos i sprawdź, czy druga strona widzi to samo. Jeśli tak, nikt nie siedzi w środku rozmowy.'**
  String get fingerprintHelp;

  /// No description provided for @peerOnline.
  ///
  /// In pl, this message translates to:
  /// **'dostępny'**
  String get peerOnline;

  /// No description provided for @peerOffline.
  ///
  /// In pl, this message translates to:
  /// **'niedostępny'**
  String get peerOffline;

  /// No description provided for @shieldNoEncryption.
  ///
  /// In pl, this message translates to:
  /// **'Bez szyfrowania: druga strona ma starszą wersję'**
  String get shieldNoEncryption;

  /// No description provided for @shieldEncrypted.
  ///
  /// In pl, this message translates to:
  /// **'Szyfrowane, ale tożsamość niepotwierdzona. Kliknij, żeby porównać kod'**
  String get shieldEncrypted;

  /// No description provided for @shieldVerified.
  ///
  /// In pl, this message translates to:
  /// **'Szyfrowane i potwierdzone'**
  String get shieldVerified;

  /// No description provided for @pairTooltip.
  ///
  /// In pl, this message translates to:
  /// **'Sparuj przez porównanie kodu'**
  String get pairTooltip;

  /// No description provided for @sendFileTooltip.
  ///
  /// In pl, this message translates to:
  /// **'Wyślij plik'**
  String get sendFileTooltip;

  /// No description provided for @sendTooltip.
  ///
  /// In pl, this message translates to:
  /// **'Wyślij'**
  String get sendTooltip;

  /// No description provided for @messageHint.
  ///
  /// In pl, this message translates to:
  /// **'Napisz wiadomość…'**
  String get messageHint;

  /// No description provided for @notDeliveredRetry.
  ///
  /// In pl, this message translates to:
  /// **'Nie dostarczono, ponów'**
  String get notDeliveredRetry;

  /// No description provided for @fileFallbackName.
  ///
  /// In pl, this message translates to:
  /// **'plik'**
  String get fileFallbackName;

  /// No description provided for @openFile.
  ///
  /// In pl, this message translates to:
  /// **'Otwórz'**
  String get openFile;

  /// No description provided for @showFolder.
  ///
  /// In pl, this message translates to:
  /// **'Pokaż folder'**
  String get showFolder;

  /// No description provided for @shareFile.
  ///
  /// In pl, this message translates to:
  /// **'Udostępnij'**
  String get shareFile;

  /// No description provided for @copyPath.
  ///
  /// In pl, this message translates to:
  /// **'Kopiuj ścieżkę'**
  String get copyPath;

  /// No description provided for @saveFile.
  ///
  /// In pl, this message translates to:
  /// **'Zapisz na urządzeniu'**
  String get saveFile;

  /// No description provided for @saveFileHint.
  ///
  /// In pl, this message translates to:
  /// **'Kopia w Zdjęciach albo Pobranych, poza katalogiem aplikacji'**
  String get saveFileHint;

  /// No description provided for @savedTo.
  ///
  /// In pl, this message translates to:
  /// **'Zapisano w {where}'**
  String savedTo(Object where);

  /// No description provided for @saveFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się zapisać pliku.'**
  String get saveFailed;

  /// No description provided for @saveUnsupported.
  ///
  /// In pl, this message translates to:
  /// **'Ten system nie ma gdzie zapisać pliku bez dodatkowych uprawnień. Użyj „Udostępnij”.'**
  String get saveUnsupported;

  /// No description provided for @fileGone.
  ///
  /// In pl, this message translates to:
  /// **'Tego pliku już nie ma na dysku.'**
  String get fileGone;

  /// No description provided for @fileOpenFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się otworzyć pliku.'**
  String get fileOpenFailed;

  /// No description provided for @receivingFile.
  ///
  /// In pl, this message translates to:
  /// **'Odbieram: {name}'**
  String receivingFile(Object name);

  /// No description provided for @pairStartFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się zacząć parowania: urządzenie nie odpowiada.'**
  String get pairStartFailed;

  /// No description provided for @pairAgainWarning.
  ///
  /// In pl, this message translates to:
  /// **'Tożsamość tego urządzenia jest już potwierdzona. Prośbę mógł przysłać ktoś inny pod tą samą nazwą, więc potwierdzaj tylko wtedy, gdy sam o to poprosiłeś.'**
  String get pairAgainWarning;

  /// No description provided for @pairRequest.
  ///
  /// In pl, this message translates to:
  /// **'{name} chce się sparować'**
  String pairRequest(Object name);

  /// No description provided for @qrShowTitle.
  ///
  /// In pl, this message translates to:
  /// **'Pokaż kod QR'**
  String get qrShowTitle;

  /// No description provided for @qrShowBody.
  ///
  /// In pl, this message translates to:
  /// **'Zeskanuj ten kod drugim urządzeniem. Kod nie zawiera nic tajnego. Liczy się to, że drugie urządzenie widziało go na tym ekranie.'**
  String get qrShowBody;

  /// No description provided for @qrOtherAddress.
  ///
  /// In pl, this message translates to:
  /// **'Inny adres'**
  String get qrOtherAddress;

  /// No description provided for @qrScanTitle.
  ///
  /// In pl, this message translates to:
  /// **'Zeskanuj kod QR'**
  String get qrScanTitle;

  /// No description provided for @qrScanHint.
  ///
  /// In pl, this message translates to:
  /// **'Wyceluj w kod pokazany na drugim urządzeniu'**
  String get qrScanHint;

  /// No description provided for @qrScanFailed.
  ///
  /// In pl, this message translates to:
  /// **'Pod adresem z kodu nie ma urządzenia z tym kluczem. Kod może być nieaktualny, pokaż go jeszcze raz.'**
  String get qrScanFailed;

  /// No description provided for @pairScannedTitle.
  ///
  /// In pl, this message translates to:
  /// **'{name} zeskanował kod z tego ekranu'**
  String pairScannedTitle(Object name);

  /// No description provided for @pairScannedBody.
  ///
  /// In pl, this message translates to:
  /// **'Potwierdź tylko wtedy, gdy to Ty właśnie skanowałeś. Kod z ekranu mógł zobaczyć ktoś jeszcze, a aplikacja nie ma jak tego rozstrzygnąć.'**
  String get pairScannedBody;

  /// No description provided for @pairScannedConfirm.
  ///
  /// In pl, this message translates to:
  /// **'To ja skanowałem'**
  String get pairScannedConfirm;

  /// No description provided for @pairCompareHint.
  ///
  /// In pl, this message translates to:
  /// **'Sprawdź, czy drugie urządzenie pokazuje ten sam kod:'**
  String get pairCompareHint;

  /// No description provided for @pairCodesMatch.
  ///
  /// In pl, this message translates to:
  /// **'Zgadza się'**
  String get pairCodesMatch;

  /// No description provided for @pairCodesDiffer.
  ///
  /// In pl, this message translates to:
  /// **'Nie zgadza się'**
  String get pairCodesDiffer;

  /// No description provided for @pairChecking.
  ///
  /// In pl, this message translates to:
  /// **'Czekam…'**
  String get pairChecking;

  /// No description provided for @pairedWith.
  ///
  /// In pl, this message translates to:
  /// **'Sparowano z {name}'**
  String pairedWith(Object name);

  /// No description provided for @pairRejected.
  ///
  /// In pl, this message translates to:
  /// **'Drugie urządzenie przerwało parowanie'**
  String get pairRejected;

  /// No description provided for @pairCodeExpired.
  ///
  /// In pl, this message translates to:
  /// **'Parowanie straciło ważność, zacznij od nowa'**
  String get pairCodeExpired;

  /// No description provided for @pairPeerUnreachable.
  ///
  /// In pl, this message translates to:
  /// **'Drugie urządzenie nie odpowiada'**
  String get pairPeerUnreachable;

  /// No description provided for @dropFilesHint.
  ///
  /// In pl, this message translates to:
  /// **'Upuść pliki, żeby je wysłać'**
  String get dropFilesHint;

  /// No description provided for @copyText.
  ///
  /// In pl, this message translates to:
  /// **'Kopiuj tekst'**
  String get copyText;

  /// No description provided for @deleteMessage.
  ///
  /// In pl, this message translates to:
  /// **'Usuń wiadomość'**
  String get deleteMessage;

  /// No description provided for @deleteMessageHint.
  ///
  /// In pl, this message translates to:
  /// **'Zniknie tylko z tego urządzenia'**
  String get deleteMessageHint;

  /// No description provided for @messageDeleted.
  ///
  /// In pl, this message translates to:
  /// **'Wiadomość usunięta z tego urządzenia'**
  String get messageDeleted;

  /// No description provided for @searchTooltip.
  ///
  /// In pl, this message translates to:
  /// **'Szukaj w rozmowie'**
  String get searchTooltip;

  /// No description provided for @searchHint.
  ///
  /// In pl, this message translates to:
  /// **'Szukaj w rozmowie…'**
  String get searchHint;

  /// No description provided for @searchConversationsTooltip.
  ///
  /// In pl, this message translates to:
  /// **'Szukaj rozmowy'**
  String get searchConversationsTooltip;

  /// No description provided for @searchConversationsHint.
  ///
  /// In pl, this message translates to:
  /// **'Szukaj rozmowy…'**
  String get searchConversationsHint;

  /// No description provided for @searchNothingFound.
  ///
  /// In pl, this message translates to:
  /// **'Nic nie pasuje do „{query}”'**
  String searchNothingFound(Object query);

  /// No description provided for @fileOfferTitle.
  ///
  /// In pl, this message translates to:
  /// **'{name} chce wysłać plik'**
  String fileOfferTitle(Object name);

  /// No description provided for @fileOfferResume.
  ///
  /// In pl, this message translates to:
  /// **'{size}, wznowienie: masz już {have}'**
  String fileOfferResume(Object size, Object have);

  /// No description provided for @unpairedWarning.
  ///
  /// In pl, this message translates to:
  /// **'Tożsamość niepotwierdzona: nazwę można sobie ustawić dowolną'**
  String get unpairedWarning;

  /// No description provided for @moreFilesWaiting.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{Czeka jeszcze {count} plik} few{Czekają jeszcze {count} pliki} other{Czeka jeszcze {count} plików}}'**
  String moreFilesWaiting(int count);

  /// No description provided for @reject.
  ///
  /// In pl, this message translates to:
  /// **'Odrzuć'**
  String get reject;

  /// No description provided for @accept.
  ///
  /// In pl, this message translates to:
  /// **'Akceptuj'**
  String get accept;

  /// No description provided for @nicknameLabel.
  ///
  /// In pl, this message translates to:
  /// **'Twój nick'**
  String get nicknameLabel;

  /// No description provided for @nicknameRequired.
  ///
  /// In pl, this message translates to:
  /// **'Podaj nick'**
  String get nicknameRequired;

  /// No description provided for @welcomeLabel.
  ///
  /// In pl, this message translates to:
  /// **'Wiadomość powitalna'**
  String get welcomeLabel;

  /// No description provided for @welcomeHelper.
  ///
  /// In pl, this message translates to:
  /// **'Widoczna dla innych przy wyszukiwaniu'**
  String get welcomeHelper;

  /// No description provided for @portFieldLabel.
  ///
  /// In pl, this message translates to:
  /// **'Preferowany port nasłuchu'**
  String get portFieldLabel;

  /// No description provided for @portRange.
  ///
  /// In pl, this message translates to:
  /// **'Port z zakresu 1024 do 65535'**
  String get portRange;

  /// No description provided for @save.
  ///
  /// In pl, this message translates to:
  /// **'Zapisz'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In pl, this message translates to:
  /// **'Zapisano.'**
  String get saved;

  /// No description provided for @savedRestartNeeded.
  ///
  /// In pl, this message translates to:
  /// **'Zapisano. Nowy port zacznie działać po ponownym uruchomieniu aplikacji.'**
  String get savedRestartNeeded;

  /// No description provided for @appearance.
  ///
  /// In pl, this message translates to:
  /// **'Wygląd'**
  String get appearance;

  /// No description provided for @themeSystem.
  ///
  /// In pl, this message translates to:
  /// **'Systemowy'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In pl, this message translates to:
  /// **'Jasny'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In pl, this message translates to:
  /// **'Ciemny'**
  String get themeDark;

  /// No description provided for @background.
  ///
  /// In pl, this message translates to:
  /// **'Tło'**
  String get background;

  /// No description provided for @backgroundNone.
  ///
  /// In pl, this message translates to:
  /// **'Bez tła'**
  String get backgroundNone;

  /// No description provided for @backgroundDusk.
  ///
  /// In pl, this message translates to:
  /// **'Zmierzch'**
  String get backgroundDusk;

  /// No description provided for @backgroundOcean.
  ///
  /// In pl, this message translates to:
  /// **'Ocean'**
  String get backgroundOcean;

  /// No description provided for @backgroundForest.
  ///
  /// In pl, this message translates to:
  /// **'Las'**
  String get backgroundForest;

  /// No description provided for @backgroundSand.
  ///
  /// In pl, this message translates to:
  /// **'Piasek'**
  String get backgroundSand;

  /// No description provided for @language.
  ///
  /// In pl, this message translates to:
  /// **'Język'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In pl, this message translates to:
  /// **'Systemowy'**
  String get languageSystem;

  /// No description provided for @languagePolish.
  ///
  /// In pl, this message translates to:
  /// **'Polski'**
  String get languagePolish;

  /// No description provided for @languageEnglish.
  ///
  /// In pl, this message translates to:
  /// **'Angielski'**
  String get languageEnglish;

  /// No description provided for @backgroundListening.
  ///
  /// In pl, this message translates to:
  /// **'Nasłuch w tle'**
  String get backgroundListening;

  /// No description provided for @batteryExemptOk.
  ///
  /// In pl, this message translates to:
  /// **'System nie usypia Chatta. Wiadomości i pliki dochodzą też przy zgaszonym ekranie.'**
  String get batteryExemptOk;

  /// No description provided for @batteryOptimizedWarning.
  ///
  /// In pl, this message translates to:
  /// **'Android usypia Chatta przy zgaszonym ekranie i potrafi odciąć mu sieć. Bez wyjątku wiadomości mogą nie dochodzić, dopóki nie otworzysz aplikacji.'**
  String get batteryOptimizedWarning;

  /// No description provided for @batteryExemptButton.
  ///
  /// In pl, this message translates to:
  /// **'Wyłącz optymalizację baterii'**
  String get batteryExemptButton;

  /// No description provided for @batteryExemptUnavailable.
  ///
  /// In pl, this message translates to:
  /// **'To urządzenie nie ma ekranu z optymalizacją baterii. Poszukaj jej w ustawieniach systemu.'**
  String get batteryExemptUnavailable;

  /// No description provided for @cleanUpDevices.
  ///
  /// In pl, this message translates to:
  /// **'Wyczyść nieużywane urządzenia'**
  String get cleanUpDevices;

  /// No description provided for @cleanUpHelp.
  ///
  /// In pl, this message translates to:
  /// **'Usuwa z listy urządzenia, z którymi nie ma żadnej wiadomości i których nie widać od godziny. Sparowanych i rozmów nie rusza.'**
  String get cleanUpHelp;

  /// No description provided for @nothingToCleanUp.
  ///
  /// In pl, this message translates to:
  /// **'Nie było czego usuwać.'**
  String get nothingToCleanUp;

  /// No description provided for @cleanedUp.
  ///
  /// In pl, this message translates to:
  /// **'Usunięto z listy: {count}'**
  String cleanedUp(int count);

  /// No description provided for @privacy.
  ///
  /// In pl, this message translates to:
  /// **'Prywatność'**
  String get privacy;

  /// No description provided for @dbKeyProtected.
  ///
  /// In pl, this message translates to:
  /// **'Historia leży na dysku zaszyfrowana, a klucz do niej trzyma schowek systemowy. Skopiowanie samego pliku bazy nic nie da.'**
  String get dbKeyProtected;

  /// No description provided for @dbKeyUnprotected.
  ///
  /// In pl, this message translates to:
  /// **'Historia jest zaszyfrowana, ale schowek systemowy nie przyjął klucza, więc leży on obok bazy. Chroni to sam plik bazy; kopia całego katalogu aplikacji zawiera też klucz.'**
  String get dbKeyUnprotected;

  /// No description provided for @retentionLabel.
  ///
  /// In pl, this message translates to:
  /// **'Kasuj wiadomości starsze niż'**
  String get retentionLabel;

  /// No description provided for @retentionNever.
  ///
  /// In pl, this message translates to:
  /// **'Nie kasuj'**
  String get retentionNever;

  /// No description provided for @retentionDays.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{{count} dzień} few{{count} dni} many{{count} dni} other{{count} dni}}'**
  String retentionDays(int count);

  /// No description provided for @retentionHelp.
  ///
  /// In pl, this message translates to:
  /// **'Kasowanie dotyczy wpisów w rozmowach. Odebrane pliki zostają na dysku.'**
  String get retentionHelp;

  /// No description provided for @clearHistory.
  ///
  /// In pl, this message translates to:
  /// **'Wyczyść historię'**
  String get clearHistory;

  /// No description provided for @clearHistoryTitle.
  ///
  /// In pl, this message translates to:
  /// **'Wyczyścić całą historię?'**
  String get clearHistoryTitle;

  /// No description provided for @clearHistoryBody.
  ///
  /// In pl, this message translates to:
  /// **'Znikną wszystkie wiadomości i rozmowy. Urządzenia razem z potwierdzoną tożsamością zostają, odebrane pliki też zostają na dysku.'**
  String get clearHistoryBody;

  /// No description provided for @historyCleared.
  ///
  /// In pl, this message translates to:
  /// **'Usunięto wiadomości: {count}'**
  String historyCleared(int count);

  /// No description provided for @thisDevice.
  ///
  /// In pl, this message translates to:
  /// **'To urządzenie'**
  String get thisDevice;

  /// No description provided for @version.
  ///
  /// In pl, this message translates to:
  /// **'Wersja'**
  String get version;

  /// No description provided for @listeningOn.
  ///
  /// In pl, this message translates to:
  /// **'Nasłuch'**
  String get listeningOn;

  /// No description provided for @deviceIdentifier.
  ///
  /// In pl, this message translates to:
  /// **'Identyfikator'**
  String get deviceIdentifier;

  /// No description provided for @listeningPort.
  ///
  /// In pl, this message translates to:
  /// **'port {port}'**
  String listeningPort(int port);

  /// No description provided for @manualPairingHint.
  ///
  /// In pl, this message translates to:
  /// **'Ten adres wpisujesz na drugim urządzeniu w „Dodaj po adresie IP”, gdy automatyczne wykrywanie nie działa.'**
  String get manualPairingHint;

  /// No description provided for @windowsSection.
  ///
  /// In pl, this message translates to:
  /// **'Windows'**
  String get windowsSection;

  /// No description provided for @startWithWindows.
  ///
  /// In pl, this message translates to:
  /// **'Uruchamiaj razem z Windowsem'**
  String get startWithWindows;

  /// No description provided for @startWithWindowsHelp.
  ///
  /// In pl, this message translates to:
  /// **'Chatt wstaje po zalogowaniu i od razu siada w zasobniku, więc wiadomości dochodzą bez otwierania okna.'**
  String get startWithWindowsHelp;

  /// No description provided for @startWithWindowsFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się zmienić autostartu.'**
  String get startWithWindowsFailed;

  /// No description provided for @trayHint.
  ///
  /// In pl, this message translates to:
  /// **'Zamknięcie okna chowa Chatt do zasobnika i nie przerywa nasłuchu. Wyjście z programu jest w menu ikony.'**
  String get trayHint;

  /// No description provided for @trayTooltip.
  ///
  /// In pl, this message translates to:
  /// **'Chatt: nasłuchuje w sieci lokalnej'**
  String get trayTooltip;

  /// No description provided for @trayShow.
  ///
  /// In pl, this message translates to:
  /// **'Pokaż Chatt'**
  String get trayShow;

  /// No description provided for @trayQuit.
  ///
  /// In pl, this message translates to:
  /// **'Zamknij Chatt'**
  String get trayQuit;

  /// No description provided for @backgroundServiceTitle.
  ///
  /// In pl, this message translates to:
  /// **'Chatt nasłuchuje'**
  String get backgroundServiceTitle;

  /// No description provided for @backgroundServiceBody.
  ///
  /// In pl, this message translates to:
  /// **'Odbiera wiadomości i pliki z tej sieci Wi-Fi'**
  String get backgroundServiceBody;

  /// No description provided for @copyImage.
  ///
  /// In pl, this message translates to:
  /// **'Kopiuj obraz'**
  String get copyImage;

  /// No description provided for @imageCopied.
  ///
  /// In pl, this message translates to:
  /// **'Obraz skopiowany do schowka'**
  String get imageCopied;

  /// No description provided for @imageCopyFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się skopiować obrazu'**
  String get imageCopyFailed;

  /// No description provided for @renamePeer.
  ///
  /// In pl, this message translates to:
  /// **'Zmień nazwę'**
  String get renamePeer;

  /// No description provided for @renamePeerTitle.
  ///
  /// In pl, this message translates to:
  /// **'Twoja nazwa tego urządzenia'**
  String get renamePeerTitle;

  /// No description provided for @renamePeerHelp.
  ///
  /// In pl, this message translates to:
  /// **'Nazwa zostaje na tym urządzeniu i nigdzie nie jedzie. Puste pole wraca do nazwy, którą rozgłasza samo urządzenie.'**
  String get renamePeerHelp;

  /// No description provided for @peerRenamed.
  ///
  /// In pl, this message translates to:
  /// **'Nazwa zmieniona na {name}'**
  String peerRenamed(String name);

  /// No description provided for @peerRenameCleared.
  ///
  /// In pl, this message translates to:
  /// **'Wróciła nazwa rozgłaszana'**
  String get peerRenameCleared;

  /// No description provided for @broadcastName.
  ///
  /// In pl, this message translates to:
  /// **'Nazwa rozgłaszana: {name}'**
  String broadcastName(String name);

  /// No description provided for @autoAcceptTitle.
  ///
  /// In pl, this message translates to:
  /// **'Przyjmuj pliki bez pytania'**
  String get autoAcceptTitle;

  /// No description provided for @autoAcceptBody.
  ///
  /// In pl, this message translates to:
  /// **'Pliki od tego urządzenia trafiają prosto do rozmowy, bez karty z pytaniem. Działa tylko przy potwierdzonej tożsamości, a przełącznik gaśnie sam, gdy potwierdzenie zniknie.'**
  String get autoAcceptBody;

  /// No description provided for @autoAcceptNeedsVerified.
  ///
  /// In pl, this message translates to:
  /// **'Najpierw potwierdź tożsamość'**
  String get autoAcceptNeedsVerified;

  /// No description provided for @selectText.
  ///
  /// In pl, this message translates to:
  /// **'Zaznacz tekst'**
  String get selectText;

  /// No description provided for @selectTextHint.
  ///
  /// In pl, this message translates to:
  /// **'Przytrzymaj, żeby zaznaczyć fragment'**
  String get selectTextHint;

  /// No description provided for @discoveryDeaf.
  ///
  /// In pl, this message translates to:
  /// **'To urządzenie nie odpowiada na skany. Inni znajdą je dopiero po ręcznym dodaniu adresu. Najczęstsza przyczyna: port 47777 zajęty przez inny program.'**
  String get discoveryDeaf;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pl':
      return AppLocalizationsPl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
