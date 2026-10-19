import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Zapis archiwum ZIP w czystym Darcie, na potrzeby eksportu danych
// (issue #50). Bez zależności z pub.dev: kompresja to `ZLibEncoder` z
// dart:io w trybie surowego DEFLATE, suma kontrolna to zwykłe CRC-32
// z tablicy.
//
// Dane płyną strumieniem prosto do pliku. Nagłówek lokalny wpisu idzie
// najpierw z zerami w miejscu CRC i rozmiarów, a po ostatnim bajcie danych
// wracamy do niego przez [RandomAccessFile] i wpisujemy prawdziwe wartości.
// Dzięki temu archiwum nie potrzebuje deskryptorów danych za wpisami
// i otwiera je każdy program, także ten, który czyta nagłówki lokalne.
//
// Bez ZIP64: rozmiary i przesunięcia mają po 32 bity, a liczba wpisów 16.
// Wpis albo archiwum, które przekroczyłoby te granice, kończy się
// [ZipLimitExceeded], a archiwum zostaje w stanie sprzed tego wpisu.
// Wywołujący pomija wtedy ten plik i pisze dalej.
//
// Wszystkie operacje są synchroniczne: zapis ma chodzić w osobnym izolacie
// (`Isolate.run`), gdzie czekanie na dysk niczego nie blokuje.

/// Największy rozmiar archiwum (i wpisu) bez ZIP64.
const int zipMaxBytes = 0xFFFFFFFF;

/// Najwięcej wpisów w archiwum bez ZIP64.
const int zipMaxEntries = 0xFFFF;

/// Która granica formatu by pękła.
enum ZipLimit {
  /// Wpis ma przed kompresją więcej bajtów, niż mieści pole rozmiaru
  /// ([zipMaxBytes]).
  entrySize,

  /// Archiwum urosłoby ponad dozwolony rozmiar.
  archiveSize,

  /// Archiwum miałoby za dużo wpisów.
  entryCount,
}

/// Wpis się nie zmieści. Archiwum zostaje takie, jak przed próbą, i można
/// dopisywać kolejne wpisy.
class ZipLimitExceeded implements Exception {
  final ZipLimit limit;

  /// Nazwa wpisu w archiwum.
  final String entry;

  const ZipLimitExceeded(this.limit, this.entry);

  @override
  String toString() => 'ZipLimitExceeded: ${limit.name} ($entry)';
}

/// Nie da się odczytać pliku źródłowego wpisu (zniknął, brak praw, błąd
/// odczytu w połowie). Archiwum zostaje takie, jak przed próbą.
class ZipSourceException implements Exception {
  /// Ścieżka pliku źródłowego.
  final String path;
  final Object error;

  const ZipSourceException(this.path, this.error);

  @override
  String toString() => 'ZipSourceException: $path: $error';
}

/// CRC-32 (wielomian 0xEDB88320, jak w ZIP i gzip), liczone kawałkami.
class Crc32 {
  static final Uint32List _tabela = _zbudujTabele();

  static Uint32List _zbudujTabele() {
    final tabela = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      }
      tabela[n] = c;
    }
    return tabela;
  }

  int _stan = 0xFFFFFFFF;

  /// Dolicza kolejne bajty.
  void add(List<int> data) {
    final tabela = _tabela;
    var c = _stan;
    for (var i = 0; i < data.length; i++) {
      c = tabela[(c ^ data[i]) & 0xFF] ^ (c >>> 8);
    }
    _stan = c;
  }

  /// Suma kontrolna wszystkiego, co przeszło przez [add].
  int get value => (_stan ^ 0xFFFFFFFF) & 0xFFFFFFFF;

  /// Suma kontrolna jednego bloku bajtów.
  static int of(List<int> data) => (Crc32()..add(data)).value;
}

/// Wpis już zapisany: to, czego potrzebuje katalog centralny.
class _Wpis {
  final List<int> nazwa;
  final int metoda;
  final int czas;
  final int data;
  final int crc;
  final int spakowane;
  final int surowe;
  final int przesuniecie;

