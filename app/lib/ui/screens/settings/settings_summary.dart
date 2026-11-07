import 'package:flutter/foundation.dart' show TargetPlatform, immutable;

import '../../../core/version.dart' as wersja;
import '../../../data/db.dart' show AppLanguage, AppStyle, AppTheme;
import '../../../l10n/app_localizations.dart';
import '../../../network/protocol.dart' show defaultTcpPort;
import '../../backgrounds.dart';
import 'settings_section.dart';

// Streszczenia pod nazwami kategorii (issue #71) mówią, co jest ustawione.
// Czyste funkcje bez BuildContext, więc dokładne napisy w obu językach
// sprawdza test bez widgetów.

/// Trzecia linia wiersza kategorii: nowość w kolorze akcentu albo kłopot
/// ([problem]) w kolorze ostrzeżenia.
typedef LiniaKategorii = ({String tekst, bool problem});

/// Wszystko, z czego powstają streszczenia: wiersz ustawień z bazy, stan
/// dodatków z serwisów i to, co ekran Ustawień pyta system (bateria,
/// autostart). Zwykły obiekt, który ekran składa przy każdej budowie listy.
/// Wartości domyślne to wartości domyślne bazy i świeżej instalacji.
@immutable
class StanUstawien {
  final TargetPlatform platforma;

  final String nickname;
  final String welcomeMessage;

  /// Preferowany port z bazy. Port, na którym serwer naprawdę wstał, stoi
  /// w kategorii Połączenie w „To urządzenie”.
  final int tcpPort;

  final AppStyle style;
  final AppTheme theme;

  /// Indeks tła w [chattBackgrounds]; 0 to „Bez tła”.
  final int background;
  final AppLanguage language;

  /// Zero: „Nie kasuj”.
  final int retentionDays;
  final bool linkPreviews;
  final bool updateChecks;

  /// Sieć lokalna jako droga. Ma znaczenie tylko przy włączonym dodatku
  /// Bluetooth: bez niego sieć chodzi zawsze.
  final bool wifiEnabled;

  final bool bluetoothAddon;
  final bool bluetoothRunning;
  final bool bluetoothRadioOn;
  final bool bluetoothGranted;
  final bool internetAddon;

  /// Droga internetowa naprawdę chodzi (gniazdo otwarte).
  final bool internetRunning;

  final bool keyboardAddon;
  final bool remoteInputReceive;
  final bool remoteInputReceiveSupported;
  final bool typingHistory;
  final int typingSessions;

  /// Numer nowego wydania, gdy jakieś czeka.
  final String? availableVersion;
  final String appVersion;

  final bool keyProtected;
  final bool discoveryListening;

  /// Android: czy system nadal usypia Chatta.
  final bool batteryOptimized;

  /// Windows: czy Chatt startuje razem z systemem.
  final bool autostart;

  const StanUstawien({
    required this.platforma,
    this.nickname = '',
    this.welcomeMessage = '',
    this.tcpPort = defaultTcpPort,
    this.style = AppStyle.cisza,
    this.theme = AppTheme.system,
    this.background = 0,
    this.language = AppLanguage.english,
    this.retentionDays = 0,
    this.linkPreviews = false,
    this.updateChecks = false,
    this.wifiEnabled = true,
    this.bluetoothAddon = false,
    this.bluetoothRunning = false,
    this.bluetoothRadioOn = false,
    this.bluetoothGranted = false,
    this.internetAddon = false,
    this.internetRunning = false,
    this.keyboardAddon = false,
    this.remoteInputReceive = false,
    this.remoteInputReceiveSupported = true,
    this.typingHistory = true,
    this.typingSessions = 0,
    this.availableVersion,
    this.appVersion = wersja.appVersion,
    this.keyProtected = true,
    this.discoveryListening = true,
    this.batteryOptimized = false,
    this.autostart = false,
  });

  /// Sieć lokalna działa: zawsze bez dodatku Bluetooth, z dodatkiem wtedy,
  /// gdy nikt jej nie wyłączył.
  bool get lanActive => !bluetoothAddon || wifiEnabled;
}

/// Fakty w streszczeniu dzieli kropka w środku, wyliczenia przecinek.
const _kropka = ' · ';

String _fakty(Iterable<String> fakty) =>
    fakty.where((f) => f.isNotEmpty).join(_kropka);

