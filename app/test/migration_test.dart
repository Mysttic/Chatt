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

  /// Schemat 12 dokłada Bluetooth. Wersja 6 wyczyściła kiedyś listę urządzeń
  /// i całą historię; to się nie ma prawa powtórzyć, bo migracja jest
  /// praktycznie nieodwracalna u użytkownika. Tu jest na to dowód: baza
  /// sprzed zmiany otwiera się z rozmówcą, jego adresem, potwierdzeniem
  /// tożsamości i wiadomościami na miejscu.
  test('przejście na schemat 12 nie rusza niczego, co już było w bazie',
      () async {
    final katalog = Directory.systemTemp.createTempSync('chatt-migracja-12');
    addTearDown(() => katalog.deleteSync(recursive: true));
    final plik = File(p.join(katalog.path, 'chatt.db'));

    final pierwsza = ChattDb(NativeDatabase(plik));
    final peer = await pierwsza.upsertPeer(
      guid: 'guid-1',
      name: 'Alicja',
      welcomeMessage: 'cześć',
      host: '192.168.0.2',
      port: 47780,
    );
    await pierwsza.setPeerVerified(peer.id, true);
    final rozmowa = await pierwsza.ensureConversation(peer.id);
    await pierwsza.insertOutgoing(
      conversationId: rozmowa,
      messageGuid: 'wiadomosc-1',
      body: 'wiadomość sprzed migracji',
    );
    // Wiersz ustawień też musi przejść: nowe kolumny dochodzą do istniejącego
    // wiersza i biorą wartości domyślne.
    await pierwsza.ensureSettings(
      identityFactory: () async => ('klucz', 'guid-ja'),
      defaultNickname: 'Ja',
      defaultPort: 47777,
    );
    await pierwsza.close();

    // Baza jak sprzed zmiany: kolumny Bluetootha znikają, licznik wersji
    // wraca na 11. Tak wygląda plik użytkownika po aktualizacji aplikacji.
    final surowa = raw.sqlite3.open(plik.path);
    surowa.execute('ALTER TABLE peers DROP COLUMN bt_address;');
    surowa.execute('ALTER TABLE peers DROP COLUMN last_protocol;');
    surowa.execute('ALTER TABLE settings DROP COLUMN wifi_enabled;');
    surowa.execute('ALTER TABLE settings DROP COLUMN bluetooth_enabled;');
    surowa.execute('PRAGMA user_version = 11;');
    surowa.close();

    final druga = ChattDb(NativeDatabase(plik));
    addTearDown(druga.close);

    final po = await druga.allPeers();
    expect(po, hasLength(1), reason: 'rozmówca nie może zniknąć');
    expect(po.single.name, 'Alicja');
    expect(po.single.host, '192.168.0.2');
    expect(po.single.port, 47780);
    expect(po.single.verified, isTrue,
        reason: 'potwierdzona tożsamość zostaje potwierdzona');
    // Nowe kolumny są puste: o drodze przez radio nic jeszcze nie wiemy.
    expect(po.single.btAddress, isNull);
    expect(po.single.lastProtocol, isNull);

    final wiadomosci = await druga.watchMessages(rozmowa).first;
    expect(wiadomosci, hasLength(1));
    expect(wiadomosci.single.body, 'wiadomość sprzed migracji');

    // Po aktualizacji dodatek Bluetooth stoi wyłączony, a sieć włączona.
    final ustawienia = await druga.getSettings();
    expect(ustawienia, isNotNull);
    expect(ustawienia!.nickname, 'Ja');
    expect(ustawienia.bluetoothEnabled, isFalse,
        reason: 'aktualizacja nie włącza dodatku sama');
    expect(ustawienia.wifiEnabled, isTrue);
  });

  /// Schemat 13 dokłada dodatek klawiatury. Ten sam dowód co przy 12: baza
  /// sprzed zmiany otwiera się z całą zawartością, a trzy nowe przełączniki
  /// stoją wyłączone: pisanie na urządzeniu włącza wyłącznie użytkownik.
  test('przejście na schemat 13 nie rusza danych i nie włącza klawiatury',
      () async {
    final katalog = Directory.systemTemp.createTempSync('chatt-migracja-13');
    addTearDown(() => katalog.deleteSync(recursive: true));
    final plik = File(p.join(katalog.path, 'chatt.db'));

    final pierwsza = ChattDb(NativeDatabase(plik));
    final peer = await pierwsza.upsertPeer(
      guid: 'guid-1',
      name: 'Alicja',
      welcomeMessage: 'cześć',
      host: '192.168.0.2',
      port: 47780,
      btAddress: 'AA:BB:CC:DD:EE:FF',
    );
    await pierwsza.setPeerVerified(peer.id, true);
    await pierwsza.setPeerAutoAccept(peer.id, true);
    final rozmowa = await pierwsza.ensureConversation(peer.id);
    await pierwsza.insertOutgoing(
      conversationId: rozmowa,
      messageGuid: 'wiadomosc-1',
      body: 'wiadomość sprzed migracji',
    );
    await pierwsza.ensureSettings(
      identityFactory: () async => ('klucz', 'guid-ja'),
      defaultNickname: 'Ja',
      defaultPort: 47777,
    );
    await pierwsza.saveBluetoothAddon(true);
    await pierwsza.close();

    // Baza jak sprzed zmiany: kolumny klawiatury znikają, licznik wersji
    // wraca na 12.
    final surowa = raw.sqlite3.open(plik.path);
    surowa.execute('ALTER TABLE settings DROP COLUMN keyboard_enabled;');
    surowa.execute('ALTER TABLE settings DROP COLUMN remote_input_receive;');
    surowa.execute('ALTER TABLE peers DROP COLUMN remote_input;');
    surowa.execute('PRAGMA user_version = 12;');
    surowa.close();

    final druga = ChattDb(NativeDatabase(plik));
    addTearDown(druga.close);

    final po = await druga.allPeers();
    expect(po, hasLength(1), reason: 'rozmówca nie może zniknąć');
    expect(po.single.name, 'Alicja');
    expect(po.single.host, '192.168.0.2');
    expect(po.single.port, 47780);
    expect(po.single.btAddress, 'AA:BB:CC:DD:EE:FF');
    expect(po.single.verified, isTrue,
        reason: 'potwierdzona tożsamość zostaje potwierdzona');
    expect(po.single.autoAccept, isTrue,
        reason: 'zgoda na pliki sprzed aktualizacji zostaje');
    expect(po.single.remoteInput, isFalse,
        reason: 'pisanie bez pytania włącza wyłącznie użytkownik');

    final wiadomosci = await druga.watchMessages(rozmowa).first;
    expect(wiadomosci, hasLength(1));
    expect(wiadomosci.single.body, 'wiadomość sprzed migracji');

    final ustawienia = await druga.getSettings();
    expect(ustawienia, isNotNull);
    expect(ustawienia!.nickname, 'Ja');
    expect(ustawienia.bluetoothEnabled, isTrue,
        reason: 'dodatek Bluetooth zostaje, jak był');
    expect(ustawienia.keyboardEnabled, isFalse,
        reason: 'aktualizacja nie włącza dodatku klawiatury');
    expect(ustawienia.remoteInputReceive, isFalse,
        reason: 'ani zgody na bycie wpisywanym');

    final wersja =
        await druga.customSelect('PRAGMA user_version;').getSingle();
    expect(wersja.read<int>('user_version'), druga.schemaVersion);
  });

  /// Schemat 14 oznacza wiadomości przywrócone z kopii historii rozmówcy.
  /// Wszystko sprzed zmiany przyszło zwykłą drogą: zostaje, jak było,
  /// z pustym znacznikiem.
  test('przejście na schemat 14 nie oznacza starych wiadomości jako przywróconych',
      () async {
    final katalog = Directory.systemTemp.createTempSync('chatt-migracja-14');
    addTearDown(() => katalog.deleteSync(recursive: true));
    final plik = File(p.join(katalog.path, 'chatt.db'));

    final pierwsza = ChattDb(NativeDatabase(plik));
    final peer = await pierwsza.upsertPeer(
      guid: 'guid-1',
      name: 'Alicja',
      welcomeMessage: '',
      host: '192.168.0.2',
      port: 47780,
    );
    final rozmowa = await pierwsza.ensureConversation(peer.id);
    await pierwsza.insertIncoming(
      conversationId: rozmowa,
      messageGuid: 'wiadomosc-1',
      body: 'wiadomość sprzed migracji',
      sentAt: DateTime(2026, 9, 1, 12),
    );
    await pierwsza.close();

    final surowa = raw.sqlite3.open(plik.path);
    surowa.execute('ALTER TABLE messages DROP COLUMN restored_at;');
    surowa.execute('PRAGMA user_version = 13;');
    surowa.close();

    final druga = ChattDb(NativeDatabase(plik));
    addTearDown(druga.close);
    final wiadomosci = await druga.watchMessages(rozmowa).first;
    expect(wiadomosci, hasLength(1));
    expect(wiadomosci.single.body, 'wiadomość sprzed migracji');
    expect(wiadomosci.single.restoredAt, isNull);
    final wersja =
        await druga.customSelect('PRAGMA user_version;').getSingle();
    expect(wersja.read<int>('user_version'), druga.schemaVersion);
  });

  /// Schemat 15 zapamiętuje styl wyglądu. Baza sprzed zmiany dostaje
  /// Ciszę, a motyw, tło i reszta ustawień zostają, jak były.
  test('przejście na schemat 15 daje styl Cisza i nie rusza reszty wyglądu',
      () async {
    final katalog = Directory.systemTemp.createTempSync('chatt-migracja-15');
    addTearDown(() => katalog.deleteSync(recursive: true));
    final plik = File(p.join(katalog.path, 'chatt.db'));

    final pierwsza = ChattDb(NativeDatabase(plik));
    await pierwsza.ensureSettings(
      identityFactory: () async => ('klucz', 'guid-ja'),
      defaultNickname: 'Ja',
      defaultPort: 47777,
    );
    await pierwsza.saveTheme(AppTheme.dark);
    await pierwsza.saveBackground(3);
    await pierwsza.close();

    final surowa = raw.sqlite3.open(plik.path);
    surowa.execute('ALTER TABLE settings DROP COLUMN style;');
    surowa.execute('PRAGMA user_version = 14;');
    surowa.close();

    final druga = ChattDb(NativeDatabase(plik));
    addTearDown(druga.close);
    final ustawienia = await druga.getSettings();
    expect(ustawienia, isNotNull);
    expect(ustawienia!.style, AppStyle.cisza);
    expect(ustawienia.theme, AppTheme.dark);
    expect(ustawienia.background, 3);
    expect(ustawienia.nickname, 'Ja');

    await druga.saveStyle(AppStyle.cieplo);
    expect((await druga.getSettings())!.style, AppStyle.cieplo);

    final wersja =
        await druga.customSelect('PRAGMA user_version;').getSingle();
    expect(wersja.read<int>('user_version'), 15);
  });

  /// Rozmówca poznany wyłącznie przez radio nie ma adresu w sieci, a rozmówca
  /// poznany przez sieć nie ma adresu radia. Spotkanie jedną drogą nie może
  /// wymazać tego, co wiemy o drugiej: inaczej każdy skan Bluetooth kasowałby
  /// adres IP i odwrotnie.
  test('adresy obu dróg nie kasują się nawzajem', () async {
    final db = ChattDb(NativeDatabase.memory());
    addTearDown(db.close);

    await db.upsertPeer(
      guid: 'guid-1',
      name: 'Alicja',
      welcomeMessage: '',
      host: '192.168.0.2',
      port: 47780,
    );
    // To samo urządzenie zobaczone przez radio: bez adresu w sieci.
    await db.upsertPeer(
      guid: 'guid-1',
      name: 'Alicja',
      welcomeMessage: '',
      host: '',
      port: 0,
      btAddress: 'AA:BB:CC:DD:EE:FF',
    );

    var peer = (await db.peerByGuid('guid-1'))!;
    expect(peer.host, '192.168.0.2');
    expect(peer.port, 47780);
    expect(peer.btAddress, 'AA:BB:CC:DD:EE:FF');

    // I w drugą stronę: kontakt po IP nie kasuje trasy przez radio.
    await db.upsertPeer(
      guid: 'guid-1',
      name: 'Alicja',
      welcomeMessage: '',
      host: '192.168.0.9',
      port: 47781,
    );
    peer = (await db.peerByGuid('guid-1'))!;
    expect(peer.host, '192.168.0.9');
    expect(peer.port, 47781);
    expect(peer.btAddress, 'AA:BB:CC:DD:EE:FF');
  });
}
