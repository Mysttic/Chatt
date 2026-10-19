import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:chatt/core/remote_input.dart';
import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_log.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/typing_journal.dart';

const _notatki = RemoteInputTarget(
  active: true,
  field: RemoteInputField.text,
  app: 'com.example.notes',
  appLabel: 'Notatki',
);

/// Ujście w pamięci: zapisuje każdą paczkę, która dotarła do wpisania,
/// i odpowiada sztucznym celem.
class _Ujscie implements RemoteInputSink {
  final paczki = <List<RemoteInputOp>>[];
  final wywolania = <String>[];
  RemoteInputTarget cel = _notatki;

  /// Co `apply` mówi o wpisaniu: `false` to pole, które zniknęło w trakcie.
  bool wpisuj = true;

  /// Zawór: gdy jest, `apply` po zapisaniu paczki czeka na niego, a
  /// [dotarla] mówi, że paczka już się wpisuje.
  Completer<void>? zawor;
  final dotarla = Completer<void>();

  @override
  bool supported = true;

  List<RemoteInputOp> get ops => [for (final paczka in paczki) ...paczka];

  String get tekst => ops
      .where((op) => op.kind == RemoteInputOpKind.insert)
      .map((op) => op.text)
      .join();

  @override
  Future<RemoteInputTarget> status() async {
    wywolania.add('status');
    return cel;
  }

  @override
  Future<RemoteInputApplied> apply(List<RemoteInputOp> nowe) async {
    wywolania.add('apply');
    paczki.add(List.of(nowe));
    final c = zawor;
    if (c != null) {
      if (!dotarla.isCompleted) dotarla.complete();
      await c.future;
    }
    return (applied: wpisuj, target: cel);
  }

  @override
  Future<void> holdOwnApp(bool on) async {}

