// Klawiatura z PC na prawdziwym telefonie: przebieg i pomiary opóźnień.
//
// Ten proces jest nadawcą (jak PC), odbiorcą jest aplikacja Chatt na
// telefonie podłączonym kablem. Skrypt jest ostrożny wobec telefonu, którego
// ktoś używa na co dzień: nie wysyła żadnej wiadomości, pisze wyłącznie do
// formularza nowego kontaktu (sprawdza cel przed każdą paczką), na koniec
// kasuje wpisany tekst, zamyka formularz bez zapisu i przywraca klawiatury
// systemu do stanu sprzed testu.
//
// Parowanie idzie tunelami adb (jak w `tool/klawiatura_android_e2e_test.dart`).
// Z CHATT_PHONE_IP sesja i pomiary idą przez Wi‑Fi prosto pod ten adres
// (host łączy się do telefonu, telefon do hosta już nie musi); bez niej
// tunelem przez kabel.
//
//   set CHATT_DEVICE=<numer z adb devices>
//   set CHATT_PHONE_IP=192.168.1.20
//   flutter test tool/klawiatura_telefon_test.dart
//
// Telefon zablokowany PIN-em: w kroku z blokadą skrypt gasi ekran, sprawdza,
// że na ekranie blokady jest zwykła klawiatura, i czeka, aż go odblokujesz.
//
// Zmienne: ADB, CHATT_DEVICE, CHATT_PHONE_IP, CHATT_POMIAR_ZNAKI (domyślnie 100).
//
// ignore_for_file: avoid_print
@Timeout(Duration(minutes: 15))
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';

import 'uiautomator.dart';

const int hostPort = 47790;
const int tunelPort = 47781;
const String appPackage = 'com.mysttic.chatt';
const String imeId = '$appPackage/.ChattInputMethod';
const String kontakty = 'com.google.android.contacts';

final String? ipTelefonu = Platform.environment['CHATT_PHONE_IP'];
final int ileZnakow =
    int.tryParse(Platform.environment['CHATT_POMIAR_ZNAKI'] ?? '') ?? 100;

Future<String> ustawienie(String klucz) async =>
    ((await adb(['shell', 'settings', 'get', 'secure', klucz])).stdout
            as String)
        .trim();

Future<String> biezacaKlawiatura() => ustawienie('default_input_method');

Future<bool> ekranBlokady() async =>
    ((await adb(['shell', 'dumpsys', 'window'])).stdout as String)
        .contains('isKeyguardShowing=true');

