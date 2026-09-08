import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chatt/core/link_preview.dart';

/// Podgląd strony to jedyny moment, w którym adres z cudzej wiadomości
/// zamienia się w połączenie. Testy pilnują dwóch rzeczy naraz: że karta
/// powstaje z tego, co strona o sobie mówi, i że aplikacja nie daje się
/// wysłać tam, gdzie nie powinna (sieć lokalna, przekierowania, olbrzymie
/// odpowiedzi, obrazki, które nie są obrazkami).

/// Nazwa zawsze wskazująca na adres publiczny.
Future<List<InternetAddress>> _publiczny(String host) async =>
    [InternetAddress('93.184.216.34')];

/// Nazwa wskazująca na sieć lokalną, czyli typowe „rebinding".
Future<List<InternetAddress>> _lokalny(String host) async =>
    [InternetAddress('192.168.0.10')];

http.Client _strona(String html, {String typ = 'text/html; charset=utf-8'}) =>
    MockClient((_) async =>
        http.Response(html, 200, headers: {'content-type': typ}));

const String _stronaZOpisem = '''
<!doctype html><html><head>
<meta charset="utf-8">
<meta property="og:site_name" content="Przykład">
<meta property="og:title" content="Tytuł strony">
<meta property="og:description" content="Opis strony &amp; reszta.">
<title>Zapasowy tytuł</title>
</head><body>tresc</body></html>
''';

