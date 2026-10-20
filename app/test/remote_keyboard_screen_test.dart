import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatt/data/db.dart';
import 'package:chatt/l10n/app_localizations.dart';
import 'package:chatt/network/protocol.dart';
import 'package:chatt/services/app_services.dart';
import 'package:chatt/services/providers.dart';
import 'package:chatt/ui/screens/remote_keyboard_screen.dart';
import 'package:chatt/ui/widgets/toasts.dart';

/// Sesja bez sieci: zapisuje, co ekran wysłał, a stan ustawia test.
class _Lacze implements RemoteKeyboardLink {
  _Lacze(this.peerGuid);

  final String peerGuid;

  @override
  final ValueNotifier<OutgoingRemoteInput?> state = ValueNotifier(null);

  final wyslane = <Map<String, Object?>>[];
  var starty = 0;
  var stopy = 0;

  /// `false` udaje kolejkę, która nie przyjmuje więcej tekstu.
  bool przyjmuje = true;

  /// Odpowiedzi na paczki z tekstem, jak liczy je serwis.
  int _odpowiedzi = 0;
  bool _wpisane = true;
  Completer<RemoteInputStart> _wynik = Completer();

  @override
  Future<RemoteInputStart> start() {
    starty++;
    state.value = OutgoingRemoteInput(
      peerGuid: peerGuid,
      peerName: 'Bartek',
      state: OutgoingRemoteInputState.waiting,
    );
    _wynik = Completer();
    return _wynik.future;
  }

  void zgoda([RemoteInputTarget cel = _poleTekstowe]) {
    ustaw(OutgoingRemoteInputState.active, cel);
    _wynik.complete(RemoteInputStart.accepted);
  }

  void odmowa(RemoteInputStart powod) {
    state.value = null;
    _wynik.complete(powod);
  }

  /// [applied] udaje odpowiedź na paczkę z tekstem; bez niego to ping.
  void ustaw(OutgoingRemoteInputState stan, RemoteInputTarget cel,
      {String? reason, bool? applied}) {
    if (applied != null) {
      _odpowiedzi++;
      _wpisane = applied;
    }
    state.value = OutgoingRemoteInput(
      peerGuid: peerGuid,
      peerName: 'Bartek',
      state: stan,
      target: cel,
      applied: _wpisane,
      typedReplies: _odpowiedzi,
      rtt: const Duration(milliseconds: 12),
      reason: reason,
    );
  }

  @override
  bool send(List<RemoteInputOp> ops) {
    final stan = state.value?.state;
    if (!przyjmuje ||
        (stan != OutgoingRemoteInputState.active &&
            stan != OutgoingRemoteInputState.paused)) {
      return false;
    }
    wyslane.addAll(ops.map((op) => op.toJson()));
    return true;
  }

  @override
  Future<void> stop() async {
    stopy++;
    state.value = null;
  }
}

const _poleHasla = RemoteInputTarget(
  active: true,
  field: RemoteInputField.password,
  appLabel: 'Chrome',
);

const _poleTekstowe = RemoteInputTarget(
  active: true,
  field: RemoteInputField.text,
  app: 'notepad.exe',
  appLabel: 'Notatnik',
);

