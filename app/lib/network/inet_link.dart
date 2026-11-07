import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'dht.dart';
import 'rendezvous.dart';
import 'secure_udp.dart';
import 'stun.dart';
import 'udp_mux.dart';

/// Menedżer drogi internetowej: spina STUN, DHT, skrzynkę kontaktową
/// i przebicie dziury w jedną funkcję „połącz mnie z tym rozmówcą".
///
/// Pomiar na sprzęcie (docs/spike-nat.md) pokazał, że NAT po obu stronach
/// wpuszcza pakiet tylko od kogoś, do kogo urządzenie samo coś wysłało.
/// Połączenie wymaga więc ruchu z obu stron:
///
///  1. Dzwoniący pyta STUN o swój publiczny adres, wpisuje go do swojej
///     skrzynki w DHT ze znacznikiem „dzwonię" i czyta skrzynkę odbiorcy.
///  2. Dzwoniący nadaje HELLO pod adres odbiorcy przez [punchTimeout]. Co
///     [relookup] czyta skrzynkę odbiorcy ponownie, bo ten mógł w tym czasie
///     podać nowy adres.
///  3. Odbiorca co [watchInterval] czyta skrzynki potwierdzonych rozmówców,
///     z którymi nie ma łącza. Gdy zobaczy świeży znacznik „dzwonię", puka
///     pod adres dzwoniącego i odświeża swój adres w skrzynce, jeśli NAT go
///     zmienił. Pukanie otwiera jego NAT na adres dzwoniącego, więc następne
///     HELLO dochodzi.
///  4. Gdy klucze się zgodzą, [SecureUdpPipe] staje i nad nią działa zwykły
///     multiplekser żądań i odpowiedzi.
///
/// Połączenie przychodzące: menedżer rozpoznaje HELLO, sprawdza guid nadawcy
/// przez [resolveStatic] (tylko rozmówca z zieloną tarczą ma tu klucz)
/// i stawia stronę przyjmującą. Gdy obie strony dzwonią naraz, ustępuje ta
/// z większym guidem, więc zostaje jedno łącze.

/// Skąd wziąć klucz statyczny i skrzynkę dla danego guida. Zwraca null, gdy
/// rozmówca nie jest potwierdzony: wtedy droga internetowa go nie obsługuje.
typedef StaticKeyResolver = Future<List<int>?> Function(String guid);
typedef RendezvousResolver = Future<Rendezvous?> Function(String guid);

/// Guidy rozmówców, do których skrzynek wpisujemy swój adres i których
/// skrzynki czytamy, żeby odebrać ich połączenie. Zwykle wszyscy z zieloną
/// tarczą.
typedef VerifiedPeersResolver = Future<List<String>> Function();

/// Co ile odbiorca czyta skrzynkę rozmówcy, z którym nie ma łącza.
const Duration kWatchInterval = Duration(seconds: 60);

/// Pusta skrzynka (rozmówca bez dodatku albo dawno poza siecią): po
/// [kWatchPatience] pustych odczytach z rzędu odstęp rośnie dwukrotnie aż do
/// tej wartości. Rozmówca z włączonym dodatkiem odświeża swój rekord co
/// [kPublishInterval], więc pusta skrzynka go nie dotyczy.
const Duration kWatchMax = Duration(minutes: 15);

/// Ile pustych odczytów z rzędu przed wydłużaniem odstępu. Pierwszy odczyt
/// tuż po starcie zwykle bywa pusty, bo rozmówca jeszcze nic nie wpisał,
/// a dzwoniący przebija krócej niż dwa odstępy.
const int kWatchPatience = 5;

/// Odstęp do następnego odczytu skrzynki po [emptyReads] pustych odczytach
/// z rzędu, gdy poprzedni odstęp wynosił [previous]. Dopóki pustych jest mniej
/// niż [kWatchPatience], odczyt idzie co [interval]; potem odstęp rośnie
/// dwukrotnie do [max]. Rekord w skrzynce zeruje licznik.
Duration watchGapAfter(int emptyReads, Duration? previous,
    {Duration interval = kWatchInterval, Duration max = kWatchMax}) {
  if (emptyReads < kWatchPatience) return interval;
  final dluzszy = (previous ?? interval) * 2;
  return dluzszy > max ? max : dluzszy;
}

