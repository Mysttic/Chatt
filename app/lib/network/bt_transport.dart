import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bt_link.dart';
import 'transport.dart';

/// Własny numer usługi Chatta w SDP.
///
/// SPP (`00001101-0000-1000-8000-00805F9B34FB`) dzieli z każdym przejściem
/// USB-szeregowym i z windowsowym portem COM, więc nasłuch pod nim łapałby
/// cudze połączenia, a cudze usługi łapałyby nasze.
const String btServiceUuid = 'c4a1f7d2-5b3e-4f1a-9c8d-6e2b0a7f3d51';

/// Nazwa usługi w rekordzie SDP: to ją widzi druga strona, zanim cokolwiek
/// powie.
const String btServiceName = 'Chatt';

/// Jak często pytamy stronę natywną o nowe łącza. Kanał wraca natychmiast,
/// więc to jest tanie, a pół sekundy jest niezauważalne przy nawiązywaniu
/// połączenia liczonym w sekundach.
const Duration btPollInterval = Duration(milliseconds: 500);

/// Co ile transport próbuje postawić nasłuch, który padł po stronie
/// natywnej (radio zgaszone i włączone z powrotem w systemie).
const Duration btListenRetry = Duration(seconds: 5);

/// Co ile włączony dodatek próbuje podnieść transport, który nie wstał
/// (radio wyłączone, brak zgody).
const Duration btRetryInterval = Duration(seconds: 10);

/// Urządzenie zobaczone przez radio. To jeszcze nie jest rozmówca Chatta:
/// dowiadujemy się o tym dopiero po połączeniu i zapytaniu o `/info`.
class BtDevice {
  final String address;
  final String name;
  final bool bonded;

  /// Główna klasa urządzenia z Bluetooth Class of Device, już z maską
  /// `0x1F00`: `0x100` komputer, `0x200` telefon, `0x400` słuchawki
  /// i głośniki. Zero, kiedy radio jej nie podało.
  final int majorClass;

  /// Urządzenie widziane tylko przez Bluetooth Low Energy. RFCOMM do takiego
  /// adresu zawsze czeka do końca limitu strony (ponad pięć sekund) i nigdy
  /// się nie łączy, więc przy szukaniu nie ma go po co pytać.
  final bool leOnly;

  const BtDevice({
    required this.address,
    required this.name,
    this.bonded = false,
    this.majorClass = 0,
    this.leOnly = false,
  });
}

/// Główne klasy urządzeń, na których może stać Chatt.
const int btClassComputer = 0x100;
const int btClassPhone = 0x200;

/// Klasy, które niczego nie mówią: „różne" i „bez kategorii".
const int btClassMisc = 0x000;
const int btClassUncategorized = 0x1F00;

/// Kogo i w jakiej kolejności pytać przy szukaniu.
///
/// Każde pytanie o urządzenie bez Chatta kosztuje kilka sekund, a pytamy po
/// jednym, bo radio nie łączy się z dwoma naraz. Najpierw więc idą komputery
/// i telefony, potem to, co klasy nie podało, na końcu słuchawki, zegarki
/// i telewizory. Urządzenia widziane tylko przez BLE odpadają całkiem.
/// W obrębie jednej grupy zostaje kolejność, w jakiej je zobaczyło radio.
List<BtDevice> btProbeOrder(Iterable<BtDevice> devices) {
  int grupa(BtDevice device) => switch (device.majorClass) {
        btClassComputer || btClassPhone => 0,
        btClassMisc || btClassUncategorized => 1,
        _ => 2,
      };
  final kandydaci = [
    for (final device in devices)
      if (!device.leOnly) device,
  ];
  final kolejnosc = {
    for (var i = 0; i < kandydaci.length; i++) kandydaci[i]: i,
  };
  return kandydaci
    ..sort((a, b) {
      final roznica = grupa(a) - grupa(b);
      return roznica != 0 ? roznica : kolejnosc[a]! - kolejnosc[b]!;
    });
}

/// Stan radia i zgód, na tyle, na ile widzi go aplikacja.
class BtStatus {
  final bool available;
  final bool enabled;
  final bool granted;
  final bool canScan;

