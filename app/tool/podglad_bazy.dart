// Podgląd bazy aplikacji: liczy wiersze i mówi, czy plik jest jawny.
// Uruchomienie: dart run tool/podglad_bazy.dart [ścieżka] [hasło]
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  // Bez ścieżki: baza aplikacji na Windowsie, `chatt.sqlite` w Dokumentach.
  final path = args.isNotEmpty
      ? args.first
      : '${Platform.environment['USERPROFILE'] ?? '.'}\\Documents\\chatt.sqlite';
  if (!File(path).existsSync()) {
    print('Brak pliku $path');
    return;
  }

  final db = sqlite3.open(path);
  if (args.length > 1) db.execute("PRAGMA key = '${args[1]}';");

  try {
    for (final table in ['settings', 'peers', 'conversations', 'messages']) {
      print('$table: ${db.select('SELECT count(*) c FROM $table').single['c']}');
    }
    print(db.select('SELECT id, nickname, device_guid FROM settings'));
    print(db.select('SELECT guid, name, verified FROM peers'));
    print(db.select('SELECT message_guid, substr(body,1,40) b FROM messages '
        'ORDER BY id LIMIT 5'));
    print('user_version: ${db.select('PRAGMA user_version').single}');
  } catch (error) {
    print('Nie da się odczytać: $error');
  } finally {
    db.close();
  }
}
