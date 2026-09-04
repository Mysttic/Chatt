# Architecture

A document for someone about to change something in this code. The user guide
is in [guide.md](guide.md), and the build commands are in
[building.md](building.md).

## Where this shape comes from

The app has no server, so **every copy is a client and a server at the same
time**. Each device hosts a small HTTP server (`shelf`) and answers UDP
broadcasts. That is exactly how LocalSend works, and it is the only arrangement
that gives a direct connection without anybody's infrastructure.

A device's identity is an **X25519 key pair**, not an IP address and not a
random string. The identifier (`guid`) is derived from a hash of the public
key, so nobody can claim someone else's without their private key: whoever
announces a foreign identifier will not finish the handshake. An IP changes
when the router restarts, an identity does not, which is why everything
(conversations, sessions, deduplication) hangs off the identifier and the
address is only a hint about where it was last seen.

## Layers

```
lib/
  core/      identity, cryptography, platform channels, environment overrides
  data/      SQLite schema (drift) and queries
  network/   protocol, UDP discovery, HTTP server, HTTP client
  services/  AppServices, the root that ties everything together, plus Riverpod providers
  ui/        screens and widgets
```

The heart of it is **`AppServices`**: it holds the database, the server, the
client and the discovery responder, and it decides what to do with every
incoming request. `AppServices.start()` builds a complete, self-contained
stack, which is why the tests bring up two of them in one process and make them
talk to each other over a real socket (see [testing.md](testing.md)).

The UI does not talk to the network. Screens read **streams from the
database**, so every change (a new message, a status change) reaches the view
by itself. The exceptions are things that are not in the database because they
are transient: transfer progress and consent requests, which travel through a
`ValueNotifier`.

## Protocol

Protocol version: **5** (`lib/network/protocol.dart`, the `protocolVersion`
constant). We bump it on incompatible changes.

**From version 5 there is no plaintext in the protocol.** Every request other
than `GET /info`, `POST /handshake` and `POST /pair` arrives in an envelope
bound to a session; everything else gets a 409 and a request to shake hands.

### Discovery (UDP 47777)

The scanner broadcasts `chatt_discover` carrying **its own identity and a
random nonce**, and every device answers with a `chatt_here` unicast. Because
the query carries the asker's identity, **one scan teaches both sides**.

Broadcast addresses: the global `255.255.255.255` plus a directed one per
interface, computed as if for a /24 (`dart:io` does not reveal the subnet
mask). The query goes out twice, 400 ms apart, because a single datagram is
easily lost over Wi-Fi.

The packet also carries the sender's public key, and the receiver checks that
it matches the announced identifier. Identities that do not match never enter
any list. That way the key for the first session is known before the first word
is said.

An answer from a **known** device carries a `tag`: HMAC-SHA256 over the guid,
the port and the nonce from the query, keyed by an agreement between the static
keys alone (computable without a live session). The scanner drops from the
results any answer that claims to be a known device without a matching
signature. Without that, somebody who knows another device's public key could
take its place in the list, and that list is where the address comes from when
the other side changes IP.

### Messages and files (TCP 47780, configurable)

| Endpoint | What for |
|---|---|
| `GET /info` | device identity **with its public key**; also used as "are you alive" |
| `POST /handshake` | opening a session (below) |
| `POST /message` | delivering a message; 200 = confirmed, 409 = renew the session |
| `POST /pair` | identity confirmation (four actions, below) |
| `POST /file-offer` | file announcement: name, size, sha256, key tag |
| `POST /file` | raw bytes from the given offset, with the session number in a header |

### Session

```
A -> B   POST /handshake   { from: <A's identity with key>, e: <A's ephemeral> }
A <- B                     { sessionId, e: <B's ephemeral>, from: <B's identity> }
```

Both sides derive the session key from four X25519 agreements (the Noise KK
pattern): `ee` gives forward secrecy, `ss` binds the session to the identities,
`es` and `se` bind each ephemeral key to the other side's identity. The whole
transcript feeds the derivation, so swapping anything on the way simply yields
a different key and the traffic does not decrypt.

