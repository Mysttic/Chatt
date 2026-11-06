import 'dart:convert';
import 'dart:typed_data';

import 'package:chatt/network/bencode.dart';
import 'package:chatt/network/dht.dart';
import 'package:chatt/network/udp_mux.dart';
import 'package:crypto/crypto.dart' as digest;

import 'fake_udp.dart';

/// Adres skrzynki jako klucz mapy (hex z targetu).
String keyOf(List<int> target) =>
    target.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class StoredItem {
  final Uint8List value;
  final int seq;
  final Uint8List publicKey;
  final Uint8List signature;
  StoredItem(
      {required this.value,
      required this.seq,
      required this.publicKey,
      required this.signature});
}

/// Minimalny węzeł DHT w pamięci: odpowiada na `get` i `put` tyle, ile
/// potrzeba do sprawdzenia klienta i skrzynki. Nie weryfikuje podpisów
/// (prawdziwe węzły też przyjmą, co dostaną z ważnym żetonem), więc testy
/// mogą wstawić także rekord z zepsutym podpisem.
class FakeDhtNode {
  final FakeUdpMux mux;
  final Uint8List id;
  final stored = <String, StoredItem>{};
  final others = <(Uint8List, dynamic, int)>[];

  FakeDhtNode(this.mux, String name)
      : id = Uint8List.fromList(digest.sha1.convert(ascii.encode(name)).bytes) {
    mux.register(_onPacket);
  }

  bool _onPacket(UdpPacket packet) {
    final msg = tryBdecode(packet.data);
    if (msg is! Map) return false;
    if (bText(msg, 'y') != 'q') return false;
    final tid = bBytes(msg, 't');
    final method = bText(msg, 'q');
    final args = bDict(msg, 'a');
    if (tid == null || method == null || args == null) return true;

    final r = <String, Object>{'id': id};
    if (method == 'get') {
      r['token'] = ascii.encode('tok-${mux.port}');
      if (others.isNotEmpty) {
        final nodes = <int>[];
        for (final (oid, addr, port) in others) {
          nodes.addAll(oid);
          nodes.addAll(addr.rawAddress as List<int>);
          nodes.addAll([(port >> 8) & 0xFF, port & 0xFF]);
        }
        r['nodes'] = Uint8List.fromList(nodes);
      }
      final target = bBytes(args, 'target');
      if (target != null) {
        final rekord = stored[keyOf(target)];
        if (rekord != null) {
          r['v'] = BencodeRaw(rekord.value);
          r['seq'] = rekord.seq;
          r['k'] = rekord.publicKey;
          r['sig'] = rekord.signature;
        }
      }
    } else if (method == 'put') {
      final k = bBytes(args, 'k');
      final seq = bInt(args, 'seq');
      final sig = bBytes(args, 'sig');
      final salt = bBytes(args, 'salt');
      final raw = bBytes(args, rawValueKey) ?? bBytes(args, 'v');
      if (k != null && seq != null && sig != null && raw != null) {
        final target = dhtTarget(k, salt ?? const []);
        stored[keyOf(target)] =
            StoredItem(value: raw, seq: seq, publicKey: k, signature: sig);
      }
    } else {
      return true;
    }
    mux.send(bencode(<String, Object>{'t': tid, 'y': 'r', 'r': r}),
        packet.address, packet.port);
    return true;
  }
}
