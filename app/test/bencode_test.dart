import 'dart:convert';
import 'dart:typed_data';

import 'package:chatt/network/bencode.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bencode to zapis, którym mówi DHT. Testy pilnują dwóch rzeczy: że okrążenie
/// koduj→dekoduj nie gubi danych, i że dekoder nie daje się wywrócić pakietem
/// z sieci.
void main() {
  String enc(Object v) => latin1.decode(bencode(v));

  group('kodowanie', () {
    test('przykłady z BEP 5', () {
      expect(enc(<String, Object>{'a': 'spam'}), 'd1:a4:spame');
      expect(enc(42), 'i42e');
      expect(enc(0), 'i0e');
      expect(enc(-7), 'i-7e');
      expect(enc('spam'), '4:spam');
      expect(enc(<Object>[1, 2, 3]), 'li1ei2ei3ee');
    });

    test('klucze słownika idą w kolejności bajtów', () {
      expect(enc(<String, Object>{'b': 1, 'a': 2, 'c': 3}),
          'd1:ai2e1:bi1e1:ci3ee');
    });

    test('pakiet ping z BEP 5 w całości', () {
      final ping = <String, Object>{
        'a': <String, Object>{'id': 'abcdefghij0123456789'},
        'q': 'ping',
        't': 'aa',
        'y': 'q',
      };
      expect(enc(ping), 'd1:ad2:id20:abcdefghij0123456789e1:q4:ping1:t2:aa1:y1:qe');
    });

    test('BencodeRaw wchodzi dosłownie', () {
      final raw = BencodeRaw(Uint8List.fromList(latin1.encode('i5e')));
      expect(enc(<String, Object>{'v': raw}), 'd1:vi5ee');
    });
  });

  group('dekodowanie', () {
    test('okrążenie zachowuje strukturę', () {
      final value = <String, Object>{
        'str': 'tekst',
        'num': 123,
        'list': <Object>[1, 'dwa', <Object>[]],
        'nested': <String, Object>{'x': 1},
      };
      final decoded = bdecode(bencode(value)) as Map;
      expect(latin1.decode(decoded['str'] as Uint8List), 'tekst');
      expect(decoded['num'], 123);
      expect((decoded['list'] as List).length, 3);
      expect((decoded['nested'] as Map)['x'], 1);
    });

    test('surowe bajty v wyciągane obok wartości', () {
      // Wartość v jako słownik; dekoder odkłada jego surową postać.
      final bytes = bencode(<String, Object>{
        'v': <String, Object>{'ip': '1.2.3.4', 'p': 47780},
      });
      final decoded = bdecode(bytes) as Map;
      final raw = decoded[rawValueKey] as Uint8List;
      // Surowe v samo w sobie jest poprawnym bencode słownika.
      final vSam = bdecode(raw) as Map;
      expect(latin1.decode(vSam['ip'] as Uint8List), '1.2.3.4');
    });

    test('odrzuca śmieci', () {
      for (final zly in <List<int>>[
        latin1.encode('i e'),
        latin1.encode('i00e'),
        latin1.encode('i-0e'),
        latin1.encode('5:abc'), // za krótkie
        latin1.encode('d1:a'), // słownik bez końca
        latin1.encode('li1e'), // lista bez końca
        latin1.encode('i1ee'), // śmieci po wartości
        latin1.encode('01:a'), // długość z zerem wiodącym
      ]) {
        expect(tryBdecode(zly), isNull, reason: latin1.decode(zly));
      }
    });

    test('za głębokie zagnieżdżenie odpada', () {
      final glebokie = StringBuffer();
      for (var i = 0; i < 40; i++) {
        glebokie.write('l');
      }
      expect(tryBdecode(latin1.encode(glebokie.toString())), isNull);
    });

    test('pomocnicze odczyty pól', () {
      final decoded = bdecode(bencode(<String, Object>{
        'y': 'r',
        'seq': 5,
        'id': Uint8List.fromList([1, 2, 3]),
      }));
      expect(bText(decoded, 'y'), 'r');
      expect(bInt(decoded, 'seq'), 5);
      expect(bBytes(decoded, 'id'), [1, 2, 3]);
      expect(bText(decoded, 'brak'), isNull);
    });
  });
}
