import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

/// Gadatliwy log ramek i powodów zerwania. Domyślnie wyłączony; włącza go
/// `--dart-define=CHATT_BT_VERBOSE=true`. Przy radiu, gdzie obie strony
/// widzą tylko ciszę tej drugiej, to jest jedyny sposób, żeby zobaczyć,
/// która z nich odłożyła słuchawkę pierwsza.
const bool btVerbose = bool.fromEnvironment('CHATT_BT_VERBOSE');

/// Dwukierunkowa rura bajtów: jedno łącze RFCOMM widziane z Darta.
///
/// Po stronie aplikacji pod spodem jest zwykłe gniazdo TCP na 127.0.0.1,
/// które kod natywny mostkuje na radio. W testach jest para kontrolerów
/// w pamięci, dzięki czemu cały protokół nad tą rurą daje się sprawdzić
/// bez radia, bez uprawnień i bez drugiego urządzenia.
abstract class BytePipe {
  Stream<List<int>> get input;

  void add(List<int> data);

  /// Czeka, aż to, co dodano, trafi do systemu. Stąd bierze się hamowanie:
  /// bez tego plik wjechałby w całości do bufora w pamięci.
  Future<void> flush();

  Future<void> close();
}

/// Żądanie, które przyszło łączem od drugiej strony.
class BtRequest {
  final String method;
  final String path;
  final Map<String, String> headers;
  final Stream<List<int>> body;

  const BtRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });
}

/// Odpowiedź na [BtRequest]. Kody są te same co w HTTP, bo warstwa wyżej
/// i tak nimi mówi.
class BtResponse {
  final int status;
  final Map<String, String> headers;
  final Stream<List<int>> body;

  const BtResponse({
    required this.status,
    this.headers = const {},
    required this.body,
  });

  static BtResponse ofBytes(int status, List<int> body,
          {Map<String, String> headers = const {}}) =>
      BtResponse(
        status: status,
        headers: headers,
        body: Stream<List<int>>.value(body),
      );
}

// Ramka: [1 bajt rodzaj][4 bajty numer strumienia][4 bajty długość][treść].
//
// Jedno łącze RFCOMM niesie wiele wymian naraz, bo w Chatcie wiadomość potrafi
// wyjść w trakcie wysyłania pliku. Numer strumienia je rozdziela, a parzystość
// pilnuje, żeby obie strony nie sięgnęły po ten sam numer: strona łącząca się
// używa nieparzystych, strona przyjmująca parzystych.
const int _kindHead = 1;
const int _kindBody = 2;
const int _kindEnd = 3;
const int _kindReply = 4;
const int _kindAbort = 5;

const int _headerBytes = 9;

/// Największa treść w jednej ramce. Pomiar z docs/spike-rfcomm.md nie pokazał
/// progu, powyżej którego większe porcje coś dają, a mniejsze trzymają
/// w ryzach pamięć i opóźnienie wiadomości wciśniętej między porcje pliku.
const int btFrameBytes = 8192;

/// Górna granica jednej ramki przy odbiorze. Chroni przed łączem, które
/// podaje długość z sufitu.
const int _maxFrameBytes = 1024 * 1024;

class _Exchange {
  final Completer<BtResponse> reply = Completer<BtResponse>();
  final StreamController<List<int>> body = StreamController<List<int>>();
  bool headSeen = false;
}

/// Protokół żądanie-odpowiedź po jednym łączu RFCOMM.
///
/// Symetryczny: każda ze stron może zacząć wymianę, bo w Chatcie każde
/// urządzenie jest równorzędne. [onRequest] dostaje to, co przyszło z drugiej
/// strony, i oddaje odpowiedź.
class BtLink {
  final BytePipe _pipe;
  final Future<BtResponse> Function(BtRequest request)? onRequest;

  /// Strona, która nawiązała łącze, numeruje nieparzyście.
  final bool initiator;

  final _outgoing = <int, _Exchange>{};
  final _incoming = <int, StreamController<List<int>>>{};

  /// Bajty, które przyszły, ale nie złożyły się jeszcze w całą ramkę.
  Uint8List _pending = Uint8List(0);

  /// Zapis idzie kolejką, bo ramki z różnych strumieni nie mogą się przepleść
  /// w połowie.
  Future<void> _writes = Future<void>.value();

  StreamSubscription<List<int>>? _reader;
  int _nextId;
  bool _closed = false;

  BtLink(this._pipe, {this.onRequest, required this.initiator})
      : _nextId = initiator ? 1 : 2 {
    _reader = _pipe.input.listen(
      _onBytes,
      onError: (Object error) => close(powod: 'pipe error: $error'),
      onDone: () => close(powod: 'pipe ended'),
      cancelOnError: true,
    );
  }