/// Znacznik „dzwonię" starszy niż to już nie budzi pukania.
const Duration kCallFresh = Duration(minutes: 2);

/// Jak długo dzwoniący przebija. Dłużej niż [kWatchInterval] razem
/// z odczytem skrzynki w DHT, więc odbiorca zdąży zobaczyć znacznik
/// i zapukać.
const Duration kPunchTimeout = Duration(seconds: 90);

/// Co ile dzwoniący w trakcie przebijania czyta skrzynkę odbiorcy ponownie.
const Duration kRelookup = Duration(seconds: 15);

/// Pierwszy odstęp między pukaniami; kolejne rosną dwukrotnie.
const Duration kKnockGap = Duration(milliseconds: 500);

/// Jak długo odbiorca puka, gdy łącze nie staje.
const Duration kKnockFor = Duration(seconds: 45);

/// Co ile odświeżamy własny adres w skrzynce (NAT mógł przestawić port).
const Duration kPublishInterval = Duration(minutes: 10);

/// Stan jednego połączenia, do interfejsu.
enum InetLinkPhase { idle, resolving, punching, up, failed }

class InetLinkManager {
  final UdpMux mux;
  final SimpleKeyPair myStatic;
  final List<int> myStaticPub;
  final String myGuid;
  final StaticKeyResolver resolveStatic;
  final RendezvousResolver resolveRendezvous;

  /// Czyje skrzynki dostają nasz adres i czyje czytamy (zob.
  /// [VerifiedPeersResolver]). Gdy null, urządzenie tylko dzwoni: nie
  /// publikuje adresu samo z siebie i nie odbiera połączeń zza NAT-u.
  final VerifiedPeersResolver? verifiedPeers;

  /// Wołane, gdy łącze stanie albo padnie (log, interfejs).
  final void Function(String guid, InetLinkPhase phase, String reason)? onPhase;

  /// Szczegóły dla narzędzia pomiarowego: każdy odczyt i zapis skrzynki.
  void Function(String message)? onDebug;

  final Duration watchInterval;
  final Duration watchMax;
  final Duration punchTimeout;
  final Duration relookup;
  final Duration knockGap;
  final Duration knockFor;

  late final StunClient _stun = StunClient(mux);
  late final DhtClient _dht = DhtClient(mux);

  /// Łącza po guidzie rozmówcy.
  final _pipes = <String, SecureUdpPipe>{};

  /// Łącza po bieżącym adresie drugiej strony: tędy trafiają pakiety danych
  /// i HELLO_ACK do właściwej rury. Przepinane, gdy NAT przestawi port.
  final _byRemote = <String, SecureUdpPipe>{};

  /// Trwające nawiązywania, żeby dwa żądania naraz nie przebijały dwa razy.
  final _connecting = <String, Future<SecureUdpPipe?>>{};

  /// Guidy, których HELLO właśnie przyjmujemy (sprawdzanie klucza trwa,
  /// a HELLO przychodzi co 400 ms).
  final _accepting = <String>{};

  /// Ostatnio zmierzony własny adres publiczny (IPv4).
  StunMapping? _publicV4;

  /// Adres, który ostatnio trafił do skrzynki danego rozmówcy.
  final _publishedTo = <String, String>{};

  Timer? _publishTimer;
  Timer? _watchTimer;
  bool _running = false;
  bool _watching = false;

  /// Kiedy następny odczyt skrzynki rozmówcy i jaki odstęp ostatnio.
  final _nextWatch = <String, DateTime>{};
  final _watchGap = <String, Duration>{};
  final _emptyReads = <String, int>{};

  /// Znacznik czasu rekordu „dzwonię", na który już zapukaliśmy.
  final _answered = <String, int>{};