Future<void> czekaj(Future<bool> Function() warunek, String co,
    {Duration ile = const Duration(seconds: 20)}) async {
  final koniec = DateTime.now().add(ile);
  while (!await warunek()) {
    if (DateTime.now().isAfter(koniec)) {
      fail('nie doczekano: $co. Na ekranie: ${await widocznaTresc()}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

/// Percentyl z posortowanej listy (metoda najbliższego rzędu).
int percentyl(List<int> wartosci, double p) {
  final s = [...wartosci]..sort();
  final i = math.max(0, (p * s.length).ceil() - 1);
  return s[math.min(i, s.length - 1)];
}

String statystyka(String co, List<int> ms) => ms.isEmpty
    ? '$co: brak próbek'
    : '$co: n=${ms.length} p50=${percentyl(ms, 0.5)} ms '
        'p95=${percentyl(ms, 0.95)} ms min=${ms.reduce(math.min)} ms '
        'max=${ms.reduce(math.max)} ms';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory work;
  late AppServices host;
  late Peer telefon;
  late String klawiaturyPrzed;
  late String klawiaturaPrzed;
  var dotkniecia = 0;
  var formularzOtwarty = false;
  var wpisaneWFormularzu = 0;

  OutgoingRemoteInput? stan() => host.outgoingRemoteInput.value;

  /// Następna odpowiedź na paczkę z tekstem.
  Future<OutgoingRemoteInput> odpowiedz(int przed) async {
    final koniec = DateTime.now().add(const Duration(seconds: 10));
    while ((stan()?.typedReplies ?? przed) <= przed) {
      if (DateTime.now().isAfter(koniec)) fail('brak odpowiedzi na paczkę');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    return stan()!;
  }

  /// Pisze wyłącznie, gdy pole z fokusem należy do aplikacji [pakiet].
  Future<OutgoingRemoteInput> wpiszW(
      String pakiet, List<RemoteInputOp> ops) async {
    final cel = stan()?.target;
    if (cel == null || cel.app != pakiet || !cel.active) {
      fail('cel to nie $pakiet (${cel?.app}), nic nie wysyłam');
    }
    final przed = stan()!.typedReplies;
    expect(host.sendRemoteInput(ops), isTrue);
    return odpowiedz(przed);
  }

  Future<OutgoingRemoteInput> wpiszDoKontaktu(List<RemoteInputOp> ops) =>
      wpiszW(kontakty, ops);

  /// Jedno pole w aplikacji [pakiet]: otwarcie, pisanie, sprawdzenie tekstu
  /// w polu, skasowanie go i zamknięcie bez zapisu.
  Future<void> poleW(String pakiet, List<String> otworz, String tekst) async {
    await adb(['shell', 'am', 'force-stop', pakiet]);
    await adb(['shell', 'am', 'start', ...otworz]);
    await Future<void>.delayed(const Duration(seconds: 2));
    await stuknijPole();
    await czekaj(() async {
      final cel = stan()?.target;
      return cel != null && cel.active && cel.app == pakiet;
    }, 'pole w $pakiet', ile: const Duration(seconds: 15));
    final klawiatura = await biezacaKlawiatura();
    await wpiszW(pakiet, [RemoteInputOp.insert(tekst)]);
    await czekaj(() async => (await poleZFokusem())?.text.contains(tekst) ?? false,
        'tekst w polu $pakiet');
    print('$pakiet „${stan()!.target.appLabel}": tekst w polu, '
        'pole=${stan()!.target.field.name} akcja=${stan()!.target.action.name}, '
        'klawiatura: ${klawiatura == imeId ? 'Chatt' : klawiatura}');
    await wpiszW(pakiet, [RemoteInputOp.backspace(tekst.runes.length)]);
    await czekaj(
        () async => !((await poleZFokusem())?.text.contains(tekst) ?? false),
        'pole $pakiet wyczyszczone');
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
    await Future<void>.delayed(const Duration(seconds: 1));
    await adb(['shell', 'am', 'force-stop', pakiet]);
  }

  Future<void> stuknij(List<String> etykiety,
      {bool ostatni = false, bool azZniknie = false, String? pakiet}) async {
    await stuknijEtykiete(etykiety,
        ostatni: ostatni, azZniknie: azZniknie, pakiet: pakiet);
    dotkniecia++;
  }

  setUpAll(() async {
    // Ekran telefonu niesie prywatne rozmowy: do logów idzie tylko liczba
    // węzłów.
    ukryjTrescEkranu = true;
    work = Directory.systemTemp.createTempSync('chatt_klawiatura_telefon');
    klawiaturyPrzed = await ustawienie('enabled_input_methods');
    klawiaturaPrzed = await biezacaKlawiatura();
    print('klawiatury przed testem: $klawiaturyPrzed, bieżąca: $klawiaturaPrzed');
    expect((await adb(['forward', 'tcp:$tunelPort', 'tcp:47780'])).exitCode, 0);
    expect((await adb(['reverse', 'tcp:$hostPort', 'tcp:$hostPort'])).exitCode,
        0);
    await adb(['shell', 'ime', 'enable', imeId]);
    await adb([
      'shell', 'monkey', '-p', appPackage, '-c',
      'android.intent.category.LAUNCHER', '1',
    ]);
    host = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: hostPort,
      nameOverride: 'Pomiar PC',
      enableDiscovery: false,
      receivedDirOverride: p.join(work.path, 'received'),
    );
    await host.setKeyboardAddon(true);
    final koniec = DateTime.now().add(const Duration(seconds: 60));
    Peer? znaleziony;
    while (znaleziony == null && DateTime.now().isBefore(koniec)) {
      znaleziony = await host.addPeerByAddress('127.0.0.1', tunelPort);
      if (znaleziony == null) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    expect(znaleziony, isNotNull, reason: 'aplikacja nie odpowiada na /info');
    telefon = znaleziony!;
  });

  tearDownAll(() async {
    // Każdy krok z limitem: zawieszone adb nie trzyma testu w nieskończoność.
    // Własne `async` daje Future<void>, więc `onTimeout` pasuje typem.
    Future<void> krok(String nazwa, Future<void> Function() co) =>
        (() async {
          await co();
        })()
            .timeout(const Duration(seconds: 30),
                onTimeout: () {
              print('sprzątanie: „$nazwa" nie skończyło się');
            });
    await krok('stop sesji', host.stopRemoteInput);
    if (formularzOtwarty) {
      // Formularz bez zapisu. Gdyby coś w nim zostało, Kontakty pytają
      // o porzucenie zmian: wtedy „Odrzuć".
      await krok('zamknięcie formularza', () async {
        await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
        await Future<void>.delayed(const Duration(seconds: 1));
        await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
        await Future<void>.delayed(const Duration(seconds: 1));
        for (final e in ['Discard', 'Odrzuć']) {
          final gdzie = await findWidget(e, timeout: const Duration(seconds: 2));
          if (gdzie != null) {
            await adb(['shell', 'input', 'tap', '${gdzie.$1}', '${gdzie.$2}']);
            break;
          }
        }
      });
    }
    // Gdyby formularz został w tle (na przykład za ekranem blokady), pusty
    // znika razem z zatrzymaniem Kontaktów.
    if (formularzOtwarty) {
      await krok('Kontakty zatrzymane', () => adb(['shell', 'am', 'force-stop', kontakty]));
    }
    await krok('klawiatury jak przed testem', () async {
      if (!klawiaturyPrzed.contains(imeId)) {
        await adb(['shell', 'ime', 'disable', imeId]);
      }
      await adb(['shell', 'ime', 'set', klawiaturaPrzed]);
    });
    await krok('zamknięcie hosta', host.dispose);
    await krok('tunel do telefonu', () => adb(['forward', '--remove', 'tcp:$tunelPort']));
    await krok('tunel do hosta', () => adb(['reverse', '--remove', 'tcp:$hostPort']));
    print('klawiatury po teście: ${await ustawienie('enabled_input_methods')}, '
        'bieżąca: ${await biezacaKlawiatura()}');
    work.deleteSync(recursive: true);
  });

  test('parowanie kodem', () async {
    expect(await host.startPairing(telefon), isNotNull);
    await host.confirmPairing(telefon.guid);
    await stuknijEtykiete(['They match', 'Zgadza się'],
        azZniknie: true, pakiet: appPackage);
    await czekaj(() async => (await host.db.peerByGuid(telefon.guid))!.verified,
        'tarcza po obu stronach');
    // Dalej host łączy się z telefonem tunelem albo prosto przez Wi‑Fi.
    await host.db.upsertPeer(
      guid: telefon.guid,
      name: telefon.name,
      welcomeMessage: telefon.welcomeMessage,
      host: ipTelefonu ?? '127.0.0.1',
      port: ipTelefonu == null ? tunelPort : 47780,
    );
    telefon = (await host.db.peerByGuid(telefon.guid))!;
    print('droga sesji: ${ipTelefonu == null ? 'tunel adb (kabel)' : 'Wi‑Fi do $ipTelefonu'}');
  });

  test('zgoda na karcie, wybór klawiatury Chatt', () async {
    var start = host.startRemoteInput(telefon);
    final zgodaAlboOdmowa = await czekajNaKarteAlbo(
        start, ['Accept', 'Akceptuj'],
        pakiet: appPackage);
    if (zgodaAlboOdmowa == RemoteInputStart.notEnabled) {
      print('dodatek albo odbiór wyłączony w aplikacji: włączam');
      await wlaczDodatekKlawiatury(appPackage);
      await adb([
        'shell', 'monkey', '-p', appPackage, '-c',
        'android.intent.category.LAUNCHER', '1',
      ]);
      start = host.startRemoteInput(telefon);
    }
    final zegar = Stopwatch()..start();
    await stuknij(['Accept', 'Akceptuj'], azZniknie: true, pakiet: appPackage);
    expect(await start, RemoteInputStart.accepted);
    if (await biezacaKlawiatura() != imeId) {
      await stuknij(['Chatt keyboard', 'Klawiatura Chatt'], ostatni: true);
    }
    await czekaj(() async => await biezacaKlawiatura() == imeId,
        'klawiatura Chatt bieżącą');
    print('od zgody do klawiatury Chatt: ${zegar.elapsedMilliseconds} ms');
  });

  test('formularz kontaktu: tekst z polskimi znakami i pomiary', () async {
    await adb(['shell', 'am', 'force-stop', kontakty]);
    await adb([
      'shell', 'am', 'start', '-a', 'android.intent.action.INSERT', '-t',
      'vnd.android.cursor.dir/contact',
    ]);
    formularzOtwarty = true;
    await stuknijPole();
    dotkniecia++;
    await czekaj(() async {
      final cel = stan()?.target;
      return cel != null && cel.active && cel.app.contains(kontakty);
    }, 'cel u nadawcy: formularz kontaktu');
    print('dotknięcia od prośby do pierwszej litery: $dotkniecia '
        '(zgoda, wybór klawiatury, pole)');
    print('cel: ${stan()!.target.app} „${stan()!.target.appLabel}" '
        'pole=${stan()!.target.field.name} akcja=${stan()!.target.action.name} '
        'droga=${stan()!.protocol?.name}');

    // Poprawność: polskie znaki, Backspace, emoji jako jeden znak.
    await wpiszDoKontaktu(const [RemoteInputOp.insert('Chatt ąęł 124')]);
    await wpiszDoKontaktu(const [RemoteInputOp.backspace()]);
    await wpiszDoKontaktu(const [RemoteInputOp.insert('3 😀')]);
    await wpiszDoKontaktu(const [RemoteInputOp.backspace()]);
    wpisaneWFormularzu = 'Chatt ąęł 123 '.runes.length;
    await czekaj(() => jestPoleZTekstem('Chatt ąęł 123 '), 'tekst w polu');

    // Ping: tło bez pisania, co sekundę.
    final pingi = <int>[];
    final sub = host.outgoingRemoteInput;
    var ostatnieOdpowiedzi = stan()!.typedReplies;
    void naPing() {
      final s = sub.value;
      if (s == null || s.rtt == null) return;
      if (s.typedReplies == ostatnieOdpowiedzi) pingi.add(s.rtt!.inMilliseconds);
      ostatnieOdpowiedzi = s.typedReplies;
    }

    sub.addListener(naPing);
    await Future<void>.delayed(const Duration(seconds: 30));
    sub.removeListener(naPing);

    // Znak po znaku w tempie spokojnego pisania (co 100 ms), każdy osobno.
    final znaki = <int>[];
    for (var i = 0; i < ileZnakow; i++) {
      final zegar = Stopwatch()..start();
      await wpiszDoKontaktu([RemoteInputOp.insert(String.fromCharCode(0x61 + i % 26))]);
      znaki.add(zegar.elapsedMilliseconds);
      wpisaneWFormularzu++;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    // Szybkie pisanie (co 20 ms) bez czekania: ile paczek na znak.
    final przedSeria = stan()!.typedReplies;
    final seria = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      final cel = stan()?.target;
      if (cel == null || !cel.app.contains(kontakty)) {
        fail('cel się zmienił w trakcie serii (${cel?.app})');
      }
      expect(host.sendRemoteInput(const [RemoteInputOp.insert('z')]), isTrue);
      wpisaneWFormularzu++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Koniec serii: przez sekundę nie przyszła żadna odpowiedź na tekst.
    var ostatnio = stan()!.typedReplies;
    var cisza = 0;
    while (cisza < 10) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final teraz = stan()!.typedReplies;
      cisza = teraz == ostatnio ? cisza + 1 : 0;
      ostatnio = teraz;
    }
    seria.stop();
    final paczkiSerii = stan()!.typedReplies - przedSeria;

    print(statystyka('RTT pingu', pingi));
    print(statystyka('znak (wysłanie do odpowiedzi, co 100 ms)', znaki));
    print('seria 50 znaków co 20 ms: $paczkiSerii paczek '
        '(${(paczkiSerii / 50).toStringAsFixed(2)} paczki na znak), '
        'całość ${seria.elapsedMilliseconds} ms');

    // Sprzątanie formularza: cały wpisany tekst z powrotem.
    await wpiszDoKontaktu([RemoteInputOp.backspace(wpisaneWFormularzu)]);
    wpisaneWFormularzu = 0;
  });

  test('pisanie wszędzie: kolejne aplikacje w jednej sesji', () async {
    // Klawiatura Chatt zostaje bieżąca, więc pisanie idzie za fokusem do
    // każdej aplikacji, bez nowej zgody i bez okna wyboru.
    await poleW('com.google.android.settings.intelligence',
        ['-a', 'android.settings.APP_SEARCH_SETTINGS'], 'Chatt ąęł ustawienia');
    await poleW(
        'com.google.android.calendar',
        [
          '-a', 'android.intent.action.INSERT', '-t',
          'vnd.android.cursor.item/event', '-p', 'com.google.android.calendar',
        ],
        'Chatt ąęł kalendarz');
    await poleW(
        kontakty,
        [
          '-a', 'android.intent.action.INSERT', '-t',
          'vnd.android.cursor.dir/contact',
        ],
        'Chatt ąęł znowu kontakty');
    expect(stan()!.state, OutgoingRemoteInputState.active,
        reason: 'ta sama sesja przez wszystkie aplikacje');
  });

  test('własne pole Chatt: pisanie trafia i tam', () async {
    await adb([
      'shell', 'monkey', '-p', appPackage, '-c',
      'android.intent.category.LAUNCHER', '1',
    ]);
    await Future<void>.delayed(const Duration(seconds: 2));
    // Aplikacja wraca na ekranie, na którym ją zostawiono: najpierw na listę
    // rozmów. Pole szukania na liście tylko filtruje, więc nawet wpisany
    // tekst niczego by nie zmienił.
    for (var i = 0; i < 3; i++) {
      final wstecz = await findAnyWidget(['Back', 'Wstecz'],
          pakiet: appPackage, timeout: const Duration(seconds: 2));
      if (wstecz == null) break;
      await adb(['shell', 'input', 'tap', '${wstecz.$2.$1}', '${wstecz.$2.$2}']);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    // Szukanie bywa otwarte z poprzedniego razu: wtedy pole już jest.
    final szukaj = await findAnyWidget(['Szukaj rozmowy', 'Search conversations'],
        pakiet: appPackage, timeout: const Duration(seconds: 5));
    if (szukaj != null) {
      await adb(['shell', 'input', 'tap', '${szukaj.$2.$1}', '${szukaj.$2.$2}']);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await stuknijPole();
    await czekaj(() async {
      final cel = stan()?.target;
      return cel != null && cel.ownApp && cel.active;
    }, 'cel u nadawcy: własne pole Chatt', ile: const Duration(seconds: 10));
    // Pole szukania tylko filtruje listę: tekst w nim niczego nie zmienia.
    final po = await wpiszW(appPackage, const [RemoteInputOp.insert('do Chatt')]);
    expect(po.applied, isTrue, reason: 'pole Chatt przyjmuje pisanie');
    await czekaj(() async => (await poleZFokusem())?.text.contains('do Chatt') ??
        false, 'tekst w polu szukania Chatt');
    await wpiszW(appPackage, const [RemoteInputOp.backspace(8)]);
    print('własne pole Chatt: applied=${po.applied} ownApp=${po.target.ownApp}');
    // Szukanie z powrotem zamknięte, lista rozmów jak przed testem.
    final zamknij = await findAnyWidget(['Zamknij', 'Close'],
        pakiet: appPackage, timeout: const Duration(seconds: 3));
    if (zamknij != null) {
      await adb(['shell', 'input', 'tap', '${zamknij.$2.$1}', '${zamknij.$2.$2}']);
    }
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
  });

  test('ekran blokady: zwykła klawiatura i odmowa', skip: Platform.environment['CHATT_BLOKADA'] == '0'
      ? 'CHATT_BLOKADA=0'
      : false, () async {
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_SLEEP']);
    await czekaj(() async => stan()?.target.locked ?? false,
        'cel u nadawcy: zablokowany', ile: const Duration(seconds: 10));
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP']);
    await Future<void>.delayed(const Duration(seconds: 2));
    // Pasek klawiatury Chatt nie może stać na ekranie blokady.
    final etykiety = [
      for (final w in await uiNodes() ?? const <UiNode>[]) ...[w.text, w.desc],
    ];
    print('ekran blokady: keyguard=${await ekranBlokady()}, '
        'klawiatura w systemie: ${await biezacaKlawiatura()}');
    for (final pasek in ['Switch keyboard', 'Przełącz klawiaturę']) {
      expect(etykiety, isNot(contains(pasek)),
          reason: 'pasek klawiatury Chatt na ekranie blokady');
    }
    if (await ekranBlokady()) {
      print('>>> Odblokuj telefon (czekam do 3 minut).');
      await czekaj(() async => !await ekranBlokady(), 'odblokowanie',
          ile: const Duration(minutes: 3));
    }
    // Po odblokowaniu pisanie trwa dalej, bez nowej zgody.
    print('po odblokowaniu klawiatura: ${await biezacaKlawiatura()}');
    await poleW('com.google.android.settings.intelligence',
        ['-a', 'android.settings.APP_SEARCH_SETTINGS'], 'Chatt po blokadzie');
  });

  test('koniec sesji: wraca poprzednia klawiatura', () async {
    await host.stopRemoteInput();
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(await biezacaKlawiatura(), isNot(imeId));
  });
}
