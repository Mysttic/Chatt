import 'dart:ui' show Locale, PlatformDispatcher;

import '../data/db.dart';
import '../l10n/app_localizations.dart';

/// Wszystko, co aplikacja wie o dostępnych językach, w jednym miejscu.
///
/// Dodanie kolejnego języka to: nowy plik `lib/l10n/app_XX.arb`, nowa wartość
/// w [AppLanguage] (na KOŃCU listy — w bazie siedzi indeks) i po jednej
/// gałęzi w [locale] oraz [label]. Reszta (lista w ustawieniach, wybór
/// locale w MaterialApp, język powiadomień usługi) idzie za tym sama.
extension AppLanguageX on AppLanguage {
  /// null = idziemy za językiem systemu.
  Locale? get locale => switch (this) {
        AppLanguage.system => null,
        AppLanguage.polish => const Locale('pl'),
        AppLanguage.english => const Locale('en'),
      };

  String label(AppLocalizations l10n) => switch (this) {
        AppLanguage.system => l10n.languageSystem,
        AppLanguage.polish => l10n.languagePolish,
        AppLanguage.english => l10n.languageEnglish,
      };

  /// Konkretny język do tekstów spoza drzewa widgetów (powiadomienie usługi
  /// w tle). Dla `system` bierzemy język systemu, ale tylko jeśli mamy dla
  /// niego tłumaczenie — inaczej angielski.
  Locale get effectiveLocale {
    final wybrany = locale;
    if (wybrany != null) return wybrany;
    final systemowy = PlatformDispatcher.instance.locale.languageCode;
    return AppLocalizations.supportedLocales
            .any((l) => l.languageCode == systemowy)
        ? Locale(systemowy)
        : const Locale('en');
  }
}
