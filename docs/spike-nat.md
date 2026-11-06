# Spike: UDP hole punching as a third transport

Step 1 of [issue #68](https://github.com/Mysttic/Chatt/issues/68), the same
shape as the Bluetooth spike ([spike-rfcomm.md](spike-rfcomm.md)): measure
first, decide after. The question that gates everything else is whether two
devices on different networks can reach each other directly, with no relay, in
the networks people actually use.

The gate from the issue: if the main case (a PC at home and a phone on mobile
data) does not connect in most attempts, the route is not worth shipping and
this file records why.

## What is already built

The protocol was written up front and is covered by tests over an in-memory
UDP network, because none of it needs real hardware to be exercised:

| File | Role | Test |
|---|---|---|
| `app/lib/network/udp_mux.dart` | one UDP socket shared by STUN, DHT and the link | (used throughout) |
| `app/lib/network/stun.dart` | STUN Binding client, NAT classification | `test/stun_test.dart` (RFC 5769 vector) |
| `app/lib/network/bencode.dart` | bencode codec | `test/bencode_test.dart` |
| `app/lib/network/dht.dart` | Mainline DHT, BEP 44 mutable get/put | `test/dht_test.dart` (RFC 8032 vectors + in-memory DHT) |
| `app/lib/network/rendezvous.dart` | per-pair sealed contact box | `test/rendezvous_test.dart` |
| `app/lib/network/secure_udp.dart` | KK handshake + replay-proof AES-GCM + ARQ | `test/secure_udp_test.dart` (loss, reorder, replay, attacker) |
| `app/lib/network/inet_link.dart`, `inet_transport.dart` | punch orchestration + `PeerTransport` | `test/inet_transport_test.dart` (full path over fake net) |

The Ed25519 signatures were cross-checked against OpenSSL. The bytes published
in BEP 44 predate RFC 8032 and do not match what today's libtorrent nodes
expect (see the note in `test/dht_test.dart`).

## How to measure

`app/tool/nat_spike.dart` runs on the PC under the plain Dart VM. On a phone it
installs as a separate app id, next to Chatt, and leaves Chatt's data alone:

```
cd app
dart run -DCHATT_NAT_MODE=stun tool/nat_spike.dart
flutter build apk --debug -t tool/nat_spike.dart -P chattAppIdSuffix=.natspike
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

On the phone the mode comes from `code_cache/chatt_nat.conf`, written with
`adb shell run-as`, so one build covers every mode (the header of the tool has
the commands). Output goes to `adb logcat -s flutter`.

1. `stun`, on each device by itself: the public address, whether the NAT keeps
   one mapping for every destination (punchable) or makes one per destination
   (symmetric, usually not punchable), whether UDP leaves the network at all,
   whether there is a global IPv6 address.
2. `dht`: write a record to the public DHT and read it back, with times. Some
   corporate and school networks block DHT.
3. `punch`, the real attempt: `CHATT_NAT_ROLE=a` on one device, `b` on the
   other, one socket per attempt for STUN and for the packets to the peer.
   Addresses go through the DHT contact box when both sides get the same
   `CHATT_NAT_PAIR` word, or through a file (and stdin on the PC) without it.
   After the first success side `a` stays silent for 15, 30, 60 and 120 s and
   checks whether its next packet still reaches `b`. That bounds the keepalive
   interval in the direction toward `b`; swapping the roles measures the other
   direction. With `CHATT_NAT_LISTEN=true` one side sends nothing until it
   hears from the other, which shows whether its NAT lets in a packet from a
   sender it never contacted.

## Results

Measured on 6 November 2026: a Windows PC on Ethernet behind a home mesh
router, and an Android 15 phone on LTE with Wi-Fi off, connected to the PC by
USB only for adb. Addresses are left out on purpose.

### Single networks

| Network | NAT mapping | Ports kept | Packet from a sender it never contacted | Global IPv6 |
|---|---|---|---|---|
| Home, PC | endpoint-independent | yes | dropped | no |
| Phone on LTE | endpoint-independent | no (carrier-grade NAT) | dropped | no |

"Dropped" comes from `CHATT_NAT_LISTEN=true`: the side that sent nothing
received nothing in 30 s, in both directions. On the PC this can be the router
or Windows Firewall; for Chatt the effect is the same.

DHT, three writes to the same box 20 s apart, each followed by a read:

| Network | Write | Read |
|---|---|---|
| Home, PC | 5.7 to 10.2 s, 7 or 8 nodes | 4.4 to 5.4 s, current record every time |
| Phone on LTE | 6.0 to 8.3 s, 7 or 8 nodes | about 5.2 s, current record every time |

The first version of the lookup took 13 to 22 s per write or read, and one
write in three reached no node. Both causes are fixed in `dht.dart` (see
below). Neither network blocks DHT.

### Pairs

| Side A | Side B | Punch | Two-way traffic | After silence, A's packet reaches B |
|---|---|---|---|---|
| home | phone LTE | 1 of 1, addresses by hand | 43 ms | after 60 s yes, after 120 s no |
| phone LTE | home | 1 of 1, addresses by hand | 55 ms | after 60 s yes, after 90 s no |
| home | phone LTE | 5 of 5, addresses through the DHT box | 45 to 90 ms after the later side started | (not run) |
| home, sends | phone LTE, only listens | 0 of 1 | | |
| phone LTE, sends | home, only listens | 0 of 1 | | |

Not measured: other carriers, LTE to LTE, a second home network, hotel or café
Wi-Fi, IPv6.

### Found along the way

- Windows accepts `send` to 0.0.0.0 and then reports error 1214 on the
  socket's stream, after which Dart closes the socket. DHT node lists carry
  such addresses. The spike died on it; the app would have lost the internet
  route's socket. `udp_mux.dart` now drops such packets and reopens a socket
  that closed on its own, on the same port.
- The bootstrap routers answer BEP 44 `get` with error 204. The lookup now
  asks them `find_node`, runs without rounds and remembers nodes between
  lookups.

**Verdict:** the main case connects: 7 of 7 attempts between the PC at home
and the phone on LTE. Both NATs drop packets from a peer they have not sent to,
so the receiver has to send toward the caller (open point 1 in the issue).
After 60 s of silence the path still worked both ways; after 90 s in one
direction and 120 s in the other it did not, so a kept link needs a keepalive
well under 60 s. The route is worth finishing.
