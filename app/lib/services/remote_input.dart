part of 'app_services.dart';

// Dodatek „Klawiatura z PC": nadawca pisze, odbiorca wpisuje to do pola
// z fokusem. Ta część serwisu siedzi w osobnym pliku, ale w tej samej
// bibliotece co `AppServices`: korzysta z sesji, kopert i tras, których nie ma
// po co wystawiać na zewnątrz. Wpisywany tekst idzie do kolejki nadawcy, do
// ujścia odbiorcy i, przy włączonym zapisie, do historii pisania po obu
// stronach (`TypingJournal`, zaszyfrowana baza). Tekst z pola hasła i z pola
// nieznanego rodzaju zostaje w historii samą liczbą znaków. Dziennik
// aplikacji i `ValueNotifier`y dostają z pisania wyłącznie zdarzenia, liczby
// i cel (rodzaj pola, aplikację).

/// Prośba o pisanie na tym urządzeniu, czekająca na decyzję użytkownika.
class PendingRemoteInput {
  /// Klucz prośby: nadawca i identyfikator jego sesji pisania. Po nim
  /// [AppServices.respondToRemoteInput] wie, na co odpowiada.
  final String id;
  final String peerGuid;
  final String peerName;

  /// System nadawcy, jeśli go podał.
  final String? platform;

  const PendingRemoteInput({
    required this.id,
    required this.peerGuid,
    required this.peerName,
    this.platform,
  });
}

/// Odpowiedź na prośbę o pisanie. [acceptAlways] to zgoda razem z „nie pytaj
/// więcej dla tego urządzenia".
enum RemoteInputDecision { accept, acceptAlways, reject, noAnswer }

/// Decyzja o prośbie o pisanie. Domyślnie pyta użytkownika (patrz
/// [AppServices.pendingRemoteInput]); testy podstawiają własną.
typedef RemoteInputPolicy = Future<RemoteInputDecision> Function(
    PendingRemoteInput request);

/// Zgoda na każdą prośbę (dla testów).
Future<RemoteInputDecision> acceptAllRemoteInput(
        PendingRemoteInput request) async =>
    RemoteInputDecision.accept;

/// Odmowa każdej prośby (dla testów).
Future<RemoteInputDecision> rejectAllRemoteInput(
        PendingRemoteInput request) async =>
    RemoteInputDecision.reject;

/// Trwająca zgoda u odbiorcy, do wskaźnika „Pisze: …" i przycisku Stop.
class IncomingRemoteInput {
  final String peerGuid;
  final String peerName;
  final DateTime started;

  /// Dokąd trafia pisanie, wg ostatniej paczki.
  final RemoteInputTarget target;

  const IncomingRemoteInput({
    required this.peerGuid,
    required this.peerName,
    required this.started,
    this.target = RemoteInputTarget.none,
  });

  IncomingRemoteInput withTarget(RemoteInputTarget target) =>
      IncomingRemoteInput(
        peerGuid: peerGuid,
        peerName: peerName,
        started: started,
        target: target,
      );
}

/// Stan sesji pisania po stronie nadawcy.
enum OutgoingRemoteInputState {
  /// Prośba poszła, karta wisi u odbiorcy.
  waiting,
  active,

  /// Odbiorca przyjmuje paczki, ale nic nie wpisuje, bo wisi u niego karta
  /// z pytaniem.
  paused,

  /// Nic więcej nie pójdzie: zerwane łącze albo odbiorca zakończył sesję
  /// (wtedy [OutgoingRemoteInput.reason] to [inputNoGrant]).
  disconnected,
}

/// Sesja pisania po stronie nadawcy, do paska stanu. Bez tekstu.
class OutgoingRemoteInput {
  final String peerGuid;
  final String peerName;
  final OutgoingRemoteInputState state;

  /// Cel u odbiorcy wg ostatniej odpowiedzi.
  final RemoteInputTarget target;

  /// Czy ostatnia paczka z tekstem albo kasowaniem została wpisana. Pingi
  /// tego nie zmieniają.
  final bool applied;

  /// Ile paczek z tekstem albo kasowaniem dostało już odpowiedź. Po nim ekran
  /// nadawcy rozpoznaje każdą kolejną odpowiedź, także gdy [applied] się nie
  /// zmienia (dwie niewpisane paczki z rzędu).
  final int typedReplies;

  /// Czas ostatniej paczki tam i z powrotem.
  final Duration? rtt;

  /// Którą drogą jadą paczki.
  final PeerProtocol? protocol;

  /// Dlaczego sesja stoi: [inputNoGrant] albo [inputStaleSeq] znaczy, że
  /// zakończył ją odbiorca, `null` przy [OutgoingRemoteInputState.disconnected]
  /// znaczy zerwane łącze.
  final String? reason;

  const OutgoingRemoteInput({
    required this.peerGuid,
    required this.peerName,
    required this.state,
    this.target = RemoteInputTarget.none,
    this.applied = true,
    this.typedReplies = 0,
    this.rtt,
    this.protocol,
    this.reason,
  });

  OutgoingRemoteInput copyWith({
    OutgoingRemoteInputState? state,
    RemoteInputTarget? target,
    bool? applied,
    int? typedReplies,
    Duration? rtt,
    PeerProtocol? protocol,
    String? reason,
  }) =>
      OutgoingRemoteInput(
        peerGuid: peerGuid,
        peerName: peerName,
        state: state ?? this.state,
        target: target ?? this.target,
        applied: applied ?? this.applied,
        typedReplies: typedReplies ?? this.typedReplies,
        rtt: rtt ?? this.rtt,
        protocol: protocol ?? this.protocol,
        reason: reason ?? this.reason,
      );
}

/// Jak skończyła się prośba o sesję pisania.
enum RemoteInputStart {
  accepted,

  /// Dodatek na tym urządzeniu jest wyłączony.
  addonOff,

  /// Tożsamość odbiorcy nie jest potwierdzona na tym urządzeniu (albo nie ma
  /// go już na liście).
  notVerified,
  rejected,

  /// Na urządzeniu odbiorcy pisanie jest wyłączone (dodatek albo odbiór).
  notEnabled,
  noAnswer,

  /// Na urządzeniu odbiorcy pisze już ktoś inny albo kolejka próśb jest pełna.
  busy,

  /// Odbiorca ma starszą wersję Chatt, bez zdalnej klawiatury.
  olderPeer,
  unreachable,

  /// Prośba wycofana przed odpowiedzią (Stop albo nowa prośba).
  cancelled,
}

/// Odstęp pingów przy bezczynności nadawcy. Ping trzyma połączenie (klient
/// HTTP zamyka bezczynne po 15 s) i przynosi aktualny cel.
@visibleForTesting
Duration debugRemoteInputPingInterval = const Duration(seconds: 1);

/// Bezczynność, po której zgoda gaśnie. Zmienna tylko po to, żeby test nie
/// czekał pół godziny.
@visibleForTesting
Duration debugRemoteInputIdle = remoteInputIdle;

/// Co ile zegar odbiorcy sprawdza, czy zgoda nie wygasła.
@visibleForTesting
Duration debugRemoteInputGrantCheck = const Duration(seconds: 30);

/// Ile razy idzie ta sama paczka, gdy nie ma odpowiedzi w limicie czasu.
const int _inputPacketAttempts = 3;

/// Ile próśb najwyżej czeka naraz na decyzję (na urządzenie, ze wszystkich
/// nadawców). Od jednego nadawcy czeka zawsze najwyżej jedna.
const int _maxPendingInputs = 8;

/// Ile zużytych identyfikatorów sesji pisania pamiętamy na jednego nadawcę.
/// Powtórzona prośba spod tego samego identyfikatora odbija się bez karty.
const int _maxUsedInputs = 512;

