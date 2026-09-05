# Tests

The split is simple: **94 `flutter test` tests** check everything that can be
checked without hardware, and separate scenarios in `app/tool/` drive a live
app on a device. The things neither of them can check are listed at the end.

## Running them

```
cd app
%USERPROFILE%\dev\flutter\bin\flutter.bat test
%USERPROFILE%\dev\flutter\bin\flutter.bat analyze
```

On-device scenarios (they need `adb` and the app installed):

```
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
%USERPROFILE%\dev\flutter\bin\flutter.bat test tool/android_e2e_test.dart
%USERPROFILE%\dev\flutter\bin\flutter.bat test tool/wifi_discovery_check.dart
%USERPROFILE%\dev\flutter\bin\flutter.bat test tool/product_shots.dart
%USERPROFILE%\dev\flutter\bin\flutter.bat test tool/windows_shots.dart
```

English screenshots: the same with `set CHATT_SHOTS_LANG=en`.

Variables: `ADB` (the path to adb), `CHATT_DEVICE` (an identifier from `adb
devices`, `emulator-5554` by default).

## How communication is tested without two devices

The key trick: `AppServices.start()` builds **a complete application stack** (an
in-memory database, an HTTP server on a random port, a client, discovery). A
test brings up two of them in one process and makes them talk to each other
over a real TCP socket, with no network fakes anywhere. That is why the tests
also catch things that would slip past a mock: request ordering, response
codes, behaviour when a connection breaks.

For the harder scenarios the tests put their own proxy between the instances:
once as a wiretap (checking that the content really does not travel in
plaintext), once as a link that dies after N bytes (resuming a transfer).

## What is covered

### Database (`test/data_test.dart`, 7 tests)
- `ensureSettings` creates the row once and keeps the GUID
- `upsertPeer` updates the address by GUID, and an empty host does not
  overwrite the last good one
- messages: dedupe by `messageGuid` and counting unread ones
- message status: pending, failed, delivered
- deleting a peer takes its conversation and messages with it
- deleting one message leaves the rest of the conversation and the peer alone
- the sweep only removes dead entries with no history

### Discovery (`test/discovery_test.dart`, 4 tests)
- a scan finds the second instance and teaches it about the scanner
- from a known device we accept only a signed answer (an impersonation drops
  out of the scan results)
- a peer whose address changed is found again by GUID
- the responder reports whether it is actually listening, because a bind that
  fails means a device nobody can find with a scan

### Messages (`test/messaging_e2e_test.dart`, 5 tests)
- pairing by address, exchanging messages both ways, dedupe
- recipient offline: failed, and after it comes back a retry delivers
- adding by hand records the address the device **answered from**
- we do not talk to ourselves (a loop onto our own address)
- the server rejects garbage without falling over

### Files (`test/file_transfer_test.dart`, 9 tests)
- several files at once go one after another, each with its own consent
  question (the same road as dragging them onto the window)
- a directory passed together with the files is skipped without a crash
- a 3 MB file arrives whole, byte for byte
- recipient offline: failed, and a retry after it returns delivers
- the recipient refuses: not one byte flows, and after agreeing a retry
  delivers
- corruption in flight (a link that flips a byte): the file is rejected and
  nothing lands in the received directory
- a partial transfer from a previous session is not appended to; the transfer
  starts from zero and comes together byte for byte
- the sender resumes after the network drops: the second attempt sends only the
  remainder
- broken metadata gives a 400 and the server stays alive

### QR code (`test/pair_link_test.dart`, 3 tests)
- a code makes the whole round trip
- garbage and other people's codes are dropped (a camera sees plenty of codes
  that are not ours)
- base64url without padding reads too

### Pairing (`test/pairing_test.dart`, 8 tests)
- both sides see **the same** code, and only agreement from both verifies
- "they do not match" on one side breaks the pairing on both
- a key that disagrees with the commitment is rejected (that is what an
  attacker picking keys to fit a code would look like)
