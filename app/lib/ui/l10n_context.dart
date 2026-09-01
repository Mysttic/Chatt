import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// Skrót do tłumaczeń: `context.l10n.zapisz` zamiast
/// `AppLocalizations.of(context).zapisz` w każdym widgecie.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