/// Ile tekstu najwyżej czeka u nadawcy na wysyłkę. Więcej niż to i wklejenie
/// jest odrzucane w całości, zanim cokolwiek pójdzie.
const int maxQueuedInputUnits = 64 * 1024;

/// Odpowiedź przed zapieczętowaniem: kod i treść. Pieczętuje się ją dopiero
/// przy wysyłce, kluczem sesji, w której przyszło dane zapytanie.
typedef _InputReply = ({int status, Map<String, Object?> payload});

/// Zgoda u odbiorcy. Żyje tylko w pamięci i jest związana z (nadawca, sesja
/// pisania, token). Sesja kryptograficzna pod nią może się zmienić: ponowny
/// uścisk dłoni po 409 daje nowy numer sesji, a pisanie trwa dalej.
class _InputGrant {
  final String peerGuid;
  final String peerName;
  final String input;
  final String token;

  /// Numer prośby, z której powstała (patrz [_InputAsk.order]).
  final int order;
  final DateTime started = DateTime.now();
  DateTime lastUsed = DateTime.now();

  /// Numer ostatniej przyjętej paczki i odpowiedź na nią. Powtórzona paczka
  /// dostaje tę samą odpowiedź i niczego nie wpisuje drugi raz.
  int lastSeq = 0;
  Map<String, Object?>? lastReply;

  /// Odpowiedź, z którą zgoda poszła do nadawcy. Ta sama prośba powtórzona
  /// inną drogą (pierwsza padła w trakcie karty) dostaje ją jeszcze raz.
  Map<String, Object?>? acceptReply;

  /// Sesja w historii pisania. `null`, gdy historia nie zapisuje.
  TypingSessionLog? journal;

  /// Cel znany przed następną paczką: z chwili zgody, potem z każdej
  /// odpowiedzi ujścia. Razem z celem po paczce mówi historii pisania, czy
  /// tekst ukryć.
  RemoteInputTarget lastTarget = RemoteInputTarget.none;

  /// Paczka tej zgody właśnie rozmawia z ujściem. Koniec zgody w tym czasie
  /// trafia do historii pisania dopiero po niej, razem z jej operacjami.
  bool applying = false;

  /// Powód końca zgody (`TypingEnd`), gdy już się skończyła.
  String? endReason;

  /// Liczniki do dziennika aplikacji: paczki z pisaniem, w tym niewpisane
  /// i wstrzymane kartą.
  int packets = 0;
  int notTyped = 0;
  int paused = 0;

  _InputGrant({
    required this.peerGuid,
    required this.peerName,
    required this.input,
    required this.token,
    required this.order,
  });

  bool get expired {
    final teraz = DateTime.now();
    return teraz.difference(lastUsed) > debugRemoteInputIdle ||
        teraz.difference(started) > remoteInputMaxLife;
  }
}

/// Prośba w trakcie rozpatrywania, od chwili, gdy jej identyfikator został
/// zużyty, do odpowiedzi.
class _InputAsk {
  final String peerGuid;

  /// Kolejność przyjścia. Dwie prośby od jednego nadawcy rozstrzyga ta
  /// liczba: nowsza zastępuje starszą, nigdy odwrotnie, choćby starsza
  /// skończyła czytać bazę później.
  final int order;

  /// Przyszła nowsza prośba od tego samego nadawcy, nadawca ją wycofał albo
  /// odbiór zgaszono: cokolwiek odpowie polityka, zgody z tego nie będzie.
  bool superseded = false;

  /// Nadawca sam zrezygnował z tej prośby: wycofał ją albo wysłał nowszą.
  /// W historii pisania odbiorcy to [TypingResult.cancelled].
  bool cancelled = false;

  /// Z tej prośby powstała zgoda, więc historia pisania ma już jej sesję.
  bool granted = false;

  /// Odpowiedź na tę prośbę. Czeka na nią także kopia tej samej prośby,
  /// która przyszła drugą drogą.
  final Completer<_InputReply> result = Completer<_InputReply>();

  _InputAsk(this.peerGuid, this.order);
}

/// Sesja pisania po stronie nadawcy.
class _Outgoing {
  final Peer peer;
  final String input;
  String? token;

  /// Trasa, która odpowiedziała na prośbę. Paczki jadą tylko nią: bez
  /// chodzenia po trasach przy każdym znaku.
  PeerRoute? route;
  int seq = 0;

  /// Operacje czekające na wysyłkę, sklejane po drodze.
  final List<RemoteInputOp> queue = [];

  /// Trwające opróżnianie kolejki. Jedna paczka w locie.
  Future<void>? pumping;

  /// Kolejka przyjęła `stop`: użytkownik nie dopisze już nic.
  bool closing = false;

  /// Nic więcej nie wyjdzie zwykłą drogą: sesja zakończona albo zerwana.
  bool dead = false;

  /// Odbiorca wie, że sesji nie ma (odpowiedział na `stop` albo sam ją
  /// zakończył), albo `stop` już poszedł; nie ma po co wysyłać drugiego.
  bool ended = false;
  final Completer<void> done = Completer<void>();
  DateTime lastSent = DateTime.now();
  Timer? ping;
  OutgoingRemoteInput state;

  /// Sesja w historii pisania. `null`, gdy historia nie zapisuje.
  TypingSessionLog? journal;

  /// Odbiorca się zgodził: sesja ruszyła, a jej koniec trafia do dziennika.
  bool accepted = false;

  /// Powód końca do historii pisania (`TypingEnd`). Ustawia go pierwszy, kto
  /// sesję kończy: Stop, nowa sesja, wyłączony dodatek, odmowa odbiorcy,
  /// zerwane łącze.
  String? endReason;

  /// Ile paczek z pisaniem dostało ostateczny wynik, do dziennika.
  int packets = 0;

  _Outgoing(this.peer, this.input, this.state);

  int get queuedUnits =>
      queue.fold(0, (suma, op) => suma + op.text.length);
}

/// Zdalna klawiatura w obie strony. Własność [AppServices], który tylko
/// deleguje.
class _RemoteInput {
  final AppServices _s;

  _RemoteInput(this._s) {
    _s.pendingOffers.addListener(_syncHold);
    _s.pendingPairings.addListener(_syncHold);
    pending.addListener(_syncHold);
    outgoing.addListener(_syncHold);
  }

  late RemoteInputPolicy _policy = _askUser;
  RemoteInputSink _sink = const RemoteInputChannel();

  /// Czy dodatek jest włączony. Jedyny włącznik całej funkcji; jedynym
  /// pisarzem jest [setAddon].
  final ValueNotifier<bool> keyboardAddon = ValueNotifier(false);
  final ValueNotifier<List<PendingRemoteInput>> pending =
      ValueNotifier(const []);
  final ValueNotifier<IncomingRemoteInput?> incoming = ValueNotifier(null);
  final ValueNotifier<OutgoingRemoteInput?> outgoing = ValueNotifier(null);

  /// Kolejka przełączeń dodatku i odbioru: szybkie „wyłącz, włącz" kończy
  /// się tym, co kliknięto na końcu.
  Future<void> _switches = Future.value();

  /// Paczki przychodzące w ramach bieżącej zgody idą po kolei. Bez tego
  /// ponowiona paczka, która przyszła, gdy pierwsza jeszcze się wpisywała,
  /// przeszłaby kontrolę `seq` razem z nią i tekst wpisałby się dwa razy.
  Future<void> _packets = Future.value();

  _InputGrant? _grant;

  /// Gasi zgodę, która wygasła, choćby nikt już nic nie przysłał (nadawca
  /// zamknięty, uśpiony albo poza zasięgiem).
  Timer? _grantClock;
  final Map<String, _InputAsk> _asks = {};
  final Map<String, Completer<RemoteInputDecision>> _decisions = {};

