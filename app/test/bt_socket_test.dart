import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chatt/network/bt_link.dart';
import 'package:chatt/network/bt_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ramkowanie nad prawdziwym gniazdem z pętli zwrotnej.
///
/// Kod natywny mostkuje łącze RFCOMM na gniazdo TCP pod 127.0.0.1, więc to
/// jest dokładnie ta rura, którą w aplikacji płyną bajty. Różnice między nią
/// a atrapą (podział na pakiety, hamowanie, zamykanie połowiczne) są tym,
/// czego `bt_link_test.dart` z założenia nie zobaczy.
Future<({BtLink klient, BtLink serwer, ServerSocket nasluch})> _para({
  Future<BtResponse> Function(BtRequest request)? obsluga,
}) async {
  final nasluch = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final przyjete = nasluch.first;
  final wychodzace =
      await Socket.connect(InternetAddress.loopbackIPv4, nasluch.port);
  final przychodzace = await przyjete;

  wychodzace.setOption(SocketOption.tcpNoDelay, true);
  przychodzace.setOption(SocketOption.tcpNoDelay, true);

  return (
    klient: BtLink(SocketPipe(wychodzace), initiator: true),
    serwer: BtLink(
      SocketPipe(przychodzace),
      initiator: false,
      onRequest: obsluga,
    ),
    nasluch: nasluch,
  );
}

Future<List<int>> _zbierz(Stream<List<int>> body) async {
  final out = <int>[];
  await for (final chunk in body) {
    out.addAll(chunk);
  }
  return out;
}

void main() {
  test('kolejne wymiany po tym samym gnieździe nie zrywają łącza', () async {
    final para = await _para(
      obsluga: (request) async {
        await _zbierz(request.body);
        return BtResponse.ofBytes(200, utf8.encode('jest ${request.path}'));
      },
    );
    addTearDown(() async {
      await para.klient.close();
      await para.serwer.close();
      await para.nasluch.close();
    });

    // Trzy wymiany pod rząd: pierwsza działała od początku, dopiero druga
    // pokazywała, że łącze nie przeżywa własnej odpowiedzi.
    for (final sciezka in ['/info', '/handshake', '/message']) {
      final odpowiedz = await para.klient.send('POST', sciezka);
      expect(odpowiedz.status, 200, reason: 'wymiana $sciezka');
      expect(utf8.decode(await _zbierz(odpowiedz.body)), 'jest $sciezka');
      expect(para.klient.isClosed, isFalse,
          reason: 'łącze ma przeżyć wymianę $sciezka');
      expect(para.serwer.isClosed, isFalse,
          reason: 'druga strona też');
    }
  });

  test('kilkusetkilobajtowy plik przechodzi bajt w bajt', () async {
    final plik = List<int>.generate(300000, (i) => (i * 31 + 7) & 0xFF);
    final para = await _para(
      obsluga: (request) async {
        final body = await _zbierz(request.body);
        return BtResponse.ofBytes(200, utf8.encode('${body.length}'));
      },
    );
    addTearDown(() async {
      await para.klient.close();
      await para.serwer.close();
      await para.nasluch.close();
    });

    final odpowiedz = await para.klient.send(
      'POST',
      '/file',
      body: Stream<List<int>>.value(plik),
    );
    expect(odpowiedz.status, 200);
    expect(utf8.decode(await _zbierz(odpowiedz.body)), '300000');
    expect(para.klient.isClosed, isFalse);
  });

  test('obie strony mogą zacząć wymianę po tym samym łączu', () async {
    final doKlienta = Completer<BtRequest>();
    final nasluch = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final przyjete = nasluch.first;
    final wychodzace =
        await Socket.connect(InternetAddress.loopbackIPv4, nasluch.port);
    final przychodzace = await przyjete;

    final klient = BtLink(
      SocketPipe(wychodzace),
      initiator: true,
      onRequest: (request) async {
        doKlienta.complete(request);
        return BtResponse.ofBytes(200, utf8.encode('klient odebral'));
      },
    );
    final serwer = BtLink(
      SocketPipe(przychodzace),
      initiator: false,
      onRequest: (request) async {
        await _zbierz(request.body);
        return BtResponse.ofBytes(200, utf8.encode('serwer odebral'));
      },
    );
    addTearDown(() async {
      await klient.close();
      await serwer.close();
      await nasluch.close();
    });

    // W Chatcie każde urządzenie jest równorzędne: rozmówca odpisuje tym
    // samym łączem, którym przyszła wiadomość.
    final wTe = await klient.send('POST', '/message');
    expect(utf8.decode(await _zbierz(wTe.body)), 'serwer odebral');

    final zPowrotem = await serwer.send('POST', '/message');
    expect(utf8.decode(await _zbierz(zPowrotem.body)), 'klient odebral');
    expect((await doKlienta.future).path, '/message');
  });
}
