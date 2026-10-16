import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/core/remote_input.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';

/// Ujście w pamięci dla odbiorcy, który stoi na innej platformie niż ta,
/// której kanał akurat sprawdzamy.
class _Ujscie implements RemoteInputSink {
  final ops = <RemoteInputOp>[];
  static const cel = RemoteInputTarget(
    active: true,
    field: RemoteInputField.text,
    app: 'com.example.notes',
    appLabel: 'Notatki',
  );

  @override
  bool get supported => true;

  @override
  Future<RemoteInputTarget> status() async => cel;

  @override
  Future<RemoteInputApplied> apply(List<RemoteInputOp> nowe) async {
    ops.addAll(nowe);
    return (applied: true, target: cel);
  }

  @override
  Future<void> holdOwnApp(bool on) async {}

  @override
  Future<void> setSession({required bool active, String peerName = ''}) async {}

  @override
  Future<bool> setImeEnabled(bool on) async => true;
}

/// Dodatek „Klawiatura z PC" (Ustawienia, sekcja „Dodatki") jest jedynym
/// włącznikiem zdalnej klawiatury. Wyłączony znaczy, że kanał natywny
/// `chatt/remoteinput` nie dostaje ani jednego wywołania, a prośby
/// zweryfikowanych urządzeń odbijają się bez karty.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Wiązanie testowe podmienia HttpClient na taki, który na wszystko
  // odpowiada 400. Tu instancje rozmawiają przez prawdziwe gniazda.
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const kanal = MethodChannel('chatt/remoteinput');

  /// Pole z fokusem, tak jak melduje je strona natywna.
  const cel = <String, Object?>{
    'active': true,
    'field': 'text',
    'action': 'none',
    'app': 'com.example.notes',
    'appLabel': 'Notatki',
  };

  /// Wywołania kanału po kolei: nazwa metody, a przy przełącznikach także
  /// ich wartość (`setImeEnabled:true`, `setSession:false`).
  final wywolania = <String>[];

  /// Te same wywołania razem z argumentami.
  final surowe = <MethodCall>[];

  /// Gdy ustawione, pierwsze `setImeEnabled` czeka na nie: tak wygląda
  /// system, który chwilę przełącza komponent klawiatury.
  Completer<void>? wstrzymajIme;
  Completer<void>? imeDotarlo;
  late Directory katalog;
  late Duration pingPrzed;

  setUp(() {
    wywolania.clear();
    surowe.clear();
    wstrzymajIme = null;
    imeDotarlo = null;
    katalog = Directory.systemTemp.createTempSync('chatt_klawiatura_');
    // Pingi co godzinę: liczymy wywołania kanału i nie chcemy w nich
    // niczego, czego test sam nie wywołał.
    pingPrzed = debugRemoteInputPingInterval;
    debugRemoteInputPingInterval = const Duration(hours: 1);
    // Udajemy platformę z kodem natywnym także na Linuksie z CI. Inaczej kanał
    // milczałby z powodu platformy i test niczego by nie dowodził.
    RemoteInputChannel.debugSupported = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, (call) async {
      surowe.add(call);
      final argumenty = call.arguments;
      wywolania.add(switch (call.method) {
        'setImeEnabled' => 'setImeEnabled:${(argumenty as Map)['on']}',
        'setSession' => 'setSession:${(argumenty as Map)['active']}',
        _ => call.method,
      });
      if (call.method == 'setImeEnabled') {
        final czekaj = wstrzymajIme;
        if (czekaj != null) {
          wstrzymajIme = null;
          imeDotarlo?.complete();
          await czekaj.future;
        }
      }
      return switch (call.method) {
        'status' => cel,
        'apply' => const {...cel, 'applied': true},
        'setSession' => const <String, Object?>{},
        'setImeEnabled' => const <String, Object?>{'ok': true},
        _ => null,
      };
    });
  });

  tearDown(() {
    RemoteInputChannel.debugSupported = null;
    debugRemoteInputPingInterval = pingPrzed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, null);
    katalog.deleteSync(recursive: true);
  });

  Future<AppServices> instancja(
    String nazwa, {
    File? plik,
    RemoteInputPolicy? polityka,
    RemoteInputSink? ujscie,
  }) async {
    final services = await AppServices.start(
      executor: plik == null ? NativeDatabase.memory() : NativeDatabase(plik),
      portOverride: 0,
      nameOverride: nazwa,
      enableDiscovery: false,
      receivedDirOverride: '${katalog.path}/$nazwa',
      remoteInputPolicy: polityka,
      remoteInputSink: ujscie,
    );
    addTearDown(services.dispose);
    return services;
  }

  /// Parowanie kodem, po którym obie strony są zweryfikowane. Zwraca
  /// [odbiorca] tak, jak widzi go [nadawca].
  Future<Peer> sparuj(AppServices nadawca, AppServices odbiorca) async {
    final odbiorcaUNadawcy =
        await nadawca.addPeerByAddress('127.0.0.1', odbiorca.server.port!);
    expect(await nadawca.startPairing(odbiorcaUNadawcy!), isNotNull);
    expect(await nadawca.confirmPairing(odbiorca.identity.guid),
        PairOutcome.accepted);
    expect(await odbiorca.confirmPairing(nadawca.identity.guid),
        PairOutcome.accepted);
    final peer = (await nadawca.db.peerByGuid(odbiorca.identity.guid))!;
    expect(peer.verified, isTrue);
    expect((await odbiorca.db.peerByGuid(nadawca.identity.guid))!.verified,
        isTrue);
    return peer;
  }

  /// Czeka, aż [warunek] się spełni. Sieć i kolejki chodzą w tle.
  Future<void> czekajNa(bool Function() warunek) async {
    final koniec = DateTime.now().add(const Duration(seconds: 10));
    while (!warunek()) {
      if (DateTime.now().isAfter(koniec)) {
        fail('warunek nie spełnił się w ciągu 10 s');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Pierwsze `setImeEnabled` wstrzymane do odwołania. Zwraca to, co je
  /// puszcza.
  Completer<void> wstrzymaneIme() {
    final pusc = Completer<void>();
    wstrzymajIme = pusc;
    imeDotarlo = Completer<void>();
    return pusc;
  }

  /// Kolejne wartości `on` z wywołań `setImeEnabled`.
  List<bool> ime() => [
        for (final call in surowe)
          if (call.method == 'setImeEnabled')
            (call.arguments as Map)['on'] == true,
      ];

  /// Paczka sklejona ręcznie, z tokenem, którego odbiorca nigdy nie wydał.
  Map<String, Object?> obcaPaczka(AppServices nadawca, List<RemoteInputOp> ops,
          {int seq = 1}) =>
      padInputPayload(RemoteInputPacket(
        from: nadawca.identity,
        input: 'obca-sesja-1',
        token: 'AAAAAAAAAAAAAAAAAAAAAA==',
        seq: seq,
        ops: ops,
      ).toJson());

  test('wyłączony dodatek nie dotyka kanału klawiatury', () async {
    final alicja = await instancja('Alicja');
    final bartek = await instancja('Bartek');
    expect(wywolania, isEmpty, reason: 'start bez żadnego wywołania');
    expect(bartek.keyboardAddon.value, isFalse);

    final peer = await sparuj(alicja, bartek);
    expect(await alicja.setKeyboardAddon(true), isTrue);
    wywolania.clear();
    surowe.clear();

    // Zweryfikowane urządzenie prosi o pisanie: odmowa, bez karty.
    expect(await alicja.startRemoteInput(peer), RemoteInputStart.notEnabled);
    expect(bartek.pendingRemoteInput.value, isEmpty);
    expect(bartek.incomingRemoteInput.value, isNull);
    expect(alicja.outgoingRemoteInput.value, isNull);

    // Paczki bez zgody: tekst, ping i stop. Każda odbija się, żadna nie
    // dociera do strony natywnej, nawet po stan pola.
    final tekst = await alicja.debugSendSealed(
        peer,
        '/input',
        obcaPaczka(alicja,
            const [RemoteInputOp.insert('x'), RemoteInputOp.action()]));
    expect(tekst.status, 403);
    expect(tekst.reply?['reason'], inputNoGrant);
    final ping = await alicja.debugSendSealed(peer, '/input',
        obcaPaczka(alicja, const [RemoteInputOp.ping()], seq: 2));
    expect(ping.status, 403);
    final stop = await alicja.debugSendSealed(peer, '/input',
        obcaPaczka(alicja, const [RemoteInputOp.stop()], seq: 3));
    expect(stop.status, 403);

    // Przełącznik odbioru bez dodatku też nic nie rusza.
    expect(await bartek.setRemoteInputReceive(true), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(wywolania, isEmpty);
    expect(bartek.pendingRemoteInput.value, isEmpty);
  });

  test('włączenie dodatku woła kanał wyłącznie po klawiaturę w systemie',
      () async {
    final services = await instancja('Bartek');

    expect(await services.setKeyboardAddon(true), isTrue);
    expect(services.keyboardAddon.value, isTrue);
    expect(wywolania, ['setImeEnabled:true']);
    expect(surowe.single.arguments, {'on': true});

    final ustawienia = (await services.db.getSettings())!;
    expect(ustawienia.keyboardEnabled, isTrue);
    expect(ustawienia.remoteInputReceive, isFalse,
        reason: 'odbiór włącza się osobno');
  });

  test('wyłączenie dodatku bez zgody woła wyłącznie setImeEnabled(false)',
      () async {
    final services = await instancja('Bartek');
    await services.setKeyboardAddon(true);
    wywolania.clear();
    surowe.clear();

    expect(await services.setKeyboardAddon(false), isFalse);
    expect(services.keyboardAddon.value, isFalse);
    expect(wywolania, ['setImeEnabled:false']);
    expect(surowe.single.arguments, {'on': false});
    expect((await services.db.getSettings())!.keyboardEnabled, isFalse);
  });

  test('wyłączenie dodatku w trakcie zgody kończy ją i od tej pory kanał '
      'milczy',
      () async {
    final alicja = await instancja('Alicja');
    final bartek =
        await instancja('Bartek', polityka: acceptAllRemoteInput);
    final peer = await sparuj(alicja, bartek);
    await alicja.setKeyboardAddon(true);
    await bartek.setKeyboardAddon(true);
    expect(await bartek.setRemoteInputReceive(true), isTrue);
    wywolania.clear();
    surowe.clear();

    // Z dodatkiem kanał działa: zgoda zapala wskaźnik, tekst idzie do pola.
    expect(await alicja.startRemoteInput(peer), RemoteInputStart.accepted);
    expect(bartek.incomingRemoteInput.value, isNotNull);
    expect(wywolania, containsAllInOrder(['setSession:true', 'status']));
    expect(alicja.sendRemoteInput(const [RemoteInputOp.insert('Cześć')]),
        isTrue);
    await czekajNa(() => wywolania.contains('apply'));
    final wpisane = surowe.firstWhere((call) => call.method == 'apply');
    expect((wpisane.arguments as Map)['ops'], [
      {'t': 'insert', 's': 'Cześć'},
    ]);

    wywolania.clear();
    surowe.clear();
    expect(await bartek.setKeyboardAddon(false), isFalse);
    expect(bartek.keyboardAddon.value, isFalse);
    expect(bartek.incomingRemoteInput.value, isNull);
    expect(wywolania, ['setSession:false', 'setImeEnabled:false']);
    final ustawienia = (await bartek.db.getSettings())!;
    expect(ustawienia.keyboardEnabled, isFalse);
    expect(ustawienia.remoteInputReceive, isFalse);

    // Po wyłączeniu cisza: paczka ze starej zgody odbija się, nowa prośba
    // też, strona natywna nie słyszy o żadnej z nich.
    wywolania.clear();
    surowe.clear();
    expect(alicja.sendRemoteInput(const [RemoteInputOp.insert('x')]), isTrue);
    await czekajNa(() =>
        alicja.outgoingRemoteInput.value?.state ==
        OutgoingRemoteInputState.disconnected);
    expect(alicja.outgoingRemoteInput.value!.reason, inputNoGrant);
    expect(await alicja.startRemoteInput(peer), RemoteInputStart.notEnabled);
    expect(bartek.pendingRemoteInput.value, isEmpty);
    expect(await bartek.setRemoteInputReceive(true), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(wywolania, isEmpty);
  });

  test('wyłączenie dodatku gasi odbiór w bazie i ponowne włączenie go nie '
      'przywraca', () async {
    final services = await instancja('Bartek');
    await services.setKeyboardAddon(true);
    expect(await services.setRemoteInputReceive(true), isTrue);
    expect((await services.db.getSettings())!.remoteInputReceive, isTrue);

    await services.setKeyboardAddon(false);
    var ustawienia = (await services.db.getSettings())!;
    expect(ustawienia.keyboardEnabled, isFalse);
    expect(ustawienia.remoteInputReceive, isFalse);

    expect(await services.setKeyboardAddon(true), isTrue);
    ustawienia = (await services.db.getSettings())!;
    expect(ustawienia.keyboardEnabled, isTrue);
    expect(ustawienia.remoteInputReceive, isFalse,
        reason: 'odbiór trzeba włączyć od nowa, świadomie');
  });

  test('przełącznik odbioru przy wyłączonym dodatku niczego nie zapisuje',
      () async {
    final services = await instancja('Bartek');

    expect(await services.setRemoteInputReceive(true), isFalse);
    final ustawienia = (await services.db.getSettings())!;
    expect(ustawienia.remoteInputReceive, isFalse);
    expect(ustawienia.keyboardEnabled, isFalse);
    expect(services.keyboardAddon.value, isFalse);
    expect(wywolania, isEmpty);
  });

  test('zapis w bazie nie podnosi dodatku za plecami przełącznika', () async {
    final alicja = await instancja('Alicja');
    final bartek = await instancja('Bartek');
    final peer = await sparuj(alicja, bartek);
    await alicja.setKeyboardAddon(true);
    wywolania.clear();

    // Spóźnione albo obce zdarzenie z bazy: dodatek i odbiór włączone
    // w wierszu, ale nikt nie przełączył dodatku.
    await bartek.db.saveKeyboardAddon(true);
    await bartek.db.saveRemoteInputReceive(true);
    await bartek.db
        .watchSettings()
        .firstWhere((s) => s.keyboardEnabled && s.remoteInputReceive);
    await pumpEventQueue();

    expect(bartek.keyboardAddon.value, isFalse);
    expect(await alicja.startRemoteInput(peer), RemoteInputStart.notEnabled);
    expect(bartek.pendingRemoteInput.value, isEmpty);
    expect(bartek.incomingRemoteInput.value, isNull);
    expect(wywolania, isEmpty);
  });

  test('szybkie „wyłącz, włącz" kończy się włączonym', () async {
    final services = await instancja('Bartek');
    await services.setKeyboardAddon(true);
    surowe.clear();
    final pusc = wstrzymaneIme();

    final a = services.setKeyboardAddon(false);
    await imeDotarlo!.future;
    final b = services.setKeyboardAddon(true);
    await pumpEventQueue();
    // Przełączenia idą po kolei: drugie czeka, aż pierwsze skończy.
    expect(services.keyboardAddon.value, isFalse);
    expect(ime(), [false]);

    pusc.complete();
    expect(await a, isFalse);
    expect(await b, isTrue);

    // Pamięć, baza i system mówią to samo, co ostatnie kliknięcie.
    expect(services.keyboardAddon.value, isTrue);
    expect((await services.db.getSettings())!.keyboardEnabled, isTrue);
    expect(ime(), [false, true]);
  });

  test('szybkie „włącz, wyłącz, włącz" kończy się włączonym', () async {
    final services = await instancja('Bartek');
    final pusc = wstrzymaneIme();

    final a = services.setKeyboardAddon(true);
    await imeDotarlo!.future;
    final b = services.setKeyboardAddon(false);
    final c = services.setKeyboardAddon(true);
    await pumpEventQueue();
    expect(services.keyboardAddon.value, isTrue);
    expect(ime(), [true]);

    pusc.complete();
    await Future.wait([a, b, c]);

    expect(services.keyboardAddon.value, isTrue);
    final ustawienia = (await services.db.getSettings())!;
    expect(ustawienia.keyboardEnabled, isTrue);
    expect(ustawienia.remoteInputReceive, isFalse);
    expect(ime(), [true, false, true]);
    expect(wywolania, everyElement(startsWith('setImeEnabled:')));
  });

  test('szybkie „włącz, wyłącz" kończy się wyłączonym i ciszą', () async {
    final services = await instancja('Bartek');
    final pusc = wstrzymaneIme();

    final a = services.setKeyboardAddon(true);
    await imeDotarlo!.future;
    final b = services.setKeyboardAddon(false);
    pusc.complete();
    await Future.wait([a, b]);

    expect(services.keyboardAddon.value, isFalse);
    expect((await services.db.getSettings())!.keyboardEnabled, isFalse);
    expect(ime(), [true, false]);

    wywolania.clear();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await services.setRemoteInputReceive(true), isFalse);
    expect(wywolania, isEmpty);
  });

  test('na platformie bez ujścia dodatek włącza się bez odbioru',
      () async {
    RemoteInputChannel.debugSupported = false;
    final alicja = await instancja('Alicja');
    expect(alicja.remoteInputReceiveSupported, isFalse);

    // Pisać na innym urządzeniu da się z każdej platformy.
    expect(await alicja.setKeyboardAddon(true), isTrue);
    expect(alicja.keyboardAddon.value, isTrue);
    expect((await alicja.db.getSettings())!.keyboardEnabled, isTrue);

    // Odbioru na tej platformie nie ma, baza też go nie zapisuje.
    expect(await alicja.setRemoteInputReceive(true), isFalse);
    expect((await alicja.db.getSettings())!.remoteInputReceive, isFalse);

    // Odbiorca na innej platformie, z własnym ujściem.
    final ujscie = _Ujscie();
    final bartek = await instancja('Bartek',
        polityka: acceptAllRemoteInput, ujscie: ujscie);
    final peer = await sparuj(alicja, bartek);
    await bartek.setKeyboardAddon(true);
    expect(await bartek.setRemoteInputReceive(true), isTrue);

    expect(await alicja.startRemoteInput(peer), RemoteInputStart.accepted);
    expect(alicja.sendRemoteInput(const [RemoteInputOp.insert('ąę')]), isTrue);
    await alicja.stopRemoteInput();
    expect(ujscie.ops, [const RemoteInputOp.insert('ąę')]);
    expect(wywolania, isEmpty, reason: 'kanał tej platformy milczy');
  });

  group('dodatek zapisany w bazie', () {
    /// Pierwsze uruchomienie: dodatek i odbiór włączone, aplikacja
    /// zamknięta. Plik zostaje jak u użytkownika.
    Future<File> zapisanyDodatek() async {
      final plik = File('${katalog.path}/chatt.db');
      final pierwsza = await AppServices.start(
        executor: NativeDatabase(plik),
        portOverride: 0,
        nameOverride: 'Bartek',
        enableDiscovery: false,
        receivedDirOverride: '${katalog.path}/pierwsza',
      );
      expect(await pierwsza.setKeyboardAddon(true), isTrue);
      expect(await pierwsza.setRemoteInputReceive(true), isTrue);
      await pierwsza.dispose();
      return plik;
    }

    test('wstaje razem z aplikacją bez wywołania kanału', () async {
      final plik = await zapisanyDodatek();
      wywolania.clear();
      final druga = await instancja('Bartek',
          plik: plik, polityka: acceptAllRemoteInput);
      expect(druga.keyboardAddon.value, isTrue);
      expect(wywolania, isEmpty);
      final ustawienia = (await druga.db.getSettings())!;
      expect(ustawienia.keyboardEnabled, isTrue);
      expect(ustawienia.remoteInputReceive, isTrue);

      // I działa: zweryfikowane urządzenie dostaje zgodę.
      final alicja = await instancja('Alicja');
      final peer = await sparuj(alicja, druga);
      await alicja.setKeyboardAddon(true);
      expect(await alicja.startRemoteInput(peer), RemoteInputStart.accepted);
      expect(druga.incomingRemoteInput.value, isNotNull);
    });
  });
}
