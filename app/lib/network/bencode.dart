import 'dart:convert';
import 'dart:typed_data';

/// Bencode, czyli zapis, którym mówi DHT BitTorrenta (BEP 3, BEP 5).
///
/// Cztery rodzaje wartości: liczba całkowita (`i42e`), napis bajtowy
/// (`4:spam`), lista (`l...e`) i słownik (`d...e`) o kluczach-napisach
/// w kolejności bajtów. Napisy bajtowe są tu zawsze [Uint8List], bo DHT
/// trzyma w nich identyfikatory, klucze i adresy, a nie tekst. Klucze
/// słowników dekodujemy do [String] w latin1, żeby dało się je porównywać
/// zwykłym `==`, a przy kodowaniu wracają do tych samych bajtów.
///
/// Dekoder jest ostrożny, bo dostaje pakiety od kogokolwiek z internetu:
/// ogranicza głębokość zagnieżdżenia, odrzuca liczby z zerami wiodącymi,
/// napisy dłuższe niż reszta wejścia i śmieci po ostatniej wartości.
class BencodeException implements Exception {
  final String message;
  const BencodeException(this.message);

  @override
  String toString() => 'BencodeException: $message';
}

/// Największe zagnieżdżenie list i słowników. Odpowiedzi DHT mają dwa,
/// trzy poziomy; więcej to albo błąd, albo próba wyczerpania stosu.
const int _maxDepth = 16;

/// Już zakodowany fragment bencode, wstawiany bez ponownego kodowania.
///
/// BEP 44 podpisuje surową postać `v`, więc przy „put" trzeba wysłać
/// dokładnie te bajty, z których policzono podpis, a nie przekodowaną
/// wartość (słownik o innej kolejności kluczy dałby inne bajty).
class BencodeRaw {
  final Uint8List bytes;
  const BencodeRaw(this.bytes);
}

/// Koduje wartość: [int], [String] (jako UTF-8), bajty ([List<int>]),
/// [BencodeRaw] (wstawiane dosłownie), [List] i [Map] o kluczach [String].
Uint8List bencode(Object value) {
  final out = BytesBuilder(copy: false);
  _encode(value, out);
  return out.takeBytes();
}

void _encode(Object value, BytesBuilder out) {
  switch (value) {
    case int liczba:
      out.add(ascii.encode('i${liczba}e'));
    case String tekst:
      _encodeBytes(utf8.encode(tekst), out);
    case BencodeRaw surowe:
      out.add(surowe.bytes);
    case Uint8List bajty:
      _encodeBytes(bajty, out);
    case List<int> bajty:
      _encodeBytes(bajty, out);
    case List lista:
      out.addByte(0x6c); // l
      for (final element in lista) {
        if (element == null) {
          throw const BencodeException('null w liście');
        }
        _encode(element as Object, out);
      }
      out.addByte(0x65); // e
    case Map mapa:
      // Klucze idą w kolejności surowych bajtów. Klucz [String] kodujemy
      // w latin1, czyli tak samo, jak dekoder go odczytał.
      final klucze = <(Uint8List, Object)>[];
      for (final entry in mapa.entries) {
        final klucz = entry.key;
        if (klucz is! String) {
          throw const BencodeException('klucz słownika musi być napisem');
        }
        final wartosc = entry.value;
        // Pole dopisane przez dekoder ([rawValueKey]) nie jest częścią
        // wiadomości i nie wraca do sieci.
        if (wartosc == null || klucz.startsWith('\u0000')) continue;
        klucze.add((Uint8List.fromList(latin1.encode(klucz)), wartosc as Object));
      }
      klucze.sort((a, b) => _compareBytes(a.$1, b.$1));
      out.addByte(0x64); // d
      for (final (klucz, wartosc) in klucze) {
        _encodeBytes(klucz, out);
        _encode(wartosc, out);
      }
      out.addByte(0x65); // e
    default:
      throw BencodeException('nie da się zakodować ${value.runtimeType}');
  }
}

void _encodeBytes(List<int> bajty, BytesBuilder out) {
  out.add(ascii.encode('${bajty.length}:'));
  out.add(bajty);
}

int _compareBytes(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final roznica = a[i] - b[i];
    if (roznica != 0) return roznica;
  }
  return a.length - b.length;
}

/// Dekoduje całe wejście. Rzuca [BencodeException], gdy coś się nie zgadza,
/// także gdy po wartości zostały bajty.
Object bdecode(List<int> data) {
  final bytes = data is Uint8List ? data : Uint8List.fromList(data);
  final reader = _Reader(bytes);
  final value = reader.value(0);
  if (reader.at != bytes.length) {
    throw const BencodeException('bajty po ostatniej wartości');
  }
  return value;
}

