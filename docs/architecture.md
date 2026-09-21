# Architecture

A document for someone about to change something in this code. The user guide
is in [guide.md](guide.md), and the build commands are in
[building.md](building.md).

## The shape

There is no server, so **every copy is a client and a server at the same
time**. Each device hosts a small HTTP server (`shelf`) and answers UDP
broadcasts.

A device's identity is an **X25519 key pair**. The identifier (`guid`) is
derived from a hash of the public key, so it cannot be claimed without the
matching private key: whoever announces a foreign identifier will not finish
the handshake. Everything (conversations, sessions, deduplication) hangs off
the identifier; the address is only a hint about where the device was last
seen.

## Layers

```
lib/
  core/      identity, cryptography, platform channels, environment overrides
  data/      SQLite schema (drift) and queries
  network/   protocol, UDP discovery, HTTP server, HTTP client
  services/  AppServices, the root that ties everything together, plus Riverpod providers
  ui/        screens and widgets
```

**`AppServices`** holds the database, the server, the client and the discovery
responder, and decides what to do with every incoming request.
`AppServices.start()` builds a complete, self-contained stack, so tests can
bring up two of them in one process and make them talk over a real socket (see
[testing.md](testing.md)).

The UI does not talk to the network. Screens read **streams from the
database**, so every change reaches the view by itself. The exceptions are
things that are not in the database because they are transient: transfer
progress and consent requests, which travel through a `ValueNotifier`.

## Protocol

Protocol version **5** (`lib/network/protocol.dart`, `protocolVersion`), bumped
on incompatible changes.

**There is no plaintext in the protocol.** Every request other than
`GET /info`, `POST /handshake` and `POST /pair` arrives in an envelope bound to
a session; anything else gets a 409 and a request to shake hands.

### Discovery (UDP 47777)

The scanner broadcasts `chatt_discover` carrying **its own identity and a
random nonce**; every device answers with a `chatt_here` unicast. Because the
query carries the asker's identity, **one scan teaches both sides**.

Broadcast addresses: the global `255.255.255.255` plus a directed one per
interface, computed as if for a /24, because `dart:io` does not reveal the
subnet mask. The query goes out twice, 400 ms apart.

The packet carries the sender's public key and the receiver checks that it
matches the announced identifier; identities that do not match never enter any
list. The key for the first session is therefore known before the first word is
said.

An answer from a **known** device carries a `tag`: HMAC-SHA256 over the guid,
the port and the nonce from the query, keyed by an agreement between the static
keys alone, which is computable without a live session. The scanner drops any
answer that claims to be a known device without a matching signature.

### Messages and files (TCP 47780, configurable)

| Endpoint | What for |
|---|---|
| `GET /info` | device identity **with its public key**; also used as "are you alive" |
| `POST /handshake` | opening a session |
| `POST /message` | delivering a message; 200 = confirmed, 409 = renew the session |
| `POST /pair` | identity confirmation |
| `POST /file-offer` | file announcement: name, size, sha256, key tag, and the batch it belongs to |
| `POST /file` | raw bytes from the given offset, with the session number in a header |

### Session

```
A -> B   POST /handshake   { from: <A's identity with key>, e: <A's ephemeral> }
A <- B                     { sessionId, e: <B's ephemeral>, from: <B's identity> }
```

Both sides derive the session key from four X25519 agreements (the Noise KK
pattern): `ee` gives forward secrecy, `ss` binds the session to the identities,
`es` and `se` bind each ephemeral key to the other side's identity. The whole
transcript feeds the derivation, so swapping anything on the way yields a
different key and the traffic does not decrypt.

A session lives **one idle hour and only in memory**. A restart wipes it and
the next send creates a new one; there is nothing on disk to steal after the
fact.

The envelope carries **only the session number** in the clear, so an
eavesdropper cannot see who is talking to whom. An unknown number means 409:
the sender drops its session, shakes hands again and repeats the request once.

### File transfer

Two stages: the announcement, which the recipient accepts or rejects, and only
then the bytes. A refusal means zero bytes transferred. Transfer metadata
travels in `x-chatt-*` headers, which have to be ASCII, hence base64 and
percent-encoding; the content streams both ways, so a large file never passes
through memory.