Map<String, Object?> _wpisz(String s) => {'t': 'insert', 's': s};
Map<String, Object?> _bs(int n) => {'t': 'bs', 'n': n};
Map<String, Object?> _del(int n) => {'t': 'del', 'n': n};
const Map<String, Object?> _akcja = {'t': 'action'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final teksty = lookupAppLocalizations(const Locale('en'));

  group('echoOps', () {
    List<Map<String, Object?>> ops(String a, String b) =>
        echoOps(a, b).map((op) => op.toJson()).toList();

    test('dopisanie to samo wpisanie', () {
      expect(ops('', 'ab'), [_wpisz('ab')]);
      expect(ops('ab', 'abc'), [_wpisz('c')]);
    });

    test('skasowanie z końca to Backspace', () {
      expect(ops('abc', 'a'), [_bs(2)]);
      expect(ops('abc', ''), [_bs(3)]);
    });

    test('podmiana końca to Backspace i wpisanie', () {
      expect(ops('kot', 'kos'), [_bs(1), _wpisz('s')]);
    });

    test('emoji z pary surogatów liczy się jako jeden znak', () {
      expect(ops('a😀', 'a'), [_bs(1)]);
      expect(ops('a', 'a😀'), [_wpisz('😀')]);
      expect(ops('😀', '😁'), [_bs(1), _wpisz('😁')]);
    });

    test('bez zmiany nic nie idzie', () {
      expect(ops('ab', 'ab'), isEmpty);
    });
  });

  group('ekran pisania', () {
    late Directory katalog;
    late AppServices services;
    late _Lacze lacze;
    final peer = Peer(
      id: 1,
      guid: 'guid-bartek',
      name: 'Bartek',
      welcomeMessage: '',
      host: '',
      port: 0,
      verified: true,
      autoAccept: false,
      remoteInput: false,
      firstSeen: DateTime(2026),
      lastSeen: DateTime(2026),
    );

    setUp(() {
      katalog = Directory.systemTemp.createTempSync('chatt_ekran_pisania_');
      lacze = _Lacze(peer.guid);
      chattToasts.clear();
    });
    tearDown(() {
      chattToasts.clear();
      katalog.deleteSync(recursive: true);
    });

    Future<void> uruchom(WidgetTester tester) async {
      services = (await tester.runAsync(() => AppServices.start(
            executor: NativeDatabase.memory(),
            portOverride: 0,
            nameOverride: 'Alicja',
            enableDiscovery: false,
            receivedDirOverride: '${katalog.path}/Alicja',
          )))!;
      await tester.pumpWidget(ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => ToastHost(child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RemoteKeyboardScreen(peer: peer, link: lacze),
                    ),
                  ),
                  child: const Text('otwórz'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('otwórz'));
      // Kółko czekania kręci się bez końca, więc bez `pumpAndSettle`.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> sprzatnij(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      // Komunikaty znikają po swoim czasie.
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(services.dispose);
    }

    Future<void> zgoda(WidgetTester tester,
        [RemoteInputTarget cel = _poleTekstowe]) async {
      lacze.zgoda(cel);
      await tester.pump();
      await tester.pump();
    }

    Finder echo() => find.byType(TextField);

    TextField pole(WidgetTester tester) => tester.widget<TextField>(echo());

    testWidgets('czeka na zgodę, a Anuluj zamyka ekran i sesję',
        (tester) async {
      await uruchom(tester);
      expect(lacze.starty, 1);
      expect(find.text(teksty.remoteKeyboardWaiting('Bartek')), findsOneWidget);
      expect(echo(), findsNothing, reason: 'przed zgodą nie ma gdzie pisać');

      await tester.tap(find.text(teksty.cancel));
      await tester.pumpAndSettle();
      expect(find.byType(RemoteKeyboardScreen), findsNothing);
      expect(lacze.stopy, 1);

      await sprzatnij(tester);
    });

    testWidgets('odmowa przy starcie zamyka ekran z komunikatem',
        (tester) async {
      await uruchom(tester);
      lacze.odmowa(RemoteInputStart.notEnabled);
      // Komunikat żyje na animacji przez czas stylu (tu Cisza: 3,2 s);
      // `pumpAndSettle` by go przeczekał.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(RemoteKeyboardScreen), findsNothing);
      expect(find.text(teksty.remoteKeyboardNotEnabled('Bartek')),
          findsOneWidget);

      await sprzatnij(tester);
    });

    testWidgets('pisanie w echu idzie jako wpisanie i Backspace',
        (tester) async {
      await uruchom(tester);
      await zgoda(tester);
      expect(find.text(teksty.remoteKeyboardTarget('Notatnik')), findsOneWidget);
      expect(pole(tester).focusNode!.hasFocus, isTrue);

      await tester.enterText(echo(), 'ab');
      await tester.enterText(echo(), 'abć');
      await tester.enterText(echo(), 'ab');
      expect(lacze.wyslane, [_wpisz('ab'), _wpisz('ć'), _bs(1)]);

      await sprzatnij(tester);
    });

    testWidgets('Enter opróżnia echo i idzie jako akcja pola, Shift+Enter '
        'jako nowa linia', (tester) async {
      await uruchom(tester);
      await zgoda(tester);

      await tester.enterText(echo(), 'raz');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pole(tester).controller!.text, isEmpty);

      await tester.enterText(echo(), 'dwa');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(pole(tester).controller!.text, isEmpty);

      expect(lacze.wyslane, [
        _wpisz('raz'),
        _akcja,
        _wpisz('dwa'),
        _wpisz('\n'),
      ]);

      await sprzatnij(tester);
    });

    testWidgets('Backspace na pustym echu i Delete kasują po drugiej stronie, '
        'strzałki nie robią nic', (tester) async {
      await uruchom(tester);
      await zgoda(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.enterText(echo(), 'xy');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(pole(tester).controller!.text, 'xy');
      expect(pole(tester).focusNode!.hasFocus, isTrue,
          reason: 'Tab nie wyprowadza fokusu z pola');
      expect(pole(tester).controller!.selection,
          const TextSelection.collapsed(offset: 2));

      expect(lacze.wyslane, [_bs(1), _del(1), _wpisz('xy')]);

      await sprzatnij(tester);
    });

    testWidgets('echo zasłonięte, dopóki druga strona nie powie, że to '
        'zwykłe pole', (tester) async {
      await uruchom(tester);
      await zgoda(
          tester,
          const RemoteInputTarget(
            active: true,
            field: RemoteInputField.password,
            appLabel: 'Chrome',
          ));
      expect(pole(tester).obscureText, isTrue);
      expect(find.text(teksty.remoteKeyboardTargetPassword('Chrome')),
          findsOneWidget);

      lacze.ustaw(
          OutgoingRemoteInputState.active,
          const RemoteInputTarget(
            active: true,
            field: RemoteInputField.none,
            appLabel: 'Chrome',
          ));
      await tester.pump();
      expect(pole(tester).obscureText, isTrue,
          reason: 'nieznany rodzaj pola też zasłania');

      lacze.ustaw(OutgoingRemoteInputState.active, _poleTekstowe);
      await tester.pump();
      expect(pole(tester).obscureText, isFalse);

      await sprzatnij(tester);
    });

    testWidgets('pasek stanu mówi, czemu nic się nie wpisze', (tester) async {
      await uruchom(tester);
      await zgoda(tester);

      Future<void> cel(RemoteInputTarget cel, String napis) async {
        lacze.ustaw(OutgoingRemoteInputState.active, cel);
        await tester.pump();
        expect(find.text(napis), findsOneWidget, reason: napis);
      }

      await cel(const RemoteInputTarget(locked: true),
          teksty.remoteKeyboardLocked);
      await cel(const RemoteInputTarget(active: true, elevated: true),
          teksty.remoteKeyboardElevated);
      await cel(RemoteInputTarget.none, teksty.remoteKeyboardNoField);

      lacze.ustaw(OutgoingRemoteInputState.paused, _poleTekstowe);
      await tester.pump();
      expect(find.text(teksty.remoteKeyboardPaused), findsOneWidget);

      await sprzatnij(tester);
    });

    testWidgets('zerwana sesja: pole tylko do odczytu i Połącz ponownie',
        (tester) async {
      await uruchom(tester);
      await zgoda(tester);

      lacze.ustaw(OutgoingRemoteInputState.disconnected, _poleTekstowe,
          reason: inputNoGrant);
      await tester.pump();
      expect(find.text(teksty.remoteKeyboardEnded('Bartek')), findsOneWidget);
      expect(pole(tester).readOnly, isTrue);

      await tester.tap(find.text(teksty.remoteKeyboardReconnect));
      await tester.pump();
      expect(lacze.starty, 2);
      expect(find.text(teksty.remoteKeyboardWaiting('Bartek')), findsOneWidget);

      await zgoda(tester);
      expect(pole(tester).readOnly, isFalse);
      await tester.enterText(echo(), 'z');
      expect(lacze.wyslane, [_wpisz('z')]);

      await sprzatnij(tester);
    });

    testWidgets('za dużo tekstu naraz: echo wraca, komunikat',
        (tester) async {
      await uruchom(tester);
      await zgoda(tester);
      await tester.enterText(echo(), 'ok');
      lacze.przyjmuje = false;
      await tester.enterText(echo(), 'ok i dużo więcej');
      await tester.pump();
      expect(pole(tester).controller!.text, 'ok');
      expect(find.text(teksty.remoteKeyboardTooLong), findsOneWidget);
      expect(lacze.wyslane, [_wpisz('ok')]);

      await sprzatnij(tester);
    });

    testWidgets('całość naraz: Wyślij z Enterem i czyste pole', (tester) async {
      await uruchom(tester);
      await zgoda(tester);
      await tester.enterText(echo(), 'a');

      await tester.tap(find.text(teksty.remoteKeyboardModeCompose));
      await tester.pumpAndSettle();
      await tester.enterText(echo(), 'akapit\ndrugi');
      await tester.tap(find.text(teksty.remoteKeyboardThenEnter));
      await tester.pump();
      await tester.tap(find.text(teksty.remoteKeyboardSend));
      await tester.pump();

      expect(pole(tester).controller!.text, isEmpty);
      expect(lacze.wyslane, [_wpisz('a'), _wpisz('akapit\ndrugi'), _akcja]);

      await sprzatnij(tester);
    });

    testWidgets('Wklej ze schowka wysyła tekst ze schowka', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, Object?>{'text': 'ze schowka'}
            : null,
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await uruchom(tester);
      await zgoda(tester);
      await tester.enterText(echo(), 'ab');

      await tester.tap(find.text(teksty.remoteKeyboardPaste));
      await tester.pump();
      await tester.pump();
      expect(pole(tester).controller!.text, isEmpty,
          reason: 'echo opróżnione, bo kursor po drugiej stronie poszedł dalej');
      expect(lacze.wyslane, [_wpisz('ab'), _wpisz('ze schowka')]);

      await sprzatnij(tester);
    });

    testWidgets('karta na tym urządzeniu wstrzymuje, a po niej fokus wraca '
        'do pola', (tester) async {
      await uruchom(tester);
      await zgoda(tester);

      services.pendingRemoteInput.value = const [
        PendingRemoteInput(id: 'x', peerGuid: 'g', peerName: 'Celina'),
      ];
      await tester.pump();
      expect(find.text(teksty.remoteKeyboardLocalCard), findsOneWidget);
      // Karta zabiera fokus w swojej pierwszej klatce; ekran odbiera go
      // w następnej, żeby spacja ani Enter nie odpowiedziały na kartę.
      pole(tester).focusNode!.unfocus();
      await tester.pump();
      await tester.pump();
      expect(pole(tester).focusNode!.hasFocus, isTrue);
      expect(pole(tester).readOnly, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect(lacze.wyslane, isEmpty, reason: 'przy karcie nic nie idzie');
      pole(tester).focusNode!.unfocus();
      await tester.pump();

      services.pendingRemoteInput.value = const [];
      await tester.pump();
      await tester.pump();
      expect(find.text(teksty.remoteKeyboardLocalCard), findsNothing);
      expect(pole(tester).focusNode!.hasFocus, isTrue);

      await sprzatnij(tester);
    });

    testWidgets('wyjście z ekranu kończy sesję', (tester) async {
      await uruchom(tester);
      await zgoda(tester);
      await tester.tap(find.text(teksty.remoteInputStop));
      await tester.pumpAndSettle();
      expect(find.byType(RemoteKeyboardScreen), findsNothing);
      expect(lacze.stopy, 1);

      await sprzatnij(tester);
    });

    testWidgets('hasło wpisane pod maską zostaje zasłonięte, gdy fokus po '
        'drugiej stronie przejdzie do zwykłego pola', (tester) async {
      await uruchom(tester);
      await zgoda(tester, _poleHasla);
      await tester.enterText(echo(), 'tajne');
      lacze.ustaw(OutgoingRemoteInputState.active, _poleTekstowe);
      await tester.pump();
      expect(pole(tester).obscureText, isTrue);
      expect(pole(tester).controller!.text, 'tajne');

      // Enter opróżnia echo i maska schodzi razem z treścią.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pole(tester).controller!.text, isEmpty);
      expect(pole(tester).obscureText, isFalse);

      // To samo w polu „całość naraz".
      lacze.ustaw(OutgoingRemoteInputState.active, _poleHasla);
      await tester.pump();
      await tester.tap(find.text(teksty.remoteKeyboardModeCompose));
      await tester.pumpAndSettle();
      await tester.enterText(echo(), 'haslo2');
      lacze.ustaw(OutgoingRemoteInputState.active, _poleTekstowe);
      await tester.pump();
      expect(pole(tester).obscureText, isTrue);
      await tester.tap(find.text(teksty.remoteKeyboardSend));
      await tester.pump();
      expect(pole(tester).controller!.text, isEmpty);
      expect(pole(tester).obscureText, isFalse);
      expect(lacze.wyslane, [_wpisz('tajne'), _akcja, _wpisz('haslo2')]);

      await sprzatnij(tester);
    });

    testWidgets('tekst, którego druga strona nie wpisała, znika z echa, '
        'a bez pola pisać się nie da', (tester) async {
      await uruchom(tester);
      await zgoda(tester);
      await tester.enterText(echo(), 'abc');
      lacze.ustaw(OutgoingRemoteInputState.active, _poleTekstowe,
          applied: false);
      await tester.pump();
      expect(pole(tester).controller!.text, isEmpty,
          reason: 'echo nie pokazuje tekstu, którego tam nie ma');

      // Druga niewpisana paczka z rzędu też znika, a ping niczego nie rusza.
      await tester.enterText(echo(), 'd');
      lacze.ustaw(OutgoingRemoteInputState.active, _poleTekstowe);
      await tester.pump();
      expect(pole(tester).controller!.text, 'd');
      lacze.ustaw(OutgoingRemoteInputState.active, _poleTekstowe,
          applied: false);
      await tester.pump();
      expect(pole(tester).controller!.text, isEmpty);

      lacze.ustaw(OutgoingRemoteInputState.paused, _poleTekstowe);
      await tester.pump();
      expect(pole(tester).readOnly, isTrue);
      lacze.ustaw(OutgoingRemoteInputState.active, RemoteInputTarget.none);
      await tester.pump();
      expect(pole(tester).readOnly, isTrue);
      lacze.ustaw(OutgoingRemoteInputState.active, _poleTekstowe);
      await tester.pump();
      expect(pole(tester).readOnly, isFalse);

      // Backspace na pustym echu kasuje już po drugiej stronie, świadomie.
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect(lacze.wyslane, [_wpisz('abc'), _wpisz('d'), _bs(1)]);

      await sprzatnij(tester);
    });

    testWidgets('Ctrl+V w echu wkleja ze schowka', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, Object?>{'text': 'z Ctrl+V'}
            : null,
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await uruchom(tester);
      await zgoda(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();
      expect(lacze.wyslane, [_wpisz('z Ctrl+V')]);

      await sprzatnij(tester);
    });

    testWidgets('przytrzymany Ctrl+Enter wysyła całość raz', (tester) async {
      await uruchom(tester);
      await zgoda(tester);
      await tester.tap(find.text(teksty.remoteKeyboardModeCompose));
      await tester.pumpAndSettle();
      await tester.enterText(echo(), 'hej');
      await tester.tap(find.text(teksty.remoteKeyboardThenEnter));
      await tester.pump();
      await tester.showKeyboard(echo());

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(lacze.wyslane, [_wpisz('hej'), _akcja]);

      await sprzatnij(tester);
    });

    testWidgets('odmowa, która przyjdzie po Anuluj, nie zamyka niczego '
        'więcej', (tester) async {
      await uruchom(tester);
      await tester.tap(find.text(teksty.cancel));
      await tester.pump();
      expect(lacze.stopy, 1, reason: 'sesja kończy się z zamknięciem ekranu');
      lacze.odmowa(RemoteInputStart.rejected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(RemoteKeyboardScreen), findsNothing);
      expect(find.text('otwórz'), findsOneWidget,
          reason: 'ekran pod spodem zostaje na miejscu');
      expect(find.text(teksty.remoteKeyboardRejected('Bartek')), findsNothing);

      await sprzatnij(tester);
    });

    testWidgets('ekran zamykany w tle nie kończy sesji następnego',
        (tester) async {
      await uruchom(tester);
      await zgoda(tester);
      await tester.tap(find.text(teksty.remoteInputStop));
      await tester.pump();
      expect(lacze.stopy, 1);

      // Następny ekran, zanim poprzedni skończył schodzić.
      await tester.tap(find.text('otwórz'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(lacze.starty, 2);
      expect(lacze.stopy, 1, reason: 'zamknięty ekran nie zatrzymał nowego');
      expect(lacze.state.value?.state, OutgoingRemoteInputState.waiting);
      expect(find.text(teksty.remoteKeyboardWaiting('Bartek')), findsOneWidget);

      await sprzatnij(tester);
    });

    testWidgets('kolejna karta z kolejki też nie zatrzymuje fokusu',
        (tester) async {
      await uruchom(tester);
      await zgoda(tester);
      const a = PendingRemoteInput(id: 'a', peerGuid: 'g1', peerName: 'Celina');
      const b = PendingRemoteInput(id: 'b', peerGuid: 'g2', peerName: 'Darek');
      services.pendingRemoteInput.value = const [a, b];
      await tester.pump();
      await tester.pump();
      expect(pole(tester).focusNode!.hasFocus, isTrue);

      // Odpowiedź na pierwszą: na jej miejsce wchodzi druga i bierze fokus.
      pole(tester).focusNode!.unfocus();
      services.pendingRemoteInput.value = const [b];
      await tester.pump();
      await tester.pump();
      expect(pole(tester).focusNode!.hasFocus, isTrue);

      services.pendingRemoteInput.value = const [];
      await tester.pump();
      await sprzatnij(tester);
    });

    testWidgets('Tab przy wstrzymanym pisaniu zostaje w polu, więc Enter '
        'nie trafia w Stop', (tester) async {
      await uruchom(tester);
      await zgoda(tester);
      lacze.ustaw(OutgoingRemoteInputState.paused, _poleTekstowe);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(pole(tester).focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(lacze.stopy, 0);
      expect(find.byType(RemoteKeyboardScreen), findsOneWidget);

      await sprzatnij(tester);
    });

    testWidgets('zmiana maski w polu „całość naraz" zostawia pole '
        'z fokusem i połączeniem z klawiaturą', (tester) async {
      await uruchom(tester);
      await zgoda(tester);
      await tester.tap(find.text(teksty.remoteKeyboardModeCompose));
      await tester.pumpAndSettle();
      await tester.showKeyboard(echo());
      expect(tester.testTextInput.hasAnyClients, isTrue);

      lacze.ustaw(OutgoingRemoteInputState.active, _poleHasla);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(pole(tester).obscureText, isTrue);
      expect(pole(tester).focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);

      lacze.ustaw(OutgoingRemoteInputState.active, _poleTekstowe);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(pole(tester).obscureText, isFalse);
      expect(pole(tester).focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);

      await sprzatnij(tester);
    });

    testWidgets('pole samego Chatt przyjmuje pisanie jak każde inne',
        (tester) async {
      await uruchom(tester);
      await zgoda(
          tester,
          const RemoteInputTarget(
            active: true,
            field: RemoteInputField.text,
            app: 'com.mysttic.chatt',
            appLabel: 'Chatt',
            ownApp: true,
          ));
      expect(find.text(teksty.remoteKeyboardTarget('Chatt')), findsOneWidget);
      expect(pole(tester).readOnly, isFalse);
      await tester.enterText(echo(), 'do Chatt');
      expect(lacze.wyslane, [_wpisz('do Chatt')]);

      await sprzatnij(tester);
    });
  });
}
