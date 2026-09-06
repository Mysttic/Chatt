import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/updates.dart';

/// Sprawdzanie aktualizacji jest jedyną rzeczą, którą aplikacja robi poza
/// siecią lokalną, więc ma się zachowywać przewidywalnie: mówić o nowszym
/// wydaniu, milczeć o starszym i o każdym błędzie, i nigdy nie rzucać.
String _wydanie({
  String tag = 'v0.9.0',
  bool draft = false,
  bool prerelease = false,
  List<String> pliki = const [
    'chatt-0.9.0-windows-instalator.exe',
    'chatt-0.9.0-android.apk',
    'chatt-0.9.0-windows.zip',
  ],
}) =>
    jsonEncode({
      'tag_name': tag,
      'name': 'Chatt ${tag.substring(1)}',
      'body': 'Opis wydania.',
      'draft': draft,
      'prerelease': prerelease,
      'published_at': '2026-09-06T09:00:39Z',
      'html_url': 'https://github.com/Mysttic/Chatt/releases/tag/$tag',
      'assets': [
        for (final p in pliki)
          {
            'name': p,
            'size': 1234,
            'browser_download_url':
                'https://github.com/Mysttic/Chatt/releases/download/$tag/$p',
          },
      ],
    });

http.Client _odpowiada(String tresc, {int kod = 200}) =>
    MockClient((_) async => http.Response(tresc, kod,
        headers: {'content-type': 'application/json'}));

void main() {
  group('porównywanie wersji', () {
    test('człon po członie, nie tekstowo', () {
      expect(compareVersions('0.5.4', '0.5.10'), lessThan(0));
      expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
      expect(compareVersions('1.0.0', '0.99.99'), greaterThan(0));
      expect(compareVersions('0.5.4', '0.5.4'), 0);
    });

    test('„v" z przodu i ogon po myślniku nie mają znaczenia', () {
      expect(compareVersions('v0.5.4', '0.5.4'), 0);
      expect(compareVersions('0.5.4', '0.5.4+10'), 0);
      expect(compareVersions('0.5.4', '0.5.5-rc1'), lessThan(0));
    });

    test('brakujące człony liczą się jak zero', () {
      expect(compareVersions('1', '1.0.0'), 0);
      expect(compareVersions('1.2', '1.2.1'), lessThan(0));
    });
  });

  group('nazwa pliku wydania', () {
    test('zgadza się z tym, co nazywa workflow wydania', () {
      expect(assetNameFor('0.5.4', platforma: 'windows'),
          'chatt-0.5.4-windows-instalator.exe');
      expect(assetNameFor('0.5.4', platforma: 'android'),
          'chatt-0.5.4-android.apk');
      expect(assetNameFor('0.5.4', platforma: 'linux'), isNull);
    });
  });

  group('pytanie o wydanie', () {
    test('nowsze wydanie wraca razem z plikiem dla tej platformy', () async {
      final w = await fetchLatestRelease(
        biezaca: '0.5.4',
        client: _odpowiada(_wydanie()),
        platforma: 'windows',
      );
      expect(w.outcome, UpdateCheck.newer);
      final r = w.release!;
      expect(r.version, '0.9.0');
      expect(r.notes, 'Opis wydania.');
      expect(r.assetName, 'chatt-0.9.0-windows-instalator.exe');
      expect(r.assetUrl, contains('/download/v0.9.0/'));
      expect(r.assetSize, 1234);
      expect(r.publishedAt, isNotNull);
    });

    test('na Androidzie wybiera APK', () async {
      final w = await fetchLatestRelease(
        biezaca: '0.5.4',
        client: _odpowiada(_wydanie()),
        platforma: 'android',
      );
      expect(w.release!.assetName, 'chatt-0.9.0-android.apk');
    });

    test('to samo albo starsze wydanie znaczy nic', () async {
      for (final biezaca in ['0.9.0', '1.0.0']) {
        final w = await fetchLatestRelease(
          biezaca: biezaca,
          client: _odpowiada(_wydanie()),
          platforma: 'windows',
        );
        expect(w.outcome, UpdateCheck.upToDate);
        expect(w.release, isNull);
      }
    });

    test('szkic i wydanie kandydujące są pomijane', () async {
      for (final tresc in [_wydanie(draft: true), _wydanie(prerelease: true)]) {
        final w = await fetchLatestRelease(
          biezaca: '0.5.4',
          client: _odpowiada(tresc),
          platforma: 'windows',
        );
        expect(w.outcome, UpdateCheck.upToDate);
      }
    });

    test('wydanie bez pliku dla tej platformy nadal daje numer i stronę',
        () async {
      final w = await fetchLatestRelease(
        biezaca: '0.5.4',
        client: _odpowiada(_wydanie(pliki: const ['chatt-0.9.0-windows.zip'])),
        platforma: 'windows',
      );
      expect(w.outcome, UpdateCheck.newer);
      expect(w.release!.assetUrl, isNull);
      expect(w.release!.pageUrl, contains('releases/tag/v0.9.0'));
    });

    test('kod inny niż 200, śmieci i wyjątek to „nie udało się zapytać"',
        () async {
      final klienci = [
        _odpowiada('{}', kod: 404),
        _odpowiada('to nie jest json'),
        MockClient((_) async => throw const SocketExceptionStub()),
      ];
      for (final klient in klienci) {
        final w = await fetchLatestRelease(
          biezaca: '0.5.4',
          client: klient,
          platforma: 'windows',
        );
        expect(w.outcome, UpdateCheck.failed);
        expect(w.release, isNull);
      }
    });
  });
}

/// Byle wyjątek z warstwy sieciowej. Chodzi o to, że [fetchLatestRelease] łyka
/// każdy, a nie o jego rodzaj.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