The size in the header is what bounds the write, so it is compared against the
size in the announcement before a single byte is taken. Under encryption the
headers are not authenticated and the announcement is: without that comparison
a consent for one 100 kB file would let the sender push as much as it liked.

Files sent together form a **batch** and cost one question. The first
announcement carries the batch identifier, the count, the total size and every
file name; the rest carry only the identifier, and the sender keeps repeating
the description until the recipient actually accepts one, so a card nobody
answered does not quietly break the batch into per-file questions.

A description that does not describe its own announcement is dropped on arrival
(`FileOffer.fromJson`): without that, a sender could attach the list of three
innocent names to the announcement of something else entirely and the card would
show the wrong thing. Because of that rule, the first file is always inside its
own batch and always charged against it.

The recipient remembers the decision per (sender, batch) and it is worth exactly
what was announced: at most that many files, at most that many bytes, only those
names. Re-announcing a file that was already let in (which is how a resumed
transfer re-establishes consent) is free, but only when it is still the same
name and the same size. Two clocks bound the consent: thirty minutes of silence,
counted from the last file that actually used it, and six hours from the moment
it was given, which nothing can push. Anything outside all that falls back to an
ordinary per-file question, so a sender that announces three small files cannot
use the same consent for a fourth large one.

A refusal of any file of a known batch travels back as `batch-rejected`, which
stops the sender from announcing the rest; silence (the two-minute timeout) is
`no-answer`, decides nothing and leaves the batch open. The batch fields are
optional, so a peer that knows nothing about them asks per file as before, and
they deliberately stay out of the partial-transfer sidecar, which is compared
field by field when a transfer resumes.

Resuming: the partial transfer sits in `received/.incomplete/<guid>.part` with
a description beside it. The next attempt sends `x-chatt-file-offset` and gets
only the missing piece; once the whole thing is together the sha256 is
computed. Abandoned parts are swept after seven days.

## Database

`drift` (SQLite), schema version **11**. Tables: `settings`, `peers`,
`conversations`, `messages`.

| Version | What was added |
|---|---|
| 2 | files (transfer columns in `messages`) |
| 3 | `peers.sessionKey` |
| 4 | `settings.theme` |
| 5 | `settings.language` |
| 6 | `settings.identityKey`, `peers.publicKey`; **clears the device list and history** |
| 7 | `settings.retentionDays` |
| 8 | `settings.background` |
| 9 | `peers.alias`, `peers.autoAccept` |
| 10 | `settings.updateChecks`, `settings.lastUpdateCheck` |
| 11 | `settings.linkPreviews` |

The wipe at v6 comes from identifiers becoming key-derived: every device got a
new one, so saved contacts no longer matched anything on the network.

Every migration step adds a column only when `PRAGMA table_info` says it is
missing. A database whose layout runs ahead of its own `user_version`, which is
what a process killed between an `ALTER TABLE` and the version write leaves
behind, then opens and repairs itself instead of failing forever.

After every change in `lib/data/db.dart` the code has to be regenerated
(`build_runner`, see [building.md](building.md)) and **`schemaVersion` bumped
together with the migration**. Otherwise a user coming from the previous
version crashes at startup.

### The database on disk is encrypted

The build pulls in **SQLite3MultipleCiphers** (the
`hooks.user_defines.sqlite3.source: sqlite3mc` choice in `pubspec.yaml`). A
`PRAGMA key` runs when the database opens, and it has to run before the first
read, or SQLite sees encrypted pages and calls the file corrupt.

The password is 32 random bytes in `chatt.key`, next to the database. Its
content is wrapped by the **system keystore** through the `chatt/sekrety`
channel:

| Platform | Wrapped with | Implementation |
|---|---|---|
| Android | AES-GCM under a **Keystore** key, with no unlock requirement, because the app receives messages with the screen off | `ChattChannels.kt` |
| Windows | **DPAPI** under the user account key, with extra entropy | `windows/runner/chatt_secrets.cpp` |

