import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/data/db.dart';
import 'package:chatt/services/app_services.dart';

/// Klucz rozmówcy znanego tylko z „W pobliżu”: discovery zapisuje nazwę
/// i adres, a klucz przychodzi z `/info`. Panel bezpieczeństwa ma go znać od
/// otwarcia rozmowy, bez czekania na pierwszą wiadomość, a „starszą wersję
/// bez szyfrowania” pokazywać tylko wtedy, gdy `/info` faktycznie odpowiedziało
/// bez klucza.
void main() {
  late Directory work;
  late AppServices alicja;
  late AppServices bartek;

  setUp(() async {
    work = Directory.systemTemp.createTempSync('chatt_klucz');
    Future<AppServices> start(String nazwa) => AppServices.start(
          executor: NativeDatabase.memory(),
          portOverride: 0,
          nameOverride: nazwa,
          enableDiscovery: false,
          receivedDirOverride: p.join(work.path, nazwa),
        );
    alicja = await start('Alicja');
    bartek = await start('Bartek');
  });

  tearDown(() async {
    await alicja.dispose();
    await bartek.dispose();
    work.deleteSync(recursive: true);
  });

  /// Bartek tak, jak zapisuje go discovery: nazwa i adres, bez klucza.
  Future<Peer> bartekZWPoblizu() async {
    await alicja.db.upsertPeer(
      guid: bartek.identity.guid,
      name: 'Bartek',
      welcomeMessage: '',
      host: '127.0.0.1',
      port: bartek.server.port!,
    );
    final peer = (await alicja.db.peerByGuid(bartek.identity.guid))!;
    expect(peer.publicKey, isNull);
    return peer;
  }

  test('otwarcie rozmowy przypina klucz z /info, zanim pójdzie wiadomość',
      () async {
    final peer = await bartekZWPoblizu();

    // To robi ekran rozmowy przy otwarciu.
    expect(await alicja.isPeerOnline(peer), isTrue);

    final poOtwarciu = (await alicja.db.peerByGuid(bartek.identity.guid))!;
    expect(poOtwarciu.publicKey, base64.encode(bartek.identity.publicKey));
    expect(alicja.peersWithoutKey.value, isEmpty);
    expect(await alicja.db.watchMessages(
            await alicja.openConversationWith(poOtwarciu)).first,
        isEmpty,
        reason: 'klucz jest, choć żadna wiadomość jeszcze nie poszła');
  });

  test('panel dociąga klucz, którego przy otwarciu rozmowy nie było',
      () async {
    final peer = await bartekZWPoblizu();

    await alicja.ensurePeerKey(peer);

    expect((await alicja.db.peerByGuid(bartek.identity.guid))!.publicKey,
        base64.encode(bartek.identity.publicKey));
  });

  test('przypiętego klucza odpowiedź /info nie podmienia', () async {
    final peer = await bartekZWPoblizu();
    const inny = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    await alicja.db.setPeerKey(peer.id, inny);

    // Przekazany wpis jest sprzed przypięcia, tak jak w otwartym ekranie.
    expect(await alicja.isPeerOnline(peer), isTrue);

    expect((await alicja.db.peerByGuid(bartek.identity.guid))!.publicKey,
        inny);
  });

  test('odpowiedź /info bez klucza to dopiero starsza wersja', () async {
    // Chatt sprzed szyfrowania: `/info` bez pola `key`.
    final stary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => stary.close(force: true));
    stary.listen((zapytanie) async {
      if (zapytanie.uri.path == '/info') {
        zapytanie.response.headers.contentType = ContentType.json;
        zapytanie.response.write(jsonEncode({
          'app': 'chatt',
          'guid': 'guid-stary',
          'name': 'Stary',
          'welcome': '',
          'tcpPort': stary.port,
        }));
      } else {
        zapytanie.response.statusCode = HttpStatus.notFound;
      }
      await zapytanie.response.close();
    });
    await alicja.db.upsertPeer(
      guid: 'guid-stary',
      name: 'Stary',
      welcomeMessage: '',
      host: '127.0.0.1',
      port: stary.port,
    );
    final peer = (await alicja.db.peerByGuid('guid-stary'))!;
    expect(alicja.peersWithoutKey.value, isEmpty,
        reason: 'przed kontaktem nic nie wiadomo');

    expect(await alicja.isPeerOnline(peer), isTrue);

    expect(alicja.peersWithoutKey.value, {'guid-stary'});
    expect((await alicja.db.peerByGuid('guid-stary'))!.publicKey, isNull);
  });
}
