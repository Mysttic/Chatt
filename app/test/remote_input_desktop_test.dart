import 'dart:io';
import 'dart:ui' show Locale;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/remote_input.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/ui/remote_input_desktop.dart';

/// Okno w pamięci: pamięta, jak wygląda, i zapisuje, co z nim robiono.
class _Okno implements DesktopWindow {
  bool widoczne = false;
  bool zminimalizowane = false;
  final ruchy = <String>[];

  @override
  Future<bool> isShown() async => widoczne;

  @override
  Future<bool> isMinimized() async => zminimalizowane;

  @override
  Future<void> show() async {
    ruchy.add('show');
    widoczne = true;
    zminimalizowane = false;
  }

  @override
  Future<void> hide() async {
    ruchy.add('hide');
    widoczne = false;
  }

  @override
  Future<void> minimize() async {
    ruchy.add('minimize');
    zminimalizowane = true;
  }
}

/// Windows poza oknem aplikacji: pływający pasek ze Stopem i ikona
/// w zasobniku przez całą zgodę, a karta zgody wyciąga schowane okno i po
/// decyzji odsyła je tam, skąd przyszło.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory katalog;
  late AppServices services;
  late _Okno okno;
  late List<String> pasek;
  late List<String> zasobnik;
  late AppLocalizations? teksty;
  late RemoteInputDesktop klawiatura;

  setUp(() async {
    katalog = Directory.systemTemp.createTempSync('chatt_pulpit_');
    services = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: 'Bartek',
      enableDiscovery: false,
      receivedDirOverride: '${katalog.path}/Bartek',
    );
    okno = _Okno();
    pasek = [];
    zasobnik = [];
    teksty = lookupAppLocalizations(const Locale('en'));
    klawiatura = RemoteInputDesktop(
      services,
      texts: () => teksty,
      window: okno,
      showIndicator: ({required String text, required String stop}) async {
        pasek.add('$text|$stop');
        return true;
      },
      hideIndicator: () async {
        pasek.add('ukryj');
        return true;
      },
      setTray: ({String? tooltip, String? stopLabel}) async =>
          zasobnik.add(tooltip == null ? 'zwykly' : '$tooltip|$stopLabel'),
    )..attach();
  });

  tearDown(() async {
    klawiatura.detach();
    await services.dispose();
    katalog.deleteSync(recursive: true);
  });

  IncomingRemoteInput zgoda({String app = '', String label = ''}) =>
      IncomingRemoteInput(
        peerGuid: 'guid-alicji',
        peerName: 'Alicja',
        started: DateTime(2026, 10, 14),
        target: RemoteInputTarget(active: true, app: app, appLabel: label),
      );

  test('zgoda pokazuje pasek i ikonę, koniec zgody je chowa', () async {
    services.incomingRemoteInput.value = zgoda();
    await klawiatura.settled;
    expect(pasek, ['Typing: Alicja|Stop']);
    expect(zasobnik, ['Typing: Alicja|Stop remote keyboard']);

    // Cel z nazwą programu: pasek mówi, dokąd idzie pisanie.
    services.incomingRemoteInput.value =
        zgoda(app: 'notepad.exe', label: 'Notepad');
    await klawiatura.settled;
    expect(pasek.last, 'Typing: Alicja → Notepad|Stop');

    // Ten sam tekst drugi raz nie idzie do strony natywnej.
    services.incomingRemoteInput.value =
        zgoda(app: 'notepad.exe', label: 'Notepad');
    await klawiatura.settled;
    expect(pasek, hasLength(2));

    services.incomingRemoteInput.value = null;
    await klawiatura.settled;
    expect(pasek.last, 'ukryj');
    expect(zasobnik.last, 'zwykly');
    expect(okno.ruchy, isEmpty, reason: 'sama zgoda nie rusza okna');
  });

  test('przyłączenie daje kanałowi pole z własnego okna, odłączenie je '
      'zabiera', () {
    expect(RemoteInputChannel.ownWindowField, focusedFieldKind);
    klawiatura.detach();
    expect(RemoteInputChannel.ownWindowField, isNull);
    klawiatura.attach();
  });

  test('bez tekstów nic się nie pokazuje, a zmiana języka odświeża napisy',
      () async {
    teksty = null;
    services.incomingRemoteInput.value = zgoda();
    await klawiatura.settled;
    expect(pasek, isEmpty);

    teksty = lookupAppLocalizations(const Locale('pl'));
    klawiatura.refreshTexts();
    await klawiatura.settled;
    expect(pasek, ['Pisze: Alicja|Stop']);
    expect(zasobnik, ['Pisze: Alicja|Zatrzymaj zdalną klawiaturę']);
  });

  test('karta przy schowanym oknie wyciąga je, a po decyzji chowa', () async {
    services.pendingRemoteInput.value = const [
      PendingRemoteInput(id: 'a|1', peerGuid: 'a', peerName: 'Alicja'),
    ];
    await klawiatura.settled;
    expect(okno.ruchy, ['show']);

    services.pendingRemoteInput.value = const [];
    await klawiatura.settled;
    expect(okno.ruchy, ['show', 'hide']);
  });

  test('karta przy zminimalizowanym oknie wraca do paska zadań', () async {
    okno
      ..widoczne = true
      ..zminimalizowane = true;
    services.pendingRemoteInput.value = const [
      PendingRemoteInput(id: 'a|1', peerGuid: 'a', peerName: 'Alicja'),
    ];
    await klawiatura.settled;
    services.pendingRemoteInput.value = const [];
    await klawiatura.settled;
    expect(okno.ruchy, ['show', 'minimize']);
  });

  test('karta przy oknie na ekranie zostawia je w spokoju', () async {
    okno.widoczne = true;
    services.pendingRemoteInput.value = const [
      PendingRemoteInput(id: 'a|1', peerGuid: 'a', peerName: 'Alicja'),
    ];
    await klawiatura.settled;
    services.pendingRemoteInput.value = const [];
    await klawiatura.settled;
    expect(okno.ruchy, isEmpty);
  });
}
