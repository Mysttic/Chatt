import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/network/transport.dart';
import 'package:chatt/services/app_services.dart';

/// E2E transferu plików między dwiema pełnymi instancjami: zgoda odbiorcy,
/// streaming, postęp, weryfikacja bajt w bajt, suma kontrolna, wznawianie,
/// dedupe, odbiorca offline i retry.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory work;
  late AppServices alice;
  late AppServices bob;

  /// Prośby o zgodę, które zobaczył Bartek, i jego odpowiedź na nie.
  late List<PendingFileOffer> bobOffers;
  late bool bobAccepts;

  /// Hak odpalany, zanim Bartek odpowie. Testy zmieniają w nim świat pod
  /// nadawcą (na przykład pozwalają plikowi urosnąć), żeby sprawdzić, co
  /// zrobi zapowiedź, która przestała się zgadzać z paczką.
  void Function(PendingFileOffer offer)? bobBeforeAnswer;

  setUp(() async {
    work = Directory.systemTemp.createTempSync('chatt_files');
    bobOffers = [];
    bobAccepts = true;
    bobBeforeAnswer = null;
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
      fileOfferPolicy: (offer) async {
        bobOffers.add(offer);
        bobBeforeAnswer?.call(offer);
        return bobAccepts ? OfferDecision.accept : OfferDecision.reject;
      },
    );
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
    work.deleteSync(recursive: true);
  });

  File makeRandomFile(String name, int bytes) {
    final random = Random(42);
    final file = File(p.join(work.path, name));
    final sink = file.openSync(mode: FileMode.write);
    const chunkSize = 64 * 1024;
    var left = bytes;
    while (left > 0) {
      final chunk = List<int>.generate(min(chunkSize, left), (_) => random.nextInt(256));
      sink.writeFromSync(chunk);
      left -= chunk.length;
    }
    sink.closeSync();
    return file;
  }

  /// Gniazda w atrapach łącza. Zapis do gniazda, które druga strona zdążyła
  /// już zamknąć (odbiorca odrzucił plik, test zerwał kabel), zgłasza błąd
  /// przez `done`, a nieobsłużony wywraca cały test. Na Windowsie domknięcie
  /// przychodzi zwykle za późno, żeby to zobaczyć; na Linuksie leci
  /// „Broken pipe" i test się sypie mimo poprawnych asercji, tak wyszło
  /// dopiero na CI. Atrapa ma ten błąd pochłonąć: sprawdzamy zachowanie
  /// aplikacji, a nie to, które gniazdo zamknęło się pierwsze.
  void pochlonBledyZapisu(Socket socket) {
    socket.done.then((_) {}, onError: (Object _) {});
  }

  test('kilka plików naraz idzie po kolei, ale z jednym pytaniem o zgodę',
      () async {
    final pierwszy = makeRandomFile('pierwszy.bin', 64 * 1024);
    final drugi = makeRandomFile('drugi.bin', 32 * 1024);
    final trzeci = makeRandomFile('trzeci.bin', 16 * 1024);
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final conversation = await alice.openConversationWith(bobAsPeer!);

    // Tą drogą idzie i wybór kilku plików z okna, i przeciągnięcie ich na okno,
    // i wklejenie ze schowka.
    await alice.sendFiles(
      conversation,
      [pierwszy.path, drugi.path, trzeci.path],
    );

    // Jedno pytanie na całą paczkę, i to pytanie musi wymienić, na co idzie
    // zgoda: inaczej użytkownik godzi się na coś, czego nie widział.
    expect(bobOffers, hasLength(1));
    final paczka = bobOffers.single.batch;
    expect(paczka, isNotNull);
    expect(paczka!.count, 3);
    expect(paczka.names, ['pierwszy.bin', 'drugi.bin', 'trzeci.bin']);
    expect(paczka.bytes, (64 + 32 + 16) * 1024);

    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    final uBartka = await bob.db.watchMessages(convAtBob).first;
    expect(uBartka.map((m) => m.fileName),
        ['pierwszy.bin', 'drugi.bin', 'trzeci.bin']);
    for (final wiadomosc in uBartka) {
      expect(File(wiadomosc.filePath!).lengthSync(), wiadomosc.fileSize);
    }

    final uAlicji = await alice.db.watchMessages(conversation).first;
    expect(uAlicji.every((m) => m.status == MessageStatus.delivered), isTrue);
  });

  test('jeden plik to nie paczka: pytanie wygląda jak zawsze', () async {
    final sam = makeRandomFile('sam.bin', 8 * 1024);
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final conversation = await alice.openConversationWith(bobAsPeer!);

    await alice.sendFiles(conversation, [sam.path]);

    expect(bobOffers, hasLength(1));
    expect(bobOffers.single.batch, isNull);
    expect(bobOffers.single.fileName, 'sam.bin');
    expect(bobOffers.single.fileCount, 1);
  });

  test('odmowa dotyczy całej paczki i zatrzymuje nadawcę', () async {
    bobAccepts = false;
    final pliki = [
      makeRandomFile('a.bin', 4 * 1024),
      makeRandomFile('b.bin', 4 * 1024),
      makeRandomFile('c.bin', 4 * 1024),
    ];
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final conversation = await alice.openConversationWith(bobAsPeer!);

    await alice.sendFiles(conversation, pliki.map((f) => f.path).toList());

    // Jedno „nie" zamyka paczkę: drugi raz nikt nie pyta.
    expect(bobOffers, hasLength(1));

    // I nadawca przestaje zapowiadać resztę, zamiast liczyć sumy kontrolne
    // stu plików, których nikt nie przyjmie.
    final uAlicji = await alice.db.watchMessages(conversation).first;
    expect(uAlicji, hasLength(1));
    expect(uAlicji.single.status, MessageStatus.failed);

    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    expect(await bob.db.watchMessages(convAtBob).first, isEmpty);
  });

  test('cisza na karcie to nie odmowa: następny plik pyta jeszcze raz',
      () async {
    // Brak odpowiedzi wygląda z zewnątrz jak odmowa (plik nie wchodzi), ale
    // nie ma zamykać paczki: nikt nie podjął decyzji.
    final pytania = <PendingFileOffer>[];
    final milczek = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Milczek',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'milczek_received'),
      fileOfferPolicy: (offer) async {
        pytania.add(offer);
        return OfferDecision.noAnswer;
      },
    );
    addTearDown(milczek.dispose);

    final pliki = [
      makeRandomFile('x.bin', 2 * 1024),
      makeRandomFile('y.bin', 2 * 1024),
    ];
    final peer =
        await alice.addPeerByAddress('127.0.0.1', milczek.server.port!);
    final conversation = await alice.openConversationWith(peer!);

    await alice.sendFiles(conversation, pliki.map((f) => f.path).toList());

    expect(pytania, hasLength(2));
    expect(pytania.map((o) => o.fileName), ['x.bin', 'y.bin']);
    // I drugie pytanie nadal jest pytaniem o paczkę. Nadawca powtarza jej
    // opis, dopóki ktoś nie odpowie: bez tego chwila nieuwagi rozbijała
    // paczkę na tyle osobnych pytań, ile plików, i to nieodwracalnie.
    expect(pytania.every((o) => o.batch != null), isTrue);
    expect(pytania.last.batch!.names, ['x.bin', 'y.bin']);
  });

  test('plik ponad zapowiedziane bajty wypada z paczki i pyta osobno',
      () async {
    // Zgoda z góry jest warta tyle, ile zapowiedź, na której ją wydano.
    // Plik, który po drodze urósł, nie jest już tym, na co ktoś się zgodził,
    // więc wraca do zwykłego pytania zamiast wejść na cudzą zgodę.
    final a = makeRandomFile('a.bin', 4 * 1024);
    final b = makeRandomFile('b.bin', 4 * 1024);
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final conversation = await alice.openConversationWith(bobAsPeer!);

    bobBeforeAnswer = (offer) {
      // Paczkę zapowiedziano na osiem kilobajtów; b urasta do sześćdziesięciu
      // czterech, zanim nadawca zdąży go zapowiedzieć.
      if (offer.batch != null) makeRandomFile('b.bin', 64 * 1024);
    };

    await alice.sendFiles(conversation, [a.path, b.path]);

    expect(bobOffers, hasLength(2));
    expect(bobOffers.first.batch, isNotNull);
    expect(bobOffers.last.fileName, 'b.bin');
    expect(bobOffers.last.batch, isNull,
        reason: 'drugie pytanie dotyczy już samego pliku, nie paczki');
    expect(bobOffers.last.fileSize, 64 * 1024);
  });

  test('katalog podany razem z plikami jest pomijany bez wywrotki', () async {
    final plik = makeRandomFile('jedyny.bin', 8 * 1024);
    final katalog = Directory(p.join(work.path, 'jakis-katalog'))
      ..createSync();
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final conversation = await alice.openConversationWith(bobAsPeer!);

    await alice.sendFiles(conversation, [katalog.path, plik.path]);

    expect(bobOffers.map((o) => o.fileName), ['jedyny.bin']);
  });

  test('plik 3 MB dochodzi w całości, bajt w bajt', () async {
    final source = makeRandomFile('zdjecie.bin', 3 * 1024 * 1024 + 137);
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final conversation = await alice.openConversationWith(bobAsPeer!);

    await alice.sendFile(conversation, source.path);

    // Bartek dostał zapowiedź z nazwą i rozmiarem, zanim poszły bajty.
    expect(bobOffers, hasLength(1));
    expect(bobOffers.single.fileName, 'zdjecie.bin');
    expect(bobOffers.single.fileSize, source.lengthSync());
    expect(bobOffers.single.resumeFrom, 0);

    final atAlice = (await alice.db.watchMessages(conversation).first).single;
    expect(atAlice.kind, MessageKind.file);
    expect(atAlice.status, MessageStatus.delivered);
    expect(atAlice.fileName, 'zdjecie.bin');

    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    final atBob = (await bob.db.watchMessages(convAtBob).first).single;
    expect(atBob.kind, MessageKind.file);
    expect(atBob.fileName, 'zdjecie.bin');
    expect(atBob.fileSize, source.lengthSync());

    final saved = File(atBob.filePath!);
    expect(saved.existsSync(), isTrue);
    expect(saved.lengthSync(), source.lengthSync());
    expect(saved.readAsBytesSync(), source.readAsBytesSync(),
        reason: 'zawartość musi być identyczna');
    expect(saved.path, startsWith(p.join(work.path, 'bob_received')));
    expect(
        Directory(p.join(work.path, 'bob_received', '.incomplete'))
            .listSync()
            .whereType<File>(),
        isEmpty,
        reason: 'po udanym transferze nie zostaje ani część, ani jej opis');

    // Retry mimo sukcesu (zgubiony ACK): u Bartka nie przybywa ani wiadomość,
    // ani plik.
    await alice.retryMessage(atAlice.id);
    final bobMessages = await bob.db.watchMessages(convAtBob).first;
    expect(bobMessages, hasLength(1));
    final receivedFiles = Directory(p.join(work.path, 'bob_received'))
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.endsWith('.part'));
    expect(receivedFiles, hasLength(1));
    expect(bobOffers, hasLength(1),
        reason: 'ponowienie kończy się na zapowiedzi ("już to mam"), '
            'użytkownik nie jest pytany drugi raz');
  });

  test('odbiorca offline: failed, retry po powrocie dostarcza', () async {
    final source = makeRandomFile('raport.pdf', 256 * 1024);
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final conversation = await alice.openConversationWith(bobAsPeer!);

    await bob.server.stop();
    await alice.sendFile(conversation, source.path);
    var message = (await alice.db.watchMessages(conversation).first).single;
    expect(message.status, MessageStatus.failed);

    await bob.server.start(preferredPort: bobAsPeer.port);
    await alice.retryMessage(message.id);
    message = (await alice.db.watchMessages(conversation).first).single;
    expect(message.status, MessageStatus.delivered);

    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    final atBob = (await bob.db.watchMessages(convAtBob).first).single;
    expect(File(atBob.filePath!).lengthSync(), source.lengthSync());
  });

  test('odmowa odbiorcy: żaden bajt nie leci, po zgodzie retry dostarcza',
      () async {
    final source = makeRandomFile('umowa.pdf', 128 * 1024);
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
    final conversation = await alice.openConversationWith(bobAsPeer!);

    bobAccepts = false;
    await alice.sendFile(conversation, source.path);

    var message = (await alice.db.watchMessages(conversation).first).single;
    expect(message.status, MessageStatus.failed);
    expect(bobOffers, hasLength(1));

    // U Bartka nie ma ani wiadomości, ani żadnego pliku na dysku.
    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    expect(await bob.db.watchMessages(convAtBob).first, isEmpty);
    expect(
        Directory(p.join(work.path, 'bob_received')).listSync().whereType<File>(),
        isEmpty);

    // Zmiana zdania: ponowienie tej samej wiadomości dochodzi normalnie.
    bobAccepts = true;
    await alice.retryMessage(message.id);
    message = (await alice.db.watchMessages(conversation).first).single;
    expect(message.status, MessageStatus.delivered);
    final atBob = (await bob.db.watchMessages(convAtBob).first).single;
    expect(File(atBob.filePath!).lengthSync(), source.lengthSync());
  });

  test('uszkodzenie w locie: plik odrzucony, nic nie ląduje w odebranych',
      () async {
    final source = makeRandomFile('podmieniony.bin', 256 * 1024);

    // Łącze, które przekręca jeden bajt gdzieś w środku transferu. Suma
    // kontrolna przyszła wcześniej w zaszyfrowanej zapowiedzi, więc odbiorca
    // ma z czym porównać to, co złożył.
    var przekrecone = false;
    final psujaceLacze = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    psujaceLacze.listen((client) async {
      final target = await Socket.connect('127.0.0.1', bob.server.port!);
      pochlonBledyZapisu(client);
      pochlonBledyZapisu(target);
      var forwarded = 0;
      client.listen(
        (chunk) {
          forwarded += chunk.length;
          if (!przekrecone && forwarded > 100 * 1024) {
            przekrecone = true;
            final kopia = List<int>.from(chunk);
            kopia[0] = kopia[0] ^ 0xff;
            target.add(kopia);
            return;
          }
          target.add(chunk);
        },
        onDone: () => target.close(),
        onError: (Object _) => target.destroy(),
      );
      target.listen(client.add,
          onDone: () => client.close(), onError: (Object _) => client.destroy());
    });
    addTearDown(() => psujaceLacze.close());

    final bobAsPeer =
        await alice.addPeerByAddress('127.0.0.1', psujaceLacze.port);
    final conversation = await alice.openConversationWith(bobAsPeer!);
    await alice.sendFile(conversation, source.path);

    expect(przekrecone, isTrue, reason: 'test ma sens tylko, gdy coś zepsuł');
    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    expect(await bob.db.watchMessages(convAtBob).first, isEmpty,
        reason: 'uszkodzony plik nie ma prawa trafić do rozmowy');
    expect(
        Directory(p.join(work.path, 'bob_received')).listSync().whereType<File>(),
        isEmpty,
        reason: 'ani do katalogu odebranych');
  });

  test('rozmiar z nagłówka musi zgadzać się z zapowiedzią', () async {
    // Nagłówki zaszyfrowanego transferu nie są uwierzytelnione, a to rozmiar
    // z nagłówka rządzi zapisem na dysku. Bez porównania z zapowiedzią zgoda
    // na jeden mały plik pozwalała przysłać dowolnie dużo, a przy paczce tyle
    // razy, ile plików w spisie.
    final source = makeRandomFile('maly.bin', 4 * 1024);
    final igla = utf8.encode('$headerFileSize:');
    var podmieniono = false;

    int znajdz(List<int> gdzie, List<int> co) {
      for (var i = 0; i + co.length <= gdzie.length; i++) {
        var pasuje = true;
        for (var j = 0; j < co.length && pasuje; j++) {
          pasuje = gdzie[i + j] == co[j];
        }
        if (pasuje) return i;
      }
      return -1;
    }

    final klamliweLacze =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    klamliweLacze.listen((client) async {
      final target = await Socket.connect('127.0.0.1', bob.server.port!);
      pochlonBledyZapisu(client);
      pochlonBledyZapisu(target);
      client.listen(
        (chunk) {
          final at = podmieniono ? -1 : znajdz(chunk, igla);
          if (at < 0) {
            target.add(chunk);
            return;
          }
          var od = at + igla.length;
          while (od < chunk.length && chunk[od] == 0x20) {
            od++;
          }
          var koniec = od;
          while (koniec < chunk.length &&
              chunk[koniec] >= 0x30 &&
              chunk[koniec] <= 0x39) {
            koniec++;
          }
          podmieniono = true;
          target.add([
            ...chunk.sublist(0, od),
            ...utf8.encode('99999999'),
            ...chunk.sublist(koniec),
          ]);
        },
        onDone: () => target.close(),
        onError: (Object _) => target.destroy(),
      );
      target.listen(client.add,
          onDone: () => client.close(), onError: (Object _) => client.destroy());
    });
    addTearDown(() => klamliweLacze.close());

    final bobAsPeer =
        await alice.addPeerByAddress('127.0.0.1', klamliweLacze.port);
    final conversation = await alice.openConversationWith(bobAsPeer!);
    await alice.sendFile(conversation, source.path);

    expect(podmieniono, isTrue, reason: 'test ma sens tylko, gdy coś skłamał');
    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    expect(await bob.db.watchMessages(convAtBob).first, isEmpty);
    expect(
        Directory(p.join(work.path, 'bob_received')).listSync().whereType<File>(),
        isEmpty,
        reason: 'ani bajtu z transferu, który skłamał o swoim rozmiarze');
  });

  test('część z poprzedniej sesji nie jest dopisywana, transfer rusza od zera',
      () async {
    final source = makeRandomFile('film.bin', 512 * 1024);

    // Łącze zrywa transfer w połowie: u Bartka zostaje część pliku.
    var cutAfter = 200 * 1024;
    final flakyLink = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    flakyLink.listen((client) async {
      final target = await Socket.connect('127.0.0.1', bob.server.port!);
      pochlonBledyZapisu(client);
      pochlonBledyZapisu(target);
      var forwarded = 0;
      client.listen(
        (chunk) {
          forwarded += chunk.length;
          if (cutAfter > 0 && forwarded > cutAfter) {
            client.destroy();
            target.destroy();
            return;
          }
          target.add(chunk);
        },
        onDone: () => target.close(),
        onError: (Object _) => target.destroy(),
      );
      target.listen(client.add,
          onDone: () => client.close(), onError: (Object _) => client.destroy());
    });
    addTearDown(() => flakyLink.close());

    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', flakyLink.port);
    final conversation = await alice.openConversationWith(bobAsPeer!);
    final message = (await alice.db.watchMessages(
            await alice.openConversationWith(bobAsPeer))
        .first);
    expect(message, isEmpty);

    await alice.sendFile(conversation, source.path);
    expect((await alice.db.watchMessages(conversation).first).single.status,
        MessageStatus.failed,
        reason: 'transfer się urwał');
    final part = Directory(p.join(work.path, 'bob_received', '.incomplete'))
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.part'));
    expect(part, isNotEmpty, reason: 'kawałek został do dokończenia');

    // Obie strony zaczynają od nowa: klucz pliku wisi na kluczu sesji, więc
    // po jej wymianie stara część jest zaszyfrowana czymś innym. Dopisanie do
    // niej dałoby plik, którego nie da się odszyfrować w całości, dlatego
    // zapowiedź niesie znacznik klucza, a odbiorca każe zacząć od zera.
    await alice.dispose();
    alice = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Alicja',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'alice_received2'),
      fileOfferPolicy: acceptAllFileOffers,
    );
    cutAfter = 0; // kabel już nie zrywa

    final bobPonownie =
        await alice.addPeerByAddress('127.0.0.1', flakyLink.port);
    final rozmowaPonownie = await alice.openConversationWith(bobPonownie!);
    await alice.sendFile(rozmowaPonownie, source.path);

    final wyslana =
        (await alice.db.watchMessages(rozmowaPonownie).first).single;
    expect(wyslana.status, MessageStatus.delivered);

    final odebrane = Directory(p.join(work.path, 'bob_received'))
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('film.bin'))
        .toList();
    expect(odebrane, hasLength(1));
    expect(odebrane.single.readAsBytesSync(), source.readAsBytesSync(),
        reason: 'plik złożony od zera musi być bajt w bajt taki sam');
  });

  test('nadawca wznawia po zerwaniu sieci: druga próba dosyła tylko resztę',
      () async {
    final source = makeRandomFile('film-duzy.bin', 2 * 1024 * 1024);

    // Kabel, który zrywa się po [cutAfter] bajtach na połączenie.
    var cutAfter = 300 * 1024;
    final flakyLink = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    flakyLink.listen((client) async {
      final target = await Socket.connect('127.0.0.1', bob.server.port!);
      pochlonBledyZapisu(client);
      pochlonBledyZapisu(target);
      var forwarded = 0;
      client.listen(
        (chunk) {
          forwarded += chunk.length;
          if (cutAfter > 0 && forwarded > cutAfter) {
            client.destroy();
            target.destroy();
            return;
          }
          target.add(chunk);
        },
        onDone: () => target.close(),
        onError: (Object _) => target.destroy(),
      );
      target.listen(client.add,
          onDone: () => client.close(), onError: (Object _) => client.destroy());
    });
    addTearDown(() => flakyLink.close());

    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', flakyLink.port);
    final conversation = await alice.openConversationWith(bobAsPeer!);

    await alice.sendFile(conversation, source.path);
    var message = (await alice.db.watchMessages(conversation).first).single;
    expect(message.status, MessageStatus.failed, reason: 'transfer się urwał');

    // U Bartka nie ma jeszcze wiadomości, ale jest kawałek pliku.
    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    expect(await bob.db.watchMessages(convAtBob).first, isEmpty);
    final parts = Directory(p.join(work.path, 'bob_received', '.incomplete'))
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.part'))
        .toList();
    expect(parts, hasLength(1));
    final partial = parts.single.lengthSync();
    expect(partial, greaterThan(0));
    expect(partial, lessThan(source.lengthSync()));

    // Sieć wraca, użytkownik ponawia.
    cutAfter = 0;
    await alice.retryMessage(message.id);

    message = (await alice.db.watchMessages(conversation).first).single;
    expect(message.status, MessageStatus.delivered);
    expect(bobOffers, hasLength(2),
        reason: 'jedno ponowienie = dokładnie jedno pytanie o zgodę');
    expect(bobOffers.last.resumeFrom, partial,
        reason: 'wznawiamy dokładnie od tego, co Bartek już ma');

    final atBob = (await bob.db.watchMessages(convAtBob).first).single;
    expect(File(atBob.filePath!).readAsBytesSync(), source.readAsBytesSync(),
        reason: 'sklejony plik musi być identyczny z oryginałem');
  });

  test('uszkodzone metadane -> 400, serwer żyje dalej', () async {
    final ok = await alice.client.sendFile(
      route: IpRoute('127.0.0.1', bob.server.port!),
      headers: {'x-chatt-message-guid': 'x'}, // brak reszty nagłówków
      file: makeRandomFile('smieci.bin', 1024),
    );
    expect(ok.delivered, isFalse);
    expect(await alice.client.fetchInfo(IpRoute('127.0.0.1', bob.server.port!)), isNotNull);
  });
}
