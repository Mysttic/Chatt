import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:chatt/data/db.dart';

/// Baza potrafi mieć układ tabel nowszy niż własny `user_version`: proces ginie
/// między ALTER TABLE a zapisem licznika i zostaje tak na zawsze. Migracja
/// ruszała wtedy od nowa i wywalała się na „duplicate column name" przed
/// pierwszą klatką, czyli w miejscu, którego nie widać.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('kolumny są, licznik wersji został w tyle, baza i tak się otwiera',
      () async {
    final katalog = Directory.systemTemp.createTempSync('chatt-migracja');
    addTearDown(() => katalog.deleteSync(recursive: true));
    final plik = File(p.join(katalog.path, 'chatt.db'));

    // Pełny, bieżący schemat i wiersz, po którym poznamy, że historia została.
    final pierwsza = ChattDb(NativeDatabase(plik));
    await pierwsza.upsertPeer(
      guid: 'guid-1',
      name: 'Alicja',
      welcomeMessage: '',
      host: '192.168.0.2',
      port: 47780,
    );
    await pierwsza.close();

    // Cofamy sam licznik. Kolumny `alias` i `auto_accept` zostają na miejscu,
    // więc to dokładnie ten stan, który zabijał aplikację przy starcie.
    final surowa = raw.sqlite3.open(plik.path);
    surowa.execute('PRAGMA user_version = 8;');
    surowa.close();

    final druga = ChattDb(NativeDatabase(plik));
    addTearDown(druga.close);
    final peers = await druga.allPeers();

    expect(peers, hasLength(1));
    expect(peers.single.name, 'Alicja');
    expect(peers.single.alias, isNull);
    expect(peers.single.autoAccept, isFalse);
  });
}
