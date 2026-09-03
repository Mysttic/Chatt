import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../core/env.dart';
import '../core/secret_store.dart';
import 'db.dart';

/// Otwarta baza razem z tym, co warto o niej powiedzieć użytkownikowi.
class OpenedDatabase {
  final QueryExecutor executor;

  /// Czy klucz bazy leży na dysku owinięty przez system (patrz [DatabaseKey]).
  final bool keyProtected;

  /// Czy przy tym starcie przepisaliśmy starą, jawną bazę na zaszyfrowaną.
  final bool migrated;

  const OpenedDatabase({
    required this.executor,
    required this.keyProtected,
    required this.migrated,
  });
}

/// Otwiera bazę aplikacji: zaszyfrowaną kluczem z [DatabaseKey], a wcześniej
/// przepisuje na zaszyfrowaną tę jawną, jeśli została po starszej wersji.
Future<OpenedDatabase> openAppDatabase() async {
  final dir = ChattEnv.dataDir ?? (await getApplicationDocumentsDirectory()).path;
  Directory(dir).createSync(recursive: true);

  // Dwie nazwy, bo tak było przed szyfrowaniem: `driftDatabase(name: 'chatt')`
  // zakładał `chatt.sqlite` w dokumentach, a tryb testowy z `ChattEnv.dataDir`
  // — `chatt.db`. Zmiana nazwy zgubiłaby istniejącą historię.
  final file = File(
    p.join(dir, ChattEnv.dataDir != null ? 'chatt.db' : 'chatt.sqlite'),
  );

  final key = await DatabaseKey.load(dir);
  final migrated = await migrateToEncrypted(file, key);

  return OpenedDatabase(
    executor: NativeDatabase.createInBackground(file, setup: setupKey(key)),
    keyProtected: key.protected,
    migrated: migrated,
  );
}

/// Funkcja podawania hasła bazie. Musi wykonać się przed pierwszym odczytem,
/// inaczej sqlite zobaczy zaszyfrowane strony i uzna plik za uszkodzony.
///
/// Domyka się nad zwykłym napisem, więc drift może ją przesłać do izolatu,
/// w którym trzyma połączenie.
void Function(raw.Database) setupKey(DatabaseKey key) {
  final passphrase = key.passphrase.replaceAll("'", "''");
  return (db) {
    db.execute("PRAGMA key = '$passphrase';");
    assert(
      db.select('PRAGMA cipher;').isNotEmpty,
      'Build bez SQLite3MultipleCiphers: PRAGMA key nic nie robi, '
      'a baza zapisze się jawnym tekstem.',
    );
  };
}

/// Przepisuje jawną bazę [file] na zaszyfrowaną tym samym kluczem, zachowując
/// całą historię. Zwraca `true`, gdy było co przepisywać.
///
/// Szyfrowanie działa na stronach pliku, więc istniejącej bazy nie da się
/// „dokluczyć" w miejscu: trzeba założyć nową i przenieść wiersze. Kopia
/// powstaje obok, a oryginał znika dopiero po jej domknięciu — przerwanie
/// prądu w połowie zostawia więc albo starą bazę, albo nową, nigdy pół.
Future<bool> migrateToEncrypted(File file, DatabaseKey key) async {
  if (!file.existsSync() || file.lengthSync() == 0) return false;
  if (!_isPlaintext(file)) return false;

  final target = File('${file.path}.enc');
  if (target.existsSync()) target.deleteSync();

  final source = ChattDb(NativeDatabase(file));
  final destination = ChattDb(NativeDatabase(target, setup: setupKey(key)));
  try {
    // Odczyt ze źródła dociąga je najpierw do bieżącego schematu, więc do
    // kopiowania obie bazy mają identyczny układ kolumn.
    final settingsRows = await source.select(source.settings).get();
    final peerRows = await source.select(source.peers).get();
    final conversationRows = await source.select(source.conversations).get();
    final messageRows = await source.select(source.messages).get();

    await destination.batch((batch) {
      batch.insertAll(destination.settings, settingsRows.map((r) => r.toCompanion(false)));
      batch.insertAll(destination.peers, peerRows.map((r) => r.toCompanion(false)));
      batch.insertAll(
          destination.conversations, conversationRows.map((r) => r.toCompanion(false)));
      batch.insertAll(destination.messages, messageRows.map((r) => r.toCompanion(false)));
    });
  } finally {
    await source.close();
    await destination.close();
  }

  _deleteWithJournals(file);
  target.renameSync(file.path);
  return true;
}

/// Czy plik da się otworzyć bez hasła. Zaszyfrowana baza wywala się na
/// pierwszym odczycie („file is not a database"), więc pytanie o nagłówek
/// nie jest potrzebne.
bool _isPlaintext(File file) {
  final db = raw.sqlite3.open(file.path);
  try {
    db.select('SELECT count(*) FROM sqlite_master;');
    return true;
  } catch (_) {
    return false;
  } finally {
    db.close();
  }
}

void _deleteWithJournals(File file) {
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final f = File('${file.path}$suffix');
    if (f.existsSync()) f.deleteSync();
  }
}