  /// Zużyte identyfikatory sesji pisania, osobno dla każdego nadawcy. Trafiają
  /// tu wyłącznie od zweryfikowanych, więc nikt nie wypchnie cudzych wpisów
  /// swoimi.
  final Map<String, Set<String>> _used = {};

  /// Ostatnia odmowa dla każdego nadawcy, z identyfikatorem prośby. Kopia
  /// prośby, która przyszła drugą drogą już po odpowiedzi, dostaje tę samą
  /// odmowę (na przykład `no-answer` po ciszy na karcie).
  final Map<String, ({String input, _InputReply reply})> _lastRefusal = {};
  int _askSeq = 0;
  _Outgoing? _out;
  bool _closed = false;

  /// Ostatnio wysłane do ujścia „pola Chatta bez pisania". `null`: nic
  /// jeszcze nie poszło w tej zgodzie.
  bool? _heldOwn;

  /// Pola samego Chatta bez pisania, dopóki wisi karta z pytaniem albo to
  /// urządzenie samo pisze na innym (jego ekran pisania odesłałby tekst
  /// dalej, a dwie sesje w obie strony kręciłyby się w kółko). Słuchacze
  /// wołają to od razu przy zmianie, więc ujście wie o karcie, zanim ta
  /// weźmie fokus klatkę później: paczka, która właśnie wpisuje się w okno
  /// Chatta, urywa się przed Enterem. Poza zgodą nic nie idzie, bo nic się
  /// nie wpisuje.
  void _syncHold() {
    if (_closed || _grant == null) return;
    final on = _s._anyPromptPending || _out != null;
    if (on == _heldOwn) return;
    _heldOwn = on;
    unawaited(_sink.holdOwnApp(on));
  }

  void _set<T>(ValueNotifier<T> notifier, T value) {
    if (!_closed) notifier.value = value;
  }

  /// Tożsamość w paczkach i prośbach. Odbiorca sprawdza z niej wyłącznie
  /// guid (właściciel sesji), a resztę zna z bazy, więc nazwa, powitanie
  /// i klucz nie jadą przy każdym znaku i nie zmieniają długości paczki.
  DeviceIdentity get _me => DeviceIdentity(
        guid: _s.identity.guid,
        name: '',
        welcomeMessage: '',
        tcpPort: _s.identity.tcpPort,
      );

  // --- Dodatek i odbiór -----------------------------------------------------

  Future<T> _serially<T>(Future<T> Function() krok) {
    final wynik = _switches.then((_) => krok());
    _switches = wynik.then((_) {}, onError: (_) {});
    return wynik;
  }

  /// Włącza albo wyłącza dodatek. Wyłączenie najpierw zamyka bramkę, potem
  /// kończy wszystko, co trwa (zgodę, prośby, własną sesję pisania), zapisuje
  /// stan razem ze zgaszonym odbiorem i dopiero na końcu wyłącza klawiaturę
  /// w systemie.
  Future<bool> setAddon(bool on) => _serially(() async {
        if (on) {
          _set(keyboardAddon, true);
          await _s.db.saveKeyboardAddon(true);
          await _sink.setImeEnabled(true);
          return true;
        }
        _set(keyboardAddon, false);
        _shutDown();
        await _s.db.saveKeyboardAddon(false);
        await _sink.setImeEnabled(false);
        return false;
      });

  /// Przełącznik „Pozwól pisać na tym urządzeniu". Zwraca stan po zmianie.
  Future<bool> setReceive(bool on) => _serially(() async {
        if (on) {
          if (!keyboardAddon.value || !_sink.supported) return false;
          await _s.db.saveRemoteInputReceive(true);
          return true;
        }
        _dropAsks();
        _endGrant(TypingEnd.receiveOff);
        await _s.db.saveRemoteInputReceive(false);
        return false;
      });

  bool get receiveSupported => _sink.supported;

  /// Czy inni mogą teraz pisać na tym urządzeniu. Czytane z bazy przy każdej
  /// prośbie i każdej paczce, obok bramki w pamięci, którą sprawdzamy jeszcze
  /// raz po odczycie: przełącznik zgaszony w jego trakcie też się liczy.
  Future<bool> _receiveOn() async {
    if (_closed || !keyboardAddon.value || !_sink.supported) return false;
    final ustawienia = await _s.db.getSettings();
    return !_closed &&
        keyboardAddon.value &&
        ustawienia != null &&
        ustawienia.keyboardEnabled &&
        ustawienia.remoteInputReceive;
  }

  void _shutDown() {
    _dropAsks();
    _endGrant(TypingEnd.addonOff);
    unawaited(stop(reason: TypingEnd.addonOff));
  }

  // --- Odbiorca: prośba o sesję ---------------------------------------------

  Future<SealedReply> _seal(_Session sesja, _InputReply odpowiedz) async => (
        status: odpowiedz.status,
        body: await ChattCrypto.seal(
            payload: padInputPayload(odpowiedz.payload),
            key: sesja.key,
            sessionId: sesja.id),
      );

  /// Brak sesji albo sesja, która w międzyczasie należy do kogoś innego:
  /// nie ma czym zapieczętować odpowiedzi dla tego nadawcy, więc ta jedna
  /// jest jawna. Nadawca robi nowy uścisk dłoni i ponawia.
  static const SealedReply _noSession = (
    status: 409,
    body: {'ok': false, 'error': errorNoSession},
  );

  Future<SealedReply> handleSession(
      InputSessionRequest prosba, String fromHost, String session) async {
    final sesja = _s._sessionsById[session];
    // Koperta już potwierdziła nadawcę; tu pilnujemy, żeby prośba nie
    // przyszła w cudzej sesji.
    if (sesja == null || sesja.peerGuid != prosba.from.guid) return _noSession;
    return _seal(sesja, await _answerSession(prosba, fromHost));
  }

  Future<_InputReply> _answerSession(
      InputSessionRequest prosba, String fromHost) async {
    final guid = prosba.from.guid;
    final input = prosba.input;
    final klucz = '$guid|$input';
    _InputReply odmowa(String powod) => (
          status: 403,
          payload: InputSessionReply(
                  accepted: false, input: input, reason: powod)
              .toJson(),
        );

    final peer = await _s.db.peerByGuid(guid);
    final zweryfikowany = peer != null && peer.verified;

    if (prosba.op == inputSessionCancel) {
      // Wycofanie zużywa identyfikator: prośba, która dotrze po nim (dłuższą
      // drogą), odbije się bez karty. Zgoda wydana tej prośbie, której
      // nadawca nie zdążył poznać, gaśnie razem z nią.
      if (zweryfikowany) _markUsed(guid, input);
      final czeka = _asks[klucz];
      czeka?.cancelled = true;
      _withdraw(klucz);
      final grant = _grant;
      final zgody =
          grant != null && grant.peerGuid == guid && grant.input == input;
      if (zgody) _endGrant(TypingEnd.stoppedByPeer);
      if (peer != null && peer.verified && (czeka != null || zgody)) {
        _s.log.info(LogArea.keyboard,
            'Typing request withdrawn by ${peer.displayName}');
      }
      return (
        status: 200,
        payload: InputSessionReply(
                accepted: false, input: input, reason: inputCancelled)
            .toJson(),
      );
    }

    // Niezweryfikowany słyszy zawsze to samo, cokolwiek leży w ustawieniach:
    // stan dodatku poznaje tylko ten, komu wolno tu pisać. Historia pisania
    // go nie zna: jej wiersze dostają wyłącznie zweryfikowani.
    if (peer == null || !peer.verified) {
      _s.log.warning(
          LogArea.keyboard, 'Typing request from an unverified device refused');
      return odmowa(inputRejected);
    }

    if (!_markUsed(guid, input)) {
      // Ta sama prośba drugi raz: kopia, która poszła inną drogą, bo
      // pierwsza padła w trakcie karty, albo nagranie odtworzone przez kogoś
      // w sieci. Karty nie ma drugiej, a odpowiedź jest ta sama co na
      // oryginał, zapieczętowana kluczem tej sesji.
      final czeka = _asks[klucz];
      if (czeka != null && !czeka.superseded) return czeka.result.future;
      final grant = _grant;
      final zgoda = grant?.acceptReply;
      if (grant != null &&
          zgoda != null &&
          grant.peerGuid == guid &&
          grant.input == input &&
          !grant.expired) {
        return (status: 200, payload: zgoda);
      }
      final ostatnia = _lastRefusal[guid];
      if (ostatnia != null && ostatnia.input == input) return ostatnia.reply;
      return odmowa(inputRejected);
    }

    final ask = _InputAsk(guid, ++_askSeq);
    _asks[klucz] = ask;
    _s.log.info(
        LogArea.keyboard, 'Typing request received from ${peer.displayName}');
    _InputReply wynik;
    try {
      wynik = await _decide(prosba, fromHost, peer, ask, klucz);
    } catch (_) {
      wynik = odmowa(inputNoAnswer);
    } finally {
      if (identical(_asks[klucz], ask)) _asks.remove(klucz);
    }
    if (wynik.status != 200) {
      _lastRefusal[guid] = (input: input, reply: wynik);
      // Prośba, z której zdążyła powstać zgoda, ma już w historii swoją
      // sesję z powodem końca. Zamykana aplikacja niczego nie odmawia.
      if (!ask.granted && !_closed) {
        final wynikProsby = ask.cancelled
            ? TypingResult.cancelled
            : _incomingRefusal(wynik.payload['reason']);
        _s.typingJournal.refused(
          direction: MessageDirection.incoming,
          inputId: input,
          peerGuid: guid,
          peerName: peer.displayName,
          result: wynikProsby,
        );
        _s.log.info(LogArea.keyboard,
            'Typing request from ${peer.displayName} refused: $wynikProsby');
      }
    }
    if (!ask.result.isCompleted) ask.result.complete(wynik);
    return wynik;
  }