  const _Wpis(this.nazwa, this.metoda, this.czas, this.data, this.crc,
      this.spakowane, this.surowe, this.przesuniecie);
}

/// Ujście dla kompresora: każdy kawałek wyjścia idzie od razu do pliku.
class _Ujscie implements Sink<List<int>> {
  final void Function(List<int> chunk) _pisz;

  _Ujscie(this._pisz);

  @override
  void add(List<int> data) => _pisz(data);

  @override
  void close() {}
}

/// Archiwum ZIP zapisywane strumieniem do pliku pod [path].
///
/// Teksty idą przez DEFLATE ([addText], [addBytes]). Pliki z dysku
/// ([addFile]) idą wprost: zdjęcia, filmy i archiwa są już skompresowane
/// i ponowna kompresja wydłużyłaby eksport bez zysku. Nazwy wpisów są w UTF-8
/// z ustawionym bitem 11, więc polskie znaki przechodzą bez strat.
///
/// [maxBytes], [maxEntryBytes] i [maxEntries] to granice formatu; testy
/// podają mniejsze.
class ZipWriter {
  ZipWriter(
    this.path, {
    this.maxBytes = zipMaxBytes,
    this.maxEntryBytes = zipMaxBytes,
    this.maxEntries = zipMaxEntries,
  })  : assert(maxBytes <= zipMaxBytes &&
            maxEntryBytes <= zipMaxBytes &&
            maxEntries <= zipMaxEntries),
        _wyjscie = File(path).openSync(mode: FileMode.write);

  /// Gdzie leży archiwum.
  final String path;

  /// Największy rozmiar całego archiwum, z katalogiem centralnym.
  final int maxBytes;

  /// Największy rozmiar jednego wpisu przed kompresją.
  final int maxEntryBytes;

  /// Najwięcej wpisów w archiwum.
  final int maxEntries;

  final RandomAccessFile _wyjscie;
  final List<_Wpis> _wpisy = [];

  /// Nazwy już użyte, małymi literami: rozpakowanie na Windowsie nie
  /// odróżnia wielkości liter, więc „A.txt" i „a.txt" nadpisałyby się.
  final Set<String> _nazwy = {};

  /// Koniec danych ostatniego wpisu, czyli miejsce następnego.
  int _pozycja = 0;

  /// Rozmiar katalogu centralnego dla wpisów już zapisanych.
  int _katalog = 0;
  bool _zamkniete = false;
  bool _zepsute = false;

  static const _naglowekLokalny = 30;
  static const _naglowekCentralny = 46;
  static const _koniecKatalogu = 22;
  static const _bitUtf8 = 0x0800;

  /// Ile bajtów zajmuje dotąd archiwum (bez katalogu centralnego).
  int get length => _pozycja;

  /// Ile wpisów jest już w archiwum.
  int get entryCount => _wpisy.length;

  /// Górna granica tego, ile wpis [name] o [length] bajtach doda do
  /// archiwum: nagłówek lokalny, dane i rekord katalogu centralnego.
  /// Przy kompresji liczy najgorszy przypadek, w którym DEFLATE niczego nie
  /// zmniejszy. Do rezerwowania miejsca na wpisy, które przyjdą później.
  static int entryBound(String name, int length, {required bool compress}) {
    final nazwa = utf8.encode(name).length;
    final dane = compress ? length + (length >> 10) + 64 : length;
    return _naglowekLokalny + _naglowekCentralny + 2 * nazwa + dane;
  }

  /// Wpis tekstowy, w UTF-8, skompresowany.
  void addText(
    String name,
    String text, {
    DateTime? modified,
    int reserveBytes = 0,
    int reserveEntries = 0,
  }) =>
      addBytes(name, utf8.encode(text),
          modified: modified,
          reserveBytes: reserveBytes,
          reserveEntries: reserveEntries);

