import 'dart:convert';
import 'dart:io';

import 'package:chatt/core/identity.dart';
import 'package:chatt/core/received_paths.dart';
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
}
