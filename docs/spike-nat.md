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
   direction.

## Results

Addresses are left out on purpose.

### Single networks

| Network | NAT mapping | Ports kept | Global IPv6 | DHT write | DHT read |
|---|---|---|---|---|---|
| Home, Ethernet behind a mesh router | endpoint-independent | yes | no | 8 nodes in 13 to 18 s; 1 run of 3 reached no node | 15 to 18 s |
| Phone on LTE | | | | | |

The DHT times come from the first version of the lookup in `dht.dart`: six
rounds in lock step, each waiting for its slowest node up to the 3 s timeout.
When the first round toward the bootstrap nodes gets no answer, the whole
operation ends with no node.

### Pairs

| Side A | Side B | Punch | Time to two-way traffic | Silence survived, A to B |
|---|---|---|---|---|
| home | phone LTE | | | |
| phone LTE | home | | | |
| home | other Wi-Fi | | | |
| phone LTE | phone LTE | | | |
| café or hotel Wi-Fi | any | | | |

**Verdict:** to be written after the runs. If the home to LTE case succeeds in
most attempts, the next steps are the receiver punching toward the caller
(open point 1 in the issue) and intervals set from the silence column. If not,
the add-on stays off and this file is the record of why.