A session lives **one idle hour and only in memory**. A restart wipes it and
the next send creates a new one. That is the whole mechanism behind forward
secrecy: there is nothing on disk to steal after the fact.

The envelope carries **only the session number** in the clear. The sender's
guid is gone from it, so an eavesdropper cannot even see who is talking to
whom. An unknown number (the other side restarted, or it expired) means 409:
the sender drops its session, shakes hands again and repeats the request once.

A file transfer has **two stages**: first the announcement, which the recipient
accepts or rejects, and only then the bytes. A refusal means zero bytes
transferred. Transfer metadata travels in `x-chatt-*` headers (which have to be
ASCII, hence base64 and percent-encoding) and the content streams both ways, so
a large file never passes through memory.

Resuming: the partial transfer sits in `received/.incomplete/<guid>.part` with
a description next to it. The next attempt sends `x-chatt-file-offset` and gets
only the missing piece; once the whole thing is together, the sha256 is
computed. Abandoned parts are cleaned up after seven days.

## Database

`drift` (SQLite), schema version **9**. Tables: `settings`, `peers`,
`conversations`, `messages`. Migrations are written in order, so a database
from an earlier version of the app opens without losing data, with one
exception described below:

| Version | What was added |
|---|---|
| 2 | files (transfer columns in `messages`) |
| 3 | `peers.sessionKey`; the migration clears `verified` for pairings with no key |
| 4 | `settings.theme` |
| 5 | `settings.language` |
| 6 | `settings.identityKey`, `peers.publicKey`; **clears the device list and history** |
| 7 | `settings.retentionDays` (automatic deletion of old messages) |
| 8 | `settings.background` (the chosen background) |
| 9 | `peers.alias` (a name of your own) and `peers.autoAccept` (take files without asking) |

The wipe at v6 is deliberate: identifiers stopped being random and started
following from keys, so every device got a new one. Saved contacts no longer
matched anything on the network, and keeping them would have meant a list of
entries nobody could write to.

After every change in `lib/data/db.dart` the code has to be regenerated
(`build_runner`, see [building.md](building.md)) and **`schemaVersion` bumped
together with the migration**. Otherwise a user coming from the previous
version gets a crash at startup.

The schema descends from the model in the first version of the project:
[`mockups/db_schema.png`](mockups/db_schema.png).

### The database on disk is encrypted

Instead of plain SQLite the build pulls in **SQLite3MultipleCiphers** (the
`hooks.user_defines.sqlite3.source: sqlite3mc` choice in `pubspec.yaml`). A
`PRAGMA key` runs when the database opens, so the `chatt.sqlite` file does not
even have a readable header: verified, `od -c` shows random bytes, and opening
it without the password ends in `SqliteException(26): file is not a database`.

The password is 32 random bytes sitting next to the database in `chatt.key`.
The file on its own is useless, because its content is wrapped by the **system
keystore** through the `chatt/sekrety` channel:

| Platform | Wrapped with | Implementation |
|---|---|---|
| Android | AES-GCM under a **Keystore** key (no unlock requirement: the app receives messages with the screen off) | `ChattChannels.kt` |
| Windows | **DPAPI** under the user account key, with extra entropy | `windows/runner/chatt_secrets.cpp` |

The first byte of `chatt.key` says whether the content is wrapped. When the
keystore refuses (a platform with no implementation), the key is written in the
clear and Settings says so outright. Database encryption still works, but from
then on it only protects against copying the database file, not the whole app
directory. When the system key **disappears** (a reinstall, a backup restored
onto another device), `DatabaseKey.load` throws instead of quietly assuming an
empty database.

A plaintext database left by an older version is rewritten on the first start
(`migrateToEncrypted`): encryption works on file pages, so a database cannot be
"keyed" in place. The copy is built alongside and the original disappears only
after it is closed, so an interruption halfway leaves either the old database
or the new one. Verified on both platforms against a real pre-change database:
the nickname and the rest of the settings survived, and after the start the
file is encrypted.

