import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/core/remote_input.dart';
import 'package:chatt/core/version.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/network/bt_transport.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_log.dart';
import 'package:chatt/services/app_services.dart';

/// Dziennik aplikacji przy prawdziwym ruchu: dwie pełne instancje w jednym
/// procesie, jak w `messaging_e2e_test.dart`. Sprawdzamy, że zdarzenia
/// zostawiają ślad, a ślad nie niesie niczego, czego nie powinien: kodu
/// parowania, treści wiadomości, nazwy pliku ani kluczy.
///
/// Same gniazda, bez `testWidgets`: atrapa HttpClienta z testów widżetów
/// zablokowałaby tu cały ruch (docs/testing.md).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory work;
  late AppServices alice;
  late AppServices bob;

  /// Czy Bartek przyjmuje zapowiedziane pliki.
  late bool bobPrzyjmuje;

  setUp(() async {
    work = Directory.systemTemp.createTempSync('chatt_app_log');
    bobPrzyjmuje = true;
    alice = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Alicja',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'alice_received'),
      fileOfferPolicy: acceptAllFileOffers,
    );
    bob = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Bartek',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'bob_received'),
      fileOfferPolicy: (offer) async =>
          bobPrzyjmuje ? OfferDecision.accept : OfferDecision.reject,
    );
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
    work.deleteSync(recursive: true);
  });

  /// Wpisy dziennika instancji, po zapisaniu tego, co czeka w pamięci.
  Future<List<AppLogEntry>> dziennik(AppServices s) async {
    await s.log.flush();
    return s.db.allLogEntries();
  }

  /// Cały dziennik jako jeden tekst: treści razem ze szczegółami.
  Future<String> calosc(AppServices s) async => [
        for (final w in await dziennik(s)) '${w.message}\n${w.details ?? ''}',
      ].join('\n');

  /// Tak dziennik podpisuje rozmówcę: nazwa i początek guid-a.
  String kto(AppServices s, String name) =>
      '$name (${s.identity.guid.substring(0, 8)})';

  /// Nic z tego nie ma prawa trafić do dziennika żadnej ze stron.
  Future<void> bezSekretow({List<String> teksty = const []}) async {
    final sekrety = [
      for (final s in [alice, bob]) ...[
        (await s.db.getSettings())!.identityKey,
        // Klucz publiczny w base64 to ślad wypisanego `Peer` albo `Setting`.
        base64.encode(s.identity.publicKey),
      ],
      work.path,
      ...teksty,
    ];
    for (final s in [alice, bob]) {
      final tekst = await calosc(s);
      for (final sekret in sekrety) {
        expect(sekret, isNotEmpty);
        expect(tekst, isNot(contains(sekret)),
            reason: 'dziennik ${s.identity.name} zawiera „$sekret”');
      }
    }
  }

  Future<int> rozmowaUAlicji() async {
    final bobAtAlice =
        await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    return alice.openConversationWith(bobAtAlice!);
  }

  test('start zostawia jeden wpis z podsumowaniem, bez ścieżek', () async {
    final wpisy = await dziennik(alice);
    final start = wpisy
        .where((w) => w.message == 'App started: Chatt $appVersion')
        .single;
    expect(start.level, LogLevel.info);
    expect(start.area, LogArea.app);
    final szczegoly = start.details!;
    for (final linia in [
      'os: ${Platform.operatingSystem}',
      'port: ${alice.identity.tcpPort}',
      'discovery listening: disabled',
      'database key protected: yes',
      'migrated to encrypted: no',
      'wifi: on',
      'bluetooth add-on: off',
      'keyboard add-on: off',
      'typing on this device allowed: off',
      'typing history: on',
    ]) {
      expect(szczegoly, contains(linia));
    }
    await bezSekretow();
  });

  test('parowanie zostawia wpisy po obu stronach, bez kodu', () async {
    final bobAtAlice =
        await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final kod = await alice.startPairing(bobAtAlice!);
    expect(kod, isNotNull);
    expect(await alice.confirmPairing(bob.identity.guid), PairOutcome.accepted);
    expect(await bob.confirmPairing(alice.identity.guid), PairOutcome.accepted);

    final uAlicji = [
      for (final w in await dziennik(alice))
        if (w.area == LogArea.pair) w.message,
    ];
    final bartek = kto(bob, 'Bartek');
    expect(uAlicji, [
      'Pairing started with $bartek',
      'Pairing code shown for $bartek',
      'Pairing confirmed on this device for $bartek',
      'Pairing confirmed by $bartek',
      'Pairing completed with $bartek',
    ]);

    final uBartka = [
      for (final w in await dziennik(bob))
        if (w.area == LogArea.pair) w.message,
    ];
    final alicja = kto(alice, 'Alicja');
    expect(uBartka, [
      'Pairing started by $alicja',
      'Pairing code shown for $alicja',
      'Pairing confirmed by $alicja',
      'Pairing confirmed on this device for $alicja',
      'Pairing completed with $alicja',
    ]);

    await bezSekretow(teksty: [kod!]);
  });

  test('odrzucone parowanie widać po obu stronach', () async {
    final bobAtAlice =
        await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final kod = await alice.startPairing(bobAtAlice!);
    await bob.cancelPairing(alice.identity.guid);

    expect(
        (await dziennik(bob)).map((w) => w.message),
        contains(
            'Pairing rejected on this device for ${kto(alice, 'Alicja')}'));
    expect((await dziennik(alice)).map((w) => w.message),
        contains('Pairing rejected by ${kto(bob, 'Bartek')}'));
    await bezSekretow(teksty: [kod!]);
  });

  test('wiadomość dostarczona i niedostarczona: identyfikator bez treści',
      () async {
    const tresc = 'Tajna treść wiadomości 7f3a';
    final rozmowa = await rozmowaUAlicji();

    await alice.sendText(rozmowa, tresc);
    final pierwsza = (await alice.db.watchMessages(rozmowa).first).single;
    expect(pierwsza.status, MessageStatus.delivered);

    // Bartek znika z sieci: druga wiadomość nie dochodzi.
    await bob.server.stop();
    await alice.sendText(rozmowa, '$tresc, druga');
    final druga = (await alice.db.watchMessages(rozmowa).first).last;
    expect(druga.status, MessageStatus.failed);

    final uAlicji = await dziennik(alice);
    final bartek = kto(bob, 'Bartek');
    final dostarczona = uAlicji
        .where((w) => w.message.contains(pierwsza.messageGuid))
        .single;
    expect(dostarczona.message,
        'Message ${pierwsza.messageGuid} delivered to $bartek');
    expect(dostarczona.area, LogArea.net);
    expect(dostarczona.level, LogLevel.info);

    final nieudana =
        uAlicji.where((w) => w.message.contains(druga.messageGuid)).single;
    expect(nieudana.message,
        'Message ${druga.messageGuid} not delivered to $bartek');
    expect(nieudana.area, LogArea.net);
    expect(nieudana.level, LogLevel.warning);

    expect(
        (await dziennik(bob)).map((w) => w.message),
        contains('Message ${pierwsza.messageGuid} received from '
            '${kto(alice, 'Alicja')}'));

    await bezSekretow(teksty: ['Tajna treść']);
  });

  test('plik: kierunek, rozmiar i wynik, bez nazwy', () async {
    const nazwa = 'sekretny-raport-kwartalny.bin';
    const rozmiar = 100 * 1024;
    final plik = File(p.join(work.path, nazwa))
      ..writeAsBytesSync(List<int>.generate(rozmiar, (i) => i % 251));
    final rozmowa = await rozmowaUAlicji();

    await alice.sendFile(rozmowa, plik.path);
    final wyslany = (await alice.db.watchMessages(rozmowa).first).single;
    expect(wyslany.status, MessageStatus.delivered);
    final guid = wyslany.messageGuid;

    final bartek = kto(bob, 'Bartek');
    final uAlicji = [
      for (final w in await dziennik(alice))
        if (w.area == LogArea.file) w.message,
    ];
    expect(uAlicji, [
      'Outgoing file to $bartek: $rozmiar bytes (message $guid)',
      'Outgoing file delivered to $bartek: $rozmiar bytes (message $guid)',
    ]);

    final alicja = kto(alice, 'Alicja');
    final uBartka = [
      for (final w in await dziennik(bob))
        if (w.area == LogArea.file) w.message,
    ];
    expect(uBartka, [
      'Incoming file offer from $alicja: $rozmiar bytes, accepted '
          '(message $guid)',
      'Incoming file received from $alicja: $rozmiar bytes (message $guid)',
    ]);

    await bezSekretow(teksty: ['sekretny-raport', 'kwartalny']);
  });

  test('odmowa pliku: wynik po obu stronach, bez nazwy', () async {
    bobPrzyjmuje = false;
    const nazwa = 'umowa-najmu-poufne.pdf';
    final plik = File(p.join(work.path, nazwa))
      ..writeAsBytesSync(List<int>.filled(2048, 7));
    final rozmowa = await rozmowaUAlicji();

    await alice.sendFile(rozmowa, plik.path);
    final wyslany = (await alice.db.watchMessages(rozmowa).first).single;
    expect(wyslany.status, MessageStatus.failed);
    final guid = wyslany.messageGuid;

    expect(
        (await dziennik(alice)).map((w) => w.message),
        contains('Outgoing file declined by ${kto(bob, 'Bartek')}: rejected '
            '(message $guid)'));
    expect(
        (await dziennik(bob)).map((w) => w.message),
        contains('Incoming file offer from ${kto(alice, 'Alicja')}: 2048 '
            'bytes, rejected (message $guid)'));

    await bezSekretow(teksty: ['umowa-najmu', 'poufne']);
  });

  test('zamknięcie: ostatni wpis zostaje w bazie, haki kanałów są wolne',
      () async {
    // Bartek wstał ostatni, więc to jego dziennik dostaje błędy kanałów
    // natywnych, i to on je zwalnia.
    expect(BtChannel.onCallError, isNotNull);
    expect(RemoteInputChannel.onCallError, isNotNull);
    await bob.dispose();
    expect(BtChannel.onCallError, isNull);
    expect(RemoteInputChannel.onCallError, isNull);

    // Baza w pliku: po zamknięciu aplikacji da się ją otworzyć jeszcze raz.
    final plikBazy = File(p.join(work.path, 'bartek.sqlite'));
    bob = await AppServices.start(
      executor: NativeDatabase(plikBazy),
      portOverride: 0,
      nameOverride: 'Bartek',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'bob_received'),
    );
    await bob.dispose();
    final baza = ChattDb(NativeDatabase(plikBazy));
    final wpisy = await baza.allLogEntries();
    await baza.close();
    expect(wpisy.first.message, 'App started: Chatt $appVersion');
    expect(wpisy.last.message, 'App stopping');

    // Na potrzeby tearDown.
    bob = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Bartek',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'bob_received'),
    );
  });
}
