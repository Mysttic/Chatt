import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/material.dart' show IconData, Icons;

import '../../../l10n/app_localizations.dart';

/// Kategoria Ustawień (issue #71). Kolejność wartości jest kolejnością na
/// liście, a [group] mówi, w której karcie kategoria stoi: od Ciebie, przez
/// łączenie z innymi urządzeniami, do samej aplikacji.
enum SettingsSection {
  profile(1, Icons.person_outline),
  connection(2, Icons.lan_outlined),
  backgroundListening(2, Icons.notifications_active_outlined),
  keyboard(2, Icons.keyboard_outlined),
  appearance(3, Icons.palette_outlined),
  privacy(3, Icons.shield_outlined),
  data(3, Icons.storage_outlined),
  updates(3, Icons.system_update_outlined);

  /// Numer karty na liście kategorii, od 1.
  final int group;
  final IconData icon;

  const SettingsSection(this.group, this.icon);

  String title(AppLocalizations l10n) => switch (this) {
    SettingsSection.profile => l10n.profileSection,
    SettingsSection.connection => l10n.connectionSection,
    SettingsSection.backgroundListening => l10n.backgroundListening,
    SettingsSection.keyboard => l10n.keyboardAddon,
    SettingsSection.appearance => l10n.appearance,
    SettingsSection.privacy => l10n.privacy,
    SettingsSection.data => l10n.dataSection,
    SettingsSection.updates => l10n.updates,
  };

  /// Czy kategoria ma na tej platformie jakąkolwiek treść. Nasłuch w tle
  /// to bateria Androida albo start razem z Windowsem; gdzie indziej
  /// proces żyje tak długo jak okno i nie ma czego ustawiać.
  bool dostepnaNa(TargetPlatform platforma) => switch (this) {
    SettingsSection.backgroundListening =>
      platforma == TargetPlatform.android ||
          platforma == TargetPlatform.windows,
    _ => true,
  };

  /// Karty listy kategorii na [platforma], w kolejności. Kategorie bez
  /// treści wypadają, a karta bez kategorii razem z nimi. Jedyne źródło
  /// kolejności: lista, dwa panele i testy biorą ją stąd.
  static List<List<SettingsSection>> grupy(TargetPlatform platforma) {
    final karty = <List<SettingsSection>>[];
    for (final kategoria in values) {
      if (!kategoria.dostepnaNa(platforma)) continue;
      if (karty.isEmpty || karty.last.first.group != kategoria.group) {
        karty.add([kategoria]);
      } else {
        karty.last.add(kategoria);
      }
    }
    return karty;
  }

  /// Pierwsza kategoria na liście: otwiera się w prawym panelu, dopóki
  /// nikt nic nie wybrał.
  static SettingsSection pierwszaNa(TargetPlatform platforma) =>
      grupy(platforma).first.first;
}

/// System, na którym aplikacja naprawdę działa, odczytany z `dart:io`.
/// O treści kategorii decyduje bateria Androida i rejestr Windows, a testy
/// podmieniają platformę motywu tylko do wyglądu.
TargetPlatform biezacaPlatforma() {
  if (Platform.isAndroid) return TargetPlatform.android;
  if (Platform.isWindows) return TargetPlatform.windows;
  if (Platform.isIOS) return TargetPlatform.iOS;
  if (Platform.isMacOS) return TargetPlatform.macOS;
  if (Platform.isLinux) return TargetPlatform.linux;
  return TargetPlatform.fuchsia;
}
