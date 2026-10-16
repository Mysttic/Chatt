import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/core/remote_input.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';

/// Szyfrowanie ruchu między sparowanymi urządzeniami. Cały ruch od Alicji do
/// Bartka przechodzi przez podsłuchiwane łącze, więc testy patrzą dokładnie
/// na to, co widzi ktoś siedzący w sieci.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory work;
  late AppServices alice;
  late AppServices bob;
  late ServerSocket wire;
  late List<int> sniffed;

  /// To samo łącze w drugą stronę: wszystko, co Bartek odsyła Alicji.
  late List<int> sniffedBack;

  /// Ruch od Alicji osobno dla każdego połączenia, w kolejności otwarcia.
  /// Z tego da się odtworzyć pojedyncze zapytania: klient trzyma połączenie
  /// otwarte i wysyła nim kilka po kolei.
  late List<List<int>> connections;

  /// Po ilu bajtach łącze ma paść (0 = przepuszcza wszystko).
  late int cutAfter;

  /// Ujście klawiatury u Bartka: pole hasła w aplikacji banku. Ani tekst,
  /// ani to, dokąd trafia, nie ma prawa pokazać się na łączu.
  late _Ujscie ujscie;
  late List<PendingRemoteInput> pytaniaOPisanie;
  late Duration pingPrzedTestem;

  setUp(() async {
    work = Directory.systemTemp.createTempSync('chatt_enc');
    sniffed = [];
    sniffedBack = [];
    connections = [];
    cutAfter = 0;
    ujscie = _Ujscie(const RemoteInputTarget(
      active: true,
      field: RemoteInputField.password,
      action: RemoteInputAction.go,
      app: 'com.example.bank',
      appLabel: 'BankApp',
    ));
    pytaniaOPisanie = [];
    // Testy liczą paczki i wywołania ujścia, więc pingi nie mogą się wcinać.
    pingPrzedTestem = debugRemoteInputPingInterval;
    debugRemoteInputPingInterval = const Duration(hours: 1);
    alice = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Alicja',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'alice'),
      fileOfferPolicy: acceptAllFileOffers,
      remoteInputSink: _Ujscie(const RemoteInputTarget()),
    );
    bob = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Bartek',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'bob'),
      fileOfferPolicy: acceptAllFileOffers,
      remoteInputPolicy: (prosba) {
        pytaniaOPisanie.add(prosba);
        return acceptAllRemoteInput(prosba);
      },
      remoteInputSink: ujscie,
    );

    // Łącze Alicja -> Bartek z kopią wszystkiego, co przez nie leci.
    wire = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    wire.listen((client) async {
      final Socket target;
      try {
        target = await Socket.connect('127.0.0.1', bob.server.port!);
      } catch (_) {
        client.destroy(); // Bartek nie zyje: nie trzymamy Alicji w zawieszeniu
        return;
      }
      final mine = <int>[];
      connections.add(mine);
      var forwarded = 0;
      client.listen(
        (chunk) {
          sniffed.addAll(chunk);
          mine.addAll(chunk);
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
      target.listen(
        (chunk) {
          sniffedBack.addAll(chunk);
          client.add(chunk);
        },
        onDone: () => client.close(),
        onError: (Object _) => client.destroy(),
      );
    });
  });

  tearDown(() async {
    debugRemoteInputPingInterval = pingPrzedTestem;
    await wire.close();
    await alice.dispose();
    await bob.dispose();
    work.deleteSync(recursive: true);
  });

  String podsluch() => utf8.decode(sniffed, allowMalformed: true);
  String podsluchOdpowiedzi() => utf8.decode(sniffedBack, allowMalformed: true);

  /// Parowanie po podsłuchiwanym łączu. Zwraca rozmówcę Alicji.
  Future<Peer> pair() async {
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', wire.port);
    final code = await alice.startPairing(bobAsPeer!);
    expect(code, isNotNull);
    expect(podsluch().contains(code!), isFalse,
        reason: 'kod do porównania liczy się z sekretu, nie idzie przez sieć');
    expect(await alice.confirmPairing(bob.identity.guid),
        PairOutcome.accepted);
    expect(await bob.confirmPairing(alice.identity.guid),
        PairOutcome.accepted);

    // Bartek odpowiada wprost do Alicji, wiec ta zapisuje sobie jego
    // prawdziwy adres. Do testu wracamy na podsluchiwane lacze.
    await alice.db.upsertPeer(
      guid: bob.identity.guid,
      name: 'Bartek',
      welcomeMessage: '',
      host: '127.0.0.1',
      port: wire.port,
    );
    return (await alice.db.peerByGuid(bob.identity.guid))!;
  }

  test('sparowani: treść wiadomości nie leci jawnym tekstem', () async {
    final bobAsPeer = await pair();
    expect(bobAsPeer.verified, isTrue,
        reason: 'parowanie od protokołu 5 nie zapisuje klucza, tylko '
            'potwierdza tożsamość, klucz sesji jest efemeryczny');

    sniffed.clear();
    final conversation = await alice.openConversationWith(bobAsPeer);
    await alice.sendText(conversation, 'TAJNE-HASLO-DO-SEJFU');

    expect(podsluch().contains('TAJNE-HASLO-DO-SEJFU'), isFalse,
        reason: 'w sieci ma być szyfrogram');
    expect(podsluch().contains('"enc":1'), isTrue, reason: 'koperta');

    // A u Bartka wiadomość jest normalnie czytelna.
    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    final atBob = await bob.db.watchMessages(convAtBob).first;
    expect(atBob.last.body, 'TAJNE-HASLO-DO-SEJFU');
    expect((await alice.db.watchMessages(conversation).first).last.status,
        MessageStatus.delivered);
  });

  test('niesparowani: treść też nie leci jawnym tekstem', () async {
    // To jest teza wydania 0.2.0: szyfrowanie nie czeka na parowanie.
    // Parowanie odpowiada tylko na pytanie „z kim rozmawiam", a nie „czy
    // ktoś to przeczyta po drodze".
    final bobAsPeer = await alice.addPeerByAddress('127.0.0.1', wire.port);
    final conversation = await alice.openConversationWith(bobAsPeer!);
    await alice.sendText(conversation, 'JAWNA-TRESC');

    expect((await alice.db.watchMessages(conversation).first).last.status,
        MessageStatus.delivered,
        reason: 'bez parowania wiadomość ma dojść tak samo jak z parowaniem');
    expect(podsluch().contains('JAWNA-TRESC'), isFalse,
        reason: 'podsłuch na łączu nie ma prawa zobaczyć treści');
    expect((await alice.db.peerByGuid(bob.identity.guid))!.verified, isFalse,
        reason: 'i to wszystko bez sparowania');
  });

  test('sparowani: plik jedzie zaszyfrowany i składa się bajt w bajt',
      () async {
    final bobAsPeer = await pair();
    final conversation = await alice.openConversationWith(bobAsPeer);

    // Rozpoznawalny wzorzec: gdyby plik szedł jawnie, znajdziemy go w podsłuchu.
    final source = File(p.join(work.path, 'tajny-raport.txt'));
    source.writeAsStringSync('ZAWARTOSC-PLIKU-DO-ZNALEZIENIA\n' * 4000);
    sniffed.clear();

    await alice.sendFile(conversation, source.path);

    expect(podsluch().contains('ZAWARTOSC-PLIKU-DO-ZNALEZIENIA'), isFalse,
        reason: 'treść pliku ma być zaszyfrowana');
    expect(podsluch().contains('tajny-raport.txt'), isFalse,
        reason: 'nazwa pliku siedzi w zaszyfrowanej zapowiedzi, nie w nagłówku');

    final atAlice = (await alice.db.watchMessages(conversation).first).last;
    expect(atAlice.status, MessageStatus.delivered);

    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    final atBob = (await bob.db.watchMessages(convAtBob).first).last;
    expect(atBob.fileName, 'tajny-raport.txt',
        reason: 'prawdziwa nazwa przyszła w zapowiedzi');
    expect(File(atBob.filePath!).readAsBytesSync(), source.readAsBytesSync(),
        reason: 'po odszyfrowaniu plik musi być identyczny');
  });

  test('sparowani: wznowienie zaszyfrowanego pliku dosyła tylko resztę',
      () async {
    final bobAsPeer = await pair();
    final conversation = await alice.openConversationWith(bobAsPeer);

    final source = File(p.join(work.path, 'duzy.bin'));
    source.writeAsBytesSync(
        List<int>.generate(900 * 1024, (i) => (i * 7 + 11) % 256));

    // Łącze pada w połowie transferu.
    cutAfter = 300 * 1024;
    await alice.sendFile(conversation, source.path);
    var message = (await alice.db.watchMessages(conversation).first).last;
    expect(message.status, MessageStatus.failed);

    // U Bartka została zaszyfrowana część pliku.
    final parts = Directory(p.join(work.path, 'bob', '.incomplete'))
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.part'))
        .toList();
    expect(parts, hasLength(1));
    final partial = parts.single.lengthSync();
    expect(partial, greaterThan(0));
    expect(partial, lessThan(source.lengthSync()));

    // Sieć wraca: ponowienie ma dołożyć resztę, nie wysłać wszystkiego od nowa.
    cutAfter = 0;
    await alice.retryMessage(message.id);

    message = (await alice.db.watchMessages(conversation).first).last;
    expect(message.status, MessageStatus.delivered);

    final aliceAtBob = await bob.db.peerByGuid(alice.identity.guid);
    final convAtBob = await bob.db.ensureConversation(aliceAtBob!.id);
    final atBob = (await bob.db.watchMessages(convAtBob).first).last;
    expect(File(atBob.filePath!).readAsBytesSync(), source.readAsBytesSync(),
        reason: 'po odszyfrowaniu i sklejeniu plik musi być identyczny');
  });

  /// Rozpoznawalny tekst z polskimi znakami: gdyby szedł jawnie, podsłuch
  /// znalazłby go od razu.
  const sekret = 'TAJNE-HASŁO-KLAWIATURA-zażółć';

  /// Sparowani, dodatek włączony po obu stronach, a Bartek pozwala pisać.
  Future<Peer> sparowaniZKlawiatura() async {
    final bobAsPeer = await pair();
    await alice.setKeyboardAddon(true);
    await bob.setKeyboardAddon(true);
    expect(await bob.setRemoteInputReceive(true), isTrue);
    return bobAsPeer;
  }

  test('zdalna klawiatura: tekst, pole hasła i aplikacja nie lecą jawnie '
      'w żadną stronę', () async {
    final bobAsPeer = await sparowaniZKlawiatura();

    sniffed.clear();
    sniffedBack.clear();
    expect(await alice.startRemoteInput(bobAsPeer), RemoteInputStart.accepted);
    expect(alice.outgoingRemoteInput.value?.target.field,
        RemoteInputField.password,
        reason: 'rodzaj pola dochodzi do Alicji w kopercie');
    expect(alice.sendRemoteInput(const [RemoteInputOp.insert(sekret)]), isTrue);
    await alice.stopRemoteInput();

    final kierunki = {
      'Alicja -> Bartek': podsluch(),
      'Bartek -> Alicja': podsluchOdpowiedzi(),
    };
    kierunki.forEach((kierunek, ruch) {
      for (final zakazane in [
        sekret,
        'TAJNE-HAS',
        'KLAWIATURA',
        'password',
        'com.example.bank',
        'BankApp',
      ]) {
        expect(ruch.contains(zakazane), isFalse,
            reason: '„$zakazane" na łączu $kierunek');
      }
    });
    expect(podsluch().contains('"enc":1'), isTrue, reason: 'prośba i paczki');
    expect(podsluchOdpowiedzi().contains('"enc":1'), isTrue,
        reason: 'odpowiedzi też są w kopertach');

    expect(ujscie.ops, const [RemoteInputOp.insert(sekret)],
        reason: 'u Bartka tekst doszedł w całości');
    expect(bob.incomingRemoteInput.value, isNull, reason: 'stop zakończył');
  });

  test('zdalna klawiatura: powtórka z drutu po końcu sesji nic nie wpisze',
      () async {
    final bobAsPeer = await sparowaniZKlawiatura();

    expect(await alice.startRemoteInput(bobAsPeer), RemoteInputStart.accepted);
    expect(
        alice.sendRemoteInput(const [
          RemoteInputOp.insert(sekret),
          RemoteInputOp.action(),
        ]),
        isTrue);
    await alice.stopRemoteInput();
    expect(ujscie.ops, const [
      RemoteInputOp.insert(sekret),
      RemoteInputOp.action(),
    ]);
    expect(bob.incomingRemoteInput.value, isNull);

    // Wszystko, co podsłuch nagrał na drodze do zdalnej klawiatury.
    final nagrane = [
      for (final polaczenie in connections)
        for (final zapytanie in _zapytaniaHttp(polaczenie))
          if (zapytanie.sciezka == '/input-session' ||
              zapytanie.sciezka == '/input')
            zapytanie,
    ];
    expect(nagrane.where((z) => z.sciezka == '/input-session'), isNotEmpty,
        reason: 'podsłuch złapał prośbę o sesję');
    expect(nagrane.where((z) => z.sciezka == '/input').length,
        greaterThanOrEqualTo(2),
        reason: 'i paczki: tekst ze Enterem, potem stop');
    for (final zapytanie in nagrane) {
      expect(zapytanie.metoda, 'POST');
      // Cała koperta, bajt w bajt: inaczej Bartek odbiłby ją jako
      // nieczytelną i test nie sprawdzałby powtórki.
      final koperta = tryDecodeJsonMap(zapytanie.cialo);
      expect(koperta, isNotNull, reason: zapytanie.sciezka);
      expect(isEncryptedEnvelope(koperta!), isTrue, reason: zapytanie.sciezka);
    }

    final pytaniaPrzed = pytaniaOPisanie.length;
    final opsPrzed = [...ujscie.ops];
    final wywolaniaPrzed = [...ujscie.wywolania];

    // Napastnik odsyła nagrane koperty prosto do Bartka, bajt w bajt.
    final surowy = HttpClient();
    addTearDown(() => surowy.close(force: true));
    for (final zapytanie in nagrane) {
      final request =
          await surowy.post('127.0.0.1', bob.server.port!, zapytanie.sciezka);
      request.headers.contentType = ContentType.json;
      request.add(zapytanie.cialo);
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, anyOf(403, 409),
          reason: '${zapytanie.sciezka} odtworzone po końcu sesji');
    }

    expect(pytaniaOPisanie, hasLength(pytaniaPrzed),
        reason: 'prośba jest jednorazowa: żadnej nowej karty');
    expect(bob.pendingRemoteInput.value, isEmpty);
    expect(bob.incomingRemoteInput.value, isNull,
        reason: 'żadnej nowej zgody');
    expect(ujscie.ops, opsPrzed, reason: 'nic nie wpisane drugi raz');
    expect(ujscie.wywolania, wywolaniaPrzed,
        reason: 'ujście nie usłyszało niczego nowego');
  });
}