  /// Powód odmowy z odpowiedzi jako wynik prośby w historii pisania.
  static String _incomingRefusal(Object? powod) => switch (powod) {
        inputNotEnabled => TypingResult.notEnabled,
        inputNoAnswer => TypingResult.noAnswer,
        inputBusy => TypingResult.busy,
        inputCancelled => TypingResult.cancelled,
        _ => TypingResult.rejected,
      };

  Future<_InputReply> _decide(InputSessionRequest prosba, String fromHost,
      Peer peer, _InputAsk ask, String klucz) async {
    final guid = peer.guid;
    _InputReply odmowa(String powod) => (
          status: 403,
          payload: InputSessionReply(
                  accepted: false, input: prosba.input, reason: powod)
              .toJson(),
        );

    if (!await _receiveOn()) return odmowa(inputNotEnabled);
    _s._drogaPrzychodzaca(guid, fromHost);

    final grant = _grant;
    if (grant != null && !grant.expired && grant.peerGuid != guid) {
      return odmowa(inputBusy);
    }
    // Zgodę ma już nowsza prośba tego nadawcy: ta jest nieaktualna.
    if (grant != null && grant.peerGuid == guid && grant.order > ask.order) {
      ask.cancelled = true;
      return odmowa(inputNoAnswer);
    }
    // Ten sam nadawca prosi jeszcze raz: jego poprzednia zgoda i poprzednia
    // prośba przestają obowiązywać, a karta pyta od nowa. Rozstrzyga
    // kolejność przyjścia, więc z dwóch próśb zostaje nowsza, w jakiej
    // kolejności by nie skończyły czytać bazy. Zgoda, która dotrwała tu
    // przy innym nadawcy, już wygasła.
    if (grant != null) {
      _endGrant(grant.expired ? TypingEnd.expired : TypingEnd.replaced);
    }
    for (final entry in _asks.entries.toList()) {
      final inna = entry.value;
      if (entry.key == klucz || inna.peerGuid != guid) continue;
      if (inna.order < ask.order) {
        inna.cancelled = true;
        _withdraw(entry.key);
      } else {
        ask.superseded = true;
        ask.cancelled = true;
      }
    }
    final czekajacych = _asks.entries
        .where((e) => e.key != klucz && !e.value.superseded)
        .length;
    if (czekajacych >= _maxPendingInputs) return odmowa(inputBusy);
    if (ask.superseded) return odmowa(inputNoAnswer);

    var decyzja = peer.remoteInput
        ? RemoteInputDecision.accept
        : await _policy(PendingRemoteInput(
            id: klucz,
            peerGuid: guid,
            peerName: peer.displayName,
            platform: prosba.platform,
          ));
    if (ask.superseded || _closed) decyzja = RemoteInputDecision.noAnswer;

    switch (decyzja) {
      case RemoteInputDecision.reject:
        return odmowa(inputRejected);
      case RemoteInputDecision.noAnswer:
        return odmowa(inputNoAnswer);
      case RemoteInputDecision.accept:
      case RemoteInputDecision.acceptAlways:
        break;
    }

    // Przez dwie minuty karty wszystko mogło się zmienić: tarcza zgaszona,
    // dodatek wyłączony, ktoś inny dostał zgodę wcześniej.
    final teraz = await _s.db.peerByGuid(guid);
    if (teraz == null || !teraz.verified) return odmowa(inputRejected);
    if (!await _receiveOn()) return odmowa(inputNotEnabled);
    if (decyzja == RemoteInputDecision.acceptAlways) {
      await _s.db.setPeerRemoteInput(teraz.id, true);
    }

    // Od tego miejsca do założenia zgody nie ma już żadnego czekania: odbiór
    // zgaszony w trakcie odczytów wyżej oznaczył tę prośbę jako wycofaną.
    if (ask.superseded) return odmowa(inputNoAnswer);
    if (_closed || !keyboardAddon.value) return odmowa(inputNotEnabled);
    final inny = _grant;
    if (inny != null && !inny.expired && inny.peerGuid != guid) {
      return odmowa(inputBusy);
    }
    if (inny != null && inny.peerGuid == guid && inny.order > ask.order) {
      ask.cancelled = true;
      return odmowa(inputNoAnswer);
    }
    if (inny != null) {
      _endGrant(inny.expired ? TypingEnd.expired : TypingEnd.replaced);
    }

    final nowy = _InputGrant(
      peerGuid: guid,
      peerName: teraz.displayName,
      input: prosba.input,
      token: newSessionId(),
      order: ask.order,
    );
    // Sesja w historii pisania rusza razem ze zgodą. Historia zapisuje
    // w tle, więc to wywołanie niczego tu nie wstrzymuje.
    final wynikProsby = peer.remoteInput
        ? TypingResult.automatic
        : (decyzja == RemoteInputDecision.acceptAlways
            ? TypingResult.acceptedAlways
            : TypingResult.accepted);
    nowy.journal = _s.typingJournal.begin(
      direction: MessageDirection.incoming,
      inputId: prosba.input,
      peerGuid: guid,
      peerName: nowy.peerName,
      result: wynikProsby,
    );
    ask.granted = true;
    _s.log.info(LogArea.keyboard,
        'Incoming typing session started: ${nowy.peerName} ($wynikProsby)');
    _grant = nowy;
    _startGrantClock();
    _heldOwn = null;
    _syncHold();
    await _sink.setSession(active: true, peerName: nowy.peerName);
    final cel = await _sink.status();
    // Zgoda cofnięta w trakcie rozmowy z ujściem (Stop, wyłączony dodatek).
    if (!identical(_grant, nowy)) return odmowa(inputNotEnabled);
    nowy.lastTarget = cel;
    _set(
      incoming,
      IncomingRemoteInput(
        peerGuid: guid,
        peerName: nowy.peerName,
        started: nowy.started,
        target: cel,
      ),
    );
    final zgoda = InputSessionReply(
      accepted: true,
      input: prosba.input,
      token: nowy.token,
      target: cel,
    ).toJson();
    nowy.acceptReply = zgoda;
    return (status: 200, payload: zgoda);
  }

