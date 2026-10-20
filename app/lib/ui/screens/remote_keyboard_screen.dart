import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../network/protocol.dart';
import '../../network/transport.dart' show PeerProtocol;
import '../../services/app_services.dart';
import '../../services/providers.dart';
import '../l10n_context.dart';
import '../widgets/toasts.dart';

/// Operacje, które zamieniają to, co już poszło, w to, co jest teraz w polu.
///
/// Liczy w punktach kodowych, tak jak `bs` po drugiej stronie: emoji z pary
/// surogatów to jeden znak do skasowania. Wspólny początek zostaje, reszta
/// starego tekstu idzie jako Backspace, reszta nowego jako wpisanie. Pole
/// ma kursor przypięty na końcu, więc zmiana jest prawie zawsze dopisaniem
/// albo skasowaniem z końca; podmiana słowa przez klawiaturę ekranową to
/// jedno i drugie naraz.
List<RemoteInputOp> echoOps(String przed, String po) {
  final stare = przed.runes.toList(growable: false);
  final nowe = po.runes.toList(growable: false);
  var wspolne = 0;
  while (wspolne < stare.length &&
      wspolne < nowe.length &&
      stare[wspolne] == nowe[wspolne]) {
    wspolne++;
  }
  return [
    if (stare.length > wspolne)
      RemoteInputOp.backspace(stare.length - wspolne),
    if (nowe.length > wspolne)
      RemoteInputOp.insert(String.fromCharCodes(nowe, wspolne)),
  ];
}

/// Sesja pisania widziana z ekranu. Domyślnie idzie przez [AppServices];
/// testy ekranu podstawiają własną, bez sieci.
abstract class RemoteKeyboardLink {
  ValueListenable<OutgoingRemoteInput?> get state;
  Future<RemoteInputStart> start();
  bool send(List<RemoteInputOp> ops);
  Future<void> stop();
}

class _ServicesLink implements RemoteKeyboardLink {
  final AppServices services;
  final Peer peer;

  _ServicesLink(this.services, this.peer);

  @override
  ValueListenable<OutgoingRemoteInput?> get state =>
      services.outgoingRemoteInput;

  @override
  Future<RemoteInputStart> start() => services.startRemoteInput(peer);

  @override
  bool send(List<RemoteInputOp> ops) => services.sendRemoteInput(ops);

  @override
  Future<void> stop() => services.stopRemoteInput();
}

enum _Tryb { live, compose }

/// Klawisze, których dodatek nie przenosi (sekcja 0 issue #35): strzałki,
/// Home/End, PgUp/PgDn i Tab. W polu-echu nie robią nic, także gdy pisanie
/// stoi: kursor nie wędruje, a fokus nie przechodzi na Stop, który następny
/// Enter by nacisnął.
final Set<LogicalKeyboardKey> _bezSkutku = {
  LogicalKeyboardKey.tab,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.home,
  LogicalKeyboardKey.end,
  LogicalKeyboardKey.pageUp,
  LogicalKeyboardKey.pageDown,
};

/// Pisanie z klawiatury tego urządzenia na drugim, w polu z fokusem po
/// tamtej stronie.
///
/// Własna trasa z własnym polem: w polu rozmowy Enter wysyła wiadomość.
/// Sesja trwa, dopóki ten ekran jest otwarty; wyjście z niego ją kończy.
/// Wpisywany tekst żyje w kontrolerach pól tego ekranu, w kolejce serwisu
/// i, przy włączonym zapisie, w zaszyfrowanej historii pisania (patrz
/// `services/typing_journal.dart`), gdzie tekst z pola hasła i z pola
/// nieznanego rodzaju zostaje samą liczbą znaków.
class RemoteKeyboardScreen extends ConsumerStatefulWidget {
  final Peer peer;

  /// Podmiana sesji w testach.
  final RemoteKeyboardLink? link;

  const RemoteKeyboardScreen({super.key, required this.peer, this.link});

  @override
  ConsumerState<RemoteKeyboardScreen> createState() =>
      _RemoteKeyboardScreenState();
}

