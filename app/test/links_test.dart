import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/links.dart';

/// Odnośnik w rozmowie jest napisem od obcego, więc rozpoznawanie go musi
/// przepuszczać dokładnie to, co da się bezpiecznie otworzyć, a resztę
/// zostawiać zwykłym tekstem. Testy trzymają tę granicę w miejscu.
void main() {
  group('findLinks', () {
    test('znajduje adres http i https', () {
      final wynik = findLinks('zobacz https://example.com/a i http://b.example');
      expect(wynik.map((l) => l.uri.toString()),
          ['https://example.com/a', 'http://b.example']);
    });

    test('www bez schematu dostaje https', () {
      final wynik = findLinks('wejdz na www.example.com/x');
      expect(wynik.single.text, 'www.example.com/x');
      expect(wynik.single.uri.toString(), 'https://www.example.com/x');
    });

    test('kropka na końcu zdania nie należy do adresu', () {
      final wynik = findLinks('Jest na https://example.com/strona.');
      expect(wynik.single.text, 'https://example.com/strona');
    });

    test('nawias domknięty w adresie zostaje, cudzy nie', () {
      final wpisany = findLinks(
          'artykul https://pl.wikipedia.org/wiki/Dart_(jezyk_programowania)');
      expect(wpisany.single.text,
          'https://pl.wikipedia.org/wiki/Dart_(jezyk_programowania)');

      final wNawiasie = findLinks('(zobacz https://example.com/a)');
      expect(wNawiasie.single.text, 'https://example.com/a');
    });

    test('pozycje wskazują dokładnie na adres w tekście', () {
      const tresc = 'aa https://example.com bb';
      final link = findLinks(tresc).single;
      expect(tresc.substring(link.start, link.end), link.text);
    });

    test('inne schematy nie stają się odnośnikiem', () {
      for (final tekst in [
        'javascript:alert(1)',
        'data:text/html,<script>x</script>',
        'file:///etc/passwd',
        'mailto:kto@example.com',
        'intent://scan#Intent;scheme=zxing;end',
        'content://media/external/images/1',
      ]) {
        expect(findLinks('tresc $tekst koniec'), isEmpty, reason: tekst);
      }
    });

    test('sam napis z kropką to nie odnośnik', () {
      expect(findLinks('plik.txt i katalog.zip'), isEmpty);
    });

    test('adres musi się zaczynać na granicy wyrazu', () {
      // Inaczej z adresu poczty wypadłby odnośnik, którego w tekście nie ma.
      expect(findLinks('jan@www.example.com'), isEmpty);
      expect(findLinks('plikwww.example.com'), isEmpty);
      expect(findLinks('(www.example.com)').single.text, 'www.example.com');
    });

    test('nazwa serwera bez kropki odpada', () {
      expect(parseLink('http://localhost:8080/panel'), isNull);
      expect(parseLink('http://serwer/panel'), isNull);
    });

    test('adres IP wpisany wprost przechodzi', () {
      expect(parseLink('http://192.168.0.1/')?.host, '192.168.0.1');
    });

    test('znaki niewidzialne wykluczają adres', () {
      // Przełącznik kierunku pisma potrafi pokazać inną końcówkę adresu, niż
      // zostanie otwarta.
      expect(parseLink('https://example.com/plik\u202Etxt.exe'), isNull);
      expect(parseLink('https://exa\u200Bmple.com'), isNull);
    });
  });

  group('warningsFor', () {
    test('login przed nazwą serwera', () {
      final ostrzezenia = warningsFor(Uri.parse('https://bank.pl@zly.example/'));
      expect(ostrzezenia, contains(LinkWarning.userInfo));
    });

    test('litery spoza ASCII w nazwie serwera', () {
      // Trzy postacie tej samej sztuczki: znaki wprost, zapis procentowy
      // (tak trzyma je `Uri.host`) i zapis `xn--` używany przez DNS.
      expect(warningsFor(Uri.parse('https://аpple.com/')),
          contains(LinkWarning.nonAsciiHost));
      expect(warningsFor(Uri.parse('https://xn--pple-43d.com/')),
          contains(LinkWarning.nonAsciiHost));
      expect(warningsFor(Uri.parse('https://example.com/')),
          isNot(contains(LinkWarning.nonAsciiHost)));
    });

    test('nazwa zapisana procentowo to nie adres lokalny', () {
      // `Uri.host` zapisuje cyrylickie „а" jako „%D0%B0". Ucięcie wszystkiego
      // od procentu zrobiłoby z tego pustą nazwę, a pusta nazwa liczy się jako
      // lokalna — cudzy serwer dostałby wtedy ostrzeżenie o Twoim routerze
      // zamiast tego o podszyciu.
      final ostrzezenia = warningsFor(Uri.parse('https://аpple.com/'));
      expect(ostrzezenia, isNot(contains(LinkWarning.localAddress)));
      expect(isLocalHost(Uri.parse('https://аpple.com/').host), isFalse);
    });

    test('http to brak szyfrowania', () {
      expect(warningsFor(Uri.parse('http://example.com/')),
          contains(LinkWarning.insecure));
      expect(warningsFor(Uri.parse('https://example.com/')),
          isNot(contains(LinkWarning.insecure)));
    });

    test('adres w sieci lokalnej', () {
      expect(warningsFor(Uri.parse('http://192.168.0.1/')),
          contains(LinkWarning.localAddress));
    });

    test('zwykły adres nie ma o czym ostrzegać', () {
      expect(warningsFor(Uri.parse('https://example.com/a')), isEmpty);
    });
  });

  group('isLocalHost', () {
    test('to urządzenie i sieć lokalna', () {
      for (final host in [
        'localhost',
        '127.0.0.1',
        '127.1.2.3',
        '0.0.0.0',
        '10.0.0.5',
        '172.16.3.4',
        '172.31.255.255',
        '192.168.1.1',
        '169.254.10.1',
        '100.64.0.1',
        '198.18.0.1',
        '255.255.255.255',
        '224.0.0.1',
        '[::1]',
        '[fe80::1]',
        '[fe80::1%eth0]',
        '[fd00::1]',
        '[::ffff:192.168.0.1]',
        'drukarka.local',
        'panel.internal',
        'router.lan',
        'serwer',
      ]) {
        expect(isLocalHost(host), isTrue, reason: host);
      }
    });

    test('adresy publiczne przechodzą', () {
      for (final host in [
        'example.com',
        '8.8.8.8',
        '1.1.1.1',
        '172.32.0.1',
        '172.15.0.1',
        '192.169.0.1',
        '[2606:4700:4700::1111]',
      ]) {
        expect(isLocalHost(host), isFalse, reason: host);
      }
    });

    test('isLocalAddress zgadza się z isLocalHost', () {
      expect(isLocalAddress(InternetAddress('10.1.2.3')), isTrue);
      expect(isLocalAddress(InternetAddress('93.184.216.34')), isFalse);
    });
  });

  group('shortenLink', () {
    test('sam serwer, gdy nie ma ścieżki', () {
      expect(shortenLink(Uri.parse('https://example.com/')), 'example.com');
      expect(shortenLink(Uri.parse('https://example.com:8443/')),
          'example.com:8443');
    });

    test('długa ścieżka jest przycinana, serwer zostaje', () {
      final krotki = shortenLink(
        Uri.parse('https://example.com/${'a' * 200}'),
        limit: 40,
      );
      expect(krotki.startsWith('example.com/'), isTrue);
      expect(krotki.length, lessThanOrEqualTo(40));
      expect(krotki.endsWith('…'), isTrue);
    });
  });

  group('openExternalLink', () {
    test('cudzy schemat nie trafia do systemu', () async {
      // Ostatnia zapora przed oddaniem adresu systemowi: nawet gdyby taki
      // adres jakoś doszedł tutaj, nie ma prawa nic uruchomić.
      expect(await openExternalLink(Uri.parse('file:///etc/passwd')),
          LinkOpenResult.failed);
      expect(await openExternalLink(Uri.parse('javascript:alert(1)')),
          LinkOpenResult.failed);
    });
  });
}
