import 'package:chatt/network/bt_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Szukanie przez radio pyta urządzenia po jednym, a każde bez Chatta
/// kosztuje kilka sekund. Od kolejności zależy, czy komputer obok pojawi się
/// po pięciu sekundach, czy po minucie.
void main() {
  BtDevice urzadzenie(String adres, int klasa, {bool leOnly = false}) =>
      BtDevice(address: adres, name: adres, majorClass: klasa, leOnly: leOnly);

  test('komputery i telefony idą przed słuchawkami i telewizorem', () {
    final kolejnosc = btProbeOrder([
      urzadzenie('sluchawki', 0x400),
      urzadzenie('bez-klasy', btClassMisc),
      urzadzenie('telefon', btClassPhone),
      urzadzenie('zegarek', 0x700),
      urzadzenie('komputer', btClassComputer),
      urzadzenie('nieopisany', btClassUncategorized),
    ]);
    expect([for (final d in kolejnosc) d.address], [
      'telefon',
      'komputer',
      'bez-klasy',
      'nieopisany',
      'sluchawki',
      'zegarek',
    ]);
  });

  test('adres widziany tylko przez BLE odpada', () {
    // Komputer rozgłasza się przez BLE losowym adresem pod tą samą nazwą.
    // RFCOMM pod taki adres czeka pełny limit strony i nigdy się nie łączy.
    final kolejnosc = btProbeOrder([
      urzadzenie('4A:E7:8D:CA:8C:18', btClassComputer, leOnly: true),
      urzadzenie('70:D8:C2:64:D9:B1', btClassComputer),
    ]);
    expect([for (final d in kolejnosc) d.address], ['70:D8:C2:64:D9:B1']);
  });
}
