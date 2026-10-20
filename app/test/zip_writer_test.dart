import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/core/zip_writer.dart';

/// Zapis ZIP do eksportu danych (issue #50). Archiwa sprawdza najprostszy
/// czytnik napisany tutaj, od końca: rekord końca archiwum, katalog
/// centralny, nagłówki lokalne, dane. Po drodze pilnuje wszystkiego, co
/// obiecuje [ZipWriter]: nagłówek lokalny zgodny z katalogiem (poprawione
/// CRC i rozmiary), wpisy jeden za drugim bez dziur i śmieci po cofniętym
/// wpisie, CRC i rozmiar każdego wpisu po rozpakowaniu.
void main() {
  late Directory katalog;

  setUp(() => katalog = Directory.systemTemp.createTempSync('chatt_zip_'));
  tearDown(() => katalog.deleteSync(recursive: true));

  String sciezka(String nazwa) => p.join(katalog.path, nazwa);

  /// Losowe bajty: DEFLATE ich nie zmniejszy.
  Uint8List losowe(int ile, {int ziarno = 1}) {
    final los = Random(ziarno);
    return Uint8List.fromList(List.generate(ile, (_) => los.nextInt(256)));
  }

  String plik(String nazwa, List<int> bajty) {
    final s = sciezka(nazwa);
    File(s).writeAsBytesSync(bajty);
    return s;
  }

  List<_Odczytany> otworz(String zip) =>
      _czytajZip(File(zip).readAsBytesSync());

  group('CRC-32', () {
    test('zgadza się z wektorami wzorcowymi', () {
      expect(Crc32.of(const []), 0);
      expect(Crc32.of(ascii.encode('123456789')), 0xCBF43926);
      expect(Crc32.of(ascii.encode('The quick brown fox jumps over the lazy dog')),
          0x414FA339);
    });

    test('liczone kawałkami daje to samo co w całości', () {
      final dane = losowe(100000);
      final crc = Crc32();
      for (var i = 0; i < dane.length; i += 777) {
        crc.add(Uint8List.sublistView(dane, i, min(i + 777, dane.length)));
      }
      expect(crc.value, Crc32.of(dane));
    });
  });

  test('pusty ZIP to sam koniec archiwum', () {
    final zip = ZipWriter(sciezka('pusty.zip'));
    expect(zip.close(), 22);
    expect(File(sciezka('pusty.zip')).lengthSync(), 22);
    expect(otworz(sciezka('pusty.zip')), isEmpty);
  });

  test('teksty skompresowane, pliki wprost, polskie nazwy w UTF-8', () {
    final kiedy = DateTime(2026, 10, 18, 15, 30, 13);
    final tekst = 'Zażółć gęślą jaźń. ' * 2000;
    final binarne = losowe(5000);
    // Ponad jeden kawałek odczytu (1 MiB) i ponad jeden kawałek kompresji.
    final duzy = losowe(2500000, ziarno: 7);
    final powtarzalne = Uint8List(300000)..fillRange(0, 300000, 0x41);

    final zip = ZipWriter(sciezka('a.zip'));
    zip.addText('README.txt', tekst, modified: kiedy);
    zip.addText('pusty.txt', '', modified: kiedy);
    zip.addBytes('dane/binarne.bin', binarne,
        compress: false, modified: kiedy);
    zip.addBytes('dane/powtarzalne.bin', powtarzalne, modified: kiedy);
    zip.addFile('files/zdjęcie z wakacji ąę.jpg', plik('zrodlo.jpg', duzy),
        modified: kiedy);
    zip.addFile('files/pusty plik', plik('pusty', const []), modified: kiedy);
    final rozmiar = zip.close();

    expect(rozmiar, File(sciezka('a.zip')).lengthSync());
    final wpisy = otworz(sciezka('a.zip'));
    expect(wpisy.map((w) => w.nazwa), [
      'README.txt',
      'pusty.txt',
      'dane/binarne.bin',
      'dane/powtarzalne.bin',
      'files/zdjęcie z wakacji ąę.jpg',
      'files/pusty plik',
    ]);
    final poNazwie = {for (final w in wpisy) w.nazwa: w};

    expect(utf8.decode(poNazwie['README.txt']!.dane), tekst);
    expect(poNazwie['README.txt']!.metoda, 8);
    expect(poNazwie['README.txt']!.spakowane, lessThan(tekst.length ~/ 10));
    expect(poNazwie['pusty.txt']!.dane, isEmpty);
    expect(poNazwie['pusty.txt']!.metoda, 8);
    expect(poNazwie['dane/binarne.bin']!.dane, binarne);
    expect(poNazwie['dane/binarne.bin']!.metoda, 0);
    expect(poNazwie['dane/powtarzalne.bin']!.dane, powtarzalne);
    expect(poNazwie['dane/powtarzalne.bin']!.metoda, 8);
    expect(poNazwie['files/zdjęcie z wakacji ąę.jpg']!.dane, duzy);
    expect(poNazwie['files/zdjęcie z wakacji ąę.jpg']!.metoda, 0);
    expect(poNazwie['files/pusty plik']!.dane, isEmpty);

    for (final w in wpisy) {
      expect(w.flagi & 0x0800, 0x0800, reason: 'bit 11: nazwa w UTF-8');
      expect(w.flagi & 0x0008, 0, reason: 'bez deskryptorów danych');
      // 15:30:13 w zapisie MS-DOS: dwusekundowa dokładność.
      expect(w.czas, (15 << 11) | (30 << 5) | 6);
      expect(w.data, ((2026 - 1980) << 9) | (10 << 5) | 18);
    }
  });

  test('data modyfikacji pliku trafia do wpisu, gdy nie podano innej', () {
    final zrodlo = plik('stary.txt', ascii.encode('abc'));
    File(zrodlo).setLastModifiedSync(DateTime(2024, 2, 29, 23, 59, 58));
    final zip = ZipWriter(sciezka('b.zip'))..addFile('stary.txt', zrodlo);
    zip.close();
    final wpis = otworz(sciezka('b.zip')).single;
    expect(wpis.czas, (23 << 11) | (59 << 5) | 29);
    expect(wpis.data, ((2024 - 1980) << 9) | (2 << 5) | 29);
  });

  group('granice formatu', () {
    test('liczba wpisów: kolejny wpis odpada, archiwum zostaje całe', () {
      final zip = ZipWriter(sciezka('c.zip'), maxEntries: 3);
      zip.addText('1.txt', 'jeden');
      zip.addText('2.txt', 'dwa');
      expect(
        () => zip.addText('3.txt', 'trzy', reserveEntries: 1),
        throwsA(isA<ZipLimitExceeded>()
            .having((b) => b.limit, 'limit', ZipLimit.entryCount)
            .having((b) => b.entry, 'entry', '3.txt')),
      );
      zip.addText('3.txt', 'trzy');
      expect(zip.entryCount, 3);
      expect(
        () => zip.addFile('4.bin', plik('4.bin', [1, 2, 3])),
        throwsA(isA<ZipLimitExceeded>()
            .having((b) => b.limit, 'limit', ZipLimit.entryCount)),
      );
      zip.close();
      expect(otworz(sciezka('c.zip')).map((w) => w.nazwa),
          ['1.txt', '2.txt', '3.txt']);
    });

    test('rozmiar archiwum: za duży plik odpada przed zapisem', () {
      final zip = ZipWriter(sciezka('d.zip'), maxBytes: 4096);
      zip.addText('a.txt', 'krótki tekst');
      final przed = zip.length;
      expect(
        () => zip.addFile('duzy.bin', plik('duzy.bin', losowe(10000))),
        throwsA(isA<ZipLimitExceeded>()
            .having((b) => b.limit, 'limit', ZipLimit.archiveSize)
            .having((b) => b.entry, 'entry', 'duzy.bin')),
      );
      expect(zip.length, przed);
      // Archiwum rośnie w pliku roboczym obok celu.
      expect(File('${sciezka('d.zip')}.part').lengthSync(), przed);
      zip.addFile('maly.bin', plik('maly.bin', losowe(1000)));
      final rozmiar = zip.close();
      expect(rozmiar, lessThanOrEqualTo(4096));
      final wpisy = otworz(sciezka('d.zip'));
      expect(wpisy.map((w) => w.nazwa), ['a.txt', 'maly.bin']);
      expect(wpisy.last.dane, losowe(1000));
    });

    test('rozmiar archiwum: kompresja przerwana w połowie wpisu się cofa', () {
      final zip = ZipWriter(sciezka('e.zip'), maxBytes: 8192);
      zip.addText('a.txt', 'przed');
      final przed = zip.length;
      // Losowe bajty po DEFLATE dalej mają ponad 20 kB: granica pęka
      // w trakcie strumienia, gdy nagłówek wpisu leży już na dysku.
      expect(
        () => zip.addBytes('losowe.bin', losowe(20000)),
        throwsA(isA<ZipLimitExceeded>()
            .having((b) => b.limit, 'limit', ZipLimit.archiveSize)),
      );
      expect(zip.length, przed);
      expect(File('${sciezka('e.zip')}.part').lengthSync(), przed);
      zip.addText('b.txt', 'po');
      zip.close();
      final wpisy = otworz(sciezka('e.zip'));
      expect(wpisy.map((w) => utf8.decode(w.dane)), ['przed', 'po']);
    });

    test('rezerwa miejsca na wpisy, które przyjdą później', () {
      final zip = ZipWriter(sciezka('f.zip'), maxBytes: 4096);
      final dane = losowe(2000);
      expect(
        () => zip.addBytes('a.bin', dane, compress: false, reserveBytes: 2500),
        throwsA(isA<ZipLimitExceeded>()
            .having((b) => b.limit, 'limit', ZipLimit.archiveSize)),
      );
      zip.addBytes('a.bin', dane, compress: false, reserveBytes: 1500);
      zip.close();
      expect(otworz(sciezka('f.zip')).single.dane, dane);
    });

    test('rozmiar wpisu: liczy się przed kompresją', () {
      final zip = ZipWriter(sciezka('g.zip'), maxEntryBytes: 1000);
      zip.addText('999.txt', 'a' * 1000);
      // Po DEFLATE to kilkanaście bajtów, ale pole rozmiaru i tak by pękło.
      expect(
        () => zip.addText('2000.txt', 'a' * 2000),
        throwsA(isA<ZipLimitExceeded>()
            .having((b) => b.limit, 'limit', ZipLimit.entrySize)),
      );
      expect(
        () => zip.addFile('plik.bin', plik('plik.bin', losowe(1001))),
        throwsA(isA<ZipLimitExceeded>()
            .having((b) => b.limit, 'limit', ZipLimit.entrySize)),
      );
      zip.addText('koniec.txt', 'koniec');
      zip.close();
      expect(otworz(sciezka('g.zip')).map((w) => w.nazwa),
          ['999.txt', 'koniec.txt']);
    });

    test('entryBound jest górną granicą przyrostu archiwum', () {
      final bazowe = (ZipWriter(sciezka('h.zip'))..addText('wstęp.txt', 'w'))
          .close();
      for (final (nazwa, dane, kompresja) in [
        ('losowe.bin', losowe(70000), true),
        ('losowe-wprost.bin', losowe(70000), false),
        ('pusty.txt', Uint8List(0), true),
        ('zażółć.txt', utf8.encode('gęś' * 5000), true),
      ]) {
        final zip = ZipWriter(sciezka('h.zip'))
          ..addText('wstęp.txt', 'w')
          ..addBytes(nazwa, dane, compress: kompresja);
        // Nagłówek lokalny, dane i rekord katalogu centralnego tego wpisu.
        final przyrost = zip.close() - bazowe;
        expect(
            przyrost,
            lessThanOrEqualTo(
                ZipWriter.entryBound(nazwa, dane.length, compress: kompresja)),
            reason: nazwa);
      }
    });
  });

  test('plik źródłowy, którego nie ma, nie zostawia śladu w archiwum', () {
    final zip = ZipWriter(sciezka('i.zip'));
    zip.addText('a.txt', 'a');
    expect(
      () => zip.addFile('brak.bin', sciezka('nie-ma-mnie.bin')),
      throwsA(isA<ZipSourceException>()),
    );
    zip.addText('b.txt', 'b');
    zip.close();
    expect(otworz(sciezka('i.zip')).map((w) => w.nazwa), ['a.txt', 'b.txt']);
  });

  test('nazwy: powtórka bez względu na wielkość liter i ścieżki z ucieczką',
      () {
    final zip = ZipWriter(sciezka('j.zip'));
    zip.addText('Plik.txt', '1');
    for (final zla in [
      'plik.TXT',
      '',
      '/bezwzgledna.txt',
      '../poza.txt',
      'files/../poza.txt',
      'files/./x.txt',
      'katalog/',
      r'files\windows.txt',
    ]) {
      expect(() => zip.addText(zla, 'x'), throwsArgumentError, reason: zla);
    }
    zip.close();
    expect(otworz(sciezka('j.zip')).single.nazwa, 'Plik.txt');
  });

  test('abort kasuje plik, zamknięte archiwum nie przyjmuje wpisów', () {
    final porzucone = ZipWriter(sciezka('k.zip'))..addText('a.txt', 'a');
    porzucone.abort();
    expect(File(sciezka('k.zip')).existsSync(), isFalse);
    expect(File('${sciezka('k.zip')}.part').existsSync(), isFalse);
    expect(() => porzucone.addText('b.txt', 'b'), throwsStateError);

    final zamkniete = ZipWriter(sciezka('l.zip'))..close();
    expect(() => zamkniete.addText('a.txt', 'a'), throwsStateError);
    zamkniete.abort();
    expect(File(sciezka('l.zip')).existsSync(), isTrue,
        reason: 'abort po close niczego nie kasuje');
    expect(File('${sciezka('l.zip')}.part').existsSync(), isFalse);
  });

  test('porzucone archiwum zostawia poprzedni plik pod tą samą nazwą', () {
    final stary = File(sciezka('m.zip'))..writeAsBytesSync([1, 2, 3]);
    final zip = ZipWriter(stary.path)..addText('a.txt', 'nowe');
    expect(stary.readAsBytesSync(), [1, 2, 3],
        reason: 'w trakcie zapisu cel jest nietknięty');
    zip.abort();
    expect(stary.readAsBytesSync(), [1, 2, 3]);
    expect(File('${stary.path}.part').existsSync(), isFalse);
  });

  test('zamknięte archiwum zastępuje poprzedni plik pod tą samą nazwą', () {
    final stary = File(sciezka('n.zip'))..writeAsBytesSync([1, 2, 3]);
    ZipWriter(stary.path)
      ..addText('a.txt', 'nowe')
      ..close();
    expect(otworz(stary.path).single.nazwa, 'a.txt');
    expect(File('${stary.path}.part').existsSync(), isFalse);
  });
}

