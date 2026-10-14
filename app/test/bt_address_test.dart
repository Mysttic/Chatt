import 'package:chatt/network/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adres radia przepisuje z ekranu człowiek, więc przychodzi w każdej postaci,
/// jaka mu się wyda rozsądna. Android przyjmuje dokładnie jedną i odrzuca
/// resztę wyjątkiem, więc sprowadzenie do niej musi się odbyć u nas.
void main() {
  test('adres radia sprowadza się do jednej postaci', () {
    const oczekiwany = '70:D8:C2:64:D9:B1';
    expect(normalizeBtAddress('70:D8:C2:64:D9:B1'), oczekiwany);
    expect(normalizeBtAddress('70d8c264d9b1'), oczekiwany);
    expect(normalizeBtAddress('70-d8-c2-64-d9-b1'), oczekiwany);
    expect(normalizeBtAddress('  70:d8:c2:64:d9:b1  '), oczekiwany);
  });

  test('to, co adresem nie jest, wraca puste', () {
    expect(normalizeBtAddress(''), '');
    // Pięć bajtów: najczęstsza literówka przy przepisywaniu.
    expect(normalizeBtAddress('70:D8:C2:64:D9'), '');
    expect(normalizeBtAddress('70:D8:C2:64:D9:B1:AA'), '');
    // Litera spoza zakresu szesnastkowego wygląda jak cyfra i nią nie jest.
    expect(normalizeBtAddress('70:D8:C2:64:DO:B1'), '');
    expect(normalizeBtAddress('192.168.0.2'), '');
  });

  test('pole „skąd przyszło" rozdziela adres radia od adresu w sieci', () {
    expect(btAddressOf('bt:70:D8:C2:64:D9:B1'), '70:D8:C2:64:D9:B1');
    expect(btAddressOf('192.168.0.2'), isNull);
    expect(ipAddressOf('bt:70:D8:C2:64:D9:B1'), '');
    expect(ipAddressOf('192.168.0.2'), '192.168.0.2');
  });
}
