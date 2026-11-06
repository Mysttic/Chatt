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