  /// Wpis z bajtów z pamięci. [compress] wybiera DEFLATE albo zapis wprost.
  ///
  /// [reserveBytes] i [reserveEntries] trzymają miejsce na to, co ma przyjść
  /// po tym wpisie: wpis, po którym tego miejsca by zabrakło, nie wchodzi.
  void addBytes(
    String name,
    List<int> data, {
    bool compress = true,
    DateTime? modified,
    int reserveBytes = 0,
    int reserveEntries = 0,
  }) {
    _zapiszWpis(
      name,
      compress: compress,
      modified: modified ?? DateTime.now(),
      reserveBytes: reserveBytes,
      reserveEntries: reserveEntries,
      expected: compress ? null : data.length,
      zrodlo: (podaj) {
        const krok = 1 << 16;
        final bajty = data is Uint8List ? data : Uint8List.fromList(data);
        for (var i = 0; i < bajty.length; i += krok) {
          final koniec = i + krok < bajty.length ? i + krok : bajty.length;
          podaj(Uint8List.sublistView(bajty, i, koniec));
        }
      },
    );
  }

  /// Wpis z pliku [sourcePath], bez kompresji, czytany kawałkami. Data
  /// wpisu to data modyfikacji pliku, chyba że podano [modified].
  ///
  /// Plik większy, niż się zmieści, odpada od razu, zanim cokolwiek trafi
  /// do archiwum. Błąd odczytu kończy się [ZipSourceException].
  void addFile(
    String name,
    String sourcePath, {
    DateTime? modified,
    int reserveBytes = 0,
    int reserveEntries = 0,
  }) {
    _sprawdzStan();
    final RandomAccessFile zrodlo;
    final int rozmiar;
    final DateTime kiedy;
    try {
      zrodlo = File(sourcePath).openSync();
    } on FileSystemException catch (blad) {
      throw ZipSourceException(sourcePath, blad);
    }
    try {
      try {
        rozmiar = zrodlo.lengthSync();
        kiedy = modified ?? File(sourcePath).lastModifiedSync();
      } on FileSystemException catch (blad) {
        throw ZipSourceException(sourcePath, blad);
      }
      _zapiszWpis(
        name,
        compress: false,
        modified: kiedy,
        reserveBytes: reserveBytes,
        reserveEntries: reserveEntries,
        expected: rozmiar,
        zrodlo: (podaj) {
          final bufor = Uint8List(1 << 20);
          while (true) {
            final int ile;
            try {
              ile = zrodlo.readIntoSync(bufor);
            } on FileSystemException catch (blad) {
              throw ZipSourceException(sourcePath, blad);
            }
            if (ile == 0) break;
            podaj(Uint8List.sublistView(bufor, 0, ile));
          }
        },
      );
    } finally {
      zrodlo.closeSync();
    }
  }

  /// Dopisuje katalog centralny i koniec archiwum, zamyka plik. Zwraca
  /// rozmiar archiwum w bajtach.
  int close() {
    _sprawdzStan();
    final katalog = BytesBuilder(copy: false);
    for (final wpis in _wpisy) {
      katalog.add(_rekordCentralny(wpis));
    }
    final rozmiarKatalogu = katalog.length;
    final koniec = ByteData(_koniecKatalogu)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(4, 0, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, _wpisy.length, Endian.little)
      ..setUint16(10, _wpisy.length, Endian.little)
      ..setUint32(12, rozmiarKatalogu, Endian.little)
      ..setUint32(16, _pozycja, Endian.little)
      ..setUint16(20, 0, Endian.little);
    _wyjscie
      ..setPositionSync(_pozycja)
      ..writeFromSync(katalog.takeBytes())
      ..writeFromSync(koniec.buffer.asUint8List())
      ..flushSync()
      ..closeSync();
    _zamkniete = true;
    return _pozycja + rozmiarKatalogu + _koniecKatalogu;
  }

  /// Porzuca archiwum: zamyka plik i go kasuje. Nic nie rzuca.
  void abort() {
    if (_zamkniete) return;
    _zamkniete = true;
    try {
      _wyjscie.closeSync();
    } catch (_) {
      // Plik już zamknięty albo dysk odpadł: i tak go kasujemy.
    }
    try {
      File(path).deleteSync();
    } catch (_) {
      // Nie ma czego kasować.
    }
  }