/// Streszczenie stanu kategorii: jedna linia faktów, które pokazuje wiersz
/// pod nazwą kategorii.
String streszczenie(
  SettingsSection kategoria,
  StanUstawien stan,
  AppLocalizations t,
) {
  switch (kategoria) {
    case SettingsSection.profile:
      return stan.welcomeMessage.isEmpty
          ? stan.nickname
          : t.settingsSummaryProfile(stan.nickname, stan.welcomeMessage);
    case SettingsSection.connection:
      final drogi = [
        if (stan.lanActive) t.transportWifi,
        if (stan.bluetoothAddon) t.transportBluetooth,
        if (stan.internetAddon) t.transportInternet,
      ];
      return _fakty([_wyliczenie(drogi, t), t.listeningPort(stan.tcpPort)]);
    case SettingsSection.backgroundListening:
      return switch (stan.platforma) {
        TargetPlatform.android =>
          stan.batteryOptimized
              ? t.settingsSummaryBatteryDozed
              : t.settingsSummaryBatteryOk,
        TargetPlatform.windows =>
          stan.autostart
              ? t.settingsSummaryAutostartOn
              : t.settingsSummaryAutostartOff,
        _ => '',
      };
    case SettingsSection.keyboard:
      if (!stan.keyboardAddon) {
        return _fakty([
          t.settingsSummaryOff,
          if (stan.typingSessions > 0)
            t.settingsSummaryTypingSessions(stan.typingSessions),
        ]);
      }
      return _fakty([
        t.settingsSummaryOn,
        if (stan.remoteInputReceiveSupported)
          stan.remoteInputReceive
              ? t.settingsSummaryReceiveOn
              : t.settingsSummaryReceiveOff,
        stan.typingHistory
            ? t.settingsSummaryHistoryOn
            : t.settingsSummaryHistoryOff,
      ]);
    case SettingsSection.appearance:
      final tlo =
          stan.background > 0 && stan.background < chattBackgrounds.length
          ? chattBackgrounds[stan.background].label(t)
          : '';
      return _fakty([
        _styl(stan.style, t),
        switch (stan.theme) {
          AppTheme.system => t.settingsSummaryThemeSystem,
          AppTheme.light => t.settingsSummaryThemeLight,
          AppTheme.dark => t.settingsSummaryThemeDark,
        },
        tlo,
        _jezyk(stan.language, t),
      ]);
    case SettingsSection.privacy:
      return _fakty([
        stan.retentionDays == 0
            ? t.retentionNever
            : t.settingsSummaryRetention(stan.retentionDays),
        stan.linkPreviews
            ? t.settingsSummaryPreviewsOn
            : t.settingsSummaryPreviewsOff,
      ]);
    case SettingsSection.data:
      return t.settingsSummaryData;
    case SettingsSection.updates:
      return _fakty([
        t.settingsSummaryVersion(stan.appVersion),
        stan.updateChecks
            ? t.settingsSummaryChecksOn
            : t.settingsSummaryChecksOff,
      ]);
  }
}

/// Trzecia linia: nowość albo kłopot, który widać bez otwierania
/// kategorii. Przy kilku kłopotach naraz pokazuje najpoważniejszy.
LiniaKategorii? linia(
  SettingsSection kategoria,
  StanUstawien stan,
  AppLocalizations t,
) {
  LiniaKategorii problem(String tekst) => (tekst: tekst, problem: true);
  switch (kategoria) {
    case SettingsSection.connection:
      // Te same warunki co ostrzeżenia w treści kategorii: karta Bluetooth
      // i karta skanów.
      // Bez sieci lokalnej i bez radia zostaje tylko internet. Gdy i on nie
      // chodzi, to urządzenie z nikim się nie skontaktuje.
      if (stan.bluetoothAddon &&
          !stan.wifiEnabled &&
          !stan.bluetoothRunning &&
          !stan.internetRunning) {
        return problem(t.settingsSummaryNobodyReached);
      }
      if (!stan.discoveryListening) {
        return problem(t.settingsSummaryOthersWontFind);
      }
      // Działające radio ma i zasilanie, i zgodę. Kłopot z radiem liczy się
      // więc dopiero przy stojącym dodatku: stan z systemu bywa sprzed
      // chwili.
      if (stan.bluetoothAddon && !stan.bluetoothRunning) {
        if (!stan.bluetoothRadioOn) {
          return problem(t.transportBluetoothRadioOff);
        }
        if (!stan.bluetoothGranted) {
          return problem(t.transportBluetoothNoPermission);
        }
      }
      return null;
    case SettingsSection.backgroundListening:
      return stan.platforma == TargetPlatform.android && stan.batteryOptimized
          ? problem(t.settingsSummaryBatteryWarning)
          : null;
    case SettingsSection.privacy:
      return stan.keyProtected
          ? null
          : problem(t.settingsSummaryKeyUnprotected);
    case SettingsSection.updates:
      final wersja = stan.availableVersion;
      return wersja == null
          ? null
          : (tekst: t.updateAvailable(wersja), problem: false);
    case SettingsSection.profile:
    case SettingsSection.keyboard:
    case SettingsSection.appearance:
    case SettingsSection.data:
      return null;
  }
}

/// „Sieć lokalna”, „Sieć lokalna i Bluetooth”, „Sieć lokalna, Bluetooth
/// i Internet”.
String _wyliczenie(List<String> elementy, AppLocalizations t) =>
    switch (elementy.length) {
      0 => '',
      1 => elementy.single,
      _ => t.settingsSummaryAnd(
        elementy.sublist(0, elementy.length - 1).join(', '),
        elementy.last,
      ),
    };

String _styl(AppStyle styl, AppLocalizations t) => switch (styl) {
  AppStyle.cisza => t.styleCisza,
  AppStyle.precyzja => t.stylePrecyzja,
  AppStyle.cieplo => t.styleCieplo,
};

/// Język wewnątrz zdania („polski”, „English”). Systemowy wypada z linii,
/// tak jak „Bez tła”: nic nie wybrano.
String _jezyk(AppLanguage jezyk, AppLocalizations t) => switch (jezyk) {
  AppLanguage.system => '',
  AppLanguage.polish => t.settingsSummaryLanguagePolish,
  AppLanguage.english => t.settingsSummaryLanguageEnglish,
};
