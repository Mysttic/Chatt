import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';

import 'bencode.dart';
import 'udp_mux.dart';

/// Klient DHT Mainline (BEP 5) na tyle, na ile potrzebuje go skrzynka
/// kontaktowa: zapis i odczyt „mutable item" z BEP 44.
///
/// Skrzynka nie przenosi wiadomości Chatta. Trzyma jeden mały, podpisany
/// i zaszyfrowany rekord: „urządzenie X jest teraz pod adresem Y". Dwa
/// urządzenia, które spotkały się wcześniej w jednej sieci, liczą z tego
/// samego sekretu ten sam adres skrzynki i ten sam klucz, więc odnajdują się
/// w DHT bez żadnego serwera pośredniczącego.
///
/// To nie jest pełny węzeł DHT: niczego nie przechowuje dla innych. Pamięta
/// tylko węzły, które odpowiedziały w tym uruchomieniu, i kolejne
/// przeszukiwanie zaczyna od tych najbliższych celowi. Bez nich startuje od
/// węzłów rozruchowych.

/// Węzły rozruchowe. Nazwy, nie adresy, bo ich adresy się zmieniają.
const List<(String, int)> defaultDhtBootstrap = [
  ('router.bittorrent.com', 6881),
  ('router.utorrent.com', 6881),
  ('dht.transmissionbt.com', 6881),
  ('dht.libtorrent.org', 25401),
];

/// Największy bencode wartości `v` w „put" (BEP 44). Ponad to węzły odrzucają.
const int dhtMaxValueBytes = 1000;

/// Najdłuższa sól (BEP 44).
const int dhtMaxSaltBytes = 64;

class DhtException implements Exception {
  final String message;
  const DhtException(this.message);
  @override
  String toString() => 'DhtException: $message';
}

/// Adres węzła DHT.
class DhtEndpoint {
  final InternetAddress address;
  final int port;

  const DhtEndpoint(this.address, this.port);

  String get key => '${address.address}:$port';

  @override
  bool operator ==(Object other) =>
      other is DhtEndpoint && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'DhtEndpoint($key)';
}

/// Para kluczy Ed25519 do podpisu rekordu BEP 44. Podpis zadowala węzły DHT;
/// tajność adresu daje szyfrowanie samej wartości, nie ten podpis.
class DhtSigner {
  static final _ed25519 = Ed25519();

  final SimpleKeyPair _keyPair;
  final Uint8List publicKey;

  DhtSigner._(this._keyPair, this.publicKey);

  /// Buduje parę z 32-bajtowego ziarna (klucza prywatnego Ed25519).
  static Future<DhtSigner> fromSeed(List<int> seed) async {
    if (seed.length != 32) {
      throw ArgumentError('ziarno Ed25519 ma 32 bajty');
    }
    final kp = await _ed25519.newKeyPairFromSeed(seed);
    final pub = await kp.extractPublicKey();
    return DhtSigner._(kp, Uint8List.fromList(pub.bytes));
  }

  Future<Uint8List> sign(List<int> message) async {
    final sig = await _ed25519.sign(message, keyPair: _keyPair);
    return Uint8List.fromList(sig.bytes);
  }

