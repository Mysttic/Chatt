import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Klucz bazy leży na dysku, ale systemowy schowek nie chce go odwinąć.
///
/// Materiał do odwijania nigdy nie opuszcza urządzenia, więc przywrócona kopia
/// zapasowa, przenosiny na nowy telefon albo wyczyszczony Keystore zostawiają
/// plik z kluczem bez niczego, czym dałoby się go otworzyć. Historii nie da
/// się wtedy odzyskać żadnym sposobem i aplikacja ma to powiedzieć wprost,
/// zamiast odmawiać startu w kółko.
class DatabaseKeyUnavailable implements Exception {
  final String keyPath;

  const DatabaseKeyUnavailable(this.keyPath);

  @override
  String toString() =>
      'The database key in $keyPath cannot be unwrapped: the system keystore '
      'no longer holds the material it was wrapped with. This happens after '
      'restoring a backup, moving to another device, or clearing the '
      'keystore. The conversation history is unreadable from here on.';
}

/// Dostęp do systemowego schowka na sekrety: Android Keystore i Windows DPAPI.
///
/// Kanał robi jedno: owija i odwija bajty kluczem, którego aplikacja nigdy nie
/// widzi. Na Androidzie leży on w Keystore (sprzętowym, jeśli urządzenie ma
/// TEE), na Windowsie owijaniem zajmuje się DPAPI kluczem konta użytkownika.
/// Gdzie zapisać wynik, decyduje już Dart (patrz [DatabaseKey]).
class SecretStore {
  static const _channel = MethodChannel('chatt/sekrety');

  /// Owija [data] kluczem systemowym. `null` znaczy „ta platforma nie ma
  /// schowka albo schowek odmówił", a wywołujący ma wtedy zdecydować, czy to
  /// błąd, czy praca dalej bez ochrony.
  static Future<Uint8List?> protect(List<int> data) =>
      _call('protect', data);

  /// Odwraca [protect]. `null` znaczy, że blobu nie da się odwinąć, klucz
  /// systemowy zniknął (reinstalacja, przywrócenie kopii na inne urządzenie,
  /// wyczyszczenie Keystore) albo blob jest uszkodzony.
  static Future<Uint8List?> unprotect(List<int> data) =>
      _call('unprotect', data);

  static Future<Uint8List?> _call(String method, List<int> data) async {
    try {
      return await _channel.invokeMethod<Uint8List>(method, {
        'data': Uint8List.fromList(data),
      });
    } on MissingPluginException {
      // Platforma bez implementacji kanału (testy, Linux, macOS).
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// Hasło do bazy: 32 losowe bajty, trzymane na dysku owinięte przez
/// [SecretStore] i podawane bazie jako `PRAGMA key`.
///
/// Plik ma jeden bajt nagłówka mówiący, czy zawartość jest owinięta. Dzięki
/// temu urządzenie, na którym schowek systemowy nie zadziałał, da się później
/// rozpoznać i naprawić, zamiast zgadywać przy odczycie.
class DatabaseKey {
  /// Hasło podawane do `PRAGMA key` (base64 z 32 bajtów).
  final String passphrase;

  /// Czy hasło leży na dysku owinięte kluczem systemowym. `false` znaczy, że
  /// baza jest zaszyfrowana, ale klucz do niej leży obok niej jawnie, czyli
  /// chroni przed podejrzeniem pliku bazy, a nie przed kimś, kto skopiuje
  /// cały katalog aplikacji. Użytkownik ma to zobaczyć w ustawieniach.
  final bool protected;

  const DatabaseKey({required this.passphrase, required this.protected});

  static const _wrapped = 1;
  static const _plain = 0;

  static String fileFor(String dir) => p.join(dir, 'chatt.key');

  /// Wczytuje hasło z [dir] albo losuje nowe przy pierwszym uruchomieniu.
  ///
  /// Rzuca [StateError], gdy plik jest, ale nie da się go odwinąć: to znaczy
  /// bazę, której nikt już nie odczyta, i zamiana jej po cichu na pustą
  /// skasowałaby całą historię bez pytania.
  static Future<DatabaseKey> load(String dir) async {
    final file = File(fileFor(dir));
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      if (bytes.isNotEmpty) {
        final body = bytes.sublist(1);
        if (bytes.first == _plain) {
          return DatabaseKey(
            passphrase: utf8.decode(body),
            protected: false,
          );
        }
        final odwiniete = await SecretStore.unprotect(body);
        if (odwiniete == null) throw DatabaseKeyUnavailable(file.path);
        return DatabaseKey(passphrase: utf8.decode(odwiniete), protected: true);
      }
    }

    final random = Random.secure();
    final losowe = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final passphrase = base64.encode(losowe);
    final owiniete = await SecretStore.protect(utf8.encode(passphrase));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync([
      owiniete == null ? _plain : _wrapped,
      ...(owiniete ?? utf8.encode(passphrase)),
    ], flush: true);
    return DatabaseKey(passphrase: passphrase, protected: owiniete != null);
  }
}