- confirming a known device again is clearly marked
- a first confirmation does not scare anyone with a warning
- scanning a code confirms immediately on the scanner's side and raises the
  "was that you scanning" question on the other
- a code carrying someone else's key at someone else's address is rejected
- pairing with an unreachable device returns null

### Identity and sessions (`test/identity_crypto_test.dart`, 8 tests)
- the identifier is derived from the public key and is reproducible
- an identity survives writing and reading the private key
- both sides of the handshake compute the same session key
- **different ephemeral keys give a different session key**, which is forward
  secrecy as an assertion
- a swapped static key breaks the agreement
- the file key hangs off the session key and the message guid
- a device broadcasts its key, and its identifier follows from it

### Encryption (`test/encryption_test.dart`, 4 tests)
- paired: message content does not travel in plaintext, checked with a wiretap
  on the link
- **unpaired: the content does not travel in plaintext either**
- paired: a file travels encrypted and comes together byte for byte
- paired: resuming an encrypted file sends only the remainder

### Search, backgrounds and thumbnails (`test/search_test.dart`, 12 tests)
- search ignores case, and an empty string matches everything
- a file is searched by name, because that is what the bubble shows
- the conversation list filters by peer name and last message, and a
  conversation with no messages at all does not break filtering
- only images by extension get a thumbnail, `photo.png.exe` does not
- a background number outside the list falls back to "no background" (the
  database may hold a number from a newer version)
- every background set has colours for the light and the dark theme

### The database on disk (`test/encrypted_db_test.dart`, 9 tests)
- the build really does have SQLite3MultipleCiphers (`PRAGMA cipher` returns
  something) and `PRAGMA key` encrypts: a string from the database is not
  visible in the file's bytes
- an encrypted database cannot be opened without the password
- a plaintext database from an older version is rewritten with its history:
  messages, peers and **identity confirmation** survive, and a second start has
  nothing left to rewrite
- the database key: with no system keystore it is written in the clear but does
  not change between starts; with a keystore something other than the password
  lands on disk; a keystore that stopped unwrapping the key is an error
- "clear history" leaves devices together with their confirmation
- the age limit deletes only messages older than itself, and turned off
  (0 days) it deletes nothing

### Per-peer settings (`test/peer_prefs_test.dart`, 10 tests)
- a name of your own covers the broadcast one without deleting it, and it
  survives the peer renaming itself; an empty string or a space brings the
  broadcast name back
- taking files without asking cannot be turned on for a peer whose identity is
  unconfirmed, and removing the confirmation turns it off. The database guards
  that, because it is the boundary of the user's consent
- three live transfers between two instances: a confirmed peer with consent
  gets the file through with no question asked; the same peer without consent
  still raises one; and the flag alone, with the shield gone, raises one too

### Migration ahead of its own version (`test/migration_test.dart`, 1 test)
- a database with the current column layout and `user_version` rolled back to
  8, which is what a process killed between `ALTER TABLE` and the version
  write leaves behind; it has to open, keep its rows, and not throw
  `duplicate column name`

### Presence on the list (`test/presence_test.dart`, 1 test)
- two live instances and one entry pointing at an address where nothing
  listens; the provider that feeds the green dot answers `true` for the first
  and `false` for the second

### The version number (`test/version_test.dart`, 1 test)
- the constant in `lib/core/version.dart` agrees with `pubspec.yaml` and
  `VERSION.md`, which catches a file left behind when the number was raised

### Messages in the corner (`test/toasts_test.dart`, 4 tests)
- the queue keeps its order, a message goes away by its id, and the oldest
  makes room once there are more than three
- a card counts itself down and disappears, and a tap closes it at once

The file is separate on purpose: one `testWidgets` anywhere in a file installs
`TestWidgetsFlutterBinding`, which replaces `HttpClient` with a fake answering
400 for **the whole** suite. Next door, in `peer_prefs_test.dart`, two
instances talk to each other over a real socket.