The first byte of `chatt.key` says whether the content is wrapped. When the
keystore refuses, the key is written in the clear and Settings says so;
encryption still protects the database file on its own; a copy of the whole
app directory carries the key with it.

Keystore material never leaves the device, so a wrapped `chatt.key` that
travels somewhere else arrives useless. Android's backup would do exactly
that, which is why `allowBackup` is off and `data_extraction_rules.xml`
excludes both the cloud copy and the transfer to a new phone. It keeps the
conversation database out of Google's hands at the same time.

When the system key **disappears** anyway, `DatabaseKey.load` throws
`DatabaseKeyUnavailable`. The history is unreadable from that point on with no
way back, so the startup screen offers to delete the database and the key and
begin again, asking first and leaving received files alone.

A plaintext database left by an older version is rewritten on the first start
(`migrateToEncrypted`). Encryption works on file pages, so a database cannot be
keyed in place: the copy is built alongside and the original is removed only
after it is closed, which leaves either the old database or the new one.

## Security

### Threat model

The attacker is **on the same local network**: they can eavesdrop, send their
own packets and claim to be anyone. Plus an attacker who **gets at the disk**
and copies the database file or the whole app directory. Not assumed: access to
an **unlocked, running** device, where the key is in process memory by
definition.

### Identity confirmation

This does not establish the encryption key, which comes from the session and
changes every hour. It answers one question, "does this key belong to the
person I have in mind", and its result is the green shield.

```
A -> B   commit   sha256(pkA)              a commitment to the key
A <- B   answer with pkB                   B draws its own pair
A -> B   reveal   pkA                      B checks it against the hash
         both sides compute a six-digit code from an agreement that also
         takes in both static keys, and show it on screen
A <> B   confirm  (after a tap on each device)
```

The commitment goes first so that an attacker running a separate agreement with
each side cannot draw keys until the two codes match. The shield turns green
only once **both** ends confirm; a matching code also proves the other side
holds the private key for that identity, because the static keys feed the code
derivation.

A full PAKE (SPAKE2, CPace) is absent: `package:cryptography` offers X25519
only as a finished agreement, with no point operations and no hash-to-curve.

### QR code

One device shows `chatt://pair?k=<key>&h=<address>&p=<port>&n=<name>`, the
other scans it. Nothing in the code is secret; the value comes from the
**channel**, because whoever scanned it was looking at that screen.

The two sides end up in different states, and the UI shows that:

- **the scanner** is certain right away and its shield turns green,
- **the scanned device** gets a notification (`pairScanned`) and asks its own
  user "was that you scanning", because somebody else could have seen the code
  on the screen.

Before pinning the key from a code, `GET /info` checks that the address in the
code really does hold a device with that key.

### Traffic encryption

- **Messages and file announcements**: an AES-GCM envelope. Only the session
  number stays in the clear; the `from` inside has to match the owner of that
  session.
- **File content**: an AES-CTR stream, which is what allows resuming from an
  arbitrary byte. The key is separate per file, derived from the session key
  and the message guid. The nonce comes from the guid **and the content
  checksum**, so a retry after the file at that path was swapped cannot reuse
  the same key stream.
- **Resuming across sessions**: the announcement carries a file key tag and the
  recipient keeps it next to the partial transfer. A mismatch starts the
  transfer from zero.
- File integrity is guarded by the sha256 from the **encrypted** announcement,
  not from a header.

### Strings from the network against the disk

The only place where a string from the sender becomes a file name is
[`core/received_paths.dart`](../app/lib/core/received_paths.dart). Two
barriers:

1. **The protocol filters the shape.** `isSafeMessageGuid` accepts only
   letters, digits and a hyphen, up to 64 characters. The message identifier
   ends up in file names, so a path in it would mean a write outside the app
   directory.
2. **The on-disk name comes from a hash**, never from the identifier itself. A
   hash cannot be turned into a path, so the file stays in the received
   directory even if the first barrier lets something odd through.

The file name from the sender goes through `p.basename` and has characters
forbidden in Windows names stripped out.

