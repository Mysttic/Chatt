import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chatt/network/bt_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Para rur w pamięci w roli łącza RFCOMM. Cały protokół nad radiem daje się
/// dzięki temu sprawdzić bez radia, bez uprawnień i bez drugiego urządzenia,
/// co było jednym z powodów, dla których transport w ogóle ma swoją warstwę.
class _MemoryPipe implements BytePipe {
  final _incoming = StreamController<List<int>>();
  late _MemoryPipe other;

  /// Ile bajtów wolno oddać naraz. Jedynka rozbija każdą ramkę na pojedyncze
  /// bajty, czyli robi dokładnie to, co robi prawdziwe gniazdo: dzieli tam,
  /// gdzie nadawcy nawet nie przyszło do głowy.
  final int chunk;

  _MemoryPipe({this.chunk = 0});

  @override
  Stream<List<int>> get input => _incoming.stream;

  @override
  void add(List<int> data) {
    if (other._incoming.isClosed) return;
    if (chunk <= 0) {
      other._incoming.add(Uint8List.fromList(data));
      return;
    }
    for (var at = 0; at < data.length; at += chunk) {
      final end = (at + chunk < data.length) ? at + chunk : data.length;
      if (other._incoming.isClosed) return;
      other._incoming.add(Uint8List.fromList(data.sublist(at, end)));
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
  }
}

({_MemoryPipe a, _MemoryPipe b}) _para({int chunk = 0}) {
  final a = _MemoryPipe(chunk: chunk);
  final b = _MemoryPipe(chunk: chunk);
  a.other = b;
  b.other = a;
  return (a: a, b: b);
}

Future<List<int>> _zbierz(Stream<List<int>> body) async {
  final out = <int>[];
  await for (final chunk in body) {
    out.addAll(chunk);
  }
  return out;
}

void main() {
  test('żądanie i odpowiedź robią pełny obrót', () async {
    final rury = _para();
    final requests = <BtRequest>[];

    BtLink(
      rury.b,
      initiator: false,
      onRequest: (request) async {
        requests.add(request);
        final body = await _zbierz(request.body);
        return BtResponse.ofBytes(
          200,
          utf8.encode('odebrano ${body.length}'),
          headers: {'x-echo': request.headers['x-test'] ?? ''},
        );
      },
    );
    final klient = BtLink(rury.a, initiator: true);

    final odpowiedz = await klient.send(
      'POST',
      '/message',
      headers: {'x-test': 'raz'},
      body: Stream<List<int>>.value(utf8.encode('dzień dobry')),
    );

    expect(odpowiedz.status, 200);
    expect(odpowiedz.headers['x-echo'], 'raz');
    expect(utf8.decode(await _zbierz(odpowiedz.body)), 'odebrano 12');
    expect(requests.single.path, '/message');
    expect(requests.single.method, 'POST');

    await klient.close();
  });

  test('dwie wymiany naraz nie mieszają się ze sobą', () async {
    final rury = _para();
    final wpuszczone = <String, Completer<void>>{
      '/wolne': Completer<void>(),
      '/szybkie': Completer<void>(),
    };

    BtLink(
      rury.b,
      initiator: false,
      onRequest: (request) async {
        await _zbierz(request.body);
        // Wolne żądanie czeka, aż szybkie się skończy: bez zwielokrotniania
        // drugie stałoby w kolejce i test by nie wrócił.
        if (request.path == '/wolne') {
          await wpuszczone['/szybkie']!.future;
        }
        wpuszczone[request.path]?.complete();
        return BtResponse.ofBytes(200, utf8.encode(request.path));
      },
    );
    final klient = BtLink(rury.a, initiator: true);

    final wolne = klient.send('POST', '/wolne');
    final szybkie = klient.send('POST', '/szybkie');

    expect(utf8.decode(await _zbierz((await szybkie).body)), '/szybkie');
    expect(utf8.decode(await _zbierz((await wolne).body)), '/wolne');

    await klient.close();
  });

  test('duża treść przechodzi bajt w bajt, cięta gdziekolwiek', () async {
    // Rura oddaje po 7 bajtów, więc granice ramek nie mają szans trafić
    // w granice pakietów.
    final rury = _para(chunk: 7);
    final plik = List<int>.generate(70000, (i) => (i * 31 + 7) & 0xFF);

    BtLink(
      rury.b,
      initiator: false,
      onRequest: (request) async {
        final body = await _zbierz(request.body);
        return BtResponse.ofBytes(200, body);
      },
    );
    final klient = BtLink(rury.a, initiator: true);

    final odpowiedz = await klient.send(
      'POST',
      '/file',
      body: Stream<List<int>>.value(plik),
    );
    expect(await _zbierz(odpowiedz.body), plik);

    await klient.close();
  });

  test('zerwane łącze kończy wiszące żądanie błędem', () async {
    final rury = _para();
    final doszlo = Completer<void>();
    final nigdy = Completer<BtResponse>();
    BtLink(
      rury.b,
      initiator: false,
      onRequest: (request) async {
        await _zbierz(request.body);
        doszlo.complete();
        // Odpowiedź nigdy nie przyjdzie: łącze pada w międzyczasie.
        return nigdy.future;
      },
    );
    final klient = BtLink(rury.a, initiator: true);

    // Oczekiwanie wpina się przed zerwaniem: inaczej błąd domknięcia nie ma
    // jeszcze odbiorcy i leci bokiem jako nieobsłużony.
    final sprawdzenie =
        expectLater(klient.send('POST', '/message'), throwsA(isA<StateError>()));
    await doszlo.future;
    await klient.close();
    await sprawdzenie;
  });

  test('żądanie bez obsługi wraca od razu jako błąd', () async {
    final rury = _para();
    // Druga strona nie przyjmuje żądań: tak wygląda łącze do urządzenia,
    // które akurat wyłączyło transport.
    BtLink(rury.b, initiator: false);
    final klient = BtLink(rury.a, initiator: true);

    final odpowiedz = await klient.send('POST', '/message');
    expect(odpowiedz.status, 502);

    await klient.close();
  });
}
