import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/core/identity.dart';
import 'package:chatt/core/remote_input.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';

/// Ujście w pamięci: zapisuje każdą paczkę, która dotarła do wpisania,
/// i odpowiada sztucznym celem.
class _Ujscie implements RemoteInputSink {
  /// Operacje z kolejnych wywołań `apply`, jedna lista na wywołanie.
  final paczki = <List<RemoteInputOp>>[];
  final wywolania = <String>[];

  /// Nazwa nadawcy z ostatniego `setSession(active: true)`.
  String? nazwa;

  RemoteInputTarget cel = const RemoteInputTarget(
    active: true,
    field: RemoteInputField.text,
    app: 'com.example.notes',
    appLabel: 'Notatki',
  );

  /// Gdy ustawiony, `apply` czeka na niego: tak wygląda paczka, która
  /// długo się wpisuje, a nadawca w tym czasie pisze dalej.
  Completer<void>? zawor;

  /// Kończy się, gdy pierwsza wstrzymana paczka dotrze do `apply`.
  final dotarla = Completer<void>();

  @override
  bool supported = true;

  List<RemoteInputOp> get ops => [for (final paczka in paczki) ...paczka];

  String get tekst => ops
      .where((op) => op.kind == RemoteInputOpKind.insert)
      .map((op) => op.text)
      .join();

  int get wpisania => wywolania.where((w) => w == 'apply').length;

  /// Wywołania bez przełącznika dodatku, czyli wszystko, co dotyczy pisania.
  List<String> get wywolaniaPisania =>
      wywolania.where((w) => !w.startsWith('setImeEnabled')).toList();

  /// Kolejne `setSession`, same wartości `active`.
  List<String> get sesje =>
      wywolania.where((w) => w.startsWith('setSession')).toList();

  @override
  Future<RemoteInputTarget> status() async {
    wywolania.add('status');
    return cel;
  }

  @override
  Future<RemoteInputApplied> apply(List<RemoteInputOp> nowe) async {
    wywolania.add('apply');
    paczki.add(List.of(nowe));
    final czekaj = zawor;
    if (czekaj != null) {
      if (!dotarla.isCompleted) dotarla.complete();
      await czekaj.future;
    }
    return (applied: true, target: cel);
  }

  @override
  Future<void> setSession({required bool active, String peerName = ''}) async {
    wywolania.add('setSession:$active');
    if (active) nazwa = peerName;
  }

  @override
  Future<bool> setImeEnabled(bool on) async {
    wywolania.add('setImeEnabled:$on');
    return true;
  }
}

/// Alicja pisze, Bartek odbiera, [ujscie] należy do Bartka.
class _Scena {
  final AppServices alicja;
  final AppServices bartek;
  final _Ujscie ujscie;
  final Peer bartekUAlicji;

  _Scena(this.alicja, this.bartek, this.ujscie, this.bartekUAlicji);
}

