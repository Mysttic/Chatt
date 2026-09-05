import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/presence.dart';
import 'package:chatt/services/providers.dart';

/// Kropka obecności na liście rozmów bierze się z [presenceProvider], a ten
/// puka do każdego znanego urządzenia po kolei. Test sprawdza obie odpowiedzi
/// naraz: instancja, która naprawdę nasłuchuje, i wpis pod adresem, pod
/// którym nie ma nikogo.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('obecny odpowiada, milczący nie', () async {
    final alicja = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Alicja',
      enableDiscovery: false,
    );
    final bartek = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Bartek',
      enableDiscovery: false,
    );
    addTearDown(() async {
      await alicja.dispose();
      await bartek.dispose();
    });

    final bartekUAlicji =
        await alicja.addPeerByAddress('127.0.0.1', bartek.server.port!);
    expect(bartekUAlicji, isNotNull);

    // Urządzenie, które kiedyś było w sieci i już go nie ma. Port 1 jest
    // zastrzeżony dla systemu, więc połączenie odbija się od razu.
    await alicja.db.upsertPeer(
      guid: 'widmo',
      name: 'Widmo',
      welcomeMessage: '',
      host: '127.0.0.1',
      port: 1,
    );

    final container = ProviderContainer(
      overrides: [appServicesProvider.overrideWithValue(alicja)],
    );
    addTearDown(container.dispose);

    // Provider jest autoDispose: bez słuchacza zniknąłby przed odpowiedzią.
    final sluchacz = container.listen(presenceProvider, (_, _) {});
    addTearDown(sluchacz.close);

    final obecnosc = await container.read(presenceProvider.future);
    expect(obecnosc[bartekUAlicji!.guid], isTrue);
    expect(obecnosc['widmo'], isFalse);
  });
}