  /// Czy system ma włączone usługi lokalizacji. Do wyszukiwania Bluetooth nie
  /// są potrzebne merytorycznie, ale Android bez nich nie oddaje ani jednego
  /// wyniku, cokolwiek aplikacja deklaruje.
  final bool locationOn;
  final String name;
  final String address;
  final List<BtDevice> paired;

  /// Czy to urządzenie pokazuje się w pobliżu tylko na żądanie
  /// ([BtChannel.showSelf]). Tak jest na Androidzie: telefon jest widoczny
  /// wyłącznie przy otwartym ekranie parowania w ustawieniach. Komputer
  /// z Windows jest widoczny przez cały czas dodatku i tego nie potrzebuje.
  final bool canShowSelf;

  /// Czy urządzenie jest teraz widoczne w eterze.
  final bool visible;

  const BtStatus({
    this.available = false,
    this.enabled = false,
    this.granted = false,
    this.canScan = false,
    this.locationOn = true,
    this.name = '',
    this.address = '',
    this.paired = const [],
    this.canShowSelf = false,
    this.visible = false,
  });

  /// Czy da się w ogóle spróbować. Reszta to już sprawa drugiej strony.
  bool get usable => available && enabled && granted;
}

/// Strona Dartowa kanału `chatt/bluetooth`.
///
/// Kod natywny doprowadza łącze RFCOMM i mostkuje je na gniazdo TCP pod
/// 127.0.0.1. Tutaj nie ma ani jednego bajtu z radia: są numery portów
/// i adresy, a bajty płyną zwykłym `Socket`.
class BtChannel {
  static const _channel = MethodChannel('chatt/bluetooth');

  /// Bluetooth Classic jest tylko tam, gdzie mamy własny kod natywny.
  static bool get supported =>
      debugSupported ?? (Platform.isAndroid || Platform.isWindows);

  /// Podmiana dla testów. CI stoi na Linuksie, gdzie [supported] jest false
  /// i kanał milczy sam z siebie, a test ma sprawdzić, że milczy z powodu
  /// wyłączonego dodatku.
  @visibleForTesting
  static bool? debugSupported;

  /// Nieudane wywołanie strony natywnej: nazwa metody, kod błędu i jego
  /// opis. Kanał jest jeden na proces, więc i ten hak: ustawia go
  /// `AppServices` przy starcie, a zapis do dziennika aplikacji (razem
  /// z pilnowaniem, żeby odpytywanie co pół sekundy go nie zalało) jest już
  /// jego sprawą.
  static void Function(String method, String code, String? message)?
      onCallError;

  static void _zglos(String method, String code, String? message) {
    try {
      onCallError?.call(method, code, message);
    } catch (_) {
      // Zgłoszenie jest dodatkiem: wywołanie i tak kończy się „nie wyszło”.
    }
  }

