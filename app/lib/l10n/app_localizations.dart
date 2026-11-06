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

  /// No description provided for @imageLoadFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się wczytać obrazu.'**
  String get imageLoadFailed;

  /// No description provided for @rotate.
  ///
  /// In pl, this message translates to:
  /// **'Obróć'**
  String get rotate;

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

  /// No description provided for @attachFromDevice.
  ///
  /// In pl, this message translates to:
  /// **'Plik z urządzenia'**
  String get attachFromDevice;

  /// No description provided for @attachFromClipboard.
  ///
  /// In pl, this message translates to:
  /// **'Wklej ze schowka'**
  String get attachFromClipboard;

  /// No description provided for @pasteNothing.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się nic wziąć ze schowka'**
  String get pasteNothing;

  /// Nazwa pliku dla obrazka wklejonego ze schowka, który nie ma swojego pliku na dysku (zrzut ekranu, „kopiuj obraz” w przeglądarce). Widzą ją obie strony rozmowy, w języku nadawcy. Rozszerzenie podmienia się, gdy obrazek nie jest PNG.
  ///
  /// In pl, this message translates to:
  /// **'obraz.png'**
  String get pastedImageName;

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

  /// Nagłówek karty, gdy jedna zgoda obejmuje całą paczkę plików. Pod nim idzie spis nazw i łączny rozmiar.
  ///
  /// In pl, this message translates to:
  /// **'{name} {count, plural, one{chce wysłać {count} plik} few{chce wysłać {count} pliki} other{chce wysłać {count} plików}}'**
  String fileOfferBatchTitle(Object name, int count);

  /// No description provided for @acceptAll.
  ///
  /// In pl, this message translates to:
  /// **'Przyjmij wszystkie'**
  String get acceptAll;

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
  /// **'Kasowanie dotyczy wpisów w rozmowach i historii pisania. Odebrane pliki zostają na dysku.'**
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
  /// **'Znikną wszystkie wiadomości, rozmowy i historia pisania. Urządzenia razem z potwierdzoną tożsamością zostają, odebrane pliki też zostają na dysku.'**
  String get clearHistoryBody;

  /// No description provided for @historyCleared.
  ///
  /// In pl, this message translates to:
  /// **'Usunięto wiadomości: {count}'**
  String historyCleared(int count);

  /// No description provided for @links.
  ///
  /// In pl, this message translates to:
  /// **'Odnośniki'**
  String get links;

  /// No description provided for @linkPreviewsLabel.
  ///
  /// In pl, this message translates to:
  /// **'Pokazuj podglądy stron'**
  String get linkPreviewsLabel;

  /// No description provided for @linkPreviewsHelp.
  ///
  /// In pl, this message translates to:
  /// **'Pod odnośnikiem w rozmowie pojawia się karta z tytułem, opisem i obrazkiem strony. Żeby ją pobrać, aplikacja łączy się z tą stroną, więc jej serwer zobaczy adres IP tego urządzenia i moment, w którym wiadomość dotarła. Domyślnie wyłączone.'**
  String get linkPreviewsHelp;

  /// No description provided for @linkPreviewsSafety.
  ///
  /// In pl, this message translates to:
  /// **'Podgląd to sam tekst i obrazek. Aplikacja nie otwiera strony, nie uruchamia żadnych skryptów z niej i nie pobiera podglądów spod adresów w Twojej sieci lokalnej. Kliknięcie w odnośnik zawsze najpierw pyta o potwierdzenie.'**
  String get linkPreviewsSafety;

  /// No description provided for @linkPreviewOf.
  ///
  /// In pl, this message translates to:
  /// **'Podgląd strony: {site}'**
  String linkPreviewOf(Object site);

  /// No description provided for @linkConfirmTitle.
  ///
  /// In pl, this message translates to:
  /// **'Czy na pewno chcesz przejść do tej strony?'**
  String get linkConfirmTitle;

  /// No description provided for @linkConfirmHost.
  ///
  /// In pl, this message translates to:
  /// **'Adres prowadzi do serwera'**
  String get linkConfirmHost;

  /// No description provided for @linkConfirmFull.
  ///
  /// In pl, this message translates to:
  /// **'Pełny adres'**
  String get linkConfirmFull;

  /// No description provided for @linkOpen.
  ///
  /// In pl, this message translates to:
  /// **'Otwórz'**
  String get linkOpen;

  /// No description provided for @linkOpenTitle.
  ///
  /// In pl, this message translates to:
  /// **'Otwórz odnośnik'**
  String get linkOpenTitle;

  /// No description provided for @linkCopy.
  ///
  /// In pl, this message translates to:
  /// **'Kopiuj adres'**
  String get linkCopy;

  /// No description provided for @linkCopied.
  ///
  /// In pl, this message translates to:
  /// **'Skopiowano adres.'**
  String get linkCopied;

  /// No description provided for @linkOpenFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się otworzyć przeglądarki.'**
  String get linkOpenFailed;

  /// No description provided for @linkWarnUserInfo.
  ///
  /// In pl, this message translates to:
  /// **'W adresie stoi znak @: to, co widać przed nim, nie jest nazwą serwera. Liczy się nazwa pokazana wyżej.'**
  String get linkWarnUserInfo;

  /// No description provided for @linkWarnNonAscii.
  ///
  /// In pl, this message translates to:
  /// **'Nazwa serwera zawiera litery spoza alfabetu łacińskiego. Bywają nie do odróżnienia od zwykłych, a prowadzą gdzie indziej.'**
  String get linkWarnNonAscii;

  /// No description provided for @linkWarnInsecure.
  ///
  /// In pl, this message translates to:
  /// **'Połączenie bez szyfrowania (http). Ktoś w tej samej sieci może podejrzeć i podmienić treść strony.'**
  String get linkWarnInsecure;

  /// No description provided for @linkWarnLocal.
  ///
  /// In pl, this message translates to:
  /// **'Adres wskazuje na urządzenie w Twojej sieci lokalnej, na przykład na router.'**
  String get linkWarnLocal;

  /// No description provided for @updates.
  ///
  /// In pl, this message translates to:
  /// **'Aktualizacje'**
  String get updates;

  /// No description provided for @updateChecksLabel.
  ///
  /// In pl, this message translates to:
  /// **'Sprawdzaj aktualizacje automatycznie'**
  String get updateChecksLabel;

  /// No description provided for @updateChecksHelp.
  ///
  /// In pl, this message translates to:
  /// **'Raz na dobę Chatt pyta GitHuba, czy wyszło nowsze wydanie. To jedyna rzecz, którą aplikacja wysyła poza Twoją sieć, i stoi wyłączona, dopóki jej nie włączysz.'**
  String get updateChecksHelp;

  /// No description provided for @updateCheckNow.
  ///
  /// In pl, this message translates to:
  /// **'Sprawdź teraz'**
  String get updateCheckNow;

  /// No description provided for @updateChecking.
  ///
  /// In pl, this message translates to:
  /// **'Sprawdzam…'**
  String get updateChecking;

  /// No description provided for @updateUpToDate.
  ///
  /// In pl, this message translates to:
  /// **'To najnowsze wydanie.'**
  String get updateUpToDate;

  /// No description provided for @updateAvailable.
  ///
  /// In pl, this message translates to:
  /// **'Wyszła wersja {version}'**
  String updateAvailable(Object version);

  /// No description provided for @updateDownload.
  ///
  /// In pl, this message translates to:
  /// **'Pobierz i zainstaluj'**
  String get updateDownload;

  /// No description provided for @updateDownloading.
  ///
  /// In pl, this message translates to:
  /// **'Pobieram… {percent}%'**
  String updateDownloading(int percent);

  /// No description provided for @updatePortableHint.
  ///
  /// In pl, this message translates to:
  /// **'Ta kopia chodzi z zipa, więc nową trzeba rozpakować ręcznie. Strona wydania:'**
  String get updatePortableHint;

  /// No description provided for @updateNoAsset.
  ///
  /// In pl, this message translates to:
  /// **'To wydanie nie ma pliku dla tej platformy. Strona wydania:'**
  String get updateNoAsset;

  /// No description provided for @updateInstallFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się uruchomić instalatora.'**
  String get updateInstallFailed;

  /// No description provided for @updateDownloadFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się pobrać pliku.'**
  String get updateDownloadFailed;

  /// No description provided for @updateClosingForInstall.
  ///
  /// In pl, this message translates to:
  /// **'Chatt zamyka się teraz, dalej pracuje instalator.'**
  String get updateClosingForInstall;

  /// No description provided for @updateLastChecked.
  ///
  /// In pl, this message translates to:
  /// **'Ostatnio sprawdzano {when}'**
  String updateLastChecked(Object when);

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

  /// No description provided for @addons.
  ///
  /// In pl, this message translates to:
  /// **'Dodatki'**
  String get addons;

  /// No description provided for @transportWifi.
  ///
  /// In pl, this message translates to:
  /// **'Sieć lokalna'**
  String get transportWifi;

  /// No description provided for @transportInternet.
  ///
  /// In pl, this message translates to:
  /// **'Internet'**
  String get transportInternet;

  /// No description provided for @transportBluetooth.
  ///
  /// In pl, this message translates to:
  /// **'Bluetooth'**
  String get transportBluetooth;

  /// No description provided for @transportBluetoothUnsupported.
  ///
  /// In pl, this message translates to:
  /// **'Na tym systemie nie ma Bluetootha w Chatcie.'**
  String get transportBluetoothUnsupported;

  /// No description provided for @transportBluetoothRadioOff.
  ///
  /// In pl, this message translates to:
  /// **'Włącz Bluetooth w ustawieniach systemu.'**
  String get transportBluetoothRadioOff;

  /// No description provided for @transportBluetoothNoPermission.
  ///
  /// In pl, this message translates to:
  /// **'Chatt nie ma zgody na urządzenia w pobliżu.'**
  String get transportBluetoothNoPermission;

  /// No description provided for @transportBluetoothGrant.
  ///
  /// In pl, this message translates to:
  /// **'Otwórz ustawienia'**
  String get transportBluetoothGrant;

  /// No description provided for @transportBluetoothFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się włączyć Bluetootha.'**
  String get transportBluetoothFailed;

  /// No description provided for @transportBothOff.
  ///
  /// In pl, this message translates to:
  /// **'Sieć wyłączona, a Bluetooth nie działa: to urządzenie z nikim się nie skontaktuje.'**
  String get transportBothOff;

  /// No description provided for @transportBluetoothDiscoverable.
  ///
  /// In pl, this message translates to:
  /// **'Przy włączonym dodatku ten komputer jest widoczny dla urządzeń w pobliżu. Gaśnie razem z przełącznikiem.'**
  String get transportBluetoothDiscoverable;

  /// No description provided for @keyboardAddon.
  ///
  /// In pl, this message translates to:
  /// **'Klawiatura z PC'**
  String get keyboardAddon;

  /// No description provided for @remoteInputReceive.
  ///
  /// In pl, this message translates to:
  /// **'Pozwól pisać na tym urządzeniu'**
  String get remoteInputReceive;

  /// No description provided for @remoteInputSafety.
  ///
  /// In pl, this message translates to:
  /// **'Drugie urządzenie pisze tu jak zwykła klawiatura: może wysłać wiadomość, zatwierdzić formularz, wpisać hasło. Sesja trwa do Stopu albo do pół godziny bez pisania.'**
  String get remoteInputSafety;

  /// No description provided for @remoteInputUnsupported.
  ///
  /// In pl, this message translates to:
  /// **'Pisanie z innego urządzenia przyjmują Android i Windows.'**
  String get remoteInputUnsupported;

  /// No description provided for @remoteInputRequestTitle.
  ///
  /// In pl, this message translates to:
  /// **'{name} chce pisać na tym urządzeniu'**
  String remoteInputRequestTitle(Object name);

  /// No description provided for @remoteInputRequestBody.
  ///
  /// In pl, this message translates to:
  /// **'Tekst trafi do pola, które ma fokus, w dowolnej aplikacji, aż do Stopu.'**
  String get remoteInputRequestBody;

  /// No description provided for @remoteInputActive.
  ///
  /// In pl, this message translates to:
  /// **'Pisze: {name}'**
  String remoteInputActive(Object name);

  /// No description provided for @remoteInputStop.
  ///
  /// In pl, this message translates to:
  /// **'Stop'**
  String get remoteInputStop;

  /// No description provided for @remoteInputBarTarget.
  ///
  /// In pl, this message translates to:
  /// **'Pisze: {name} → {app}'**
  String remoteInputBarTarget(Object name, Object app);

  /// No description provided for @trayRemoteInputStop.
  ///
  /// In pl, this message translates to:
  /// **'Zatrzymaj zdalną klawiaturę'**
  String get trayRemoteInputStop;

  /// No description provided for @remoteInputSwitchTitle.
  ///
  /// In pl, this message translates to:
  /// **'Przełącz klawiaturę na Chatt'**
  String get remoteInputSwitchTitle;

  /// No description provided for @remoteInputSwitchBody.
  ///
  /// In pl, this message translates to:
  /// **'{name} pisze na tym urządzeniu. Dotknij i wybierz klawiaturę Chatt.'**
  String remoteInputSwitchBody(Object name);

  /// No description provided for @remoteInputImeOff.
  ///
  /// In pl, this message translates to:
  /// **'Pisanie z innego urządzenia przechodzi przez klawiaturę Chatt. Włącz ją raz w ustawieniach systemu.'**
  String get remoteInputImeOff;

  /// No description provided for @remoteInputImeWarning.
  ///
  /// In pl, this message translates to:
  /// **'Android ostrzeże, że klawiatura może zbierać wpisywany tekst. Klawiatura Chatt niczego z Twoich pól nie wysyła: wpisuje to, co przyjdzie od urządzenia, któremu pozwolisz pisać.'**
  String get remoteInputImeWarning;

  /// No description provided for @remoteInputImeEnable.
  ///
  /// In pl, this message translates to:
  /// **'Włącz klawiaturę Chatt'**
  String get remoteInputImeEnable;

  /// No description provided for @remoteInputImeNotSelected.
  ///
  /// In pl, this message translates to:
  /// **'Na czas pisania wybierz klawiaturę Chatt. Po sesji wraca poprzednia.'**
  String get remoteInputImeNotSelected;

  /// No description provided for @remoteInputImePick.
  ///
  /// In pl, this message translates to:
  /// **'Wybierz klawiaturę'**
  String get remoteInputImePick;

  /// No description provided for @remoteInputImeReady.
  ///
  /// In pl, this message translates to:
  /// **'Klawiatura Chatt jest włączona.'**
  String get remoteInputImeReady;

  /// No description provided for @remoteInputDontAskAgain.
  ///
  /// In pl, this message translates to:
  /// **'Nie pytaj więcej dla tego urządzenia'**
  String get remoteInputDontAskAgain;

  /// No description provided for @remoteInputBannerTarget.
  ///
  /// In pl, this message translates to:
  /// **'{name} pisze do: {app}'**
  String remoteInputBannerTarget(Object name, Object app);

  /// No description provided for @remoteInputAllowTitle.
  ///
  /// In pl, this message translates to:
  /// **'Pisanie bez pytania'**
  String get remoteInputAllowTitle;

  /// No description provided for @remoteInputAllowBody.
  ///
  /// In pl, this message translates to:
  /// **'To urządzenie zaczyna pisać tutaj bez karty zgody. Pasek „Pisze” ze Stopem pokazuje się jak zawsze. Działa tylko przy potwierdzonej tożsamości i włączonym pisaniu w dodatku „Klawiatura z PC”.'**
  String get remoteInputAllowBody;

  /// No description provided for @remoteKeyboardOpen.
  ///
  /// In pl, this message translates to:
  /// **'Pisz na tamtym urządzeniu'**
  String get remoteKeyboardOpen;

  /// No description provided for @remoteKeyboardNeedsVerified.
  ///
  /// In pl, this message translates to:
  /// **'Pisanie na tamtym urządzeniu wymaga potwierdzonej tożsamości'**
  String get remoteKeyboardNeedsVerified;

  /// No description provided for @remoteKeyboardTitle.
  ///
  /// In pl, this message translates to:
  /// **'Piszesz na: {name}'**
  String remoteKeyboardTitle(Object name);

  /// No description provided for @remoteKeyboardWaiting.
  ///
  /// In pl, this message translates to:
  /// **'Czekam na zgodę na urządzeniu {name}. Otwórz tam Chatt.'**
  String remoteKeyboardWaiting(Object name);

  /// No description provided for @remoteKeyboardWaitingHint.
  ///
  /// In pl, this message translates to:
  /// **'Telefon z Androidem pokaże powiadomienie, jeśli Chatt ma zgodę na powiadomienia.'**
  String get remoteKeyboardWaitingHint;

  /// No description provided for @remoteKeyboardTarget.
  ///
  /// In pl, this message translates to:
  /// **'Pisze do: {app}'**
  String remoteKeyboardTarget(Object app);

  /// No description provided for @remoteKeyboardTargetPassword.
  ///
  /// In pl, this message translates to:
  /// **'Pisze do: {app} · pole hasła'**
  String remoteKeyboardTargetPassword(Object app);

  /// No description provided for @remoteKeyboardNoField.
  ///
  /// In pl, this message translates to:
  /// **'Brak pola do pisania. Stuknij pole na tamtym urządzeniu; na Androidzie z wybraną klawiaturą Chatt.'**
  String get remoteKeyboardNoField;

  /// No description provided for @remoteKeyboardElevated.
  ///
  /// In pl, this message translates to:
  /// **'Okno z uprawnieniami administratora. Tam nic się nie wpisze.'**
  String get remoteKeyboardElevated;

  /// No description provided for @remoteKeyboardLocked.
  ///
  /// In pl, this message translates to:
  /// **'Tamto urządzenie jest zablokowane albo ma wygaszony ekran.'**
  String get remoteKeyboardLocked;

  /// No description provided for @remoteKeyboardPaused.
  ///
  /// In pl, this message translates to:
  /// **'Wstrzymane: na tamtym urządzeniu czeka pytanie. Pisanie wróci po odpowiedzi.'**
  String get remoteKeyboardPaused;

  /// No description provided for @remoteKeyboardLocalCard.
  ///
  /// In pl, this message translates to:
  /// **'Odpowiedz na pytanie u góry, potem pisz dalej.'**
  String get remoteKeyboardLocalCard;

  /// No description provided for @remoteKeyboardEnded.
  ///
  /// In pl, this message translates to:
  /// **'Sesję zakończono na urządzeniu {name}.'**
  String remoteKeyboardEnded(Object name);

  /// No description provided for @remoteKeyboardLost.
  ///
  /// In pl, this message translates to:
  /// **'Połączenie zerwane.'**
  String get remoteKeyboardLost;

  /// No description provided for @remoteKeyboardReconnect.
  ///
  /// In pl, this message translates to:
  /// **'Połącz ponownie'**
  String get remoteKeyboardReconnect;

  /// No description provided for @remoteKeyboardModeLive.
  ///
  /// In pl, this message translates to:
  /// **'Znak po znaku'**
  String get remoteKeyboardModeLive;

  /// No description provided for @remoteKeyboardModeCompose.
  ///
  /// In pl, this message translates to:
  /// **'Całość naraz'**
  String get remoteKeyboardModeCompose;

  /// No description provided for @remoteKeyboardLiveHint.
  ///
  /// In pl, this message translates to:
  /// **'Pisz tutaj. Każdy znak od razu trafia na tamto urządzenie.'**
  String get remoteKeyboardLiveHint;

  /// No description provided for @remoteKeyboardKeysHint.
  ///
  /// In pl, this message translates to:
  /// **'Enter zatwierdza pole, Shift+Enter to nowa linia, Backspace i Delete kasują na tamtym urządzeniu.'**
  String get remoteKeyboardKeysHint;

  /// No description provided for @remoteKeyboardComposeHint.
  ///
  /// In pl, this message translates to:
  /// **'Napisz tekst i wyślij go w całości.'**
  String get remoteKeyboardComposeHint;

  /// No description provided for @remoteKeyboardSend.
  ///
  /// In pl, this message translates to:
  /// **'Wyślij'**
  String get remoteKeyboardSend;

  /// No description provided for @remoteKeyboardThenEnter.
  ///
  /// In pl, this message translates to:
  /// **'Potem Enter'**
  String get remoteKeyboardThenEnter;

  /// No description provided for @remoteKeyboardPaste.
  ///
  /// In pl, this message translates to:
  /// **'Wklej ze schowka'**
  String get remoteKeyboardPaste;

  /// No description provided for @remoteKeyboardClipboardEmpty.
  ///
  /// In pl, this message translates to:
  /// **'W schowku nie ma tekstu.'**
  String get remoteKeyboardClipboardEmpty;

  /// No description provided for @remoteKeyboardTooLong.
  ///
  /// In pl, this message translates to:
  /// **'Za dużo tekstu naraz. Wyślij go w częściach.'**
  String get remoteKeyboardTooLong;

  /// No description provided for @remoteKeyboardRejected.
  ///
  /// In pl, this message translates to:
  /// **'Urządzenie {name} odmówiło.'**
  String remoteKeyboardRejected(Object name);

  /// No description provided for @remoteKeyboardNotEnabled.
  ///
  /// In pl, this message translates to:
  /// **'Na urządzeniu {name} pisanie jest wyłączone. Włącza się je w Ustawieniach, w dodatku „Klawiatura z PC”.'**
  String remoteKeyboardNotEnabled(Object name);

  /// No description provided for @remoteKeyboardNoAnswer.
  ///
  /// In pl, this message translates to:
  /// **'Urządzenie {name} nie odpowiedziało na prośbę.'**
  String remoteKeyboardNoAnswer(Object name);

  /// No description provided for @remoteKeyboardBusy.
  ///
  /// In pl, this message translates to:
  /// **'Na urządzeniu {name} pisze już ktoś inny.'**
  String remoteKeyboardBusy(Object name);

  /// No description provided for @remoteKeyboardOlderPeer.
  ///
  /// In pl, this message translates to:
  /// **'Urządzenie {name} ma starszą wersję Chatt, bez zdalnej klawiatury.'**
  String remoteKeyboardOlderPeer(Object name);

  /// No description provided for @remoteKeyboardUnreachable.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się połączyć z urządzeniem {name}.'**
  String remoteKeyboardUnreachable(Object name);

  /// No description provided for @remoteKeyboardNotVerified.
  ///
  /// In pl, this message translates to:
  /// **'Najpierw potwierdź tożsamość tego urządzenia.'**
  String get remoteKeyboardNotVerified;

  /// No description provided for @remoteKeyboardAddonOff.
  ///
  /// In pl, this message translates to:
  /// **'Dodatek „Klawiatura z PC” jest wyłączony.'**
  String get remoteKeyboardAddonOff;

  /// No description provided for @viaWifi.
  ///
  /// In pl, this message translates to:
  /// **'przez sieć'**
  String get viaWifi;

  /// No description provided for @viaBluetooth.
  ///
  /// In pl, this message translates to:
  /// **'przez Bluetooth'**
  String get viaBluetooth;

  /// No description provided for @viaInternet.
  ///
  /// In pl, this message translates to:
  /// **'przez internet'**
  String get viaInternet;

  /// No description provided for @protocolWifi.
  ///
  /// In pl, this message translates to:
  /// **'Sieć'**
  String get protocolWifi;

  /// No description provided for @protocolBluetooth.
  ///
  /// In pl, this message translates to:
  /// **'Bluetooth'**
  String get protocolBluetooth;

  /// No description provided for @protocolInternet.
  ///
  /// In pl, this message translates to:
  /// **'Internet'**
  String get protocolInternet;

  /// No description provided for @searchWhere.
  ///
  /// In pl, this message translates to:
  /// **'Gdzie szukać'**
  String get searchWhere;

  /// No description provided for @searchBluetoothHint.
  ///
  /// In pl, this message translates to:
  /// **'Szukanie przez radio trwa do półtorej minuty i na ten czas zwalnia otwarte rozmowy.'**
  String get searchBluetoothHint;

  /// No description provided for @searchBluetoothOff.
  ///
  /// In pl, this message translates to:
  /// **'Bluetooth nie działa. Sprawdź radio i zgodę w Ustawieniach, w sekcji Dodatki.'**
  String get searchBluetoothOff;

  /// No description provided for @searchingBluetooth.
  ///
  /// In pl, this message translates to:
  /// **'Szukam przez Bluetooth…'**
  String get searchingBluetooth;

  /// No description provided for @scanStartBluetooth.
  ///
  /// In pl, this message translates to:
  /// **'Szukaj przez Bluetooth'**
  String get scanStartBluetooth;

  /// No description provided for @nearbyBeforeScanBluetooth.
  ///
  /// In pl, this message translates to:
  /// **'Wyszukaj przez Bluetooth, żeby zobaczyć, które urządzenia obok odpowiadają.'**
  String get nearbyBeforeScanBluetooth;

  /// No description provided for @nearbyScanningBluetooth.
  ///
  /// In pl, this message translates to:
  /// **'Jeszcze nikt nie odpowiedział. Urządzenia pojawiają się tu po kolei, gdy tylko odpowiedzą.'**
  String get nearbyScanningBluetooth;

  /// No description provided for @scanNothingFoundBluetooth.
  ///
  /// In pl, this message translates to:
  /// **'Nie znaleziono urządzeń przez Bluetooth. Sprawdź, czy Chatt działa na drugim urządzeniu i ma włączony dodatek Bluetooth, i czy stoi najwyżej kilka metrów dalej. Telefon z Androidem trzeba najpierw pokazać: na nim w „W pobliżu” przy wybranym Bluetoothcie stuknij „Pokaż ten telefon w pobliżu”. Możesz też dodać urządzenie po adresie radia.'**
  String get scanNothingFoundBluetooth;

  /// No description provided for @searchBluetoothNoLocation.
  ///
  /// In pl, this message translates to:
  /// **'Android nie odda wyników szukania przy wyłączonych usługach lokalizacji. Do samego połączenia nie są potrzebne i Chatt o położenie nie pyta.'**
  String get searchBluetoothNoLocation;

  /// No description provided for @turnOnLocation.
  ///
  /// In pl, this message translates to:
  /// **'Włącz lokalizację'**
  String get turnOnLocation;

  /// No description provided for @showThisPhone.
  ///
  /// In pl, this message translates to:
  /// **'Pokaż ten telefon w pobliżu'**
  String get showThisPhone;

  /// No description provided for @showThisPhoneHint.
  ///
  /// In pl, this message translates to:
  /// **'Android pokazuje telefon innym urządzeniom tylko na żądanie. Gdy drugie urządzenie ma znaleźć ten telefon, stuknij przycisk, potwierdź w okienku i uruchom szukanie tam.'**
  String get showThisPhoneHint;

  /// No description provided for @thisPhoneVisible.
  ///
  /// In pl, this message translates to:
  /// **'Ten telefon jest teraz widoczny dla urządzeń w pobliżu, przez około dwie minuty. Uruchom szukanie na drugim urządzeniu.'**
  String get thisPhoneVisible;

  /// No description provided for @showThisPhoneFailed.
  ///
  /// In pl, this message translates to:
  /// **'Android nie pokazał pytania o widoczność. Ten sam skutek daje otwarty ekran parowania w ustawieniach Bluetooth telefonu.'**
  String get showThisPhoneFailed;

  /// No description provided for @addByBtAddress.
  ///
  /// In pl, this message translates to:
  /// **'Dodaj po adresie radia'**
  String get addByBtAddress;

  /// No description provided for @manualAddBtTitle.
  ///
  /// In pl, this message translates to:
  /// **'Dodaj po adresie Bluetooth'**
  String get manualAddBtTitle;

  /// No description provided for @manualAddBtHelp.
  ///
  /// In pl, this message translates to:
  /// **'Adres drugiego urządzenia znajdziesz w jego ustawieniach Bluetooth. Komputer pokazuje swój także w Ustawieniach Chatta, w sekcji Dodatki.'**
  String get manualAddBtHelp;

  /// No description provided for @btAddressLabel.
  ///
  /// In pl, this message translates to:
  /// **'Adres Bluetooth'**
  String get btAddressLabel;

  /// No description provided for @btAddressHint.
  ///
  /// In pl, this message translates to:
  /// **'AA:BB:CC:DD:EE:FF'**
  String get btAddressHint;

  /// No description provided for @noChattAtBtAddress.
  ///
  /// In pl, this message translates to:
  /// **'Pod {address} nie odpowiada Chatt'**
  String noChattAtBtAddress(String address);

  /// No description provided for @myBtAddress.
  ///
  /// In pl, this message translates to:
  /// **'Adres tego radia: {address}'**
  String myBtAddress(String address);

  /// No description provided for @historyMenu.
  ///
  /// In pl, this message translates to:
  /// **'Więcej'**
  String get historyMenu;

  /// No description provided for @historyShare.
  ///
  /// In pl, this message translates to:
  /// **'Udostępnij historię'**
  String get historyShare;

  /// No description provided for @historyRequest.
  ///
  /// In pl, this message translates to:
  /// **'Poproś o historię'**
  String get historyRequest;

  /// No description provided for @historyShareTitle.
  ///
  /// In pl, this message translates to:
  /// **'Udostępnij historię rozmowy'**
  String get historyShareTitle;

  /// No description provided for @historyShareBody.
  ///
  /// In pl, this message translates to:
  /// **'{name} dostanie kopię waszej rozmowy, oznaczoną jako przywrócona. Najpierw zobaczy kartę z pytaniem.'**
  String historyShareBody(Object name);

  /// No description provided for @historyRangeAll.
  ///
  /// In pl, this message translates to:
  /// **'Całość'**
  String get historyRangeAll;

  /// No description provided for @historyRangeSince.
  ///
  /// In pl, this message translates to:
  /// **'Od {date}'**
  String historyRangeSince(DateTime date);

  /// No description provided for @historyPickDate.
  ///
  /// In pl, this message translates to:
  /// **'Wybierz datę'**
  String get historyPickDate;

  /// No description provided for @historyWithFiles.
  ///
  /// In pl, this message translates to:
  /// **'Z plikami'**
  String get historyWithFiles;

  /// No description provided for @historyWithoutFiles.
  ///
  /// In pl, this message translates to:
  /// **'Bez plików'**
  String get historyWithoutFiles;

  /// No description provided for @historyCountMessages.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{{count} wiadomość} few{{count} wiadomości} many{{count} wiadomości} other{{count} wiadomości}}'**
  String historyCountMessages(int count);

  /// No description provided for @historyCountFiles.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, =0{bez plików} one{{count} plik} few{{count} pliki} many{{count} plików} other{{count} plików}}'**
  String historyCountFiles(int count);

  /// No description provided for @historyRange.
  ///
  /// In pl, this message translates to:
  /// **'od {from} do {to}'**
  String historyRange(DateTime from, DateTime to);

  /// No description provided for @historyMissingFiles.
  ///
  /// In pl, this message translates to:
  /// **'Plików, których już tu nie ma, pójdzie bez treści: {count}'**
  String historyMissingFiles(int count);

  /// No description provided for @historyNothing.
  ///
  /// In pl, this message translates to:
  /// **'W tej rozmowie nie ma czego udostępnić.'**
  String get historyNothing;

  /// No description provided for @historyShareAction.
  ///
  /// In pl, this message translates to:
  /// **'Udostępnij'**
  String get historyShareAction;

  /// No description provided for @historyShareDone.
  ///
  /// In pl, this message translates to:
  /// **'Historia udostępniona.'**
  String get historyShareDone;

  /// No description provided for @historyShareRejected.
  ///
  /// In pl, this message translates to:
  /// **'{name} nie przyjmuje historii.'**
  String historyShareRejected(Object name);

  /// No description provided for @historyNoAnswer.
  ///
  /// In pl, this message translates to:
  /// **'Nikt nie odpowiedział na karcie po drugiej stronie.'**
  String get historyNoAnswer;

  /// No description provided for @historyBusy.
  ///
  /// In pl, this message translates to:
  /// **'Trwa już inne przesyłanie historii. Spróbuj później.'**
  String get historyBusy;

  /// No description provided for @historyOlderVersion.
  ///
  /// In pl, this message translates to:
  /// **'Tamto urządzenie ma starszą wersję Chatt, bez udostępniania historii.'**
  String get historyOlderVersion;

  /// No description provided for @historyUnreachable.
  ///
  /// In pl, this message translates to:
  /// **'Tamto urządzenie nie odpowiada.'**
  String get historyUnreachable;

  /// No description provided for @historyCancelled.
  ///
  /// In pl, this message translates to:
  /// **'Udostępnianie przerwane. To, co doszło, zostaje po drugiej stronie.'**
  String get historyCancelled;

  /// No description provided for @historyFailed.
  ///
  /// In pl, this message translates to:
  /// **'Udostępnianie się nie udało. Spróbuj jeszcze raz: to, co doszło, się nie zdubluje.'**
  String get historyFailed;

  /// No description provided for @historyRequestSent.
  ///
  /// In pl, this message translates to:
  /// **'Prośba wysłana, czekam na odpowiedź.'**
  String get historyRequestSent;

  /// No description provided for @historyRequestAccepted.
  ///
  /// In pl, this message translates to:
  /// **'{name}: zgoda. Historia zaraz zacznie spływać.'**
  String historyRequestAccepted(Object name);

  /// No description provided for @historyRequestRejected.
  ///
  /// In pl, this message translates to:
  /// **'{name}: odmowa.'**
  String historyRequestRejected(Object name);

  /// No description provided for @historyRequestEmpty.
  ///
  /// In pl, this message translates to:
  /// **'{name} nie ma u siebie tej rozmowy.'**
  String historyRequestEmpty(Object name);

  /// No description provided for @historyOfferTitle.
  ///
  /// In pl, this message translates to:
  /// **'{name} chce przywrócić historię waszej rozmowy'**
  String historyOfferTitle(Object name);

  /// No description provided for @historyOfferDeleted.
  ///
  /// In pl, this message translates to:
  /// **'Wróci także to, co zostało tu wcześniej usunięte.'**
  String get historyOfferDeleted;

  /// No description provided for @historyOfferMarked.
  ///
  /// In pl, this message translates to:
  /// **'Przywrócone wiadomości są oznaczone: to kopia rozmówcy i nikt jej nie podpisuje.'**
  String get historyOfferMarked;

  /// No description provided for @historyOfferUnverified.
  ///
  /// In pl, this message translates to:
  /// **'Tożsamość niepotwierdzona: historię może przysyłać ktoś, kto podaje się za tę osobę.'**
  String get historyOfferUnverified;

  /// No description provided for @historyOfferRetention.
  ///
  /// In pl, this message translates to:
  /// **'Wiadomości starsze niż {days} dni nie wejdą, bo tyle trzyma je ustawienie przechowywania.'**
  String historyOfferRetention(int days);

  /// No description provided for @historyRequestTitle.
  ///
  /// In pl, this message translates to:
  /// **'{name} prosi o historię waszej rozmowy'**
  String historyRequestTitle(Object name);

  /// No description provided for @historyRequestBody.
  ///
  /// In pl, this message translates to:
  /// **'Dostanie kopię tego, co jest tutaj w tej rozmowie, oznaczoną jako przywrócona.'**
  String get historyRequestBody;

  /// No description provided for @historySharing.
  ///
  /// In pl, this message translates to:
  /// **'Udostępnianie historii: {name}'**
  String historySharing(Object name);

  /// No description provided for @historyRestoring.
  ///
  /// In pl, this message translates to:
  /// **'Przywracanie historii od: {name}'**
  String historyRestoring(Object name);

  /// No description provided for @historyRestored.
  ///
  /// In pl, this message translates to:
  /// **'Historia od {name} przywrócona'**
  String historyRestored(Object name);

  /// No description provided for @historyProgressMessages.
  ///
  /// In pl, this message translates to:
  /// **'Wiadomości: {done} z {total}'**
  String historyProgressMessages(int done, int total);

  /// No description provided for @historyProgressFiles.
  ///
  /// In pl, this message translates to:
  /// **'Pliki: {done} z {total}'**
  String historyProgressFiles(int done, int total);

  /// No description provided for @historySkipped.
  ///
  /// In pl, this message translates to:
  /// **'Pominięte, bo już były albo są za stare: {count}'**
  String historySkipped(int count);

  /// No description provided for @historyStop.
  ///
  /// In pl, this message translates to:
  /// **'Przerwij'**
  String get historyStop;

  /// No description provided for @messageRestored.
  ///
  /// In pl, this message translates to:
  /// **'Przywrócona {date} z kopii rozmówcy'**
  String messageRestored(DateTime date);

  /// No description provided for @fileUnavailable.
  ///
  /// In pl, this message translates to:
  /// **'Plik niedostępny'**
  String get fileUnavailable;

  /// No description provided for @fileAwaiting.
  ///
  /// In pl, this message translates to:
  /// **'Czeka na przesłanie'**
  String get fileAwaiting;

  /// No description provided for @dateToday.
  ///
  /// In pl, this message translates to:
  /// **'Dzisiaj'**
  String get dateToday;

  /// No description provided for @dateYesterday.
  ///
  /// In pl, this message translates to:
  /// **'Wczoraj'**
  String get dateYesterday;

  /// No description provided for @dateSeparator.
  ///
  /// In pl, this message translates to:
  /// **'{date}'**
  String dateSeparator(DateTime date);

  /// No description provided for @historySource.
  ///
  /// In pl, this message translates to:
  /// **'Skąd'**
  String get historySource;

  /// No description provided for @historySourceThis.
  ///
  /// In pl, this message translates to:
  /// **'Ta rozmowa'**
  String get historySourceThis;

  /// No description provided for @historySourceOther.
  ///
  /// In pl, this message translates to:
  /// **'Starsza rozmowa z: {name} ({count})'**
  String historySourceOther(Object name, int count);

  /// No description provided for @historySourceHint.
  ///
  /// In pl, this message translates to:
  /// **'Po reinstalacji albo na nowym telefonie to samo urządzenie przychodzi pod nowym wpisem. Starszą rozmowę z dawnym wpisem możesz oddać tutaj.'**
  String get historySourceHint;

  /// No description provided for @historySourceNeedsShield.
  ///
  /// In pl, this message translates to:
  /// **'Starszą rozmowę z innym wpisem można oddać tylko urządzeniu z zieloną tarczą. Najpierw potwierdź jego tożsamość.'**
  String get historySourceNeedsShield;

  /// No description provided for @historyMergeLocally.
  ///
  /// In pl, this message translates to:
  /// **'Połącz u mnie tamtą rozmowę z tą'**
  String get historyMergeLocally;

  /// No description provided for @historyNeedsVerified.
  ///
  /// In pl, this message translates to:
  /// **'Najpierw potwierdź tożsamość tego urządzenia (zielona tarcza).'**
  String get historyNeedsVerified;

  /// No description provided for @historyMerged.
  ///
  /// In pl, this message translates to:
  /// **'Rozmowy połączone.'**
  String get historyMerged;

  /// No description provided for @profileSection.
  ///
  /// In pl, this message translates to:
  /// **'Profil'**
  String get profileSection;

  /// No description provided for @styleLabel.
  ///
  /// In pl, this message translates to:
  /// **'Styl'**
  String get styleLabel;

  /// No description provided for @styleCisza.
  ///
  /// In pl, this message translates to:
  /// **'Cisza'**
  String get styleCisza;

  /// No description provided for @stylePrecyzja.
  ///
  /// In pl, this message translates to:
  /// **'Precyzja'**
  String get stylePrecyzja;

  /// No description provided for @styleCieplo.
  ///
  /// In pl, this message translates to:
  /// **'Ciepło'**
  String get styleCieplo;

  /// No description provided for @themeLabel.
  ///
  /// In pl, this message translates to:
  /// **'Motyw'**
  String get themeLabel;

  /// No description provided for @addonBluetoothShort.
  ///
  /// In pl, this message translates to:
  /// **'Rozmowy bez wspólnej sieci Wi-Fi'**
  String get addonBluetoothShort;

  /// No description provided for @addonInternetShort.
  ///
  /// In pl, this message translates to:
  /// **'Rozmowy między różnymi sieciami'**
  String get addonInternetShort;

  /// No description provided for @addonInternetBody.
  ///
  /// In pl, this message translates to:
  /// **'Połączenie z potwierdzonym urządzeniem w innej sieci, bez serwera pośredniczącego. Drogę pomagają znaleźć publiczne serwery STUN i sieć DHT BitTorrenta; widzą one twój adres IP i moment połączenia, nigdy treść. Nie zawsze się udaje: zwykle zawodzi, gdy obie strony są za CGNAT-em operatora, a część sieci Wi-Fi to blokuje. Domyślnie wyłączone.'**
  String get addonInternetBody;

  /// No description provided for @internetAddonExperimental.
  ///
  /// In pl, this message translates to:
  /// **'Eksperymentalne. Działa bezpośrednio między urządzeniami, przebijając dziurę w NAT; udaje się około siedmiu połączeń na dziesięć.'**
  String get internetAddonExperimental;

  /// No description provided for @internetBatteryWarning.
  ///
  /// In pl, this message translates to:
  /// **'Żeby być osiągalnym, to urządzenie nasłuchuje w tle i co kilka minut odświeża swój adres. Zużywa to więcej baterii niż samo Wi-Fi.'**
  String get internetBatteryWarning;

  /// No description provided for @internetPublicAddressLabel.
  ///
  /// In pl, this message translates to:
  /// **'To urządzenie widać pod: {address}'**
  String internetPublicAddressLabel(String address);

  /// No description provided for @internetPublicAddressUnknown.
  ///
  /// In pl, this message translates to:
  /// **'Adres publiczny jeszcze nieznany.'**
  String get internetPublicAddressUnknown;

  /// No description provided for @internetCheckNat.
  ///
  /// In pl, this message translates to:
  /// **'Sprawdź osiągalność'**
  String get internetCheckNat;

  /// No description provided for @internetNatOpen.
  ///
  /// In pl, this message translates to:
  /// **'NAT niezależny od celu: przebicie dziury powinno działać.'**
  String get internetNatOpen;

  /// No description provided for @internetNatSymmetric.
  ///
  /// In pl, this message translates to:
  /// **'NAT symetryczny: przebicie dziury zwykle tu zawodzi.'**
  String get internetNatSymmetric;

  /// No description provided for @internetNatNone.
  ///
  /// In pl, this message translates to:
  /// **'Brak NAT: urządzenie jest osiągalne wprost.'**
  String get internetNatNone;

  /// No description provided for @internetNatUnknown.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się połączyć z serwerami STUN.'**
  String get internetNatUnknown;

  /// No description provided for @addonKeyboardShort.
  ///
  /// In pl, this message translates to:
  /// **'Pisanie z klawiatury komputera'**
  String get addonKeyboardShort;

  /// No description provided for @historyClearedWithTyping.
  ///
  /// In pl, this message translates to:
  /// **'Usunięto wiadomości: {messages}, sesje pisania: {sessions}'**
  String historyClearedWithTyping(int messages, int sessions);

  /// No description provided for @typingHistorySwitch.
  ///
  /// In pl, this message translates to:
  /// **'Zapisuj historię pisania'**
  String get typingHistorySwitch;

  /// No description provided for @typingHistoryHelp.
  ///
  /// In pl, this message translates to:
  /// **'Zapisuje na tym urządzeniu sesje w obu kierunkach: pisanie stąd i pisanie tutaj. Drugie urządzenie prowadzi własną historię według swojego przełącznika. Tekst z pól haseł i pól nieznanego rodzaju zostaje ukryty: zapisuje się sama liczba znaków. Historia leży zaszyfrowana.'**
  String get typingHistoryHelp;

  /// No description provided for @typingHistory.
  ///
  /// In pl, this message translates to:
  /// **'Historia pisania'**
  String get typingHistory;

  /// No description provided for @typingHistoryEntryHelp.
  ///
  /// In pl, this message translates to:
  /// **'Sesje zdalnej klawiatury zapisane na tym urządzeniu: {count}. Wyczyścić je można na ekranie historii.'**
  String typingHistoryEntryHelp(int count);

  /// No description provided for @typingHistoryOff.
  ///
  /// In pl, this message translates to:
  /// **'Zapisywanie historii pisania jest wyłączone. Włącza się je w Ustawieniach, w dodatku „Klawiatura z PC”.'**
  String get typingHistoryOff;

  /// No description provided for @typingHistoryEmptyTitle.
  ///
  /// In pl, this message translates to:
  /// **'Brak historii pisania'**
  String get typingHistoryEmptyTitle;

  /// No description provided for @typingHistoryEmptyBody.
  ///
  /// In pl, this message translates to:
  /// **'Tutaj pojawią się sesje zdalnej klawiatury w obu kierunkach: pisanie stąd na innych urządzeniach i pisanie innych urządzeń tutaj.'**
  String get typingHistoryEmptyBody;

  /// No description provided for @typingHistoryClear.
  ///
  /// In pl, this message translates to:
  /// **'Wyczyść historię pisania'**
  String get typingHistoryClear;

  /// No description provided for @typingHistoryClearTitle.
  ///
  /// In pl, this message translates to:
  /// **'Wyczyścić historię pisania?'**
  String get typingHistoryClearTitle;

  /// No description provided for @typingHistoryClearBody.
  ///
  /// In pl, this message translates to:
  /// **'Znikną wszystkie zapisane sesje pisania. Rozmowy i dziennik aplikacji zostają.'**
  String get typingHistoryClearBody;

  /// No description provided for @typingHistoryCleared.
  ///
  /// In pl, this message translates to:
  /// **'Usunięto sesje pisania: {count}'**
  String typingHistoryCleared(int count);

  /// Sesja, w której to urządzenie pisało na urządzeniu {name}. Forma bezosobowa, bez rodzaju.
  ///
  /// In pl, this message translates to:
  /// **'Pisanie stąd na: {name}'**
  String typingHistoryOutgoing(Object name);

  /// Sesja, w której urządzenie {name} pisało na tym urządzeniu. Forma bezosobowa, bez rodzaju.
  ///
  /// In pl, this message translates to:
  /// **'Pisanie tutaj z: {name}'**
  String typingHistoryIncoming(Object name);

  /// No description provided for @typingHistorySessions.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{{count} sesja} few{{count} sesje} many{{count} sesji} other{{count} sesji}}'**
  String typingHistorySessions(int count);

  /// No description provided for @typingHistoryChars.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{{count} znak} few{{count} znaki} many{{count} znaków} other{{count} znaku}}'**
  String typingHistoryChars(int count);

  /// No description provided for @typingHistoryStarted.
  ///
  /// In pl, this message translates to:
  /// **'Początek'**
  String get typingHistoryStarted;

  /// No description provided for @typingHistoryEnded.
  ///
  /// In pl, this message translates to:
  /// **'Koniec'**
  String get typingHistoryEnded;

  /// No description provided for @typingHistoryDuration.
  ///
  /// In pl, this message translates to:
  /// **'Czas trwania'**
  String get typingHistoryDuration;

  /// No description provided for @typingHistoryCharsLabel.
  ///
  /// In pl, this message translates to:
  /// **'Znaki'**
  String get typingHistoryCharsLabel;

  /// No description provided for @typingHistoryApps.
  ///
  /// In pl, this message translates to:
  /// **'Aplikacje'**
  String get typingHistoryApps;

  /// No description provided for @typingHistoryRequest.
  ///
  /// In pl, this message translates to:
  /// **'Prośba'**
  String get typingHistoryRequest;

  /// No description provided for @typingHistoryEndReason.
  ///
  /// In pl, this message translates to:
  /// **'Powód końca'**
  String get typingHistoryEndReason;

  /// No description provided for @typingHistorySessionId.
  ///
  /// In pl, this message translates to:
  /// **'Identyfikator sesji'**
  String get typingHistorySessionId;

  /// No description provided for @typingHistoryNotEnded.
  ///
  /// In pl, this message translates to:
  /// **'Koniec jeszcze niezapisany'**
  String get typingHistoryNotEnded;

  /// No description provided for @typingHistoryText.
  ///
  /// In pl, this message translates to:
  /// **'Odtworzony tekst'**
  String get typingHistoryText;

  /// No description provided for @typingHistoryTextNote.
  ///
  /// In pl, this message translates to:
  /// **'Tekst odtworzony z klawiszy. Ukryte pola widać jako kropki.'**
  String get typingHistoryTextNote;

  /// No description provided for @typingHistoryNoText.
  ///
  /// In pl, this message translates to:
  /// **'Odtworzony tekst jest pusty.'**
  String get typingHistoryNoText;

  /// No description provided for @typingHistoryTimeline.
  ///
  /// In pl, this message translates to:
  /// **'Przebieg'**
  String get typingHistoryTimeline;

  /// No description provided for @typingHistoryNoEntries.
  ///
  /// In pl, this message translates to:
  /// **'W tej sesji nic nie pisano.'**
  String get typingHistoryNoEntries;

  /// No description provided for @typingHistoryHidden.
  ///
  /// In pl, this message translates to:
  /// **'Ukryty tekst'**
  String get typingHistoryHidden;

  /// No description provided for @typingFieldPassword.
  ///
  /// In pl, this message translates to:
  /// **'pole hasła'**
  String get typingFieldPassword;

  /// No description provided for @typingFieldUnknown.
  ///
  /// In pl, this message translates to:
  /// **'pole nieznanego rodzaju'**
  String get typingFieldUnknown;

  /// No description provided for @typingKeyEnter.
  ///
  /// In pl, this message translates to:
  /// **'Enter'**
  String get typingKeyEnter;

  /// No description provided for @typingKeyBackspace.
  ///
  /// In pl, this message translates to:
  /// **'Backspace'**
  String get typingKeyBackspace;

  /// No description provided for @typingKeyDelete.
  ///
  /// In pl, this message translates to:
  /// **'Delete'**
  String get typingKeyDelete;

  /// No description provided for @typingResultAccepted.
  ///
  /// In pl, this message translates to:
  /// **'Zgoda z karty'**
  String get typingResultAccepted;

  /// No description provided for @typingResultAcceptedAlways.
  ///
  /// In pl, this message translates to:
  /// **'Zgoda z karty, „Nie pytaj więcej”'**
  String get typingResultAcceptedAlways;

  /// No description provided for @typingResultAutomatic.
  ///
  /// In pl, this message translates to:
  /// **'Bez karty: zapamiętana zgoda'**
  String get typingResultAutomatic;

  /// No description provided for @typingResultRejected.
  ///
  /// In pl, this message translates to:
  /// **'Odmowa'**
  String get typingResultRejected;

  /// No description provided for @typingResultNoAnswer.
  ///
  /// In pl, this message translates to:
  /// **'Brak odpowiedzi na karcie'**
  String get typingResultNoAnswer;

  /// No description provided for @typingResultBusy.
  ///
  /// In pl, this message translates to:
  /// **'Zajęte przez inną sesję'**
  String get typingResultBusy;

  /// No description provided for @typingResultNotEnabled.
  ///
  /// In pl, this message translates to:
  /// **'Pisanie wyłączone na urządzeniu odbiorcy'**
  String get typingResultNotEnabled;

  /// No description provided for @typingResultCancelled.
  ///
  /// In pl, this message translates to:
  /// **'Prośba wycofana'**
  String get typingResultCancelled;

  /// No description provided for @typingResultUnreachable.
  ///
  /// In pl, this message translates to:
  /// **'Brak połączenia z urządzeniem'**
  String get typingResultUnreachable;

  /// No description provided for @typingResultOlderPeer.
  ///
  /// In pl, this message translates to:
  /// **'Starsza wersja Chatt po drugiej stronie'**
  String get typingResultOlderPeer;

  /// No description provided for @typingEndStoppedHere.
  ///
  /// In pl, this message translates to:
  /// **'Zakończona na tym urządzeniu'**
  String get typingEndStoppedHere;

  /// No description provided for @typingEndStoppedByPeer.
  ///
  /// In pl, this message translates to:
  /// **'Zakończona przez drugą stronę'**
  String get typingEndStoppedByPeer;

  /// No description provided for @typingEndExpired.
  ///
  /// In pl, this message translates to:
  /// **'Zgoda wygasła'**
  String get typingEndExpired;

  /// No description provided for @typingEndReceiveOff.
  ///
  /// In pl, this message translates to:
  /// **'Wyłączone pisanie na tym urządzeniu'**
  String get typingEndReceiveOff;

  /// No description provided for @typingEndAddonOff.
  ///
  /// In pl, this message translates to:
  /// **'Wyłączony dodatek klawiatury'**
  String get typingEndAddonOff;

  /// No description provided for @typingEndReplaced.
  ///
  /// In pl, this message translates to:
  /// **'Zastąpiona nową sesją'**
  String get typingEndReplaced;

  /// No description provided for @typingEndPeerRemoved.
  ///
  /// In pl, this message translates to:
  /// **'Urządzenie usunięte z listy'**
  String get typingEndPeerRemoved;

  /// No description provided for @typingEndNotAllowed.
  ///
  /// In pl, this message translates to:
  /// **'Zgoda cofnięta w trakcie sesji'**
  String get typingEndNotAllowed;

  /// No description provided for @typingEndLinkLost.
  ///
  /// In pl, this message translates to:
  /// **'Połączenie zerwane'**
  String get typingEndLinkLost;

  /// No description provided for @typingEndAppClosed.
  ///
  /// In pl, this message translates to:
  /// **'Aplikacja zamknięta'**
  String get typingEndAppClosed;

  /// No description provided for @typingStatusTyped.
  ///
  /// In pl, this message translates to:
  /// **'Wpisane'**
  String get typingStatusTyped;

  /// No description provided for @typingStatusNotTyped.
  ///
  /// In pl, this message translates to:
  /// **'Wpisane częściowo albo wcale'**
  String get typingStatusNotTyped;

  /// No description provided for @typingStatusPaused.
  ///
  /// In pl, this message translates to:
  /// **'Wstrzymane: czekała karta z pytaniem'**
  String get typingStatusPaused;

  /// No description provided for @typingStatusRefused.
  ///
  /// In pl, this message translates to:
  /// **'Odrzucone: zgoda już się skończyła'**
  String get typingStatusRefused;

  /// No description provided for @typingStatusUnconfirmed.
  ///
  /// In pl, this message translates to:
  /// **'Bez potwierdzenia odbioru'**
  String get typingStatusUnconfirmed;

  /// No description provided for @typingStatusUnsent.
  ///
  /// In pl, this message translates to:
  /// **'Niewysłane'**
  String get typingStatusUnsent;

  /// No description provided for @dataSection.
  ///
  /// In pl, this message translates to:
  /// **'Dane i diagnostyka'**
  String get dataSection;

  /// No description provided for @exportData.
  ///
  /// In pl, this message translates to:
  /// **'Eksportuj dane'**
  String get exportData;

  /// No description provided for @exportDataHelp.
  ///
  /// In pl, this message translates to:
  /// **'Jeden plik ZIP z wybranymi danymi: rozmowy, urządzenia, ustawienia, historia pisania, dziennik aplikacji i odebrane pliki. Do archiwum albo do analizy w innym programie.'**
  String get exportDataHelp;

  /// No description provided for @exportDataConversations.
  ///
  /// In pl, this message translates to:
  /// **'Rozmowy, urządzenia i ustawienia'**
  String get exportDataConversations;

  /// No description provided for @exportDataCountConversations.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{{count} rozmowa} few{{count} rozmowy} many{{count} rozmów} other{{count} rozmowy}}'**
  String exportDataCountConversations(int count);

  /// No description provided for @exportDataCountDevices.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{{count} urządzenie} few{{count} urządzenia} many{{count} urządzeń} other{{count} urządzenia}}'**
  String exportDataCountDevices(int count);

  /// No description provided for @exportDataFiles.
  ///
  /// In pl, this message translates to:
  /// **'Odebrane pliki'**
  String get exportDataFiles;

  /// Ostrzeżenie w oknie eksportu. parts: both (rozmowy i historia pisania), messages (same rozmowy), typing (sama historia pisania), none (żadna z nich).
  ///
  /// In pl, this message translates to:
  /// **'{parts, select, both{Plik eksportu nie jest zaszyfrowany i zawiera treść wiadomości oraz wpisywany tekst.} messages{Plik eksportu nie jest zaszyfrowany i zawiera treść wiadomości.} typing{Plik eksportu nie jest zaszyfrowany i zawiera wpisywany tekst.} other{Plik eksportu nie jest zaszyfrowany.}} Trzymaj go w bezpiecznym miejscu. Klucze tego urządzenia zostają poza eksportem.'**
  String exportDataWarning(String parts);

  /// No description provided for @exportDataReplaceTitle.
  ///
  /// In pl, this message translates to:
  /// **'Zastąpić plik?'**
  String get exportDataReplaceTitle;

  /// No description provided for @exportDataReplaceBody.
  ///
  /// In pl, this message translates to:
  /// **'Plik {name} już istnieje. Eksport go zastąpi.'**
  String exportDataReplaceBody(Object name);

  /// No description provided for @exportDataReplace.
  ///
  /// In pl, this message translates to:
  /// **'Zastąp'**
  String get exportDataReplace;

  /// No description provided for @exportDataAction.
  ///
  /// In pl, this message translates to:
  /// **'Eksportuj'**
  String get exportDataAction;

  /// No description provided for @exportDataBusy.
  ///
  /// In pl, this message translates to:
  /// **'Eksportuję…'**
  String get exportDataBusy;

  /// No description provided for @exportDataEstimateFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się policzyć danych do eksportu.'**
  String get exportDataEstimateFailed;

  /// No description provided for @exportDataSaved.
  ///
  /// In pl, this message translates to:
  /// **'Eksport zapisany w {where}'**
  String exportDataSaved(Object where);

  /// No description provided for @exportDataDone.
  ///
  /// In pl, this message translates to:
  /// **'Eksport gotowy.'**
  String get exportDataDone;

  /// No description provided for @exportDataFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się wyeksportować danych.'**
  String get exportDataFailed;

  /// No description provided for @exportDataUnsupported.
  ///
  /// In pl, this message translates to:
  /// **'Ten system nie ma gdzie zapisać pliku eksportu.'**
  String get exportDataUnsupported;

  /// No description provided for @exportDataSkipped.
  ///
  /// In pl, this message translates to:
  /// **'Pominięte pliki: {count}'**
  String exportDataSkipped(int count);

  /// No description provided for @appLog.
  ///
  /// In pl, this message translates to:
  /// **'Dziennik aplikacji'**
  String get appLog;

  /// No description provided for @appLogHelp.
  ///
  /// In pl, this message translates to:
  /// **'Zdarzenia sieci, parowania i plików oraz błędy z ostatnich 30 dni, do diagnostyki. Bez treści wiadomości, wpisywanego tekstu i kluczy.'**
  String get appLogHelp;

  /// No description provided for @appLogEntries.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{{count} wpis} few{{count} wpisy} many{{count} wpisów} other{{count} wpisu}}'**
  String appLogEntries(int count);

  /// No description provided for @appLogFilterAll.
  ///
  /// In pl, this message translates to:
  /// **'Wszystko'**
  String get appLogFilterAll;

  /// No description provided for @appLogFilterProblems.
  ///
  /// In pl, this message translates to:
  /// **'Ostrzeżenia i błędy'**
  String get appLogFilterProblems;

  /// No description provided for @appLogEmpty.
  ///
  /// In pl, this message translates to:
  /// **'Dziennik jest pusty.'**
  String get appLogEmpty;

  /// No description provided for @appLogEmptyProblems.
  ///
  /// In pl, this message translates to:
  /// **'Brak ostrzeżeń i błędów.'**
  String get appLogEmptyProblems;

  /// No description provided for @appLogLimit.
  ///
  /// In pl, this message translates to:
  /// **'Widać najnowsze wpisy: {count}. Pełny dziennik jest w eksporcie.'**
  String appLogLimit(int count);

  /// No description provided for @appLogCopy.
  ///
  /// In pl, this message translates to:
  /// **'Kopiuj widoczne wpisy'**
  String get appLogCopy;

  /// No description provided for @appLogExport.
  ///
  /// In pl, this message translates to:
  /// **'Eksportuj dziennik'**
  String get appLogExport;

  /// No description provided for @appLogClear.
  ///
  /// In pl, this message translates to:
  /// **'Wyczyść dziennik'**
  String get appLogClear;

  /// No description provided for @appLogClearTitle.
  ///
  /// In pl, this message translates to:
  /// **'Wyczyścić dziennik aplikacji?'**
  String get appLogClearTitle;

  /// No description provided for @appLogClearBody.
  ///
  /// In pl, this message translates to:
  /// **'Znikną wszystkie wpisy dziennika. Rozmowy i historia pisania zostają.'**
  String get appLogClearBody;

  /// No description provided for @appLogCleared.
  ///
  /// In pl, this message translates to:
  /// **'Usunięto wpisy dziennika: {count}'**
  String appLogCleared(int count);

  /// No description provided for @appLogDetails.
  ///
  /// In pl, this message translates to:
  /// **'Szczegóły'**
  String get appLogDetails;

  /// No description provided for @appLogLevelInfo.
  ///
  /// In pl, this message translates to:
  /// **'Informacja'**
  String get appLogLevelInfo;

  /// No description provided for @appLogLevelWarning.
  ///
  /// In pl, this message translates to:
  /// **'Ostrzeżenie'**
  String get appLogLevelWarning;

  /// No description provided for @appLogLevelError.
  ///
  /// In pl, this message translates to:
  /// **'Błąd'**
  String get appLogLevelError;

  /// No description provided for @shareSendToTitle.
  ///
  /// In pl, this message translates to:
  /// **'Wyślij do'**
  String get shareSendToTitle;

  /// No description provided for @shareFiles.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{{count} plik} few{{count} pliki} many{{count} plików} other{{count} pliku}}'**
  String shareFiles(int count);

  /// No description provided for @shareNoConversations.
  ///
  /// In pl, this message translates to:
  /// **'Nie masz jeszcze żadnej rozmowy. Znajdź urządzenie przyciskiem „W pobliżu”, żeby mu to wysłać.'**
  String get shareNoConversations;

  /// No description provided for @sharePreparing.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{Przygotowuję plik…} few{Przygotowuję {count} pliki…} many{Przygotowuję {count} plików…} other{Przygotowuję {count} pliku…}}'**
  String sharePreparing(int count);

  /// No description provided for @shareDontSend.
  ///
  /// In pl, this message translates to:
  /// **'Nie wysyłaj'**
  String get shareDontSend;

  /// No description provided for @shareNothing.
  ///
  /// In pl, this message translates to:
  /// **'Chatt nie dostał nic do wysłania: ani tekstu, ani pliku, który umie odczytać.'**
  String get shareNothing;

  /// No description provided for @shareSkipped.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{Pominięty {count} plik: Chatt nie przyjmuje plików podanych zwykłą ścieżką.} few{Pominięte {count} pliki: Chatt nie przyjmuje plików podanych zwykłą ścieżką.} many{Pominiętych {count} plików: Chatt nie przyjmuje plików podanych zwykłą ścieżką.} other{Pominięte {count} pliku: Chatt nie przyjmuje plików podanych zwykłą ścieżką.}}'**
  String shareSkipped(int count);

  /// No description provided for @shareFilesMissing.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się wczytać {missing} z {total} udostępnionych plików.'**
  String shareFilesMissing(int missing, int total);

  /// No description provided for @conversationGone.
  ///
  /// In pl, this message translates to:
  /// **'Tej rozmowy już nie ma.'**
  String get conversationGone;
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