/// Dekoduje, a przy błędzie oddaje null. Dla pakietów z sieci, gdzie zły
/// pakiet po prostu się pomija.
Object? tryBdecode(List<int> data) {
  try {
    return bdecode(data);
  } on BencodeException {
    return null;
  }
}

/// Fragment wejścia od [start] do [end], zakodowany tak, jak przyszedł.
/// BEP 44 podpisuje surową postać `v`, więc trzeba ją umieć wyciąć bez
/// przekodowywania.
class _Reader {
  final Uint8List bytes;
  int at = 0;

  _Reader(this.bytes);

  Object value(int depth) {
    if (depth > _maxDepth) {
      throw const BencodeException('za głębokie zagnieżdżenie');
    }
    if (at >= bytes.length) throw const BencodeException('urwane wejście');
    final znak = bytes[at];
    if (znak == 0x69) return _int(); // i
    if (znak == 0x6c) return _list(depth); // l
    if (znak == 0x64) return _dict(depth); // d
    if (znak >= 0x30 && znak <= 0x39) return _bytes();
    throw BencodeException('nieznany znak 0x${znak.toRadixString(16)}');
  }

  int _int() {
    at++; // i
    final koniec = bytes.indexOf(0x65, at);
    if (koniec < 0) throw const BencodeException('liczba bez końca');
    final tekst = ascii.decode(bytes.sublist(at, koniec), allowInvalid: false);
    if (tekst.isEmpty ||
        tekst == '-0' ||
        (tekst.length > 1 && tekst.startsWith('0')) ||
        tekst.startsWith('-0') ||
        tekst.length > 20) {
      throw BencodeException('zła liczba "$tekst"');
    }
    final liczba = int.tryParse(tekst);
    if (liczba == null) throw BencodeException('zła liczba "$tekst"');
    at = koniec + 1;
    return liczba;
  }

  Uint8List _bytes() {
    final dwukropek = bytes.indexOf(0x3a, at);
    if (dwukropek < 0 || dwukropek - at > 10) {
      throw const BencodeException('napis bez długości');
    }
    final tekst = ascii.decode(bytes.sublist(at, dwukropek), allowInvalid: false);
    if (tekst.length > 1 && tekst.startsWith('0')) {
      throw const BencodeException('długość z zerem wiodącym');
    }
    final dlugosc = int.tryParse(tekst);
    if (dlugosc == null || dlugosc < 0) {
      throw const BencodeException('zła długość napisu');
    }
    final start = dwukropek + 1;
    if (start + dlugosc > bytes.length) {
      throw const BencodeException('napis dłuższy niż wejście');
    }
    at = start + dlugosc;
    return Uint8List.fromList(bytes.sublist(start, at));
  }

  List<Object> _list(int depth) {
    at++; // l
    final out = <Object>[];
    while (true) {
      if (at >= bytes.length) throw const BencodeException('lista bez końca');
      if (bytes[at] == 0x65) {
        at++;
        return out;
      }
      out.add(value(depth + 1));
    }
  }

  Map<String, Object> _dict(int depth) {
    at++; // d
    final out = <String, Object>{};
    while (true) {
      if (at >= bytes.length) {
        throw const BencodeException('słownik bez końca');
      }
      if (bytes[at] == 0x65) {
        at++;
        return out;
      }
      final klucz = _bytes();
      // Surowy fragment wartości `v` zapamiętujemy obok: podpis BEP 44
      // liczy się z bajtów, które przyszły, nie z przekodowanych.
      final start = at;
      final wartosc = value(depth + 1);
      final nazwa = latin1.decode(klucz);
      out[nazwa] = wartosc;
      if (nazwa == 'v') {
        out[rawValueKey] = Uint8List.fromList(bytes.sublist(start, at));
      }
    }
  }
}

/// Pod tym kluczem dekoder odkłada surowe bajty wartości `v` ze słownika.
/// Klucz zawiera bajt, którego nie ma w żadnym kluczu z prawdziwego DHT,
/// więc nie zderzy się z niczym, co przyszło z sieci.
const String rawValueKey = '\u0000raw:v';

/// Pomocnicze odczyty pól o znanym typie. null, gdy pola nie ma albo ma
/// inny typ niż oczekiwany.
Uint8List? bBytes(Object? map, String key) {
  if (map is! Map) return null;
  final value = map[key];
  return value is Uint8List ? value : null;
}

int? bInt(Object? map, String key) {
  if (map is! Map) return null;
  final value = map[key];
  return value is int ? value : null;
}

Map<String, Object>? bDict(Object? map, String key) {
  if (map is! Map) return null;
  final value = map[key];
  return value is Map<String, Object> ? value : null;
}

/// Napis z pola jako tekst latin1 (tak przychodzą `y` i `q` w KRPC).
String? bText(Object? map, String key) {
  final bytes = bBytes(map, key);
  return bytes == null ? null : latin1.decode(bytes);
}