  @override
  Future<void> setSession({required bool active, String peerName = ''}) async {
    wywolania.add('setSession:$active');
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

/// Historia pisania po obu stronach zdalnej klawiatury, między dwiema
/// prawdziwymi instancjami, przez prawdziwe gniazda: nadawca zapisuje to,
/// co wysłał, odbiorca to, co przyszło, a tekst z pola hasła i pola
/// nieznanego rodzaju zostaje po obu stronach samą liczbą znaków.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory katalog;
  late Duration pingi;
  final uruchomione = <AppServices>[];

  setUp(() {
    katalog = Directory.systemTemp.createTempSync('chatt_historia_pisania_');
    pingi = debugRemoteInputPingInterval;
    // Testy liczą paczki i kawałki historii: pingi by je zaśmiecały.
    debugRemoteInputPingInterval = const Duration(hours: 1);
  });

  tearDown(() async {
    for (final s in uruchomione.reversed) {
      await s.dispose();
    }
    uruchomione.clear();
    debugRemoteInputPingInterval = pingi;
    katalog.deleteSync(recursive: true);
  });

  /// [plik] zostawia bazę na dysku: po zamknięciu instancji da się ją
  /// otworzyć jeszcze raz i sprawdzić, co zapisało zamknięcie.
  Future<AppServices> instancja(
    String nazwa, {
    RemoteInputPolicy? polityka,
    _Ujscie? ujscie,
    File? plik,
  }) async {
    final s = await AppServices.start(
      executor: plik == null ? NativeDatabase.memory() : NativeDatabase(plik),
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
    bool naDysku = false,
  }) async {
    final ujscie = _Ujscie();
    final alicja = await instancja(
      'Alicja',
      plik: naDysku ? File(p.join(katalog.path, 'alicja.db')) : null,
    );
    final bartek = await instancja(
      'Bartek',
      polityka: karta ? null : polityka,
      ujscie: ujscie,
      plik: naDysku ? File(p.join(katalog.path, 'bartek.db')) : null,
    );
    await sparuj(alicja, bartek);
    expect(await alicja.setKeyboardAddon(true), isTrue);
    if (dodatek) {
      expect(await bartek.setKeyboardAddon(true), isTrue);
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

  Future<void> czekajNa(Future<bool> Function() warunek,
      [String opis = '']) async {
    final koniec = DateTime.now().add(const Duration(seconds: 10));
    while (!await warunek()) {
      if (DateTime.now().isAfter(koniec)) fail('nie doczekano: $opis');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  OutgoingRemoteInputState? stan(AppServices s) =>
      s.outgoingRemoteInput.value?.state;

  /// Sesje z historii pisania, po zapisaniu wszystkiego, co czeka w pamięci.
  Future<List<TypingSession>> sesje(AppServices s) async {
    await s.typingJournal.flush();
    return s.db.allTypingSessions();
  }

  Future<List<TypingEntry>> kawalki(AppServices s) async {
    await s.typingJournal.flush();
    return s.db.allTypingEntries();
  }

  /// Kawałki jako `[skutek, rodzaj pola, ukryty, operacje]` (listy, bo
  /// `expect` porównuje je element po elemencie). Sąsiednie kawałki tej
  /// samej sesji, aplikacji, pola i skutku są sklejone: na wolnej maszynie
  /// sekunda ciszy między paczkami zapisuje kawałek wcześniej, a treść
  /// zostaje ta sama.
  Future<List<List<Object>>> opis(AppServices s) async {
    final wynik = <List<Object>>[];
    final ops = <List<TypingOp>>[];
    TypingEntry? poprzedni;
    for (final k in await kawalki(s)) {
      final nowe = TypingOp.decode(k.ops);
      final p = poprzedni;
      if (p != null &&
          p.sessionId == k.sessionId &&
          p.app == k.app &&
          p.field == k.field &&
          p.status == k.status &&
          p.masked == k.masked) {
        for (final op in nowe) {
          appendTypingOp(ops.last, op);
        }
      } else {
        ops.add(List.of(nowe));
        wynik.add([k.status, k.field, k.masked, ops.last]);
      }
      poprzedni = k;
    }
    return wynik;
  }

  Future<List<AppLogEntry>> dziennik(AppServices s) async {
    await s.log.flush();
    return s.db.allLogEntries();
  }

  /// Komunikaty klawiatury z dziennika aplikacji.
  Future<List<String>> zdarzenia(AppServices s) async => [
        for (final wpis in await dziennik(s))
          if (wpis.area == LogArea.keyboard) wpis.message,
      ];

  /// Wszystko, co [s] trzyma w historii pisania i w dzienniku, jednym
  /// napisem: do szukania tekstu, którego tam być nie może.
  Future<String> wszystko(AppServices s) async => [
        ...await sesje(s),
        ...await kawalki(s),
        ...await dziennik(s),
      ].map((wiersz) => '$wiersz').join('\n');

  /// Wysyła [ops] i czeka, aż nadawca dostanie odpowiedź na [ktora] z kolei
  /// paczkę z pisaniem.
  Future<void> wpisz(_Scena s, List<RemoteInputOp> ops, int ktora) async {
    expect(s.alicja.sendRemoteInput(ops), isTrue);
    await czekaj(
      () => s.alicja.outgoingRemoteInput.value?.typedReplies == ktora,
      'odpowiedź na paczkę $ktora',
    );
  }

  /// Prośba o sesję złożona ręcznie, pod wybranym identyfikatorem.
  Future<({int status, InputSessionReply? odpowiedz})> popros(
    AppServices nadawca,
    Peer odbiorca,
    String input,
  ) async {
    final wynik = await nadawca.debugSendSealed(
      odbiorca,
      '/input-session',
      InputSessionRequest(
        from: nadawca.identity,
        op: inputSessionRequest,
        input: input,
      ).toJson(),
    );
    return (
      status: wynik.status,
      odpowiedz: InputSessionReply.fromJson(wynik.reply, input: input),
    );
  }

  group('sesja po obu stronach', () {
    test('ten sam identyfikator, kierunki, tekst i powód końca', () async {
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('Zażółć gęślą')], 1);
      await wpisz(s, const [RemoteInputOp.backspace(2)], 2);
      await wpisz(
        s,
        const [RemoteInputOp.insert('ą jaźń'), RemoteInputOp.action()],
        3,
      );
      await s.alicja.stopRemoteInput();

      final uAlicji = (await sesje(s.alicja)).single;
      final uBartka = (await sesje(s.bartek)).single;
      expect(uAlicji.direction, MessageDirection.outgoing);
      expect(uBartka.direction, MessageDirection.incoming);
      expect(uAlicji.inputId, uBartka.inputId,
          reason: 'po identyfikatorze da się zestawić obie strony');
      expect(uAlicji.peerGuid, s.bartek.identity.guid);
      expect(uAlicji.peerName, 'Bartek');
      expect(uBartka.peerGuid, s.alicja.identity.guid);
      expect(uBartka.peerName, 'Alicja');
      expect(uAlicji.result, TypingResult.accepted);
      expect(uBartka.result, TypingResult.accepted);
      expect(uAlicji.endReason, TypingEnd.stoppedHere);
      expect(uBartka.endReason, TypingEnd.stoppedByPeer);
      expect(uAlicji.endedAt, isNotNull);
      expect(uBartka.endedAt, isNotNull);

      const oczekiwane = [
        TypingOp.insert('Zażółć gęślą'),
        TypingOp.backspace(2),
        TypingOp.insert('ą jaźń'),
        TypingOp.action(),
      ];
      for (final strona in [s.alicja, s.bartek]) {
        final wiersze = await kawalki(strona);
        expect(wiersze.map((k) => (k.app, k.appLabel)).toSet(),
            {('com.example.notes', 'Notatki')});
        expect(wiersze.fold<int>(0, (suma, k) => suma + k.chars), 18);
        final kawalek = (await opis(strona)).single;
        expect(kawalek, ['typed', 'text', false, oczekiwane]);
        expect(reconstructTyping(kawalek[3] as List<TypingOp>),
            'Zażółć gęśą jaźń\n');
      }
      expect(s.ujscie.tekst, 'Zażółć gęśląą jaźń');
    });

    test('wynik prośby: zgoda z karty, „nie pytaj więcej", potem bez karty',
        () async {
      final s = await scena(karta: true);

      Future<void> zKarta({required bool remember}) async {
        final start = s.alicja.startRemoteInput(s.bartekUAlicji);
        await czekaj(
          () => s.bartek.pendingRemoteInput.value.isNotEmpty,
          'karta u Bartka',
        );
        s.bartek.respondToRemoteInput(
          s.bartek.pendingRemoteInput.value.single.id,
          accept: true,
          remember: remember,
        );
        expect(await start, RemoteInputStart.accepted);
        await s.alicja.stopRemoteInput();
      }

      await zKarta(remember: false);
      await zKarta(remember: true);
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await s.alicja.stopRemoteInput();

      expect([for (final w in await sesje(s.bartek)) w.result], [
        TypingResult.accepted,
        TypingResult.acceptedAlways,
        TypingResult.automatic,
      ]);
      expect([for (final w in await sesje(s.alicja)) w.result], [
        TypingResult.accepted,
        TypingResult.accepted,
        TypingResult.accepted,
      ]);
      for (final strona in [s.alicja, s.bartek]) {
        expect(
          [for (final w in await sesje(strona)) w.endReason],
          everyElement(isNotNull),
        );
      }
    });
  });

  group('ukrywanie', () {
    test('pole hasła i pole nieznanego rodzaju: po obu stronach sama liczba '
        'znaków, tekstu nie ma nigdzie', () async {
      const haslo = RemoteInputTarget(
        active: true,
        field: RemoteInputField.password,
        app: 'com.example.bank',
        appLabel: 'Bank',
      );
      const nieznane = RemoteInputTarget(
        active: true,
        field: RemoteInputField.none,
        app: 'com.example.bank',
        appLabel: 'Bank',
      );
      const tekst = RemoteInputTarget(
        active: true,
        field: RemoteInputField.text,
        app: 'com.example.bank',
        appLabel: 'Bank',
      );
      final s = await scena();
      s.ujscie.cel = haslo;
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);

      await wpisz(s, const [RemoteInputOp.insert('Tajne123!')], 1);
      s.ujscie.cel = nieznane;
      await wpisz(s, const [RemoteInputOp.insert('Sekret')], 2);
      // Pierwsza paczka po polu nieznanego rodzaju zostaje ukryta, choć
      // trafiła już w pole tekstowe: jej początek mógł wpisać się wcześniej.
      s.ujscie.cel = tekst;
      await wpisz(s, const [RemoteInputOp.insert('jawny')], 3);
      await wpisz(s, const [RemoteInputOp.insert('widoczny')], 4);
      await s.alicja.stopRemoteInput();
      expect(s.ujscie.tekst, 'Tajne123!Sekretjawnywidoczny');

      for (final strona in [s.alicja, s.bartek]) {
        expect(await opis(strona), [
          ['typed', 'password', true, const [TypingOp.hidden(9)]],
          ['typed', 'none', true, const [TypingOp.hidden(11)]],
          ['typed', 'text', false, const [TypingOp.insert('widoczny')]],
        ]);
        final wiersze = await kawalki(strona);
        int znaki(bool ukryte) => wiersze
            .where((k) => k.masked == ukryte)
            .fold(0, (suma, k) => suma + k.chars);
        expect(znaki(true), 20);
        expect(znaki(false), 8);
        final ops = [for (final k in wiersze) ...TypingOp.decode(k.ops)];
        expect(reconstructTyping(ops), '${'•' * 20}widoczny');

        final calosc = await wszystko(strona);
        for (final tajne in ['Tajne123!', 'Tajne', 'Sekret', 'jawny']) {
          expect(calosc, isNot(contains(tajne)), reason: tajne);
        }
        expect(calosc, contains('widoczny'),
            reason: 'szukanie widzi zawartość wierszy');
      }
    });
  });

  group('skutek paczki', () {
    test('karta u odbiorcy: wstrzymane, pole bez wpisania: niewpisane',
        () async {
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
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
      await wpisz(
        s,
        const [RemoteInputOp.insert('x'), RemoteInputOp.action()],
        1,
      );
      expect(stan(s.alicja), OutgoingRemoteInputState.paused);
      s.bartek.pendingOffers.value = const [];

      s.ujscie.wpisuj = false;
      await wpisz(s, const [RemoteInputOp.insert('z')], 2);
      s.ujscie.wpisuj = true;
      await wpisz(s, const [RemoteInputOp.insert('y')], 3);
      await s.alicja.stopRemoteInput();

      for (final strona in [s.alicja, s.bartek]) {
        expect(await opis(strona), [
          [
            'paused',
            'text',
            false,
            const [TypingOp.insert('x'), TypingOp.action()],
          ],
          ['notTyped', 'text', false, const [TypingOp.insert('z')]],
          ['typed', 'text', false, const [TypingOp.insert('y')]],
        ]);
      }
    });
  });

  group('koniec sesji u odbiorcy', () {
    final konce = <String, (String, Future<void> Function(_Scena s))>{
      'Stop u odbiorcy': (
        TypingEnd.stoppedHere,
        (s) async => s.bartek.stopIncomingRemoteInput(),
      ),
      'wyłączony odbiór': (
        TypingEnd.receiveOff,
        (s) => s.bartek.setRemoteInputReceive(false),
      ),
      'wyłączony dodatek': (
        TypingEnd.addonOff,
        (s) => s.bartek.setKeyboardAddon(false),
      ),
      'rozmówca usunięty z listy': (
        TypingEnd.peerRemoved,
        (s) async => s.bartek.forgetPeer(await rozmowca(s.bartek, s.alicja)),
      ),
      'tarcza zdjęta w bazie': (
        TypingEnd.notAllowed,
        (s) async => s.bartek.db
            .setPeerVerified((await rozmowca(s.bartek, s.alicja)).id, false),
      ),
    };

    for (final koniec in konce.entries) {
      test(
        '${koniec.key}: u odbiorcy ${koniec.value.$1}, u nadawcy '
        'stoppedByPeer po następnej paczce',
        () async {
          final s = await scena();
          expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
              RemoteInputStart.accepted);
          await wpisz(s, const [RemoteInputOp.insert('a')], 1);

          await koniec.value.$2(s);
          expect(s.alicja.sendRemoteInput(const [RemoteInputOp.insert('b')]),
              isTrue);
          await czekaj(
            () => stan(s.alicja) == OutgoingRemoteInputState.disconnected,
            'rozłączenie',
          );
          await s.alicja.stopRemoteInput();

          final uBartka = (await sesje(s.bartek)).single;
          expect(uBartka.endReason, koniec.value.$1);
          expect(await opis(s.bartek), [
            ['typed', 'text', false, const [TypingOp.insert('a')]],
          ]);
          final uAlicji = (await sesje(s.alicja)).single;
          expect(uAlicji.endReason, TypingEnd.stoppedByPeer);
          expect(await opis(s.alicja), [
            ['typed', 'text', false, const [TypingOp.insert('a')]],
            // Odmowa nie niesie celu: tekst bez odpowiedzi zostaje ukryty.
            ['refused', 'none', true, const [TypingOp.hidden(1)]],
          ]);
        },
      );
    }

    test('Stop u odbiorcy: nadawca bez pisania dowiaduje się z pingu',
        () async {
      debugRemoteInputPingInterval = const Duration(milliseconds: 50);
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('a')], 1);

      s.bartek.stopIncomingRemoteInput();
      await czekaj(
        () => stan(s.alicja) == OutgoingRemoteInputState.disconnected,
        'rozłączenie z pingu',
      );

      expect((await sesje(s.bartek)).single.endReason, TypingEnd.stoppedHere);
      expect((await sesje(s.alicja)).single.endReason,
          TypingEnd.stoppedByPeer);
      // Ping niczego nie wpisuje, więc nie zostawia kawałka.
      expect(await opis(s.alicja), [
        ['typed', 'text', false, const [TypingOp.insert('a')]],
      ]);
    });
  });

  group('koniec sesji u nadawcy', () {
    test('wyłączony dodatek: addonOff u nadawcy, stoppedByPeer u odbiorcy',
        () async {
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('a')], 1);
      expect(await s.alicja.setKeyboardAddon(false), isFalse);
      await czekaj(
        () => s.bartek.incomingRemoteInput.value == null,
        'koniec zgody u Bartka',
      );
      await czekajNa(
        () async => (await sesje(s.alicja)).single.endReason != null,
        'koniec sesji u Alicji',
      );

      expect((await sesje(s.alicja)).single.endReason, TypingEnd.addonOff);
      expect((await sesje(s.bartek)).single.endReason,
          TypingEnd.stoppedByPeer);
    });

    test('nowa sesja: poprzednia kończy się replaced', () async {
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('pierwsza')], 1);
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('druga')], 1);
      await s.alicja.stopRemoteInput();
      await czekajNa(
        () async => (await sesje(s.alicja)).every((w) => w.endReason != null),
        'koniec obu sesji u Alicji',
      );

      final uAlicji = await sesje(s.alicja);
      final uBartka = await sesje(s.bartek);
      expect([for (final w in uAlicji) w.endReason],
          [TypingEnd.replaced, TypingEnd.stoppedHere]);
      expect([for (final w in uAlicji) w.inputId],
          [for (final w in uBartka) w.inputId]);
      // Stop starej sesji i nowa prośba jadą osobno: odbiorca kończy starą
      // zgodę tym, co przyjdzie pierwsze.
      expect(uBartka.first.endReason,
          anyOf(TypingEnd.stoppedByPeer, TypingEnd.replaced));
      expect(uBartka.last.endReason, TypingEnd.stoppedByPeer);
      for (final strona in [s.alicja, s.bartek]) {
        final kawalkiStrony = await kawalki(strona);
        expect(
          [for (final k in kawalkiStrony) TypingOp.decode(k.ops)],
          const [
            [TypingOp.insert('pierwsza')],
            [TypingOp.insert('druga')],
          ],
        );
        expect(kawalkiStrony.first.sessionId, isNot(kawalkiStrony.last.sessionId));
      }
    });

    test('rozmówca usunięty z listy: peerRemoved', () async {
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('a')], 1);
      await s.alicja.forgetPeer(s.bartekUAlicji);
      await czekajNa(
        () async => (await sesje(s.alicja)).single.endReason != null,
        'koniec sesji u Alicji',
      );
      expect((await sesje(s.alicja)).single.endReason, TypingEnd.peerRemoved);
    });

    test('zamknięcie aplikacji: appClosed po obu stronach, kolejka jako '
        'niewysłana', () async {
      final s = await scena(naDysku: true);
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('a')], 1);
      expect((await sesje(s.bartek)).single.endReason, isNull);

      // Zamyka instancję i czyta jej historię z bazy otwartej na nowo.
      Future<(TypingSession, List<List<Object>>)> poZamknieciu(
          AppServices kto, String plik) async {
        uruchomione.remove(kto);
        await kto.dispose();
        final baza = ChattDb(NativeDatabase(File(p.join(katalog.path, plik))));
        try {
          return (
            (await baza.allTypingSessions()).single,
            [
              for (final k in await baza.allTypingEntries())
                [k.status, TypingOp.decode(k.ops)],
            ],
          );
        } finally {
          await baza.close();
        }
      }

      // Bartek zamyka aplikację w trakcie zgody.
      final (uBartka, kawalkiBartka) =
          await poZamknieciu(s.bartek, 'bartek.db');
      expect(uBartka.endReason, TypingEnd.appClosed);
      expect(uBartka.endedAt, isNotNull);
      expect(kawalkiBartka, [
        ['typed', const [TypingOp.insert('a')]],
      ]);

      // Alicja zamyka aplikację z pisaniem w drodze: Bartka już nie ma,
      // więc jedna paczka jest w locie, a reszta czeka za nią w kolejce.
      expect(s.alicja.sendRemoteInput(const [RemoteInputOp.insert('b')]),
          isTrue);
      expect(s.alicja.sendRemoteInput(const [RemoteInputOp.insert('c')]),
          isTrue);
      final (uAlicji, kawalkiAlicji) =
          await poZamknieciu(s.alicja, 'alicja.db');
      expect(uAlicji.endReason, TypingEnd.appClosed);
      expect(kawalkiAlicji, [
        ['typed', const [TypingOp.insert('a')]],
        // Bez odpowiedzi rodzaj pola jest nieznany: tekst zostaje ukryty.
        ['unconfirmed', const [TypingOp.hidden(1)]],
        ['unsent', const [TypingOp.hidden(1)]],
      ]);
    });
  });

  group('koniec sesji w trakcie paczki', () {
    test('zerwane łącze: paczka bez odpowiedzi ukryta, koniec linkLost',
        () async {
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('login')], 1);
      // Bartek znika bez słowa: następna paczka nie dostaje odpowiedzi.
      uruchomione.remove(s.bartek);
      await s.bartek.dispose();
      expect(s.alicja.sendRemoteInput(const [RemoteInputOp.insert('hasło1')]),
          isTrue);
      await czekaj(
        () => stan(s.alicja) == OutgoingRemoteInputState.disconnected,
        'rozłączenie',
      );
      await czekajNa(
        () async => (await sesje(s.alicja)).single.endReason != null,
        'koniec sesji u Alicji',
      );

      expect((await sesje(s.alicja)).single.endReason, TypingEnd.linkLost);
      expect(await opis(s.alicja), [
        ['typed', 'text', false, const [TypingOp.insert('login')]],
        // Rodzaj pola po paczce jest nieznany: zostaje sama liczba znaków.
        ['unconfirmed', 'none', true, const [TypingOp.hidden(6)]],
      ]);
      expect(await wszystko(s.alicja), isNot(contains('hasło1')));
      expect(await zdarzenia(s.alicja),
          contains(startsWith('Typing packet unconfirmed')));
    });

    test('Stop z tekstem w tej samej paczce: tekst wpisany po obu stronach',
        () async {
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      final zawor = s.ujscie.zawor = Completer<void>();
      expect(s.alicja.sendRemoteInput(const [RemoteInputOp.insert('a')]),
          isTrue);
      await s.ujscie.dotarla.future;
      // „b" czeka w kolejce za paczką w locie i jedzie razem ze Stopem.
      expect(s.alicja.sendRemoteInput(const [RemoteInputOp.insert('b')]),
          isTrue);
      s.ujscie.zawor = null;
      final stop = s.alicja.stopRemoteInput();
      zawor.complete();
      await stop;
      await czekajNa(
        () async => (await sesje(s.bartek)).single.endReason != null,
        'koniec zgody u Bartka',
      );

      expect(s.ujscie.tekst, 'ab');
      for (final strona in [s.alicja, s.bartek]) {
        expect(await opis(strona), [
          ['typed', 'text', false, const [TypingOp.insert('ab')]],
        ]);
      }
      expect((await sesje(s.alicja)).single.endReason, TypingEnd.stoppedHere);
      expect((await sesje(s.bartek)).single.endReason,
          TypingEnd.stoppedByPeer);
    });

    for (final (nazwa, koniec, zakoncz) in [
      (
        'Stop u odbiorcy',
        TypingEnd.stoppedHere,
        (AppServices b) async => b.stopIncomingRemoteInput(),
      ),
      (
        'wyłączony dodatek',
        TypingEnd.addonOff,
        (AppServices b) => b.setKeyboardAddon(false),
      ),
    ]) {
      test('$nazwa w trakcie wpisywania: paczka zapisana, potem $koniec',
          () async {
        final s = await scena();
        expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
            RemoteInputStart.accepted);
        final zawor = s.ujscie.zawor = Completer<void>();
        expect(s.alicja.sendRemoteInput(const [RemoteInputOp.insert('x')]),
            isTrue);
        await s.ujscie.dotarla.future;
        final konczy = zakoncz(s.bartek);
        zawor.complete();
        await konczy;
        await czekajNa(
          () async => (await sesje(s.bartek)).single.endReason != null,
          'koniec zgody u Bartka',
        );

        expect((await sesje(s.bartek)).single.endReason, koniec);
        expect(await opis(s.bartek), [
          ['typed', 'text', false, const [TypingOp.insert('x')]],
        ]);
      });
    }
  });

  group('prośba bez sesji', () {
    test('odmowa i wyłączony odbiór: wiersz po obu stronach, od razu '
        'zakończony', () async {
      final s = await scena(polityka: rejectAllRemoteInput);
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.rejected);
      expect(await s.bartek.setRemoteInputReceive(false), isFalse);
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.notEnabled);

      final uAlicji = await sesje(s.alicja);
      final uBartka = await sesje(s.bartek);
      expect([for (final w in uAlicji) w.result],
          [TypingResult.rejected, TypingResult.notEnabled]);
      expect([for (final w in uBartka) w.result],
          [TypingResult.rejected, TypingResult.notEnabled]);
      expect([for (final w in uAlicji) w.inputId],
          [for (final w in uBartka) w.inputId]);
      for (final w in [...uAlicji, ...uBartka]) {
        expect(w.endedAt, w.startedAt);
        expect(w.endReason, isNull);
      }
      expect(uAlicji.every((w) => w.direction == MessageDirection.outgoing),
          isTrue);
      expect(uBartka.every((w) => w.direction == MessageDirection.incoming),
          isTrue);
      expect(await kawalki(s.alicja), isEmpty);
      expect(await kawalki(s.bartek), isEmpty);
      expect(s.ujscie.wywolania.where((w) => !w.startsWith('setImeEnabled')),
          isEmpty);
    });

    test('prośba wycofana przy wiszącej karcie: cancelled po obu stronach',
        () async {
      final s = await scena(karta: true);
      final start = s.alicja.startRemoteInput(s.bartekUAlicji);
      await czekaj(
        () => s.bartek.pendingRemoteInput.value.isNotEmpty,
        'karta u Bartka',
      );
      await s.alicja.stopRemoteInput();
      expect(await start, RemoteInputStart.cancelled);
      await czekajNa(
        () async => (await sesje(s.bartek)).isNotEmpty,
        'odmowa u Bartka',
      );

      expect((await sesje(s.alicja)).single.result, TypingResult.cancelled);
      expect((await sesje(s.bartek)).single.result, TypingResult.cancelled);
    });

    test('niezweryfikowany nadawca: nic w historii, ostrzeżenie w dzienniku',
        () async {
      final s = await scena(karta: true);
      final dawid = await instancja('Dawid');
      final bartekUDawida = (await dawid.addPeerByAddress(
        '127.0.0.1',
        s.bartek.server.port!,
      ))!;
      expect(await dawid.setKeyboardAddon(true), isTrue);
      expect(await dawid.startRemoteInput(bartekUDawida),
          RemoteInputStart.notVerified);
      final wynik = await popros(dawid, bartekUDawida, 'dawid-1');
      expect(wynik.status, 403);
      expect(wynik.odpowiedz!.reason, inputRejected);

      expect(await sesje(s.bartek), isEmpty);
      expect(await sesje(dawid), isEmpty);
      expect(
        await zdarzenia(s.bartek),
        contains('Typing request from an unverified device refused'),
      );
    });
  });

  group('wyłączony zapis', () {
    test('dodatek wyłączony: ta strona nic nie zapisuje', () async {
      final s = await scena(dodatek: false);
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.notEnabled);
      expect(await sesje(s.bartek), isEmpty);
      expect((await sesje(s.alicja)).single.result, TypingResult.notEnabled);

      expect(await s.alicja.setKeyboardAddon(false), isFalse);
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.addonOff);
      expect(await sesje(s.alicja), hasLength(1));
    });

    test('przełącznik „Zapisuj historię pisania" zgaszony: nic się nie '
        'zapisuje', () async {
      final s = await scena();
      expect(s.alicja.typingHistory.value, isTrue,
          reason: 'domyślnie włączony');
      expect(await s.alicja.setTypingHistory(false), isFalse);
      expect(await s.bartek.setTypingHistory(false), isFalse);
      expect((await s.bartek.db.getSettings())!.typingHistory, isFalse);

      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('bez śladu')], 1);
      await s.alicja.stopRemoteInput();
      expect(await sesje(s.alicja), isEmpty);
      expect(await sesje(s.bartek), isEmpty);
      expect(await kawalki(s.bartek), isEmpty);

      // Zgaszony tylko u Bartka: Alicja zapisuje, Bartek dalej nie.
      expect(await s.alicja.setTypingHistory(true), isTrue);
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('tylko u Alicji')], 1);
      await s.alicja.stopRemoteInput();
      expect(await opis(s.alicja), [
        ['typed', 'text', false, const [TypingOp.insert('tylko u Alicji')]],
      ]);
      expect(await sesje(s.bartek), isEmpty);
      expect(s.ujscie.tekst, 'bez śladutylko u Alicji');
    });
  });

  group('kasowanie', () {
    test('retencja kasuje stare sesje i zostawia świeże', () async {
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('dzisiaj')], 1);
      await s.alicja.stopRemoteInput();

      // Sesja sprzed dziesięciu dni, wprost w bazie Bartka.
      final dawno = DateTime.now().subtract(const Duration(days: 10));
      final stara = await s.bartek.db.insertTypingSession(
        TypingSessionsCompanion.insert(
          inputId: 'stara',
          direction: MessageDirection.incoming,
          peerGuid: s.alicja.identity.guid,
          peerName: 'Alicja',
          startedAt: dawno,
          endedAt: Value(dawno),
          result: TypingResult.accepted,
          endReason: const Value(TypingEnd.stoppedByPeer),
        ),
      );
      await s.bartek.db.insertTypingEntries([
        TypingEntriesCompanion.insert(
          sessionId: stara,
          at: dawno,
          field: RemoteInputField.text.name,
          status: TypingStatus.typed.name,
          ops: TypingOp.encode(const [TypingOp.insert('stare')]),
        ),
      ]);

      await s.bartek.applyRetention(0);
      expect(await sesje(s.bartek), hasLength(2),
          reason: 'zero znaczy „nie kasuj"');
      await s.bartek.applyRetention(30);
      expect(await sesje(s.bartek), hasLength(2));

      await s.bartek.applyRetention(7);
      final zostalo = await sesje(s.bartek);
      expect(zostalo.single.inputId, isNot('stara'));
      expect(await opis(s.bartek), [
        ['typed', 'text', false, const [TypingOp.insert('dzisiaj')]],
      ]);
    });

    test('„Wyczyść historię pisania" w trakcie sesji: dalsze pisanie bez '
        'śladu, następna sesja znowu zapisana', () async {
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('przed')], 1);

      expect(await s.bartek.clearTypingHistory(), 1);
      expect(await sesje(s.bartek), isEmpty);
      await wpisz(s, const [RemoteInputOp.insert('po')], 2);
      await s.alicja.stopRemoteInput();
      expect(await sesje(s.bartek), isEmpty);
      expect(await kawalki(s.bartek), isEmpty);
      // Alicja nic nie czyściła: jej historia zostaje.
      expect(await opis(s.alicja), [
        ['typed', 'text', false, const [TypingOp.insert('przedpo')]],
      ]);

      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('nowa')], 1);
      await s.alicja.stopRemoteInput();
      expect(await opis(s.bartek), [
        ['typed', 'text', false, const [TypingOp.insert('nowa')]],
      ]);
    });

    test('„Wyczyść historię" kasuje też historię pisania', () async {
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(s, const [RemoteInputOp.insert('cokolwiek')], 1);
      await s.alicja.stopRemoteInput();
      expect(await sesje(s.alicja), hasLength(1));

      await s.alicja.clearHistory();
      expect(await sesje(s.alicja), isEmpty);
      expect(await kawalki(s.alicja), isEmpty);
      expect(await sesje(s.bartek), hasLength(1));
    });
  });

  group('dziennik aplikacji', () {
    test('zdarzenia klawiatury są, wpisanego tekstu nie ma', () async {
      final s = await scena();
      expect(await s.alicja.startRemoteInput(s.bartekUAlicji),
          RemoteInputStart.accepted);
      await wpisz(
        s,
        const [RemoteInputOp.insert('Tajny tekst 42'), RemoteInputOp.action()],
        1,
      );
      s.bartek.stopIncomingRemoteInput();
      expect(
        s.alicja.sendRemoteInput(const [RemoteInputOp.insert('drugi sekret')]),
        isTrue,
      );
      await czekaj(
        () => stan(s.alicja) == OutgoingRemoteInputState.disconnected,
        'rozłączenie',
      );
      await s.alicja.stopRemoteInput();

      final uAlicji = await zdarzenia(s.alicja);
      // Rozmówca w dzienniku to nazwa z początkiem guid-a (peerLabel).
      expect(uAlicji, contains(startsWith('Typing request sent to Bartek (')));
      expect(uAlicji,
          contains(startsWith('Outgoing typing session started: Bartek (')));
      expect(uAlicji, contains('Typing packet refused by peer: $inputNoGrant'));
      expect(uAlicji,
          contains(startsWith('Outgoing typing session ended: stoppedByPeer')));

      final uBartka = await zdarzenia(s.bartek);
      expect(uBartka,
          contains(startsWith('Typing request received from Alicja (')));
      expect(
          uBartka,
          contains(allOf(startsWith('Incoming typing session started: Alicja ('),
              endsWith('(accepted)'))));
      expect(uBartka,
          contains(startsWith('Incoming typing session ended: stoppedHere')));

      for (final strona in [s.alicja, s.bartek]) {
        final wpisy = [
          for (final w in await dziennik(strona)) '${w.message}\n${w.details}',
        ].join('\n');
        for (final tajne in ['Tajny', 'tekst 42', 'sekret']) {
          expect(wpisy, isNot(contains(tajne)), reason: tajne);
        }
      }
      // Historia pisania ma ten tekst: tam jego miejsce.
      expect(
        (await opis(s.bartek)).single[3],
        const [TypingOp.insert('Tajny tekst 42'), TypingOp.action()],
      );
    });
  });
}