  static Future<Map<String, Object?>?> _call(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMapMethod<String, Object?>(method, args);
    } on PlatformException catch (error) {
      _zglos(method, error.code, error.message);
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> _callBool(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException catch (error) {
      _zglos(method, error.code, error.message);
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<BtStatus> status() async {
    final json = await _call('status');
    if (json == null) return const BtStatus();
    return BtStatus(
      available: json['available'] == true,
      enabled: json['enabled'] == true,
      granted: json['granted'] == true,
      canScan: json['canScan'] == true,
      // Brak pola znaczy „nie dotyczy": tak odpowiada Windows.
      locationOn: json['locationOn'] != false,
      name: json['name'] is String ? json['name'] as String : '',
      address: json['address'] is String ? json['address'] as String : '',
      paired: _devices(json['paired']),
      // Brak pól znaczy „nie dotyczy": tak odpowiada Windows.
      canShowSelf: json['canShowSelf'] == true,
      visible: json['visible'] == true,
    );
  }

  /// Ekran zgód w ustawieniach systemu. Na Windowsie nie ma czego otwierać.
  static Future<bool> openSettings() => _callBool('openSettings');

  /// Systemowe pytanie o zgodę na urządzenia w pobliżu. false znaczy, że nie
  /// ma jak zapytać (zamknięte okno, starszy Android, Windows) i zostaje
  /// [openSettings].
  static Future<bool> requestPermission() => _callBool('requestPermission');

  /// Systemowy ekran lokalizacji. Sami jej nie włączamy: to decyzja
  /// użytkownika, a bez niej Android nie znajdzie żadnego urządzenia.
  static Future<bool> openLocationSettings() =>
      _callBool('openLocationSettings');

  /// Wykrywalność radia. Liczy się na Windowsie: bez tego komputer jest
  /// widoczny wyłącznie przy otwartym oknie „Dodaj urządzenie", więc telefon
  /// nie ma go jak znaleźć.
  static Future<bool> discoverable(bool on) =>
      _callBool('discoverable', {'on': on});

  /// Systemowe okienko „pokaż ten telefon w pobliżu" na dwie minuty. Dotyczy
  /// Androida ([BtStatus.canShowSelf]). Decyzję podejmuje użytkownik
  /// w okienku, a jej skutek widać w [BtStatus.visible]. false znaczy, że nie
  /// ma jak zapytać (zamknięte okno, zgaszone radio).
  static Future<bool> showSelf() => _callBool('showSelf');

  static Future<bool> scan() async {
    final json = await _call('scan');
    return json?['scanning'] == true;
  }

  static Future<({bool scanning, List<BtDevice> devices})> scanResults() async {
    final json = await _call('scanResults');
    return (
      scanning: json?['scanning'] == true,
      devices: _devices(json?['devices']),
    );
  }

  static Future<bool> linkStart() async {
    final json = await _call('linkStart', {
      'uuid': btServiceUuid,
      'name': btServiceName,
      // Bluetooth traktujemy jak kabel: może być podsłuchany, może być
      // podstawiony, i to nie ma znaczenia, bo wszystko nad nim jest
      // zaszyfrowane uściskiem dłoni. Wymuszanie parowania systemowego
      // niczego by nie dodało, a odebrałoby „działa, gdy jesteście obok".
      'secure': false,
    });
    // Windows odpowiada na nieudany nasłuch mapą z powodem i kodem WSA,
    // bez wyjątku. To też jest nieudane wywołanie.
    final blad = json?['error'];
    if (blad != null) _zglos('linkStart', '${json?['code'] ?? 'error'}', '$blad');
    return json != null && blad == null;
  }

  static Future<bool> linkStop() => _callBool('linkStop');

  /// Zaczyna łączenie i wraca od razu. Wynik przychodzi przez [linkPoll].
  static Future<int?> linkConnect(String address) async {
    final json = await _call('linkConnect', {
      'address': address,
      'uuid': btServiceUuid,
      'secure': false,
    });
    final id = json?['id'];
    return id is int ? id : null;
  }

  static Future<bool> linkClose(int id) => _callBool('linkClose', {'id': id});

  static Future<BtPoll> linkPoll() async {
    final json = await _call('linkPoll');
    if (json == null) return const BtPoll();
    return BtPoll(
      ready: [
        for (final entry in (json['ready'] as List<Object?>? ?? const []))
          if (entry is Map)
            BtReady(
              id: entry['id'] as int? ?? 0,
              peer: entry['peer'] as String? ?? '',
              port: entry['port'] as int? ?? 0,
              incoming: entry['incoming'] == true,
            ),
      ],
      failed: [
        for (final entry in (json['failed'] as List<Object?>? ?? const []))
          if (entry is Map) entry['id'] as int? ?? 0,
      ],
      closed: [
        for (final entry in (json['closed'] as List<Object?>? ?? const []))
          if (entry is Map)
            (
              id: entry['id'] as int? ?? 0,
              reason: entry['reason'] as String? ?? '',
            ),
      ],
      notes: [
        for (final entry in (json['notes'] as List<Object?>? ?? const []))
          if (entry is String) entry,
      ],
      listening: json['listening'] == true,
      answered: true,
    );
  }

  static List<BtDevice> _devices(Object? raw) => [
        for (final entry in (raw as List<Object?>? ?? const []))
          if (entry is Map)
            BtDevice(
              address: entry['address'] as String? ?? '',
              name: entry['name'] as String? ?? '',
              bonded: entry['bonded'] == true,
              majorClass: (entry['major'] as int? ?? 0) & 0x1F00,
              leOnly: entry['leOnly'] == true,
            ),
      ];
}

class BtReady {
  final int id;
  final String peer;
  final int port;
  final bool incoming;

  const BtReady({
    required this.id,
    required this.peer,
    required this.port,
    required this.incoming,
  });
}

class BtPoll {
  final List<BtReady> ready;
  final List<int> failed;

  /// Zerwane łącza razem z powodem: to jedyne miejsce, w którym widać,
  /// dlaczego rura się skończyła.
  final List<({int id, String reason})> closed;

  /// Notatki ze strony natywnej. Radio nie ma konsoli, więc to jest jedyna
  /// droga, którą kod natywny może cokolwiek powiedzieć.
  final List<String> notes;
  final bool listening;

  /// Czy strona natywna w ogóle odpowiedziała. Bez odpowiedzi [listening]
  /// jest false z braku wiedzy i nie znaczy, że nasłuch padł.
  final bool answered;

  const BtPoll({
    this.ready = const [],
    this.failed = const [],
    this.closed = const [],
    this.notes = const [],
    this.listening = false,
    this.answered = false,
  });
}

/// Rura bajtów nad gniazdem z pętli zwrotnej, czyli nad łączem RFCOMM
/// przełożonym przez kod natywny.
///
/// Publiczna, bo to jedyny kawałek transportu, którego nie da się sprawdzić
/// atrapą w pamięci: różnica między nią a prawdziwym gniazdem (podział na
/// pakiety, hamowanie, zamykanie) jest dokładnie tym, co potrafi się zepsuć.
/// `test/bt_socket_test.dart` przepuszcza przez nią ruch po pętli zwrotnej.
class SocketPipe implements BytePipe {
  final Socket _socket;

  SocketPipe(this._socket);

  @override
  Stream<List<int>> get input => _socket;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  Future<void> flush() => _socket.flush();

  @override
  Future<void> close() async {
    try {
      await _socket.close();
    } catch (_) {
      // Zamykanie zamkniętego gniazda nie jest błędem.
    }
    _socket.destroy();
  }
}

/// Bluetooth jako droga dla bajtów Chatta.
///
/// Trzyma po jednym łączu na rozmówcę i zwielokrotnia na nim wymiany
/// (patrz [BtLink]), bo wiadomość potrafi wyjść w trakcie wysyłania pliku.
/// Łącza przychodzące i wychodzące są tym samym: kto się z kim połączył,
/// przestaje mieć znaczenie, gdy łącze już stoi.
class BluetoothTransport implements PeerTransport {
  /// Obsługa żądań, które przyszły od drugiej strony. Ta sama, którą karmi
  /// serwer HTTP, więc wiadomości i pliki idą tą samą drogą co zawsze.
  final Future<BtResponse> Function(BtRequest request, String peerAddress)?
      onRequest;

  /// Wołane, gdy łącze stanie albo padnie: po tym widać w interfejsie,
  /// którym protokołem stoi rozmowa. [reason] mówi, skąd łącze się wzięło
  /// (`incoming`, `outgoing`) albo dlaczego padło (`native: …` z powodem ze
  /// strony natywnej, poprzedzone `dart: …`, gdy pierwsza zamknęła je ta
  /// strona), do dziennika aplikacji.
  final void Function(String address, bool up, String reason)? onLinkChange;

  /// Wołane, gdy natywny nasłuch padnie (radio zgaszone w systemie) albo
  /// wróci. Tylko przy zmianie: odpytywanie co pół sekundy nie powtarza
  /// tego samego stanu.
  final void Function(bool listening)? onListeningChange;

  /// Błąd w trakcie strumieniowania pliku po stojącym łączu, jak
  /// `HttpTransport.onStreamError`. Ustawia go [PeerClient.useBluetooth].
  void Function(PeerRoute route, String path, Object error)? onStreamError;

  final _links = <String, BtLink>{};
  final _addressOfId = <int, String>{};
  final _connecting = <int, Completer<BtLink?>>{};
  final _waiting = <String, Future<BtLink?>>{};

  Timer? _poll;
  bool _running = false;

  /// Ostatni stan nasłuchu, jaki zgłosiła strona natywna.
  bool _listening = false;

  /// Trwająca próba postawienia nasłuchu na nowo i chwila ostatniej próby.
  Future<void>? _relisten;
  DateTime? _lastRelisten;

  BluetoothTransport(
      {this.onRequest, this.onLinkChange, this.onListeningChange});

  @override
  PeerProtocol get protocol => PeerProtocol.bluetooth;

  bool get isRunning => _running;

  @override
  bool handles(PeerRoute route) =>
      _running && route is BluetoothRoute && route.isUsable;

  /// Zaczyna nasłuch i odpytywanie. Bez tego Bluetooth nie robi nic. Woła
  /// to wyłącznie `AppServices` przy włączonym dodatku Bluetooth.
  Future<bool> start() async {
    if (_running) return true;
    if (!BtChannel.supported) return false;
    if (!await BtChannel.linkStart()) return false;
    // Windows jest wykrywalny tylko przy otwartym oknie „Dodaj urządzenie",
    // więc bez tego telefon nie ma go jak znaleźć.
    await BtChannel.discoverable(true);
    _running = true;
    _listening = true;
    _poll = Timer.periodic(btPollInterval, (_) => _odbierz());
    return true;
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _poll?.cancel();
    _poll = null;
    // Próba postawienia nasłuchu w locie skończy się przed linkStop: inaczej
    // mogłaby otworzyć nasłuch już po zatrzymaniu transportu.
    await _relisten;
    await BtChannel.discoverable(false);
    await BtChannel.linkStop();
    for (final link in _links.values.toList()) {
      await link.close();
    }
    _links.clear();
    _addressOfId.clear();
    for (final pending in _connecting.values) {
      if (!pending.isCompleted) pending.complete(null);
    }
    _connecting.clear();
    _waiting.clear();
  }

  @override
  Future<void> dispose() => stop();

  void _ponowNasluch() {
    if (_relisten != null) return;
    final teraz = DateTime.now();
    final ostatnia = _lastRelisten;
    if (ostatnia != null && teraz.difference(ostatnia) < btListenRetry) return;
    _lastRelisten = teraz;
    _relisten = () async {
      try {
        if (await BtChannel.linkStart() && _running) {
          await BtChannel.discoverable(true);
        }
      } finally {
        _relisten = null;
      }
    }();
  }

  // --- łącza ---------------------------------------------------------------

  Future<void> _odbierz() async {
    if (!_running) return;
    final poll = await BtChannel.linkPoll();
    // Radio zgaszone w systemie zabija nasłuch po stronie natywnej, a po
    // ponownym włączeniu nic go samo nie podnosi. Odpytywanie widzi to jako
    // „nie słucham" i stawia go z powrotem. Przy zgaszonym radiu próba odbija
    // się od razu i wraca po [btListenRetry].
    if (_running && poll.answered && !poll.listening) _ponowNasluch();
    if (_running && poll.answered && poll.listening != _listening) {
      _listening = poll.listening;
      onListeningChange?.call(poll.listening);
    }
    if (btVerbose) {
      for (final note in poll.notes) {
        debugPrint('[bt natywne] $note');
      }
    }
    if (btVerbose &&
        (poll.ready.isNotEmpty ||
            poll.failed.isNotEmpty ||
            poll.closed.isNotEmpty)) {
      debugPrint('[bt] poll gotowe=${poll.ready.map((r) => r.id).toList()} '
          'nieudane=${poll.failed} '
          'zamkniete=${poll.closed.map((c) => '${c.id}(${c.reason})').toList()} '
          'nasluch=${poll.listening}');
    }
    for (final entry in poll.ready) {
      await _podlacz(entry);
    }
    for (final id in poll.failed) {
      _connecting.remove(id)?.complete(null);
    }
    for (final entry in poll.closed) {
      final address = _addressOfId.remove(entry.id);
      if (address == null) continue;
      final link = _links.remove(address);
      // Łącze zamknięte wcześniej po tej stronie (zerwana rura, zła ramka)
      // ma swój powód: strona natywna widzi wtedy tylko zamknięte gniazdo.
      final poTejStronie = link?.closeReason;
      await link?.close(powod: 'natywne: ${entry.reason}');
      if (btVerbose) {
        debugPrint('[bt] padlo lacze ${entry.id} do $address: ${entry.reason}');
      }
      onLinkChange?.call(
        address,
        false,
        poTejStronie == null
            ? 'native: ${entry.reason}'
            : 'dart: $poTejStronie; native: ${entry.reason}',
      );
    }
  }

  Future<void> _podlacz(BtReady entry) async {
    Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        entry.port,
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      _connecting.remove(entry.id)?.complete(null);
      await BtChannel.linkClose(entry.id);
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);

    final handler = onRequest;
    final link = BtLink(
      SocketPipe(socket),
      // Numery strumieni rozdziela to, kto się połączył: strona łącząca się
      // bierze nieparzyste, przyjmująca parzyste.
      initiator: !entry.incoming,
      onRequest: handler == null
          ? null
          : (request) => handler(request, entry.peer),
    );

    // Drugie łącze do tego samego urządzenia (obie strony ruszyły naraz)
    // nie ma po co żyć: zostaje to, które przyszło pierwsze.
    final istniejace = _links[entry.peer];
    if (istniejace != null && !istniejace.isClosed) {
      await link.close();
      // Zamknięcie po stronie Dartowej nie sprząta gniazda w kodzie
      // natywnym: trzeba mu o tym powiedzieć.
      await BtChannel.linkClose(entry.id);
      _connecting.remove(entry.id)?.complete(istniejace);
      if (btVerbose) debugPrint('[bt] zbedne lacze ${entry.id}, zostaje stare');
      return;
    }

    _links[entry.peer] = link;
    _addressOfId[entry.id] = entry.peer;
    _connecting.remove(entry.id)?.complete(link);
    if (btVerbose) {
      debugPrint('[bt] stoi lacze ${entry.id} do ${entry.peer} '
          '(${entry.incoming ? 'przychodzace' : 'wychodzace'}, '
          'port ${entry.port})');
    }
    onLinkChange?.call(
        entry.peer, true, entry.incoming ? 'incoming' : 'outgoing');
  }

  /// Łącze do urządzenia: istniejące albo świeżo nawiązane. null, gdy się
  /// nie udało (wyłączone radio, urządzenie poza zasięgiem, brak Chatta
  /// po drugiej stronie).
  /// Zamyka łącze do tego urządzenia, jeśli jakieś stoi. Przy wyszukiwaniu
  /// pytamy wszystko, co widzi radio, a łącze do czegoś, co Chattem nie jest,
  /// nie ma po co żyć i tylko zajmuje kanał.
  Future<void> dropLink(String address) async {
    final link = _links.remove(address);
    if (link == null) return;
    _addressOfId.removeWhere((_, value) => value == address);
    await link.close(powod: 'niepotrzebne po sprawdzeniu');
  }

  Future<BtLink?> _linkTo(String address, Duration budzet) {
    final existing = _links[address];
    if (existing != null && !existing.isClosed) {
      return Future<BtLink?>.value(existing);
    }
    // Dwie wiadomości naraz do tego samego urządzenia nie mogą otworzyć
    // dwóch łączy: RFCOMM i tak obsługuje jedno na kanał.
    final pending = _waiting[address];
    if (pending != null) return pending;

    final attempt = () async {
      final id = await BtChannel.linkConnect(address);
      if (id == null) return null;
      // Odpytywanie chodzi równolegle i mogło zdążyć odebrać to łącze, zanim
      // wrócił jego numer. Bez tego sprawdzenia czekalibyśmy tu pełne 25 s na
      // zgłoszenie, które już się odbyło.
      final juz = _links[address];
      if (juz != null && !juz.isClosed) return juz;

      final done = Completer<BtLink?>();
      _connecting[id] = done;
      // Łączenie po RFCOMM potrafi trwać kilkanaście sekund, a nieudane
      // kończy się ciszą, więc ma własny limit. Przy wyszukiwaniu jest on
      // krótki, bo nieudanych prób jest tyle, ile urządzeń w zasięgu,
      // a każda z nich zagłusza radio.
      return done.future.timeout(
        budzet,
        onTimeout: () {
          _connecting.remove(id);
          unawaited(BtChannel.linkClose(id));
          return null;
        },
      );
    }();
    _waiting[address] = attempt;
    return attempt.whenComplete(() => _waiting.remove(address));
  }

  /// Czy stoi łącze do tego adresu. Po tym interfejs pokazuje, że rozmowa
  /// idzie przez Bluetooth.
  bool isLinked(String address) {
    final link = _links[address];
    return link != null && !link.isClosed;
  }

  List<String> get linkedAddresses => [
        for (final entry in _links.entries)
          if (!entry.value.isClosed) entry.key,
      ];

  // --- transport -----------------------------------------------------------

  @override
  Future<TransportReply> request(
    PeerRoute route,
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int> body = const [],
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (route is! BluetoothRoute || !route.isUsable || !_running) {
      return const TransportReply.unreachable();
    }
    final link = await _linkTo(route.address, _budzetLaczenia(timeout));
    if (link == null) return const TransportReply.unreachable();
    try {
      final response = await link
          .send(
            method,
            path,
            headers: headers,
            body: body.isEmpty ? null : Stream<List<int>>.value(body),
          )
          // Bluetooth jest kilkadziesiąt razy wolniejszy od Wi-Fi, więc limity
          // z HTTP są tu za ciasne: pomiar z docs/spike-rfcomm.md daje 22 ms
          // na obrót krótkiej wiadomości, ale przy zajętym łączu czeka się
          // na swoją kolej.
          .timeout(timeout * 3);
      return TransportReply(response.status, await _zbierz(response.body));
    } catch (_) {
      return const TransportReply.unreachable();
    }
  }

  @override
  Future<TransportReply> stream(
    PeerRoute route,
    String path, {
    required Map<String, String> headers,
    required File file,
    int offset = 0,
    void Function(int sentBytes, int totalBytes)? onProgress,
    Stream<List<int>> Function(Stream<List<int>> data, int startOffset)?
        transform,
  }) async {
    if (route is! BluetoothRoute || !route.isUsable || !_running) {
      return const TransportReply.unreachable();
    }
    final link = await _linkTo(route.address, const Duration(seconds: 25));
    if (link == null) return const TransportReply.unreachable();

    try {
      final total = await file.length();
      final start = (offset < 0 || offset > total) ? 0 : offset;
      var sent = start;

      final source = transform == null
          ? file.openRead(start)
          : transform(file.openRead(start), start);
      final counted = source.map((chunk) {
        sent += chunk.length;
        onProgress?.call(sent, total);
        return chunk;
      });

      final response = await link.send(
        'POST',
        path,
        headers: {...headers, 'content-type': 'application/octet-stream'},
        body: counted,
      );
      return TransportReply(response.status, await _zbierz(response.body));
    } catch (blad) {
      try {
        onStreamError?.call(route, path, blad);
      } catch (_) {
        // Zgłoszenie jest dodatkiem: wynik to i tak „nieosiągalny”.
      }
      return const TransportReply.unreachable();
    }
  }

  /// Ile czekamy na nawiązanie łącza. Udane trwa sekundę albo dwie, więc
  /// limit bierze się z cierpliwości wołającego: krótkie pytanie nie ma
  /// prawa wisieć pół minuty.
  static Duration _budzetLaczenia(Duration timeout) {
    final podwojony = timeout * 2;
    if (podwojony < const Duration(seconds: 8)) {
      return const Duration(seconds: 8);
    }
    if (podwojony > const Duration(seconds: 25)) {
      return const Duration(seconds: 25);
    }
    return podwojony;
  }

  static Future<List<int>> _zbierz(Stream<List<int>> body) async {
    final out = <int>[];
    await for (final chunk in body) {
      out.addAll(chunk);
    }
    return out;
  }

  /// Wygodne dla warstwy wyżej: odpowiedź jako tekst.
  static String asText(TransportReply reply) => utf8.decode(
        reply.body,
        allowMalformed: true,
      );
}
