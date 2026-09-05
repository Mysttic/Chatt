import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;

/// Nasłuch w tle na Androidzie. Zwykły proces aplikacji ginie zaraz po
/// zamknięciu okna (zmierzone: wiadomość wysłana do zamkniętej aplikacji nie
/// dochodzi wcale), więc trzyma go usługa pierwszoplanowa ze stałym
/// powiadomieniem. Na desktopie nie ma czego trzymać: proces żyje, dopóki
/// okno jest otwarte.
class BackgroundService {
  static const MethodChannel _channel = MethodChannel('chatt/background');

  /// Zwraca true, gdy nasłuch w tle faktycznie ruszył. Teksty stałego
  /// powiadomienia przychodzą z aplikacji, żeby były w jej języku.
  static Future<bool> start({
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('start', {
            'title': title,
            'body': body,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // Brak kanału (testy, desktop), nie ma czego zatrzymywać.
    }
  }

  /// Czy Android nadal usypia aplikację. Usługa pierwszoplanowa chroni proces
  /// przed ubiciem, ale w trybie Doze system potrafi mimo to odciąć jej sieć:
  /// dopiero wyjątek od optymalizacji baterii to zdejmuje. Poza Androidem
  /// nie ma czego usypiać, więc false.
  static Future<bool> batteryOptimized() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('batteryOptimized') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Otwiera systemowe okienko z pytaniem o wyjątek. Zwraca tylko tyle, czy
  /// okienko w ogóle się pokazało. Odpowiedź użytkownika czytamy potem
  /// przez [batteryOptimized].
  static Future<bool> requestBatteryExemption() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestBatteryExemption') ??
          false;
    } catch (_) {
      return false;
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
      // Brak kanału albo zgody na powiadomienia: trudno, wiadomość i tak
      // jest już zapisana.
    }
  }
}