  bool _markUsed(String guid, String input) {
    final zuzyte = _used.putIfAbsent(guid, () => <String>{});
    if (!zuzyte.add(input)) return false;
    if (zuzyte.length > _maxUsedInputs) zuzyte.remove(zuzyte.first);
    return true;
  }

  /// Karta pyta użytkownika: prośba ląduje w [pending], odpowiedź przychodzi
  /// przez [respond], a po dwóch minutach ciszy kończy się bez zgody.
  Future<RemoteInputDecision> _askUser(PendingRemoteInput prosba) {
    final decyzja = Completer<RemoteInputDecision>();
    _decisions[prosba.id] = decyzja;
    _set(pending, [...pending.value, prosba]);
    return decyzja.future.timeout(
      remoteInputAnswerTimeout,
      onTimeout: () {
        _resolve(prosba.id, RemoteInputDecision.noAnswer);
        return RemoteInputDecision.noAnswer;
      },
    );
  }

  void respond(String id, {required bool accept, bool remember = false}) =>
      _resolve(
          id,
          accept
              ? (remember
                  ? RemoteInputDecision.acceptAlways
                  : RemoteInputDecision.accept)
              : RemoteInputDecision.reject);

  void _resolve(String id, RemoteInputDecision decyzja) {
    _set(
        pending,
        pending.value
            .where((prosba) => prosba.id != id)
            .toList(growable: false));
    final czeka = _decisions.remove(id);
    if (czeka != null && !czeka.isCompleted) czeka.complete(decyzja);
  }

  /// Prośba wycofana albo zastąpiona: karta znika, a cokolwiek odpowie
  /// polityka, zgody z tego nie będzie.
  void _withdraw(String klucz) {
    _asks[klucz]?.superseded = true;
    _resolve(klucz, RemoteInputDecision.noAnswer);
  }

  void _dropAsks() {
    for (final klucz in {..._asks.keys, ..._decisions.keys}) {
      _withdraw(klucz);
    }
  }

  // --- Odbiorca: paczki -----------------------------------------------------

  Future<SealedReply> handlePacket(
      RemoteInputPacket paczka, String fromHost, String session) {
    final sesja = _s._sessionsById[session];
    final guid = paczka.from.guid;
    if (sesja == null || sesja.peerGuid != guid) {
      return Future.value(_noSession);
    }
    // Paczka spoza bieżącej zgody dostaje odmowę od razu, bez stania w kolejce.
    // Zły albo stary token niczego w niej nie rusza (inaczej odtworzona paczka
    // z poprzedniej sesji kończyłaby obecną), a czas odpowiedzi nie zależy od
    // tego, czy ktoś właśnie pisze.
    final grant = _grant;
    if (grant == null ||
        grant.peerGuid != guid ||
        grant.input != paczka.input ||
        !ChattCrypto.sameTag(grant.token, paczka.token)) {
      return _seal(sesja, _packetRefusal(paczka, inputNoGrant));
    }
    final wynik = _packets
        .then((_) => _handlePacket(paczka, fromHost, sesja, grant))
        .then((odpowiedz) => _seal(sesja, odpowiedz));
    _packets = wynik.then((_) {}, onError: (_) {});
    return wynik;
  }

  static _InputReply _packetRefusal(RemoteInputPacket paczka, String powod) => (
        status: 403,
        payload: RemoteInputReply(
                ok: false, input: paczka.input, seq: paczka.seq, reason: powod)
            .toJson(),
      );

  Future<_InputReply> _handlePacket(RemoteInputPacket paczka, String fromHost,
      _Session sesja, _InputGrant grant) async {
    final guid = paczka.from.guid;
    if (!identical(_grant, grant)) return _packetRefusal(paczka, inputNoGrant);
    if (grant.expired) {
      _endGrant(TypingEnd.expired);
      return _packetRefusal(paczka, inputNoGrant);
    }

    // Bramki jeszcze raz, z bazy: tarcza zdjęta albo przełącznik zgaszony
    // gdziekolwiek kończą zgodę na następnej paczce.
    final peer = await _s.db.peerByGuid(guid);
    if (peer == null || !peer.verified || !await _receiveOn()) {
      if (identical(_grant, grant)) _endGrant(TypingEnd.notAllowed);
      return _packetRefusal(paczka, inputNoGrant);
    }
    if (!identical(_grant, grant)) return _packetRefusal(paczka, inputNoGrant);

    if (paczka.seq < grant.lastSeq) {
      _s.log.warning(LogArea.keyboard,
          'Typing packet refused: $inputStaleSeq (seq ${paczka.seq}, '
          'last ${grant.lastSeq})');
      return _packetRefusal(paczka, inputStaleSeq);
    }
    if (paczka.seq == grant.lastSeq) {
      final ostatnia = grant.lastReply;
      if (ostatnia != null) {
        return (status: 200, payload: {...ostatnia, 'duplicate': true});
      }
    }
    grant.lastSeq = paczka.seq;
    _s._drogaPrzychodzaca(guid, fromHost);

    final piszace = [
      for (final op in paczka.ops)
        if (op.kind.types) op,
    ];
    final stop = paczka.ops.last.kind == RemoteInputOpKind.stop;
    var wpisane = false;
    // Zdalny Enter nie odpowie na kartę z pytaniem, która właśnie wyskoczyła
    // u odbiorcy. Ping też to zgłasza, żeby nadawca widział przerwę przez cały
    // czas, gdy karta wisi.
    final String? powod = _s._anyPromptPending ? inputPaused : null;
    final przed = grant.lastTarget;
    RemoteInputTarget cel;
    if (piszace.isNotEmpty) grant.lastUsed = DateTime.now();
    // Koniec zgody w trakcie rozmowy z ujściem czeka z wpisem do historii
    // pisania na tę paczkę: to, co ona wpisze, należy jeszcze do tej sesji.
    grant.applying = true;
    try {
      if (piszace.isEmpty || powod != null) {
        cel = await _sink.status();
      } else {
        final wynik = await _sink.apply(piszace);
        wpisane = wynik.applied;
        cel = wynik.target;
      }
      grant.lastTarget = cel;
      if (piszace.isNotEmpty) {
        final skutek = powod != null
            ? TypingStatus.paused
            : (wpisane ? TypingStatus.typed : TypingStatus.notTyped);
        grant.packets++;
        if (skutek == TypingStatus.notTyped) grant.notTyped++;
        if (skutek == TypingStatus.paused) grant.paused++;
        _s.typingJournal.record(grant.journal, piszace,
            status: skutek, before: przed, after: cel);
      }
    } finally {
      grant.applying = false;
      final koniec = grant.endReason;
      if (koniec != null) _s.typingJournal.end(grant.journal, koniec);
    }

    final odpowiedz = RemoteInputReply(
      ok: true,
      input: paczka.input,
      seq: paczka.seq,
      applied: wpisane,
      reason: powod,
      target: cel,
    ).toJson();
    grant.lastReply = odpowiedz;
    if (identical(_grant, grant)) {
      if (stop) {
        _endGrant(TypingEnd.stoppedByPeer);
      } else {
        final teraz = incoming.value;
        if (teraz != null) _set(incoming, teraz.withTarget(cel));
      }
    }
    return (status: 200, payload: odpowiedz);
  }

  void _startGrantClock() {
    _grantClock?.cancel();
    _grantClock = Timer.periodic(debugRemoteInputGrantCheck, (_) {
      final grant = _grant;
      if (grant == null) {
        _grantClock?.cancel();
        _grantClock = null;
      } else if (grant.expired) {
        _endGrant(TypingEnd.expired);
      }
    });
  }

