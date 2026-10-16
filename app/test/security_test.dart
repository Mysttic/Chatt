import 'dart:convert';
import 'dart:io';

import 'package:chatt/core/identity.dart';
import 'package:chatt/core/received_paths.dart';
import 'package:chatt/core/remote_input.dart';
import 'package:chatt/network/bt_link.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Rzeczy, które psuje **napastnik**, a nie użytkownik: napisy z sieci
/// wchodzące w ścieżki plików i zapytania liczone na wyczerpanie pamięci.
///
/// Wszystkie te testy powstały po przeglądzie bezpieczeństwa wydania 0.3.0
/// i każdy z nich zapalał się na czerwono przed poprawką.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// Identyfikatory, którymi da się wyjść z katalogu aplikacji. Ostatni jest
  /// groźny na Windowsie, gdzie backslash też jest separatorem.
  final zlosliweGuidy = [
    '../../../../evil',
    '..\\..\\..\\evil',
    '/etc/chatt',
    'a/b',
    'x' * 200,
    '',
  ];

  group('identyfikator wiadomości z sieci', () {
    test('zapowiedź pliku ze ścieżką w identyfikatorze jest odrzucana', () {
      for (final guid in zlosliweGuidy) {
        final json = {
          'messageGuid': guid,
          'from': const DeviceIdentity(
            guid: 'x',
            name: 'Napastnik',
            welcomeMessage: '',
            tcpPort: 47780,
            publicKey: <int>[],
          ).toJson(),
          'fileName': 'niewinny.jpg',
          'fileSize': 10,
          'sentAt': DateTime.now().toUtc().toIso8601String(),
        };
        expect(FileOffer.fromJson(json), isNull, reason: guid);
      }
    });

    test('wiadomość ze ścieżką w identyfikatorze jest odrzucana', () {
      for (final guid in zlosliweGuidy) {
        final json = {
          'messageGuid': guid,
          'from': const DeviceIdentity(
            guid: 'x',
            name: 'Napastnik',
            welcomeMessage: '',
            tcpPort: 47780,
            publicKey: <int>[],
          ).toJson(),
          'text': 'cześć',
          'sentAt': DateTime.now().toUtc().toIso8601String(),
        };
        expect(IncomingMessage.fromJson(json), isNull, reason: guid);
      }
    });

    test('nagłówki transferu ze ścieżką w identyfikatorze są odrzucane', () {
      for (final guid in zlosliweGuidy) {
        final headers = {
          headerMessageGuid: guid,
          headerFrom: encodeIdentityHeader(const DeviceIdentity(
            guid: 'x',
            name: 'Napastnik',
            welcomeMessage: '',
            tcpPort: 47780,
            publicKey: <int>[],
          )),
          headerFileName: 'niewinny.jpg',
          headerFileSize: '10',
        };
        expect(IncomingFileMeta.fromHeaders(headers), isNull, reason: guid);
      }
    });

    test('zwykły UUID przechodzi', () {
      final json = {
        'messageGuid': '2f1a9c74-0d3e-4f21-9a55-7b1d2c3e4f50',
        'from': const DeviceIdentity(
          guid: 'x',
          name: 'Ktoś',
          welcomeMessage: '',
          tcpPort: 47780,
          publicKey: <int>[],
        ).toJson(),
        'fileName': 'raport.pdf',
        'fileSize': 10,
        'sentAt': DateTime.now().toUtc().toIso8601String(),
      };
      expect(FileOffer.fromJson(json), isNotNull);
    });
  });

  group('paczka plików: zgoda z góry ma granice', () {
    Map<String, Object?> zapowiedz(Object? batchId, Object? batch) => {
          'messageGuid': '2f1a9c74-0d3e-4f21-9a55-7b1d2c3e4f50',
          'from': const DeviceIdentity(
            guid: 'x',
            name: 'Ktoś',
            welcomeMessage: '',
            tcpPort: 47780,
            publicKey: <int>[],
          ).toJson(),
          'fileName': 'a.bin',
          'fileSize': 10,
          'sentAt': DateTime.now().toUtc().toIso8601String(),
          'batchId': batchId,
          'batch': batch,
        };

    Map<String, Object?> paczka({
      Object? count = 2,
      Object? bytes = 20,
      Object? names = const ['a.bin', 'b.bin'],
    }) =>
        {'count': count, 'bytes': bytes, 'names': names};

    test('identyfikator paczki trzyma ten sam kształt co identyfikator wiadomości',
        () {
      // Ten napis jest kluczem zapamiętanej zgody, więc przyjmujemy pod nim
      // dokładnie tyle, co pod identyfikatorem wiadomości.
      for (final zly in zlosliweGuidy) {
        final offer = FileOffer.fromJson(zapowiedz(zly, paczka()));
        expect(offer, isNotNull, reason: zly);
        expect(offer!.batchId, isNull, reason: zly);
        expect(offer.batch, isNull, reason: zly);
      }
    });

    test('zepsuty opis paczki znaczy „nie ma paczki", a nie odmowa', () {
      // Pytanie o każdy plik osobno jest gorsze, ale nigdy szkodliwe;
      // odrzucenie zapowiedzi gubiłoby plik przez błąd nadawcy.
      final zle = <Object?>[
        null,
        'nie mapa',
        paczka(count: 1), // paczka z jednego pliku to nie paczka
        paczka(count: 0),
        paczka(count: maxBatchFiles + 1),
        paczka(count: 'dużo'),
        paczka(bytes: -1),
        paczka(bytes: null),
        paczka(names: const ['a.bin']), // spis krótszy niż liczba plików
        paczka(names: const ['a.bin', '']),
        paczka(names: const ['a.bin', 42]),
        paczka(names: 'a.bin, b.bin'),
        paczka(names: ['a.bin', 'x' * 256]),
      ];
      for (final batch in zle) {
        final offer = FileOffer.fromJson(zapowiedz('paczka-1', batch));
        expect(offer, isNotNull, reason: '$batch');
        expect(offer!.batch, isNull, reason: '$batch');
      }
    });

    test('poprawna paczka przechodzi w całości', () {
      final offer = FileOffer.fromJson(zapowiedz('paczka-1', paczka()));
      expect(offer?.batchId, 'paczka-1');
      expect(offer?.batch?.count, 2);
      expect(offer?.batch?.bytes, 20);
      expect(offer?.batch?.names, ['a.bin', 'b.bin']);
    });

    test('zapowiedź bez paczki wygląda tak, jak wyglądała zawsze', () {
      // Nadawca w starszej wersji nie wie o paczkach: jego zapowiedź ma
      // przejść bez zmian i skończyć się pytaniem o ten jeden plik.
      final json = zapowiedz(null, null)
        ..remove('batchId')
        ..remove('batch');
      final offer = FileOffer.fromJson(json);
      expect(offer, isNotNull);
      expect(offer!.batchId, isNull);
      expect(offer.batch, isNull);
    });
  });

  group('ścieżki plików nie wychodzą poza katalog aplikacji', () {
    final katalog = p.join('C:', 'dane', 'received');

    test('część transferu i jej opis zostają w środku', () {
      for (final guid in [...zlosliweGuidy, 'zwykly-guid']) {
        for (final sciezka in [
          partPath(katalog, guid),
          partMetaPath(katalog, guid),
        ]) {
          expect(p.isWithin(katalog, sciezka), isTrue,
              reason: '$guid -> $sciezka');
        }
      }
    });

    test('plik docelowy zostaje w środku mimo nazwy ze ścieżką', () {
      const nazwy = [
        '../../../../evil.exe',
        '..\\..\\..\\evil.exe',
        '/etc/passwd',
        'zwykla.jpg',
        '..',
      ];
      for (final nazwa in nazwy) {
        for (final guid in zlosliweGuidy) {
          final sciezka = receivedFilePath(katalog, guid, nazwa);
          expect(p.isWithin(katalog, sciezka), isTrue,
              reason: '$guid / $nazwa -> $sciezka');
        }
      }
    });

    test('różne identyfikatory dają różne pliki', () {
      // Gdyby oczyszczanie sklejało identyfikatory do jednej nazwy, dwa
      // równoległe transfery pisałyby do tego samego pliku.
      final a = partPath(katalog, 'a/b');
      final b = partPath(katalog, 'a_b');
      expect(a, isNot(b));
    });
  });

  group('serwer nie daje się wywrócić rozmiarem zapytania', () {
    late AppServices bob;

    setUp(() async {
      bob = await AppServices.start(
        executor: NativeDatabase.memory(),
        portOverride: 0,
        nameOverride: 'Bartek',
        enableDiscovery: false,
        receivedDirOverride:
            Directory.systemTemp.createTempSync('chatt_sec').path,
      );
    });

    tearDown(() => bob.dispose());

    test('wielkie ciało zapytania nie jest wczytywane, a serwer żyje dalej',
        () async {
      final client = HttpClient();
      int? status;
      try {
        final request =
            await client.post('127.0.0.1', bob.server.port!, '/message');
        request.headers.contentType = ContentType.json;
        // Osiem megabajtów śmieci. Bez granicy serwer wczytałby to w całości
        // do pamięci, zanim w ogóle sprawdzi, czy nadawca ma sesję, a takich
        // zapytań można wysłać ile się chce.
        final kawalek = List<int>.filled(64 * 1024, 65);
        for (var i = 0; i < 128; i++) {
          request.add(kawalek);
        }
        final response = await request.close();
        await response.drain<void>();
        status = response.statusCode;
      } on SocketException {
        // Serwer przerwał połączenie w trakcie wysyłania, też dobrze,
        // bo znaczy, że przestał czytać. Który wariant wyjdzie, zależy od
        // buforów gniazda, więc test nie wymaga konkretnego.
      }
      if (status != null) expect(status, 413);

      // Rzecz najważniejsza: serwer po tym nadal odpowiada.
      final info = await client.get('127.0.0.1', bob.server.port!, '/info');
      final infoResponse = await info.close();
      final tresc = await infoResponse.transform(utf8.decoder).join();
      expect(infoResponse.statusCode, 200);
      expect(tresc, contains('"app":"chatt"'));
      client.close(force: true);
    });
  });

  group('zdalna klawiatura: paczka z sieci ma ścisły kształt', () {
    const nadawca = DeviceIdentity(
      guid: 'x',
      name: 'Napastnik',
      welcomeMessage: '',
      tcpPort: 47780,
      publicKey: <int>[],
    );
    const sesja = '2f1a9c74-0d3e-4f21-9a55-7b1d2c3e4f50';
    const token = 'dG9rZW4tdGVzdG93eQ==';

    Map<String, Object?> wpisz(Object? s) => {'t': 'insert', 's': s};

    /// Poprawna paczka. Każdy test psuje w niej po jednej rzeczy.
    Map<String, Object?> paczka([List<Object?>? ops]) => {
          'from': nadawca.toJson(),
          'input': sesja,
          'token': token,
          'seq': 1,
          'ops': ops ?? [wpisz('cześć')],
        };

    RemoteInputPacket? czytaj(Map<String, Object?> json) =>
        RemoteInputPacket.fromJson(json);

    test('tekst do wpisania: limit, połówki surogatów, znaki sterujące i tab',
        () {
      final zle = <String, Object?>{
        'o jednostkę za długi': 'a' * (maxInputTextUnits + 1),
        'samotna wysoka połówka na końcu': 'abc\uD83D',
        'wysoka połówka przed zwykłym znakiem': '\uD83Dx',
        'samotna niska połówka': '\uDE00b',
        'dzwonek': 'a\u0007b',
        'escape terminala': '\u001B[2J',
        'NUL': 'a\u0000b',
        'DEL': 'a\u007Fb',
        'znak sterujący C1': 'a\u0085b',
        'tab': 'a\tb',
        'powrót karetki': 'a\rb',
        'pusty': '',
        'liczba': 42,
        'brak': null,
      };
      zle.forEach((opis, s) {
        expect(czytaj(paczka([wpisz(s)])), isNull, reason: opis);
      });

      // Granica liczy się włącznie, a para surogatów to jeden znak.
      expect(czytaj(paczka([wpisz('a' * maxInputTextUnits)])), isNotNull);
      expect(czytaj(paczka([wpisz('ok 👍')])), isNotNull);
    });

    test('nieznana operacja i zła liczba kasowanych znaków odrzucają całość',
        () {
      final zle = <Object?>[
        {'t': 'key', 'k': 'enter'},
        {
          't': 'key',
          'c': 'a',
          'm': ['ctrl']
        },
        {'t': 'Insert', 's': 'a'},
        {'t': 'tab'},
        {'s': 'a'},
        'insert',
        null,
        {'t': 'bs', 'n': 0},
        {'t': 'bs', 'n': maxInputDeleteRun + 1},
        {'t': 'del', 'n': 0},
        {'t': 'del', 'n': maxInputDeleteRun + 1},
        {'t': 'bs', 'n': -1},
        {'t': 'bs', 'n': 1.0},
        {'t': 'bs', 'n': '1'},
        {'t': 'del'},
      ];
      for (final op in zle) {
        // Zła operacja między dobrymi: połowa paczki wpisana to gorzej niż
        // żadna, więc odpada cała.
        expect(czytaj(paczka([wpisz('a'), op, wpisz('b')])), isNull,
            reason: '$op');
      }
      for (final n in [1, maxInputDeleteRun]) {
        expect(
            czytaj(paczka([
              {'t': 'bs', 'n': n},
              {'t': 'del', 'n': n},
            ])),
            isNotNull,
            reason: 'n = $n');
      }
    });

    test('paczka ma granice: liczba operacji, suma tekstu, suma kasowania', () {
      const akcja = {'t': 'action'};
      expect(czytaj(paczka(List.filled(maxInputOps + 1, akcja))), isNull,
          reason: 'o jedną operację za dużo');
      expect(czytaj(paczka(List.filled(maxInputOps, akcja))), isNotNull);
      expect(czytaj(paczka(const [])), isNull, reason: 'pusta paczka');

      // Każdy kawałek mieści się w limicie, razem już nie.
      const polowa = maxInputTextUnits ~/ 2;
      expect(
          czytaj(paczka([
            wpisz('a' * polowa),
            {'t': 'bs', 'n': 1},
            wpisz('b' * (polowa + 1)),
          ])),
          isNull,
          reason: 'suma tekstu w kilku wpisach');
      expect(czytaj(paczka([wpisz('a' * polowa), wpisz('b' * polowa)])),
          isNotNull);

      const kasuj = {'t': 'bs', 'n': maxInputDeleteRun};
      const mieszczaSie = maxInputDeletes ~/ maxInputDeleteRun;
      expect(czytaj(paczka(List.filled(mieszczaSie + 1, kasuj))), isNull,
          reason: 'suma kasowania');
      expect(czytaj(paczka(List.filled(mieszczaSie, kasuj))), isNotNull);
    });

    test('stop wolno wysłać tylko na końcu paczki', () {
      const stop = {'t': 'stop'};
      const akcja = {'t': 'action'};
      expect(czytaj(paczka([stop, wpisz('a')])), isNull);
      expect(czytaj(paczka([wpisz('a'), stop, akcja])), isNull);
      expect(czytaj(paczka([stop, stop])), isNull);
      expect(czytaj(paczka([wpisz('a'), stop])), isNotNull);
      expect(czytaj(paczka([stop])), isNotNull);
    });

    test('identyfikator sesji, numer paczki, token i dopełnienie mają kształt',
        () {
      for (final input in <Object?>[
        '../x',
        '..\\x',
        'a/b',
        'x' * 65,
        '',
        7,
        null,
      ]) {
        expect(czytaj(paczka()..['input'] = input), isNull,
            reason: 'input: $input');
      }
      for (final seq in <Object?>[1.0, 1.5, '1', 0, -1, null]) {
        expect(czytaj(paczka()..['seq'] = seq), isNull, reason: 'seq: $seq');
      }
      for (final zly in <Object?>[
        'zły token',
        'abc-def',
        '../x',
        'a\nb',
        '',
        'A' * 65,
        7,
        null,
      ]) {
        expect(czytaj(paczka()..['token'] = zly), isNull,
            reason: 'token: $zly');
      }
      for (final pad in <Object?>[5, true, const <Object?>[], const {}]) {
        expect(czytaj(paczka()..['pad'] = pad), isNull, reason: 'pad: $pad');
      }
      for (final ops in <Object?>['insert', null, const {}]) {
        expect(czytaj(paczka()..['ops'] = ops), isNull, reason: 'ops: $ops');
      }
      expect(czytaj(paczka()..remove('from')), isNull, reason: 'bez nadawcy');

      // To, co leży na granicy, przechodzi.
      expect(czytaj(paczka()..['input'] = 'x' * 64), isNotNull);
      expect(czytaj(paczka()..['token'] = 'A' * 64), isNotNull);
      expect(czytaj(paczka()..['pad'] = ''), isNotNull);
      expect(czytaj(paczka()..['seq'] = 1 << 40), isNotNull);
    });

    test('poprawna paczka przechodzi w całości, z emoji i nową linią', () {
      final json = paczka([
        wpisz('Cześć 👋\nświat'),
        {'t': 'bs', 'n': 2},
        {'t': 'del', 'n': 1},
        {'t': 'action'},
        {'t': 'ping'},
        {'t': 'stop'},
      ])
        ..['pad'] = '    ';
      final wynik = czytaj(json);
      expect(wynik, isNotNull);
      expect(wynik!.from.guid, 'x');
      expect(wynik.input, sesja);
      expect(wynik.token, token);
      expect(wynik.seq, 1);
      expect(wynik.ops, const [
        RemoteInputOp.insert('Cześć 👋\nświat'),
        RemoteInputOp.backspace(2),
        RemoteInputOp.delete(1),
        RemoteInputOp.action(),
        RemoteInputOp.ping(),
        RemoteInputOp.stop(),
      ]);

      // Tak samo po drodze przez drut: dopełnienie wyrównuje długość do
      // bloku i nie psuje kształtu.
      final bajty = utf8.encode(jsonEncode(padInputPayload(wynik.toJson())));
      expect(bajty.length % inputPadBlock, 0);
      final znowu =
          czytaj(jsonDecode(utf8.decode(bajty)) as Map<String, Object?>);
      expect(znowu?.ops, wynik.ops);
    });

    test('prośba o sesję: zła operacja i zły identyfikator odpadają, '
        'nieznany system znika', () {
      Map<String, Object?> prosba() => {
            'from': nadawca.toJson(),
            'op': inputSessionRequest,
            'input': sesja,
            'platform': 'windows',
          };

      final dobra = InputSessionRequest.fromJson(prosba());
      expect(dobra?.op, inputSessionRequest);
      expect(dobra?.input, sesja);
      expect(dobra?.platform, 'windows');
      expect(
          InputSessionRequest.fromJson(prosba()..['op'] = inputSessionCancel)
              ?.op,
          inputSessionCancel);

      for (final op in <Object?>['key', 'REQUEST', 'accept', '', 1, null]) {
        expect(InputSessionRequest.fromJson(prosba()..['op'] = op), isNull,
            reason: 'op: $op');
      }
      for (final input in <Object?>['../x', 'a/b', 'x' * 65, '', 7, null]) {
        expect(
            InputSessionRequest.fromJson(prosba()..['input'] = input), isNull,
            reason: 'input: $input');
      }
      expect(InputSessionRequest.fromJson(prosba()..remove('from')), isNull);

      // System nadawcy idzie tylko na kartę: nieznany znaczy „nie podano"
      // i prośba przechodzi bez niego.
      for (final platform in <Object?>['amiga', 'Windows', 'windows\n', 5]) {
        final wynik =
            InputSessionRequest.fromJson(prosba()..['platform'] = platform);
        expect(wynik, isNotNull, reason: 'platform: $platform');
        expect(wynik!.platform, isNull, reason: 'platform: $platform');
      }
      expect(
          InputSessionRequest.fromJson(prosba()..remove('platform'))?.platform,
          isNull);
    });
  });

  group('zdalna klawiatura: serwer odrzuca złe zapytania przed ujściem', () {
    late Directory work;
    late AppServices alice;
    late AppServices bob;
    late _Ujscie ujscie;

    setUp(() async {
      work = Directory.systemTemp.createTempSync('chatt_sec_klawiatura');
      ujscie = _Ujscie();
      alice = await AppServices.start(
        executor: NativeDatabase.memory(),
        portOverride: 0,
        nameOverride: 'Alicja',
        enableDiscovery: false,
        receivedDirOverride: p.join(work.path, 'alice'),
      );
      bob = await AppServices.start(
        executor: NativeDatabase.memory(),
        portOverride: 0,
        nameOverride: 'Bartek',
        enableDiscovery: false,
        receivedDirOverride: p.join(work.path, 'bob'),
        remoteInputPolicy: acceptAllRemoteInput,
        remoteInputSink: ujscie,
      );
      // U Bartka wszystko otwarte: zatrzymać ma sam kształt zapytania.
      await bob.setKeyboardAddon(true);
      expect(await bob.setRemoteInputReceive(true), isTrue);
    });

    tearDown(() async {
      await alice.dispose();
      await bob.dispose();
      work.deleteSync(recursive: true);
    });

    Future<int> wyslij(String sciezka, List<int> cialo) async {
      final client = HttpClient();
      try {
        final request =
            await client.post('127.0.0.1', bob.server.port!, sciezka);
        request.headers.contentType = ContentType.json;
        request.add(cialo);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    Future<void> infoOdpowiada() async {
      final client = HttpClient();
      try {
        final info = await client.get('127.0.0.1', bob.server.port!, '/info');
        final response = await info.close();
        final tresc = await response.transform(utf8.decoder).join();
        expect(response.statusCode, 200);
        expect(tresc, contains('"app":"chatt"'));
      } finally {
        client.close(force: true);
      }
    }

    void nicNieDotarlo() {
      expect(bob.pendingRemoteInput.value, isEmpty);
      expect(bob.incomingRemoteInput.value, isNull);
      expect(ujscie.ops, isEmpty);
      expect(ujscie.wywolania, ['setImeEnabled:true'],
          reason: 'ujście słyszało tylko przełącznik dodatku');
    }

    test('ciało ponad granicę dostaje 413, a serwer żyje dalej', () async {
      final zaDuze = List<int>.filled(maxInputBodyBytes + 1, 0x41);

      // Ta sama obsługa, którą idą zapytania z gniazda TCP, przez łącze
      // radiowe: ciało jest w pamięci, więc odpowiedź widać zawsze.
      for (final sciezka in ['/input', '/input-session']) {
        final odpowiedz = await bob.server.handleBluetooth(
          BtRequest(
            method: 'POST',
            path: sciezka,
            headers: const {'content-type': 'application/json'},
            body: Stream.value(zaDuze),
          ),
          'AA:BB:CC:DD:EE:FF',
        );
        await odpowiedz.body.drain<void>();
        expect(odpowiedz.status, 413, reason: sciezka);
      }

      // Przez TCP: 413 albo zerwane połączenie, jak przy `/message` wyżej.
      // Serwer, który przestaje czytać ciało w połowie, zostawia `dart:io`
      // połączenie bez dokończonego zapytania i to ono je zamyka.
      for (final sciezka in ['/input', '/input-session']) {
        int? status;
        try {
          status = await wyslij(sciezka, zaDuze);
        } on SocketException {
          // zerwane w trakcie wysyłania
        } on HttpException {
          // zerwane przed odpowiedzią
        }
        if (status != null) expect(status, 413, reason: sciezka);
      }

      // Na samej granicy ciało jest przeczytane i odrzucone jako jawne.
      expect(await wyslij('/input', List<int>.filled(maxInputBodyBytes, 0x41)),
          409);

      await infoOdpowiada();
      nicNieDotarlo();
    });

    test('jawne śmieci i jawna paczka dostają 409', () async {
      final smieci = <List<int>>[
        const [],
        utf8.encode('to nie jest JSON'),
        utf8.encode('[1,2,3]'),
        utf8.encode(jsonEncode(RemoteInputPacket(
          from: alice.identity,
          input: 'sesja-1',
          token: 'dG9rZW4tdGVzdG93eQ==',
          seq: 1,
          ops: const [RemoteInputOp.insert('ls\n')],
        ).toJson())),
        utf8.encode(jsonEncode(InputSessionRequest(
          from: alice.identity,
          op: inputSessionRequest,
          input: 'sesja-1',
        ).toJson())),
        // Koperta z sesją, której serwer nie zna.
        utf8.encode(jsonEncode({
          envelopeMarker: 1,
          envelopeSession: 'nieznana',
          'nonce': 'AAAA',
          'mac': 'AAAA',
          'data': 'AAAA',
        })),
      ];
      for (var i = 0; i < smieci.length; i++) {
        expect(await wyslij('/input', smieci[i]), 409, reason: '/input #$i');
        expect(await wyslij('/input-session', smieci[i]), 409,
            reason: '/input-session #$i');
      }

      await infoOdpowiada();
      nicNieDotarlo();
    });

    test('zapieczętowana paczka złego kształtu dostaje 400', () async {
      // Wystarczy sesja z samego uścisku dłoni: kształt jest sprawdzany przed
      // jakąkolwiek zgodą, więc parowanie nie ma tu nic do rzeczy.
      final bobAtAlice =
          await alice.addPeerByAddress('127.0.0.1', bob.server.port!);
      expect(bobAtAlice, isNotNull);

      Map<String, Object?> paczka(List<Object?> ops,
              {Object? seq = 1, Object? input = 'sesja-1'}) =>
          {
            'from': alice.identity.toJson(),
            'input': input,
            'token': 'dG9rZW4tdGVzdG93eQ==',
            'seq': seq,
            'ops': ops,
          };
      final zle = <Map<String, Object?>>[
        paczka([
          {'t': 'key', 'k': 'enter'}
        ]),
        paczka([
          {'t': 'insert', 's': 'a' * (maxInputTextUnits + 1)}
        ]),
        paczka([
          {'t': 'insert', 's': 'a\tb'}
        ]),
        paczka([
          {'t': 'bs', 'n': maxInputDeleteRun + 1}
        ]),
        paczka([
          {'t': 'stop'},
          {'t': 'insert', 's': 'a'}
        ]),
        paczka([
          {'t': 'action'}
        ], seq: '1'),
        paczka([
          {'t': 'action'}
        ], input: '../x'),
      ];
      for (var i = 0; i < zle.length; i++) {
        final wynik =
            await alice.debugSendSealed(bobAtAlice!, '/input', zle[i]);
        expect(wynik.status, 400, reason: 'paczka #$i');
        expect(wynik.reply, isNull, reason: 'paczka #$i');
      }

      final zlaProsba =
          await alice.debugSendSealed(bobAtAlice!, '/input-session', {
        'from': alice.identity.toJson(),
        'op': 'key',
        'input': 'sesja-1',
      });
      expect(zlaProsba.status, 400);
      expect(zlaProsba.reply, isNull);

      await infoOdpowiada();
      nicNieDotarlo();
    });
  });
}

/// Ujście w pamięci: zapisuje, co by wpisało, i odpowiada stałym celem.
class _Ujscie implements RemoteInputSink {
  final ops = <RemoteInputOp>[];
  final wywolania = <String>[];
  final RemoteInputTarget cel = const RemoteInputTarget(
      active: true,
      field: RemoteInputField.text,
      app: 'com.example.notes',
      appLabel: 'Notatki');

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