## Security

### Threat model

We assume an attacker **on the same local network**: they can eavesdrop, send
their own packets and claim to be anyone. On top of that comes an attacker who
**gets at the disk**: copying the database file or the whole app directory. The
database is encrypted and its key is held by the system keystore, so the file
alone gets them nothing. We do not assume an attacker with access to an
**unlocked, running** device, where the key is in process memory by definition.

### Identity confirmation (formerly "pairing")

Since protocol 5 this ritual **does not establish the encryption key**, which
comes from the session and changes every hour. It answers one question only,
"does this key belong to the person I have in mind", and its result is the
green shield.

```
A -> B   commit   sha256(pkA)              a commitment to the key
A <- B   answer with pkB                   B draws its own pair
A -> B   reveal   pkA                      B checks it against the hash
         both sides compute a six-digit code from an agreement that also
         takes in both static keys, and show it on screen
A <> B   confirm  (after a tap on each device)
```

The shield turns green only once **both** ends confirm. A matching code also
proves that the other side holds the private key for that identity, because the
static keys feed the code derivation.

### QR code

A faster and stronger route to the same thing. One device shows
`chatt://pair?k=<key>&h=<address>&p=<port>&n=<name>`, the other scans it.

There is nothing secret in the code. The value comes from the **channel**:
whoever scanned it was looking at that screen, so they know the key came from
there and not from somebody in between. Here the attacker does not get a
one-in-a-million chance, as with six digits. They get zero, because there is no
way to substitute their own key.

The asymmetry is unavoidable, which is why it is visible in the UI:

- **the scanner** is certain right away and its shield turns green,
- **the scanned device** only gets a notification (`pairScanned`) and asks its
  own user "was that you scanning", because somebody else could have seen the
  code on the screen. The human confirms what the machine cannot know: that a
  scan just happened and that they were the one who did it.

Before pinning the key from the code, `GET /info` checks that the address in
the code really does hold a device with that key. Otherwise somebody could hand
over a code with their own key and somebody else's address.

Why the commitment: without it an attacker in the middle (running a separate
agreement with each side) could keep drawing their own keys until the two codes
matched. A hash sent before the other side's key is known makes that
impossible, leaving one hit in a million, and a visible one at that, because
the users would see different codes.

An earlier version mixed a retyped PIN into HKDF as a salt. That had a weak
spot: an attacker present during pairing could then check all six-digit codes
offline. Now the code takes no part in deriving the key, so there is nothing to
break.

A full PAKE (SPAKE2, CPace) is deliberately absent: `package:cryptography`
offers X25519 only as a finished agreement, with no point operations and no
hash-to-curve, and hand-rolled curve arithmetic is a short road to a silent
bug.

### Traffic encryption

- **Messages and file announcements**: an AES-GCM envelope. Only the session
  number stays in the clear, and the recipient finds the key by it; the `from`
  inside has to match the owner of that session, otherwise a peer could write
  in someone else's name inside its own, correctly encrypted message.
- **File content**: an AES-CTR stream, because that is the only way to resume a
  transfer from an arbitrary byte. The key is separate per file, derived from
  the session key and the message guid. The nonce is computed from the guid
  **and the content checksum**: the guid alone is not enough, because a retry
  after the file at that path was swapped would reuse the same key stream a
  second time.
- **Resuming after a session change**: the announcement carries a file key tag
  and the recipient keeps it next to the partial transfer. A mismatch means the
  part is encrypted with something else, and then the transfer starts from zero
  instead of gluing on bytes that cannot be decrypted with the rest.
- File integrity is guarded by the sha256 from the **encrypted** announcement,
  not from a header.

### The rule everything else stands on

**There is no plaintext in the protocol.** A request without an envelope bound
to a live session gets a 409, no matter who it claims to be. Earlier this rule
applied only to paired devices, and a single plaintext packet with somebody
else's identifier was enough to borrow their green shield; three tests in
`test/downgrade_test.dart` replay exactly that attack.

