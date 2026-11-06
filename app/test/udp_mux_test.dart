import 'dart:async';
import 'dart:io';

import 'package:chatt/network/udp_mux.dart';
import 'package:flutter_test/flutter_test.dart';

/// Czeka na pierwszy pakiet, który dotrze do [mux].
Future<void> pierwszyPakiet(UdpMux mux) {
  final odebrany = Completer<void>();
  mux.register((_) {
    if (!odebrany.isCompleted) odebrany.complete();
    return true;
  });
  return odebrany.future.timeout(const Duration(seconds: 2));
}

void main() {
  test('pakiety, których system nie przyjął, czekają i wychodzą po kolei',
      () async {
    // Na Windowsie `send` przy serii pakietów zwraca zero i pakiet nie
    // wychodzi; bez kolejki ginęły tak cztery pakiety na pięć.
    final gniazdo = _PelnyBufor();
    final mux = SocketUdpMux(gniazdo);
    addTearDown(mux.close);
    final cel = InternetAddress('203.0.113.9');
    gniazdo.miejsce = 1;
    for (var i = 0; i < 5; i++) {
      mux.send([i], cel, 6881);
    }
    expect(gniazdo.wyslane, [
      [0]
    ]);
    expect(gniazdo.writeEventsEnabled, isTrue,
        reason: 'gniazdo ma zgłosić gotowość do zapisu');

    gniazdo.gotowe(2);
    await Future<void>.delayed(Duration.zero);
    expect(gniazdo.wyslane, [
      [0],
      [1],
      [2]
    ]);

    // Nowy pakiet staje w kolejce za czekającymi.
    mux.send([5], cel, 6881);
    gniazdo.gotowe(10);
    await Future<void>.delayed(Duration.zero);
    expect(gniazdo.wyslane, [
      [0],
      [1],
      [2],
      [3],
      [4],
      [5]
    ]);
    expect(mux.dropped, 0);
  });

  test('kolejka ma granicę: nadmiar ponad nią ginie', () async {
    final gniazdo = _PelnyBufor();
    final mux = SocketUdpMux(gniazdo);
    addTearDown(mux.close);
    for (var i = 0; i < kUdpSendBacklog + 10; i++) {
      mux.send([i & 0xFF], InternetAddress('203.0.113.9'), 6881);
    }
    expect(mux.dropped, 10);
    gniazdo.gotowe(kUdpSendBacklog + 10);
    await Future<void>.delayed(Duration.zero);
    expect(gniazdo.wyslane, hasLength(kUdpSendBacklog));
  });

  test('adresy, pod które gniazdo nie wysyła', () {
    expect(udpSendable(InternetAddress('0.0.0.0'), 6881), isFalse);
    expect(udpSendable(InternetAddress('0.1.2.3'), 6881), isFalse);
    expect(udpSendable(InternetAddress('203.0.113.9'), 0), isFalse);
    expect(udpSendable(InternetAddress('224.0.0.1'), 6881), isFalse);
    expect(udpSendable(InternetAddress('255.255.255.255'), 6881), isFalse);
    expect(udpSendable(InternetAddress('::1'), 6881), isFalse);
    expect(udpSendable(InternetAddress('203.0.113.9'), 6881), isTrue);
    expect(udpSendable(InternetAddress.loopbackIPv4, 6881), isTrue);
  });

  test('pakiet pod 0.0.0.0 odpada, a gniazdo dalej działa', () async {
    final mux = await SocketUdpMux.bind();
    addTearDown(mux.close);
    final odebrany = pierwszyPakiet(mux);
    // Na Windowsie taki pakiet kończył się błędem 1214 w strumieniu gniazda
    // i zamknięciem gniazda: kolejne pakiety już nie wychodziły.
    mux.send([1], InternetAddress('0.0.0.0'), 6881);
    mux.send([2], InternetAddress('203.0.113.9'), 0);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    mux.send([3], InternetAddress.loopbackIPv4, mux.port);
    await odebrany;
  });

  test('gniazdo zamknięte bez udziału warstwy wstaje na tym samym porcie',
      () async {
    final surowe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final mux = SocketUdpMux(surowe);
    addTearDown(mux.close);
    final port = mux.port;
    surowe.close();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(mux.port, port);
    final odebrany = pierwszyPakiet(mux);
    mux.send([4], InternetAddress.loopbackIPv4, port);
    await odebrany;
  });
}

/// Gniazdo na niby z pełnym buforem wysyłki: `send` przyjmuje pakiet tylko,
/// gdy jest [miejsce], a gotowość do zapisu zgłasza test przez [gotowe].
class _PelnyBufor extends Stream<RawSocketEvent> implements RawDatagramSocket {
  final _zdarzenia = StreamController<RawSocketEvent>();

  /// Ile pakietów przyjmie jeszcze `send`.
  int miejsce = 0;

  final wyslane = <List<int>>[];

  @override
  bool readEventsEnabled = true;

  @override
  bool writeEventsEnabled = false;

  @override
  final InternetAddress address = InternetAddress.anyIPv4;

  @override
  final int port = 40000;

  @override
  int send(List<int> buffer, InternetAddress address, int port) {
    if (miejsce == 0) return 0;
    miejsce--;
    wyslane.add(buffer);
    return buffer.length;
  }

  /// System zwolnił miejsce na [ile] pakietów; jak prawdziwe gniazdo,
  /// zgłasza to tylko, gdy ktoś czeka na zapis.
  void gotowe(int ile) {
    miejsce = ile;
    if (writeEventsEnabled) {
      writeEventsEnabled = false;
      _zdarzenia.add(RawSocketEvent.write);
    }
  }

  @override
  Datagram? receive() => null;

  @override
  void close() => unawaited(_zdarzenia.close());

  @override
  StreamSubscription<RawSocketEvent> listen(
          void Function(RawSocketEvent event)? onData,
          {Function? onError,
          void Function()? onDone,
          bool? cancelOnError}) =>
      _zdarzenia.stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