A request body has a **one megabyte limit** (`_maxBodyBytes` in `server.dart`),
because it is read to the end before it is known whether the sender has a
session. File content does not go this way: it streams through `/file` straight
to disk, and reception aborts the moment the sender goes past the announced
size.

### What stays open

- `POST /pair` is not authenticated, so anyone can raise the confirmation card
  while borrowing a friend's name. That does not get them a green shield, and a
  card for an already known device is marked in red.
- **A restart during a transfer loses the progress**, because the file key
  hangs off the session key. A network drop of seconds or minutes resumes
  normally. Deriving the key from the static keys would fix it at the price of
  decrypting every previously recorded transfer after an identity theft.
- Discovery is in the clear: the device name and port are visible to everyone
  on the network. A broadcast goes out to someone you do not know yet, so there
  is nothing to encrypt it with.
- Session key rotation is deferred, because resuming a transfer needs the same
  key across sessions.
- Received files lie on disk unencrypted. The database wraps conversation
  history; file content stays where the user opens it with other applications.
- The database key can be extracted by a process running **as the same system
  user**: on Windows DPAPI unwraps it for any such process, and on Android the
  app sandbox is what protects it.
- **The transfer timeout assumes a fast link.** `lib/network/client.dart` uses
  `Duration(seconds: 30 + (total - start) ~/ (512 * 1024))`, which assumes at
  least 512 KB/s. Over a VPN at 2 Mbps a 100 MB file needs about 400 s and gets
  230, so the transfer is cut off and resuming never reaches the end. The fix
  is a clock refreshed on every chunk, so that only idleness counts.
- **A failed send always scans the LAN**, even when the peer's last known
  address is not local, so over a VPN the user sees a silent "not delivered"
  with no reason given. This is a diagnostics gap: the identity is the key and
  a device at a hijacked address derives a different session key.

## Android: background listening

A plain Flutter process dies with its window, so:

- the Flutter engine lives in the application cache (`ChattApplication`), not
  in the activity, so platform channels work with the window closed;
- `ChattService` (a `connectedDevice` foreground service) keeps the process
  alive and shows the permanent notification;
- the service holds a **MulticastLock**, without which the Wi-Fi stack filters
  broadcasts out before they reach the app;
- **`reusePort` is off**, because Dart does not support `SO_REUSEPORT` on
  Android and the bind throws. The flag is set only on desktop Linux and macOS,
  where it lets two instances share the port. `AppServices` records whether the
  responder started, and Settings shows a warning when it did not;
- **WifiLock** is taken only up to Android 12. From 13 the system accepts
  `WIFI_MODE_FULL_HIGH_PERF` and ignores it, and `LOW_LATENCY` works only for a
  foreground app.

A foreground service overrides Doze's network cut, so a battery optimisation
exemption is not needed on stock Android; the button in Settings stays as
insurance against manufacturers with their own app killing.

Files go out to other apps through FileProvider as `content://` (our own
`chatt/files` channel), because from API 24 a plain path ends in
`FileUriExposedException`. FileProvider serves only what
[`res/xml/file_paths.xml`](../app/android/app/src/main/res/xml/file_paths.xml)
lists, and it lists four roots: received files, a downloaded release, and the
two cache directories holding copies of files the user picked or pasted to
send. A file outside all of them cannot be handed out at all — which is what
made tapping your own sent photo fail until 0.8.2, because an outgoing message
keeps the source path it was given and nothing ever moves that file under
`files/`. The channel answers with a word (`ok`, `missing`, `failed`) rather
than a flag, so "the file is gone" and "handing it out failed" reach the user
as different sentences, and the failure is written to logcat instead of
vanishing into a `catch`.

Images skip all of this: tapping one opens
[`ImageViewScreen`](../app/lib/ui/screens/image_view_screen.dart), which draws
the file itself with Flutter's own decoder. Nothing leaves the app, so the
most common case does not depend on FileProvider, on the roots above, or on
there being an app installed that opens pictures.

Files come in through the same channel: the paperclip opens the system
document picker (`ACTION_OPEN_DOCUMENT`) from `ChattFilePicker`, which copies
each chosen file into the app cache on a worker thread and hands Dart the
paths. `file_selector`'s Android side reads every chosen file into a byte
array and ships it over the channel, which for a 150 MB file ends in
`OutOfMemoryError`; the desktop pickers return paths only, so `file_selector`
stays there.

