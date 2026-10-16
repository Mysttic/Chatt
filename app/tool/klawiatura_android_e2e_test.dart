// Klawiatura z PC na PRAWDZIWYM Androidzie: ten proces jest nadawcą (jak PC),
// a odbiorcą jest aplikacja na emulatorze albo telefonie, z klawiaturą Chatt.
//
// Tunele adb jak w `tool/android_e2e_test.dart`:
//   adb forward tcp:47781 tcp:47780   host  -> aplikacja na urządzeniu
//   adb reverse tcp:47790 tcp:47790   urządzenie -> instancja hosta
//
// Przygotowanie (raz, ręcznie albo tak jak w przewodniku): w aplikacji na
// urządzeniu Ustawienia → Dodatki → „Klawiatura z PC" i „Pozwól pisać na tym
// urządzeniu" włączone. Klawiaturę Chatt w systemie test włącza sam przez adb
// (`ime enable`), a bieżącą wybiera w systemowym oknie wyboru, tak jak
// użytkownik. Test paruje się z aplikacją kodem, za każdym razem od nowa.
//
//   flutter test tool/klawiatura_android_e2e_test.dart
//
// Co test robi na urządzeniu, krok po kroku:
//   1. prośba przed parowaniem: odmowa bez karty;
//   2. parowanie kodem (stuknięcie „They match"/„Zgadza się");
//   3. prośba, stuknięcie „Accept"/„Akceptuj" na karcie, w oknie wyboru
//      klawiatury „Chatt keyboard"/„Klawiatura Chatt"; aplikacja schodzi na dół;
//   4. formularz nowego kontaktu: tekst z polskimi znakami, Backspace, akcja
//      pola (Dalej) przenosi fokus do nazwiska;
//   5. (emulator) hasło blokady: klawiatura Chatt oddaje miejsce, po
//      odblokowaniu powiadomienie „Switch the keyboard to Chatt" przywraca ją;
//   6. Stop na pasku klawiatury: nadawca dostaje no_grant, wraca poprzednia
//      klawiatura;
//   7. nowa sesja i pole wiadomości w samym Chatcie: tekst trafia i tam (bez
//      Entera, więc nic nie wychodzi), po czym znika z pola.
//
// Zmienne: ADB, CHATT_DEVICE (patrz `tool/uiautomator.dart`), CHATT_PROXY_PORT,
// CHATT_SHOTS=1 (zrzuty do docs/screenshots/android/: karta dodatku
// z „Turn on the Chatt keyboard", oba systemowe ostrzeżenia przy włączaniu
// klawiatury, karta zgody, okno wyboru klawiatury, pasek klawiatury Chatt
// przy pisaniu, powiadomienie „Switch the keyboard to Chatt" i pasek „Pisze"
// w aplikacji; nadawca nazywa się wtedy „Office PC". Klawiaturę Chatt
// skrypt włącza wtedy tak jak użytkownik, w ustawieniach systemu. Bez tej
// zmiennej przebieg niczego w repozytorium nie zmienia).
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';

import 'uiautomator.dart';

const int hostPort = 47790;
final int deviceProxyPort =
    int.tryParse(Platform.environment['CHATT_PROXY_PORT'] ?? '') ?? 47781;

const String appPackage = 'com.mysttic.chatt';
const String imeId = '$appPackage/.ChattInputMethod';

/// Zrzuty do dokumentacji (CHATT_SHOTS=1).
final bool zrzuty = Platform.environment['CHATT_SHOTS'] == '1';

/// Nadawca na zrzutach ma nazwę po angielsku, jak reszta zrzutów Androida.
final String nazwaHosta = zrzuty ? 'Office PC' : 'Komputer PC';

Future<String> biezacaKlawiatura() async =>
    ((await adb(['shell', 'settings', 'get', 'secure', 'default_input_method']))
            .stdout as String)
        .trim();

/// Stan nadawcy do komunikatów błędów.
String Function() stanNadawcy = () => '';