/// Ujście klawiatury w pamięci: zapisuje, co by wpisało, i odpowiada stałym
/// celem.
class _Ujscie implements RemoteInputSink {
  final ops = <RemoteInputOp>[];
  final wywolania = <String>[];
  final RemoteInputTarget cel;

  _Ujscie(this.cel);

  @override
  bool supported = true;

  @override
  Future<RemoteInputTarget> status() async {
    wywolania.add('status');
    return cel;
  }

  @override
  Future<RemoteInputApplied> apply(List<RemoteInputOp> nowe) async {
    wywolania.add('apply');
    ops.addAll(nowe);
    return (applied: true, target: cel);
  }

  @override
  Future<void> holdOwnApp(bool on) async {}

  @override
  Future<void> setSession({required bool active, String peerName = ''}) async =>
      wywolania.add('setSession:$active');

  @override
  Future<bool> setImeEnabled(bool on) async {
    wywolania.add('setImeEnabled:$on');
    return true;
  }
}

/// Zapytanie HTTP wyjęte z nagranego strumienia.
typedef _Zapytanie = ({String metoda, String sciezka, List<int> cialo});

/// Tnie nagrany strumień jednego połączenia na zapytania HTTP/1.1. Klient
/// trzyma połączenie otwarte (keep-alive), więc zapytań bywa w nim kilka.
/// Nazwy nagłówków bez względu na wielkość liter: klient z `dart:io` pisze
/// je małymi. Zapytanie urwane w połowie na końcu strumienia odpada.
List<_Zapytanie> _zapytaniaHttp(List<int> strumien) {
  final wynik = <_Zapytanie>[];
  var pozycja = 0;
  while (true) {
    final koniecNaglowkow = _szukaj(strumien, const [13, 10, 13, 10], pozycja);
    if (koniecNaglowkow < 0) break;
    final linie =
        latin1.decode(strumien.sublist(pozycja, koniecNaglowkow)).split('\r\n');
    final pierwsza = linie.first.split(' ');
    final naglowki = <String, String>{
      for (final linia in linie.skip(1))
        if (linia.contains(':'))
          linia.substring(0, linia.indexOf(':')).trim().toLowerCase():
              linia.substring(linia.indexOf(':') + 1).trim(),
    };

    var dalej = koniecNaglowkow + 4;
    var cialo = <int>[];
    if (naglowki['transfer-encoding']?.toLowerCase() == 'chunked') {
      while (true) {
        final koniecRozmiaru = _szukaj(strumien, const [13, 10], dalej);
        if (koniecRozmiaru < 0) return wynik;
        final rozmiar = int.parse(
          latin1
              .decode(strumien.sublist(dalej, koniecRozmiaru))
              .split(';')
              .first
              .trim(),
          radix: 16,
        );
        dalej = koniecRozmiaru + 2;
        if (rozmiar == 0) {
          dalej += 2; // pusta linia po ostatnim kawałku
          break;
        }
        if (dalej + rozmiar > strumien.length) return wynik;
        cialo.addAll(strumien.sublist(dalej, dalej + rozmiar));
        dalej += rozmiar + 2;
      }
    } else {
      final dlugosc = int.parse(naglowki['content-length'] ?? '0');
      if (dalej + dlugosc > strumien.length) break;
      cialo = strumien.sublist(dalej, dalej + dlugosc);
      dalej += dlugosc;
    }
    wynik.add((
      metoda: pierwsza.first,
      sciezka: pierwsza.length > 1 ? pierwsza[1] : '',
      cialo: cialo,
    ));
    pozycja = dalej;
  }
  return wynik;
}

/// Pierwsze wystąpienie [czego] w [gdzie] od pozycji [od], albo -1.
int _szukaj(List<int> gdzie, List<int> czego, int od) {
  for (var i = od; i + czego.length <= gdzie.length; i++) {
    var zgodne = true;
    for (var j = 0; j < czego.length; j++) {
      if (gdzie[i + j] != czego[j]) {
        zgodne = false;
        break;
      }
    }
    if (zgodne) return i;
  }
  return -1;
}