  InetLinkManager({
    required this.mux,
    required this.myStatic,
    required this.myStaticPub,
    required this.myGuid,
    required this.resolveStatic,
    required this.resolveRendezvous,
    this.verifiedPeers,
    this.onPhase,
    this.watchInterval = kWatchInterval,
    this.watchMax = kWatchMax,
    this.punchTimeout = kPunchTimeout,
    this.relookup = kRelookup,
    this.knockGap = kKnockGap,
    this.knockFor = kKnockFor,
  });

  bool get isRunning => _running;
  StunMapping? get publicAddress => _publicV4;

  /// Klient DHT tego menedżera: testy wstrzykują mu węzły rozruchowe wprost
  /// (`manager.dht.debugBootstrap = [...]`), żeby obejść DNS i prawdziwą sieć.
  DhtClient get dht => _dht;

  /// Gdy ustawione, [_refreshPublic] bierze adres stąd i nie pyta STUN-u.
  /// Do testów nad siecią w pamięci, gdzie nie ma serwerów STUN; funkcja,
  /// bo NAT w pamięci potrafi zmienić mapowanie.
  StunMapping? Function()? debugStun;

  /// Stały adres, skrót dla [debugStun].
  set debugPublic(StunMapping? mapping) =>
      debugStun = mapping == null ? null : () => mapping;

  /// Rozpoznaje pakiety HELLO od jeszcze nieznanych adresów. STUN, DHT
  /// i stojące łącza mają własne handlery zarejestrowane wcześniej, więc tu
  /// trafia tylko to, czego nikt nie wziął.
  void start() {
    if (_running) return;
    _running = true;
    mux.register(_onPacket);
    // Od razu wpisujemy swój adres do skrzynek, żeby odbiorca był osiągalny,
    // nim ktokolwiek zadzwoni; potem co [kPublishInterval], bo NAT przestawia
    // port.
    unawaited(_publishToAll());
    _publishTimer =
        Timer.periodic(kPublishInterval, (_) => unawaited(_publishToAll()));
    if (verifiedPeers != null) {
      _watchTimer = Timer.periodic(_watchTick, (_) => unawaited(_watchRound()));
      unawaited(_watchRound());
    }
  }

  /// Zegar przeglądu skrzynek: częściej niż [watchInterval], bo każdy
  /// rozmówca ma własny termin.
  Duration get _watchTick {
    final t = watchInterval ~/ 4;
    if (t < const Duration(milliseconds: 20)) {
      return const Duration(milliseconds: 20);
    }
    return t > const Duration(seconds: 5) ? const Duration(seconds: 5) : t;
  }

  Future<void> stop() async {
    _running = false;
    _publishTimer?.cancel();
    _watchTimer?.cancel();
    mux.unregister(_onPacket);
    for (final pipe in _pipes.values.toList()) {
      await pipe.close(powod: 'add-on off');
    }
    _pipes.clear();
    _byRemote.clear();
    _connecting.clear();
    _stun.dispose();
    await _dht.close();
  }

  /// Pyta STUN o własny adres.
  Future<StunMapping?> _refreshPublic() async {
    final debug = debugStun;
    if (debug != null) {
      _publicV4 = debug();
      return _publicV4;
    }
    final wynik = await _stun.discover();
    _publicV4 = wynik.mapping ?? _publicV4;
    return wynik.mapping;
  }

  /// Wpisuje adres do skrzynki rozmówcy. Zwraca, do ilu węzłów DHT trafił;
  /// błąd sieci daje 0.
  Future<int> _publishTo(String guid, StunMapping mine,
      {required bool calling, Rendezvous? box}) async {
    final skrzynka = box ?? await resolveRendezvous(guid);
    if (skrzynka == null) return 0;
    try {
      final ile = await skrzynka.publish(_dht,
          address: mine.address, port: mine.port, calling: calling);
      if (ile > 0) _publishedTo[guid] = mine.label;
      onDebug?.call('${calling ? 'calling' : 'address'} written for $guid '
          'to $ile DHT nodes');
      return ile;
    } catch (_) {
      return 0;
    }
  }

