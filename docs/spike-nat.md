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
4. `link`: the app's own `InetLinkManager` and `InternetTransport` with
   throwaway identities derived from `CHATT_NAT_PAIR`, without Chatt's
   database. Side `b` only waits, as an idle app does; side `a` calls from a
   cold start (a new socket each time), times the answer and sends a block of
   bytes once. On the PC this mode needs the Windows build of the tool
   (`flutter build windows --debug -t tool/nat_spike.dart`), with the settings
   in environment variables.

## Results

Measured on 6 November 2026: a Windows PC on Ethernet behind a home mesh
router, and an Android 15 phone on LTE with Wi-Fi off, connected to the PC by
USB only for adb. Addresses are left out on purpose.

### Single networks

| Network | NAT mapping | Ports kept | Packet from a sender it never contacted | Global IPv6 |
|---|---|---|---|---|
| Home, PC | endpoint-independent | yes | dropped | no |
| Phone on LTE | endpoint-independent | no (carrier-grade NAT) | dropped | no |

A traceroute from the PC shows three NAT layers on the home side: the mesh
router, the provider's modem and the provider's own carrier-grade NAT
(`100.64.0.1`). Both ends of the pair sit behind a carrier-grade NAT, and the
punch still works because every layer maps endpoint-independently.

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

### The app's link manager over real networks (`link`)

Side `b` reads boxes every 60 s, as the app does; every call starts cold.

| Caller | Receiver, only waiting | Answered | From cold start to answer | 256 KB transfer |
|---|---|---|---|---|
| PC at home | phone on LTE | 3 of 3 | 60.0, 66.9, 72.6 s | 0.5 s, about 520 kB/s |
| phone on LTE | PC at home | 3 of 3 | 60.3, 64.7, 68.5 s | 0.9 s, about 290 kB/s |

Each answer took one box read on the receiver's side: it found the "calling"
record 43 to 62 s after the caller wrote it, knocked, and the link came up 1.1
to 1.5 s later. The time to answer is therefore set by the read interval.

### Round trip on the punched path

`CHATT_NAT_PINGS=100`: side `a` sends 100 packets 100 ms apart over the
punched path and times each echo. The phone lay next to the PC both times.

| Path | Min | Median | Mean | 90% under | Max | Lost |
|---|---|---|---|---|---|---|
| PC at home to phone on LTE, punched | 34.0 ms | 36.9 ms | 40.0 ms | 50.8 ms | 69.5 ms | 0 of 100 |
| PC to phone in one Wi-Fi network (`CHATT_NAT_LAN=true`) | 4.9 ms | 11.4 ms | 17.8 ms | 25.4 ms | 112.3 ms | 0 of 100 |

Over LTE the packets leave the home network, cross the home provider's network
to a Polish internet exchange, where the mobile carrier takes them, and come
back over the radio; the traceroute reaches the exchange in about 15 ms and the
carrier's network does not answer it. The Wi-Fi spread comes from the phone's
power saving between packets. A round trip says only how far the path could
reach: light in fiber covers about 200 km per millisecond, so 34 ms bounds the
path at roughly 3,400 km each way, and the same numbers would come from a phone
in another city.

### Files over the punched path

Test copies of the app on both devices, the phone on LTE, two photos each way;
times from the app log on the PC (sender's log for PC to phone, receiver's log
for phone to PC):

| Path | 2.5 MB | 7.7 MB |
|---|---|---|
| PC at home to phone on LTE | 15.0 s (170 kB/s) | 45.4 s (170 kB/s) |
| Phone on LTE to PC at home | 6.9 s (370 kB/s) | 16.1 s (480 kB/s) |
| One Wi-Fi network (TCP, no internet route) | 0.5 s and 0.3 s | |

Those rates sat far below what the path carries, so the link was measured
without hardware, over the in-memory network of the tests with a 20 ms delay
each way, 1 MB per run (`SecureUdpPipe` alone, as it stood on 6 November):

