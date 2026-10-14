import 'dart:io';
import 'dart:ui' show Locale;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/ui/remote_input_mobile.dart';

/// Android poza ekranami aplikacji: pasek klawiatury i stałe powiadomienie
/// przez całą zgodę, wybór klawiatury po zgodzie z karty, powiadomienie
/// o przełączeniu przy zgodzie bez karty i o karcie przy zamkniętym oknie.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory katalog;
  late AppServices services;
  late List<String> wywolania;
  late bool naWierzchu;
  late RemoteInputMobile klawiatura;

  setUp(() async {
    katalog = Directory.systemTemp.createTempSync('chatt_mobilna_');
    services = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Telefon',
      enableDiscovery: false,
      receivedDirOverride: '${katalog.path}/Telefon',
    );
    wywolania = [];
    naWierzchu = true;
    klawiatura = RemoteInputMobile(
      services,
      texts: () => lookupAppLocalizations(const Locale('pl')),
      appInFront: () => naWierzchu,
      showIndicator: ({required String text, required String stop}) async {
        wywolania.add('pasek: $text|$stop');
        return true;
      },
      hideIndicator: () async {
        wywolania.add('ukryj');
        return true;
      },
      afterAccept: () async {
        wywolania.add('po zgodzie');
        return true;
      },
      notifySwitchKeyboard: (
          {required String title, required String body}) async {
        wywolania.add('przełącz: $title|$body');
        return true;
      },
      notify: ({required String title, required String body, required int id}) async =>
          wywolania.add('karta: $title|$id'),
    )..attach();
  });

  tearDown(() async {
    klawiatura.detach();
    await services.dispose();
    katalog.deleteSync(recursive: true);
  });

  IncomingRemoteInput zgoda({String label = ''}) => IncomingRemoteInput(
        peerGuid: 'guid-pc',
        peerName: 'PC',
        started: DateTime(2026, 10, 14, 12),
        target: RemoteInputTarget(active: label.isNotEmpty, appLabel: label),
      );

  test('zgoda z karty: pasek, wybór klawiatury raz, koniec chowa pasek',
      () async {
    services.incomingRemoteInput.value = zgoda();
    await klawiatura.settled;
    expect(wywolania, ['pasek: Pisze: PC|Stop', 'po zgodzie']);

    // Kolejne paczki tej samej zgody zmieniają tylko napis.
    services.incomingRemoteInput.value = zgoda(label: 'Chrome');
    await klawiatura.settled;
    expect(wywolania.last, 'pasek: Pisze: PC → Chrome|Stop');
    expect(wywolania.where((w) => w == 'po zgodzie'), hasLength(1));

    services.incomingRemoteInput.value = null;
    await klawiatura.settled;
    expect(wywolania.last, 'ukryj');
  });

  test('zgoda bez karty przy zamkniętym oknie: powiadomienie o przełączeniu',
      () async {
    naWierzchu = false;
    services.incomingRemoteInput.value = zgoda();
    await klawiatura.settled;
    expect(wywolania, [
      'pasek: Pisze: PC|Stop',
      'przełącz: Przełącz klawiaturę na Chatt|'
          'PC pisze na tym urządzeniu. Dotknij i wybierz klawiaturę Chatt.',
    ]);
  });

  test('karta przy zamkniętym oknie daje znać raz, przy otwartym wcale',
      () async {
    naWierzchu = false;
    const prosba =
        PendingRemoteInput(id: 'pc|1', peerGuid: 'pc', peerName: 'PC');
    services.pendingRemoteInput.value = const [prosba];
    await klawiatura.settled;
    services.pendingRemoteInput.value = const [prosba];
    await klawiatura.settled;
    expect(wywolania, [
      'karta: PC chce pisać na tym urządzeniu|'
          '${RemoteInputMobile.requestNotificationId}',
    ]);

    naWierzchu = true;
    services.pendingRemoteInput.value = const [
      PendingRemoteInput(id: 'pc|2', peerGuid: 'pc', peerName: 'PC'),
    ];
    await klawiatura.settled;
    expect(wywolania, hasLength(1));
  });
}