  /// Odświeża własny adres i wpisuje go do skrzynki każdego potwierdzonego
  /// rozmówcy. Dzięki temu dzwoniący wie, pod jaki adres nadawać.
  Future<void> _publishToAll() async {
    final peers = verifiedPeers;
    if (peers == null) return;
    final mine = await _refreshPublic();
    if (mine == null) return;
    List<String> guids;
    try {
      guids = await peers();
    } catch (_) {
      return;
    }
    for (final guid in guids) {
      if (!_running) return;
      // Rozmówca, do którego właśnie dzwonimy, dostaje znacznik „dzwonię"
      // także tutaj, żeby zwykłe odświeżenie nie skasowało go w trakcie.
      // Zapis, który nie trafił do żadnego węzła, ponawiamy od razu: bez
      // adresu w skrzynce nikt się do nas nie dodzwoni aż do następnej rundy.
      for (var proba = 0; proba < 3 && _running; proba++) {
        final ile = await _publishTo(guid, mine,
            calling: _connecting.containsKey(guid));
        if (ile > 0) break;
      }
    }
  }

  /// Rozmówca właśnie dostał zieloną tarczę: wpisujemy mu swój adres od
  /// razu. Bez tego adres trafiał do jego skrzynki dopiero przy następnym
  /// odświeżeniu (co [kPublishInterval]), a pierwsza wiadomość po parowaniu
  /// kończyła się „peer address not in DHT". Nieudany zapis ponawiamy, jak
  /// w [_publishToAll].
  Future<void> announceTo(String guid) async {
    if (!_running || verifiedPeers == null) return;
    final mine = await _refreshPublic();
    if (mine == null) return;
    for (var proba = 0; proba < 3 && _running; proba++) {
      final ile = await _publishTo(guid, mine,
          calling: _connecting.containsKey(guid));
      if (ile > 0) return;
    }
  }

  /// Odczyt skrzynki rozmówcy w trakcie dzwonienia, liczony jak odczyt przy
  /// przeglądzie: pusta skrzynka podbija licznik pustych odczytów, rekord go
  /// zeruje. Po jednym nieudanym czekaniu kolejne dzwonienie do rozmówcy
  /// bez dodatku kończy się więc od razu.
  Future<RendezvousAddress?> _lookupCounted(String guid, Rendezvous box) async {
    final rekord = await _lookup(box);
    _emptyReads[guid] = rekord == null ? (_emptyReads[guid] ?? 0) + 1 : 0;
    return rekord;
  }

  Future<RendezvousAddress?> _lookup(Rendezvous box) async {
    try {
      return await box.lookup(_dht);
    } catch (_) {
      return null;
    }
  }

  // --- odbiorca: czytanie skrzynek i pukanie -------------------------------

  /// Jedna runda przeglądu: skrzynki rozmówców bez łącza, którym minął
  /// termin. Rekord jest: następny odczyt za [watchInterval]. Rekordu nie ma
  /// [kWatchPatience] razy z rzędu: odstęp rośnie dwukrotnie do [watchMax].
  Future<void> _watchRound() async {
    final peers = verifiedPeers;
    if (peers == null || _watching || !_running) return;
    _watching = true;
    try {
      final List<String> guids;
      try {
        guids = await peers();
      } catch (_) {
        return;
      }
      for (final guid in guids) {
        if (!_running) return;
        if (isLinked(guid)) {
          // Po zerwaniu łącza czytamy od nowa w podstawowym odstępie.
          _nextWatch.remove(guid);
          _watchGap.remove(guid);
          _emptyReads.remove(guid);
          continue;
        }
        // W trakcie dzwonienia skrzynkę czyta samo dzwonienie. Licznik
        // pustych odczytów zostaje: następne dzwonienie ma wiedzieć, że
        // skrzynka od dawna stoi pusta, i nie czekać na nią znowu 90 s.
        if (_connecting.containsKey(guid)) continue;
        final termin = _nextWatch[guid];
        if (termin != null && DateTime.now().isBefore(termin)) continue;
        final box = await resolveRendezvous(guid);
        if (box == null) continue;
        final rekord = await _lookup(box);
        if (rekord == null) {
          onDebug?.call('box of $guid: empty');
        } else {
          final wiek =
              (DateTime.now().millisecondsSinceEpoch - rekord.timestamp) ~/
                  1000;
          onDebug?.call('box of $guid: '
              '${rekord.calling ? 'calling' : 'address'}, $wiek s old');
        }
        final puste = rekord == null ? (_emptyReads[guid] ?? 0) + 1 : 0;
        _emptyReads[guid] = puste;
        final odstep = watchGapAfter(puste, _watchGap[guid],
            interval: watchInterval, max: watchMax);
        _watchGap[guid] = odstep;
        _nextWatch[guid] = DateTime.now().add(odstep);
        if (rekord != null &&
            rekord.calling &&
            _fresh(rekord) &&
            _answered[guid] != rekord.timestamp &&
            !isLinked(guid)) {
          _answered[guid] = rekord.timestamp;
          unawaited(_answer(guid, box, rekord));
        }
      }
    } finally {
      _watching = false;
    }
  }

