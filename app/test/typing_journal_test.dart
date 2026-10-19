import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/typing_journal.dart';

const _tekst = RemoteInputTarget(
  active: true,
  field: RemoteInputField.text,
  app: 'com.example.notes',
  appLabel: 'Notatki',
);

const _haslo = RemoteInputTarget(
  active: true,
  field: RemoteInputField.password,
  app: 'com.example.notes',
  appLabel: 'Notatki',
);

const _nieznane = RemoteInputTarget(
  active: true,
  field: RemoteInputField.none,
  app: 'com.example.notes',
  appLabel: 'Notatki',
);

const _inna = RemoteInputTarget(
  active: true,
  field: RemoteInputField.text,
  app: 'com.example.mail',
  appLabel: 'Poczta',
);

/// Historia pisania bez sieci: operacje, ich zapis w JSON-ie, odtwarzanie
/// tekstu i zapis do bazy w tle.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('TypingOp', () {
    test('JSON w obie strony, także ukryte wpisanie', () {
      const ops = [
        TypingOp.insert('Zażółć 😀'),
        TypingOp.hidden(7),
        TypingOp.backspace(2),
        TypingOp.delete(1),
        TypingOp.action(),
      ];
      expect(ops[0].toJson(), {'t': 'insert', 's': 'Zażółć 😀'});
      expect(ops[1].toJson(), {'t': 'insert', 'hidden': 7});
      expect(ops[2].toJson(), {'t': 'bs', 'n': 2});
      expect(ops[3].toJson(), {'t': 'del', 'n': 1});
      expect(ops[4].toJson(), {'t': 'action'});

      for (final op in ops) {
        expect(TypingOp.fromJson(op.toJson()), op);
      }
      expect(TypingOp.decode(TypingOp.encode(ops)), ops);
      expect(TypingOp.fromJson(ops[1].toJson())!.hidden, isTrue);
      expect(TypingOp.fromJson(ops[1].toJson())!.chars, 7);
    });

    test('wyrozumiały odczyt: zły JSON, nieznane i niepełne operacje '
        'odpadają', () {
      expect(TypingOp.decode('to nie JSON'), isEmpty);
      expect(TypingOp.decode('{"t":"insert"}'), isEmpty);
      expect(TypingOp.fromJson('insert'), isNull);
      expect(TypingOp.fromJson({'t': 'ping'}), isNull);
      expect(TypingOp.fromJson({'t': 'stop'}), isNull);
      expect(TypingOp.fromJson({'t': 'insert'}), isNull);
      expect(TypingOp.fromJson({'t': 'bs'}), isNull);
      expect(
        TypingOp.decode('[{"t":"insert","s":"a"},{"t":"cos"},{"t":"bs","n":1}]'),
        const [TypingOp.insert('a'), TypingOp.backspace(1)],
      );
    });

    test('opis do dziennika i testów bez tekstu', () {
      expect('${const TypingOp.insert('tajne')}', isNot(contains('tajne')));
      expect('${const TypingOp.insert('tajne')}', 'insert(5)');
      expect('${const TypingOp.hidden(3)}', 'hidden(3)');
    });

    test('fromRemote: tekst jawny albo sama liczba znaków, ping i stop '
        'odpadają, sąsiednie wpisania się sklejają', () {
      const zSieci = [
        RemoteInputOp.insert('ab'),
        RemoteInputOp.insert('ć😀'),
        RemoteInputOp.ping(),
        RemoteInputOp.backspace(2),
        RemoteInputOp.delete(),
        RemoteInputOp.action(),
        RemoteInputOp.insert('x'),
        RemoteInputOp.stop(),
      ];
      expect(TypingOp.fromRemote(zSieci, hide: false), const [
        TypingOp.insert('abć😀'),
        TypingOp.backspace(2),
        TypingOp.delete(1),
        TypingOp.action(),
        TypingOp.insert('x'),
      ]);
      // Emoji to jeden znak: liczą się punkty kodowe.
      expect(TypingOp.fromRemote(zSieci, hide: true), const [
        TypingOp.hidden(4),
        TypingOp.backspace(2),
        TypingOp.delete(1),
        TypingOp.action(),
        TypingOp.hidden(1),
      ]);
      expect(
        TypingOp.fromRemote(
            const [RemoteInputOp.ping(), RemoteInputOp.stop()],
            hide: false),
        isEmpty,
      );
    });

    test('TypingStatus: nieznana nazwa to notTyped', () {
      for (final status in TypingStatus.values) {
        expect(TypingStatus.parse(status.name), status);
      }
      expect(TypingStatus.parse('cos'), TypingStatus.notTyped);
    });
  });

  group('appendTypingOp', () {
    test('skleja ten sam rodzaj, Enter i różne rodzaje zostają osobno', () {
      final ops = <TypingOp>[];
      appendTypingOp(ops, const TypingOp.insert('a'));
      appendTypingOp(ops, const TypingOp.insert('b'));
      appendTypingOp(ops, const TypingOp.hidden(2));
      appendTypingOp(ops, const TypingOp.hidden(3));
      appendTypingOp(ops, const TypingOp.insert('c'));
      appendTypingOp(ops, const TypingOp.backspace(1));
      appendTypingOp(ops, const TypingOp.backspace(2));
      appendTypingOp(ops, const TypingOp.delete(1));
      appendTypingOp(ops, const TypingOp.delete(4));
      appendTypingOp(ops, const TypingOp.action());
      appendTypingOp(ops, const TypingOp.action());
      expect(ops, const [
        TypingOp.insert('ab'),
        TypingOp.hidden(5),
        TypingOp.insert('c'),
        TypingOp.backspace(3),
        TypingOp.delete(5),
        TypingOp.action(),
        TypingOp.action(),
      ]);
    });
  });

  group('reconstructTyping', () {
    test('kasowanie poza początek zostawia pusty tekst', () {
      expect(
        reconstructTyping(const [
          TypingOp.insert('abc'),
          TypingOp.backspace(5),
          TypingOp.insert('d'),
        ]),
        'd',
      );
    });

    test('Backspace zabiera całe emoji', () {
      expect(
        reconstructTyping(const [
          TypingOp.insert('a😀'),
          TypingOp.backspace(1),
        ]),
        'a',
      );
    });

    test('Delete nie zmienia tekstu: kursor odbiorcy jest nieznany', () {
      expect(
        reconstructTyping(const [
          TypingOp.insert('ab'),
          TypingOp.delete(3),
          TypingOp.insert('c'),
        ]),
        'abc',
      );
    });

    test('Enter to nowa linia', () {
      expect(
        reconstructTyping(const [
          TypingOp.insert('Hej'),
          TypingOp.action(),
          TypingOp.insert('Druga'),
        ]),
        'Hej\nDruga',
      );
    });

    test('ukryte wpisanie to kropki, po jednej na znak', () {
      const ops = [
        TypingOp.insert('login '),
        TypingOp.hidden(4),
        TypingOp.backspace(1),
      ];
      expect(reconstructTyping(ops), 'login •••');
      expect(reconstructTyping(ops, hiddenChar: '*'), 'login ***');
      expect(reconstructTyping(ops, hiddenChar: ''), 'login');
    });
  });

  test('describeTypingOps: tekst dosłownie, klawisze w nawiasach', () {
    expect(
      describeTypingOps(const [
        TypingOp.insert('Hej'),
        TypingOp.backspace(1),
        TypingOp.backspace(3),
        TypingOp.delete(1),
        TypingOp.delete(2),
        TypingOp.action(),
        TypingOp.hidden(4),
      ]),
      'Hej[Backspace][Backspace x3][Delete][Delete x2][Enter]'
      '[hidden: 4 chars]',
    );
    expect(describeTypingOps(const []), isEmpty);
  });

  group('hideTyping', () {
    test('jawne tylko pole tekstowe przed paczką i po niej', () {
      expect(hideTyping(_tekst, _tekst), isFalse);
      expect(hideTyping(_tekst, _inna), isFalse);
      expect(hideTyping(_tekst, _haslo), isTrue,
          reason: 'pierwsza paczka w świeżo kliknięte pole hasła');
      expect(hideTyping(_tekst, _nieznane), isTrue);
      expect(hideTyping(_nieznane, _nieznane), isTrue);
      expect(
        hideTyping(RemoteInputTarget.none, RemoteInputTarget.none),
        isTrue,
      );
    });

    test('opóźnienie o jedną paczkę: pierwsza paczka po wyjściu z pola '
        'hasła też jest ukryta', () {
      // Cel znany przed paczką: hasło. Odpowiedź mówi już „tekst", ale
      // początek tej paczki mógł jeszcze wpisać się w hasło.
      expect(hideTyping(_haslo, _tekst), isTrue);
      expect(hideTyping(_nieznane, _tekst), isTrue);
      // Następna paczka zna już pole tekstowe.
      expect(hideTyping(_tekst, _tekst), isFalse);
    });
  });

  group('TypingJournal', () {
    late ChattDb db;
    late bool wlaczony;
    final bledy = <Object>[];

    setUp(() {
      db = ChattDb(NativeDatabase.memory());
      wlaczony = true;
      bledy.clear();
    });

    tearDown(() => db.close());

    TypingJournal dziennik({
      Duration flushDelay = const Duration(milliseconds: 50),
    }) =>
        TypingJournal(
          db,
          enabled: () => wlaczony,
          flushDelay: flushDelay,
          onError: (blad, _) => bledy.add(blad),
        );

    TypingSessionLog? zacznij(
      TypingJournal j, {
      String input = 'sesja-1',
      MessageDirection direction = MessageDirection.incoming,
      String result = TypingResult.accepted,
    }) =>
        j.begin(
          direction: direction,
          inputId: input,
          peerGuid: 'guid-alicji',
          peerName: 'Alicja',
          result: result,
        );

    void zapisz(
      TypingJournal j,
      TypingSessionLog? sesja,
      List<RemoteInputOp> ops, {
      TypingStatus status = TypingStatus.typed,
      RemoteInputTarget before = _tekst,
      RemoteInputTarget after = _tekst,
    }) =>
        j.record(sesja, ops, status: status, before: before, after: after);

    test('sesja: wiersz od razu, bez końca, z wynikiem prośby', () async {
      final j = dziennik();
      final sesja = zacznij(j, direction: MessageDirection.outgoing);
      expect(sesja, isNotNull);
      expect(sesja!.ended, isFalse);
      await j.flush();

      final wiersz = (await db.allTypingSessions()).single;
      expect(wiersz.inputId, 'sesja-1');
      expect(wiersz.direction, MessageDirection.outgoing);
      expect(wiersz.peerGuid, 'guid-alicji');
      expect(wiersz.peerName, 'Alicja');
      expect(wiersz.result, TypingResult.accepted);
      expect(wiersz.endedAt, isNull);
      expect(wiersz.endReason, isNull);
      expect(bledy, isEmpty);
    });

    test('kolejne paczki do tego samego pola sklejają się w jeden kawałek',
        () async {
      final j = dziennik(flushDelay: const Duration(hours: 1));
      final sesja = zacznij(j);
      zapisz(j, sesja, const [RemoteInputOp.insert('Zażółć')]);
      zapisz(j, sesja, const [RemoteInputOp.insert(' gęślą')]);
      zapisz(j, sesja, const [RemoteInputOp.backspace(), RemoteInputOp.ping()]);
      zapisz(j, sesja, const [RemoteInputOp.insert('ą'), RemoteInputOp.action()]);
      // Paczka bez pisania niczego nie dokłada.
      zapisz(j, sesja, const [RemoteInputOp.ping()]);
      await j.flush();

      final kawalek = (await db.allTypingEntries()).single;
      expect(TypingOp.decode(kawalek.ops), const [
        TypingOp.insert('Zażółć gęślą'),
        TypingOp.backspace(1),
        TypingOp.insert('ą'),
        TypingOp.action(),
      ]);
      expect(kawalek.chars, 13);
      expect(kawalek.app, 'com.example.notes');
      expect(kawalek.appLabel, 'Notatki');
      expect(kawalek.field, RemoteInputField.text.name);
      expect(kawalek.status, TypingStatus.typed.name);
      expect(kawalek.masked, isFalse);
    });

    test('zmiana skutku, pola albo aplikacji zaczyna nowy kawałek', () async {
      final j = dziennik(flushDelay: const Duration(hours: 1));
      final sesja = zacznij(j);
      zapisz(j, sesja, const [RemoteInputOp.insert('a')]);
      zapisz(j, sesja, const [RemoteInputOp.insert('b')],
          status: TypingStatus.notTyped);
      zapisz(j, sesja, const [RemoteInputOp.insert('c')],
          status: TypingStatus.paused);
      zapisz(j, sesja, const [RemoteInputOp.insert('tajne')], after: _haslo);
      zapisz(j, sesja, const [RemoteInputOp.insert('?')],
          before: _haslo, after: _nieznane);
      zapisz(j, sesja, const [RemoteInputOp.insert('d')],
          before: _nieznane, after: _inna);
      zapisz(j, sesja, const [RemoteInputOp.insert('e')],
          before: _inna, after: _inna);
      await j.flush();

      final kawalki = await db.allTypingEntries();
      expect(
        [for (final k in kawalki) (k.status, k.field, k.app, k.masked, k.ops)],
        [
          ('typed', 'text', 'com.example.notes', false,
              TypingOp.encode(const [TypingOp.insert('a')])),
          ('notTyped', 'text', 'com.example.notes', false,
              TypingOp.encode(const [TypingOp.insert('b')])),
          ('paused', 'text', 'com.example.notes', false,
              TypingOp.encode(const [TypingOp.insert('c')])),
          ('typed', 'password', 'com.example.notes', true,
              TypingOp.encode(const [TypingOp.hidden(5)])),
          ('typed', 'none', 'com.example.notes', true,
              TypingOp.encode(const [TypingOp.hidden(1)])),
          // Pierwsza paczka po polu nieznanego rodzaju jeszcze ukryta.
          ('typed', 'none', 'com.example.mail', true,
              TypingOp.encode(const [TypingOp.hidden(1)])),
          ('typed', 'text', 'com.example.mail', false,
              TypingOp.encode(const [TypingOp.insert('e')])),
        ],
      );
      final calosc = kawalki.map((k) => k.ops).join();
      expect(calosc, isNot(contains('tajne')));
      expect(kawalki[3].chars, 5);
    });

    test('kawałek trafia do bazy po ciszy, bez czekania na koniec sesji',
        () async {
      final j = dziennik(flushDelay: const Duration(milliseconds: 20));
      final sesja = zacznij(j);
      zapisz(j, sesja, const [RemoteInputOp.insert('a')]);
      final koniec = DateTime.now().add(const Duration(seconds: 10));
      while ((await db.allTypingEntries()).isEmpty) {
        if (DateTime.now().isAfter(koniec)) fail('kawałek nie trafił do bazy');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect((await db.allTypingSessions()).single.endedAt, isNull);
    });

    test('koniec sesji zapisuje zebrany kawałek i powód', () async {
      // Cisza nigdy nie minie: kawałek zapisuje sam koniec sesji.
      final j = dziennik(flushDelay: const Duration(hours: 1));
      final sesja = zacznij(j);
      zapisz(j, sesja, const [RemoteInputOp.insert('ostatnie')]);
      j.end(sesja, TypingEnd.stoppedByPeer);
      expect(sesja!.ended, isTrue);
      // Po końcu nic już nie dochodzi, a drugi koniec niczego nie zmienia.
      zapisz(j, sesja, const [RemoteInputOp.insert('po końcu')]);
      j.end(sesja, TypingEnd.expired);
      await j.flush();

      final wiersz = (await db.allTypingSessions()).single;
      expect(wiersz.endReason, TypingEnd.stoppedByPeer);
      expect(wiersz.endedAt, isNotNull);
      final kawalek = (await db.allTypingEntries()).single;
      expect(kawalek.sessionId, wiersz.id);
      expect(TypingOp.decode(kawalek.ops),
          const [TypingOp.insert('ostatnie')]);
    });

    test('prośba bez sesji: wiersz zakończony w chwili prośby, bez powodu '
        'końca', () async {
      final j = dziennik();
      j.refused(
        direction: MessageDirection.outgoing,
        inputId: 'odmowa-1',
        peerGuid: 'guid-bartka',
        peerName: 'Bartek',
        result: TypingResult.rejected,
      );
      final zaczeta = zacznij(j, input: 'odmowa-2', result: TypingResult.busy);
      expect(zaczeta!.ended, isTrue);
      zapisz(j, zaczeta, const [RemoteInputOp.insert('x')]);
      await j.flush();

      final wiersze = await db.allTypingSessions();
      expect([for (final w in wiersze) w.result],
          [TypingResult.rejected, TypingResult.busy]);
      for (final w in wiersze) {
        expect(w.endedAt, w.startedAt);
        expect(w.endReason, isNull);
      }
      expect(await db.allTypingEntries(), isEmpty);
      expect(TypingResult.started(TypingResult.accepted), isTrue);
      expect(TypingResult.started(TypingResult.acceptedAlways), isTrue);
      expect(TypingResult.started(TypingResult.automatic), isTrue);
      expect(TypingResult.started(TypingResult.rejected), isFalse);
    });

    test('wyłączona historia niczego nie zapisuje', () async {
      wlaczony = false;
      final j = dziennik();
      expect(j.enabled, isFalse);
      final sesja = zacznij(j);
      expect(sesja, isNull);
      zapisz(j, sesja, const [RemoteInputOp.insert('x')]);
      j.end(sesja, TypingEnd.stoppedHere);
      j.refused(
        direction: MessageDirection.incoming,
        inputId: 'odmowa',
        peerGuid: 'guid-alicji',
        peerName: 'Alicja',
        result: TypingResult.rejected,
      );
      await j.flush();
      expect(await db.allTypingSessions(), isEmpty);
      expect(await db.allTypingEntries(), isEmpty);
    });

    test('wyłączona w trakcie sesji: dalsze pisanie bez zapisu, koniec '
        'zapisany', () async {
      final j = dziennik(flushDelay: const Duration(hours: 1));
      final sesja = zacznij(j);
      zapisz(j, sesja, const [RemoteInputOp.insert('przed')]);
      wlaczony = false;
      zapisz(j, sesja, const [RemoteInputOp.insert('po')]);
      j.end(sesja, TypingEnd.addonOff);
      await j.flush();

      expect((await db.allTypingSessions()).single.endReason,
          TypingEnd.addonOff);
      expect(TypingOp.decode((await db.allTypingEntries()).single.ops),
          const [TypingOp.insert('przed')]);
    });

    test('detachAll: trwająca sesja przestaje zapisywać, nowa zapisuje',
        () async {
      final j = dziennik(flushDelay: const Duration(hours: 1));
      final stara = zacznij(j, input: 'stara');
      zapisz(j, stara, const [RemoteInputOp.insert('przed')]);
      await j.flush();
      await db.clearTypingHistory();
      // Kawałek zebrany po zapisie, a przed czyszczeniem, przepada razem
      // z sesją.
      zapisz(j, stara, const [RemoteInputOp.insert('w trakcie')]);
      j.detachAll();
      expect(stara!.ended, isTrue);
      zapisz(j, stara, const [RemoteInputOp.insert('po')]);
      j.end(stara, TypingEnd.stoppedHere);

      final nowa = zacznij(j, input: 'nowa');
      zapisz(j, nowa, const [RemoteInputOp.insert('nowe')]);
      j.end(nowa, TypingEnd.stoppedHere);
      await j.flush();

      final wiersz = (await db.allTypingSessions()).single;
      expect(wiersz.inputId, 'nowa');
      expect(wiersz.endReason, TypingEnd.stoppedHere);
      expect(TypingOp.decode((await db.allTypingEntries()).single.ops),
          const [TypingOp.insert('nowe')]);
    });

    test('detachAll: zapisy czekające jeszcze w kolejce nie wskrzeszają '
        'skasowanej historii', () async {
      final j = dziennik(flushDelay: const Duration(hours: 1));
      final sesja = zacznij(j);
      zapisz(j, sesja, const [RemoteInputOp.insert('przed')]);
      await j.flush();
      zapisz(j, sesja, const [RemoteInputOp.insert('tajne')]);
      await db.clearTypingHistory();
      // Między czyszczeniem a odcięciem sesja się kończy i przychodzi
      // odmowa: ich zapisy stoją jeszcze w kolejce, gdy sesje są odcinane.
      j.end(sesja, TypingEnd.stoppedHere);
      j.refused(
        direction: MessageDirection.incoming,
        inputId: 'odmowa',
        peerGuid: 'guid-alicji',
        peerName: 'Alicja',
        result: TypingResult.rejected,
      );
      j.detachAll();
      await j.flush();

      expect(await db.allTypingSessions(), isEmpty);
      expect(await db.allTypingEntries(), isEmpty);
      expect(bledy, isEmpty);
    });

    test('close: trwające sesje kończą się appClosed, potem nic nie '
        'dochodzi', () async {
      final j = dziennik(flushDelay: const Duration(hours: 1));
      final sesja = zacznij(j);
      zapisz(j, sesja, const [RemoteInputOp.insert('ostatnie')]);
      await j.close();
      expect(j.enabled, isFalse);
      expect(sesja!.ended, isTrue);

      final wiersz = (await db.allTypingSessions()).single;
      expect(wiersz.endReason, TypingEnd.appClosed);
      expect(wiersz.endedAt, isNotNull);
      expect(TypingOp.decode((await db.allTypingEntries()).single.ops),
          const [TypingOp.insert('ostatnie')]);

      expect(zacznij(j, input: 'po zamknięciu'), isNull);
      j.refused(
        direction: MessageDirection.incoming,
        inputId: 'po zamknięciu',
        peerGuid: 'guid-alicji',
        peerName: 'Alicja',
        result: TypingResult.rejected,
      );
      await j.flush();
      expect(await db.allTypingSessions(), hasLength(1));
    });

    test('błąd zapisu idzie do onError i nie zatrzymuje kolejki', () async {
      final j = dziennik(flushDelay: const Duration(hours: 1));
      final pierwsza = zacznij(j, input: 'pierwsza');
      await j.flush();
      await db.customStatement('DROP TABLE typing_entries');
      zapisz(j, pierwsza, const [RemoteInputOp.insert('x')]);
      j.end(pierwsza, TypingEnd.stoppedHere);
      final druga = zacznij(j, input: 'druga');
      j.end(druga, TypingEnd.expired);
      await j.flush();

      expect(bledy, hasLength(1));
      expect(
        [for (final w in await db.allTypingSessions()) (w.inputId, w.endReason)],
        [('pierwsza', TypingEnd.stoppedHere), ('druga', TypingEnd.expired)],
      );
    });
  });
}
