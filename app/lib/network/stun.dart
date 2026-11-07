import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'udp_mux.dart';

/// Najprostszy klient STUN (RFC 5389): jedno pytanie „Binding" i odczyt
/// adresu, pod którym serwer nas widzi.
///
/// Serwer STUN niczego nie przenosi. Odpowiada jednym pakietem: „widzę cię
/// jako X:Y", czyli mówi, jaki adres i port nadał nam NAT po drodze. Ten sam
/// adres trafia potem do skrzynki kontaktowej w DHT, więc pytanie musi wyjść
/// z tego samego gniazda UDP, którym potem idą pakiety do rozmówcy.

/// Stała z RFC 5389: odróżnia STUN od starego RFC 3489 i od innych
/// protokołów na tym samym gnieździe.
const int stunMagicCookie = 0x2112A442;

const int _bindingRequest = 0x0001;
const int _bindingSuccess = 0x0101;
const int _attrMappedAddress = 0x0001;
const int _attrXorMappedAddress = 0x0020;

/// Domyślne serwery. Dwa różne, bo porównanie odpowiedzi mówi, jaki NAT
/// stoi po drodze (patrz [NatMapping]).
const List<(String, int)> defaultStunServers = [
  ('stun.l.google.com', 19302),
  ('stun.cloudflare.com', 3478),
];

/// Czy pakiet wygląda na STUN: dwa najstarsze bity zero i ciasteczko na
/// swoim miejscu. Po tym gniazdo odróżnia STUN od DHT i od pakietów Chatta.
bool looksLikeStun(Uint8List data) {
  if (data.length < 20 || (data[0] & 0xC0) != 0) return false;
  final view = ByteData.sublistView(data);
  return view.getUint32(4) == stunMagicCookie;
}

/// Losowy numer transakcji, 12 bajtów.
Uint8List newStunTransaction([Random? random]) {
  final los = random ?? Random.secure();
  return Uint8List.fromList(List<int>.generate(12, (_) => los.nextInt(256)));
}

/// Pytanie „Binding" bez żadnych atrybutów.
Uint8List stunBindingRequest(Uint8List transaction) {
  if (transaction.length != 12) {
    throw ArgumentError('numer transakcji STUN ma 12 bajtów');
  }
  final out = Uint8List(20);
  final view = ByteData.sublistView(out);
  view.setUint16(0, _bindingRequest);
  view.setUint16(2, 0);
  view.setUint32(4, stunMagicCookie);
  out.setRange(8, 20, transaction);
  return out;
}

/// Adres widziany przez serwer.
class StunMapping {
  final InternetAddress address;
  final int port;

  const StunMapping(this.address, this.port);

  String get label => '${address.address}:$port';

  @override
  bool operator ==(Object other) =>
      other is StunMapping &&
      other.address.address == address.address &&
      other.port == port;

  @override
  int get hashCode => Object.hash(address.address, port);

  @override
  String toString() => 'StunMapping($label)';
}

/// Numer transakcji z odpowiedzi, do dopasowania jej do pytania.
Uint8List? stunTransactionOf(Uint8List data) =>
    looksLikeStun(data) ? Uint8List.fromList(data.sublist(8, 20)) : null;

/// Czyta odpowiedź na [stunBindingRequest]. null, gdy to nie jest udana
/// odpowiedź z adresem.
///
/// Atrybut XOR-MAPPED-ADDRESS ma pierwszeństwo przed starym
/// MAPPED-ADDRESS: część NAT-ów przepisuje w pakietach wszystko, co
/// wygląda na ich własny adres, a wersja z XOR tego nie przypomina.
StunMapping? parseStunBindingResponse(Uint8List data) {
  if (!looksLikeStun(data)) return null;
  final view = ByteData.sublistView(data);
  if (view.getUint16(0) != _bindingSuccess) return null;
  final dlugosc = view.getUint16(2);
  if (20 + dlugosc > data.length || dlugosc % 4 != 0) return null;
  final transakcja = data.sublist(8, 20);

  StunMapping? zwykly;
  var at = 20;
  final koniec = 20 + dlugosc;
  while (at + 4 <= koniec) {
    final typ = view.getUint16(at);
    final dl = view.getUint16(at + 2);
    final start = at + 4;
    if (start + dl > koniec) return null;
    final wartosc = Uint8List.sublistView(data, start, start + dl);
    if (typ == _attrXorMappedAddress) {
      final adres = _readAddress(wartosc, xor: true, transaction: transakcja);
      if (adres != null) return adres;
    } else if (typ == _attrMappedAddress) {
      zwykly ??= _readAddress(wartosc, xor: false, transaction: transakcja);
    }
    // Atrybuty są wyrównane do czterech bajtów.
    at = start + ((dl + 3) & ~3);
  }
  return zwykly;
}

