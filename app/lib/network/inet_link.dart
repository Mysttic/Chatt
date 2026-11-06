import 'dart:async';

import 'package:cryptography/cryptography.dart';

import 'dht.dart';
import 'rendezvous.dart';
import 'secure_udp.dart';
import 'stun.dart';
import 'udp_mux.dart';

/// Menedżer drogi internetowej: spina STUN, DHT, skrzynkę kontaktową
/// i przebicie dziury w jedną funkcję „połącz mnie z tym rozmówcą".
///
/// Krok po kroku dla połączenia wychodzącego:
///  1. STUN mówi, pod jakim publicznym adresem widać nasze gniazdo.
///  2. Publikujemy ten adres do swojej skrzynki w DHT i czytamy skrzynkę
///     rozmówcy, żeby poznać jego publiczny adres.
///  3. Oba urządzenia zaczynają nadawać do siebie naraz (HELLO tam i z
///     powrotem). Każdy wychodzący pakiet otwiera w naszym NAT-cie furtkę na
///     odpowiedź z adresu, do którego poszedł — to jest całe przebicie.
///  4. Gdy klucze się zgodzą, [SecureUdpPipe] staje i nad nią działa zwykły
///     multiplekser żądań/odpowiedzi.
///
/// Połączenie przychodzące: menedżer rozpoznaje HELLO od nieznanego adresu,
/// sprawdza guid nadawcy przez [resolveStatic] (tylko rozmówca z zieloną
/// tarczą ma tu klucz) i stawia stronę przyjmującą.

/// Skąd wziąć klucz statyczny i skrzynkę dla danego guida. Zwraca null, gdy
/// rozmówca nie jest potwierdzony — wtedy droga internetowa go nie obsługuje.
typedef StaticKeyResolver = Future<List<int>?> Function(String guid);
typedef RendezvousResolver = Future<Rendezvous?> Function(String guid);

/// Guidy rozmówców, do których skrzynek mamy wpisywać swój adres, żeby dało
/// się nas znaleźć, gdy to oni dzwonią. Zwykle wszyscy z zieloną tarczą.
typedef VerifiedPeersResolver = Future<List<String>> Function();

/// Jak długo próbujemy przebić dziurę, zanim uznamy próbę za nieudaną.
const Duration kPunchTimeout = Duration(seconds: 12);

