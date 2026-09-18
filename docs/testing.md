# Tests

The split is simple: **205 `flutter test` tests** check everything that can be
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

### Choosing a file on Android (`test/file_actions_test.dart`, 4 tests)
The `chatt/files` channel answers with the paths of the copies it made:
- the list comes back as it is
- a closed picker, an error from Android and a missing channel (the desktop,
  a widget test) all give an empty list, so the paperclip never takes a screen
  down with it

### Pasting from the clipboard (`test/clipboard_test.dart`, 13 tests)
The Dart side of the `chatt/clipboard` channel. Whatever the platform says,
the conversation screen gets a list of paths or an empty list, never an
exception, because this hangs off Ctrl+V and off an entry in a sheet:
- `hasFiles` passes the platform's answer through; an error and a missing
  channel (Linux, a widget test) both mean "nothing there"
- `pasteFiles` returns the paths and passes the name for an image that has no
  file of its own; the name is cut down to its last segment, so
  `../../etc/passwd` reaches the platform as `passwd`
- content inserted from the keyboard lands in the temporary directory, takes
  its extension from the MIME type (`image/gif` turns `obraz.png` into
  `obraz.gif`), keeps an unknown type's name as it came, and two insertions in
  a row do not overwrite each other

The platform halves of the channel are not here: they need a real clipboard,
and that is `tool/schowek_check.dart`.

### Ctrl+V on the conversation screen (`test/paste_shortcut_test.dart`, 10 tests)
`PasteShortcut` listens for keys globally, because a freshly opened
conversation has focus nowhere and a handler sitting in the widget tree would
never hear the most common case: copy a file in Explorer, come back, Ctrl+V.
Global also means it hears keys that are not its own, so what is tested is
when it speaks and when it stays quiet:
- nothing focused, or focus inside the screen: it pastes
- focus on a button outside the screen (the file-offer card floats above the
  whole app and takes focus so Enter accepts it): it still pastes
- focus in a text field outside the screen (the search box in the bar): silence,
  because that is the one place where Ctrl+V already means something
- V alone, Ctrl alone, Ctrl+Shift+V: silence
- a key going up does not count a second time
- something on top of the screen (a sheet, a dialog), and the screen taken out
  of the tree: silence
- the event travels on, so Ctrl+V in the message field still pastes text **and**
  asks about the clipboard; returning "handled" would have killed the first one

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

### Starting over after a lost key (`test/startup_error_test.dart`, 4 tests)
- the reset deletes the database, its journals and the key, and stops at the
  received files and the failure report
- it also survives a directory with none of those in it
- "Start over" opens a confirmation first, because the button throws away every
  conversation on the device
- another kind of startup failure has nothing to reset, and the button is not
  offered at all

### Migration ahead of its own version (`test/migration_test.dart`, 1 test)
- a database with the current column layout and `user_version` rolled back to
  8, which is what a process killed between `ALTER TABLE` and the version
  write leaves behind; it has to open, keep its rows, and not throw
  `duplicate column name`

### Links in messages (`test/links_test.dart`, 23 tests)
- `http`, `https` and a bare `www.` become links; `javascript:`, `data:`,
  `file:`, `mailto:`, `intent:` and `content:` stay plain text
- the full stop ending a sentence is not part of the address, a bracket that
  belongs to the address stays and one that belongs to the sentence goes
- an address carrying invisible or direction-changing characters is not a link
  at all, and a host name with no dot is not one either unless it is a literal
  IP address
- the warnings the confirmation card shows: an `@` before the host, non-ASCII
  letters in the host, no encryption, an address on the local network
- what counts as local: loopback, `10/8`, `172.16/12`, `192.168/16`,
  `169.254/16`, CGNAT, `198.18/15`, multicast and reserved, `::1`, `fe80::/10`,
  `fc00::/7`, an IPv4 address mapped into IPv6, and names like `.local`,
  `.lan`, `.internal`; `172.32.0.1` and `192.169.0.1` are not local, which is
  where an off-by-one in the ranges would show
- `openExternalLink` refuses a scheme other than `http`/`https` before it
  starts any process