| Path in the test | Before | Segments sent for 1,024 | After |
|---|---|---|---|
| No delay | 2,362 kB/s | 1,024 | 2,503 kB/s |
| 20 ms each way | 1,425 kB/s | 1,024 | 1,415 kB/s |
| 20 ms, 1% of packets lost | 434 kB/s | 1,434 | 779 kB/s, 1,036 sent |
| 20 ms, 4 Mbit/s bottleneck, 64 KB queue | 476 kB/s | 1,024 | 475 kB/s |
| 20 ms, 4 Mbit/s bottleneck, 32 KB queue | 274 kB/s | 1,600 | 386 kB/s, 1,289 sent |

Two causes came out of it, plus one on Windows:

- **Every lost packet stopped the link for an RTO** (at least 200 ms), and then
  everything still unacknowledged went out again. With 1% loss the sender
  needed 410 extra sends for 1,024 segments. The receiver did report the gap (SACK bits), but the
  sender used them only to drop delivered segments, and only 32 segments
  behind the gap fit in the map while the window is 64.
- **The window counted unacknowledged segments**, so with a gap it kept sliding
  past the end of the SACK map, and the segments beyond it had to be resent.
- **Windows drops UDP packets sent in one burst.** `RawDatagramSocket.send`
  returns 0 when the system's send buffer is full, and the packet never
  leaves. Two processes on one PC, 20 bursts of 64 packets of 1,100 bytes,
  50 ms apart: `send` returned 0 for 1,017 of the 1,280 packets and 263
  arrived. With a queue that waits for the socket's write event, all 1,280
  arrived. The link's own packets come out spaced by encryption (about 60 µs
  each on the PC), and over loopback the pipe ran at 2 MB/s both before and
  after, so on Ethernet this probably did not cost much; DHT queries and the
  knock packets do go out in bursts.

What changed: the SACK map has 64 bits and covers the whole window; the window
counts sequence numbers from the oldest unacknowledged one; a segment is resent
at once when three transmissions sent after it have been delivered, which also
catches a resent segment that got lost again; `SocketUdpMux` queues packets the
system refused and sends them in order on the socket's write event; the AES key
is expanded once per link. The sender's counters (segments sent, resent at
once, resent after an RTO) show in the spike's `link` mode after each transfer.

Not changed: there is no congestion window. A queue smaller than the window
still loses part of every window (the 32 KB row), and halving the window on
every loss would cost the most on random loss: Reno's formula gives about
300 kB/s at 1% loss and a 40 ms round trip, where the link now does 779 kB/s.
The photo transfers have not been measured again on hardware after the
change.

### Found along the way

- Windows accepts `send` to 0.0.0.0 and then reports error 1214 on the
  socket's stream, after which Dart closes the socket. DHT node lists carry
  such addresses. The spike died on it; the app would have lost the internet
  route's socket. `udp_mux.dart` now drops such packets and reopens a socket
  that closed on its own, on the same port.
- The bootstrap routers answer BEP 44 `get` with error 204. The lookup now
  asks them `find_node`, runs without rounds and remembers nodes between
  lookups.
- The first `link` runs failed for two reasons, both fixed: an empty box at
  start doubled the receiver's read interval past the caller's 90 s, and the
  routine address refresh could overwrite the "calling" record written in the
  same second (BEP 44 `seq` was in seconds, now in milliseconds).

**Verdict:** the main case connects: 7 of 7 attempts between the PC at home
and the phone on LTE. Both NATs drop packets from a peer they have not sent to,
so the receiver has to send toward the caller (open point 1 in the issue).
After 60 s of silence the path still worked both ways; after 90 s in one
direction and 120 s in the other it did not, so a kept link needs a keepalive
well under 60 s (now one after 25 s of silence). With the receiver knocking,
the app's own link manager connected 6 of 6 calls, three each way. The route
is worth finishing.
