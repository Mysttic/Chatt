# Spike: Bluetooth Classic (RFCOMM) as a second transport

Step 1 of [issue #27](https://github.com/Mysttic/Chatt/issues/27). The issue
puts a measurement first and everything else after it, because the answer
decides whether the transport abstraction is worth building at all.

This file is the record of how the Bluetooth transport came about. The work
began as the measurement described in the first sections and grew, over the
third and fourth runs, into the transport itself, which now ships as the
Bluetooth add-on (Settings, Add-ons) and is described in
[architecture.md](architecture.md#transports). Everything up to "What step 1
deliberately left out" is the state of step 1.

Step 1 answered three questions and nothing else:

1. Does an RFCOMM link stand between an Android phone and a Windows PC under
   a service UUID of our own?
2. How many bytes per second go through it, and how long does a short message
   take to make the round trip?
3. Is there a Flutter plugin for this, or do we write platform channels?

At that point it was a harness. Nothing in the app called it, and it brought
no protocol change, no database migration and no test.

## What step 1 added

| File | Role |
|---|---|
| `app/tool/bt_spike.dart` | The harness. Its own `flutter run -t` entry point; never starts `AppServices`, never opens the database. |
| `app/android/.../ChattBluetooth.kt` | Android side of the `chatt/bluetooth` channel. `listenUsingRfcommWithServiceRecord` + `createRfcommSocketToServiceRecord`, sockets on a worker thread. |
| `app/windows/runner/chatt_bluetooth.cpp` | Windows side. Win32 Winsock `AF_BTH`/`BTHPROTO_RFCOMM`, SDP record via `WSASetServiceW`. |

The measurement runs in native code. Only byte counts cross the method
channel, so the numbers measure the radio itself.

Both sides walk the same agreed sequence, so the stream needs no framing:
for each chunk size, the client sends N bytes and the server reads exactly N,
then the server sends N and the client reads exactly N. The payload is a
deterministic pattern, so the receiving side verifies itself and prints an
FNV-1a hash for a second pair of eyes.

## Running it

Pair the two devices in system settings first. Bluetooth pairing gives us
nothing security-wise (the issue is explicit: Bluetooth is a cable, trust
comes from the handshake), but Windows needs a bond before it will accept an
authenticated RFCOMM link.

```
cd app
flutter run -d windows -t tool/bt_spike.dart --dart-define=CHATT_BT_ROLE=serwer
```

Note the radio address it prints, then on the phone:

```
cd app
flutter run -d <device-id> -t tool/bt_spike.dart ^
  --dart-define=CHATT_BT_ROLE=klient ^
  --dart-define=CHATT_BT_ADDR=AA:BB:CC:DD:EE:FF
```

`CHATT_BT_ROLE=status` prints the radio, the permission and the paired list
and stops there. Other knobs are documented at the top of `bt_spike.dart`.

The Windows window does not repaint while a channel call is in flight: the
call blocks the platform thread on purpose, because completing a method
result from another thread is a problem the real transport has to solve and
a measurement does not.

## Results

It works. An RFCOMM link stands between the two devices under our own service
UUID, both directions carry a megabyte, and the byte pattern arrives intact
every time (both sides print FNV-1a `0xc2dc9dc5` for all eight phases).

PC: desktop, Windows 11, Microsoft stack, PC listening
Phone: moto g84 5G, Android 15 (API 35), phone connecting
Distance: same desk
Payload: 1 MiB per phase, kB = 1000 B, timed by the receiving side
Addresses: the radio addresses below are placeholders

| Chunk | Direction | ms | kB/s |
|---|---|---|---|
| 990 | phone → PC | 6970 | 150 |
| 990 | PC → phone | 11566 | 91 |
| 1024 | phone → PC | 6804 | 154 |
| 1024 | PC → phone | 11338 | 92 |
| 4096 | phone → PC | 9960 | 105 |
| 4096 | PC → phone | 9401 | 112 |
| 16384 | phone → PC | 9675 | 108 |
| 16384 | PC → phone | 8337 | 126 |

Round trip, 200 B × 20: **24.6 ms** per round trip.

Reading of it:

- **~90 to 155 kB/s**, which lands where the issue guessed. A megabyte takes
  7 to 12 seconds. Call it 100 kB/s when sizing anything.
- That is roughly **50 to 100× slower than Wi-Fi**. The issue is right that
  this has to be shown in the interface.
- **No 1021 → 1024 byte cliff.** Both chunk sizes measure the same within
  noise; the modern stacks apparently do their own batching.
- **Chunk size matters, and the two directions disagree about how.** Phone →
  PC is fastest with small writes (154 kB/s at 1024, 108 at 16384); PC →
  phone is the opposite (92 at 1024, 126 at 16384). Whoever writes the
  transport should not pick one chunk size for both directions on a hunch.
- **24.6 ms per round trip for a short message.** That is the number that
  matters for Chatt, because the dominant traffic is short text, and it is
  entirely usable: a message over Bluetooth will feel no different from one
  over Wi-Fi. Bulk file transfer is where the user will notice.
- The link came up in about a second, with no system prompt, because the
  devices were already bonded.

### Second run: no network, no pairing

The same two devices with both conditions removed at once. The phone had
Wi-Fi off and no usable route (`ping 8.8.8.8` → `Network is unreachable`,
checked before and after the run), so the two machines shared no network of
any kind and Chatt's IP transport could not have carried a byte between them.
Neither device had the other in its paired list. Both sides ran with
`CHATT_BT_SECURE=false`: `listenUsingInsecureRfcommWithServiceRecord` on
Android, a listening socket with no `SO_BTH_AUTHENTICATE`/`SO_BTH_ENCRYPT` on
Windows.

| Chunk | Direction | ms | kB/s |
|---|---|---|---|
| 990 | phone → PC | 6345 | 165 |
| 990 | PC → phone | 9005 | 116 |
| 1024 | phone → PC | 6427 | 163 |
| 1024 | PC → phone | 8487 | 124 |
| 4096 | phone → PC | 6691 | 157 |
| 4096 | PC → phone | 7572 | 138 |
| 16384 | phone → PC | 6655 | 158 |
| 16384 | PC → phone | 6956 | 151 |

Round trip, 200 B × 20: **22.2 ms**.

- **System pairing is not required.** The link came up with no bond, no system
  dialog and no interaction on either device. That settles question 5 in the
  issue: "just works" is available, and the whole of the trust can stay where
  the issue wants it, in the code/QR confirmation.
- **No shared network is required.** Obvious from the protocol, now shown on
  hardware.
- **Unbonded measured faster** (124 to 165 kB/s against
  91 to 154, round trip 22.2 ms against 24.6). Plausibly the link-layer
  encryption and authentication that a bond brings, which Chatt does not need
  because it encrypts above the transport anyway. One run per configuration,
  so read it as a direction.
- **Chunk size stopped mattering in this run.** Every size landed within
  spitting distance of every other. Whatever made 16384 slow phone → PC in the
  first run was not the chunk size itself.

Not measured yet: screen off, distance and walls, behaviour during a
Bluetooth scan, discovery without a known address, and anything on a second
PC.

## Plugin or platform channels

Verdict: **platform channels**, written here. Recorded before measuring, to
be revisited if the numbers say otherwise.

`flutter_classic_bluetooth` (1.4.1) is the only package on pub.dev that
exposes an RFCOMM *server* socket on both Android and Windows, and its native
code is the right shape. Four things ruled it out:

- Its Windows server never sets `SO_BTH_AUTHENTICATE`/`SO_BTH_ENCRYPT` on the
  listening socket, so `startServer(secure: true)` is a no-op there. The
  client path in the same package does set it.
- Its manifest merges `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`,
  `ACCESS_FINE_LOCATION` and `<uses-feature android.hardware.bluetooth
  required="true"/>` into Chatt, which widens the permission surface and
  hides the app from devices with no radio.
- It hands Dart a byte `Stream`/`Sink`. A real transport has to keep the byte
  pump native to preserve `PeerClient.sendFile`'s back-pressure, resume and
  cancel contract.
- The repo has no plugins for platform work: five hand-written channels and
  one pattern. At step 1, ~150 lines of Kotlin and ~350 lines of C++
  reproduced what the package does, under the runner's existing C++17 /
  `/W4 /WX` settings.

Windows uses Win32 `AF_BTH`. WinRT `RfcommServiceProvider` would force C++20 and exceptions, which the runner has switched off, and its
background listener (`RfcommConnectionTrigger`) needs package identity that
an unpackaged `.exe` does not have.

## What step 1 deliberately left out

The harness had these gaps. The third and fourth runs below close most of
them.

- **Discovery.** Devices are paired by hand in system settings. The real
  transport replaces the UDP broadcast with an SDP record.
- **Pairing UX.** Connecting to an unbonded peer pops a system dialog on both
  sides mid-connect; the Windows one is a toast that is easy to miss.
- **One connection at a time.** RFCOMM allows a single client per UUID
  channel, and the harness closes the listener after the first accept.
- **Back-pressure.** Nothing in the harness plugged into `PeerClient` or
  `ChattServer`.
- **Background listening.** The Android socket lived in the harness process,
  outside `ChattService`. A listener held open under Android 15's tightened
  `connectedDevice` foreground-service rules is untested and is the largest
  unknown for the next step.
- **Reconnect and resume.** A dropped link ends the run.
- **Timeouts on Android reads.** `BluetoothSocket` streams have none, so a
  peer that dies mid-transfer hangs the worker thread until the app is killed.

## Third run: the real thing

The transport itself: the full Chatt stack on both sides, with the Noise-KK
handshake, sealed envelopes and an encrypted file, all over RFCOMM. Phone with Wi-Fi off, neither device paired with the
other. Run with `tool/bt_rozmowa_check.dart`.

| What | Result |
|---|---|
| Message | delivered, 1315 ms end to end |
| File, 1 MiB | delivered, 7328 ms, 143 kB/s |
| Protocol recorded | Bluetooth, on both the sender and the receiver |

The file number matches the raw measurement above, so framing, multiplexing
and encryption cost nothing worth naming. The message number is dominated by
the handshake, which is two round trips plus key agreement.

Two bugs that only hardware could have found, both now fixed:

- **Starting the transport twice built two of them.** The settings watcher and
  the explicit call raced, each transport polled the native side separately,
  and they took turns stealing each other's ready links. Whichever lost then
  waited out the full 25 second connect timeout. `AppServices.startBluetooth`
  now hands back the attempt already in flight.
- **A device with no network at all threw from discovery.** `RawDatagramSocket`
  reports "network is unreachable" as an error on its stream, so it
  escaped as an unhandled error and took the send down with it. Both discovery
  sockets now have an `onError`, and `_relocate` no longer scans when the
  Wi-Fi transport is off.

## Fourth run: finding the other device

The third run went straight to an address. This one starts from the Nearby
screen on the phone: release builds on both sides, the phone with Wi-Fi off,
nothing paired, every step tapped through the interface.

| What | Result |
|---|---|
| Phone searches, finds the PC | on the list after about 25 s; the whole search ends at 60 s |
| Message, phone to PC and back | delivered both ways |
| Image, 323 KB, phone to PC | delivered, preview on the PC, SHA-256 identical |
| File, 1 MiB, PC to phone | delivered, SHA-256 identical |
| Protocol shown | "over Bluetooth" in both headers and on both lists |

What stood between the phone and a working search, in the order it came up:

- **Location services.** Android 12+ hands out no discovery results while they
  are off, `neverForLocation` notwithstanding. The status now carries
  `locationOn`, and the Nearby screen says so with a button to the system
  setting. Adding by radio address works either way.
- **The receiver for discovery broadcasts has to be exported.** Registered as
  not exported on Android 13+, it got the start and the end of discovery and
  not one `ACTION_FOUND`, so the search saw only bonded devices.
  `ACTION_FOUND` is a protected broadcast only the system can send, so
  `RECEIVER_EXPORTED` opens nothing to other apps.
- **Asking during discovery cut discovery short.** A connect cancels the
  inquiry on both platforms, so probing the first device ended the search.
  The search now collects for 16 s and asks afterwards, each phase with its
  own budget.
- **The order of asking.** Every device that is not Chatt costs time, and an
  address seen only over BLE costs the most: RFCOMM to it waits out the page
  timeout (5.12 s) and never connects. The PC was in the air twice, as
  `12:34:56:78:9A:BC` and as the BLE address `6E:11:22:33:44:55` under the
  same name. BLE-only addresses are now skipped, computers and phones go
  first by Class of Device, and each device that answers is on the list at
  once. The PC went from about 65 s, at the very end, to about 25 s.
- **An abandoned probe held the radio.** A probe that ran out of budget left
  its connect pending on the native side. Closing a link now also closes a
  connect still in flight, on Android and on Windows, and a failed probe
  drops its link at once.

One false alarm worth recording: a 256 KiB file sent right after a search
"failed" after 120 s at 2 kB/s. The radio was fine. The receiving PC ran the
real app, which asked about the file; nobody answered, and the question
expired after its two minutes. The harness receives without asking and the
app asks every time, so a file test against the app needs somebody to tap
Accept.

## Fifth run: the add-on on hardware

14 October, after the transport moved behind the Bluetooth add-on. A Pixel 9
Pro on Android 17, upgraded in place from 0.8.1 with its data, against the
Windows PC from the earlier runs. Location services on, the local network
switch off on both sides, so everything went over the radio.

- With the add-on off, the phone's Bluetooth socket log had no entry from
  Chatt. Switching it on brought up the "Nearby devices" question and then
  the RFCOMM listener named `Chatt`.
- The first search tripped over a leftover system pairing: the phone still
  had the PC (`…9A:BC`) on its bonded list, the PC no longer had the phone.
  The link came up and Android reported `bondLossCallback:
  BREDR_AUTH_FAILURE`, showed its own "pair again" dialog and dropped the
  link. Once the user removed the PC from the phone's Bluetooth settings, the
  next search found `Chatt PC` at `12:34:56:78:9A:BC` after about 25 seconds,
  with no dialog, and the whole search ended at 86 seconds.
- A message each way, 1 MiB from the PC to the phone and a 323 KB image from
  the phone to the PC, both with the consent card and a matching SHA-256. The
  phone's socket log showed RFCOMM connections to `…9a:bc` under Chatt's
  service UUID.
- With the add-on then switched off on the phone, a message to the PC (known
  only by its radio address, so with no IP address on record) was delivered
  over Wi-Fi after the UDP search found the PC by its guid, and the PC's
  conversation header switched to "over the network".

## Two things the run itself taught us

**A bonded peer can be filed under an address that is not its radio's.**
While the two were paired, the phone's bonded list showed the PC as
`7A:66:77:88:99:AA` and only that address connected, even though
`BluetoothGetRadioInfo` reported `12:34:56:78:9A:BC` and enumerating all
radios found exactly one. Unpairing resolved it: with no bond, the phone
connects to `12:34:56:78:9A:BC` and nothing else. So the bond was made over
dual-mode LE, the phone stored the LE address, and its stack was resolving
that back to the BR/EDR transport through the bond record. The rule that
falls out is the one Chatt already applies to IP: **a Bluetooth route is
only a hint.** It has to be learned from the bond or from the peer
and allowed to change, with the crypto GUID staying the only key.

**`cancelDiscovery()` needs `BLUETOOTH_SCAN` on Android 12+.** The first run
died on `SecurityException: Need android.permission.BLUETOOTH_SCAN ...
AdapterService cancelDiscovery`. The spike kept the permission out and
swallowed the refusal: it never started a scan of its own, so there was
nothing of ours to cancel. A real transport that does its own SDP discovery
will have to ask for `BLUETOOTH_SCAN` and pay the extra permission prompt.

## Notes worth keeping

- Android has not let an app read its own Bluetooth address since Android 6:
  `BluetoothAdapter.getAddress()` returns `02:00:00:00:00:00` for everyone.
  The phone's address has to come from the other side's paired list.
- Bluetooth Classic does not randomise addresses. Address randomisation is a
  BLE mechanism; BR/EDR uses the static public BD_ADDR.
- A missing `BLUETOOTH_CONNECT` grant surfaces as a `SecurityException`
  that names `getAddress`, even when `listenUsingRfcommWithServiceRecord` is
  the call that failed.
- Windows is only inquiry-discoverable while the "Add a device" dialog is
  open, unless something asks for discoverability explicitly.
- Running a Bluetooth scan during a transfer starves the link. The harness
  calls `cancelDiscovery()` before connecting for this reason.