### Strings from the network against the disk

The only place where a string from the sender becomes a file name is
[`core/received_paths.dart`](../app/lib/core/received_paths.dart). Two barriers,
because one is not enough:

1. **The protocol filters the shape.** `isSafeMessageGuid` accepts only
   letters, digits and a hyphen (up to 64 characters). The message identifier
   ends up in file names, so `../../../anything` would mean a write outside the
   app directory, and on a desktop that reaches everywhere the user reaches.
2. **The on-disk name comes from a hash**, never from the identifier itself. A
   hash cannot be turned into a path, so even if the first barrier ever let
   something odd through, the file still stays in the received directory.

The file name from the sender additionally goes through `p.basename` and has
characters forbidden in Windows names stripped out.

A request body has a **one megabyte limit** (`_maxBodyBytes` in `server.dart`).
Without it anyone on the network could send a multi-gigabyte JSON and take the
app down on memory: the body is read to the end before it is even known whether
the sender has a session. File content does not go this way. That streams
through `/file` straight to disk, and reception aborts the moment the sender
goes past the announced size.

### What stays open

- `POST /pair` is not authenticated, so anyone can raise the confirmation card
  while borrowing a friend's name. That does not get them a green shield (the
  codes have to match on both screens), but a card for an already known device
  is clearly marked in red.
- **A restart during a transfer loses the progress**, because the file key
  hangs off the session key. A network drop of seconds or minutes resumes
  normally. Deriving the key from the static keys would fix it at the cost of
  decrypting every previously recorded transfer after an identity theft, which
  is the very thing this release exists for.
- Discovery is in the clear. The device name and port are visible to everyone
  on the network. There is no way to encrypt that: a broadcast goes out to
  someone you do not know yet.
- Session key rotation: deliberately deferred, because resuming a transfer
  needs the same key across sessions.
- Received files lie on disk unencrypted. The database only wraps conversation
  history; the content of transferred files stays where the user expects to
  open it with other applications.
- The database key can be extracted by a process running **as the same system
  user**: on Windows DPAPI will unwrap it for any such process, and on Android
  the app sandbox is what protects it.
- **The transfer timeout assumes a fast link.** `lib/network/client.dart` uses
  `Duration(seconds: 30 + (total - start) ~/ (512 * 1024))`, which is "30
  seconds plus a second per 512 KB" and therefore assumes at least 512 KB/s. On
  a local network that always holds, which is why nobody noticed. Over a VPN
  the upload is often slower: at 2 Mbps a 100 MB file needs about 400 s and
  gets 230, so the transfer is cut off. Resuming rescues it, but it keeps
  coming back and never finishes if every piece is cut before the end. The fix
  is a clock refreshed on every chunk (idleness rather than the whole
  transfer), which also simplifies the formula.
- **A failed send always scans the LAN**, even when the peer's last known
  address is not local. Over a VPN that scan cannot find anything, so the user
  sees a silent "not delivered" instead of a reason. This is diagnostics, not a
  security gap: the identity is the key, the address is only a hint, and a
  device sitting at a hijacked address derives a different session key and gets
  nothing.

## Android: background listening

An ordinary Flutter process dies right after the window closes. Measured: a
message sent to a closed app did not arrive at all. Hence:

- the Flutter engine lives in the application cache (`ChattApplication`), not
  in the activity, so platform channels work with the window closed too;
- `ChattService` (a `connectedDevice` foreground service) keeps the process
  alive and shows the permanent notification;
- the service holds a **MulticastLock**. Without it the Wi-Fi stack filters
  broadcasts out before they reach the app, and discovery dies with the screen
  off;
- **`reusePort` is off on Android.** Dart does not support `SO_REUSEPORT`
  there, and asking for it made the responder's bind throw. The exception was
  swallowed, so the phone quietly stopped answering other devices' scans while
  everything else kept working. The flag is now enabled only on desktop Linux
  and macOS, where it lets two instances share the port, and `AppServices`
  records whether the responder actually started so Settings can say so.