class _RemoteKeyboardScreenState extends ConsumerState<RemoteKeyboardScreen> {
  late final RemoteKeyboardLink _link =
      widget.link ?? _ServicesLink(ref.read(appServicesProvider), widget.peer);

  /// Tryb „znak po znaku": echo tego, co poszło od ostatniego Entera.
  final _echo = TextEditingController();
  final _echoFocus = FocusNode(debugLabel: 'echo pisania');

  /// Tryb „całość naraz": tekst czekający na Wyślij. Pole wielowierszowe
  /// i zasłonięte jednowierszowe to dwa pola z osobnymi węzłami fokusu:
  /// fokus przechodzi na nowe pole, a z nim połączenie z klawiaturą.
  final _tekst = TextEditingController();
  final _tekstFocus = FocusNode(debugLabel: 'tekst do wysłania');
  final _tajnyTekstFocus = FocusNode(debugLabel: 'zasłonięty tekst');

  /// Treść echa, która już poszła na drugą stronę.
  String _wyslane = '';
  _Tryb _tryb = _Tryb.live;
  bool _zEnterem = false;

  /// Prośba o sesję w drodze.
  bool _laczy = true;

  /// Sesja choć raz ruszyła: od tej chwili ekran pokazuje pola, także po
  /// zerwaniu, żeby było widać, co zostało napisane.
  bool _byla = false;

  /// Dlaczego nie udało się połączyć ponownie.
  String? _porazka;

  /// Ekran zakończył już sesję (wyjście z niego). Od tej chwili nie rusza
  /// sesji serwisu, która może już należeć do następnego ekranu.
  bool _zatrzymana = false;

  /// Stan sprzed zakończenia: ekran w trakcie zamykania pokazuje dalej to,
  /// co pokazywał przed wyjściem.
  OutgoingRemoteInput? _ostatni;

  /// Ile odpowiedzi na paczki z tekstem już widział ten ekran.
  int _odpowiedzi = 0;

  /// Treść echa i pola „całość naraz" powstała pod maską (pole hasła albo
  /// pole nieznanego rodzaju). Maska zostaje, dopóki ta treść jest w polu,
  /// także gdy fokus po drugiej stronie przejdzie do zwykłego pola.
  bool _tajneEcho = false;
  bool _tajnyTekst = false;

  /// Maska pola „całość naraz" przy ostatnim budowaniu: jej zmiana podłącza
  /// pole od nowa, a fokus ma przy nim zostać.
  bool? _maskaTekstu;

  /// Na tym urządzeniu wisi karta z pytaniem. Pisanie stoi, dopóki ktoś na
  /// nią nie odpowie.
  bool _kartaTutaj = false;
  late final Listenable _karty;

  @override
  void initState() {
    super.initState();
    _echo.addListener(_poZmianieEcha);
    _tekst.addListener(_poZmianieTekstu);
    _link.state.addListener(_poStanie);
    final services = ref.read(appServicesProvider);
    _karty = Listenable.merge([
      services.pendingOffers,
      services.pendingPairings,
      services.pendingRemoteInput,
    ]);
    _karty.addListener(_poKartach);
    _kartaTutaj = _kartyWisza;
    // Po budowaniu: prośba zmienia stan sesji, a ten słyszy także ekran,
    // który właśnie schodzi i jeszcze stoi w drzewie.
    Future.microtask(() => _polacz(pierwszy: true));
  }

  @override
  void dispose() {
    _zakoncz();
    _link.state.removeListener(_poStanie);
    _karty.removeListener(_poKartach);
    _echo.dispose();
    _echoFocus.dispose();
    _tekst.dispose();
    _tekstFocus.dispose();
    _tajnyTekstFocus.dispose();
    super.dispose();
  }

  /// Koniec sesji tego ekranu, raz: przy zdjęciu trasy, a gdyby ta zniknęła
  /// bez zdjęcia, przy `dispose`. Prośbę bez odpowiedzi wycofuje.
  void _zakoncz() {
    if (_zatrzymana) return;
    _zatrzymana = true;
    unawaited(_link.stop());
  }

  bool get _kartyWisza {
    final services = ref.read(appServicesProvider);
    return services.pendingOffers.value.isNotEmpty ||
        services.pendingPairings.value.isNotEmpty ||
        services.pendingRemoteInput.value.isNotEmpty;
  }