## Windows: tray and autostart

A desktop process ends with its window, so:

- **The X hides the window.** `window_manager` blocks the close
  (`setPreventClose`) and `lib/core/tray.dart` hides the window. Quitting is
  in the tray icon menu and lifts that block.
- **The tray icon** (`tray_manager`) carries a tooltip and a menu in the app
  language, rebuilt when the language changes. The icon ships as a Flutter
  asset (`assets/tray_icon.ico`), because the tray reads a file from disk, not
  resources inside the `.exe`.
- **Starting minimised** is decided in the runner: `main.cpp` checks for the
  `--minimized` argument and then does not register showing the window after
  the first frame.
- **Autostart** is an entry in
  `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, created through our own
  `chatt/autostart` channel (`windows/runner/chatt_autostart.cpp`). A user
  account entry, so it needs no administrator rights. The value
  is the quoted path to the `.exe` plus `--minimized`.

## Layout: one window, two sizes

One set of screens serves a phone and a monitor:

- **A 900 px threshold** (`czyDwupanel`): above it the conversation list and
  the conversation stand side by side in one `Scaffold`, below it the
  conversation is a separate screen on the navigation stack. The same
  `ChatScreen` in both cases; the embedded one gets no back arrow.
- **Upper width limits**: bubbles 560 px, forms 760 px (`ContentColumn`).
- **`VisualDensity.adaptivePlatformDensity`**: tighter spacing on a desktop
  than on a phone.
- **Android system bars**: from API 35 the system draws them **over** the app
  without shrinking the window, so scrollable content adds its own bottom
  margin (`bottomSystemInset`). It takes `MediaQuery.padding`, not
  `viewPadding`, because with the keyboard open the bar sits above it.
- **Backgrounds** (`ui/backgrounds.dart`) are a gradient under the whole app,
  injected in `MaterialApp.builder`. A background makes the screen background
  and the app bar transparent; cards and bubbles stay opaque. The brightness of
  the system bar icons is then passed explicitly, because Flutter derives it
  from the app bar colour.
- **Selecting message text** is a `SelectionArea` around the conversation on
  the desktop, and a "Select text" entry in the bubble menu on a phone, where
  the long press already belongs to that menu.

## Updates: a call outside the local network

Everything else in the app talks only to devices on the same Wi-Fi. Checking
for a newer release is one of two exceptions (the other is
[link previews](#links-in-messages)), so it is fenced off:

- **Off by default.** `settings.updateChecks` (schema v10) starts false. With
  it off, the only way anything reaches `api.github.com` is the user pressing
  "Check now".
- **Once a day.** The timer in `AppServices` fires hourly but the question
  goes out only when `settings.lastUpdateCheck` is older than 24 hours. The
  stamp is written after a failed attempt too, so a dead connection does not
  turn a daily check into hourly knocking.
- **A public endpoint, nothing attached.** `GET /repos/Mysttic/Mysttic/releases`,
  no token, no identifiers. GitHub sees an IP address and a timestamp, the
  same as any HTTPS server. That repository is the one behind the
  [download page][strona] and it holds releases of every project, so the app
  takes the newest tag carrying the `chatt-v` prefix and skips drafts and
  prereleases. The code lives in a private repository, which is why the
  question goes here.

[strona]: https://mysttic.github.io/Mysttic/chatt/
- **Failure is silence.** `fetchLatestRelease` never throws;
  a timeout, a broken response or a missing network all come back as
  `UpdateCheck.failed` and the app carries on.

Installing is deliberately not automatic. The app downloads the release file
for its platform and hands it over:

| Platform | Handed to | Note |
|---|---|---|
| Windows | the Inno Setup installer with `/SILENT /CLOSEAPPLICATIONS` | `AppId` is fixed, so it lands in the same place and leaves the database in Documents |
| Android | the system package installer through the FileProvider | needs `REQUEST_INSTALL_PACKAGES`; the user confirms on a system screen |

The portable copy from the zip is left out: an installer would write a second
copy somewhere else and the running directory would stay old. It is recognised
by the absence of `unins000.exe` next to the executable, and it gets the
release page address instead of a button.

## Links in messages

A message body is plain text from someone else on the network, so a link in it
is a **string from a stranger**. Two separate things happen to it, and they are
gated separately.

### Clicking a link always asks first

[`core/links.dart`](../app/lib/core/links.dart) finds addresses in the body and
[`ui/widgets/linked_text.dart`](../app/lib/ui/widgets/linked_text.dart) turns
them into tappable spans, composed with the search highlight, so the two can
overlap on the same characters.

- **Only `http` and `https` become links.** `javascript:`, `data:`, `file:`,
  `intent:` and `content:` stay plain text, because tapping them would mean
  "run something", not "show a page".
- **An address carrying invisible characters is not linkified at all**: a
  right-to-left override reverses the tail of a name, so `…exe` reads as
  `…txt`, and there is no honest way to show where such a link goes.
- **A host name with no dot is not a link** (`http://localhost:8080`), unless
  it is a literal IP address, which is everyday life on a local network.