- **WifiLock** is taken only up to Android 12. From 13 the system accepts
  `WIFI_MODE_FULL_HIGH_PERF` and ignores it (visible in `dumpsys wifi` as
  "0 full high perf"), and `LOW_LATENCY` works only for a foreground app, so it
  is useless in the background.

In Doze the system would like to cut the app off the network, but a foreground
service overrides that. It shows up directly in `dumpsys netpolicy`:

```
UID=... state={procState=FGS}
blocked_state={blocked=DOZE|APP_BACKGROUND, allowed=FOREGROUND, effective=NONE}
```

A battery optimisation exemption (the button in settings) is not needed for
this on stock Android; it stays as insurance against manufacturers with their
own app killing.

Files go out to other apps through FileProvider as `content://` (our own
`chatt/files` channel, no plugins from pub.dev), because from API 24 a plain
path ends in `FileUriExposedException`.

## Windows: tray and autostart

The same problem as on Android, solved differently: the app listens for as long
as the process lives, and a desktop process ends with its window.

- **The X hides the window.** `window_manager` blocks the close
  (`setPreventClose`) and `lib/core/tray.dart` hides the window instead of
  destroying it. Quitting is in the tray icon menu and lifts that block, so
  only then does closing the window end the process.
- **The tray icon** (`tray_manager`) carries a tooltip and a menu in the app
  language. The menu is rebuilt when the language changes, exactly like the
  service notification on Android. The icon ships as a Flutter asset
  (`assets/tray_icon.ico`), because the tray reads a file from disk, not
  resources inside the `.exe`.
- **Starting minimised** is decided in the runner, not in Dart: `main.cpp`
  checks for the `--minimized` argument and then does not register showing the
  window after the first frame. That way there is no window flash at system
  startup.
- **Autostart** is an entry in
  `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, created through our own
  `chatt/autostart` channel (`windows/runner/chatt_autostart.cpp`). A user
  account entry, not a service: no administrator rights, and removable by hand
  as well. The value is the quoted path to the `.exe` plus `--minimized`.

## Layout: one window, two sizes

One set of screens serves a phone and a monitor, with no separate version per
platform:

- **A 900 px threshold** (`czyDwupanel`): above it the conversation list and
  the conversation stand side by side in one `Scaffold`, below it the
  conversation is a separate screen on the navigation stack. The same
  `ChatScreen` in both cases, and the embedded one gets no back arrow, because
  there is nothing to pop.
- **Upper width limits**: bubbles 560 px, forms 760 px (`ContentColumn`).
  Without them a line on a monitor runs half a metre across.
- **`VisualDensity.adaptivePlatformDensity`**: a desktop is driven with a
  mouse, so lists and buttons get tighter spacing than on a phone.
- **Android system bars**: from API 35 the system draws them **over** the app
  and does not shrink the window, so scrollable content has to add its own
  bottom margin (`bottomSystemInset`). We take `MediaQuery.padding`, not
  `viewPadding`: with the keyboard open the bar sits above it, and adding that
  gap a second time would push content into thin air.
- **Backgrounds** (`ui/backgrounds.dart`) are a gradient under the whole app,
  injected in `MaterialApp.builder`. Turning a background on makes the screen
  background and the app bar transparent; cards and bubbles stay opaque,
  because readability rides on them. The brightness of the system bar icons
  then has to be given explicitly, because Flutter derives it from the app bar
  colour and that colour is gone.

## Where the look came from

The screens follow the mockups from the first version of the project, which
live in [`mockups/`](mockups/): [conversation
list](mockups/conversation_list.png), [conversation](mockups/conversation.png),
[nearby devices](mockups/nearby_devices.png), [settings](mockups/settings.png),
[adding by address](mockups/add_by_address.png). The flows (retrying
undelivered messages, checking presence) are in the
[diagram](mockups/flows.png).