  bool _fresh(RendezvousAddress rekord) =>
      DateTime.now().millisecondsSinceEpoch - rekord.timestamp <=
      kCallFresh.inMilliseconds;

  /// Odpowiedź na znacznik „dzwonię": pukanie pod adres dzwoniącego, a gdy
  /// NAT zmienił nasz adres od ostatniego wpisu, także nowy adres w skrzynce.
  /// Dzwoniący czyta ją ponownie co [relookup].
  Future<void> _answer(
      String guid, Rendezvous box, RendezvousAddress caller) async {
    onPhase?.call(guid, InetLinkPhase.punching, 'knocking');
    // Najpierw pukanie: pierwszy pakiet otwiera NAT, zanim skończy się zapis.
    final pukanie = _knock(guid, caller);
    final mine = await _refreshPublic();
    if (mine != null && _publishedTo[guid] != mine.label) {
      await _publishTo(guid, mine, calling: false, box: box);
    }
    await pukanie;
  }

  Future<void> _knock(String guid, RendezvousAddress caller) async {
    final pakiet = knockPacket();
    final koniec = DateTime.now().add(knockFor);
    var przerwa = knockGap;
    while (_running && !isLinked(guid) && DateTime.now().isBefore(koniec)) {
      mux.send(pakiet, caller.address, caller.port);
      await Future<void>.delayed(przerwa);
      przerwa *= 2;
    }
  }

  // --- dzwoniący -----------------------------------------------------------

  /// Zwraca stojące łącze do rozmówcy albo próbuje je postawić. null, gdy się
  /// nie udało (rozmówca nieosiągalny, symetryczny NAT, cisza w skrzynce).
  Future<SecureUdpPipe?> linkTo(String guid) async {
    final przychodzace = pipeFor(guid);
    if (przychodzace != null &&
        !przychodzace.initiator &&
        przychodzace.state == LinkState.handshaking) {
      // Rozmówca właśnie do nas dzwoni: czekamy na jego uścisk, bo własne
      // HELLO tylko by go przerwało.
      final ok = await przychodzace.ready
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
      if (ok) return przychodzace;
    }
    final stojace = pipeFor(guid);
    if (stojace != null && stojace.state == LinkState.up) return stojace;
    // Blok, nie wyrażenie strzałkowe: `Map.remove` oddaje tę samą przyszłość,
    // a `whenComplete` czekałby wtedy sam na siebie i łączenie by stanęło.
    return _connecting[guid] ??= _establish(guid).whenComplete(() {
      _connecting.remove(guid);
    });
  }

  SecureUdpPipe? pipeFor(String guid) {
    final p = _pipes[guid];
    return (p != null && !p.isClosed) ? p : null;
  }

  bool isLinked(String guid) => pipeFor(guid)?.state == LinkState.up;

  List<String> get linkedGuids => [
        for (final e in _pipes.entries)
          if (!e.value.isClosed && e.value.state == LinkState.up) e.key,
      ];