### Link previews (`test/link_preview_test.dart`, 37 tests)
- the card is built from `og:`, then `twitter:`, then `<title>` and
  `description`; attribute order and quoting do not matter, and a `<meta>`
  after `</head>` cannot override the real title
- what is drawn is scrubbed: entities decoded, whitespace collapsed, control
  and direction-changing characters removed, a long title clipped
- the switch decides: with previews off nothing reaches the network at all
- the fence around the address: a local address, a name that resolves to one,
  a DNS answer mixing a public and a local address, an empty answer and a
  failed lookup are all refused, and a literal local address is refused before
  DNS is even asked
- a redirect is followed and re-checked, one into the local network or onto
  another scheme ends it, and a chain cannot run past the limit
- a non-HTML type, a non-200, an announced length over the limit and a body
  that runs past it while streaming all end with no card; the oversized body
  is cut off rather than read to the end
- the image comes in a second request, `image/svg+xml` is refused, and an
  image address in the local network is not fetched
- answers are cached, two questions at once become one connection, turning the
  switch off drops what was fetched, and a thrown socket error ends as no card

### Checking for a newer release (`test/updates_test.dart`, 12 tests)
- version comparison member by member, so 0.5.10 beats 0.5.4, with a leading
  `v` and anything after `-` or `+` ignored, and a missing member counting as
  zero
- the asset name matches what the release workflow writes, per platform, and
  on Android that is the APK
- a newer release comes back with its file; the same or an older one is
  `upToDate`; a draft or a pre-release counts as nothing new; somebody else's
  release does not pass for ours, and a release with no file for this platform
  still yields a number and a page
- a non-200, a malformed body and a thrown exception all end as `failed`, and
  the call never throws

### The release card (`test/update_card_test.dart`, 5 tests)
- an installable release shows the button and calls back when tapped
- the portable copy and a release with no file for this platform get the page
  address instead
- while downloading, the progress bar replaces the button
- an error sits under the button without taking it away

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

### `tool/schowek_check.dart`
The platform half of `chatt/clipboard` lives in the runner, so `flutter test`
never sees it. This one raises the real app, asks the clipboard and prints what
came out:

```
cd app
%USERPROFILE%\dev\flutter\bin\flutter.bat run -d windows -t tool/schowek_check.dart
%USERPROFILE%\dev\flutter\bin\flutter.bat run -d emulator-5554 -t tool/schowek_check.dart
```

Three lines come before the result, because "nothing to paste" has several very
different causes that look identical from Dart: whether the channel answered at
all, what plain text is on the clipboard (read through Flutter's own
`Clipboard`, which on Android also proves the app has the window focus the
system demands for a clipboard read), and only then the answer.

Four cases on Windows, one run each, with the clipboard filled beforehand: a
file copied in Explorer (the path has to come back as it is, with no copy
made), a screen clipping from Win+Shift+S and "copy image" on a web page (both
have to come out as a PNG in the temporary directory, and the script prints the
size and the first bytes, so an empty file shows up at once), and a range of
cells copied in Excel, which carries a bitmap alongside the text and has to
come out as **nothing**: otherwise an ordinary Ctrl+V of some numbers would
also send the other side a screenshot of them.

On Android the negative cases run the same way. The positive one needs an app
that puts a `content://` on the clipboard, and a stock emulator image has none:
Files has no clipboard copy at all (only "Copy to…", which copies the file
somewhere else), Chrome's "Copy image" leaves an empty text clip, the
screenshot overlay has no Copy, and Photos wants a Google account. That case
needs a real phone.

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
- **Pasting a file on Android**: a stock emulator image has no app that puts a
  `content://` on the clipboard, so the reading side of `ChattClipboard` is
  checked on a real phone, with a file manager and with "copy image" in a
  browser. The copy itself is shared with the file picker and does get
  exercised on the emulator.
- **The keyboard's "insert image"**: the emulator ships AOSP LatinIME, which
  has no picture or GIF button, so `contentInsertionConfiguration` needs Gboard
  on a real phone.