/// Co ile odświeżamy własny adres w skrzynce (NAT mógł przestawić port,
/// a rekord i tak wygasa po około godzinie).
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

  late final StunClient _stun = StunClient(mux);
  late final DhtClient _dht = DhtClient(mux);

  /// Łącza po guidzie rozmówcy.
  final _pipes = <String, SecureUdpPipe>{};

  /// Łącza po bieżącym adresie drugiej strony: tędy trafiają pakiety danych
  /// i HELLO_ACK do właściwej rury. Przepinane, gdy NAT przestawi port.
  final _byRemote = <String, SecureUdpPipe>{};

  /// Trwające nawiązywania, żeby dwa żądania naraz nie przebijały dwa razy.
  final _connecting = <String, Future<SecureUdpPipe?>>{};

  /// Ostatnio zmierzony własny adres publiczny (IPv4).
  StunMapping? _publicV4;

  /// Wołane, gdy łącze stanie albo padnie (log, interfejs).
  final void Function(String guid, InetLinkPhase phase, String reason)? onPhase;

  Timer? _publishTimer;
  bool _running = false;

  /// Czyja skrzynka ma dostać nasz adres (zob. [VerifiedPeersResolver]).
  /// Gdy null, adres trafia do skrzynki dopiero w chwili, gdy sami dzwonimy —
  /// czyli urządzenie, które tylko czeka, jest nieosiągalne.
  final VerifiedPeersResolver? verifiedPeers;

  InetLinkManager({
    required this.mux,
    required this.myStatic,
    required this.myStaticPub,
    required this.myGuid,
    required this.resolveStatic,
    required this.resolveRendezvous,
    this.verifiedPeers,
    this.onPhase,
  });

  bool get isRunning => _running;
  StunMapping? get publicAddress => _publicV4;

  /// Klient DHT tego menedżera: testy wstrzykują mu węzły rozruchowe wprost
  /// (`manager.dht.debugBootstrap = [...]`), żeby obejść DNS i prawdziwą sieć.
  DhtClient get dht => _dht;

  /// Gdy ustawione, [_refreshPublic] zwraca to zamiast pytać STUN. Do testów
  /// nad siecią w pamięci, gdzie nie ma prawdziwych serwerów STUN.
  StunMapping? debugPublic;

  /// Rozpoznaje pakiety HELLO od jeszcze nieznanych adresów. STUN, DHT i stojące
  /// łącza mają własne handlery zarejestrowane wcześniej, więc tu trafia tylko
  /// to, czego nikt nie wziął.
  void start() {
    if (_running) return;
    _running = true;
    mux.register(_onPacket);
    // Od razu wpisujemy swój adres do skrzynek, żeby odbiorca był osiągalny,
    // nim ktokolwiek zadzwoni; potem co [kPublishInterval], bo NAT przestawia
    // port, a rekord w DHT i tak wygasa po około godzinie.
    unawaited(_publishToAll());
    _publishTimer =
        Timer.periodic(kPublishInterval, (_) => unawaited(_publishToAll()));
  }

  Future<void> stop() async {
    _running = false;
    _publishTimer?.cancel();
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

  /// Pyta STUN o własny adres. Woła to [_publishToAll] i [_establish].
  Future<StunMapping?> _refreshPublic() async {
    final debug = debugPublic;
    if (debug != null) {
      _publicV4 = debug;
      return debug;
    }
    final wynik = await _stun.discover();
    _publicV4 = wynik.mapping;
    return _publicV4;
  }

  /// Odświeża własny adres i wpisuje go do skrzynki każdego potwierdzonego
  /// rozmówcy. Dzięki temu urządzenie, które tylko nasłuchuje, da się znaleźć,
  /// gdy to druga strona zacznie dzwonić.
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
      final box = await resolveRendezvous(guid);
      if (box == null) continue;
      try {
        await box.publish(_dht, address: mine.address, port: mine.port);
      } catch (_) {
        // Jeden nieudany zapis (brak węzłów, chwilowa cisza sieci) nie
        // przerywa reszty; następna runda spróbuje znowu.
      }
    }
  }

  /// Zwraca stojące łącze do rozmówcy albo próbuje je postawić. null, gdy się
  /// nie udało (rozmówca nieosiągalny, symetryczny NAT, cisza w skrzynce).
  Future<SecureUdpPipe?> linkTo(String guid) {
    final istniejace = _pipes[guid];
    if (istniejace != null && !istniejace.isClosed) {
      return Future.value(istniejace);
    }
    // Blok, nie wyrażenie strzałkowe: `Map.remove` oddaje właśnie tę samą
    // przyszłość, a `whenComplete` czekałby wtedy, aż ona się skończy —
    // czyli sama na siebie. To by zawiesiło każde łączenie.
    return _connecting[guid] ??= _establish(guid).whenComplete(() {
      _connecting.remove(guid);
    });
  }

  SecureUdpPipe? pipeFor(String guid) {
    final p = _pipes[guid];
    return (p != null && !p.isClosed) ? p : null;
  }

  bool isLinked(String guid) => pipeFor(guid) != null;

  List<String> get linkedGuids => [
        for (final e in _pipes.entries)
          if (!e.value.isClosed) e.key,
      ];

  Future<SecureUdpPipe?> _establish(String guid) async {
    onPhase?.call(guid, InetLinkPhase.resolving, 'looking up');
    final theirStatic = await resolveStatic(guid);
    final rendezvous = await resolveRendezvous(guid);
    if (theirStatic == null || rendezvous == null) {
      onPhase?.call(guid, InetLinkPhase.failed, 'peer not verified');
      return null;
    }

    // Własny adres, potem publikacja i odczyt skrzynki rozmówcy. Publikacja
    // best-effort, z połkniętym błędem: bez tego nieudany zapis (brak węzłów,
    // cisza sieci) leciałby jako nieobsłużony wyjątek w tle.
    final mine = await _refreshPublic();
    if (mine != null) {
      unawaited(rendezvous
          .publish(_dht, address: mine.address, port: mine.port)
          .catchError((_) => 0));
    }
    final theirs = await rendezvous.lookup(_dht);
    if (theirs == null) {
      onPhase?.call(guid, InetLinkPhase.failed, 'peer address not in DHT');
      return null;
    }

    onPhase?.call(guid, InetLinkPhase.punching, theirs.toString());
    final pipe = SecureUdpPipe(
      mux: mux,
      myStatic: myStatic,
      myStaticPub: myStaticPub,
      theirStatic: theirStatic,
      myGuid: myGuid,
      remoteAddress: theirs.address,
      remotePort: theirs.port,
      initiator: true,
      onState: (state, reason) => _onPipeState(guid, state, reason),
    );
    _registerPipe(guid, pipe);

    final up = await pipe.connect().timeout(kPunchTimeout, onTimeout: () => false);
    if (!up) {
      _dropPipe(guid, pipe);
      await pipe.close(powod: 'punch timed out');
      onPhase?.call(guid, InetLinkPhase.failed, 'hole punching failed');
      return null;
    }
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

  void _onPipeState(String guid, LinkState state, String reason) {
    if (state == LinkState.up) {
      onPhase?.call(guid, InetLinkPhase.up, reason);
    } else if (state == LinkState.closed) {
      final pipe = _pipes[guid];
      if (pipe != null) _dropPipe(guid, pipe);
      onPhase?.call(guid, InetLinkPhase.failed, reason);
    }
  }

  // --- połączenia przychodzące ---------------------------------------------

  bool _onPacket(UdpPacket packet) {
    if (!isLinkPacket(packet.data)) return false; // STUN/DHT biorą swoje
    final hello = parseHello(packet.data);
    if (hello == null) {
      // Pakiet stojącego (albo stającego) łącza: dane, HELLO_ACK, zamknięcie.
      // Najpierw po adresie; a gdy ten nie pasuje (NAT przestawił port),
      // próbujemy każdej żywej rury — zła rura i tak nie odszyfruje pakietu,
      // a właściwa odświeży sobie adres i od tej pory trafia po nim.
      final pipe = _byRemote['${packet.address.address}:${packet.port}'];
      if (pipe != null && !pipe.isClosed) {
        pipe.handlePacket(packet);
        return true;
      }
      for (final p in _pipes.values) {
        if (!p.isClosed) p.handlePacket(packet);
      }
      return true;
    }
    // HELLO: początek uścisku od strony inicjującej.
    final istniejace = _pipes[hello.guid];
    if (istniejace != null && !istniejace.isClosed) {
      if (istniejace.state == LinkState.up) {
        // Już stoimy, a druga strona wciąż powtarza HELLO (zgubiła nasze
        // potwierdzenie): odsyłamy je jeszcze raz, żeby i ona stanęła.
        istniejace.resendConfirm();
        return true;
      }
      // Rurę wciąż w uścisku zostawiamy, jeśli to ten sam adres; HELLO
      // z innego adresu może ją zastąpić (podszycie się, stary adres nigdy
      // nie dowiezie klucza).
      if (istniejace.remoteLabel == '${packet.address.address}:${packet.port}') {
        return true;
      }
      unawaited(istniejace.close(powod: 'superseded by HELLO from another address'));
    }
    unawaited(_acceptIncoming(hello.guid, hello.ephemeral, packet));
    return true;
  }

  Future<void> _acceptIncoming(
      String guid, List<int> ephemeral, UdpPacket packet) async {
    final theirStatic = await resolveStatic(guid);
    if (theirStatic == null) {
      // Nieznany albo niepotwierdzony: droga internetowa go nie obsługuje.
      // Nic nie odsyłamy, żeby z ciszy nie dało się nic wyczytać.
      onPhase?.call(guid, InetLinkPhase.failed, 'unknown peer at the door');
      return;
    }
    final stojace = _pipes[guid];
    if (stojace != null && !stojace.isClosed && stojace.state == LinkState.up) {
      return;
    }
    final pipe = SecureUdpPipe(
      mux: mux,
      myStatic: myStatic,
      myStaticPub: myStaticPub,
      theirStatic: theirStatic,
      myGuid: myGuid,
      remoteAddress: packet.address,
      remotePort: packet.port,
      initiator: false,
      onState: (state, reason) => _onPipeState(guid, state, reason),
    );
    _registerPipe(guid, pipe);
    _onNewPipe?.call(guid, pipe);
    await pipe.acceptHello(ephemeral);
  }

  /// Wołane, gdy stanęło łącze przychodzące: transport podpina pod nie
  /// multiplekser żądań/odpowiedzi.
  void Function(String guid, SecureUdpPipe pipe)? _onNewPipe;
  set onNewPipe(void Function(String guid, SecureUdpPipe pipe)? hook) =>
      _onNewPipe = hook;

  /// Diagnostyka dla narzędzia spike i panelu „To urządzenie".
  Future<({StunMapping? mapping, NatMapping nat})> probeNat(
          {Iterable<String> localAddresses = const []}) =>
      _stun.discover(localAddresses: localAddresses);
}
