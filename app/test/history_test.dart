import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/core/identity.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';

/// Udostępnianie historii (issue #36) między prawdziwymi instancjami, przez
/// prawdziwe gniazda. Odbiorca dostaje naszą wspólną rozmowę z odwróconymi
/// kierunkami, oznaczoną jako przywróconą, bez powiadomień, i wyłącznie
/// w granicach zgody, którą wydał.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory katalog;
  final uruchomione = <AppServices>[];

  /// Karty historii u każdej instancji, po nazwie.
  final karty = <String, List<PendingHistory>>{};

  /// Decyzje kart, po nazwie instancji. Brak wpisu znaczy zgodę.
  final decyzje = <String, HistoryDecision>{};

  /// Powiadomienia o nowych wiadomościach, po nazwie instancji.
  final powiadomienia = <String, int>{};

  /// Karta, która czeka na odpowiedź, dopóki test jej nie puści.
  final blokady = <String, Completer<void>>{};

  /// Zwykłe karty plików, po nazwie instancji.
  final kartyPlikow = <String, int>{};

  setUp(() {
    katalog = Directory.systemTemp.createTempSync('chatt_historia_');
    karty.clear();
    decyzje.clear();
    powiadomienia.clear();
    blokady.clear();
    kartyPlikow.clear();
  });

  tearDown(() async {
    for (final s in uruchomione.reversed) {
      await s.dispose();
    }
    uruchomione.clear();
    katalog.deleteSync(recursive: true);
  });

  String odebrane(String nazwa) => p.join(katalog.path, nazwa);

  Future<AppServices> instancja(String nazwa) async {
    final s = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: nazwa,
      enableDiscovery: false,
      receivedDirOverride: odebrane(nazwa),
      fileOfferPolicy: (offer) async {
        kartyPlikow[nazwa] = (kartyPlikow[nazwa] ?? 0) + 1;
        return OfferDecision.accept;
      },
      onIncomingMessage: (peer, text, conversationId) =>
          powiadomienia[nazwa] = (powiadomienia[nazwa] ?? 0) + 1,
      historyPolicy: (ask) async {
        (karty[nazwa] ??= []).add(ask);
        final blokada = blokady[nazwa];
        if (blokada != null) await blokada.future;
        return decyzje[nazwa] ?? HistoryDecision.accept;
      },
    );
    uruchomione.add(s);
    return s;
  }

  Future<Peer> rozmowca(AppServices u, AppServices kto) async =>
      (await u.db.peerByGuid(kto.identity.guid))!;

  Future<void> sparuj(AppServices a, AppServices b) async {
    final bUA = await a.addPeerByAddress('127.0.0.1', b.server.port!);
    expect(await a.startPairing(bUA!), isNotNull);
    expect(await a.confirmPairing(b.identity.guid), PairOutcome.accepted);
    expect(await b.confirmPairing(a.identity.guid), PairOutcome.accepted);
  }

  Future<int> rozmowa(AppServices u, AppServices z) async =>
      u.openConversationWith(await rozmowca(u, z));

  Future<List<Message>> wiadomosci(AppServices u, AppServices z) async =>
      (await u.db.watchMessages(await rozmowa(u, z)).first);

  File plik(String nazwa, String tresc) {
    final f = File(p.join(katalog.path, 'zrodla', nazwa))
      ..createSync(recursive: true)
      ..writeAsStringSync(tresc);
    return f;
  }

  /// Alicja i Bartek, sparowani, z rozmową w obie strony: dwie wiadomości
  /// i po jednym pliku od każdego.
  Future<(AppServices, AppServices)> rozmowaZPlikami() async {
    final alicja = await instancja('Alicja');
    final bartek = await instancja('Bartek');
    await sparuj(alicja, bartek);
    final uAlicji = await rozmowa(alicja, bartek);
    final uBartka = await rozmowa(bartek, alicja);
    await alicja.sendText(uAlicji, 'Cześć Bartek');
    await bartek.sendText(uBartka, 'Hej Alicja');
    await alicja.sendFile(uAlicji, plik('a.txt', 'treść od Alicji').path);
    await bartek.sendFile(uBartka, plik('b.txt', 'treść od Bartka').path);
    expect(await wiadomosci(alicja, bartek), hasLength(4));
    expect(await wiadomosci(bartek, alicja), hasLength(4));
    return (alicja, bartek);
  }

  /// Bartek traci historię razem z odebranymi plikami.
  Future<void> stracHistorie(AppServices s, String nazwa) async {
    await s.db.clearHistory();
    for (final f in Directory(odebrane(nazwa)).listSync()) {
      if (f is File) f.deleteSync();
    }
  }

  test('udostępniona historia wraca z odwróconymi kierunkami i plikami',
      () async {
    final (alicja, bartek) = await rozmowaZPlikami();
    final przed = await wiadomosci(bartek, alicja);
    await stracHistorie(bartek, 'Bartek');
    expect(await wiadomosci(bartek, alicja), isEmpty);
    final powiadomieniaPrzed = powiadomienia['Bartek'] ?? 0;

    final wynik = await alicja.shareHistory(await rozmowa(alicja, bartek));
    expect(wynik, HistoryShareResult.done);

    final po = await wiadomosci(bartek, alicja);
    expect(po, hasLength(4));
    for (final stara in przed) {
      final nowa = po.singleWhere((m) => m.messageGuid == stara.messageGuid);
      expect(nowa.direction, stara.direction, reason: stara.body);
      expect(nowa.body, stara.body);
      expect(nowa.createdAt, stara.createdAt);
      expect(nowa.kind, stara.kind);
      expect(nowa.restoredAt, isNotNull);
      expect(nowa.status, MessageStatus.delivered);
    }
    // Przychodzące wchodzą jako przeczytane: to stara rozmowa.
    expect(
        po
            .where((m) => m.direction == MessageDirection.incoming)
            .every((m) => m.readAt != null),
        isTrue);
    // Pliki dojechały: od Alicji i własny Bartka, który ona miała.
    final a = po.singleWhere((m) => m.fileName == 'a.txt');
    final b = po.singleWhere((m) => m.fileName == 'b.txt');
    expect(a.direction, MessageDirection.incoming);
    expect(b.direction, MessageDirection.outgoing);
    expect(File(a.filePath!).readAsStringSync(), 'treść od Alicji');
    expect(File(b.filePath!).readAsStringSync(), 'treść od Bartka');
    expect(p.isWithin(odebrane('Bartek'), b.filePath!), isTrue);

    expect(powiadomienia['Bartek'] ?? 0, powiadomieniaPrzed,
        reason: 'import nie woła powiadomień');
    final postep = bartek.incomingHistory.value;
    expect(postep?.finished, isTrue);
    expect(postep?.messagesDone, 4);
    expect(postep?.filesDone, 2);
    // Udostępniający nie zmienia u siebie niczego.
    final uAlicji = await wiadomosci(alicja, bartek);
    expect(uAlicji.every((m) => m.restoredAt == null), isTrue);
    expect(uAlicji.every((m) => m.status == MessageStatus.delivered), isTrue);
  });

  test('karta zapowiedzi niesie liczby i stan tarczy', () async {
    final (alicja, bartek) = await rozmowaZPlikami();
    await stracHistorie(bartek, 'Bartek');
    await bartek.db.saveRetentionDays(30);
    await alicja.shareHistory(await rozmowa(alicja, bartek));

    final karta = karty['Bartek']!.single;
    expect(karta.kind, PendingHistoryKind.offer);
    expect(karta.peerName, 'Alicja');
    expect(karta.fromVerifiedPeer, isTrue);
    expect(karta.summary!.count, 4);
    expect(karta.summary!.files, 2);
    expect(karta.summary!.bytes,
        'treść od Alicji'.length + 'treść od Bartka'.length + 4);
    expect(karta.retentionDays, 30);
  });

  test('bez plików: wpisy plików zostają bez treści', () async {
    final (alicja, bartek) = await rozmowaZPlikami();
    await stracHistorie(bartek, 'Bartek');

    final wynik = await alicja.shareHistory(await rozmowa(alicja, bartek),
        withFiles: false);
    expect(wynik, HistoryShareResult.done);
    final po = await wiadomosci(bartek, alicja);
    expect(po, hasLength(4));
    final pliki = po.where((m) => m.kind == MessageKind.file).toList();
    expect(pliki, hasLength(2));
    expect(pliki.every((m) => m.filePath == null), isTrue);
    expect(karty['Bartek']!.single.summary!.files, 0);
  });

  test('plik, który przetrwał u odbiorcy, podpina się bez przesyłania',
      () async {
    final (alicja, bartek) = await rozmowaZPlikami();
    // „Wyczyść historię" zostawia odebrane pliki na dysku.
    await bartek.db.clearHistory();

    await alicja.shareHistory(await rozmowa(alicja, bartek),
        withFiles: false);
    final a = (await wiadomosci(bartek, alicja))
        .singleWhere((m) => m.fileName == 'a.txt');
    expect(a.filePath, isNotNull);
    expect(File(a.filePath!).readAsStringSync(), 'treść od Alicji');
  });

  test('drugie udostępnienie niczego nie dubluje i dowozi brakujące pliki',
      () async {
    final (alicja, bartek) = await rozmowaZPlikami();
    await stracHistorie(bartek, 'Bartek');
    final uAlicji = await rozmowa(alicja, bartek);

    await alicja.shareHistory(uAlicji, withFiles: false);
    expect(await alicja.shareHistory(uAlicji), HistoryShareResult.done);

    final po = await wiadomosci(bartek, alicja);
    expect(po, hasLength(4));
    expect(
        po
            .where((m) => m.kind == MessageKind.file)
            .every((m) => m.filePath != null && File(m.filePath!).existsSync()),
        isTrue);
  });

  test('odmowa i cisza na karcie nie wpuszczają niczego', () async {
    final (alicja, bartek) = await rozmowaZPlikami();
    await stracHistorie(bartek, 'Bartek');
    final uAlicji = await rozmowa(alicja, bartek);

    decyzje['Bartek'] = HistoryDecision.reject;
    expect(await alicja.shareHistory(uAlicji), HistoryShareResult.rejected);
    decyzje['Bartek'] = HistoryDecision.noAnswer;
    expect(await alicja.shareHistory(uAlicji), HistoryShareResult.noAnswer);
    expect(await wiadomosci(bartek, alicja), isEmpty);
    expect(bartek.incomingHistory.value, isNull);
  });

  test('pusta rozmowa: nie ma czego udostępniać ani o co prosić', () async {
    final alicja = await instancja('Alicja');
    final bartek = await instancja('Bartek');
    await sparuj(alicja, bartek);
    expect(await alicja.shareHistory(await rozmowa(alicja, bartek)),
        HistoryShareResult.nothingToShare);
    expect(await bartek.requestHistory(await rozmowa(bartek, alicja)),
        HistoryRequestResult.empty);
    expect(karty['Alicja'], isNull, reason: 'pusta rozmowa nie pyta');
  });

  test('prośba o historię: karta u proszonego, zapowiedź wchodzi bez karty',
      () async {
    final (alicja, bartek) = await rozmowaZPlikami();
    await stracHistorie(bartek, 'Bartek');
    // Gdyby Bartek dostał kartę, odmówiłby: odpowiedź na jego prośbę ma jej
    // nie pokazać.
    decyzje['Bartek'] = HistoryDecision.reject;

    expect(await bartek.requestHistory(await rozmowa(bartek, alicja)),
        HistoryRequestResult.accepted);
    final karta = karty['Alicja']!.single;
    expect(karta.kind, PendingHistoryKind.request);
    expect(karta.peerName, 'Bartek');
    expect(karta.summary!.count, 4);

    final koniec = DateTime.now().add(const Duration(seconds: 10));
    while ((bartek.incomingHistory.value?.finished ?? false) == false) {
      if (DateTime.now().isAfter(koniec)) fail('historia nie dojechała');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(await wiadomosci(bartek, alicja), hasLength(4));
    expect(karty['Bartek'], isNull);
  });

  test('prośba: odmowa i „bez plików" u proszonego', () async {
    final (alicja, bartek) = await rozmowaZPlikami();
    await stracHistorie(bartek, 'Bartek');
    final uBartka = await rozmowa(bartek, alicja);

    decyzje['Alicja'] = HistoryDecision.reject;
    expect(await bartek.requestHistory(uBartka), HistoryRequestResult.rejected);

    decyzje['Alicja'] = HistoryDecision.acceptWithoutFiles;
    expect(await bartek.requestHistory(uBartka), HistoryRequestResult.accepted);
    final koniec = DateTime.now().add(const Duration(seconds: 10));
    while ((bartek.incomingHistory.value?.finished ?? false) == false) {
      if (DateTime.now().isAfter(koniec)) fail('historia nie dojechała');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final pliki = (await wiadomosci(bartek, alicja))
        .where((m) => m.kind == MessageKind.file);
    expect(pliki.every((m) => m.filePath == null), isTrue);
  });

  test('starsza rozmowa z dawnym wpisem idzie tylko do urządzenia z tarczą',
      () async {
    // Alicja rozmawiała z Bartkiem; Bartek reinstaluje aplikację i wraca
    // z nową tożsamością, czyli pod nowym wpisem.
    final (alicja, stary) = await rozmowaZPlikami();
    final staraRozmowa = await rozmowa(alicja, stary);
    final nowy = await instancja('Bartek-nowy');
    final nowyUAlicji =
        (await alicja.addPeerByAddress('127.0.0.1', nowy.server.port!))!;
    final nowaRozmowa = await alicja.openConversationWith(nowyUAlicji);

    final inne = await alicja.otherConversations(nowaRozmowa);
    expect(inne.map((r) => r.conversationId), [staraRozmowa]);
    expect(inne.single.messages, 4);

    expect(
        await alicja.shareHistory(nowaRozmowa,
            sourceConversationId: staraRozmowa),
        HistoryShareResult.needsVerified);
    expect(karty['Bartek-nowy'], isNull, reason: 'bez tarczy nic nie wyszło');

    await sparuj(alicja, nowy);
    expect(
        await alicja.shareHistory(nowaRozmowa,
            sourceConversationId: staraRozmowa),
        HistoryShareResult.done);
    final uNowego = await wiadomosci(nowy, alicja);
    expect(uNowego, hasLength(4));
    expect(
        uNowego.singleWhere((m) => m.body == 'Cześć Bartek').direction,
        MessageDirection.incoming);
    expect(uNowego.singleWhere((m) => m.body == 'Hej Alicja').direction,
        MessageDirection.outgoing);
    expect(
        uNowego
            .where((m) => m.kind == MessageKind.file)
            .every((m) => m.filePath != null),
        isTrue);

    // U siebie Alicja łączy starą rozmowę z nową.
    expect(
        await alicja.mergeConversations(from: staraRozmowa, into: nowaRozmowa),
        4);
    expect(await alicja.otherConversations(nowaRozmowa), isEmpty);
    expect(
        (await alicja.db.watchMessages(nowaRozmowa).first), hasLength(4));
    expect(await alicja.db.peerByGuid(stary.identity.guid), isNotNull,
        reason: 'stary wpis zostaje na liście urządzeń');
  });

  group('zgoda obowiązuje w granicach zapowiedzi', () {
    late AppServices alicja;
    late AppServices bartek;
    late Peer bartekUAlicji;

    setUp(() async {
      alicja = await instancja('Alicja');
      bartek = await instancja('Bartek');
      await sparuj(alicja, bartek);
      bartekUAlicji = await rozmowca(alicja, bartek);
    });

    HistoryItem wpis(String guid,
            {bool mine = true, DateTime? kiedy, String? plik, int size = 0}) =>
        HistoryItem(
          messageGuid: guid,
          mine: mine,
          sentAt: kiedy ?? DateTime.now().subtract(const Duration(days: 1)),
          body: plik == null ? 'wiadomość $guid' : '📎 $plik',
          fileName: plik,
          fileSize: plik == null ? null : size,
          fileFollows: plik != null,
        );

    /// Zapowiedź złożona ręcznie. Zwraca token zgody.
    Future<String> zapowiedz(String id, HistorySummary summary) async {
      final wynik = await alicja.debugSendSealed(
        bartekUAlicji,
        '/history-offer',
        HistoryOfferMessage(
          from: alicja.identity,
          op: historyOpOffer,
          id: id,
          summary: summary,
        ).toJson(),
      );
      expect(wynik.status, 200);
      final reply = HistoryReply.fromJson(wynik.reply, id: id)!;
      expect(reply.accepted, isTrue);
      return reply.token!;
    }

    Future<(int, HistoryChunkReply?)> paczka(String id, String token, int seq,
        List<HistoryItem> items) async {
      final wynik = await alicja.debugSendSealed(
        bartekUAlicji,
        '/history-chunk',
        HistoryChunk(
          from: alicja.identity,
          id: id,
          token: token,
          seq: seq,
          items: items,
        ).toJson(),
      );
      return (
        wynik.status,
        HistoryChunkReply.fromJson(wynik.reply, id: id, seq: seq),
      );
    }

    HistorySummary ile(int count, {int files = 0, int bytes = 0}) =>
        HistorySummary(
          count: count,
          files: files,
          bytes: bytes,
          first: DateTime.now().subtract(const Duration(days: 400)),
          // Zapas w przyszłość: test dat z przyszłości sprawdza import,
          // a nie zakres z karty.
          last: DateTime.now().add(const Duration(days: 3)),
        );

    test('więcej wiadomości, niż zapowiedziano, odpada w całości', () async {
      final token = await zapowiedz('h1', ile(2));
      final (status, reply) =
          await paczka('h1', token, 1, [wpis('m1'), wpis('m2'), wpis('m3')]);
      expect(status, 403);
      expect(reply?.reason, historyOverLimit);
      expect(await wiadomosci(bartek, alicja), isEmpty);
    });

    test('zły token i cudza historia nie mają zgody', () async {
      final token = await zapowiedz('h2', ile(5));
      expect((await paczka('h2', 'AAAA', 1, [wpis('m1')])).$2?.reason,
          historyNoGrant);
      expect((await paczka('h3', token, 1, [wpis('m1')])).$2?.reason,
          historyNoGrant);
      expect(await wiadomosci(bartek, alicja), isEmpty);
    });

    test('powtórzona paczka nie liczy się drugi raz do limitu', () async {
      final token = await zapowiedz('h4', ile(2));
      final pierwsza = await paczka('h4', token, 1, [wpis('m1'), wpis('m2')]);
      expect(pierwsza.$2?.imported, 2);
      final druga = await paczka('h4', token, 1, [wpis('m1'), wpis('m2')]);
      expect(druga.$1, 200);
      expect(druga.$2?.imported, 0);
      expect(druga.$2?.skipped, 2);
      expect(await wiadomosci(bartek, alicja), hasLength(2));
    });

    test('daty z przyszłości i sprzed retencji odpadają', () async {
      await bartek.db.saveRetentionDays(7);
      final token = await zapowiedz('h5', ile(3));
      final (_, reply) = await paczka('h5', token, 1, [
        wpis('m1'),
        wpis('m2', kiedy: DateTime.now().add(const Duration(days: 2))),
        wpis('m3', kiedy: DateTime.now().subtract(const Duration(days: 30))),
      ]);
      expect(reply?.imported, 1);
      expect(reply?.skipped, 2);
      final po = await wiadomosci(bartek, alicja);
      expect(po.single.messageGuid, 'm1');
      expect(po.single.direction, MessageDirection.incoming);
      expect(po.single.readAt, isNotNull);
    });

    test('pliki ponad zapowiedź odpadają', () async {
      final token = await zapowiedz('h6', ile(2, files: 1, bytes: 10));
      final (status, reply) = await paczka('h6', token, 1, [
        wpis('f1', plik: 'a.txt', size: 10),
        wpis('f2', plik: 'b.txt', size: 10),
      ]);
      expect(status, 403);
      expect(reply?.reason, historyOverLimit);
    });

    test('druga historia w trakcie pierwszej to busy', () async {
      final cezary = await instancja('Cezary');
      await sparuj(cezary, bartek);
      await zapowiedz('h7', ile(2));
      final bartekUCezarego = await rozmowca(cezary, bartek);
      final wynik = await cezary.debugSendSealed(
        bartekUCezarego,
        '/history-offer',
        HistoryOfferMessage(
          from: cezary.identity,
          op: historyOpOffer,
          id: 'h8',
          summary: ile(1),
        ).toJson(),
      );
      expect(wynik.status, 403);
      expect(HistoryReply.fromJson(wynik.reply, id: 'h8')?.reason, historyBusy);
    });

    test('ten sam numer paczki z nową treścią nie wpuszcza niczego', () async {
      final token = await zapowiedz('h10', ile(2));
      await paczka('h10', token, 1, [wpis('m1'), wpis('m2')]);
      final (status, reply) =
          await paczka('h10', token, 1, [wpis('m3'), wpis('m4'), wpis('m5')]);
      expect(status, 200);
      expect(reply?.imported, 0);
      expect(await wiadomosci(bartek, alicja), hasLength(2));
    });

    test('plik zapowiedziany raz nie zmienia nazwy ani rozmiaru', () async {
      final token = await zapowiedz('h11', ile(2, files: 1, bytes: 1));
      expect((await paczka('h11', token, 1, [wpis('f1', plik: 'a.txt', size: 1)]))
          .$1, 200);
      final (status, reply) = await paczka('h11', token, 2,
          [wpis('f1', plik: 'a.txt', size: 5000000000)]);
      expect(status, 403);
      expect(reply?.reason, historyOverLimit);
    });

    test('wiadomość spoza zakresu dat z karty odpada w całości', () async {
      final token = await zapowiedz(
          'h12',
          HistorySummary(
            count: 2,
            files: 0,
            bytes: 0,
            first: DateTime.now().subtract(const Duration(days: 2)),
            last: DateTime.now().subtract(const Duration(days: 1)),
          ));
      final (status, reply) = await paczka('h12', token, 1, [
        wpis('m1', kiedy: DateTime.now().subtract(const Duration(days: 30))),
      ]);
      expect(status, 403);
      expect(reply?.reason, historyOverLimit);
      expect(await wiadomosci(bartek, alicja), isEmpty);
    });

    test('plik z historii pod inną nazwą niż wpis dostaje odmowę', () async {
      final token = await zapowiedz('h13', ile(2, files: 1, bytes: 3));
      // Wpis „zdjecie.jpg" bez treści, potem ten sam identyfikator jako
      // plik wykonywalny, który miałby się pod niego podpiąć.
      await paczka('h13', token, 1, [
        HistoryItem(
          messageGuid: 'f1',
          mine: true,
          sentAt: DateTime.now().subtract(const Duration(days: 1)),
          body: '📎 zdjecie.jpg',
          fileName: 'zdjecie.jpg',
          fileSize: 3,
        ),
      ]);
      await paczka('h13', token, 2, [wpis('f1', plik: 'zdjecie.exe', size: 3)]);
      final reply = await alicja.debugOfferFile(
        bartekUAlicji,
        FileOffer(
          messageGuid: 'f1',
          from: alicja.identity,
          fileName: 'zdjecie.exe',
          fileSize: 3,
          sentAt: DateTime.now(),
          history: 'h13',
        ),
      );
      expect(reply?.accepted, isFalse);
      expect(reply?.reason, historyNoGrant);
      final wiersz = await bartek.db.messageByGuid('f1');
      expect(wiersz?.fileName, 'zdjecie.jpg');
      expect(wiersz?.filePath, isNull);
    });

    test('plik z historii spoza zgody dostaje odmowę, nigdy zwykłą kartę',
        () async {
      await zapowiedz('h14', ile(1, files: 1, bytes: 3));
      for (final historia in ['h14', 'obca']) {
        final reply = await alicja.debugOfferFile(
          bartekUAlicji,
          FileOffer(
            messageGuid: 'niezapowiedziany',
            from: alicja.identity,
            fileName: 'x.txt',
            fileSize: 3,
            sentAt: DateTime.now(),
            history: historia,
          ),
        );
        expect(reply?.accepted, isFalse, reason: historia);
      }
      expect(kartyPlikow['Bartek'], isNull);
      expect(await bartek.db.messageByGuid('niezapowiedziany'), isNull);
    });

    test('druga karta od tego samego nadawcy to busy', () async {
      blokady['Bartek'] = Completer<void>();
      final pierwsza = alicja.debugSendSealed(
        bartekUAlicji,
        '/history-offer',
        HistoryOfferMessage(
          from: alicja.identity,
          op: historyOpOffer,
          id: 'h15',
          summary: ile(1),
        ).toJson(),
      );
      final koniec = DateTime.now().add(const Duration(seconds: 10));
      while (karty['Bartek'] == null) {
        if (DateTime.now().isAfter(koniec)) fail('karta nie przyszła');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final druga = await alicja.debugSendSealed(
        bartekUAlicji,
        '/history-offer',
        HistoryOfferMessage(
          from: alicja.identity,
          op: historyOpRequest,
          id: 'h16',
        ).toJson(),
      );
      expect(HistoryReply.fromJson(druga.reply, id: 'h16')?.reason,
          historyBusy);
      expect(karty['Bartek'], hasLength(1));
      blokady['Bartek']!.complete();
      expect((await pierwsza).status, 200);
    });

    test('przerwanie kończy zgodę, a to, co doszło, zostaje', () async {
      final token = await zapowiedz('h9', ile(4));
      await paczka('h9', token, 1, [wpis('m1')]);
      final wynik = await alicja.debugSendSealed(
        bartekUAlicji,
        '/history-offer',
        HistoryOfferMessage(
          from: alicja.identity,
          op: historyOpCancel,
          id: 'h9',
          token: token,
        ).toJson(),
      );
      expect(wynik.status, 200);
      expect((await paczka('h9', token, 2, [wpis('m2')])).$2?.reason,
          historyNoGrant);
      expect(await wiadomosci(bartek, alicja), hasLength(1));
      expect(bartek.incomingHistory.value, isNull);
    });
  });

  group('trasy historii bez koperty', () {
    Future<int> wyslijJawnie(AppServices do_, String sciezka, List<int> cialo)
        async {
      final client = HttpClient();
      try {
        final request = await client.post(
            '127.0.0.1', do_.server.port!, sciezka);
        request.headers.contentType = ContentType.json;
        request.add(cialo);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    test('jawne zapytania dostają 409 i nie zostawiają śladu', () async {
      final bartek = await instancja('Bartek');
      final ja = DeviceIdentity(
          guid: 'guid-obcy', name: 'Obcy', welcomeMessage: '', tcpPort: 1);
      final smieci = <List<int>>[
        const [],
        utf8.encode('to nie jest JSON'),
        utf8.encode(jsonEncode(HistoryOfferMessage(
          from: ja,
          op: historyOpOffer,
          id: 'h1',
          summary: HistorySummary(
            count: 1,
            files: 0,
            bytes: 0,
            first: DateTime(2026),
            last: DateTime(2026),
          ),
        ).toJson())),
        utf8.encode(jsonEncode(HistoryChunk(
          from: ja,
          id: 'h1',
          token: 'AAAA',
          seq: 1,
          items: [
            HistoryItem(
                messageGuid: 'm1', mine: true, sentAt: DateTime(2026), body: 'x'),
          ],
        ).toJson())),
      ];
      for (var i = 0; i < smieci.length; i++) {
        expect(await wyslijJawnie(bartek, '/history-offer', smieci[i]), 409,
            reason: '/history-offer #$i');
        expect(await wyslijJawnie(bartek, '/history-chunk', smieci[i]), 409,
            reason: '/history-chunk #$i');
      }
      expect(bartek.pendingHistory.value, isEmpty);
      expect(bartek.incomingHistory.value, isNull);
      expect(await bartek.db.allPeers(), isEmpty);
    });

    test('zapieczętowane, ale złego kształtu, dostaje 400 bez karty', () async {
      final alicja = await instancja('Alicja');
      final bartek = await instancja('Bartek');
      final bartekUAlicji =
          (await alicja.addPeerByAddress('127.0.0.1', bartek.server.port!))!;
      for (final (sciezka, tresc) in [
        ('/history-offer', <String, Object?>{
          'from': alicja.identity.toJson(),
          'op': historyOpOffer,
          'id': 'h1',
        }),
        ('/history-chunk', <String, Object?>{
          'from': alicja.identity.toJson(),
          'id': 'h1',
          'token': 'AAAA',
          'seq': 1,
          'items': const [],
        }),
      ]) {
        final wynik =
            await alicja.debugSendSealed(bartekUAlicji, sciezka, tresc);
        expect(wynik.status, 400, reason: sciezka);
      }
      expect(karty['Bartek'], isNull);
    });
  });

  group('kształty z sieci', () {
    final ja = DeviceIdentity(
      guid: 'guid-a',
      name: 'A',
      welcomeMessage: '',
      tcpPort: 1,
    );
    Map<String, Object?> pozycja(Map<String, Object?> zmiany) => {
          'g': 'm1',
          'm': true,
          't': DateTime.utc(2026).toIso8601String(),
          'b': 'tekst',
          ...zmiany,
        };
    Map<String, Object?> paczka(List<Object?> items) => {
          'from': ja.toJson(),
          'id': 'h1',
          'token': 'AAAA',
          'seq': 1,
          'items': items,
        };

    test('poprawna paczka przechodzi', () {
      final chunk = HistoryChunk.fromJson(paczka([
        pozycja({}),
        pozycja({'g': 'm2', 'fn': 'a.txt', 'fs': 3, 'ff': true}),
      ]));
      expect(chunk, isNotNull);
      expect(chunk!.items.last.isFile, isTrue);
      expect(chunk.items.last.fileFollows, isTrue);
    });

    test('zła pozycja odrzuca całą paczkę', () {
      for (final zla in [
        pozycja({'g': '../x'}),
        pozycja({'m': 'tak'}),
        pozycja({'t': 'wczoraj'}),
        pozycja({'b': 'x' * (maxHistoryBodyUnits + 1)}),
        pozycja({'fn': '', 'fs': 1}),
        pozycja({'fn': 'a' * (maxHistoryFileName + 1), 'fs': 1}),
        pozycja({'fn': 'a.txt', 'fs': -1}),
        pozycja({'fs': 3}),
        pozycja({'ff': true}),
      ]) {
        expect(HistoryChunk.fromJson(paczka([pozycja({}), zla])), isNull,
            reason: '$zla');
      }
      expect(HistoryChunk.fromJson(paczka([])), isNull);
      expect(
          HistoryChunk.fromJson(paczka(
              List.filled(maxHistoryChunkItems + 1, pozycja({})))),
          isNull);
    });

    test('zapowiedź z liczbami, które się nie składają, odpada', () {
      Map<String, Object?> zapowiedz(Map<String, Object?> summary) => {
            'from': ja.toJson(),
            'op': historyOpOffer,
            'id': 'h1',
            'summary': {
              'count': 2,
              'files': 1,
              'bytes': 5,
              'first': DateTime.utc(2025).toIso8601String(),
              'last': DateTime.utc(2026).toIso8601String(),
              ...summary,
            },
          };
      expect(HistoryOfferMessage.fromJson(zapowiedz({})), isNotNull);
      for (final zle in [
        {'count': 0},
        {'count': maxHistoryMessages + 1},
        {'files': 3},
        {'files': 0},
        {'bytes': -1},
        {'last': DateTime.utc(2024).toIso8601String()},
      ]) {
        expect(HistoryOfferMessage.fromJson(zapowiedz(zle)), isNull,
            reason: '$zle');
      }
      expect(
          HistoryOfferMessage.fromJson(
              {'from': ja.toJson(), 'op': historyOpDone, 'id': 'h1'}),
          isNull,
          reason: 'koniec bez tokenu');
      expect(
          HistoryOfferMessage.fromJson(
              {'from': ja.toJson(), 'op': 'delete', 'id': 'h1'}),
          isNull);
    });

    test('odpowiedź z polem from albo na inną historię nie przechodzi', () {
      final dobra = const HistoryReply(id: 'h1', accepted: true, token: 'AAAA')
          .toJson();
      expect(HistoryReply.fromJson(dobra, id: 'h1'), isNotNull);
      expect(HistoryReply.fromJson(dobra, id: 'h2'), isNull);
      expect(
          HistoryReply.fromJson({...dobra, 'from': ja.toJson()}, id: 'h1'),
          isNull);
      expect(
          HistoryChunkReply.fromJson(
              const HistoryChunkReply(id: 'h1', seq: 2, ok: true).toJson(),
              id: 'h1',
              seq: 1),
          isNull);
    });
  });
}