/// Wpis odczytany przez czytnik w teście.
class _Odczytany {
  final String nazwa;
  final int flagi;
  final int metoda;
  final int czas;
  final int data;
  final int spakowane;
  final Uint8List dane;

  _Odczytany(this.nazwa, this.flagi, this.metoda, this.czas, this.data,
      this.spakowane, this.dane);
}

/// Najprostszy czytnik ZIP bez ZIP64, z kontrolą spójności na każdym kroku.
List<_Odczytany> _czytajZip(Uint8List zip) {
  final b = ByteData.sublistView(zip);
  int u16(int o) => b.getUint16(o, Endian.little);
  int u32(int o) => b.getUint32(o, Endian.little);

  expect(zip.length, greaterThanOrEqualTo(22));
  // Archiwum bez komentarza: koniec archiwum to ostatnie 22 bajty.
  final koniec = zip.length - 22;
  expect(u32(koniec), 0x06054b50);
  expect(u16(koniec + 4), 0);
  expect(u16(koniec + 6), 0);
  final ile = u16(koniec + 10);
  expect(u16(koniec + 8), ile);
  final rozmiarKatalogu = u32(koniec + 12);
  final poczatekKatalogu = u32(koniec + 16);
  expect(u16(koniec + 20), 0);
  expect(poczatekKatalogu + rozmiarKatalogu, koniec);

  final wynik = <_Odczytany>[];
  var o = poczatekKatalogu;
  var nastepny = 0;
  for (var i = 0; i < ile; i++) {
    expect(u32(o), 0x02014b50);
    final flagi = u16(o + 8);
    final metoda = u16(o + 10);
    final czas = u16(o + 12);
    final data = u16(o + 14);
    final crc = u32(o + 16);
    final spakowane = u32(o + 20);
    final surowe = u32(o + 24);
    final n = u16(o + 28);
    final dodatkowe = u16(o + 30);
    final komentarz = u16(o + 32);
    final lokalny = u32(o + 42);
    final nazwaBajty = Uint8List.sublistView(zip, o + 46, o + 46 + n);
    final nazwa = (flagi & 0x0800) != 0
        ? utf8.decode(nazwaBajty)
        : latin1.decode(nazwaBajty);
    o += 46 + n + dodatkowe + komentarz;

    expect(lokalny, nastepny, reason: 'wpisy jeden za drugim: $nazwa');
    expect(u32(lokalny), 0x04034b50);
    expect(u16(lokalny + 6), flagi);
    expect(u16(lokalny + 8), metoda);
    expect(u16(lokalny + 10), czas);
    expect(u16(lokalny + 12), data);
    expect(u32(lokalny + 14), crc, reason: 'CRC w nagłówku lokalnym: $nazwa');
    expect(u32(lokalny + 18), spakowane);
    expect(u32(lokalny + 22), surowe);
    expect(u16(lokalny + 26), n);
    expect(Uint8List.sublistView(zip, lokalny + 30, lokalny + 30 + n),
        nazwaBajty);
    final start = lokalny + 30 + n + u16(lokalny + 28);
    final spak = Uint8List.sublistView(zip, start, start + spakowane);
    nastepny = start + spakowane;

    final Uint8List dane = switch (metoda) {
      0 => Uint8List.fromList(spak),
      8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(spak)),
      _ => fail('Nieznana metoda $metoda: $nazwa'),
    };
    if (metoda == 0) expect(spakowane, surowe);
    expect(dane.length, surowe, reason: 'rozmiar po rozpakowaniu: $nazwa');
    expect(Crc32.of(dane), crc, reason: 'CRC danych: $nazwa');
    wynik.add(_Odczytany(nazwa, flagi, metoda, czas, data, spakowane, dane));
  }
  expect(o, koniec);
  expect(nastepny, poczatekKatalogu);
  return wynik;
}
