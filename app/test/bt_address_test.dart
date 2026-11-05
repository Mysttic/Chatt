import 'package:chatt/network/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adres radia przepisuje z ekranu człowiek, więc przychodzi w każdej postaci,
/// jaka mu się wyda rozsądna. Android przyjmuje dokładnie jedną i odrzuca
/// resztę wyjątkiem, więc sprowadzenie do niej musi się odbyć u nas.
void main() {
  test('adres radia sprowadza się do jednej postaci', () {
    const oczekiwany = '12:34:56:78:9A:BC';
    expect(normalizeBtAddress('12:34:56:78:9A:BC'), oczekiwany);
    expect(normalizeBtAddress('123456789abc'), oczekiwany);
    expect(normalizeBtAddress('12-34-56-78-9a-bc'), oczekiwany);
    expect(normalizeBtAddress('  12:34:56:78:9a:bc  '), oczekiwany);
  });

  test('to, co adresem nie jest, wraca puste', () {
    expect(normalizeBtAddress(''), '');
    // Pięć bajtów: najczęstsza literówka przy przepisywaniu.
    expect(normalizeBtAddress('12:34:56:78:9A'), '');
    expect(normalizeBtAddress('12:34:56:78:9A:BC:AA'), '');
    // Litera spoza zakresu szesnastkowego wygląda jak cyfra i nią nie jest.
    expect(normalizeBtAddress('12:34:56:78:9A:BO'), '');
    expect(normalizeBtAddress('192.168.0.2'), '');
  });

  test('pole „skąd przyszło" rozdziela adres radia od adresu w sieci', () {
    expect(btAddressOf('bt:12:34:56:78:9A:BC'), '12:34:56:78:9A:BC');
    expect(btAddressOf('192.168.0.2'), isNull);
    expect(ipAddressOf('bt:12:34:56:78:9A:BC'), '');
    expect(ipAddressOf('192.168.0.2'), '192.168.0.2');
  });
}