### An attacker on the wire (`test/security_test.dart`, 8 tests)
- a message identifier carrying a path (`../../../../evil`, `..\..\evil`,
  `/etc/chatt`) is rejected in a file announcement, in a message and in the
  transfer headers; an ordinary UUID passes
- the path of a transfer part, of its description and of the target file stays
  inside the received directory **regardless** of what the sender sends
  (checked with `p.isWithin`, which returns false for `..`)
- two different identifiers do not collapse into one file
- an eight megabyte request does not take the server down, and `/info` answers
  afterwards

### Resistance to a security downgrade (`test/downgrade_test.dart`, 3 tests)
The attacker knows a peer's identifier and has no private key for it:
- a plaintext message impersonating a known peer is rejected
- a plaintext file announcement from a known peer is rejected
- a plaintext transfer will not replace a file announced under encryption

The protocol itself defends against all three, because there is no plaintext in
it. The tests stay as a guard: a fallback unencrypted mode would turn them red.

## Scenarios on live hardware

### `tool/android_e2e_test.dart`
A host instance on the PC talks to the **app installed on a device** through
adb tunnels (the emulator sits behind NAT, so an ordinary network is out):

```
adb forward tcp:47781 tcp:47780    host -> the app on the device
adb reverse tcp:47790 tcp:47790    device -> the host instance
```

Four tests: `/info` with a message and its confirmation; a file with the
acceptance tapped on screen and the checksum verified; saving an image on the
device, checked with `ls /sdcard/Pictures/Chatt`; a refusal ending in a "not
delivered" status. The test restarts the app at the start, taps buttons found
by label in the accessibility tree and sends files with fresh content on every
run.

`CHATT_PROXY_PORT` moves the `adb forward` port when the default one is taken,
for example by an ordinary Chatt running on the same desktop. The tunnel is
asserted: without it the test would talk to whatever else holds the port.

### `tool/wifi_discovery_check.dart`
Broadcasts a discovery query on a real network and prints who answered. This
one cannot be checked on an emulator.

### `tool/product_shots.dart`
Sets up a demonstration conversation and takes screenshots into
`docs/screenshots/produkt/`. Afterwards it wipes the app data so no demo is
left on the device.

### `tool/windows_shots.dart`
Screenshots of the Windows window **without clicking around the desktop**: the
app renders in the `flutter_test` harness at 1600x900, with its own in-memory
stack and two peers in the same process, and the image comes straight out of
the engine (`RepaintBoundary.toImage`). There are no private conversations in
the screenshots, and the result is the same on every machine.
`CHATT_SHOTS_LANG=en` gives the English version. One trap: the harness replaces
`HttpClient` with a fake answering 400, so the script restores the real one
(`HttpOverrides.global = null`).

### `tool/store_assets.py`
Draws the README banner (`docs/promo.png`), the only graphic in the repository
that comes out of code.

### `tool/zrzut_okna.ps1`
A screenshot of **the app window alone** on Windows (not the whole desktop),
with a size set for it. For looking at the layout in a wide window without
guessing:

```
powershell -ExecutionPolicy Bypass -File tool/zrzut_okna.ps1 -Plik okno.png -Szerokosc 1400 -Wysokosc 900
```

### `tool/podglad_bazy.dart`
Says how much of what is in the database, and whether the file can be opened at
all without a password. On an encrypted database it answers "cannot be read".

## What the tests will not check

Deliberate holes in coverage, to be checked by hand at release time:

- **Router behaviour**: client isolation on a guest network, broadcasts between
  the 2.4 and 5 GHz bands, masks other than /24 (the scanner computes the
  broadcast address as if for a /24 and adds the global 255.255.255.255).
- **Manufacturer app killing** on Android outside stock systems.
- **Doze mode**: the foreground service overrides the network block, but there
  is no automated test for it.
- **The UI on Windows**: there are no widget tests; it is checked by clicking.
- **Very large files and weak links**: the tests run over loopback, so they do
  not catch the timeouts typical of distant Wi-Fi.