  Future<SecureUdpPipe?> _establish(String guid) async {
    onPhase?.call(guid, InetLinkPhase.resolving, 'looking up');
    final theirStatic = await resolveStatic(guid);
    final rendezvous = await resolveRendezvous(guid);
    if (theirStatic == null || rendezvous == null) {
      onPhase?.call(guid, InetLinkPhase.failed, 'peer not verified');
      return null;
    }

    // Skrzynka odbiorcy była pusta przy tylu odczytach z rzędu jeszcze przed
    // tym dzwonieniem: rozmówca najpewniej nie ma dodatku albo dawno go nie
    // było, więc nie ma na co czekać.
    final dawnoPusta = (_emptyReads[guid] ?? 0) >= kWatchPatience;
    // Własny adres ze znacznikiem „dzwonię", równolegle z odczytem adresu
    // odbiorcy. Odbiorca puka tylko pod adres, który zobaczy w skrzynce,
    // a bez pukania jego NAT nie wpuści HELLO: nieudany zapis ponawiamy.
    final mine = await _refreshPublic();
    if (mine != null) unawaited(_publishCalling(guid, rendezvous, mine));
    var theirs = await _lookupCounted(guid, rendezvous);
    // Pusta skrzynka to jeszcze nie koniec: świeżo potwierdzony rozmówca
    // mógł nie zdążyć wpisać adresu. Przy najbliższym przeglądzie skrzynek
    // zobaczy nasz znacznik „dzwonię", zapuka i wpisze adres, więc czytamy
    // ponownie co [relookup]. Czekanie ma własny limit: przegląd co minutę,
    // zapis znacznika i adresu w DHT i nasz kolejny odczyt razem mieszczą
    // się w [punchTimeout] i jeszcze jednym odstępie [relookup].
    final czekajDo = DateTime.now().add(punchTimeout + relookup);
    while (theirs == null && _running && !dawnoPusta) {
      final reszta = czekajDo.difference(DateTime.now());
      if (reszta <= Duration.zero) break;
      onPhase?.call(guid, InetLinkPhase.resolving, 'waiting for the address');
      await Future<void>.delayed(reszta < relookup ? reszta : relookup);
      // W czasie czekania rozmówca mógł zadzwonić sam: jego łącze wystarczy,
      // a własne HELLO tylko by mu przeszkodziło.
      final przychodzaca = pipeFor(guid);
      if (przychodzaca != null && !przychodzaca.initiator) {
        final zostalo = czekajDo.difference(DateTime.now());
        if (zostalo > Duration.zero &&
            await przychodzaca.ready.timeout(zostalo, onTimeout: () => false)) {
          return przychodzaca;
        }
      }
      theirs = await _lookupCounted(guid, rendezvous);
    }
    if (theirs == null) {
      onPhase?.call(guid, InetLinkPhase.failed, 'peer address not in DHT');
      return null;
    }

    // Przebicie ma pełny czas od chwili, gdy znamy adres.
    final koniec = DateTime.now().add(punchTimeout);
    // Rozmówca mógł zadzwonić sam, gdy czytaliśmy jego skrzynkę. Nowa rura
    // zajęłaby miejsce jego łącza w mapach i jego pakiety trafiałyby do rury
    // bez klucza, więc najpierw czekamy na jego łącze.
    final juzDzwoni = pipeFor(guid);
    if (juzDzwoni != null && !juzDzwoni.initiator) {
      if (await juzDzwoni.ready.timeout(punchTimeout, onTimeout: () => false)) {
        return juzDzwoni;
      }
    }

    SecureUdpPipe? pipe;
    while (_running) {
      final reszta = koniec.difference(DateTime.now());
      if (reszta <= Duration.zero) break;
      var biezaca = pipe;
      if (biezaca == null || biezaca.isClosed) {
        // Pierwsza rura albo poprzednia padła po ciszy: świeży uścisk.
        biezaca = pipe = _newPipe(guid, theirStatic, theirs!.address,
            theirs.port,
            initiator: true);
        onPhase?.call(guid, InetLinkPhase.punching, theirs.toString());
        unawaited(biezaca.connect());
      }
      final krok = reszta < relookup ? reszta : relookup;
      if (await biezaca.ready.timeout(krok, onTimeout: () => false)) {
        return biezaca;
      }
      // Obie strony dzwoniły naraz i nasza rura ustąpiła przychodzącej.
      final przychodzaca = _pipes[guid];
      if (przychodzaca != null &&
          przychodzaca != biezaca &&
          !przychodzaca.isClosed) {
        final zostalo = koniec.difference(DateTime.now());
        if (zostalo > Duration.zero &&
            await przychodzaca.ready.timeout(zostalo, onTimeout: () => false)) {
          return przychodzaca;
        }
        break;
      }
      // Odbiorca mógł w tym czasie wpisać do skrzynki nowy adres.
      final nowszy = await _lookup(rendezvous);
      if (nowszy != null) {
        theirs = nowszy;
        biezaca.retarget(nowszy.address, nowszy.port);
      }
    }
    final ostatnia = pipe;
    if (ostatnia != null &&
        !ostatnia.isClosed &&
        ostatnia.state != LinkState.up) {
      _dropPipe(guid, ostatnia);
      await ostatnia.close(powod: 'punch timed out');
    }
    onPhase?.call(guid, InetLinkPhase.failed, 'hole punching failed');
    return null;
  }