  /// Sprawdza podpis cudzego rekordu.
  static Future<bool> verify(
    List<int> message,
    List<int> signature,
    List<int> publicKey,
  ) async {
    try {
      return await _ed25519.verify(
        message,
        signature: Signature(
          signature,
          publicKey:
              SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

/// Adres skrzynki (target) dla klucza publicznego i soli (BEP 44): SHA-1
/// z klucza, a gdy sól niepusta, z klucza i soli.
Uint8List dhtTarget(List<int> publicKey, [List<int> salt = const []]) {
  final input = salt.isEmpty ? publicKey : <int>[...publicKey, ...salt];
  return Uint8List.fromList(digest.sha1.convert(input).bytes);
}

/// Bajty podpisywane w BEP 44: `4:salt<len>:<salt>3:seqi<seq>e1:v<raw>`,
/// gdzie `<raw>` to już zbencode'owana wartość `v`. Przedrostek z solą
/// wchodzi tylko, gdy sól jest niepusta.
Uint8List bep44SignatureBuffer(List<int> salt, int seq, List<int> bencodedValue) {
  final out = BytesBuilder(copy: false);
  if (salt.isNotEmpty) {
    out.add(ascii.encode('4:salt${salt.length}:'));
    out.add(salt);
  }
  out.add(ascii.encode('3:seqi${seq}e1:v'));
  out.add(bencodedValue);
  return out.takeBytes();
}

/// Rekord odczytany ze skrzynki.
class DhtMutableValue {
  /// Surowa, zbencode'owana zawartość `v`, dokładnie jak w podpisie.
  final Uint8List value;
  final int seq;
  final Uint8List publicKey;
  final Uint8List signature;

  const DhtMutableValue({
    required this.value,
    required this.seq,
    required this.publicKey,
    required this.signature,
  });
}

/// Jedna transakcja KRPC w locie.
class _Transaction {
  final Completer<Map<String, Object>> reply = Completer<Map<String, Object>>();
  final DhtEndpoint endpoint;
  _Transaction(this.endpoint);
}

class DhtClient {
  final UdpMux _mux;

  /// Nasz identyfikator węzła: 20 losowych bajtów na czas działania.
  final Uint8List nodeId;

  final List<(String, int)> bootstrap;

  /// Ile węzłów pytamy równolegle w jednej rundzie (α z Kademlii).
  final int alpha;

  /// Ile najbliższych węzłów bierze „put".
  final int replicate;

  final Duration queryTimeout;

  /// Po takim czasie milczenia węzeł oddaje miejsce w przeszukiwaniu
  /// następnemu kandydatowi. Jego spóźniona odpowiedź wciąż się liczy;
  /// twardy limit to [queryTimeout].
  final Duration softTimeout;

  /// Górny limit jednego przeszukiwania. Po nim wynik jest tym, co zebrano.
  final Duration lookupTimeout;

  /// Węzły, które odpowiedziały w tym uruchomieniu, od najstarszego.
  final _pamiec = <String, (DhtEndpoint, Uint8List)>{};
  static const int _pamiecMax = 256;

  final _pending = <String, _Transaction>{};
  var _nextTid = 0;
  bool _registered = false;
  List<DhtEndpoint> _resolvedBootstrap = const [];

  /// Węzły rozruchowe wstrzyknięte wprost, z pominięciem DNS-u. Wyłącznie do
  /// testów nad siecią w pamięci.
  List<DhtEndpoint>? debugBootstrap;

  DhtClient(
    this._mux, {
    Uint8List? nodeId,
    this.bootstrap = defaultDhtBootstrap,
    this.alpha = 8,
    this.replicate = 8,
    this.queryTimeout = const Duration(seconds: 3),
    this.softTimeout = const Duration(seconds: 1),
    this.lookupTimeout = const Duration(seconds: 20),
    Random? random,
  }) : nodeId = nodeId ??
            Uint8List.fromList(
                List<int>.generate(20, (_) => (random ?? Random.secure()).nextInt(256)));

  bool _onPacket(UdpPacket packet) {
    final decoded = tryBdecode(packet.data);
    if (decoded is! Map) return false;
    final tid = bBytes(decoded, 't');
    final type = bText(decoded, 'y');
    if (tid == null || type == null) return false;
    final pending = _pending.remove(_tidKey(tid));
    if (pending == null) return true; // DHT, ale nie nasze (albo spóźnione)
    if (pending.reply.isCompleted) return true;
    if (type == 'r') {
      final r = bDict(decoded, 'r');
      pending.reply.complete(r ?? const <String, Object>{});
    } else {
      // Błąd albo coś nieoczekiwanego: transakcja kończy się pusto, żeby
      // przeszukiwanie szło dalej innymi węzłami.
      pending.reply.complete(const <String, Object>{});
    }
    return true;
  }

  void _ensureRegistered() {
    if (_registered) return;
    _mux.register(_onPacket);
    _registered = true;
  }

  Future<List<DhtEndpoint>> _bootstrapEndpoints() async {
    final wstrzykniete = debugBootstrap;
    if (wstrzykniete != null) return wstrzykniete;
    if (_resolvedBootstrap.isNotEmpty) return _resolvedBootstrap;
    final out = <DhtEndpoint>[];
    for (final (host, port) in bootstrap) {
      try {
        final adresy = await InternetAddress.lookup(host,
            type: InternetAddressType.IPv4);
        if (adresy.isNotEmpty) out.add(DhtEndpoint(adresy.first, port));
      } catch (_) {
        // Jeden węzeł rozruchowy, którego nazwa się nie rozwiązała, nie
        // przerywa startu: są inne.
      }
    }
    _resolvedBootstrap = out;
    return out;
  }

  String _tidKey(List<int> tid) =>
      tid.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Uint8List _newTid() {
    final value = _nextTid++ & 0xFFFF;
    return Uint8List.fromList([(value >> 8) & 0xFF, value & 0xFF]);
  }

  /// Wysyła zapytanie KRPC i czeka na odpowiedź. Pusta mapa = nie odpowiedział
  /// albo zwrócił błąd.
  Future<Map<String, Object>> _query(
    DhtEndpoint endpoint,
    String method,
    Map<String, Object> args,
  ) async {
    _ensureRegistered();
    final tid = _newTid();
    final transaction = _Transaction(endpoint);
    _pending[_tidKey(tid)] = transaction;
    final packet = bencode(<String, Object>{
      't': tid,
      'y': 'q',
      'q': method,
      'a': args,
      // BEP 43: nie jesteśmy pełnym węzłem, więc nie chcemy trafić do cudzych
      // tablic routingu.
      'ro': 1,
    });
    _mux.send(packet, endpoint.address, endpoint.port);
    try {
      return await transaction.reply.future.timeout(queryTimeout);
    } catch (_) {
      _pending.remove(_tidKey(tid));
      return const <String, Object>{};
    }
  }

  /// Odległość XOR między 20-bajtowymi identyfikatorami, jako porównanie.
  static int _closer(Uint8List target, Uint8List a, Uint8List b) {
    for (var i = 0; i < 20; i++) {
      final da = (i < a.length ? a[i] : 0) ^ target[i];
      final db = (i < b.length ? b[i] : 0) ^ target[i];
      if (da != db) return da - db;
    }
    return 0;
  }

  static List<DhtEndpoint> _parseNodes(Uint8List? compact) {
    if (compact == null) return const [];
    final out = <DhtEndpoint>[];
    final view = ByteData.sublistView(compact);
    for (var at = 0; at + 26 <= compact.length; at += 26) {
      final ip = compact.sublist(at + 20, at + 24);
      final port = view.getUint16(at + 24);
      out.add(DhtEndpoint(
        InternetAddress.fromRawAddress(Uint8List.fromList(ip),
            type: InternetAddressType.IPv4),
        port,
      ));
    }
    return out;
  }

  static Uint8List? _nodeIdOf(Uint8List? compact, int index) {
    if (compact == null) return null;
    final at = index * 26;
    if (at + 20 > compact.length) return null;
    return Uint8List.fromList(compact.sublist(at, at + 20));
  }

  /// Przeszukiwanie iteracyjne w stronę [target] zapytaniem `get`. Zbiera
  /// żetony zapisu z najbliższych węzłów i, przy odczycie, najlepszy rekord.
  ///
  /// Bez rund: najwyżej [alpha] pytań czeka naraz, a każda odpowiedź albo
  /// cisza od razu zwalnia miejsce dla najbliższego niezapytanego kandydata.
  /// Węzeł milczący dłużej niż [softTimeout] też zwalnia miejsce, więc martwe
  /// węzły nie wstrzymują reszty. Koniec, gdy [replicate] najbliższych
  /// żywych kandydatów odpowiedziało albo gdy nie ma już kogo pytać.
  Future<_Lookup> _lookup(
    Uint8List target,
    Uint8List? wantPublicKey, {
    List<int> verifySalt = const [],
  }) async {
    final bootstrap = await _bootstrapEndpoints();

    // Kandydaci: najpierw zapamiętani najbliżsi celowi, potem węzły
    // rozruchowe. Te mają nieznany identyfikator i stoją na końcu kolejki,
    // a gdy pamięć jest pusta, idą pierwsze, bo nie ma nikogo innego.
    final kandydaci = <String, _Kandydat>{};
    final zPamieci = _pamiec.values.toList()
      ..sort((a, b) => _closer(target, a.$2, b.$2));
    for (final (ep, id) in zPamieci.take(replicate * 2)) {
      kandydaci[ep.key] = _Kandydat(ep, id);
    }
    for (final ep in bootstrap) {
      // Dwie próby: jeden zgubiony pakiet do węzła rozruchowego nie może
      // skończyć całego przeszukiwania niczym.
      kandydaci.putIfAbsent(
          ep.key, () => _Kandydat(ep, null, proby: 2, rozruchowy: true));
    }
    if (kandydaci.isEmpty) {
      throw const DhtException('brak węzłów rozruchowych');
    }

    int porownaj(_Kandydat a, _Kandydat b) {
      final ida = a.id;
      final idb = b.id;
      if (ida == null && idb == null) return 0;
      if (ida == null) return 1;
      if (idb == null) return -1;
      return _closer(target, ida, idb);
    }

    final wartosci = <DhtMutableValue>[];
    final koniec = Completer<void>();
    var wLocie = 0;
    late final void Function() pompuj;

    void zapytaj(_Kandydat k) {
      k.stan = _Stan.czeka;
      wLocie++;
      var oddane = false;
      void oddaj() {
        if (oddane) return;
        oddane = true;
        wLocie--;
      }

      final miekki = Timer(softTimeout, () {
        k.wolny = true;
        oddaj();
        pompuj();
      });
      // Węzły rozruchowe dostają `find_node`: część z nich nie zna `get`
      // z BEP 44 i odpowiada błędem 204, a do wejścia w sieć wystarczy lista
      // węzłów. Żeton i rekord dają dopiero węzły bliżej celu.
      _query(k.ep, k.rozruchowy ? 'find_node' : 'get', <String, Object>{
        'id': nodeId,
        'target': target,
      }).then((r) {
        miekki.cancel();
        oddaj();
        if (koniec.isCompleted) return;
        if (r.isEmpty) {
          k.proby--;
          k.stan = k.proby > 0 ? _Stan.nowy : _Stan.padl;
        } else {
          final id = bBytes(r, 'id');
          final znaneId = id != null && id.length == 20;
          if (znaneId) _zapamietaj(k.ep, id);
          if (k.rozruchowy) {
            // Węzeł rozruchowy podał drogę i swój identyfikator. Od teraz to
            // zwykły kandydat: gdy leży blisko celu, dostanie jeszcze `get`.
            k.stan = _Stan.padl;
            if (znaneId) kandydaci[k.ep.key] = _Kandydat(k.ep, id);
          } else {
            k.stan = _Stan.odpowiedzial;
            k.token = bBytes(r, 'token');
          }
          if (wantPublicKey != null && !k.rozruchowy) {
            final wartosc = _readValue(r, wantPublicKey);
            if (wartosc != null) wartosci.add(wartosc);
          }
          final nodes = bBytes(r, 'nodes');
          final lista = _parseNodes(nodes);
          for (var i = 0; i < lista.length; i++) {
            final nid = _nodeIdOf(nodes, i);
            if (nid == null || !_routable(lista[i])) continue;
            kandydaci.putIfAbsent(
                lista[i].key, () => _Kandydat(lista[i], nid));
          }
        }
        pompuj();
      });
    }

    pompuj = () {
      if (koniec.isCompleted) return;
      final posortowani = kandydaci.values.toList()..sort(porownaj);
      // Koniec, gdy `replicate` najbliższych żywych odpowiedziało. Milczący
      // dłużej niż miękki limit tego nie wstrzymuje, a gdy zdąży odpowiedzieć,
      // liczy się jak każdy inny. Gdy żywych jest mniej, koniec dopiero wtedy,
      // gdy nikt już nie czeka: inaczej jeden wolny węzeł rozruchowy kończyłby
      // przeszukiwanie, zanim podał choć jeden adres.
      var odpowiedzialo = 0;
      bool? zbiegl;
      for (final k in posortowani) {
        if (k.stan == _Stan.padl || (k.stan == _Stan.czeka && k.wolny)) {
          continue;
        }
        if (k.stan != _Stan.odpowiedzial) {
          zbiegl = false;
          break;
        }
        if (++odpowiedzialo >= replicate) {
          zbiegl = true;
          break;
        }
      }
      zbiegl ??= !posortowani.any((k) => k.stan == _Stan.czeka);
      if (zbiegl) {
        koniec.complete();
        return;
      }
      for (final k in posortowani) {
        if (wLocie >= alpha) break;
        if (k.stan == _Stan.nowy) zapytaj(k);
      }
    };

    pompuj();
    await koniec.future.timeout(lookupTimeout, onTimeout: () {});
    if (!koniec.isCompleted) koniec.complete();

    final posortowani = kandydaci.values.toList()..sort(porownaj);
    final closestWithToken = <(DhtEndpoint, Uint8List)>[
      for (final k in posortowani)
        if (k.stan == _Stan.odpowiedzial && k.token != null) (k.ep, k.token!),
    ];

    // Rekord: najwyższy numer z poprawnym podpisem. Podpisy idą od
    // najwyższego numeru w dół, więc podrobiony rekord z wysokim numerem
    // odpada i nie przesłania prawdziwego.
    wartosci.sort((a, b) => b.seq.compareTo(a.seq));
    final sprawdzone = <String>{};
    DhtMutableValue? best;
    for (final w in wartosci) {
      if (!sprawdzone.add(_tidKey(w.signature))) continue;
      final ok = await DhtSigner.verify(
          bep44SignatureBuffer(verifySalt, w.seq, w.value),
          w.signature,
          w.publicKey);
      if (ok) {
        best = w;
        break;
      }
    }
    return _Lookup(closestWithToken, best);
  }

  /// Czy węzeł z cudzej listy warto pytać. Odpada adres, pod który gniazdo
  /// nie wyśle ([udpSendable]), pętla zwrotna, a w prawdziwej sieci także
  /// adresy prywatne: z internetu ich nie widać, a zapytanie poszłoby do
  /// czyjejś sieci lokalnej. Testy z [debugBootstrap] stoją na adresach
  /// prywatnych, więc tam zostają.
  bool _routable(DhtEndpoint ep) {
    if (!udpSendable(ep.address, ep.port)) return false;
    final b = ep.address.rawAddress;
    if (b[0] == 127) return false;
    if (debugBootstrap != null) return true;
    return !(b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] < 32) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 100 && b[1] >= 64 && b[1] < 128) ||
        (b[0] == 169 && b[1] == 254));
  }

  void _zapamietaj(DhtEndpoint ep, Uint8List id) {
    _pamiec.remove(ep.key);
    _pamiec[ep.key] = (ep, id);
    if (_pamiec.length > _pamiecMax) _pamiec.remove(_pamiec.keys.first);
  }

  DhtMutableValue? _readValue(Map<String, Object> r, Uint8List wantPublicKey) {
    final raw = bBytes(r, rawValueKey) ?? bBytes(r, 'v');
    final seq = bInt(r, 'seq');
    final sig = bBytes(r, 'sig');
    final k = bBytes(r, 'k');
    if (raw == null || seq == null || sig == null || k == null) return null;
    if (k.length != 32 ||
        !_sameBytes(k, wantPublicKey)) {
      return null;
    }
    return DhtMutableValue(value: raw, seq: seq, publicKey: k, signature: sig);
  }

  /// Czyta rekord ze skrzynki i sprawdza jego podpis. null, gdy nic nie
  /// znaleziono albo podpis się nie zgadza.
  Future<DhtMutableValue?> getMutable(
    List<int> publicKey, {
    List<int> salt = const [],
  }) async {
    final target = dhtTarget(publicKey, salt);
    // `_lookup` już odsiewa rekordy z błędnym podpisem, więc zwrócony jest
    // albo zweryfikowany, albo go nie ma.
    final lookup = await _lookup(target, Uint8List.fromList(publicKey),
        verifySalt: salt);
    return lookup.value;
  }

  /// Zapisuje rekord do skrzynki. [bencodedValue] to już zbencode'owana
  /// wartość `v` (patrz [bencode]); nie może przekroczyć [dhtMaxValueBytes].
  /// Zwraca, do ilu węzłów rekord trafił bez błędu.
  Future<int> putMutable(
    DhtSigner signer, {
    required List<int> bencodedValue,
    required int seq,
    List<int> salt = const [],
  }) async {
    if (bencodedValue.length > dhtMaxValueBytes) {
      throw DhtException('wartość za duża: ${bencodedValue.length} B');
    }
    if (salt.length > dhtMaxSaltBytes) {
      throw DhtException('sól za długa: ${salt.length} B');
    }
    final target = dhtTarget(signer.publicKey, salt);
    final lookup = await _lookup(target, null);
    if (lookup.closestWithToken.isEmpty) return 0;

    final signature =
        await signer.sign(bep44SignatureBuffer(salt, seq, bencodedValue));

    var stored = 0;
    final cele = lookup.closestWithToken.take(replicate).toList();
    final wyniki = await Future.wait([
      for (final (endpoint, token) in cele)
        _query(endpoint, 'put', <String, Object>{
          'id': nodeId,
          'k': signer.publicKey,
          if (salt.isNotEmpty) 'salt': Uint8List.fromList(salt),
          'seq': seq,
          'sig': signature,
          'token': token,
          'v': BencodeRaw(Uint8List.fromList(bencodedValue)),
        }),
    ]);
    for (final r in wyniki) {
      // Węzeł, który przyjął, odsyła odpowiedź `r` ze swoim `id`. Błąd (albo
      // brak odpowiedzi) daje pustą mapę.
      if (r.isNotEmpty) stored++;
    }
    return stored;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> close() async {
    if (_registered) _mux.unregister(_onPacket);
    _registered = false;
    for (final t in _pending.values) {
      if (!t.reply.isCompleted) t.reply.complete(const <String, Object>{});
    }
    _pending.clear();
  }
}

enum _Stan { nowy, czeka, odpowiedzial, padl }

/// Kandydat w jednym przeszukiwaniu.
class _Kandydat {
  final DhtEndpoint ep;

  /// Identyfikator węzła; null dla węzła rozruchowego przed odpowiedzią.
  final Uint8List? id;

  /// Węzeł rozruchowy: pytany o drogę (`find_node`), bez żetonu i rekordu.
  final bool rozruchowy;
  _Stan stan = _Stan.nowy;

  /// Przekroczył miękki limit i wciąż milczy.
  bool wolny = false;
  int proby;
  Uint8List? token;

  _Kandydat(this.ep, this.id, {this.proby = 1, this.rozruchowy = false});
}

class _Lookup {
  final List<(DhtEndpoint, Uint8List)> closestWithToken;
  final DhtMutableValue? value;
  const _Lookup(this.closestWithToken, this.value);
}
