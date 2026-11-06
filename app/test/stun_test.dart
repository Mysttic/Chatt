import 'dart:io';
import 'dart:typed_data';

import 'package:chatt/network/stun.dart';
import 'package:flutter_test/flutter_test.dart';

/// STUN mówi urządzeniu, pod jakim adresem widzi je świat. Wektor z RFC 5769
/// pilnuje, że odczyt XOR-MAPPED-ADDRESS jest dokładnie zgodny ze standardem;
/// reszta testów sprawdza ocenę rodzaju NAT-u.
void main() {
  // RFC 5769, 2.2 "Sample IPv4 Response".
  final respV4 = Uint8List.fromList(<int>[
    0x01, 0x01, 0x00, 0x3c,
    0x21, 0x12, 0xa4, 0x42,
    0xb7, 0xe7, 0xa7, 0x01,
    0xbc, 0x34, 0xd6, 0x86,
    0xfa, 0x87, 0xdf, 0xae,
    0x80, 0x22, 0x00, 0x0b,
    0x74, 0x65, 0x73, 0x74,
    0x20, 0x76, 0x65, 0x63,
    0x74, 0x6f, 0x72, 0x20,
    0x00, 0x20, 0x00, 0x08,
    0x00, 0x01, 0xa1, 0x47,
    0xe1, 0x12, 0xa6, 0x43,
    0x00, 0x08, 0x00, 0x14,
    0x2b, 0x91, 0xf5, 0x99,
    0xfd, 0x9e, 0x90, 0xc3,
    0x8c, 0x74, 0x89, 0xf9,
    0x2a, 0xf9, 0xba, 0x53,
    0xf0, 0x6b, 0xe7, 0xd7,
    0x80, 0x28, 0x00, 0x04,
    0xc0, 0x7d, 0x4c, 0x96,
  ]);

  test('wektor RFC 5769: XOR-MAPPED-ADDRESS to 192.0.2.1:32853', () {
    expect(looksLikeStun(respV4), isTrue);
    final mapping = parseStunBindingResponse(respV4);
    expect(mapping, isNotNull);
    expect(mapping!.address.address, '192.0.2.1');
    expect(mapping.port, 32853);
  });

  test('numer transakcji z pakietu', () {
    final tid = stunTransactionOf(respV4);
    expect(tid, isNotNull);
    expect(
        tid!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'b7e7a701bc34d686fa87dfae');
  });

  test('pytanie Binding ma poprawny kształt', () {
    final tid = newStunTransaction();
    final req = stunBindingRequest(tid);
    expect(req.length, 20);
    expect(looksLikeStun(req), isTrue);
    final view = ByteData.sublistView(req);
    expect(view.getUint16(0), 0x0001); // Binding Request
    expect(view.getUint16(2), 0); // bez atrybutów
    expect(view.getUint32(4), stunMagicCookie);
    expect(stunTransactionOf(req), tid);
  });

  test('nie-STUN odpada', () {
    expect(looksLikeStun(Uint8List.fromList([0, 1, 2, 3])), isFalse);
    expect(parseStunBindingResponse(Uint8List.fromList(List.filled(20, 0))),
        isNull);
  });

  group('ocena NAT-u', () {
    final a = StunMapping(InternetAddress('203.0.113.5'), 1111);
    final a2 = StunMapping(InternetAddress('203.0.113.5'), 1111);
    final b = StunMapping(InternetAddress('203.0.113.5'), 2222);

    test('ten sam adres z dwóch serwerów = niezależny od celu', () {
      expect(classifyNat(a, a2), NatMapping.endpointIndependent);
    });
    test('różne porty = zależny od celu (symetryczny)', () {
      expect(classifyNat(a, b), NatMapping.endpointDependent);
    });
    test('jedna odpowiedź = nieznany', () {
      expect(classifyNat(a, null), NatMapping.unknown);
    });
    test('adres publiczny = adres lokalny → brak NAT', () {
      expect(
          classifyNat(a, b, localAddresses: ['203.0.113.5']), NatMapping.none);
    });
  });
}