  /// Kończy bieżącą zgodę. [reason] to powód w historii pisania
  /// (`TypingEnd`).
  void _endGrant(String reason) {
    _grantClock?.cancel();
    _grantClock = null;
    final grant = _grant;
    if (grant == null) return;
    _grant = null;
    _heldOwn = null;
    _set(incoming, null);
    _grantEnded(grant, reason);
    unawaited(_sink.setSession(active: false));
  }

  /// Koniec zgody w historii pisania i w dzienniku. Paczka, która właśnie
  /// rozmawia z ujściem, zapisuje jeszcze swoje operacje, a koniec sesji
  /// w historii przychodzi po niej (patrz [_handlePacket]). Przy zamykaniu
  /// aplikacji koniec idzie od razu.
  void _grantEnded(_InputGrant grant, String reason) {
    final koniec = grant.endReason ??= reason;
    if (!grant.applying || _closed) {
      _s.typingJournal.end(grant.journal, koniec);
    }
    _s.log.info(
      LogArea.keyboard,
      'Incoming typing session ended: $koniec (${grant.peerName}, '
      '${grant.packets} packets, ${grant.notTyped} not typed, '
      '${grant.paused} paused)',
    );
  }

  /// Stop po stronie odbiorcy. Nadawca dowie się przy następnej paczce albo
  /// pingu.
  void stopIncoming() => _endGrant(TypingEnd.stoppedHere);

  // --- Nadawca ----------------------------------------------------------------

  void _publish(_Outgoing o, OutgoingRemoteInput stan) {
    o.state = stan;
    if (identical(_out, o)) _set(outgoing, stan);
  }

  Future<RemoteInputStart> start(Peer peer) async {
    if (!keyboardAddon.value) return RemoteInputStart.addonOff;
    // Pisanie to także hasła, więc idzie wyłącznie do urządzenia, które jest
    // na liście i którego tożsamość potwierdzono na tym ekranie.
    final rozmowca = await _s.db.peerByGuid(peer.guid);
    if (rozmowca == null || !rozmowca.verified) {
      return RemoteInputStart.notVerified;
    }
    // Dodatek zgaszony w trakcie odczytu: sesja nie ma prawa ruszyć.
    if (!keyboardAddon.value || _closed) return RemoteInputStart.addonOff;

    final o = _Outgoing(
      rozmowca,
      AppServices._uuid.v4(),
      OutgoingRemoteInput(
        peerGuid: rozmowca.guid,
        peerName: rozmowca.displayName,
        state: OutgoingRemoteInputState.waiting,
      ),
    );
    // Podmiana bez czekania: poprzednia sesja kończy się w tle (jej `stop`
    // albo wycofanie prośby idzie osobno), a nowa prośba nie stoi za jej
    // ponowieniami na zrywającym się łączu.
    final stara = _out;
    _out = o;
    _set(outgoing, o.state);
    if (stara != null) {
      stara.endReason ??= TypingEnd.replaced;
      unawaited(_stopSession(stara));
    }
    _s.log.info(
        LogArea.keyboard, 'Typing request sent to ${rozmowca.displayName}');

    final prosba = InputSessionRequest(
      from: _me,
      op: inputSessionRequest,
      input: o.input,
      platform: Platform.operatingSystem,
    ).toJson();
    ({PeerRoute? route, int status, Map<String, Object?>? reply}) wynik;
    try {
      wynik = await _s._exchangeSealed(
        rozmowca,
        padInputPayload(prosba),
        (route, koperta) =>
            _s.client.requestInputSession(route: route, payload: koperta),
        // Wycofana prośba nie idzie już następną drogą.
        alive: () => identical(_out, o),
      );
    } catch (_) {
      wynik = (route: null, status: -1, reply: null);
    }
    final odpowiedz = InputSessionReply.fromJson(wynik.reply, input: o.input);

    if (!identical(_out, o)) {
      // Wycofana w trakcie czekania. Zgoda, która przyszła mimo to, wraca od
      // razu: odbiorca nie ma zostać z paskiem „Pisze" bez nikogo po drugiej
      // stronie.
      if (odpowiedz != null && odpowiedz.accepted && wynik.route != null) {
        o.token = odpowiedz.token;
        o.route = wynik.route;
        unawaited(_sendStop(o));
      }
      return _refusedOutgoing(o, RemoteInputStart.cancelled);
    }
    if (odpowiedz == null || !odpowiedz.accepted) {
      _out = null;
      _set(outgoing, null);
      if (odpowiedz == null) {
        if (wynik.status == 404) {
          return _refusedOutgoing(o, RemoteInputStart.olderPeer);
        }
        // Brak odpowiedzi nie znaczy, że karta nie wisi: łącze mogło paść
        // w jej trakcie. Wycofanie zamyka ją, a zgodę, gdyby zdążyła paść,
        // gasi.
        unawaited(_withdrawRequest(o));
        return _refusedOutgoing(o, RemoteInputStart.unreachable);
      }
      return _refusedOutgoing(
        o,
        switch (odpowiedz.reason) {
          inputNotEnabled => RemoteInputStart.notEnabled,
          inputNoAnswer => RemoteInputStart.noAnswer,
          inputBusy => RemoteInputStart.busy,
          inputCancelled => RemoteInputStart.cancelled,
          _ => RemoteInputStart.rejected,
        },
      );
    }

    o.token = odpowiedz.token;
    o.route = wynik.route;
    o.lastSent = DateTime.now();
    o.accepted = true;
    o.journal = _s.typingJournal.begin(
      direction: MessageDirection.outgoing,
      inputId: o.input,
      peerGuid: rozmowca.guid,
      peerName: rozmowca.displayName,
      result: TypingResult.accepted,
    );
    _s.log.info(LogArea.keyboard,
        'Outgoing typing session started: ${rozmowca.displayName}');
    _publish(
      o,
      o.state.copyWith(
        state: OutgoingRemoteInputState.active,
        target: odpowiedz.target,
        protocol: wynik.route?.protocol,
      ),
    );
    o.ping = Timer.periodic(debugRemoteInputPingInterval, (_) => _pingIfIdle(o));
    return RemoteInputStart.accepted;
  }

  /// Prośba bez sesji po stronie nadawcy: wiersz w historii pisania i wpis
  /// w dzienniku. Zamykana aplikacja nie zostawia wiersza.
  RemoteInputStart _refusedOutgoing(_Outgoing o, RemoteInputStart odmowa) {
    final wynik = _outgoingRefusal(odmowa);
    if (wynik != null && !_closed) {
      _s.typingJournal.refused(
        direction: MessageDirection.outgoing,
        inputId: o.input,
        peerGuid: o.peer.guid,
        peerName: o.peer.displayName,
        result: wynik,
      );
      _s.log.info(LogArea.keyboard,
          'Typing request to ${o.peer.displayName} refused: $wynik');
    }
    return odmowa;
  }

  /// Wynik prośby w historii pisania nadawcy. Wyłączony dodatek i rozmówca
  /// bez potwierdzonej tożsamości kończą się przed wysyłką, więc wiersza
  /// nie mają.
  static String? _outgoingRefusal(RemoteInputStart odmowa) => switch (odmowa) {
        RemoteInputStart.rejected => TypingResult.rejected,
        RemoteInputStart.notEnabled => TypingResult.notEnabled,
        RemoteInputStart.noAnswer => TypingResult.noAnswer,
        RemoteInputStart.busy => TypingResult.busy,
        RemoteInputStart.olderPeer => TypingResult.olderPeer,
        RemoteInputStart.unreachable => TypingResult.unreachable,
        RemoteInputStart.cancelled => TypingResult.cancelled,
        RemoteInputStart.accepted ||
        RemoteInputStart.addonOff ||
        RemoteInputStart.notVerified =>
          null,
      };