StunMapping? _readAddress(Uint8List value,
    {required bool xor, required List<int> transaction}) {
  if (value.length < 8) return null;
  final view = ByteData.sublistView(value);
  final rodzina = value[1];
  var port = view.getUint16(2);
  if (xor) port ^= stunMagicCookie >> 16;
  if (rodzina == 0x01) {
    final bajty = Uint8List.fromList(value.sublist(4, 8));
    if (xor) {
      final ciastko = ByteData(4)..setUint32(0, stunMagicCookie);
      for (var i = 0; i < 4; i++) {
        bajty[i] ^= ciastko.getUint8(i);
      }
    }
    return StunMapping(
        InternetAddress.fromRawAddress(bajty, type: InternetAddressType.IPv4),
        port);
  }
  if (rodzina == 0x02 && value.length >= 20) {
    final bajty = Uint8List.fromList(value.sublist(4, 20));
    if (xor) {
      final klucz = Uint8List(16);
      ByteData.sublistView(klucz).setUint32(0, stunMagicCookie);
      klucz.setRange(4, 16, transaction);
      for (var i = 0; i < 16; i++) {
        bajty[i] ^= klucz[i];
      }
    }
    return StunMapping(
        InternetAddress.fromRawAddress(bajty, type: InternetAddressType.IPv6),
        port);
  }
  return null;
}

/// Co mówi porównanie odpowiedzi dwóch różnych serwerów STUN zadanych
/// z jednego gniazda.
enum NatMapping {
  /// Nie wiadomo: odpowiedział jeden serwer albo żaden.
  unknown,

  /// Ten sam adres i port dla obu serwerów: NAT nadaje jedno mapowanie
  /// niezależnie od celu. Przy takim przebicie dziury zwykle wychodzi.
  endpointIndependent,

  /// Różne porty (albo adresy): NAT nadaje osobne mapowanie dla każdego
  /// celu, czyli jest „symetryczny". Adres ze skrzynki nie zgadza się wtedy
  /// z tym, którym pójdą pakiety do rozmówcy, i przebicie raczej nie wyjdzie.
  endpointDependent,

  /// Adres widziany z zewnątrz jest adresem tego urządzenia: nie ma NAT-u.
  none,
}

/// Ocena NAT-u z dwóch odpowiedzi i lokalnego adresu gniazda.
NatMapping classifyNat(StunMapping? first, StunMapping? second,
    {Iterable<String> localAddresses = const []}) {
  final znany = first ?? second;
  if (znany != null && localAddresses.contains(znany.address.address)) {
    return NatMapping.none;
  }
  if (first == null || second == null) return NatMapping.unknown;
  return first == second
      ? NatMapping.endpointIndependent
      : NatMapping.endpointDependent;
}

/// Pyta serwery STUN o adres, pod którym widać to gniazdo. Działa na
/// wspólnym [UdpMux], więc pyta z tego samego portu, którym potem pójdą
/// pakiety do rozmówcy, i mapowanie zmierzone tutaj jest tym samym, które
/// dostanie druga strona.
class StunClient {
  final UdpMux _mux;
  final Duration timeout;

  /// Oczekujące pytania po numerze transakcji (jako hex).
  final _pending = <String, Completer<StunMapping>>{};
  bool _registered = false;

  StunClient(this._mux, {this.timeout = const Duration(seconds: 2)});

  bool _onPacket(UdpPacket packet) {
    if (!looksLikeStun(packet.data)) return false;
    final transakcja = stunTransactionOf(packet.data);
    if (transakcja == null) return false;
    final pending = _pending.remove(_hex(transakcja));
    if (pending == null) return true; // STUN, ale nie nasze pytanie
    final mapping = parseStunBindingResponse(packet.data);
    if (mapping != null && !pending.isCompleted) {
      pending.complete(mapping);
    } else if (!pending.isCompleted) {
      pending.completeError(const StunException('zła odpowiedź STUN'));
    }
    return true;
  }

  void _ensureRegistered() {
    if (_registered) return;
    _mux.register(_onPacket);
    _registered = true;
  }

  /// Pyta jeden serwer. null, gdy nie odpowiedział w czasie albo nazwa się
  /// nie rozwiązała.
  Future<StunMapping?> query((String, int) server, {Random? random}) async {
    _ensureRegistered();
    final List<InternetAddress> adresy;
    try {
      adresy = await InternetAddress.lookup(server.$1,
          type: InternetAddressType.IPv4);
    } catch (_) {
      return null;
    }
    if (adresy.isEmpty) return null;

    final transakcja = newStunTransaction(random);
    final klucz = _hex(transakcja);
    final completer = Completer<StunMapping>();
    _pending[klucz] = completer;
    _mux.send(stunBindingRequest(transakcja), adresy.first, server.$2);
    try {
      return await completer.future.timeout(timeout);
    } catch (_) {
      _pending.remove(klucz);
      return null;
    }
  }

  /// Pyta dwa serwery i mówi, jaki NAT stoi po drodze. Zwraca też sam adres
  /// (z pierwszego, który odpowiedział), bo to on idzie do skrzynki.
  Future<({StunMapping? mapping, NatMapping nat})> discover({
    List<(String, int)> servers = defaultStunServers,
    Iterable<String> localAddresses = const [],
    Random? random,
  }) async {
    final first = servers.isNotEmpty ? await query(servers[0], random: random) : null;
    final second =
        servers.length > 1 ? await query(servers[1], random: random) : null;
    return (
      mapping: first ?? second,
      nat: classifyNat(first, second, localAddresses: localAddresses),
    );
  }

  void dispose() {
    if (_registered) _mux.unregister(_onPacket);
    _registered = false;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(const StunException('zamknięto'));
      }
    }
    _pending.clear();
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class StunException implements Exception {
  final String message;
  const StunException(this.message);
  @override
  String toString() => 'StunException: $message';
}