  /// Stan tej sesji. Stan cudzej (innego rozmówcy) ekranu nie dotyczy.
  OutgoingRemoteInput? get _stan {
    if (_zatrzymana) return _ostatni;
    final stan = _link.state.value;
    return stan != null && stan.peerGuid == widget.peer.guid ? stan : null;
  }

  /// Sesja trwa (także wstrzymana kartą po drugiej stronie).
  bool get _sesja {
    final stan = _stan;
    return !_laczy &&
        stan != null &&
        (stan.state == OutgoingRemoteInputState.active ||
            stan.state == OutgoingRemoteInputState.paused);
  }

  /// Pisanie ma dokąd trafić: sesja trwa i nie stoi, po drugiej stronie jest
  /// pole, które przyjmie tekst (także pole samego Chatt), a tutaj żadna
  /// karta nie czeka na odpowiedź.
  /// Inaczej pola są tylko do odczytu: tekst wpisany w próżnię zostałby
  /// w echu bez odpowiednika po drugiej stronie, i następny Backspace
  /// kasowałby tam cudzy tekst.
  bool get _mozna {
    final stan = _stan;
    if (_laczy ||
        _kartaTutaj ||
        stan == null ||
        stan.state != OutgoingRemoteInputState.active) {
      return false;
    }
    final cel = stan.target;
    return cel.active && !cel.locked && !cel.elevated;
  }

  /// Druga strona nie powiedziała wprost, że to zwykłe pole tekstowe.
  bool get _zaslonCelu => _stan?.target.field != RemoteInputField.text;

  void _poStanie() {
    if (_zatrzymana) return;
    final stan = _stan;
    if (stan == null) return;
    _ostatni = stan;
    // Odbiorca nie wpisał tekstu z paczki (pauza, brak pola, Chatt na
    // wierzchu): echo pokazywałoby coś, czego tam nie ma. Każda taka
    // odpowiedź, także druga z rzędu.
    if (stan.typedReplies != _odpowiedzi) {
      _odpowiedzi = stan.typedReplies;
      if (!stan.applied) _oproznij();
    }
  }