  void _sprawdzStan() {
    if (_zamkniete) throw StateError('ZipWriter is closed');
    if (_zepsute) {
      throw StateError('ZipWriter could not roll back a failed entry');
    }
  }

  /// Wspólna droga każdego wpisu. [zrodlo] podaje kolejne kawałki danych
  /// przed kompresją; [expected] to ich rozmiar, gdy jest znany z góry
  /// (wtedy za duży wpis odpada przed zapisem pierwszego bajtu).
  void _zapiszWpis(
    String name, {
    required bool compress,
    required DateTime modified,
    required int reserveBytes,
    required int reserveEntries,
    required int? expected,
    required void Function(void Function(List<int> chunk) podaj) zrodlo,
  }) {
    _sprawdzStan();
    final nazwa = utf8.encode(name);
    _sprawdzNazwe(name, nazwa.length);
    if (_wpisy.length + 1 + reserveEntries > maxEntries) {
      throw ZipLimitExceeded(ZipLimit.entryCount, name);
    }
    if (expected != null && expected > maxEntryBytes) {
      throw ZipLimitExceeded(ZipLimit.entrySize, name);
    }

    final poczatek = _pozycja;
    final katalogPo = _katalog + _naglowekCentralny + nazwa.length;
    void pilnuj(int koniecDanych) {
      if (koniecDanych + katalogPo + _koniecKatalogu + reserveBytes >
          maxBytes) {
        throw ZipLimitExceeded(ZipLimit.archiveSize, name);
      }
    }

    final naglowek = _naglowekLokalny + nazwa.length;
    pilnuj(poczatek + naglowek + (expected ?? 0));

    final (czas, data) = _dosDateTime(modified);
    final metoda = compress ? 8 : 0;
    final crc = Crc32();
    var surowe = 0;
    var spakowane = 0;
    var porzucone = false;
    var skompresowane = false;

    void pisz(List<int> kawalek) {
      if (porzucone || kawalek.isEmpty) return;
      pilnuj(_pozycja + kawalek.length);
      _wyjscie.writeFromSync(kawalek);
      _pozycja += kawalek.length;
      spakowane += kawalek.length;
    }

    final kompresor = compress
        ? ZLibEncoder(raw: true).startChunkedConversion(_Ujscie(pisz))
        : null;

    try {
      _wyjscie
        ..setPositionSync(poczatek)
        ..writeFromSync(_rekordLokalny(nazwa, metoda, czas, data));
      _pozycja = poczatek + naglowek;
      zrodlo((kawalek) {
        surowe += kawalek.length;
        if (surowe > maxEntryBytes) {
          throw ZipLimitExceeded(ZipLimit.entrySize, name);
        }
        crc.add(kawalek);
        if (kompresor != null) {
          kompresor.add(kawalek);
        } else {
          pisz(kawalek);
        }
      });
      skompresowane = true;
      kompresor?.close();

      // Prawdziwe CRC i rozmiary do nagłówka lokalnego.
      final poprawka = ByteData(12)
        ..setUint32(0, crc.value, Endian.little)
        ..setUint32(4, spakowane, Endian.little)
        ..setUint32(8, surowe, Endian.little);
      _wyjscie
        ..setPositionSync(poczatek + 14)
        ..writeFromSync(poprawka.buffer.asUint8List())
        ..setPositionSync(_pozycja);
    } catch (_) {
      porzucone = true;
      if (!skompresowane) {
        try {
          // Zwalnia natywny stan kompresora; resztki wyjścia trafiają
          // w próżnię, bo wpis i tak znika.
          kompresor?.close();
        } catch (_) {
          // Kompresor po błędzie w połowie nie ma już czego oddać.
        }
      }
      _cofnij(poczatek);
      rethrow;
    }

    _wpisy.add(_Wpis(
        nazwa, metoda, czas, data, crc.value, spakowane, surowe, poczatek));
    _nazwy.add(name.toLowerCase());
    _katalog = katalogPo;
  }

