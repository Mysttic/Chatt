# Spike: UDP hole punching as a third transport

Step 1 of [issue #68](https://github.com/Mysttic/Chatt/issues/68), the same
shape as the Bluetooth spike ([spike-rfcomm.md](spike-rfcomm.md)): measure
first, decide after. The question that gates everything else is whether two
devices on different networks can reach each other directly, with no relay, in
the networks people actually use.

The issue puts it bluntly: if the main case — a PC at home on Wi-Fi and a phone
on mobile data — does not connect in most attempts, the road is not worth
shipping and this file is where it is retired.

## What is already built

Unlike the Bluetooth spike, the protocol was written up front and is covered by
tests over an in-memory UDP network, because none of it needs real hardware to
be exercised:

| File | Role | Test |
|---|---|---|
| `app/lib/network/udp_mux.dart` | one UDP socket shared by STUN, DHT and the link | (used throughout) |
| `app/lib/network/stun.dart` | STUN Binding client, NAT classification | `test/stun_test.dart` (RFC 5769 vector) |
| `app/lib/network/bencode.dart` | bencode codec | `test/bencode_test.dart` |
| `app/lib/network/dht.dart` | Mainline DHT, BEP 44 mutable get/put | `test/dht_test.dart` (RFC 8032 vectors + in-memory DHT) |
| `app/lib/network/rendezvous.dart` | per-pair sealed contact box | `test/rendezvous_test.dart` |
| `app/lib/network/secure_udp.dart` | KK handshake + replay-proof AES-GCM + ARQ | `test/secure_udp_test.dart` (loss, reorder, replay, attacker) |
| `app/lib/network/inet_link.dart`, `inet_transport.dart` | punch orchestration + `PeerTransport` | `test/inet_transport_test.dart` (full path over fake net) |

The Ed25519 signatures were cross-checked against OpenSSL, not just the BEP 44
examples (whose published bytes predate RFC 8032 and do not match what today's
libtorrent nodes expect — see the note in `test/dht_test.dart`).

## What step 1 measures on hardware

`app/tool/nat_spike.dart` (`flutter run -t tool/nat_spike.dart`), three modes:

1. `stun` — run on each device by itself. Reports the public address, whether
   the NAT is endpoint-independent (punchable) or symmetric (not), whether UDP
   leaves the network at all, and whether there is a global IPv6 address.
2. `punch` — the real attempt. Each side prints its STUN address; paste the
   other side's into `CHATT_NAT_PEER` and start both within a few seconds.
   Reports whether and after how long packets started flowing, then holds
   silent for 15/30/60/120 s to find when the NAT closes the pinhole — that is
   the keepalive interval.
3. `dht` — whether a record can be written to and read from the public DHT from
   this network (some corporate and school networks block DHT).

## Results

Fill this in from real runs. Leave the verdict explicit.

| Side A network | Side B network | STUN A | STUN B | Punch? | Time to first packet | Pinhole closes after |
|---|---|---|---|---|---|---|
| _home Wi-Fi_ | _phone LTE_ | | | | | |
| _home Wi-Fi_ | _other Wi-Fi_ | | | | | |
| _phone LTE_ | _phone LTE_ | | | | | |
| _café / hotel Wi-Fi_ | _any_ | | | | | |

DHT reachability: _home Wi-Fi_ … , _LTE_ … , _corporate Wi-Fi_ … .

**Verdict:** _to be written after the runs._ If the home-Wi-Fi ↔ LTE case
succeeds in most attempts, step 2 (wiring the box publish/poll into a running
app and measuring first-message latency after a network change) is worth doing;
if not, the add-on stays off and this measurement is the record of why.