Future<void> czekaj(Future<bool> Function() warunek, String co,
    {Duration ile = const Duration(seconds: 20)}) async {
  final koniec = DateTime.now().add(ile);
  while (!await warunek()) {
    if (DateTime.now().isAfter(koniec)) {
      fail('nie doczekano: $co. Nadawca: ${stanNadawcy()}. '
          'Na ekranie: ${await widocznaTresc()}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory work;
  late AppServices host;
  late Peer telefon;

  /// Telefon za tunelem: host zapisuje sobie z powrotem port tunelu.
  Future<Peer> przypnijTunel() async {
    await host.db.upsertPeer(
      guid: telefon.guid,
      name: telefon.name,
      welcomeMessage: telefon.welcomeMessage,
      host: '127.0.0.1',
      port: deviceProxyPort,
    );
    return (await host.db.peerByGuid(telefon.guid))!;
  }

  /// Zostawia w zrzucie [nazwa] pas od [gora] do [dol] pikseli, na całą
  /// szerokość. Tylko na Windows (System.Drawing); gdzie indziej zrzut
  /// zostaje cały.
  Future<void> przytnijZrzut(String nazwa, int gora, int dol) async {
    if (!zrzuty || !Platform.isWindows) return;
    final plik = p.absolute(
        p.join('..', 'docs', 'screenshots', 'android', '$nazwa.png'));
    final skrypt = 'Add-Type -AssemblyName System.Drawing; '
        '\$b = [System.Drawing.Bitmap]::FromFile("$plik"); '
        '\$w = \$b.Clone((New-Object System.Drawing.Rectangle(0, $gora, '
        '\$b.Width, ${dol - gora})), \$b.PixelFormat); '
        '\$b.Dispose(); '
        '\$w.Save("$plik", [System.Drawing.Imaging.ImageFormat]::Png); '
        '\$w.Dispose()';
    await Process.run('powershell', ['-NoProfile', '-Command', skrypt]);
  }

  /// Zrzut do dokumentacji; powstaje wyłącznie przy CHATT_SHOTS=1.
  Future<void> zrzutDoDokumentacji(String nazwa) async {
    if (Platform.environment['CHATT_SHOTS'] != '1') return;
    await screenshot(
        p.join('..', 'docs', 'screenshots', 'android', '$nazwa.png'));
  }

  /// Prośba o sesję ze zgodą na karcie i wyborem klawiatury Chatt, gdy nie
  /// jest bieżąca. [zrzut] to nazwa zrzutu karty do dokumentacji.
  Future<void> sesja({String? zrzut, String? zrzutWyboru}) async {
    var start = host.startRemoteInput(telefon);
    // Aplikacja z czystymi danymi (nowa instalacja, emulator po starcie
    // z migawki) ma dodatek wyłączony: wtedy włącza go sam test.
    final odmowa = await czekajNaKarteAlbo(start, ['Accept', 'Akceptuj'],
        pakiet: appPackage);
    if (odmowa == RemoteInputStart.notEnabled) {
      await wlaczDodatekKlawiatury(appPackage);
      await adb([
        'shell', 'monkey', '-p', appPackage, '-c',
        'android.intent.category.LAUNCHER', '1',
      ]);
      start = host.startRemoteInput(telefon);
    }
    if (zrzut != null) {
      await findWidget('Accept') ??
          await findWidget('Akceptuj', timeout: const Duration(seconds: 1));
      await zrzutDoDokumentacji(zrzut);
    }
    await stuknijEtykiete(['Accept', 'Akceptuj'], azZniknie: true);
    expect(await start, RemoteInputStart.accepted);
    if (await biezacaKlawiatura() != imeId) {
      if (zrzutWyboru != null) {
        await findWidget('Chatt keyboard',
            timeout: const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await zrzutDoDokumentacji(zrzutWyboru);
      }
      // Okno wyboru ma nagłówek z nazwą klawiatury i pod nim wiersz z jej
      // podtypem o tej samej nazwie; stuknąć trzeba w wiersz, czyli niższy.
      await stuknijEtykiete(['Chatt keyboard', 'Klawiatura Chatt'],
          ostatni: true);
    }
    await czekaj(() async => await biezacaKlawiatura() == imeId,
        'klawiatura Chatt bieżącą');
  }

  setUpAll(() async {
    work = Directory.systemTemp.createTempSync('chatt_klawiatura_android');
    final forward = await adb(['forward', 'tcp:$deviceProxyPort', 'tcp:47780']);
    expect(forward.exitCode, 0, reason: '${forward.stderr}');
    final reverse = await adb(['reverse', 'tcp:$hostPort', 'tcp:$hostPort']);
    expect(reverse.exitCode, 0, reason: '${reverse.stderr}');
    // Klawiatura Chatt włączona w systemie (komponent włącza dodatek). Adb
    // robi to bez okienka z ostrzeżeniem; w przewodniku robi to użytkownik.
    // Przy zrzutach odwrotnie: klawiatura wyłączona, a włącza ją pierwszy
    // krok, przez ustawienia systemu, z oboma ostrzeżeniami na zrzutach.
    await adb(['shell', 'ime', zrzuty ? 'disable' : 'enable', imeId]);
    await adb(['shell', 'am', 'force-stop', appPackage]);
    await adb([
      'shell', 'monkey', '-p', appPackage, '-c',
      'android.intent.category.LAUNCHER', '1',
    ]);

    host = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: hostPort,
      nameOverride: nazwaHosta,
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'received'),
    );
    await host.setKeyboardAddon(true);
    stanNadawcy = () {
      final stan = host.outgoingRemoteInput.value;
      if (stan == null) return 'brak sesji';
      return '${stan.state.name} reason=${stan.reason} applied=${stan.applied} '
          'cel=${stan.target.app} active=${stan.target.active} '
          'ownApp=${stan.target.ownApp} field=${stan.target.field.name}';
    };

    final koniec = DateTime.now().add(const Duration(seconds: 60));
    Peer? znaleziony;
    while (znaleziony == null && DateTime.now().isBefore(koniec)) {
      znaleziony = await host.addPeerByAddress('127.0.0.1', deviceProxyPort);
      if (znaleziony == null) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    expect(znaleziony, isNotNull, reason: 'aplikacja nie odpowiada na /info');
    telefon = znaleziony!;
  });

  tearDownAll(() async {
    // Sprzątanie z limitem na każdy krok: raz zawisło na 12 minut, a test
    // ma powiedzieć, na którym.
    Future<void> krok(String nazwa, Future<Object?> Function() co) =>
        co().then<void>((_) {}).timeout(const Duration(seconds: 30),
            onTimeout: () {
          // ignore: avoid_print
          print('sprzątanie: „$nazwa" nie skończyło się w 30 s');
        });
    await krok('stop sesji', host.stopRemoteInput);
    await krok('zamknięcie hosta', host.dispose);
    await krok('tunel do urządzenia',
        () => adb(['forward', '--remove', 'tcp:$deviceProxyPort']));
    await krok('tunel do hosta',
        () => adb(['reverse', '--remove', 'tcp:$hostPort']));
    work.deleteSync(recursive: true);
  });

  test(
      'zrzuty: karta dodatku i włączenie klawiatury Chatt w systemie, tak jak '
      'robi to użytkownik',
      skip: zrzuty ? false : 'tylko przy CHATT_SHOTS=1', () async {
    await adb([
      'shell', 'monkey', '-p', appPackage, '-c',
      'android.intent.category.LAUNCHER', '1',
    ]);
    await Future<void>.delayed(const Duration(seconds: 2));
    // Aplikacja wraca na ekranie, na którym ją zostawiono: najpierw lista.
    for (var i = 0; i < 3; i++) {
      final wstecz = await findAnyWidget(['Back', 'Wstecz'],
          pakiet: appPackage, timeout: const Duration(seconds: 2));
      if (wstecz == null) break;
      await adb(['shell', 'input', 'tap', '${wstecz.$2.$1}', '${wstecz.$2.$2}']);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await stuknijEtykiete(['Settings', 'Ustawienia'], pakiet: appPackage);
    const wlacz = ['Turn on the Chatt keyboard', 'Włącz klawiaturę Chatt'];
    for (var i = 0; i < 12; i++) {
      if (await findAnyWidget(wlacz,
              pakiet: appPackage, timeout: const Duration(seconds: 2)) !=
          null) {
        break;
      }
      await adb(['shell', 'input', 'swipe', '640', '2200', '640', '1400', '300']);
    }
    final przycisk = await findAnyWidget(wlacz, pakiet: appPackage);
    expect(przycisk, isNotNull,
        reason: 'na karcie dodatku nie ma „Turn on the Chatt keyboard"');
    // Przycisk na dole kadru, nad nim cała karta z tytułem.
    await adb([
      'shell', 'input', 'swipe', '640', '${przycisk!.$2.$2}', '640', '2550',
      '800',
    ]);
    await Future<void>.delayed(const Duration(seconds: 1));
    await zrzutDoDokumentacji('and26_klawiatura_dodatek');

    await stuknijEtykiete(wlacz, pakiet: appPackage);
    await Future<void>.delayed(const Duration(seconds: 2));
    // Lista klawiatur w ustawieniach systemu: przełącznik klawiatury Chatt
    // to ostatni węzeł z jej nazwą (po tytule i podpisie).
    await stuknijEtykiete(['Chatt keyboard'],
        ostatni: true, pakiet: 'com.android.settings');
    expect(await findWidget('OK'), isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await zrzutDoDokumentacji('and27_klawiatura_ostrzezenie');
    await stuknijEtykiete(['OK'], pakiet: 'com.android.settings');
    await Future<void>.delayed(const Duration(seconds: 1));
    if (await findWidget('OK', timeout: const Duration(seconds: 3)) != null) {
      await zrzutDoDokumentacji('and28_klawiatura_po_restarcie');
      await stuknijEtykiete(['OK'], pakiet: 'com.android.settings');
    }
    await czekaj(() async {
      final lista =
          (await adb(['shell', 'ime', 'list', '-s'])).stdout as String;
      return lista.contains(imeId);
    }, 'klawiatura Chatt włączona w systemie');
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
    await Future<void>.delayed(const Duration(seconds: 1));
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
  });

  test('przed parowaniem: odmowa bez karty', () async {
    expect(await host.startRemoteInput(telefon), RemoteInputStart.notVerified);
    // ignore: invalid_use_of_visible_for_testing_member
    final wynik = await host.debugSendSealed(
      telefon,
      '/input-session',
      InputSessionRequest(
        from: host.identity,
        op: inputSessionRequest,
        input: 'przed-parowaniem',
      ).toJson(),
    );
    expect(wynik.status, 403);
    expect(wynik.reply?['reason'], inputRejected);
    expect(
      await findWidget('type on this device',
          fragment: true, timeout: const Duration(seconds: 2)),
      isNull,
      reason: 'karta nie może się pokazać',
    );
  });

  test('parowanie kodem', () async {
    expect(await host.startPairing(telefon), isNotNull);
    // Host potwierdza pierwszy. Każde zapytanie od telefonu zapisuje u hosta
    // port, którym telefon się przedstawia (47780), a host dociera do niego
    // wyłącznie tunelem (47781): potwierdzenie wysłane po potwierdzeniu
    // telefonu poszłoby donikąd.
    await host.confirmPairing(telefon.guid);
    await stuknijEtykiete(['They match', 'Zgadza się'], azZniknie: true);
    await czekaj(() async => (await host.db.peerByGuid(telefon.guid))!.verified,
        'tarcza po obu stronach');
    telefon = await przypnijTunel();
  });

  test('zgoda, wybór klawiatury i pisanie w Kontaktach', () async {
    if (zrzuty) {
      // Okno wyboru klawiatury nad jedną rozmową: lista rozmów na
      // urządzeniu testowym zbiera po rozmówcy z każdego przebiegu.
      final rozmowa = await host.openConversationWith(telefon);
      await host.sendText(rozmowa, 'Meeting moved to 3 pm, room 2');
      await stuknijEtykiete([nazwaHosta], fragment: true, pakiet: appPackage);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await sesja(zrzutWyboru: 'and29_klawiatura_wybor');
    // Po zgodzie aplikacja schodzi na dół.
    await czekaj(() async {
      final top = (await adb(['shell', 'dumpsys', 'activity', 'activities']))
          .stdout as String;
      final wiersz = top
          .split('\n')
          .firstWhere((l) => l.contains('ResumedActivity'), orElse: () => '');
      return !wiersz.contains(appPackage);
    }, 'Chatt schodzi na dół po zgodzie');

    // Świeży formularz: Kontakty pamiętają niezapisany szkic z poprzedniego
    // przebiegu i dopisywalibyśmy do niego.
    await adb(['shell', 'am', 'force-stop', 'com.google.android.contacts']);
    await adb([
      'shell', 'am', 'start', '-a', 'android.intent.action.INSERT', '-t',
      'vnd.android.cursor.dir/contact',
    ]);
    // Pierwsze pole formularza: imię (albo całe imię i nazwisko, zależnie
    // od wersji Kontaktów).
    await stuknijPole();
    await czekaj(() async {
      final cel = host.outgoingRemoteInput.value?.target;
      return cel != null && cel.active && cel.app.contains('contacts');
    }, 'cel u nadawcy: pole w Kontaktach', ile: const Duration(seconds: 10));
    final cel = host.outgoingRemoteInput.value!.target;
    expect(cel.field, RemoteInputField.text);
    // Akcja zależy od pola i wersji Kontaktów (Dalej albo Gotowe); liczy się,
    // że dociera do nadawcy.
    expect(cel.action, isNot(RemoteInputAction.none));
    expect(cel.appLabel, isNotEmpty);

    expect(
      host.sendRemoteInput(const [
        RemoteInputOp.insert('Chatt ąęł 124'),
        RemoteInputOp.backspace(),
        RemoteInputOp.insert('3'),
      ]),
      isTrue,
    );
    await czekaj(() => jestPoleZTekstem('Chatt ąęł 123'),
        'tekst w polu imienia');
    // Pasek klawiatury Chatt pod polem, zanim akcja pola go schowa.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await zrzutDoDokumentacji('and24_klawiatura_pisze');

    // Akcja pola to akcja z `imeOptions`: przy „Dalej" fokus idzie do
    // następnego pola, przy „Gotowe" (pole imienia w nowszych Kontaktach)
    // klawiatura się chowa, a pole zostaje z fokusem i dalej przyjmuje tekst.
    final akcja = host.outgoingRemoteInput.value!.target.action;
    expect(host.sendRemoteInput(const [RemoteInputOp.action()]), isTrue);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(host.sendRemoteInput(const [RemoteInputOp.insert(' Klawiatura')]),
        isTrue);
    await czekaj(
      () => jestPoleZTekstem(akcja == RemoteInputAction.next
          ? ' Klawiatura'
          : 'Chatt ąęł 123 Klawiatura'),
      'tekst po akcji pola',
    );
    await screenshot(p.join(work.path, 'kontakt.png'));
  });

  test('zablokowany ekran: odmowa i nic się nie wpisuje', () async {
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_SLEEP']);
    await czekaj(() async {
      final cel = host.outgoingRemoteInput.value?.target;
      return cel != null && cel.locked && !cel.active;
    }, 'cel u nadawcy: zablokowany ekran', ile: const Duration(seconds: 10));
    expect(host.sendRemoteInput(const [RemoteInputOp.insert('ZA BLOKADĄ')]),
        isTrue);
    await czekaj(() async => host.outgoingRemoteInput.value?.applied == false,
        'odmowa przy zablokowanym ekranie');
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP']);
    await adb(['shell', 'wm', 'dismiss-keyguard']);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(await jestPoleZTekstem('Chatt ąęł 123 Klawiatura'), isTrue,
        reason: 'nic z zablokowanego ekranu nie trafiło do pola');
    expect(await biezacaKlawiatura(), imeId,
        reason: 'ekran blokady bez hasła zostawia klawiaturę Chatt');
    final powiadomienia =
        (await adb(['shell', 'dumpsys', 'notification', '--noredact'])).stdout
            as String;
    expect(
        powiadomienia.contains('id=7301') &&
            powiadomienia.contains('pkg=$appPackage'),
        isFalse,
        reason: 'bez hasła nie ma powiadomienia o przełączeniu klawiatury');
  });

  test(
      'hasło na ekranie blokady: klawiatura oddaje miejsce, po odblokowaniu '
      'powiadomienie przywraca ją jednym dotknięciem',
      // Hasło blokady ustawia się wyłącznie na emulatorze, nigdy na telefonie
      // kogoś, kto go używa.
      skip: deviceId.startsWith('emulator-') ? false : 'tylko emulator',
      () async {
    const haslo = 'chatt1234';
    await adb(['shell', 'locksettings', 'set-password', haslo]);
    try {
      expect(await biezacaKlawiatura(), imeId);
      await adb(['shell', 'input', 'keyevent', 'KEYCODE_SLEEP']);
      await Future<void>.delayed(const Duration(seconds: 2));
      await adb(['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP']);
      await Future<void>.delayed(const Duration(seconds: 1));
      // Pole hasła na ekranie blokady: przesunięcie w górę.
      await adb(['shell', 'input', 'swipe', '640', '2400', '640', '800', '300']);
      await czekaj(() async => await biezacaKlawiatura() != imeId,
          'klawiatura Chatt oddaje miejsce na ekranie blokady');
      await adb(['shell', 'input', 'text', haslo]);
      await adb(['shell', 'input', 'keyevent', 'KEYCODE_ENTER']);
      await czekaj(() async {
        final okna = (await adb(['shell', 'dumpsys', 'window'])).stdout as String;
        return okna.contains('isKeyguardShowing=false');
      }, 'odblokowanie');
      await czekaj(() async {
        final powiadomienia =
            (await adb(['shell', 'dumpsys', 'notification', '--noredact']))
                .stdout as String;
        return powiadomienia.contains('id=7301') &&
            powiadomienia.contains('pkg=$appPackage');
      }, 'powiadomienie „Przełącz klawiaturę na Chatt"');
      await adb(['shell', 'cmd', 'statusbar', 'expand-notifications']);
      if (zrzuty) {
        await findWidget('Switch the keyboard to Chatt',
            fragment: true, timeout: const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(seconds: 1));
        await zrzutDoDokumentacji('and30_klawiatura_powiadomienie');
        // Same dwa powiadomienia Chatt, bez kafelków i bez powiadomień
        // samego emulatora (Pixel 9 Pro, 1280×2856).
        await przytnijZrzut('and30_klawiatura_powiadomienie', 680, 1492);
      }
      await stuknijEtykiete(
          ['Switch the keyboard to Chatt', 'Przełącz klawiaturę na Chatt'],
          fragment: true);
      await stuknijEtykiete(['Chatt keyboard', 'Klawiatura Chatt'],
          ostatni: true);
      await czekaj(() async => await biezacaKlawiatura() == imeId,
          'klawiatura Chatt z powrotem bieżącą');
    } finally {
      await adb(['shell', 'locksettings', 'clear', '--old', haslo]);
    }
  });

  test('Stop na pasku klawiatury kończy sesję po obu stronach', () async {
    // Pasek klawiatury wraca po stuknięciu w pole.
    await stuknijPole();
    await Future<void>.delayed(const Duration(seconds: 1));
    await stuknijEtykiete(['Stop']);
    await czekaj(
      () async =>
          host.outgoingRemoteInput.value?.state ==
          OutgoingRemoteInputState.disconnected,
      'nadawca rozłączony',
    );
    expect(host.outgoingRemoteInput.value!.reason, inputNoGrant);
    await czekaj(() async => await biezacaKlawiatura() != imeId,
        'powrót poprzedniej klawiatury');
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
  });

  test('pole wiadomości w samym Chatcie: pisanie trafia i tam', () async {
    await adb([
      'shell', 'monkey', '-p', appPackage, '-c',
      'android.intent.category.LAUNCHER', '1',
    ]);
    await Future<void>.delayed(const Duration(seconds: 2));
    // Rozmowa z hostem powstała przy parowaniu.
    final rozmowa = await host.openConversationWith(telefon);
    await host.sendText(rozmowa,
        zrzuty ? 'Can you check the room for tomorrow?' : 'Rozmowa do testu klawiatury');
    await stuknijEtykiete([nazwaHosta], fragment: true);
    // Karta zgody nad jedną rozmową: lista rozmów na urządzeniu testowym
    // zbiera po jednym „Komputerze PC" z każdego przebiegu.
    await sesja(zrzut: 'and23_klawiatura_zgoda');
    await adb([
      'shell', 'monkey', '-p', appPackage, '-c',
      'android.intent.category.LAUNCHER', '1',
    ]);
    // Flutter wystawia całe pole tekstowe jako jeden węzeł na pół ekranu,
    // więc w pole wiadomości stukamy na wysokości przycisku Wyślij.
    final wyslij = await findWidget('Send') ?? await findWidget('Wyślij');
    expect(wyslij, isNotNull, reason: await widocznaTresc());
    await adb(['shell', 'input', 'tap', '400', '${wyslij!.$2}']);
    await czekaj(() async {
      final cel = host.outgoingRemoteInput.value?.target;
      return cel != null && cel.ownApp;
    }, 'cel u nadawcy: własne pole Chatta', ile: const Duration(seconds: 10));
    final przed = (await host.db.watchMessages(rozmowa).first).length;
    expect(host.sendRemoteInput(const [RemoteInputOp.insert('do Chatt')]),
        isTrue);
    await czekaj(() async => (await poleZFokusem())?.text.contains('do Chatt') ??
        false, 'tekst w polu wiadomości Chatt');
    // Pasek „Pisze" u góry aplikacji i tekst w polu wiadomości.
    await zrzutDoDokumentacji('and25_klawiatura_pasek');
    expect(host.sendRemoteInput(const [RemoteInputOp.backspace(8)]), isTrue);
    await czekaj(() async => !((await poleZFokusem())?.text.contains('do Chatt') ??
        false), 'pole wiadomości z powrotem puste');
    expect((await host.db.watchMessages(rozmowa).first).length, przed,
        reason: 'bez Entera nic nie wyszło');
    await host.stopRemoteInput();
  });

  test('wyłączony dodatek: klawiatury Chatt nie ma na liście systemu',
      () async {
    Future<bool> naLiscie() async =>
        ((await adb(['shell', 'ime', 'list', '-a', '-s'])).stdout as String)
            .contains(imeId);
    Future<void> doDodatkow() async {
      // Aplikacja wraca na ekran, na którym ją zostawiono: z rozmowy na
      // listę przyciskiem wstecz w pasku aplikacji.
      for (var i = 0; i < 3; i++) {
        final wstecz = await findWidget('Back',
                timeout: const Duration(seconds: 2)) ??
            await findWidget('Wstecz', timeout: const Duration(seconds: 1));
        if (wstecz == null) break;
        await adb(['shell', 'input', 'tap', '${wstecz.$1}', '${wstecz.$2}']);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      await stuknijEtykiete(['Settings', 'Ustawienia']);
      for (var i = 0;
          i < 8 &&
              await findWidget('Keyboard from a PC',
                      fragment: true, timeout: const Duration(seconds: 1)) ==
                  null &&
              await findWidget('Klawiatura z PC',
                      fragment: true, timeout: const Duration(seconds: 1)) ==
                  null;
          i++) {
        await adb(['shell', 'input', 'swipe', '640', '2200', '640', '1000',
            '300']);
      }
    }

    await adb([
      'shell', 'monkey', '-p', appPackage, '-c',
      'android.intent.category.LAUNCHER', '1',
    ]);
    await Future<void>.delayed(const Duration(seconds: 2));
    await doDodatkow();
    expect(await naLiscie(), isTrue);
    await stuknijEtykiete(['Keyboard from a PC', 'Klawiatura z PC'],
        fragment: true);
    await czekaj(() async => !await naLiscie(),
        'klawiatura Chatt znika z listy systemu');

    // Z powrotem jak było, żeby następny przebieg zastał dodatek i odbiór.
    await stuknijEtykiete(['Keyboard from a PC', 'Klawiatura z PC'],
        fragment: true);
    // Przełącznik odbioru stoi pod podpowiedzią dodatku, zwykle już pod
    // krawędzią ekranu: lista przewija się kawałek, aż go widać.
    for (var i = 0;
        i < 4 &&
            await findWidget('Allow typing on this device',
                    fragment: true, timeout: const Duration(seconds: 1)) ==
                null &&
            await findWidget('Pozwól pisać na tym urządzeniu',
                    fragment: true, timeout: const Duration(seconds: 1)) ==
                null;
        i++) {
      await adb(['shell', 'input', 'swipe', '640', '2000', '640', '1500',
          '300']);
    }
    await stuknijEtykiete(
        ['Allow typing on this device', 'Pozwól pisać na tym urządzeniu'],
        fragment: true);
    await czekaj(() async => naLiscie(), 'klawiatura Chatt wraca na listę');
  });
}
