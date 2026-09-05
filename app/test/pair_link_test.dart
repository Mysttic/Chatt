import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/crypto.dart';
import 'package:chatt/core/identity.dart';
import 'package:chatt/core/pair_link.dart';

void main() {
  test('kod QR obchodzi całą drogę tam i z powrotem', () async {
    final klucz = await ChattCrypto.publicKeyOf(await ChattCrypto.newKeyPair());
    final ja = DeviceIdentity(
      guid: ChattCrypto.guidFromPublicKey(klucz),
      name: 'Komputer w biurze',
      welcomeMessage: '',
      tcpPort: 47780,
      publicKey: klucz,
    );

    final kod = PairLink.encode(identity: ja, address: '192.168.68.147');
    final odczytany = PairLink.decode(kod);

    expect(odczytany, isNotNull);
    expect(odczytany!.publicKey, klucz);
    expect(odczytany.host, '192.168.68.147');
    expect(odczytany.port, 47780);
    expect(odczytany.name, 'Komputer w biurze');
    expect(odczytany.guid, ja.guid,
        reason: 'identyfikatora nie ma w kodzie, liczy się z klucza');
  });

  test('śmieci i cudze kody odpadają', () {
    for (final wejscie in [
      '',
      'nie kod',
      'https://example.com',
      'chatt://cos?k=abc',
      'chatt://pair', // bez parametrów
      'chatt://pair?k=abc&h=1.2.3.4&p=47780', // klucz nie ma 32 bajtów
      'chatt://pair?k=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=&h=&p=47780',
      'chatt://pair?k=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=&h=1.2.3.4&p=0',
    ]) {
      expect(PairLink.decode(wejscie), isNull, reason: 'odrzucone: $wejscie');
    }
  });

  test('base64url bez wyrównania też się czyta', () async {
    final klucz = await ChattCrypto.publicKeyOf(await ChattCrypto.newKeyPair());
    final ja = DeviceIdentity(
      guid: ChattCrypto.guidFromPublicKey(klucz),
      name: 'Telefon',
      welcomeMessage: '',
      tcpPort: 47780,
      publicKey: klucz,
    );

    // Część czytników obcina znaki wyrównania, kod ma się wtedy nadal czytać.
    final kod = PairLink.encode(identity: ja, address: '10.0.0.5')
        .replaceAll('%3D', '');
    expect(PairLink.decode(kod)?.publicKey, klucz);
  });
}