  /// Dopisuje operacje do kolejki. `false`, gdy nie ma aktywnej sesji albo
  /// wklejenie przekracza [maxQueuedInputUnits]; wtedy nic nie idzie.
  bool send(List<RemoteInputOp> ops) {
    final o = _out;
    if (o == null || o.token == null || o.dead || o.closing) return false;
    final czyste = <RemoteInputOp>[];
    var tekst = 0;
    for (final op in ops) {
      switch (op.kind) {
        case RemoteInputOpKind.insert:
          final s = typableText(op.text);
          if (s.isEmpty) continue;
          tekst += s.length;
          czyste.add(RemoteInputOp.insert(s));
        case RemoteInputOpKind.backspace:
        case RemoteInputOpKind.delete:
          if (op.count < 1) continue;
          czyste.add(op);
        case RemoteInputOpKind.action:
          czyste.add(op);
        case RemoteInputOpKind.ping:
        case RemoteInputOpKind.stop:
          // Ping wysyła serwis sam, a koniec sesji idzie przez [stop].
          continue;
      }
    }
    if (o.queuedUnits + tekst > maxQueuedInputUnits) return false;
    for (final op in czyste) {
      _enqueue(o.queue, op);
    }
    _kick(o);
    return true;
  }

  /// Sklejanie: tekst z tekstem i kasowanie z kasowaniem tego samego
  /// rodzaju. Różne rodzaje zostają osobno i w kolejności, bo „wpisz, cofnij"
  /// przy zaznaczeniu w polu znaczy co innego niż nic.
  static void _enqueue(List<RemoteInputOp> kolejka, RemoteInputOp op) {
    final ostatnia = kolejka.isEmpty ? null : kolejka.last;
    if (ostatnia != null && ostatnia.kind == op.kind) {
      switch (op.kind) {
        case RemoteInputOpKind.insert:
          kolejka[kolejka.length - 1] =
              RemoteInputOp.insert(ostatnia.text + op.text);
          return;
        case RemoteInputOpKind.backspace:
          kolejka[kolejka.length - 1] =
              RemoteInputOp.backspace(ostatnia.count + op.count);
          return;
        case RemoteInputOpKind.delete:
          kolejka[kolejka.length - 1] =
              RemoteInputOp.delete(ostatnia.count + op.count);
          return;
        default:
          break;
      }
    }
    kolejka.add(op);
  }

  /// Zdejmuje z kolejki jedną paczkę w granicach protokołu. Długi tekst
  /// i długie kasowanie dzielą się między paczki; para surogatów nigdy.
  static List<RemoteInputOp> _takePacket(List<RemoteInputOp> kolejka) {
    final paczka = <RemoteInputOp>[];
    var tekst = 0;
    var kasowanie = 0;
    while (kolejka.isNotEmpty && paczka.length < maxInputOps) {
      final op = kolejka.first;
      switch (op.kind) {
        case RemoteInputOpKind.insert:
          final miejsce = maxInputTextUnits - tekst;
          if (op.text.length <= miejsce) {
            paczka.add(op);
            tekst += op.text.length;
            kolejka.removeAt(0);
            continue;
          }
          var ciecie = miejsce;
          final przed = ciecie > 0 ? op.text.codeUnitAt(ciecie - 1) : 0;
          if (przed >= 0xD800 && przed <= 0xDBFF) ciecie--;
          if (ciecie > 0) {
            paczka.add(RemoteInputOp.insert(op.text.substring(0, ciecie)));
            kolejka[0] = RemoteInputOp.insert(op.text.substring(ciecie));
          }
          return paczka;
        case RemoteInputOpKind.backspace:
        case RemoteInputOpKind.delete:
          final miejsce = maxInputDeletes - kasowanie;
          if (miejsce <= 0) return paczka;
          final n = math.min(op.count, math.min(maxInputDeleteRun, miejsce));
          paczka.add(op.kind == RemoteInputOpKind.backspace
              ? RemoteInputOp.backspace(n)
              : RemoteInputOp.delete(n));
          kasowanie += n;
          if (n == op.count) {
            kolejka.removeAt(0);
          } else {
            kolejka[0] = op.kind == RemoteInputOpKind.backspace
                ? RemoteInputOp.backspace(op.count - n)
                : RemoteInputOp.delete(op.count - n);
          }
        case RemoteInputOpKind.stop:
          paczka.add(op);
          kolejka.removeAt(0);
          return paczka;
        case RemoteInputOpKind.action:
        case RemoteInputOpKind.ping:
          paczka.add(op);
          kolejka.removeAt(0);
      }
    }
    return paczka;
  }

  /// Rusza opróżnianie kolejki, jeśli jeszcze nie trwa. Wyjątek po drodze
  /// kończy sesję jak zerwane łącze: inaczej `stop` czekałby na nią wiecznie.
  void _kick(_Outgoing o) {
    if (o.pumping != null) return;
    o.pumping = _drain(o).catchError((Object blad) {
      // Sam typ błędu: jego opis mógłby nieść treść paczki.
      _s.log.warning(
          LogArea.keyboard, 'Typing queue stopped: ${blad.runtimeType}');
      _finish(o, null, end: TypingEnd.linkLost);
    }).whenComplete(() {
      o.pumping = null;
      // Coś doszło między ostatnią paczką a końcem opróżniania.
      if (o.queue.isNotEmpty && !o.dead) _kick(o);
    });
  }

  Future<void> _drain(_Outgoing o) async {
    while (o.queue.isNotEmpty && !o.dead) {
      final paczka = _takePacket(o.queue);
      if (paczka.isEmpty) break;
      await _sendPacket(o, paczka);
    }
    if (o.dead) _dropQueue(o);
  }

  Future<void> _sendPacket(_Outgoing o, List<RemoteInputOp> ops) async {
    final seq = ++o.seq;
    o.lastSent = DateTime.now();
    final payload = padInputPayload(RemoteInputPacket(
      from: _me,
      input: o.input,
      token: o.token!,
      seq: seq,
      ops: ops,
    ).toJson());
    final stop = ops.last.kind == RemoteInputOpKind.stop;
    final pisze = ops.any((op) => op.kind.types);
    // Cel sprzed paczki: razem z celem z odpowiedzi mówi historii pisania,
    // czy tekst ukryć.
    final przed = o.state.target;

    // Długie wklejenie odbiorca wpisuje znak po znaku, więc paczka z nim
    // dostaje tyle czasu więcej, ile potrwa wpisanie.
    final limit = remoteInputPacketTimeout + remoteInputTypingTime(ops);
    RemoteInputReply? odpowiedz;
    var rtt = Duration.zero;
    var status = -1;
    for (var proba = 0; proba < _inputPacketAttempts; proba++) {
      final zegar = Stopwatch()..start();
      final wynik = await _s._exchangeSealed(
        o.peer,
        payload,
        (route, koperta) => _s.client
            .sendInput(route: route, payload: koperta, timeout: limit),
        route: o.route,
      );
      zegar.stop();
      status = wynik.status;
      odpowiedz =
          RemoteInputReply.fromJson(wynik.reply, input: o.input, seq: seq);
      if (odpowiedz != null) {
        rtt = zegar.elapsed;
        break;
      }
      // Brak odpowiedzi w limicie: ta sama paczka jeszcze raz, z tym samym
      // `seq`. Każda inna porażka (sesja nie wstała po ponownym uścisku,
      // starszy odbiorca, zły kształt) się nie poprawi.
      if (wynik.status != -1) break;
    }

    // Wynik paczki trafia do historii pisania raz, po ostatniej próbie.
    if (odpowiedz == null) {
      if (pisze) {
        o.packets++;
        _s.typingJournal.record(o.journal, ops,
            status: TypingStatus.unconfirmed, before: przed, after: przed);
      }
      _s.log.warning(LogArea.keyboard,
          'Typing packet unconfirmed: ${_opsCounts(ops)}, status $status');
      _finish(o, null, end: TypingEnd.linkLost);
      return;
    }
    if (!odpowiedz.ok) {
      final powod = odpowiedz.reason ?? inputNoGrant;
      if (pisze) {
        o.packets++;
        _s.typingJournal.record(o.journal, ops,
            status: TypingStatus.refused, before: przed, after: przed);
      }
      _s.log.info(LogArea.keyboard, 'Typing packet refused by peer: $powod');
      o.ended = true;
      _finish(o, powod, end: TypingEnd.stoppedByPeer);
      return;
    }
    if (pisze) {
      o.packets++;
      _s.typingJournal.record(
        o.journal,
        ops,
        status: odpowiedz.reason == inputPaused
            ? TypingStatus.paused
            : (odpowiedz.applied ? TypingStatus.typed : TypingStatus.notTyped),
        before: przed,
        after: odpowiedz.target,
      );
    }
    if (stop) {
      o.ended = true;
      _finish(o, null, end: TypingEnd.stoppedHere);
      return;
    }
    _publish(
      o,
      o.state.copyWith(
        state: odpowiedz.reason == inputPaused
            ? OutgoingRemoteInputState.paused
            : OutgoingRemoteInputState.active,
        target: odpowiedz.target,
        // Ping niczego nie wpisuje, więc nie mówi nic o ostatnim tekście.
        applied: pisze ? odpowiedz.applied : null,
        typedReplies: pisze ? o.state.typedReplies + 1 : null,
        rtt: rtt,
      ),
    );
  }