- Tapping never opens anything. It raises the card in
  [`ui/widgets/link_confirm.dart`](../app/lib/ui/widgets/link_confirm.dart),
  which shows the **host on its own line** and the full address below it, plus
  a warning for each of: an `@` before the host name (`https://bank@evil.example`),
  non-ASCII letters in the host name, no encryption, and an address on the
  local network. Only "Open" hands it to the system browser.
- `openExternalLink` checks the scheme once more immediately before starting a
  process, and passes the address as a **list argument, never through a
  shell**. On Android it goes through the `chatt/files` channel, where
  `ChattChannels.openUrl` checks the scheme a third time and adds
  `CATEGORY_BROWSABLE`.
- Links also appear as entries in the bubble's long-press menu. That is the
  reliable path on the desktop, where `SelectionArea` owns the tap.

### The preview fetches, so it is off by default

[`core/link_preview.dart`](../app/lib/core/link_preview.dart) is the second
place the app reaches outside the local network, and unlike the update check
the address is chosen by **the sender of the message**, not by the user. Hence
`settings.linkPreviews` (schema v11), false until switched on, live: turning it
off stops the fetches and drops what was already fetched.

- **Nothing from the page is executed.** There is no WebView, no browser and no
  HTML tree. The code reads `<meta>` tags and `<title>` with a regular
  expression, keeps the text and hands the image bytes to Flutter's own
  decoder, the same one the received-file thumbnails use. `image/svg+xml` is
  excluded on purpose: SVG is a document that can carry scripts.
- **Never into the local network.** `hostAllowsPreview` refuses loopback,
  private, CGNAT, link-local and unique-local addresses, and names that look
  local (`.local`, `.lan`, `.internal`, no dot at all). Every DNS answer is
  checked, not just the first, so a name pointing at both a public and a
  private address is refused whole. Without this, a message saying
  `http://192.168.0.1/reboot` would make the app visit the router, and a series
  of addresses would turn response times into a scan of the network.
- **Redirects are followed by hand**, at most three, with the scheme and host
  checked again at every hop, because a redirect is the simplest way to turn a
  public address into a local one.
- **Hard limits**: 8 s, 512 KB of HTML, 2 MB of image, `identity` encoding, and
  a content type that has to match. Going past the byte limit tears the
  connection down rather than reading the rest into the bin.
- **What is drawn is scrubbed**: entities decoded, whitespace collapsed,
  control and bidi characters removed, title clipped at 140 characters and
  description at 300, so a foreign title cannot rearrange the rest of the card.
- Answers are cached in memory, sixty-four of them, failures included, so
  scrolling a conversation back and forth does not question anyone's server
  twice. Only the **first** link in a message gets a card.

What stays open: between our DNS question and the one the HTTP client asks
itself, the record can change ("DNS rebinding"). The cost of losing that race
is one empty GET to a local address; the answer still cannot run anything,
because all the app takes from it is text and image bytes.