/// Zdalna klawiatura między dwiema (czasem trzema) prawdziwymi instancjami,
/// przez prawdziwe gniazda. Wpisuje się wyłącznie to, na co odbiorca się
/// zgodził, po kolei, raz i tylko w ramach bieżącej zgody.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory katalog;
  late Duration pingi;
  final uruchomione = <AppServices>[];
  final zamkniete = <AppServices>{};

  setUp(() {
    katalog = Directory.systemTemp.createTempSync('chatt_klawiatura_');
    pingi = debugRemoteInputPingInterval;
    // Testy liczą paczki i wywołania ujścia: pingi by je zaśmiecały.
    debugRemoteInputPingInterval = const Duration(hours: 1);
  });

  tearDown(() async {
    for (final s in uruchomione.reversed) {
      if (zamkniete.add(s)) await s.dispose();
    }
    uruchomione.clear();
    zamkniete.clear();
    debugRemoteInputPingInterval = pingi;
    katalog.deleteSync(recursive: true);
  });

  Future<AppServices> instancja(
    String nazwa, {
    RemoteInputPolicy? polityka,
    _Ujscie? ujscie,
  }) async {
    final s = await AppServices.start(
      executor: NativeDatabase.memory(),
      portOverride: 0,
      nameOverride: nazwa,
      enableDiscovery: false,
      receivedDirOverride: p.join(katalog.path, nazwa),
      remoteInputPolicy: polityka,
      remoteInputSink: ujscie ?? _Ujscie(),
    );
    uruchomione.add(s);
    return s;
  }

  /// Zamyka instancję przed końcem testu; sprzątanie jej już nie ruszy.
  Future<void> zamknij(AppServices s) async {
    if (zamkniete.add(s)) await s.dispose();
  }

  Future<Peer> rozmowca(AppServices u, AppServices kto) async =>
      (await u.db.peerByGuid(kto.identity.guid))!;

  /// Parowanie kodem: po nim oboje mają się nawzajem za zweryfikowanych.
  Future<void> sparuj(AppServices a, AppServices b) async {
    final bUA = await a.addPeerByAddress('127.0.0.1', b.server.port!);
    expect(await a.startPairing(bUA!), isNotNull);
    expect(await a.confirmPairing(b.identity.guid), PairOutcome.accepted);
    expect(await b.confirmPairing(a.identity.guid), PairOutcome.accepted);
  }

  /// Sparowani Alicja i Bartek, dodatek włączony u obojga, u Bartka także
  /// odbiór. [karta] zostawia Bartkowi domyślną politykę, czyli kartę
  /// w [AppServices.pendingRemoteInput].
  Future<_Scena> scena({
    RemoteInputPolicy polityka = acceptAllRemoteInput,
    bool karta = false,
    bool dodatek = true,
    bool odbior = true,
  }) async {
    final ujscie = _Ujscie();
    final alicja = await instancja('Alicja');
    final bartek = await instancja(
      'Bartek',
      polityka: karta ? null : polityka,
      ujscie: ujscie,
    );
    await sparuj(alicja, bartek);
    expect(await alicja.setKeyboardAddon(true), isTrue);
    if (dodatek) expect(await bartek.setKeyboardAddon(true), isTrue);
    if (dodatek && odbior) {
      expect(await bartek.setRemoteInputReceive(true), isTrue);
    }
    return _Scena(alicja, bartek, ujscie, await rozmowca(alicja, bartek));
  }

  Future<void> czekaj(bool Function() warunek, [String opis = '']) async {
    final koniec = DateTime.now().add(const Duration(seconds: 10));
    while (!warunek()) {
      if (DateTime.now().isAfter(koniec)) fail('nie doczekano: $opis');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Czy u [s] pokazała się kiedykolwiek karta z prośbą o pisanie.
  bool Function() obserwujKarty(AppServices s) {
    var byla = s.pendingRemoteInput.value.isNotEmpty;
    s.pendingRemoteInput.addListener(() {
      if (s.pendingRemoteInput.value.isNotEmpty) byla = true;
    });
    return () => byla;
  }

  /// Identyfikator sesji pisania z klucza karty (`guid|input`).
  String inputKarty(PendingRemoteInput karta) =>
      karta.id.substring(karta.id.indexOf('|') + 1);

  OutgoingRemoteInputState? stan(AppServices s) =>
      s.outgoingRemoteInput.value?.state;

  /// Prośba o sesję złożona ręcznie, pod wybranym identyfikatorem.
  Future<({int status, InputSessionReply? odpowiedz})> popros(
    AppServices nadawca,
    Peer odbiorca,
    String input, {
    String op = inputSessionRequest,
  }) async {
    final wynik = await nadawca.debugSendSealed(
      odbiorca,
      '/input-session',
      InputSessionRequest(
        from: nadawca.identity,
        op: op,
        input: input,
      ).toJson(),
    );
    return (
      status: wynik.status,
      odpowiedz: InputSessionReply.fromJson(wynik.reply, input: input),
    );
  }

  /// Ręczna zgoda: zwraca token, którym podpisuje się każdą paczkę.
  Future<String> zgoda(AppServices nadawca, Peer odbiorca, String input) async {
    final wynik = await popros(nadawca, odbiorca, input);
    expect(wynik.status, 200);
    expect(wynik.odpowiedz?.accepted, isTrue);
    return wynik.odpowiedz!.token!;
  }

  /// Paczka złożona ręcznie: dowolny token, dowolny `seq` i dowolny nadawca
  /// wewnątrz koperty.
  Future<({int status, RemoteInputReply? odpowiedz})> wyslij(
    AppServices nadawca,
    Peer odbiorca, {
    required String input,
    required String token,
    required int seq,
    required List<RemoteInputOp> ops,
    DeviceIdentity? from,
  }) async {
    final wynik = await nadawca.debugSendSealed(
      odbiorca,
      '/input',
      RemoteInputPacket(
        from: from ?? nadawca.identity,
        input: input,
        token: token,
        seq: seq,
        ops: ops,
      ).toJson(),
    );
    return (
      status: wynik.status,
      odpowiedz: RemoteInputReply.fromJson(wynik.reply, input: input, seq: seq),
    );
  }

  /// Chatt sprzed dodatku klawiatury pod adresem pośrednika: wszystko idzie
  /// dalej do [port], a na trasy klawiatury odpowiada tak jak router bez
  /// nich, czyli 404.
  Future<HttpServer> staryChatt(int port) async {
    final serwer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final klient = HttpClient();
    addTearDown(() async {
      klient.close(force: true);
      await serwer.close(force: true);
    });
    const pomijane = {
      'host',
      'content-length',
      'transfer-encoding',
      'connection',
    };
    serwer.listen((zapytanie) async {
      final cialo = await zapytanie.fold<List<int>>(
        <int>[],
        (suma, kawalek) => suma..addAll(kawalek),
      );
      final odpowiedz = zapytanie.response;
      if (zapytanie.uri.path.startsWith('/input')) {
        odpowiedz.statusCode = 404;
        odpowiedz.write('Route not found');
        await odpowiedz.close();
        return;
      }
      final dalej = await klient.openUrl(
        zapytanie.method,
        Uri.parse('http://127.0.0.1:$port${zapytanie.uri}'),
      );
      zapytanie.headers.forEach((nazwa, wartosci) {
        if (pomijane.contains(nazwa)) return;
        for (final wartosc in wartosci) {
          dalej.headers.add(nazwa, wartosc);
        }
      });
      dalej.contentLength = cialo.length;
      dalej.add(cialo);
      final wynik = await dalej.close();
      odpowiedz.statusCode = wynik.statusCode;
      final typ = wynik.headers.contentType;
      if (typ != null) odpowiedz.headers.contentType = typ;
      await odpowiedz.addStream(wynik);
      await odpowiedz.close();
    });
    return serwer;
  }

  group('prośba o sesję', () {
    test('zgoda: operacje docierają do ujścia po kolei, z polskimi znakami '
        'i nową linią', () async {
      final s = await scena();
      expect(
        await s.alicja.startRemoteInput(s.bartekUAlicji),
        RemoteInputStart.accepted,
      );

      final wychodzaca = s.alicja.outgoingRemoteInput.value!;
      expect(wychodzaca.state, OutgoingRemoteInputState.active);
      expect(wychodzaca.peerGuid, s.bartek.identity.guid);
      expect(wychodzaca.target, s.ujscie.cel);
      final przychodzaca = s.bartek.incomingRemoteInput.value!;
      expect(przychodzaca.peerGuid, s.alicja.identity.guid);
      expect(przychodzaca.peerName, 'Alicja');
      expect(s.ujscie.nazwa, 'Alicja');

      const oczekiwane = [
        RemoteInputOp.insert('Zażółć gęślą jaźń\nDruga linia'),
        RemoteInputOp.backspace(2),
        RemoteInputOp.delete(),
        RemoteInputOp.insert('ĄĘŁŃÓŚŹŻ'),
        RemoteInputOp.action(),
      ];
      for (final op in oczekiwane) {
        expect(s.alicja.sendRemoteInput([op]), isTrue);
      }
      await s.alicja.stopRemoteInput();

      expect(s.ujscie.ops, oczekiwane);
      expect(s.alicja.outgoingRemoteInput.value, isNull);
      expect(s.bartek.incomingRemoteInput.value, isNull);
      expect(s.ujscie.sesje, ['setSession:true', 'setSession:false']);
      expect(s.ujscie.wywolaniaPisania.last, 'setSession:false');
    });

    test('cel z ujścia wraca do nadawcy i do wskaźnika odbiorcy', () async {
      final s = await scena();
      await s.alicja.startRemoteInput(s.bartekUAlicji);
      const haslo = RemoteInputTarget(
        active: true,
        field: RemoteInputField.password,
        action: RemoteInputAction.go,
        app: 'com.android.chrome',
        appLabel: 'Chrome',
      );
      s.ujscie.cel = haslo;

      expect(
        s.alicja.sendRemoteInput(const [RemoteInputOp.insert('x')]),
        isTrue,
      );
      await czekaj(
        () => s.alicja.outgoingRemoteInput.value?.target == haslo,
        'cel u nadawcy',
      );
      expect(s.alicja.outgoingRemoteInput.value!.applied, isTrue);
      expect(s.alicja.outgoingRemoteInput.value!.typedReplies, 1);
      expect(s.alicja.outgoingRemoteInput.value!.rtt, isNotNull);
      expect(s.bartek.incomingRemoteInput.value!.target, haslo);
    });

    test('ping przy bezczynności przynosi cel i niczego nie wpisuje', () async {
      debugRemoteInputPingInterval = const Duration(milliseconds: 50);
      final s = await scena();
      await s.alicja.startRemoteInput(s.bartekUAlicji);
      const inny = RemoteInputTarget(
        active: true,
        field: RemoteInputField.text,
        app: 'com.example.contacts',
        appLabel: 'Kontakty',
      );
      s.ujscie.cel = inny;

      await czekaj(
        () => s.alicja.outgoingRemoteInput.value?.target == inny,
        'cel z pingu',
      );
      expect(s.ujscie.wpisania, 0);
      expect(s.alicja.outgoingRemoteInput.value!.typedReplies, 0,
          reason: 'ping to nie paczka z tekstem');
      expect(
        s.ujscie.wywolania.where((w) => w == 'status').length,
        greaterThan(1),
      );
      expect(stan(s.alicja), OutgoingRemoteInputState.active);
      await s.alicja.stopRemoteInput();
      expect(s.ujscie.wpisania, 0);
    });

    test('przełącznik odbioru wyłączony: 403 not_enabled, bez karty i bez '
        'wywołań ujścia', () async {
      final s = await scena(karta: true, odbior: false);
      final bylaKarta = obserwujKarty(s.bartek);

      final reczna = await popros(s.alicja, s.bartekUAlicji, 'odbior-zgaszony');
      expect(reczna.status, 403);
      expect(reczna.odpowiedz!.accepted, isFalse);
      expect(reczna.odpowiedz!.reason, inputNotEnabled);
      expect(
        await s.alicja.startRemoteInput(s.bartekUAlicji),
        RemoteInputStart.notEnabled,
      );

      expect(s.alicja.outgoingRemoteInput.value, isNull);
      expect(bylaKarta(), isFalse);
      expect(s.bartek.incomingRemoteInput.value, isNull);
      expect(s.ujscie.wywolaniaPisania, isEmpty);
    });

    test('dodatek wyłączony u odbiorcy: odmowa bez karty, także gdy baza '
        'mówi co innego', () async {
      final s = await scena(karta: true, dodatek: false);
      final bylaKarta = obserwujKarty(s.bartek);
      expect(
        await s.alicja.startRemoteInput(s.bartekUAlicji),
        RemoteInputStart.notEnabled,
      );
      expect(await s.bartek.setRemoteInputReceive(true), isFalse);

      // Zapis w bazie z pominięciem przełącznika nie podnosi bramki.
      await s.bartek.db.saveKeyboardAddon(true);
      await s.bartek.db.saveRemoteInputReceive(true);
      expect(s.bartek.keyboardAddon.value, isFalse);
      final reczna = await popros(
        s.alicja,
        s.bartekUAlicji,
        'dodatek-zgaszony',
      );
      expect(reczna.status, 403);
      expect(reczna.odpowiedz!.reason, inputNotEnabled);
      expect(
        await s.alicja.startRemoteInput(s.bartekUAlicji),
        RemoteInputStart.notEnabled,
      );

      expect(bylaKarta(), isFalse);
      expect(s.bartek.incomingRemoteInput.value, isNull);
      // Wyłączony dodatek milczy całkiem: ani jednego wywołania ujścia.
      expect(s.ujscie.wywolania, isEmpty);
    });

    test('niezweryfikowany nadawca: rejected bez karty, cokolwiek leży '
        'w ustawieniach', () async {
      final s = await scena(karta: true);
      final bylaKarta = obserwujKarty(s.bartek);
      final dawid = await instancja('Dawid');
      final bartekUDawida = (await dawid.addPeerByAddress(
        '127.0.0.1',
        s.bartek.server.port!,
      ))!;
      expect(bartekUDawida.verified, isFalse);

      // Nadawca sam nie prosi: bez dodatku i bez weryfikacji odbiorcy.
      expect(
        await dawid.startRemoteInput(bartekUDawida),
        RemoteInputStart.addonOff,
      );
      await dawid.setKeyboardAddon(true);
      expect(
        await dawid.startRemoteInput(bartekUDawida),
        RemoteInputStart.notVerified,
      );
      expect(dawid.outgoingRemoteInput.value, isNull);

      // A prośba złożona ręcznie odbija się u odbiorcy zawsze tak samo.
      Future<void> odmowa(String input) async {
        final wynik = await popros(dawid, bartekUDawida, input);
        expect(wynik.status, 403, reason: input);
        expect(wynik.odpowiedz!.accepted, isFalse, reason: input);
        expect(wynik.odpowiedz!.reason, inputRejected, reason: input);
      }

      await odmowa('dawid-odbior-wlaczony');
      expect(await s.bartek.setRemoteInputReceive(false), isFalse);
      await odmowa('dawid-odbior-zgaszony');
      expect(await s.bartek.setKeyboardAddon(false), isFalse);
      await odmowa('dawid-dodatek-zgaszony');

      // Paczka bez zgody też.
      final paczka = await wyslij(
        dawid,
        bartekUDawida,
        input: 'dawid-paczka',
        token: 'WymyslonyToken1',
        seq: 1,
        ops: const [RemoteInputOp.insert('x')],
      );
      expect(paczka.status, 403);
      expect(paczka.odpowiedz!.reason, inputNoGrant);

      expect(bylaKarta(), isFalse);
      expect(s.bartek.incomingRemoteInput.value, isNull);
      expect(s.ujscie.wywolaniaPisania, isEmpty);
    });

    test('tarcza zdjęta tylko u odbiorcy: rejected bez karty', () async {
      final s = await scena(karta: true);
      final bylaKarta = obserwujKarty(s.bartek);
      final alicjaUBartka = await rozmowca(s.bartek, s.alicja);
      await s.bartek.db.setPeerVerified(alicjaUBartka.id, false);

      expect(
        await s.alicja.startRemoteInput(s.bartekUAlicji),
        RemoteInputStart.rejected,
      );
      expect(s.alicja.outgoingRemoteInput.value, isNull);
      expect(bylaKarta(), isFalse);
      expect(s.ujscie.wywolaniaPisania, isEmpty);
    });

    test('karta: odmowa, zgoda i „nie pytaj więcej"', () async {
      final s = await scena(karta: true);
      final alicjaUBartka = await rozmowca(s.bartek, s.alicja);

      Future<PendingRemoteInput> karta() async {
        await czekaj(
          () => s.bartek.pendingRemoteInput.value.isNotEmpty,
          'karta u Bartka',
        );
        return s.bartek.pendingRemoteInput.value.single;
      }

      // Odmowa.
      var start = s.alicja.startRemoteInput(s.bartekUAlicji);
      var prosba = await karta();
      expect(prosba.peerGuid, s.alicja.identity.guid);
      expect(prosba.peerName, 'Alicja');
      expect(prosba.platform, Platform.operatingSystem);
      expect(prosba.id, startsWith('${s.alicja.identity.guid}|'));
      expect(stan(s.alicja), OutgoingRemoteInputState.waiting);
      s.bartek.respondToRemoteInput(prosba.id, accept: false);
      expect(await start, RemoteInputStart.rejected);
      expect(s.bartek.pendingRemoteInput.value, isEmpty);
      expect(s.bartek.incomingRemoteInput.value, isNull);
      expect(s.alicja.outgoingRemoteInput.value, isNull);
      expect(s.ujscie.wywolaniaPisania, isEmpty);

      // Zgoda jednorazowa: sesja rusza, `peers.remoteInput` zostaje false.
      start = s.alicja.startRemoteInput(s.bartekUAlicji);
      prosba = await karta();
      s.bartek.respondToRemoteInput(prosba.id, accept: true);
      expect(await start, RemoteInputStart.accepted);
      expect(s.bartek.pendingRemoteInput.value, isEmpty);
      expect(
        s.bartek.incomingRemoteInput.value?.peerGuid,
        s.alicja.identity.guid,
      );
      expect((await rozmowca(s.bartek, s.alicja)).remoteInput, isFalse);
      await s.alicja.stopRemoteInput();
      expect(s.bartek.incomingRemoteInput.value, isNull);

      // „Nie pytaj więcej".
      start = s.alicja.startRemoteInput(s.bartekUAlicji);
      prosba = await karta();
      s.bartek.respondToRemoteInput(prosba.id, accept: true, remember: true);
      expect(await start, RemoteInputStart.accepted);
      expect(
        (await s.bartek.db.peerById(alicjaUBartka.id))!.remoteInput,
        isTrue,
      );
      await s.alicja.stopRemoteInput();

      // Następna sesja bez karty.
      final bylaKarta = obserwujKarty(s.bartek);
      expect(
        await s.alicja.startRemoteInput(s.bartekUAlicji),
        RemoteInputStart.accepted,
      );
      expect(bylaKarta(), isFalse);
      expect(s.bartek.incomingRemoteInput.value, isNotNull);
    });

    test('peers.remoteInput ustawione wprost: sesja bez karty', () async {
      final s = await scena(karta: true);
      final alicjaUBartka = await rozmowca(s.bartek, s.alicja);
      expect(
        await s.bartek.db.setPeerRemoteInput(alicjaUBartka.id, true),
        isTrue,
      );
      final bylaKarta = obserwujKarty(s.bartek);

      expect(
        await s.alicja.startRemoteInput(s.bartekUAlicji),
        RemoteInputStart.accepted,
      );
      expect(bylaKarta(), isFalse);
      expect(
        s.bartek.incomingRemoteInput.value?.peerGuid,
        s.alicja.identity.guid,
      );
      expect(
        s.alicja.sendRemoteInput(const [RemoteInputOp.insert('bez')]),
        isTrue,
      );
      await czekaj(() => s.ujscie.tekst == 'bez', 'tekst');
    });

    test('brak odpowiedzi kończy się noAnswer', () async {
      final s = await scena(
        polityka: (_) async => RemoteInputDecision.noAnswer,
      );
      expect(
        await s.alicja.startRemoteInput(s.bartekUAlicji),
        RemoteInputStart.noAnswer,
      );
      expect(s.alicja.outgoingRemoteInput.value, isNull);
      expect(s.bartek.incomingRemoteInput.value, isNull);
      expect(s.ujscie.wywolaniaPisania, isEmpty);
      expect(
        s.alicja.sendRemoteInput(const [RemoteInputOp.insert('x')]),
        isFalse,
      );
    });

    test('kopia prośby po odmowie dostaje tę samą odmowę', () async {
      final s = await scena(
        polityka: (_) async => RemoteInputDecision.noAnswer,
      );
      final bylaKarta = obserwujKarty(s.bartek);
      final pierwsza = await popros(s.alicja, s.bartekUAlicji, 'cisza');
      expect(pierwsza.status, 403);
      expect(pierwsza.odpowiedz!.reason, inputNoAnswer);

      // Ta sama prośba drugą drogą, gdy odpowiedź na pierwszą zginęła:
      // nadawca słyszy tę samą odpowiedź, którą dostała pierwsza.
      final kopia = await popros(s.alicja, s.bartekUAlicji, 'cisza');
      expect(kopia.status, 403);
      expect(kopia.odpowiedz!.reason, inputNoAnswer);
      expect(bylaKarta(), isFalse);
      expect(s.bartek.incomingRemoteInput.value, isNull);
    });

    test('dwie prośby naraz od tego samego nadawcy: zostaje nowsza, '
        'z jedną kartą', () async {
      final s = await scena(karta: true);
      final pierwsza = popros(s.alicja, s.bartekUAlicji, 'pierwsza');
      final druga = popros(s.alicja, s.bartekUAlicji, 'druga');

      // Która dotarła później, ta jest nowsza. Starsza kończy się bez zgody
      // i bez wpływu na nowszą, w jakiej kolejności by nie czytały bazy.
      final wyniki = <String, ({int status, InputSessionReply? odpowiedz})>{};
      unawaited(pierwsza.then((w) => wyniki['pierwsza'] = w));
      unawaited(druga.then((w) => wyniki['druga'] = w));
      await czekaj(() => wyniki.length == 1, 'starsza prośba się kończy');
      final starsza = wyniki.keys.single;
      final nowsza = starsza == 'pierwsza' ? 'druga' : 'pierwsza';
      expect(wyniki[starsza]!.status, 403);
      expect(wyniki[starsza]!.odpowiedz!.reason, inputNoAnswer);

      await czekaj(
          () => s.bartek.pendingRemoteInput.value.isNotEmpty, 'karta');
      final karty = s.bartek.pendingRemoteInput.value;
      expect(karty, hasLength(1));
      expect(inputKarty(karty.single), nowsza);

      s.bartek.respondToRemoteInput(karty.single.id, accept: true);
      await czekaj(() => wyniki.length == 2, 'nowsza prośba');
      expect(wyniki[nowsza]!.status, 200);
      expect(wyniki[nowsza]!.odpowiedz!.accepted, isTrue);
      expect(s.bartek.incomingRemoteInput.value, isNotNull);
    });

    test('powtórzona prośba pod zużytym identyfikatorem: ta sama odpowiedź, '
        'bez drugiej karty', () async {
      final s = await scena(karta: true);
      final start = s.alicja.startRemoteInput(s.bartekUAlicji);
      await czekaj(() => s.bartek.pendingRemoteInput.value.isNotEmpty, 'karta');
      final prosba = s.bartek.pendingRemoteInput.value.single;
      final input = inputKarty(prosba);

      // Kopia, póki karta wisi: tak wygląda prośba ponowiona drugą drogą, gdy
      // pierwsza padła w trakcie karty. Czeka na tę samą decyzję, a karta
      // zostaje jedna.
      final wtrakcie = popros(s.alicja, s.bartekUAlicji, input);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(s.bartek.pendingRemoteInput.value.map((k) => k.id), [prosba.id]);

      s.bartek.respondToRemoteInput(prosba.id, accept: true);
      expect(await start, RemoteInputStart.accepted);
      final kopia = await wtrakcie;
      expect(kopia.status, 200);
      expect(kopia.odpowiedz!.accepted, isTrue);
      final token = kopia.odpowiedz!.token;

      // Odtworzona po zgodzie: bez karty, ta sama zgoda z tym samym tokenem,
      // a pisanie trwa dalej.
      final bylaKarta = obserwujKarty(s.bartek);
      final po = await popros(s.alicja, s.bartekUAlicji, input);
      expect(po.status, 200);
      expect(po.odpowiedz!.token, token);
      expect(bylaKarta(), isFalse);
      expect(s.bartek.incomingRemoteInput.value, isNotNull);
      expect(
        s.alicja.sendRemoteInput(const [RemoteInputOp.insert('dalej')]),
        isTrue,
      );
      await czekaj(() => s.ujscie.tekst == 'dalej', 'tekst');

      // Po końcu zgody ta sama prośba odbija się odmową, nadal bez karty.
      await s.alicja.stopRemoteInput();
      final koniec = await popros(s.alicja, s.bartekUAlicji, input);
      expect(koniec.status, 403);
      expect(koniec.odpowiedz!.reason, inputRejected);
      expect(bylaKarta(), isFalse);
      expect(s.bartek.incomingRemoteInput.value, isNull);
    });

    test('zużytych identyfikatorów nie wypchnie zalew próśb od '
        'niezweryfikowanego', () async {
      final s = await scena(karta: true);
      final dawid = await instancja('Dawid');
      final bartekUDawida =
          await dawid.addPeerByAddress('127.0.0.1', s.bartek.server.port!);
      expect(bartekUDawida, isNotNull);

      final start = s.alicja.startRemoteInput(s.bartekUAlicji);
      await czekaj(() => s.bartek.pendingRemoteInput.value.isNotEmpty, 'karta');
      final prosba = s.bartek.pendingRemoteInput.value.single;
      final input = inputKarty(prosba);
      s.bartek.respondToRemoteInput(prosba.id, accept: true);
      expect(await start, RemoteInputStart.accepted);
      await s.alicja.stopRemoteInput();
      await czekaj(() => s.bartek.incomingRemoteInput.value == null, 'koniec');

      // Ktoś bez potwierdzonej tożsamości zalewa Bartka prośbami pod coraz
      // to nowymi identyfikatorami. Każda dostaje odmowę i żadna nie zajmuje
      // miejsca w pamięci zużytych.
      for (var i = 0; i < 520; i++) {
        final zalew = await popros(dawid, bartekUDawida!, 'zalew-$i');
        expect(zalew.status, 403);
        expect(zalew.odpowiedz!.reason, inputRejected);
      }

      // Nagrana prośba Alicji dalej jest zużyta: bez karty i bez zgody.
      final bylaKarta = obserwujKarty(s.bartek);
      final powtorka = await popros(s.alicja, s.bartekUAlicji, input);
      expect(powtorka.status, 403);
      expect(powtorka.odpowiedz!.reason, inputRejected);
      expect(bylaKarta(), isFalse);
      expect(s.bartek.incomingRemoteInput.value, isNull);
    });

    test('wycofanie zużywa identyfikator: prośba, która dotrze po nim, '
        'odbija się bez karty', () async {
      final s = await scena(karta: true);
      final bylaKarta = obserwujKarty(s.bartek);

      final wycofanie = await popros(
        s.alicja,
        s.bartekUAlicji,
        'spozniona',
        op: inputSessionCancel,
      );
      expect(wycofanie.status, 200);
      expect(wycofanie.odpowiedz!.reason, inputCancelled);

      final spozniona = await popros(s.alicja, s.bartekUAlicji, 'spozniona');
      expect(spozniona.status, 403);
      expect(spozniona.odpowiedz!.reason, inputRejected);
      expect(bylaKarta(), isFalse);
    });

    test('wycofanie po zgodzie, której nadawca nie poznał, gasi tę zgodę',
        () async {
      final s = await scena();
      await zgoda(s.alicja, s.bartekUAlicji, 'osierocona');
      expect(s.bartek.incomingRemoteInput.value, isNotNull);

      final wycofanie = await popros(
        s.alicja,
        s.bartekUAlicji,
        'osierocona',
        op: inputSessionCancel,
      );
      expect(wycofanie.status, 200);
      expect(s.bartek.incomingRemoteInput.value, isNull);
      expect(s.ujscie.sesje, ['setSession:true', 'setSession:false']);
    });

    test('zgoda, po której nikt nic nie przysłał, gaśnie sama', () async {
      final bezczynnosc = debugRemoteInputIdle;
      final zegar = debugRemoteInputGrantCheck;
      addTearDown(() {
        debugRemoteInputIdle = bezczynnosc;
        debugRemoteInputGrantCheck = zegar;
      });
      debugRemoteInputIdle = const Duration(milliseconds: 300);
      debugRemoteInputGrantCheck = const Duration(milliseconds: 50);

      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      expect(s.bartek.incomingRemoteInput.value, isNotNull);

      // Nadawca milknie (zamknięty, uśpiony, poza zasięgiem): wskaźnik
      // i sesja po stronie natywnej gasną bez żadnej paczki.
      await czekaj(
        () => s.bartek.incomingRemoteInput.value == null,
        'wygaśnięcie zgody',
      );
      expect(s.ujscie.sesje, ['setSession:true', 'setSession:false']);

      expect(
        s.alicja.sendRemoteInput(const [RemoteInputOp.insert('za późno')]),
        isTrue,
      );
      await czekaj(
        () => stan(s.alicja) == OutgoingRemoteInputState.disconnected,
        'rozłączenie',
      );
      expect(s.alicja.outgoingRemoteInput.value!.reason, inputNoGrant);
      expect(s.ujscie.wpisania, 0);
    });

    test('wycofanie od innego nadawcy nie rusza cudzej karty', () async {
      final s = await scena(karta: true);
      final celina = await instancja('Celina');
      await sparuj(celina, s.bartek);
      final bartekUCeliny = await rozmowca(celina, s.bartek);

      final start = s.alicja.startRemoteInput(s.bartekUAlicji);
      await czekaj(() => s.bartek.pendingRemoteInput.value.isNotEmpty, 'karta');
      final prosba = s.bartek.pendingRemoteInput.value.single;

      final wycofanie = await popros(
        celina,
        bartekUCeliny,
        inputKarty(prosba),
        op: inputSessionCancel,
      );
      expect(wycofanie.status, 200);
      expect(wycofanie.odpowiedz!.accepted, isFalse);
      expect(wycofanie.odpowiedz!.reason, inputCancelled);
      expect(s.bartek.pendingRemoteInput.value.map((k) => k.id), [prosba.id]);

      s.bartek.respondToRemoteInput(prosba.id, accept: true);
      expect(await start, RemoteInputStart.accepted);
      expect(
        s.bartek.incomingRemoteInput.value?.peerGuid,
        s.alicja.identity.guid,
      );
    });

    test('Stop w trakcie czekania wycofuje kartę, a start kończy się '
        'cancelled', () async {
      final s = await scena(karta: true);
      final start = s.alicja.startRemoteInput(s.bartekUAlicji);
      await czekaj(() => s.bartek.pendingRemoteInput.value.isNotEmpty, 'karta');

      await s.alicja.stopRemoteInput();
      expect(s.alicja.outgoingRemoteInput.value, isNull);
      expect(await start, RemoteInputStart.cancelled);
      await czekaj(
        () => s.bartek.pendingRemoteInput.value.isEmpty,
        'karta znika',
      );
      expect(s.bartek.incomingRemoteInput.value, isNull);
      expect(s.alicja.outgoingRemoteInput.value, isNull);
      expect(s.ujscie.wywolaniaPisania, isEmpty);
    });

    test('ten sam nadawca prosi ponownie: nowa zgoda zastępuje starą, '
        'stary token przestaje działać', () async {
      final s = await scena();
      final stary = await zgoda(s.alicja, s.bartekUAlicji, 'pierwsza');
      final a = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'pierwsza',
        token: stary,
        seq: 1,
        ops: const [RemoteInputOp.insert('a')],
      );
      expect(a.odpowiedz!.applied, isTrue);

      final nowy = await zgoda(s.alicja, s.bartekUAlicji, 'druga');
      expect(nowy, isNot(stary));
      final staraPaczka = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'pierwsza',
        token: stary,
        seq: 2,
        ops: const [RemoteInputOp.insert('x')],
      );
      expect(staraPaczka.status, 403);
      expect(staraPaczka.odpowiedz!.reason, inputNoGrant);

      final nowaPaczka = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'druga',
        token: nowy,
        seq: 1,
        ops: const [RemoteInputOp.insert('b')],
      );
      expect(nowaPaczka.status, 200);
      expect(nowaPaczka.odpowiedz!.applied, isTrue);
      expect(s.ujscie.tekst, 'ab');
      expect(s.ujscie.sesje, [
        'setSession:true',
        'setSession:false',
        'setSession:true',
      ]);
      expect(s.bartek.incomingRemoteInput.value, isNotNull);
    });

    test('ten sam nadawca prosi ponownie przy wiszącej karcie: stara prośba '
        'kończy się no-answer, karta pyta o nową', () async {
      final s = await scena(karta: true);
      final pierwsza = popros(s.alicja, s.bartekUAlicji, 'pierwsza');
      await czekaj(
        () => s.bartek.pendingRemoteInput.value.isNotEmpty,
        'pierwsza karta',
      );
      expect(
        s.bartek.pendingRemoteInput.value.single.id,
        '${s.alicja.identity.guid}|pierwsza',
      );

      final druga = popros(s.alicja, s.bartekUAlicji, 'druga');
      await czekaj(
        () =>
            s.bartek.pendingRemoteInput.value.length == 1 &&
            s.bartek.pendingRemoteInput.value.single.id.endsWith('|druga'),
        'druga karta',
      );
      final odpowiedz1 = await pierwsza;
      expect(odpowiedz1.status, 403);
      expect(odpowiedz1.odpowiedz!.reason, inputNoAnswer);

      s.bartek.respondToRemoteInput(
        s.bartek.pendingRemoteInput.value.single.id,
        accept: true,
      );
      final odpowiedz2 = await druga;
      expect(odpowiedz2.status, 200);
      expect(odpowiedz2.odpowiedz!.accepted, isTrue);
      expect(s.bartek.pendingRemoteInput.value, isEmpty);
    });

    test(
      'drugi nadawca przy trwającej zgodzie dostaje busy, bez karty',
      () async {
        final s = await scena(karta: true);
        final alicjaUBartka = await rozmowca(s.bartek, s.alicja);
        await s.bartek.db.setPeerRemoteInput(alicjaUBartka.id, true);
        expect(
          await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted,
        );

        final celina = await instancja('Celina');
        await sparuj(celina, s.bartek);
        await celina.setKeyboardAddon(true);
        final bartekUCeliny = await rozmowca(celina, s.bartek);
        final bylaKarta = obserwujKarty(s.bartek);

        expect(
          await celina.startRemoteInput(bartekUCeliny),
          RemoteInputStart.busy,
        );
        expect(celina.outgoingRemoteInput.value, isNull);
        expect(bylaKarta(), isFalse);
        expect(
          s.bartek.incomingRemoteInput.value?.peerGuid,
          s.alicja.identity.guid,
        );

        // Zgoda Alicji trwa.
        expect(
          s.alicja.sendRemoteInput(const [RemoteInputOp.insert('dalej')]),
          isTrue,
        );
        await czekaj(() => s.ujscie.tekst == 'dalej', 'tekst Alicji');

        // Po jej końcu Celina może prosić jak każdy.
        await s.alicja.stopRemoteInput();
        final start = celina.startRemoteInput(bartekUCeliny);
        await czekaj(
          () => s.bartek.pendingRemoteInput.value.isNotEmpty,
          'karta Celiny',
        );
        final prosba = s.bartek.pendingRemoteInput.value.single;
        expect(prosba.peerName, 'Celina');
        s.bartek.respondToRemoteInput(prosba.id, accept: true);
        expect(await start, RemoteInputStart.accepted);
        expect(
          s.bartek.incomingRemoteInput.value?.peerGuid,
          celina.identity.guid,
        );
      },
    );

    test('starszy odbiorca bez tras klawiatury: olderPeer', () async {
      final s = await scena();
      final stary = await staryChatt(s.bartek.server.port!);
      final przezStary = (await s.alicja.addPeerByAddress(
        '127.0.0.1',
        stary.port,
      ))!;
      expect(przezStary.port, stary.port);
      expect(przezStary.verified, isTrue);

      expect(
        await s.alicja.startRemoteInput(przezStary),
        RemoteInputStart.olderPeer,
      );
      expect(s.alicja.outgoingRemoteInput.value, isNull);
      expect(s.bartek.pendingRemoteInput.value, isEmpty);
      expect(s.bartek.incomingRemoteInput.value, isNull);
      expect(s.ujscie.wywolaniaPisania, isEmpty);
    });

    test(
      'zamknięcie odbiorcy rozwiązuje wiszącą kartę, start nie wisi',
      () async {
        final s = await scena(karta: true);
        final start = s.alicja.startRemoteInput(s.bartekUAlicji);
        await czekaj(
          () => s.bartek.pendingRemoteInput.value.isNotEmpty,
          'karta',
        );

        await zamknij(s.bartek);
        final wynik = await start.timeout(const Duration(seconds: 20));
        expect(
          wynik,
          anyOf(RemoteInputStart.noAnswer, RemoteInputStart.unreachable),
        );
        expect(s.alicja.outgoingRemoteInput.value, isNull);
        expect(s.ujscie.wywolaniaPisania, isEmpty);
      },
    );
  });

  group('paczki', () {
    test('powtórzony seq: duplicate i nic nie wpisuje się drugi raz', () async {
      final s = await scena();
      final token = await zgoda(s.alicja, s.bartekUAlicji, 'powtorka');

      final pierwsza = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'powtorka',
        token: token,
        seq: 1,
        ops: const [RemoteInputOp.insert('raz')],
      );
      expect(pierwsza.status, 200);
      expect(pierwsza.odpowiedz!.ok, isTrue);
      expect(pierwsza.odpowiedz!.applied, isTrue);
      expect(pierwsza.odpowiedz!.duplicate, isFalse);

      final druga = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'powtorka',
        token: token,
        seq: 1,
        ops: const [RemoteInputOp.insert('raz')],
      );
      expect(druga.status, 200);
      expect(druga.odpowiedz!.ok, isTrue);
      expect(druga.odpowiedz!.duplicate, isTrue);
      expect(druga.odpowiedz!.applied, pierwsza.odpowiedz!.applied);

      // Pod tym samym numerem inna treść też się nie wpisze.
      final podmieniona = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'powtorka',
        token: token,
        seq: 1,
        ops: const [RemoteInputOp.insert('dwa')],
      );
      expect(podmieniona.odpowiedz!.duplicate, isTrue);

      expect(s.ujscie.tekst, 'raz');
      expect(s.ujscie.wpisania, 1);
    });

    test('cofnięty seq: 403 stale_seq, a zgoda działa dalej', () async {
      final s = await scena();
      final token = await zgoda(s.alicja, s.bartekUAlicji, 'cofniety');
      Future<({int status, RemoteInputReply? odpowiedz})> paczka(
        int seq,
        String tekst,
      ) => wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'cofniety',
        token: token,
        seq: seq,
        ops: [RemoteInputOp.insert(tekst)],
      );

      expect((await paczka(5, 'a')).odpowiedz!.applied, isTrue);
      final cofnieta = await paczka(3, 'b');
      expect(cofnieta.status, 403);
      expect(cofnieta.odpowiedz!.ok, isFalse);
      expect(cofnieta.odpowiedz!.reason, inputStaleSeq);
      expect(s.bartek.incomingRemoteInput.value, isNotNull);

      final dalej = await paczka(6, 'c');
      expect(dalej.status, 200);
      expect(dalej.odpowiedz!.applied, isTrue);
      expect(s.ujscie.tekst, 'ac');
    });

    test('zły token albo cudzy identyfikator: 403 no_grant, bieżąca zgoda '
        'działa dalej', () async {
      final s = await scena();
      final token = await zgoda(s.alicja, s.bartekUAlicji, 'dobra');

      final zlyToken = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'dobra',
        token: 'ZlyToken123',
        seq: 1,
        ops: const [RemoteInputOp.insert('x')],
      );
      expect(zlyToken.status, 403);
      expect(zlyToken.odpowiedz!.reason, inputNoGrant);

      final zlyInput = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'inna',
        token: token,
        seq: 1,
        ops: const [RemoteInputOp.insert('x')],
      );
      expect(zlyInput.status, 403);
      expect(zlyInput.odpowiedz!.reason, inputNoGrant);
      expect(s.bartek.incomingRemoteInput.value, isNotNull);

      final dobra = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'dobra',
        token: token,
        seq: 1,
        ops: const [RemoteInputOp.insert('y')],
      );
      expect(dobra.status, 200);
      expect(dobra.odpowiedz!.applied, isTrue);
      expect(s.ujscie.tekst, 'y');
    });

    test('paczka pod sesją innego rozmówcy jest odrzucona', () async {
      final s = await scena();
      final celina = await instancja('Celina');
      await sparuj(celina, s.bartek);
      final bartekUCeliny = await rozmowca(celina, s.bartek);
      final token = await zgoda(s.alicja, s.bartekUAlicji, 'alicji');

      // Celina zna identyfikator i token Alicji i podpisuje paczkę sobą.
      final swoja = await wyslij(
        celina,
        bartekUCeliny,
        input: 'alicji',
        token: token,
        seq: 1,
        ops: const [RemoteInputOp.insert('celina')],
      );
      expect(swoja.status, 403);
      expect(swoja.odpowiedz!.reason, inputNoGrant);

      // Podszywa się pod Alicję wewnątrz własnej, poprawnie zaszyfrowanej
      // koperty.
      final podszyta = await wyslij(
        celina,
        bartekUCeliny,
        input: 'alicji',
        token: token,
        seq: 2,
        ops: const [RemoteInputOp.insert('podszyta')],
        from: s.alicja.identity,
      );
      expect(podszyta.status, isNot(200));
      expect(podszyta.odpowiedz, isNull);
      expect(s.ujscie.wpisania, 0);

      // Zgoda Alicji działa, a jej numeracja nie ucierpiała.
      final alicji = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'alicji',
        token: token,
        seq: 1,
        ops: const [RemoteInputOp.insert('ok')],
      );
      expect(alicji.status, 200);
      expect(alicji.odpowiedz!.applied, isTrue);
      expect(s.ujscie.tekst, 'ok');
    });

    test('stop od nadawcy kończy zgodę, a odtworzony nic nie daje', () async {
      final s = await scena();
      final token = await zgoda(s.alicja, s.bartekUAlicji, 'ze-stopem');
      const zeStopem = [RemoteInputOp.insert('a'), RemoteInputOp.stop()];

      final stop = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'ze-stopem',
        token: token,
        seq: 1,
        ops: zeStopem,
      );
      expect(stop.status, 200);
      expect(stop.odpowiedz!.applied, isTrue);
      expect(s.bartek.incomingRemoteInput.value, isNull);
      expect(s.ujscie.wywolaniaPisania.last, 'setSession:false');

      final odtworzony = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'ze-stopem',
        token: token,
        seq: 1,
        ops: zeStopem,
      );
      expect(odtworzony.status, 403);
      expect(odtworzony.odpowiedz!.reason, inputNoGrant);
      final dalej = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'ze-stopem',
        token: token,
        seq: 2,
        ops: const [RemoteInputOp.insert('b')],
      );
      expect(dalej.status, 403);
      expect(dalej.odpowiedz!.reason, inputNoGrant);
      expect(s.ujscie.tekst, 'a');
    });

    test('Stop u odbiorcy: następna paczka dostaje no_grant, nadawca jest '
        'rozłączony', () async {
      final s = await scena();
      await s.alicja.startRemoteInput(s.bartekUAlicji);
      s.alicja.sendRemoteInput(const [RemoteInputOp.insert('a')]);
      await czekaj(() => s.ujscie.tekst == 'a', 'pierwsza paczka');

      s.bartek.stopIncomingRemoteInput();
      expect(s.bartek.incomingRemoteInput.value, isNull);
      expect(s.ujscie.sesje.last, 'setSession:false');

      // Nadawca dowiaduje się przy następnej paczce.
      expect(
        s.alicja.sendRemoteInput(const [RemoteInputOp.insert('b')]),
        isTrue,
      );
      await czekaj(
        () => stan(s.alicja) == OutgoingRemoteInputState.disconnected,
        'rozłączenie',
      );
      expect(s.alicja.outgoingRemoteInput.value!.reason, inputNoGrant);
      expect(
        s.alicja.sendRemoteInput(const [RemoteInputOp.insert('c')]),
        isFalse,
      );
      expect(s.ujscie.tekst, 'a');
      expect(s.ujscie.wpisania, 1);

      await s.alicja.stopRemoteInput();
      expect(s.alicja.outgoingRemoteInput.value, isNull);
    });

    test('stop ze starym tokenem nie rusza nowej zgody', () async {
      final s = await scena();
      final stary = await zgoda(s.alicja, s.bartekUAlicji, 'stara');
      final nowy = await zgoda(s.alicja, s.bartekUAlicji, 'nowa');

      final staryStop = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'stara',
        token: stary,
        seq: 1,
        ops: const [RemoteInputOp.stop()],
      );
      expect(staryStop.status, 403);
      expect(staryStop.odpowiedz!.reason, inputNoGrant);

      // Stary token pod nowym identyfikatorem też nic nie kończy.
      final mieszany = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'nowa',
        token: stary,
        seq: 1,
        ops: const [RemoteInputOp.stop()],
      );
      expect(mieszany.status, 403);
      expect(mieszany.odpowiedz!.reason, inputNoGrant);
      expect(s.bartek.incomingRemoteInput.value, isNotNull);
      expect(s.ujscie.sesje.last, 'setSession:true');

      final nowa = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'nowa',
        token: nowy,
        seq: 1,
        ops: const [RemoteInputOp.insert('b')],
      );
      expect(nowa.status, 200);
      expect(nowa.odpowiedz!.applied, isTrue);
      expect(s.ujscie.tekst, 'b');
    });

    test('409 w środku sesji: nowy uścisk dłoni, ta sama zgoda, tekst '
        'wpisany raz', () async {
      final s = await scena();
      await s.alicja.startRemoteInput(s.bartekUAlicji);
      s.alicja.sendRemoteInput(const [RemoteInputOp.insert('ab')]);
      await czekaj(() => s.ujscie.tekst == 'ab', 'przed 409');

      s.bartek.debugDropIncomingSessions(s.alicja.identity.guid);
      expect(
        s.alicja.sendRemoteInput(const [RemoteInputOp.insert('cd')]),
        isTrue,
      );
      await czekaj(() => s.ujscie.tekst == 'abcd', 'po 409');
      expect(stan(s.alicja), OutgoingRemoteInputState.active);
      expect(s.alicja.outgoingRemoteInput.value!.reason, isNull);
      expect(s.bartek.incomingRemoteInput.value, isNotNull);

      await s.alicja.stopRemoteInput();
      expect(s.ujscie.tekst, 'abcd');
      expect(s.ujscie.wpisania, 2);
      expect(s.bartek.incomingRemoteInput.value, isNull);
    });

    test('409 w środku sesji: ten sam token i ciągła numeracja', () async {
      final s = await scena();
      final token = await zgoda(s.alicja, s.bartekUAlicji, 'po-409');
      Future<({int status, RemoteInputReply? odpowiedz})> paczka(
        int seq,
        String tekst,
      ) => wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'po-409',
        token: token,
        seq: seq,
        ops: [RemoteInputOp.insert(tekst)],
      );

      expect((await paczka(1, 'x')).odpowiedz!.applied, isTrue);
      s.bartek.debugDropIncomingSessions(s.alicja.identity.guid);

      final po = await paczka(2, 'y');
      expect(po.status, 200);
      expect(po.odpowiedz!.applied, isTrue);
      expect(po.odpowiedz!.duplicate, isFalse);
      final powtorka = await paczka(2, 'y');
      expect(powtorka.odpowiedz!.duplicate, isTrue);
      expect(s.ujscie.tekst, 'xy');
      expect(s.ujscie.wpisania, 2);
    });

    test(
      'karta pliku u odbiorcy wstrzymuje pisanie, po niej pisanie wraca',
      () async {
        final s = await scena();
        await s.alicja.startRemoteInput(s.bartekUAlicji);
        s.bartek.pendingOffers.value = const [
          PendingFileOffer(
            messageGuid: 'plik-1',
            peerName: 'Alicja',
            fileName: 'umowa.pdf',
            fileSize: 1024,
            resumeFrom: 0,
            conversationId: 1,
          ),
        ];

        expect(
          s.alicja.sendRemoteInput(const [
            RemoteInputOp.insert('x'),
            RemoteInputOp.action(),
          ]),
          isTrue,
        );
        await czekaj(
          () => stan(s.alicja) == OutgoingRemoteInputState.paused,
          'wstrzymanie',
        );
        expect(s.alicja.outgoingRemoteInput.value!.applied, isFalse);
        expect(s.ujscie.wpisania, 0);
        expect(s.ujscie.tekst, isEmpty);
        expect(s.bartek.incomingRemoteInput.value, isNotNull);

        s.bartek.pendingOffers.value = const [];
        expect(
          s.alicja.sendRemoteInput(const [RemoteInputOp.insert('y')]),
          isTrue,
        );
        await czekaj(() => s.ujscie.tekst == 'y', 'tekst po karcie');
        await czekaj(
          () => stan(s.alicja) == OutgoingRemoteInputState.active,
          'powrót do pisania',
        );
        expect(s.alicja.outgoingRemoteInput.value!.applied, isTrue);
        expect(s.ujscie.ops, const [RemoteInputOp.insert('y')]);
      },
    );

    test('ping przy wiszącej karcie trzyma wstrzymanie i nie gasi '
        '„wpisane"', () async {
      // Pingi co chwilę: każdy przynosi stan, żaden nie mówi nic o tekście.
      debugRemoteInputPingInterval = const Duration(milliseconds: 50);
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      expect(s.alicja.sendRemoteInput(const [RemoteInputOp.insert('a')]),
          isTrue);
      await czekaj(() => s.ujscie.tekst == 'a', 'tekst');
      expect(s.alicja.outgoingRemoteInput.value!.applied, isTrue);

      final przed = s.ujscie.wywolania.where((w) => w == 'status').length;
      await czekaj(
        () => s.ujscie.wywolania.where((w) => w == 'status').length > przed + 2,
        'pingi',
      );
      expect(s.alicja.outgoingRemoteInput.value!.applied, isTrue);
      expect(stan(s.alicja), OutgoingRemoteInputState.active);

      s.bartek.pendingPairings.value = const [
        PendingPairing(peerGuid: 'ktos', peerName: 'Ktoś', code: '123456'),
      ];
      await czekaj(
        () => stan(s.alicja) == OutgoingRemoteInputState.paused,
        'wstrzymanie od pingu',
      );
      // Kilka kolejnych pingów: karta wisi, więc wstrzymanie trwa.
      final teraz = s.ujscie.wywolania.where((w) => w == 'status').length;
      await czekaj(
        () => s.ujscie.wywolania.where((w) => w == 'status').length > teraz + 3,
        'pingi przy karcie',
      );
      expect(stan(s.alicja), OutgoingRemoteInputState.paused);

      s.bartek.pendingPairings.value = const [];
      await czekaj(
        () => stan(s.alicja) == OutgoingRemoteInputState.active,
        'powrót po karcie',
      );
      expect(s.ujscie.wpisania, 1);
    });

    test('paczka spoza zgody dostaje odmowę od razu, bez czekania na cudzą '
        'paczkę w toku', () async {
      final s = await scena();
      final celina = await instancja('Celina');
      await sparuj(celina, s.bartek);
      final bartekUCeliny = await rozmowca(celina, s.bartek);
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);

      // Paczka Alicji utyka w ujściu.
      s.ujscie.zawor = Completer<void>();
      expect(s.alicja.sendRemoteInput(const [RemoteInputOp.insert('x')]),
          isTrue);
      await s.ujscie.dotarla.future;

      final zegar = Stopwatch()..start();
      final obca = await wyslij(
        celina,
        bartekUCeliny,
        input: 'cudza',
        token: 'AAAAAAAAAAAAAAAAAAAAAA==',
        seq: 1,
        ops: const [RemoteInputOp.ping()],
      );
      zegar.stop();
      expect(obca.status, 403);
      expect(obca.odpowiedz!.reason, inputNoGrant);
      expect(zegar.elapsed, lessThan(const Duration(seconds: 1)),
          reason: 'odmowa nie stoi w kolejce za paczką Alicji');

      s.ujscie.zawor!.complete();
      await czekaj(() => s.ujscie.tekst == 'x', 'tekst Alicji');
    });

    test('Stop dochodzi, choć paczka w locie padła po drodze', () async {
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);

      // Paczka utyka u odbiorcy tak długo, że nadawca wyczerpuje próby
      // i uznaje łącze za zerwane. `stop` czekał w kolejce za nią.
      s.ujscie.zawor = Completer<void>();
      expect(s.alicja.sendRemoteInput(const [RemoteInputOp.insert('x')]),
          isTrue);
      await s.ujscie.dotarla.future;
      await s.alicja.stopRemoteInput();

      // Odbiorca odzyskuje głos: wpisuje zaległą paczkę, a `stop`, wysłany
      // osobno po zerwaniu, kończy zgodę.
      s.ujscie.zawor!.complete();
      await czekaj(
        () => s.bartek.incomingRemoteInput.value == null,
        'koniec zgody',
      );
      expect(s.ujscie.tekst, 'x');
      expect(s.ujscie.sesje.last, 'setSession:false');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('karta parowania u odbiorcy też wstrzymuje: applied false, '
        'reason paused', () async {
      final s = await scena();
      final token = await zgoda(s.alicja, s.bartekUAlicji, 'parowanie');
      s.bartek.pendingPairings.value = const [
        PendingPairing(peerGuid: 'ktos', peerName: 'Ktoś', code: '123456'),
      ];

      final wstrzymana = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'parowanie',
        token: token,
        seq: 1,
        ops: const [RemoteInputOp.insert('x'), RemoteInputOp.action()],
      );
      expect(wstrzymana.status, 200);
      expect(wstrzymana.odpowiedz!.ok, isTrue);
      expect(wstrzymana.odpowiedz!.applied, isFalse);
      expect(wstrzymana.odpowiedz!.reason, inputPaused);
      expect(s.ujscie.wpisania, 0);

      s.bartek.pendingPairings.value = const [];
      final dalej = await wyslij(
        s.alicja,
        s.bartekUAlicji,
        input: 'parowanie',
        token: token,
        seq: 2,
        ops: const [RemoteInputOp.insert('y')],
      );
      expect(dalej.odpowiedz!.applied, isTrue);
      expect(dalej.odpowiedz!.reason, isNull);
      expect(s.ujscie.tekst, 'y');
    });
  });

  group('koniec zgody w trakcie sesji', () {
    final konce = <String, Future<void> Function(_Scena s)>{
      'forgetPeer u odbiorcy': (s) async =>
          s.bartek.forgetPeer(await rozmowca(s.bartek, s.alicja)),
      'setPeerVerified(false) u odbiorcy': (s) async => s.bartek.db
          .setPeerVerified((await rozmowca(s.bartek, s.alicja)).id, false),
      'wyłączony odbiór': (s) => s.bartek.setRemoteInputReceive(false),
      'wyłączony dodatek': (s) => s.bartek.setKeyboardAddon(false),
      'odbiór zgaszony w bazie z pominięciem serwisu': (s) =>
          s.bartek.db.saveRemoteInputReceive(false),
    };

    for (final koniec in konce.entries) {
      test(
        '${koniec.key}: następna paczka dostaje 403, ujście bez zmian',
        () async {
          final s = await scena();
          expect(
            await s.alicja.startRemoteInput(s.bartekUAlicji),
            RemoteInputStart.accepted,
          );
          s.alicja.sendRemoteInput(const [RemoteInputOp.insert('a')]);
          await czekaj(() => s.ujscie.tekst == 'a', 'przed końcem');
          final wpisania = s.ujscie.wpisania;

          await koniec.value(s);
          expect(
            s.alicja.sendRemoteInput(const [RemoteInputOp.insert('b')]),
            isTrue,
          );
          await czekaj(
            () => stan(s.alicja) == OutgoingRemoteInputState.disconnected,
            'rozłączenie',
          );
          expect(s.alicja.outgoingRemoteInput.value!.reason, inputNoGrant);
          expect(s.ujscie.wpisania, wpisania);
          expect(s.ujscie.tekst, 'a');
          expect(s.bartek.incomingRemoteInput.value, isNull);
          expect(s.ujscie.sesje.last, 'setSession:false');
        },
      );
    }
  });

  group('kolejka nadawcy', () {
    test('dopełnienie: pojedynczy znak, kasowanie i ping mają tę samą długość',
        () {
      String paczka(List<RemoteInputOp> ops) => jsonEncode(padInputPayload(
            RemoteInputPacket(
              from: const DeviceIdentity(
                guid: 'guid-nadawcy',
                name: '',
                welcomeMessage: '',
                tcpPort: 47780,
              ),
              input: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
              token: 'AAAAAAAAAAAAAAAAAAAAAA==',
              seq: 7,
              ops: ops,
            ).toJson(),
          ));
      final dlugosci = {
        for (final ops in const [
          [RemoteInputOp.insert('a')],
          [RemoteInputOp.insert('ż')],
          [RemoteInputOp.insert('😀')],
          [RemoteInputOp.backspace()],
          [RemoteInputOp.delete(3)],
          [RemoteInputOp.action()],
          [RemoteInputOp.ping()],
          [RemoteInputOp.stop()],
        ])
          utf8.encode(paczka(ops)).length,
      };
      expect(dlugosci, {inputPadMinimum});
    });

    test('dopełnienie: odpowiedź z długimi nazwami spoza alfabetu łacińskiego '
        'mieści się w minimum', () {
      final cjk = '漢' * 64;
      final emoji = '😀' * 64;
      for (final nazwy in [
        (app: cjk, label: cjk),
        (app: emoji, label: cjk),
        (app: 'a' * 300, label: 'Ж' * 300),
      ]) {
        for (final pole in RemoteInputField.values) {
          final cel = RemoteInputTarget.fromJson({
            'active': true,
            'field': pole.name,
            'action': 'previous',
            'app': nazwy.app,
            'appLabel': nazwy.label,
            'ownApp': true,
            'locked': true,
            'elevated': true,
          });
          // Przycięte po całych znakach: para surogatów nigdy na pół.
          expect(isTypableText(cel.app), isTrue);
          expect(isTypableText(cel.appLabel), isTrue);
          final odpowiedzi = [
            RemoteInputReply(
              ok: true,
              input: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
              seq: 99999,
              applied: true,
              duplicate: true,
              reason: inputPaused,
              target: cel,
            ).toJson(),
            InputSessionReply(
              accepted: true,
              input: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
              token: 'AAAAAAAAAAAAAAAAAAAAAA==',
              target: cel,
            ).toJson(),
          ];
          for (final odpowiedz in odpowiedzi) {
            expect(utf8.encode(jsonEncode(padInputPayload(odpowiedz))).length,
                inputPadMinimum,
                reason: '${pole.name}: ${nazwy.app.runes.first}');
          }
        }
      }
    });

    test('sklejanie: to, co przyszło w czasie paczki w locie, jedzie jedną '
        'paczką', () async {
      final s = await scena();
      await s.alicja.startRemoteInput(s.bartekUAlicji);
      final zawor = s.ujscie.zawor = Completer<void>();

      expect(
        s.alicja.sendRemoteInput(const [RemoteInputOp.insert('a')]),
        isTrue,
      );
      await s.ujscie.dotarla.future;
      // Paczka z „a" stoi u odbiorcy, a nadawca pisze dalej.
      for (final op in const [
        RemoteInputOp.insert('b'),
        RemoteInputOp.insert('c'),
        RemoteInputOp.insert('d'),
        RemoteInputOp.backspace(),
        RemoteInputOp.backspace(2),
        RemoteInputOp.insert('e'),
        RemoteInputOp.delete(),
        RemoteInputOp.delete(),
      ]) {
        expect(s.alicja.sendRemoteInput([op]), isTrue);
      }
      s.ujscie.zawor = null;
      zawor.complete();
      await s.alicja.stopRemoteInput();

      expect(s.ujscie.paczki, const [
        [RemoteInputOp.insert('a')],
        [
          RemoteInputOp.insert('bcd'),
          RemoteInputOp.backspace(3),
          RemoteInputOp.insert('e'),
          RemoteInputOp.delete(2),
        ],
      ]);
      expect(s.ujscie.wpisania, 2);
    });

    test(
      'długie wklejenie dzieli się na paczki, para surogatów zostaje cała',
      () async {
        final s = await scena();
        await s.alicja.startRemoteInput(s.bartekUAlicji);
        final wklejka = '${'a' * (maxInputTextUnits - 1)}\u{1F600}${'b' * 100}';
        // Wysoka połówka emoji wypada dokładnie na ostatniej jednostce paczki.
        expect(
          wklejka.codeUnitAt(maxInputTextUnits - 1),
          inInclusiveRange(0xD800, 0xDBFF),
        );

        expect(
          s.alicja.sendRemoteInput([RemoteInputOp.insert(wklejka)]),
          isTrue,
        );
        await s.alicja.stopRemoteInput();

        expect(s.ujscie.paczki, hasLength(2));
        for (final paczka in s.ujscie.paczki) {
          final tekst = paczka.map((op) => op.text).join();
          expect(tekst.length, lessThanOrEqualTo(maxInputTextUnits));
          expect(isTypableText(tekst), isTrue);
        }
        expect(
          s.ujscie.paczki.first.single.text,
          'a' * (maxInputTextUnits - 1),
        );
        expect(s.ujscie.paczki.last.single.text, startsWith('\u{1F600}'));
        expect(s.ujscie.tekst, wklejka);
      },
    );

    test('długi tekst i długie kasowanie mieszczą się w limitach paczki', () async {
      final s = await scena();
      await s.alicja.startRemoteInput(s.bartekUAlicji);

      final wklejka = 'ą' * (2 * maxInputTextUnits + 1808);
      expect(s.alicja.sendRemoteInput([RemoteInputOp.insert(wklejka)]), isTrue);
      await czekaj(() => s.ujscie.tekst.length == wklejka.length, 'wklejka');
      expect(s.ujscie.paczki.map((paczka) => paczka.single.text.length), [
        maxInputTextUnits,
        maxInputTextUnits,
        1808,
      ]);
      expect(s.ujscie.tekst, wklejka);

      int suma(List<RemoteInputOp> paczka) =>
          paczka.fold(0, (razem, op) => razem + op.count);

      // Kasowanie dzieli się na operacje po najwyżej 64. Ile paczek, zależy
      // od tego, kiedy wróci odpowiedź na ostatnią wklejkę; kolejność i podział
      // operacji są zawsze te same.
      s.ujscie.paczki.clear();
      s.alicja.sendRemoteInput(const [RemoteInputOp.backspace(200)]);
      s.alicja.sendRemoteInput(const [RemoteInputOp.delete(70)]);
      await czekaj(() => suma(s.ujscie.ops) == 270, 'kasowanie');
      expect(s.ujscie.ops, const [
        RemoteInputOp.backspace(64),
        RemoteInputOp.backspace(64),
        RemoteInputOp.backspace(64),
        RemoteInputOp.backspace(8),
        RemoteInputOp.delete(64),
        RemoteInputOp.delete(6),
      ]);

      // A jedna paczka kasuje najwyżej maxInputDeletes znaków.
      s.ujscie.paczki.clear();
      s.alicja.sendRemoteInput(const [RemoteInputOp.backspace(5000)]);
      await czekaj(() => suma(s.ujscie.ops) == 5000, 'długie kasowanie');
      expect(s.ujscie.paczki.map(suma), [
        maxInputDeletes,
        5000 - maxInputDeletes,
      ]);
      for (final paczka in s.ujscie.paczki) {
        expect(paczka.length, lessThanOrEqualTo(maxInputOps));
        expect(
          paczka.map((op) => op.count),
          everyElement(lessThanOrEqualTo(maxInputDeleteRun)),
        );
      }
    });

    test(
      'kolejka ponad maxQueuedInputUnits: false i nic z tego nie idzie',
      () async {
        final s = await scena();
        // Bez sesji nic nie wchodzi do kolejki.
        expect(
          s.alicja.sendRemoteInput(const [RemoteInputOp.insert('a')]),
          isFalse,
        );
        await s.alicja.startRemoteInput(s.bartekUAlicji);

        // Za długie wklejenie odpada w całości, razem z tym, co szło przed nim.
        expect(
          s.alicja.sendRemoteInput([
            const RemoteInputOp.insert('c'),
            RemoteInputOp.insert('d' * maxQueuedInputUnits),
          ]),
          isFalse,
        );

        final zawor = s.ujscie.zawor = Completer<void>();
        s.alicja.sendRemoteInput(const [RemoteInputOp.insert('x')]);
        await s.ujscie.dotarla.future;
        // Kolejka pełna co do jednostki.
        expect(
          s.alicja.sendRemoteInput([
            RemoteInputOp.insert('a' * maxQueuedInputUnits),
          ]),
          isTrue,
        );
        expect(
          s.alicja.sendRemoteInput(const [RemoteInputOp.insert('b')]),
          isFalse,
        );
        s.ujscie.zawor = null;
        zawor.complete();
        await s.alicja.stopRemoteInput();

        expect(s.ujscie.tekst, 'x${'a' * maxQueuedInputUnits}');
        for (final paczka in s.ujscie.paczki) {
          expect(
            paczka.map((op) => op.text).join().length,
            lessThanOrEqualTo(maxInputTextUnits),
          );
        }
      },
    );

    test(
      'tekst normalizowany przed wysyłką: CRLF, tab i znaki sterujące',
      () async {
        final s = await scena();
        await s.alicja.startRemoteInput(s.bartekUAlicji);
        expect(
          s.alicja.sendRemoteInput(const [
            RemoteInputOp.insert('a\r\nb\tc\u0007d\re\uD800f\u0085g'),
          ]),
          isTrue,
        );
        // Sam znak sterujący nie zostawia niczego do wysłania.
        s.alicja.sendRemoteInput(const [RemoteInputOp.insert('\u0001\u0002')]);
        await s.alicja.stopRemoteInput();

        expect(s.ujscie.ops, const [RemoteInputOp.insert('a\nb cd\nefg')]);
      },
    );
  });
}