void main() {
  group('parsePreviewMeta', () {
    test('bierze znaczniki Open Graph', () {
      final meta = parsePreviewMeta(_stronaZOpisem);
      expect(meta.siteName, 'Przykład');
      expect(meta.title, 'Tytuł strony');
      expect(meta.description, 'Opis strony & reszta.');
    });

    test('bez og wraca do <title> i description', () {
      final meta = parsePreviewMeta(
        '<head><title>Sam tytuł</title>'
        '<meta name="description" content="Zwykły opis"></head>',
      );
      expect(meta.title, 'Sam tytuł');
      expect(meta.description, 'Zwykły opis');
    });

    test('twitter: to zapasowa droga', () {
      final meta = parsePreviewMeta(
        '<head><meta name="twitter:title" content="Z ptaszka">'
        '<meta name="twitter:image" content="/a.png"></head>',
      );
      expect(meta.title, 'Z ptaszka');
      expect(meta.image, '/a.png');
    });

    test('kolejność atrybutów i apostrofy nie mają znaczenia', () {
      final meta = parsePreviewMeta(
        "<head><meta content='Odwrotnie' property='og:title'></head>",
      );
      expect(meta.title, 'Odwrotnie');
    });

    test('treść spoza <head> nie trafia do karty', () {
      final meta = parsePreviewMeta(
        '<head><title>Nagłówek</title></head>'
        '<body><meta property="og:title" content="Podszywka"></body>',
      );
      expect(meta.title, 'Nagłówek');
    });

    test('encje są rozwijane, a nie pokazywane', () {
      final meta = parsePreviewMeta(
        '<head><meta property="og:title" '
        'content="A &lt;b&gt; &amp; &#65; &#x42;"></head>',
      );
      expect(meta.title, 'A <b> & A B');
    });

    test('znaki sterujące i przestawiające kierunek wylatują', () {
      final meta = parsePreviewMeta(
        '<head><meta property="og:title" content="Tytul\u202Egyp.exe"></head>',
      );
      expect(meta.title, 'Tytulgyp.exe');
    });

    test('długi tytuł jest przycinany', () {
      final meta = parsePreviewMeta(
        '<head><meta property="og:title" content="${'a' * 500}"></head>',
      );
      expect(meta.title!.length, lessThanOrEqualTo(141));
      expect(meta.title!.endsWith('…'), isTrue);
    });

    test('białe znaki są zbijane do jednej spacji', () {
      final meta = parsePreviewMeta(
        '<head><meta property="og:title" content="  dwa\n\n  slowa  "></head>',
      );
      expect(meta.title, 'dwa slowa');
    });

    test('strona bez niczego nie daje nic', () {
      final meta = parsePreviewMeta('<html><body>nic</body></html>');
      expect(meta.title, isNull);
      expect(meta.description, isNull);
      expect(meta.image, isNull);
    });
  });

  group('hostAllowsPreview', () {
    test('nazwa wskazująca na sieć lokalną jest odrzucana', () async {
      expect(await hostAllowsPreview('zly.example', resolve: _lokalny), isFalse);
    });

    test('nazwa wskazująca na adres publiczny przechodzi', () async {
      expect(
          await hostAllowsPreview('example.com', resolve: _publiczny), isTrue);
    });

    test('jeden lokalny wpis psuje całą nazwę', () async {
      Future<List<InternetAddress>> mieszany(String host) async => [
            InternetAddress('93.184.216.34'),
            InternetAddress('127.0.0.1'),
          ];
      expect(await hostAllowsPreview('example.com', resolve: mieszany), isFalse);
    });

    test('brak odpowiedzi DNS-u znaczy „nie"', () async {
      Future<List<InternetAddress>> pusty(String host) async => [];
      expect(await hostAllowsPreview('example.com', resolve: pusty), isFalse);

      Future<List<InternetAddress>> bledny(String host) async =>
          throw const SocketException('brak');
      expect(await hostAllowsPreview('example.com', resolve: bledny), isFalse);
    });

    test('adres lokalny wpisany wprost nie idzie nawet do DNS-u', () async {
      var pytano = false;
      Future<List<InternetAddress>> licznik(String host) async {
        pytano = true;
        return [InternetAddress('93.184.216.34')];
      }

      expect(await hostAllowsPreview('192.168.0.1', resolve: licznik), isFalse);
      expect(await hostAllowsPreview('localhost', resolve: licznik), isFalse);
      expect(pytano, isFalse);
    });
  });

  group('LinkPreviewService', () {
    test('wyłączony nie rusza sieci', () async {
      var pytano = false;
      final serwis = LinkPreviewService(
        client: MockClient((_) async {
          pytano = true;
          return http.Response('', 200);
        }),
        resolve: _publiczny,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('https://example.com/')), isNull);
      expect(pytano, isFalse);
    });

    test('włączony składa kartę ze znaczników strony', () async {
      final serwis = LinkPreviewService(
        client: _strona(_stronaZOpisem),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      final podglad = await serwis.previewOf(Uri.parse('https://example.com/'));
      expect(podglad, isNotNull);
      expect(podglad!.title, 'Tytuł strony');
      expect(podglad.description, 'Opis strony & reszta.');
      expect(podglad.label, 'Przykład');
      expect(podglad.imageBytes, isNull);
    });

    test('drugie pytanie o ten sam adres nie idzie w sieć', () async {
      var ile = 0;
      final serwis = LinkPreviewService(
        client: MockClient((_) async {
          ile++;
          return http.Response(_stronaZOpisem, 200,
              headers: {'content-type': 'text/html; charset=utf-8'});
        }),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      final adres = Uri.parse('https://example.com/');
      await serwis.previewOf(adres);
      await serwis.previewOf(adres);
      expect(ile, 1);
      expect(serwis.cached(adres), isNotNull);
    });

    test('dwa pytania naraz to jedno połączenie', () async {
      var ile = 0;
      final serwis = LinkPreviewService(
        client: MockClient((_) async {
          ile++;
          return http.Response(_stronaZOpisem, 200,
              headers: {'content-type': 'text/html; charset=utf-8'});
        }),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      final adres = Uri.parse('https://example.com/');
      await Future.wait([serwis.previewOf(adres), serwis.previewOf(adres)]);
      expect(ile, 1);
    });

    test('wyłączenie czyści to, co zdążyło przyjść', () async {
      final serwis = LinkPreviewService(
        client: _strona(_stronaZOpisem),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      final adres = Uri.parse('https://example.com/');
      await serwis.previewOf(adres);
      expect(serwis.cached(adres), isNotNull);
      serwis.clear();
      expect(serwis.cached(adres), isNull);
      expect(serwis.asked(adres), isFalse);
    });

    test('adres w sieci lokalnej nie jest odpytywany', () async {
      var pytano = false;
      final serwis = LinkPreviewService(
        client: MockClient((_) async {
          pytano = true;
          return http.Response(_stronaZOpisem, 200,
              headers: {'content-type': 'text/html; charset=utf-8'});
        }),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('http://192.168.0.1/')), isNull);
      expect(await serwis.previewOf(Uri.parse('http://router.local/')), isNull);
      expect(pytano, isFalse);
    });

    test('nazwa rozwiązująca się na sieć lokalną też nie', () async {
      var pytano = false;
      final serwis = LinkPreviewService(
        client: MockClient((_) async {
          pytano = true;
          return http.Response(_stronaZOpisem, 200,
              headers: {'content-type': 'text/html; charset=utf-8'});
        }),
        resolve: _lokalny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('https://zly.example/')), isNull);
      expect(pytano, isFalse);
    });

    test('przekierowanie jest sprawdzane od nowa', () async {
      final odwiedzone = <String>[];
      final serwis = LinkPreviewService(
        client: MockClient((zadanie) async {
          odwiedzone.add(zadanie.url.toString());
          if (zadanie.url.path == '/dalej') {
            return http.Response(_stronaZOpisem, 200,
                headers: {'content-type': 'text/html; charset=utf-8'});
          }
          return http.Response('', 302, headers: {'location': '/dalej'});
        }),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      final podglad = await serwis.previewOf(Uri.parse('https://example.com/'));
      expect(podglad?.title, 'Tytuł strony');
      expect(odwiedzone,
          ['https://example.com/', 'https://example.com/dalej']);
    });

    test('przekierowanie do sieci lokalnej kończy sprawę', () async {
      final odwiedzone = <String>[];
      final serwis = LinkPreviewService(
        client: MockClient((zadanie) async {
          odwiedzone.add(zadanie.url.toString());
          return http.Response('', 302,
              headers: {'location': 'http://127.0.0.1/panel'});
        }),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('https://example.com/')), isNull);
      expect(odwiedzone, ['https://example.com/']);
    });

    test('przekierowanie na inny schemat kończy sprawę', () async {
      final serwis = LinkPreviewService(
        client: MockClient((_) async => http.Response('', 302,
            headers: {'location': 'file:///etc/passwd'})),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('https://example.com/')), isNull);
    });

    test('pętla przekierowań nie kręci się w nieskończoność', () async {
      var ile = 0;
      final serwis = LinkPreviewService(
        client: MockClient((zadanie) async {
          ile++;
          final numer = ile;
          return http.Response('', 302, headers: {'location': '/krok$numer'});
        }),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('https://example.com/')), isNull);
      expect(ile, lessThanOrEqualTo(previewMaxRedirects + 1));
    });

    test('brak charsetu w nagłówku nie przeszkadza', () async {
      final serwis = LinkPreviewService(
        client: MockClient((_) async => http.Response(
              '<head><meta property="og:title" content="Bez charsetu"></head>',
              200,
              headers: {'content-type': 'text/html'},
            )),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      final podglad = await serwis.previewOf(Uri.parse('https://example.com/'));
      expect(podglad?.title, 'Bez charsetu');
    });

    test('nie-HTML jest odrzucany', () async {
      final serwis = LinkPreviewService(
        client: MockClient((_) async => http.Response(
              jsonEncode({'a': 1}),
              200,
              headers: {'content-type': 'application/json'},
            )),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('https://example.com/')), isNull);
    });

    test('odpowiedź inna niż 200 nie daje karty', () async {
      final serwis = LinkPreviewService(
        client: MockClient((_) async => http.Response('nie ma', 404,
            headers: {'content-type': 'text/html; charset=utf-8'})),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('https://example.com/')), isNull);
    });

    test('zapowiedziana długość ponad granicę zamyka temat', () async {
      final serwis = LinkPreviewService(
        client: _strona('x' * (previewHtmlLimit + 1)),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('https://example.com/')), isNull);
    });

    test('strona bez końca jest ucinana i odrzucana', () async {
      // Bez zapowiedzianej długości: granicę trzyma dopiero czytanie.
      var wyslane = 0;
      final serwis = LinkPreviewService(
        client: MockClient.streaming((_, _) async {
          // Leniwie: licznik rośnie o to, co zostało naprawdę pobrane,
          // więc widać, że czytanie urywa się na granicy, a nie po całości.
          final strumien = Stream<List<int>>.fromIterable(
            Iterable<List<int>>.generate(64, (_) {
              wyslane += 16 * 1024;
              return List<int>.filled(16 * 1024, 65);
            }),
          );
          return http.StreamedResponse(strumien, 200,
              headers: {'content-type': 'text/html; charset=utf-8'});
        }),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('https://example.com/')), isNull);
      expect(wyslane, greaterThan(previewHtmlLimit));
      // Gdyby granicy nie było, doszłoby całe 1 MB.
      expect(wyslane, lessThan(1024 * 1024));
    });

    test('strona bez tytułu i opisu nie daje karty', () async {
      final serwis = LinkPreviewService(
        client: _strona('<html><body>nic tu nie ma</body></html>'),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('https://example.com/')), isNull);
    });

    test('obrazek dochodzi osobnym pytaniem', () async {
      final serwis = LinkPreviewService(
        client: MockClient((zadanie) async {
          if (zadanie.url.path == '/obraz.png') {
            return MockClient.pngResponse();
          }
          return http.Response(
            '<head><meta property="og:title" content="Z obrazkiem">'
            '<meta property="og:image" content="/obraz.png"></head>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      final podglad = await serwis.previewOf(Uri.parse('https://example.com/a'));
      expect(podglad?.title, 'Z obrazkiem');
      expect(podglad?.imageBytes, isNotNull);
    });

    test('SVG jako obrazek nie przechodzi', () async {
      // SVG to dokument, który potrafi nieść skrypty, więc nie ma go na
      // liście formatów podglądu.
      final serwis = LinkPreviewService(
        client: MockClient((zadanie) async {
          if (zadanie.url.path == '/obraz.svg') {
            return http.Response('<svg onload="x()"/>', 200,
                headers: {'content-type': 'image/svg+xml'});
          }
          return http.Response(
            '<head><meta property="og:title" content="Z SVG">'
            '<meta property="og:image" content="/obraz.svg"></head>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      final podglad = await serwis.previewOf(Uri.parse('https://example.com/a'));
      expect(podglad?.title, 'Z SVG');
      expect(podglad?.imageBytes, isNull);
    });

    test('obrazek spod adresu lokalnego nie jest pobierany', () async {
      var pytanoOObraz = false;
      final serwis = LinkPreviewService(
        client: MockClient((zadanie) async {
          if (zadanie.url.host != 'example.com') {
            pytanoOObraz = true;
            return MockClient.pngResponse();
          }
          return http.Response(
            '<head><meta property="og:title" content="Sonda">'
            '<meta property="og:image" content="http://192.168.0.1/x.png">'
            '</head>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      final podglad = await serwis.previewOf(Uri.parse('https://example.com/a'));
      expect(podglad?.imageBytes, isNull);
      expect(pytanoOObraz, isFalse);
    });

    test('błąd sieci kończy się brakiem karty, nie wyjątkiem', () async {
      final serwis = LinkPreviewService(
        client: MockClient((_) async => throw const SocketException('brak')),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('https://example.com/')), isNull);
    });

    test('inne schematy nie są pobierane', () async {
      final serwis = LinkPreviewService(
        client: _strona(_stronaZOpisem),
        resolve: _publiczny,
        enabled: true,
      );
      addTearDown(serwis.dispose);

      expect(await serwis.previewOf(Uri.parse('ftp://example.com/')), isNull);
    });
  });
}