  Future<void> _publishCalling(
      String guid, Rendezvous box, StunMapping mine) async {
    for (var proba = 0; proba < 3 && _running; proba++) {
      if (await _publishTo(guid, mine, calling: true, box: box) > 0) return;
    }
  }

  SecureUdpPipe _newPipe(String guid, List<int> theirStatic,
      InternetAddress address, int port,
      {required bool initiator}) {
    late final SecureUdpPipe pipe;
    pipe = SecureUdpPipe(
      mux: mux,
      myStatic: myStatic,
      myStaticPub: myStaticPub,
      theirStatic: theirStatic,
      myGuid: myGuid,
      remoteAddress: address,
      remotePort: port,
      initiator: initiator,
      onState: (state, reason) => _onPipeState(guid, pipe, state, reason),
    );
    _registerPipe(guid, pipe);
    return pipe;
  }

  /// Wpina rurę do obu map i pilnuje przepięcia adresu po stronie NAT.
  void _registerPipe(String guid, SecureUdpPipe pipe) {
    _pipes[guid] = pipe;
    _byRemote[pipe.remoteLabel] = pipe;
    pipe.onRebind = (stary, nowy) {
      if (_byRemote[stary] == pipe) _byRemote.remove(stary);
      _byRemote[nowy] = pipe;
    };
  }

  void _dropPipe(String guid, SecureUdpPipe pipe) {
    if (_pipes[guid] == pipe) _pipes.remove(guid);
    _byRemote.removeWhere((_, p) => p == pipe);
  }

  void _onPipeState(
      String guid, SecureUdpPipe pipe, LinkState state, String reason) {
    if (state == LinkState.up) {
      onPhase?.call(guid, InetLinkPhase.up, reason);
    } else if (state == LinkState.closed) {
      // Zgłaszamy tylko rurę, która była bieżąca: zastąpiona przez nowszą
      // (nowy uścisk, rozstrzygnięcie dzwonienia naraz) niczego nie zrywa.
      final biezaca = _pipes[guid] == pipe;
      _dropPipe(guid, pipe);
      if (biezaca) onPhase?.call(guid, InetLinkPhase.failed, reason);
    }
  }

  // --- połączenia przychodzące ---------------------------------------------