  /// Liczby do dziennika: ile operacji piszących i ile znaków. Bez tekstu.
  static String _opsCounts(Iterable<RemoteInputOp> ops) {
    var operacje = 0;
    var znaki = 0;
    for (final op in ops) {
      if (!op.kind.types) continue;
      operacje++;
      znaki += op.text.runes.length;
    }
    return '$operacje ops, $znaki chars';
  }

  /// Operacje, które zostały w kolejce, gdy sesja się skończyła. Nie wyszły,
  /// więc historia pisania zapisuje je jako niewysłane.
  void _dropQueue(_Outgoing o) {
    if (o.queue.isEmpty) return;
    final zostalo = List.of(o.queue);
    o.queue.clear();
    if (!zostalo.any((op) => op.kind.types)) return;
    final cel = o.state.target;
    _s.typingJournal.record(o.journal, zostalo,
        status: TypingStatus.unsent, before: cel, after: cel);
    _s.log.warning(
        LogArea.keyboard, 'Typing ops not sent: ${_opsCounts(zostalo)}');
  }

  /// Koniec sesji nadawcy. [reason] jak w [OutgoingRemoteInput.reason],
  /// [end] to powód w historii pisania (`TypingEnd`), o ile nikt nie podał
  /// go wcześniej.
  void _finish(_Outgoing o, String? reason, {required String end}) {
    final pierwszy = !o.dead;
    o.dead = true;
    o.ping?.cancel();
    final koniec = o.endReason ??= end;
    _dropQueue(o);
    _s.typingJournal.end(o.journal, koniec);
    if (pierwszy && o.accepted) {
      _s.log.info(
        LogArea.keyboard,
        'Outgoing typing session ended: $koniec (${o.peer.displayName}, '
        '${o.packets} packets)',
      );
    }
    if (!o.done.isCompleted) o.done.complete();
    if (identical(_out, o)) {
      _publish(
        o,
        o.state.copyWith(
          state: OutgoingRemoteInputState.disconnected,
          reason: reason,
        ),
      );
    }
  }

  void _pingIfIdle(_Outgoing o) {
    if (o.dead || o.closing || o.token == null) return;
    if (o.pumping != null || o.queue.isNotEmpty) return;
    if (DateTime.now().difference(o.lastSent) < debugRemoteInputPingInterval) {
      return;
    }
    o.queue.add(const RemoteInputOp.ping());
    _kick(o);
  }

  /// Kończy własną sesję pisania. To, co czeka w kolejce, idzie jeszcze
  /// przed `stop`. Prośba bez odpowiedzi zostaje wycofana, żeby karta
  /// u odbiorcy zniknęła. [reason] to powód w historii pisania
  /// (`TypingEnd`): domyślnie Stop użytkownika.
  Future<void> stop({String reason = TypingEnd.stoppedHere}) async {
    final o = _out;
    if (o == null) return;
    _out = null;
    _set(outgoing, null);
    o.endReason ??= reason;
    await _stopSession(o);
  }

  Future<void> _stopSession(_Outgoing o) async {
    o.ping?.cancel();
    if (o.token == null) {
      unawaited(_withdrawRequest(o));
      return;
    }
    await _sendStop(o);
  }

  Future<void> _sendStop(_Outgoing o) async {
    if (o.ended || _closed) return;
    if (!o.dead) {
      o.closing = true;
      o.queue.add(const RemoteInputOp.stop());
      _kick(o);
      await o.done.future;
      if (o.ended || _closed) return;
    }
    // Łącze padło, zanim `stop` wyszedł zwykłą drogą: jedna próba poza
    // kolejką, i to każdą trasą, bo ta zapamiętana mogła właśnie zgasnąć.
    // Bez tego odbiorca czekałby na koniec zgody do jej wygaśnięcia.
    o.ended = true;
    try {
      await _s._exchangeSealed(
        o.peer,
        padInputPayload(RemoteInputPacket(
          from: _me,
          input: o.input,
          token: o.token!,
          seq: ++o.seq,
          ops: const [RemoteInputOp.stop()],
        ).toJson()),
        (route, koperta) => _s.client.sendInput(route: route, payload: koperta),
      );
    } catch (_) {
      // Odbiorca i tak zgasi zgodę po bezczynności.
    }
  }

  Future<void> _withdrawRequest(_Outgoing o) async {
    try {
      await _s._exchangeSealed(
        o.peer,
        padInputPayload(InputSessionRequest(
          from: _me,
          op: inputSessionCancel,
          input: o.input,
        ).toJson()),
        (route, koperta) => _s.client.requestInputSession(
            route: route,
            payload: koperta,
            timeout: remoteInputPacketTimeout * 3),
      );
    } catch (_) {
      // Karta u odbiorcy zgaśnie sama po dwóch minutach.
    }
  }

  // --- Sprzątanie -----------------------------------------------------------

  /// Rozmówca usunięty z listy: jego zgoda, prośba i sesja pisania znikają
  /// razem z nim.
  void forgetPeer(String guid) {
    _lastRefusal.remove(guid);
    if (_grant?.peerGuid == guid) _endGrant(TypingEnd.peerRemoved);
    for (final entry in _asks.entries.toList()) {
      if (entry.value.peerGuid == guid) _withdraw(entry.key);
    }
    if (_out?.peer.guid == guid) {
      unawaited(stop(reason: TypingEnd.peerRemoved));
    }
  }

  Future<void> dispose() async {
    // Najpierw zamknięcie: obsługa, która właśnie czeka na bazę albo kartę,
    // po powrocie nie założy już zgody ani nie dotknie powiadamiaczy.
    _closed = true;
    _dropAsks();
    _grantClock?.cancel();
    _grantClock = null;
    final grant = _grant;
    _grant = null;
    if (grant != null) {
      _grantEnded(grant, TypingEnd.appClosed);
      await _sink.setSession(active: false);
    }
    final o = _out;
    _out = null;
    // Bez `_out` koniec nie dotyka już powiadamiacza, a kolejka trafia do
    // historii pisania jako niewysłana.
    if (o != null) _finish(o, null, end: TypingEnd.appClosed);
    _s.pendingOffers.removeListener(_syncHold);
    _s.pendingPairings.removeListener(_syncHold);
    keyboardAddon.dispose();
    pending.dispose();
    incoming.dispose();
    outgoing.dispose();
  }
}