  String get _kto => initiator ? 'laczacy' : 'przyjmujacy';

  bool get isClosed => _closed;

  /// Dlaczego łącze zamknęło się po tej stronie, `null`, dopóki stoi.
  /// Transport dokłada to do powodu ze strony natywnej, kiedy zgłasza
  /// zerwane łącze do dziennika aplikacji: strona natywna widzi wtedy tylko
  /// tyle, że gniazdo z pętli zwrotnej się zamknęło.
  String? get closeReason => _closeReason;
  String? _closeReason;

  /// Wysyła żądanie i czeka na odpowiedź. Rzuca [StateError], gdy łącze padło.
  Future<BtResponse> send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Stream<List<int>>? body,
  }) async {
    if (_closed) throw StateError('Łącze Bluetooth jest zamknięte');
    final id = _nextId;
    _nextId += 2;

    final exchange = _Exchange();
    _outgoing[id] = exchange;

    await _write(
      _kindHead,
      id,
      utf8.encode(jsonEncode({'m': method, 'p': path, 'h': headers})),
    );
    if (body != null) {
      await for (final chunk in body) {
        if (_closed) break;
        for (var at = 0; at < chunk.length; at += btFrameBytes) {
          final end = (at + btFrameBytes < chunk.length)
              ? at + btFrameBytes
              : chunk.length;
          await _write(_kindBody, id, chunk.sublist(at, end));
        }
      }
    }
    await _write(_kindEnd, id, const []);
    return exchange.reply.future;
  }

  Future<void> close({String powod = 'closed from outside'}) async {
    if (_closed) return;
    _closed = true;
    _closeReason = powod;
    if (btVerbose) debugPrint('[link $_kto] zamykam: $powod');
    // Czytnik idzie pierwszy: ramka wpuszczona już po zamknięciu trafiłaby
    // na wymianę, którą właśnie domykamy błędem, i domknęła ją drugi raz.
    await _reader?.cancel();
    _reader = null;
    for (final exchange in _outgoing.values) {
      if (!exchange.reply.isCompleted) {
        exchange.reply.completeError(StateError('Łącze Bluetooth zerwane'));
      }
      _zerwij(exchange.body);
    }
    _outgoing.clear();
    for (final controller in _incoming.values) {
      _zerwij(controller);
    }
    _incoming.clear();
    unawaited(_pipe.close());
  }

  /// Urwana treść musi być błędem: plik przerwany
  /// w połowie wyglądałby inaczej jak kompletny. Błąd ma jednak gdzie trafić
  /// tylko wtedy, gdy ktoś już słucha; bez tego leciałby bokiem jako
  /// nieobsłużony. Zamknięcia nie czekamy, bo kontroler bez słuchacza
  /// domyka się dopiero wtedy, gdy ten się pojawi.
  void _zerwij(StreamController<List<int>> controller) {
    if (controller.isClosed) return;
    if (controller.hasListener) {
      controller.addError(StateError('Łącze Bluetooth zerwane'));
    }
    unawaited(controller.close());
  }

  // --- zapis ---------------------------------------------------------------

  Future<void> _write(int kind, int id, List<int> payload) {
    final done = _writes.then((_) async {
      if (_closed) return;
      final frame = Uint8List(_headerBytes + payload.length);
      frame[0] = kind;
      final view = ByteData.view(frame.buffer);
      view.setUint32(1, id);
      view.setUint32(5, payload.length);
      frame.setRange(_headerBytes, frame.length, payload);
      if (btVerbose) {
        debugPrint('[link $_kto] -> rodzaj $kind strumien $id '
            '${payload.length} B');
      }
      _pipe.add(frame);
      // Hamowanie: czekanie na opróżnienie bufora trzyma duży plik w tempie
      // radia. Bez niego plik wjechałby w całości do pamięci.
      await _pipe.flush();
    }).catchError((Object error) async {
      await close(powod: 'write failed: $error');
    });
    _writes = done;
    return done;
  }

  // --- odczyt --------------------------------------------------------------

  void _onBytes(List<int> data) {
    if (data.isEmpty) return;
    if (_pending.isEmpty) {
      _pending = Uint8List.fromList(data);
    } else {
      final joined = Uint8List(_pending.length + data.length);
      joined.setRange(0, _pending.length, _pending);
      joined.setRange(_pending.length, joined.length, data);
      _pending = joined;
    }

    var at = 0;
    while (_pending.length - at >= _headerBytes) {
      final view = ByteData.view(_pending.buffer, _pending.offsetInBytes + at);
      final kind = _pending[at];
      final id = view.getUint32(1);
      final length = view.getUint32(5);
      if (length > _maxFrameBytes) {
        unawaited(close(
            powod: 'frame of kind $kind has $length B, over the limit'));
        return;
      }
      if (_pending.length - at - _headerBytes < length) break;
      final start = at + _headerBytes;
      final payload = Uint8List.sublistView(_pending, start, start + length);
      at = start + length;
      _onFrame(kind, id, payload);
      if (_closed) return;
    }
    _pending = at == 0
        ? _pending
        : Uint8List.fromList(_pending.sublist(at));
  }

  void _onFrame(int kind, int id, Uint8List payload) {
    if (btVerbose) {
      debugPrint('[link $_kto] <- rodzaj $kind strumien $id '
          '${payload.length} B');
    }
    switch (kind) {
      case _kindHead:
        _onHead(id, payload);
      case _kindReply:
        _onReply(id, payload);
      case _kindBody:
        _onBody(id, payload);
      case _kindEnd:
        _onEnd(id);
      case _kindAbort:
        _onAbort(id);
    }
  }

  void _onHead(int id, Uint8List payload) {
    final handler = onRequest;
    final json = _tryJson(payload);
    if (handler == null || json == null) {
      unawaited(_write(_kindAbort, id, utf8.encode('no_handler')));
      return;
    }
    final controller = StreamController<List<int>>();
    _incoming[id] = controller;

    final headers = <String, String>{};
    final raw = json['h'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.key is String && entry.value is String) {
          headers[entry.key as String] = entry.value as String;
        }
      }
    }
    final request = BtRequest(
      method: json['m'] is String ? json['m'] as String : 'POST',
      path: json['p'] is String ? json['p'] as String : '/',
      headers: headers,
      body: controller.stream,
    );

    unawaited(() async {
      BtResponse response;
      try {
        response = await handler(request);
      } catch (_) {
        response = BtResponse.ofBytes(500, utf8.encode('{"ok":false}'));
      }
      if (_closed) return;
      await _write(
        _kindReply,
        id,
        utf8.encode(jsonEncode({'s': response.status, 'h': response.headers})),
      );
      try {
        await for (final chunk in response.body) {
          if (_closed) return;
          for (var start = 0; start < chunk.length; start += btFrameBytes) {
            final end = (start + btFrameBytes < chunk.length)
                ? start + btFrameBytes
                : chunk.length;
            await _write(_kindBody, id, chunk.sublist(start, end));
          }
        }
      } catch (_) {
        // Zerwane ciało odpowiedzi: druga strona zobaczy pustą treść.
      }
      await _write(_kindEnd, id, const []);
    }());
  }

  void _onReply(int id, Uint8List payload) {
    final exchange = _outgoing[id];
    if (exchange == null || exchange.headSeen || exchange.reply.isCompleted) {
      return;
    }
    exchange.headSeen = true;
    final json = _tryJson(payload);
    final headers = <String, String>{};
    final raw = json?['h'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.key is String && entry.value is String) {
          headers[entry.key as String] = entry.value as String;
        }
      }
    }
    exchange.reply.complete(BtResponse(
      status: json?['s'] is int ? json!['s'] as int : 500,
      headers: headers,
      body: exchange.body.stream,
    ));
  }

  void _onBody(int id, Uint8List payload) {
    final copy = Uint8List.fromList(payload);
    final exchange = _outgoing[id];
    if (exchange != null) {
      if (!exchange.body.isClosed) exchange.body.add(copy);
      return;
    }
    final controller = _incoming[id];
    if (controller != null && !controller.isClosed) controller.add(copy);
  }

  void _onEnd(int id) {
    final exchange = _outgoing[id];
    if (exchange != null) {
      // Koniec odpowiedzi: wymiana się domknęła.
      if (!exchange.headSeen && !exchange.reply.isCompleted) {
        exchange.reply.complete(
            BtResponse(status: 500, body: const Stream<List<int>>.empty()));
      }
      unawaited(exchange.body.close());
      _outgoing.remove(id);
      return;
    }
    final controller = _incoming.remove(id);
    if (controller != null) unawaited(controller.close());
  }

  void _onAbort(int id) {
    final exchange = _outgoing.remove(id);
    if (exchange != null) {
      if (!exchange.reply.isCompleted) {
        exchange.reply.complete(
            BtResponse(status: 502, body: const Stream<List<int>>.empty()));
      }
      unawaited(exchange.body.close());
    }
    final controller = _incoming.remove(id);
    if (controller != null) unawaited(controller.close());
  }

  static Map<String, Object?>? _tryJson(List<int> bytes) {
    try {
      final value = jsonDecode(utf8.decode(bytes));
      return value is Map<String, Object?> ? value : null;
    } catch (_) {
      return null;
    }
  }
}