  bool _onPacket(UdpPacket packet) {
    if (!isLinkPacket(packet.data)) return false; // STUN/DHT biorą swoje
    // Pukanie odbiorcy już zrobiło swoje: otworzyło jego NAT.
    if (isKnock(packet.data)) return true;
    final hello = parseHello(packet.data);
    if (hello == null) {
      // Pakiet stojącego (albo stającego) łącza: dane, HELLO_ACK, zamknięcie.
      // Najpierw po adresie; a gdy ten nie pasuje (NAT przestawił port),
      // próbujemy każdej żywej rury. Zła rura i tak nie odszyfruje pakietu,
      // a właściwa odświeży sobie adres i od tej pory trafia po nim.
      final pipe = _byRemote['${packet.address.address}:${packet.port}'];
      if (pipe != null && !pipe.isClosed) {
        pipe.handlePacket(packet);
        return true;
      }
      for (final p in _pipes.values.toList()) {
        if (!p.isClosed) p.handlePacket(packet);
      }
      return true;
    }
    // HELLO: początek uścisku od strony inicjującej.
    final skad = '${packet.address.address}:${packet.port}';
    final istniejace = _pipes[hello.guid];
    if (istniejace != null && !istniejace.isClosed) {
      if (istniejace.state == LinkState.up) {
        // Już stoimy, a druga strona wciąż powtarza HELLO (zgubiła nasze
        // potwierdzenie): odsyłamy je jeszcze raz, żeby i ona stanęła.
        istniejace.resendConfirm();
        return true;
      }
      if (istniejace.initiator) {
        // Obie strony dzwonią naraz. Prowadzi mniejszy guid: jego HELLO
        // zostaje, a druga strona zamyka swoje i przyjmuje cudze.
        if (myGuid.compareTo(hello.guid) < 0) return true;
        _dropPipe(hello.guid, istniejace);
        unawaited(istniejace.close(powod: 'both called, the other side leads'));
        // Klucz rozmówcy znamy z własnej rury, więc przyjmujemy od razu. Bez
        // przerwy na jego sprawdzanie, w której nasze czekające połączenie
        // zaczęłoby dzwonić od nowa.
        _accept(hello.guid, istniejace.theirStatic, hello.ephemeral, packet);
        return true;
      } else if (istniejace.remoteLabel == skad &&
          istniejace.isHelloFrom(hello.ephemeral)) {
        // Powtórzone HELLO tego samego uścisku: rura sama odsyła potwierdzenie.
        return true;
      } else {
        // Nowy uścisk (dzwoniący zaczął od nowa) albo inny adres (podszycie
        // się): stara rura i tak nie dowiezie klucza.
        _dropPipe(hello.guid, istniejace);
        unawaited(istniejace.close(powod: 'superseded by a new HELLO'));
      }
    }
    if (_accepting.contains(hello.guid)) return true;
    unawaited(_acceptIncoming(hello.guid, hello.ephemeral, packet));
    return true;
  }

  Future<void> _acceptIncoming(
      String guid, List<int> ephemeral, UdpPacket packet) async {
    _accepting.add(guid);
    try {
      final theirStatic = await resolveStatic(guid);
      if (theirStatic == null) {
        // Nieznany albo niepotwierdzony: droga internetowa go nie obsługuje.
        // Nic nie odsyłamy, żeby z ciszy nie dało się nic wyczytać.
        onPhase?.call(guid, InetLinkPhase.failed, 'unknown peer at the door');
        return;
      }
      final stojace = _pipes[guid];
      if (stojace != null &&
          !stojace.isClosed &&
          stojace.state == LinkState.up) {
        return;
      }
      _accept(guid, theirStatic, ephemeral, packet);
    } finally {
      _accepting.remove(guid);
    }
  }

  /// Strona przyjmująca: rura pod adres, z którego przyszło HELLO.
  void _accept(String guid, List<int> theirStatic, List<int> ephemeral,
      UdpPacket packet) {
    final pipe = _newPipe(guid, theirStatic, packet.address, packet.port,
        initiator: false);
    _onNewPipe?.call(guid, pipe);
    // Część synchroniczna zapamiętuje klucz efemeryczny HELLO, więc jego
    // kolejne powtórki rura już rozpozna jako swoje.
    unawaited(pipe.acceptHello(ephemeral));
  }

  /// Wołane, gdy stanęło łącze przychodzące: transport podpina pod nie
  /// multiplekser żądań/odpowiedzi.
  void Function(String guid, SecureUdpPipe pipe)? _onNewPipe;
  set onNewPipe(void Function(String guid, SecureUdpPipe pipe)? hook) =>
      _onNewPipe = hook;

  /// Diagnostyka dla narzędzia spike i karty dodatku Internet.
  Future<({StunMapping? mapping, NatMapping nat})> probeNat(
          {Iterable<String> localAddresses = const []}) =>
      _stun.discover(localAddresses: localAddresses);
}