  void _poKartach() {
    if (!mounted) return;
    final wisza = _kartyWisza;
    final zmiana = wisza != _kartaTutaj;
    if (zmiana) setState(() => _kartaTutaj = wisza);
    if (wisza) {
      // Karta bierze fokus klatkę po pokazaniu (przy pliku przycisk
      // Akceptuj), także następna karta z kolejki. Piszący patrzy na drugie
      // urządzenie, więc spacja albo Enter odpowiedziałyby na kartę bez
      // czytania. Fokus wraca do pola, które teraz niczego nie wysyła; na
      // kartę odpowiada się kliknięciem. Dwie klatki: karta prosi o fokus
      // w swojej pierwszej, a ten ekran ma przyjść po niej.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _wrocFokusTeraz());
        WidgetsBinding.instance.scheduleFrame();
      });
    } else if (zmiana) {
      _wrocFokus();
    }
  }

  void _wrocFokus() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _wrocFokusTeraz());
  }

  void _wrocFokusTeraz() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    (_tryb == _Tryb.live ? _echoFocus : _fokusTekstu).requestFocus();
  }

  /// Węzeł fokusu pola „całość naraz", które teraz stoi na ekranie.
  FocusNode get _fokusTekstu =>
      (_maskaTekstu ?? false) ? _tajnyTekstFocus : _tekstFocus;

  Future<void> _polacz({bool pierwszy = false}) async {
    if (!pierwszy) {
      if (_laczy || _zatrzymana) return;
      setState(() {
        _laczy = true;
        _porazka = null;
      });
    }
    if (!mounted || _zatrzymana) return;
    final wynik = await _link.start();
    // Ekran zamknięty w trakcie czekania: jego sesja jest już wycofana.
    if (!mounted || _zatrzymana) return;
    setState(() => _laczy = false);
    if (wynik == RemoteInputStart.accepted) {
      _oproznij();
      _odpowiedzi = _stan?.typedReplies ?? 0;
      setState(() => _byla = true);
      _wrocFokus();
      return;
    }
    if (wynik == RemoteInputStart.cancelled) return;
    final opis = _opisPorazki(context.l10n, wynik);
    showToast(opis);
    if (pierwszy) {
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop();
      }
    } else {
      setState(() => _porazka = opis);
    }
  }

  String _opisPorazki(AppLocalizations teksty, RemoteInputStart wynik) {
    final nazwa = widget.peer.displayName;
    return switch (wynik) {
      RemoteInputStart.addonOff => teksty.remoteKeyboardAddonOff,
      RemoteInputStart.notVerified => teksty.remoteKeyboardNotVerified,
      RemoteInputStart.rejected => teksty.remoteKeyboardRejected(nazwa),
      RemoteInputStart.notEnabled => teksty.remoteKeyboardNotEnabled(nazwa),
      RemoteInputStart.noAnswer => teksty.remoteKeyboardNoAnswer(nazwa),
      RemoteInputStart.busy => teksty.remoteKeyboardBusy(nazwa),
      RemoteInputStart.olderPeer => teksty.remoteKeyboardOlderPeer(nazwa),
      RemoteInputStart.unreachable => teksty.remoteKeyboardUnreachable(nazwa),
      RemoteInputStart.accepted ||
      RemoteInputStart.cancelled =>
        teksty.remoteKeyboardLost,
    };
  }

  /// Kolejka serwisu przyjęła operacje. Odmowa przy polu, które przyjmuje
  /// tekst, znaczy za dużo tekstu naraz.
  bool _wyslij(List<RemoteInputOp> ops) {
    if (ops.isEmpty) return true;
    if (!_mozna) return false;
    if (_link.send(ops)) return true;
    showToast(context.l10n.remoteKeyboardTooLong);
    return false;
  }

  /// Echo zaczyna od zera: to, co w nim było, zostaje po drugiej stronie,
  /// a następny Backspace na pustym echu kasuje już tam.
  void _oproznij() {
    _wyslane = '';
    if (_tajneEcho) {
      _tajneEcho = false;
      if (mounted) setState(() {});
    }
    _echo.clear();
  }

  void _poZmianieEcha() {
    final wartosc = _echo.value;
    // Klawiatura w trakcie składania znaku (martwe klawisze, IME): pole
    // zostaje nietknięte, bo przestawienie kursora w środku składania
    // psuje je na Windows. Idzie dopiero gotowy znak.
    if (wartosc.composing.isValid && !wartosc.composing.isCollapsed) return;
    final koniec = wartosc.text.length;
    if (wartosc.selection.baseOffset != koniec ||
        wartosc.selection.extentOffset != koniec) {
      // Kursor zawsze na końcu: echo odpowiada temu, co stoi przed kursorem
      // po drugiej stronie, i tylko tam wolno dopisywać i kasować.
      _echo.value =
          wartosc.copyWith(selection: TextSelection.collapsed(offset: koniec));
      return;
    }
    if (wartosc.text == _wyslane) return;
    if (_wyslij(echoOps(_wyslane, wartosc.text))) {
      _wyslane = wartosc.text;
      if (_zaslonCelu && wartosc.text.isNotEmpty) _tajneEcho = true;
    } else {
      _echo.value = TextEditingValue(
        text: _wyslane,
        selection: TextSelection.collapsed(offset: _wyslane.length),
      );
    }
  }

  void _poZmianieTekstu() {
    final tajny = _tekst.text.isNotEmpty && (_tajnyTekst || _zaslonCelu);
    if (tajny != _tajnyTekst && mounted) setState(() => _tajnyTekst = tajny);
  }

  void _enter({required bool shift}) {
    if (!_mozna) return;
    _oproznij();
    _wyslij([
      shift ? const RemoteInputOp.insert('\n') : const RemoteInputOp.action(),
    ]);
  }

  KeyEventResult _klawisz(FocusNode _, KeyEvent zdarzenie) {
    if (zdarzenie is KeyUpEvent) return KeyEventResult.ignored;
    final klawisz = zdarzenie.logicalKey;
    if (_bezSkutku.contains(klawisz)) return KeyEventResult.handled;
    // Bez pola po drugiej stronie albo przy karcie tutaj reszta klawiszy
    // idzie zwykłą drogą i w polu tylko do odczytu nic nie zmienia.
    if (!_mozna) return KeyEventResult.ignored;
    final klawiatura = HardwareKeyboard.instance;
    if (klawisz == LogicalKeyboardKey.enter ||
        klawisz == LogicalKeyboardKey.numpadEnter) {
      _enter(shift: klawiatura.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (klawisz == LogicalKeyboardKey.backspace && _echo.text.isEmpty) {
      _wyslij(const [RemoteInputOp.backspace(1)]);
      return KeyEventResult.handled;
    }
    if (klawisz == LogicalKeyboardKey.delete) {
      // Kasuje za kursorem po drugiej stronie; echo się nie zmienia, bo
      // kursor stoi tam, gdzie stał.
      _wyslij(const [RemoteInputOp.delete(1)]);
      return KeyEventResult.handled;
    }
    // Wklejenie: echo bez zaznaczania nie wkleja samo, więc Ctrl+V
    // i Shift+Insert idą jak przycisk „Wklej ze schowka".
    final wklej = (klawisz == LogicalKeyboardKey.keyV &&
            (klawiatura.isControlPressed || klawiatura.isMetaPressed) &&
            !klawiatura.isAltPressed) ||
        (klawisz == LogicalKeyboardKey.insert && klawiatura.isShiftPressed);
    if (wklej) {
      if (zdarzenie is KeyDownEvent) unawaited(_wklej());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _wklej() async {
    final teksty = context.l10n;
    final dane = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || !_mozna) return;
    final tekst = dane?.text ?? '';
    if (tekst.isEmpty) {
      showToast(teksty.remoteKeyboardClipboardEmpty);
      return;
    }
    if (_tryb == _Tryb.live) _oproznij();
    _wyslij([RemoteInputOp.insert(tekst)]);
    _wrocFokus();
  }

  void _wyslijBlok() {
    if (!_mozna) return;
    final tekst = _tekst.text;
    if (tekst.isEmpty && !_zEnterem) return;
    if (_wyslij([
      if (tekst.isNotEmpty) RemoteInputOp.insert(tekst),
      if (_zEnterem) const RemoteInputOp.action(),
    ])) {
      _tekst.clear();
    }
    _fokusTekstu.requestFocus();
  }

  void _zmienTryb(_Tryb tryb) {
    if (tryb == _tryb) return;
    setState(() {
      _tryb = tryb;
      _oproznij();
    });
    _wrocFokus();
  }

  /// Skróty cofania. Cofnięcie w echu nie ma odpowiednika po drugiej
  /// stronie, a w polu „całość naraz" przywracałoby wysłany tekst, także
  /// hasło.
  static const Map<ShortcutActivator, Intent> _bezCofania = {
    SingleActivator(LogicalKeyboardKey.keyZ, control: true):
        DoNothingAndStopPropagationTextIntent(),
    SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
        DoNothingAndStopPropagationTextIntent(),
    SingleActivator(LogicalKeyboardKey.keyY, control: true):
        DoNothingAndStopPropagationTextIntent(),
  };

  @override
  Widget build(BuildContext context) {
    final teksty = context.l10n;
    return PopScope(
      // Sesja kończy się w chwili zdjęcia ekranu: zanim skończy się
      // animacja, można już otworzyć następny, a ten nie ma ruszyć jego
      // sesji.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _zakoncz();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(teksty.remoteKeyboardTitle(widget.peer.displayName)),
        ),
        body: SafeArea(
          child: ValueListenableBuilder<OutgoingRemoteInput?>(
            valueListenable: _link.state,
            builder: (context, _, _) {
              final stan = _stan;
              final sesja = _sesja;
              final mozna = _mozna;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_laczy)
                        _Czekanie(
                          nazwa: widget.peer.displayName,
                          onCancel: () => Navigator.of(context).maybePop(),
                        )
                      else
                        _Stan(
                          opis: _opisStanu(teksty, stan),
                          rtt: sesja ? stan?.rtt : null,
                          protocol: sesja ? stan?.protocol : null,
                          onReconnect: sesja ? null : () => _polacz(),
                        ),
                      if (_byla) ...[
                        const SizedBox(height: 16),
                        SegmentedButton<_Tryb>(
                          segments: [
                            ButtonSegment(
                              value: _Tryb.live,
                              icon: const Icon(Icons.bolt_outlined),
                              label: Text(teksty.remoteKeyboardModeLive),
                            ),
                            ButtonSegment(
                              value: _Tryb.compose,
                              icon: const Icon(Icons.edit_note_outlined),
                              label: Text(teksty.remoteKeyboardModeCompose),
                            ),
                          ],
                          selected: {_tryb},
                          onSelectionChanged: (wybor) =>
                              _zmienTryb(wybor.first),
                        ),
                        const SizedBox(height: 16),
                        if (_tryb == _Tryb.live)
                          ..._live(teksty, mozna)
                        else
                          ..._compose(teksty, mozna),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: mozna ? _wklej : null,
                              icon: const Icon(Icons.content_paste),
                              label: Text(teksty.remoteKeyboardPaste),
                            ),
                            const Spacer(),
                            FilledButton.tonalIcon(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: Text(teksty.remoteInputStop),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _live(AppLocalizations teksty, bool mozna) {
    final scheme = Theme.of(context).colorScheme;
    return [
      Shortcuts(
        shortcuts: _bezCofania,
        child: Focus(
          onKeyEvent: _klawisz,
          child: TextField(
            controller: _echo,
            focusNode: _echoFocus,
            autofocus: true,
            readOnly: !mozna,
            obscureText: _zaslonCelu || _tajneEcho,
            maxLines: 1,
            enableInteractiveSelection: false,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            textInputAction: TextInputAction.done,
            // Enter z klawiatury ekranowej. Fizyczny Enter łapie [_klawisz]
            // wcześniej, więc nie idzie dwa razy.
            onSubmitted: (_) => _enter(shift: false),
            onEditingComplete: () {},
            decoration: InputDecoration(
              hintText: teksty.remoteKeyboardLiveHint,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.keyboard_alt_outlined),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        teksty.remoteKeyboardKeysHint,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
    ];
  }

  List<Widget> _compose(AppLocalizations teksty, bool mozna) {
    final zaslon = _zaslonCelu || _tajnyTekst;
    // Zmiana maski to drugie pole: fokus, który miało poprzednie, przechodzi
    // na nowe w następnej klatce.
    final mialoFokus = _fokusTekstu.hasFocus;
    final zmiana = _maskaTekstu != null && _maskaTekstu != zaslon;
    _maskaTekstu = zaslon;
    if (zmiana && mialoFokus) _wrocFokus();
    return [
      Shortcuts(
        shortcuts: _bezCofania,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter,
                control: true, includeRepeats: false): _wyslijBlok,
            const SingleActivator(LogicalKeyboardKey.numpadEnter,
                control: true, includeRepeats: false): _wyslijBlok,
          },
          child: TextField(
            // Pole jednowierszowe (hasło) i wielowierszowe to dla Windows
            // dwa różne pola: zmiana maski podłącza pole od nowa, inaczej
            // Enter zostałby przy dawnym zachowaniu.
            key: ValueKey(zaslon),
            controller: _tekst,
            focusNode: zaslon ? _tajnyTekstFocus : _tekstFocus,
            autofocus: true,
            readOnly: !mozna,
            obscureText: zaslon,
            minLines: zaslon ? 1 : 3,
            maxLines: zaslon ? 1 : 8,
            keyboardType:
                zaslon ? TextInputType.text : TextInputType.multiline,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            // Enter w polu jednowierszowym wysyła całość; fokus zostaje.
            onSubmitted: zaslon ? (_) => _wyslijBlok() : null,
            onEditingComplete: () {},
            decoration: InputDecoration(
              hintText: teksty.remoteKeyboardComposeHint,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Checkbox(
            value: _zEnterem,
            onChanged: (value) => setState(() => _zEnterem = value ?? false),
          ),
          GestureDetector(
            onTap: () => setState(() => _zEnterem = !_zEnterem),
            child: Text(teksty.remoteKeyboardThenEnter),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: mozna ? _wyslijBlok : null,
            icon: const Icon(Icons.send),
            label: Text(teksty.remoteKeyboardSend),
          ),
        ],
      ),
    ];
  }

  ({IconData ikona, String tekst, bool uwaga}) _opisStanu(
      AppLocalizations teksty, OutgoingRemoteInput? stan) {
    if (stan == null ||
        stan.state == OutgoingRemoteInputState.disconnected ||
        stan.state == OutgoingRemoteInputState.waiting) {
      final tekst = _porazka ??
          (stan?.reason != null
              ? teksty.remoteKeyboardEnded(widget.peer.displayName)
              : teksty.remoteKeyboardLost);
      return (ikona: Icons.link_off, tekst: tekst, uwaga: true);
    }
    if (_kartaTutaj) {
      return (
        ikona: Icons.pause_circle_outline,
        tekst: teksty.remoteKeyboardLocalCard,
        uwaga: true,
      );
    }
    if (stan.state == OutgoingRemoteInputState.paused) {
      return (
        ikona: Icons.pause_circle_outline,
        tekst: teksty.remoteKeyboardPaused,
        uwaga: true,
      );
    }
    final cel = stan.target;
    if (cel.locked) {
      return (
        ikona: Icons.lock_outline,
        tekst: teksty.remoteKeyboardLocked,
        uwaga: true,
      );
    }
    if (cel.elevated) {
      return (
        ikona: Icons.admin_panel_settings_outlined,
        tekst: teksty.remoteKeyboardElevated,
        uwaga: true,
      );
    }
    if (!cel.active) {
      return (
        ikona: Icons.touch_app_outlined,
        tekst: teksty.remoteKeyboardNoField,
        uwaga: true,
      );
    }
    final aplikacja = cel.appLabel.isNotEmpty
        ? cel.appLabel
        : (cel.app.isNotEmpty ? cel.app : '?');
    return cel.field == RemoteInputField.password
        ? (
            ikona: Icons.password,
            tekst: teksty.remoteKeyboardTargetPassword(aplikacja),
            uwaga: false,
          )
        : (
            ikona: Icons.keyboard_alt_outlined,
            tekst: teksty.remoteKeyboardTarget(aplikacja),
            uwaga: false,
          );
  }
}

/// Prośba poszła, karta wisi po drugiej stronie.
class _Czekanie extends StatelessWidget {
  final String nazwa;
  final VoidCallback onCancel;

  const _Czekanie({required this.nazwa, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.remoteKeyboardWaiting(nazwa)),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.remoteKeyboardWaitingHint,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                child: Text(context.l10n.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dokąd idzie pisanie, albo czemu nie idzie.
class _Stan extends ConsumerWidget {
  final ({IconData ikona, String tekst, bool uwaga}) opis;
  final Duration? rtt;
  final PeerProtocol? protocol;

  /// Sesji nie ma: przycisk ponownego połączenia.
  final VoidCallback? onReconnect;

  const _Stan({
    required this.opis,
    required this.rtt,
    required this.protocol,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final kolor = opis.uwaga ? scheme.error : scheme.primary;
    final services = ref.read(appServicesProvider);
    final maly = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(opis.ikona, color: kolor),
            const SizedBox(width: 12),
            Expanded(child: Text(opis.tekst)),
            if (rtt != null) ...[
              const SizedBox(width: 12),
              Text('${rtt!.inMilliseconds} ms', style: maly),
            ],
            // Droga ma znaczenie tylko przy dodatku Bluetooth: bez niego
            // zawsze jest jedna.
            if (protocol != null)
              ValueListenableBuilder<bool>(
                valueListenable: services.bluetoothAddon,
                builder: (context, radio, _) => radio
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Tooltip(
                          message: protocol == PeerProtocol.bluetooth
                              ? context.l10n.viaBluetooth
                              : context.l10n.viaWifi,
                          child: Icon(
                            protocol == PeerProtocol.bluetooth
                                ? Icons.bluetooth
                                : Icons.wifi,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            if (onReconnect != null) ...[
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onReconnect,
                child: Text(context.l10n.remoteKeyboardReconnect),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