  /// Archiwum wraca do stanu sprzed nieudanego wpisu.
  void _cofnij(int poczatek) {
    try {
      _wyjscie
        ..truncateSync(poczatek)
        ..setPositionSync(poczatek);
      _pozycja = poczatek;
    } catch (_) {
      // Plik nie daje się przyciąć: dalsze wpisy trafiłyby za śmieci.
      _zepsute = true;
    }
  }

  void _sprawdzNazwe(String name, int dlugosc) {
    final czesci = name.split('/');
    if (name.isEmpty ||
        dlugosc > 0xFFFF ||
        name.contains('\\') ||
        name.startsWith('/') ||
        czesci.any((c) => c.isEmpty || c == '.' || c == '..')) {
      throw ArgumentError.value(name, 'name', 'Invalid ZIP entry name');
    }
    if (_nazwy.contains(name.toLowerCase())) {
      throw ArgumentError.value(name, 'name', 'Duplicate ZIP entry name');
    }
  }

  static Uint8List _rekordLokalny(
      List<int> nazwa, int metoda, int czas, int data) {
    final rekord = ByteData(_naglowekLokalny + nazwa.length)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, metoda == 8 ? 20 : 10, Endian.little)
      ..setUint16(6, _bitUtf8, Endian.little)
      ..setUint16(8, metoda, Endian.little)
      ..setUint16(10, czas, Endian.little)
      ..setUint16(12, data, Endian.little)
      // CRC i oba rozmiary (14..25) dopisuje poprawka po danych.
      ..setUint16(26, nazwa.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    final bajty = rekord.buffer.asUint8List();
    bajty.setRange(_naglowekLokalny, bajty.length, nazwa);
    return bajty;
  }

  static Uint8List _rekordCentralny(_Wpis wpis) {
    final rekord = ByteData(_naglowekCentralny + wpis.nazwa.length)
      ..setUint32(0, 0x02014b50, Endian.little)
      // Utworzone przez: wersja 2.0, system MS-DOS (atrybuty bez praw
      // uniksowych, rozpakowanie nadaje domyślne).
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, wpis.metoda == 8 ? 20 : 10, Endian.little)
      ..setUint16(8, _bitUtf8, Endian.little)
      ..setUint16(10, wpis.metoda, Endian.little)
      ..setUint16(12, wpis.czas, Endian.little)
      ..setUint16(14, wpis.data, Endian.little)
      ..setUint32(16, wpis.crc, Endian.little)
      ..setUint32(20, wpis.spakowane, Endian.little)
      ..setUint32(24, wpis.surowe, Endian.little)
      ..setUint16(28, wpis.nazwa.length, Endian.little)
      ..setUint16(30, 0, Endian.little)
      ..setUint16(32, 0, Endian.little)
      ..setUint16(34, 0, Endian.little)
      ..setUint16(36, 0, Endian.little)
      ..setUint32(38, 0, Endian.little)
      ..setUint32(42, wpis.przesuniecie, Endian.little);
    final bajty = rekord.buffer.asUint8List();
    bajty.setRange(_naglowekCentralny, bajty.length, wpis.nazwa);
    return bajty;
  }

  /// Czas lokalny w zapisie MS-DOS: dwusekundowa dokładność, lata od 1980
  /// do 2107. Daty spoza zakresu przycinamy do jego brzegów.
  static (int, int) _dosDateTime(DateTime kiedy) {
    final t = kiedy.toLocal();
    if (t.year < 1980) return (0, (1 << 5) | 1);
    if (t.year > 2107) {
      return ((23 << 11) | (59 << 5) | 29, (127 << 9) | (12 << 5) | 31);
    }
    final czas = (t.hour << 11) | (t.minute << 5) | (t.second >> 1);
    final data = ((t.year - 1980) << 9) | (t.month << 5) | t.day;
    return (czas, data);
  }
}
