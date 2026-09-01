import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;

/// Nasłuch w tle na Androidzie. Zwykły proces aplikacji ginie zaraz po
/// zamknięciu okna (zmierzone: wiadomość wysłana do zamkniętej aplikacji nie
/// dochodzi wcale), więc trzyma go usługa pierwszoplanowa ze stałym
/// powiadomieniem. Na desktopie nie ma czego trzymać: proces żyje, dopóki
/// okno jest otwarte.
class BackgroundService {
  static const MethodChannel _channel = MethodChannel('chatt/background');

  /// Zwraca true, gdy nasłuch w tle faktycznie ruszył.
  static Future<bool> start() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // Brak kanału (testy, desktop) — nie ma czego zatrzymywać.
    }
  }

  /// Powiadomienie o wiadomości, która przyszła przy zamkniętym oknie.
  /// [id] jest stałe dla rozmowy, więc kolejne wiadomości od tej samej osoby
  /// podmieniają powiadomienie zamiast mnożyć je w szufladzie.
  static Future<void> notifyMessage({
    required String title,
    required String body,
    required int id,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('notify', {
        'title': title,
        'body': body,
        'id': id,
      });
    } catch (_) {
      // Brak kanału albo zgody na powiadomienia — trudno, wiadomość i tak
      // jest już zapisana.
    }
  }
}
