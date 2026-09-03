import 'dart:io';

import 'package:flutter/services.dart';

/// Uruchamianie aplikacji razem z systemem. Na Windowsie to wpis w rejestrze
/// użytkownika (`HKCU\...\CurrentVersion\Run`), zakładany przez kanał
/// `chatt/autostart` — patrz `windows/runner/chatt_autostart.cpp`.
///
/// Androida to nie dotyczy: tam ciągłość nasłuchu załatwia usługa
/// pierwszoplanowa, a nie autostart.
class Autostart {
  static const _channel = MethodChannel('chatt/autostart');

  static bool get supported => Platform.isWindows;

  /// Czy wpis autostartu istnieje. `false` także wtedy, gdy nie da się tego
  /// sprawdzić — lepiej pokazać przełącznik wyłączony niż skłamać.
  static Future<bool> enabled() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('get') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Zakłada albo kasuje wpis. Zwraca `true`, gdy się udało.
  static Future<bool> setEnabled(bool value) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('set', {'enabled': value}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
