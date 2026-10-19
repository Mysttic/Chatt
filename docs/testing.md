# Tests

The split is simple: **442 `flutter test` tests** check everything that can be
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
plaintext), once as a link that dies after N bytes (resuming a transfer). The
wiretap records both directions and keeps each connection of the sending side
apart, so a test can cut the recording into single HTTP requests and play them
back.

The remote keyboard needs a device that types, and `flutter test` has no native
side, so the receiving instance gets an in-memory sink
(`AppServices.start(remoteInputSink:)`) that records every operation it is
handed and answers with a made-up target. Two hooks marked
`@visibleForTesting` cover what a real sender never does:
`debugSendSealed` seals any payload under the live session and sends it to
`/input-session` or `/input` (forged tokens, old numbers, bad shapes), and
`debugDropIncomingSessions` makes the receiver forget a sender's session
without a restart, which would wipe the grant as well.

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

### Messages (`test/messaging_e2e_test.dart`, 6 tests)
- pairing by address, exchanging messages both ways, dedupe
- recipient offline: failed, and after it comes back a retry delivers
- another Chatt answering at the peer's old address is neither the peer's
  presence nor a road to the peer: the presence check says offline and the
  message ends as failed
- adding by hand records the address the device **answered from**
- we do not talk to ourselves (a loop onto our own address)
- the server rejects garbage without falling over

### Files (`test/file_transfer_test.dart`, 14 tests)
- several files at once go one after another but cost one consent question,
  and that question carries the count, the names and the total size (the same
  road as dragging them onto the window or pasting them)
- one file is not a batch: the question looks exactly as it always did
- a refusal covers the whole batch and stops the sender, so nothing after the
  first file is even announced and nothing reaches the recipient
- silence is not a refusal: after the two-minute timeout the next file of the
  batch asks again instead of disappearing because nobody was looking
- a file that grew past what the batch announced falls out of the consent and
  is asked about on its own
- a transfer whose header claims a bigger size than the announcement is refused
  before a byte is written (a proxy rewrites `x-chatt-file-size` in flight; the
  headers are not authenticated under encryption and the announcement is)
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

### Choosing a file on Android (`test/file_actions_test.dart`, 9 tests)
The `chatt/files` channel answers with the paths of the copies it made:
- the list comes back as it is
- a closed picker, an error from Android and a missing channel (the desktop,
  a widget test) all give an empty list, so the paperclip never takes a screen
  down with it

Opening and sharing answer with a word rather than a flag, and that word
decides which sentence the user reads:
- `ok` is success, `missing` says the file is gone, `failed` says handing it
  out did not work
- an unknown word and no answer at all both count as a failure, never as a
  quiet success

### The photo preview (`test/image_view_test.dart`, 5 tests)
The screen a thumbnail opens into:
- the sender's name of the file is in the bar, and the picture is in the view
- the button turns the picture a quarter at a time and comes back to zero
- a file deleted in the meantime gets a sentence, not a black screen
- a file that is not an image at all does not take the screen down
- the actions handed in by the conversation land in the bar and fire

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

### Encryption (`test/encryption_test.dart`, 6 tests)
- paired: message content does not travel in plaintext, checked with a wiretap
  on the link
- **unpaired: the content does not travel in plaintext either**
- paired: a file travels encrypted and comes together byte for byte
- paired: resuming an encrypted file sends only the remainder
- remote keyboard: the typed text, the word `password` from the target and the
  receiving app's package and label appear in neither direction on the wire,
  while the receiver's sink gets the text exactly
- remote keyboard, replay from the wire: every recorded `/input-session` and
  `/input` request, sent again with a plain `HttpClient` after the session
  stopped, gets 403 or 409; no card appears, nothing reaches the sink and no
  grant comes back

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

### Per-peer settings (`test/peer_prefs_test.dart`, 13 tests)
- a name of your own covers the broadcast one without deleting it, and it
  survives the peer renaming itself; an empty string or a space brings the
  broadcast name back
- taking files without asking cannot be turned on for a peer whose identity is
  unconfirmed, and removing the confirmation turns it off. The database guards
  that, because it is the boundary of the user's consent
- three live transfers between two instances: a confirmed peer with consent
  gets the file through with no question asked; the same peer without consent
  still raises one; and the flag alone, with the shield gone, raises one too
- typing without a card (`peers.remoteInput`) is guarded the same way: it
  cannot be turned on for an unconfirmed peer, it can for a confirmed one, and
  removing the confirmation turns it off together with taking files

### Starting over after a lost key (`test/startup_error_test.dart`, 4 tests)
- the reset deletes the database, its journals and the key, and stops at the
  received files and the failure report
- it also survives a directory with none of those in it
- "Start over" opens a confirmation first, because the button throws away every
  conversation on the device
- another kind of startup failure has nothing to reset, and the button is not
  offered at all

### Migrations (`test/migration_test.dart`, 7 tests)
- a database with the current column layout and `user_version` rolled back to
  8, which is what a process killed between `ALTER TABLE` and the version
  write leaves behind; it has to open, keep its rows, and not throw
  `duplicate column name`
- the step from 11 to 12 keeps the peer, its address, its identity confirmation
  and its messages, and the settings row comes through with the Bluetooth
  add-on off and the network on
- the two roads to a peer do not wipe each other: the network address and the
  radio address sit side by side in the same row
- the step from 12 to 13 keeps the peer (its addresses, confirmation and
  taking files without asking), its messages and the settings, the Bluetooth
  add-on included, and brings the keyboard add-on, receiving and typing
  without a card in switched off
- the step from 13 to 14 keeps the messages and marks none of them as restored
- the step from 14 to 15 brings the Cisza style in and keeps the theme, the
  background and the nickname; a saved style comes back after reopening
- a 0.10.0 database (schema 13, with neither `restored_at` nor `style`) goes
  to 15 in one opening and keeps the peer, the message and the settings

### Styles (`test/style_test.dart`, 12 tests)
- each of the six variants (three styles, light and dark) carries its own
  tokens, its text font and its fixed-width font
- in each variant body text, secondary text, both bubbles, the primary button,
  the warning, danger and confirmation frames and the corner message reach at
  least 4.5:1, and a link on the other side's bubble and the time inside a
  bubble at least 3:1
- every variant has five walls and an avatar palette
- the unconfirmed identity warning is red in Cisza and amber in Precyzja and
  Ciepło
- every font a style names is declared in `pubspec.yaml`
- the unread counter in a list row is the size of its number in every style
  (it once stretched across the whole row and covered the name)
- a bare `MaterialApp` with no tokens falls back to Cisza
- the whole app switches style as soon as the database changes, fonts
  included, and the top of the conversation list carries the device name with
  no version number
- the style picker in Settings writes to the database, and the "This device"
  panel shows the fingerprint and the identifier in the fixed-width font and
  copies the identifier with a "Copied" message

### Sharing history (`test/history_test.dart`, 29 tests)
Two or three real instances over real sockets, paired, with a conversation both
ways and a file from each side. The recipient loses its history and the other
side hands it back:
- the shared history comes back with every direction flipped, the original
  times, both files (the recipient's own one included, from the sharer's
  received copy), incoming messages already read, `restoredAt` on every row,
  no notification, and nothing changes on the sharing side
- the card carries the counts, the bytes, the shield and the recipient's
  retention
- without files the file rows arrive without content; a received file that
  survived "Clear history" is linked at import and does not travel again
- sharing twice duplicates nothing and brings the files that were missing
- a refusal and silence on the card let nothing in; an empty conversation has
  nothing to share and a request for it comes back `empty` without a card
- after a "reinstall" (a new instance under a new identity) the older
  conversation is offered as a source, goes only once the new entry has a
  green shield (`needsVerified` before), arrives with the directions right and
  the files in place, and merges into the new conversation on the sharing
  side while the old entry stays on the device list
- a request shows a card on the asked side, and the offer that answers it goes
  in on the asking side without one; a refusal and "share without files" on
  the asked side do what they say
- the consent holds within the announcement: more messages or more files than
  announced is `over_limit` and nothing goes in, a wrong token or another
  history's identifier is `no_grant`, a chunk repeated under the same number is
  not counted twice, messages from the future and from before the recipient's
  retention are skipped, a second history while one is coming in is `busy`,
  and a cancel ends the grant while keeping what arrived
- a chunk number that already went in imports nothing new, whatever it carries
  the second time; a file announced once keeps its name and size; a message
  outside the date range on the card drops the whole chunk; a second card from
  the same sender is `busy`
- a history file offered under another name than its waiting row (a ".jpg"
  row taking an ".exe") is refused and the row stays empty, and a history file
  outside the grant is refused without ever raising the ordinary file card
- both routes answer plaintext with 409 and leave no trace, and a sealed body of
  the wrong shape with 400 and no card
- the parsers: a chunk goes in whole or not at all (a bad identifier, a bad
  time, a body or a file name over the limit, a negative size, file fields on a
  plain message, an empty chunk or one over 200), a summary whose numbers do
  not add up is dropped, an end without a token is dropped, and a reply that
  carries `from`, answers another history or another chunk does not count

### History on screen (`test/history_ui_test.dart`, 6 tests)
- restored bubbles carry the history icon and plain ones do not; the first
  bubble of each day gets "Today", "Yesterday" or the full date above it; a
  file row without content says "File not available" and offers no save
- the conversation's menu leads to the share dialog, which shows the counts
  and how many files would go without content
- the offer card shows the counts, the warnings (deleted messages come back,
  restored messages are marked, the identity is not confirmed, retention skips
  the older ones), no "without files" button, and has the focus on Reject
- the request card offers "without files" only when there are files
- the share dialog offers an older conversation as the source only for a peer
  with a green shield (without it, a note says why), and the merge option
  appears once an older conversation is picked
- the progress bars: both sides get Stop while it runs, another conversation
  sees nothing, and a finished restore shows the skipped count and closes

### Links in messages (`test/links_test.dart`, 25 tests)
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
- on Windows the address goes to the `chatt/links` channel whole, equals signs
  and fragment included (the shape from issue #31), the channel's "no" comes
  back as a failure, and without the channel nothing is started at all

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

### An attacker on the wire (`test/security_test.dart`, 22 tests)
- a message identifier carrying a path (`../../../../evil`, `..\..\evil`,
  `/etc/chatt`) is rejected in a file announcement, in a message and in the
  transfer headers; an ordinary UUID passes
- the path of a transfer part, of its description and of the target file stays
  inside the received directory **regardless** of what the sender sends
  (checked with `p.isWithin`, which returns false for `..`)
- two different identifiers do not collapse into one file
- an eight megabyte request does not take the server down, and `/info` answers
  afterwards
- a batch identifier is held to the same shape as a message identifier, because
  it is the key of a remembered consent
- a broken batch description means "no batch", never a refusal: the recipient
  falls back to asking per file, which is worse but never destructive
- a well-formed batch survives the round trip whole, and an announcement with
  no batch at all still looks exactly as it did before batches existed
- a keyboard packet off the network has a strict shape, and anything wrong
  drops the whole packet: text over 4096 units, a lone high or low surrogate,
  a control character, a tab, CR or an empty text; an unknown operation (`key`
  included); a Backspace or Delete run of 0 or 65; more than 256 operations,
  more than 4096 units of text or 4096 deletions in total; a `stop` anywhere
  but last; an `input` with a path or over 64 characters; a `seq` that is a
  fraction, a string or below 1; a token with foreign characters; a `pad` that
  is not a string. A valid packet with an emoji and a newline passes whole,
  and padding comes out at a multiple of 64 bytes
- a typing request keeps only `request` and `cancel` as operations and turns an
  unknown platform into none
- the server turns away a keyboard body over 32 KiB (413 on the radio path;
  over TCP the connection may close first, as on the other routes),
  answers plaintext junk and an unknown session with 409, and a sealed packet
  of a bad shape with 400 before anything reaches the sink; `/info` answers
  afterwards

### Resistance to a security downgrade (`test/downgrade_test.dart`, 4 tests)
The attacker knows a peer's identifier and has no private key for it:
- a plaintext message impersonating a known peer is rejected
- a plaintext file announcement from a known peer is rejected
- a plaintext transfer will not replace a file announced under encryption
- a plaintext typing request and a plaintext packet of typing operations get
  409; no card, no grant and nothing at the sink

The protocol itself defends against all four, because there is no plaintext in
it. The tests stay as a guard: a fallback unencrypted mode would turn them red.

### Framing over one Bluetooth link (`test/bt_link_test.dart`, 5 tests)
`lib/network/bt_link.dart` cuts requests into frames and runs several of them
down a single RFCOMM link. It sits on a `BytePipe`, so the whole layer is
driven in a test with no radio anywhere:
- a request and its reply make the whole round trip
- two exchanges at once do not mix into each other
- 70000 bytes go through a pipe that hands them over 7 bytes at a time
- a link that breaks ends a hanging request with an error
- a request to a side that has no handler for it comes back as 502

### The same framing over a real socket (`test/bt_socket_test.dart`, 3 tests)
The native side bridges an RFCOMM link onto a TCP socket on 127.0.0.1, so the
pipe the app actually uses is a socket. What sets it apart from the in-memory
pair above (packet boundaries, back-pressure, how a close arrives) is exactly
what broke on hardware, so it gets its own tests on the loopback:
- three exchanges one after another, with the link expected to survive each
  one; the first worked from the start, the second was what exposed a link
  that did not outlive its own reply
- 300000 bytes arrive byte for byte
- both sides open an exchange over the same link, because in Chatt every
  device is an equal

### The radio address (`test/bt_address_test.dart`, 3 tests)
A radio address is copied off a screen by a person, so it arrives in whatever
shape seemed reasonable at the time. Android accepts exactly one and throws on
the rest, so the flattening happens on our side:
- with colons, with dashes, with nothing and with spaces around it, all come
  out as `AA:BB:CC:DD:EE:FF`
- five bytes, seven bytes, a letter outside hex and an IP address all come back
  empty
- the "where it came from" field keeps a radio address and a network address
  apart

### The order of asking (`test/bt_probe_order_test.dart`, 2 tests)
A search over the radio asks the devices it saw one at a time, and every one
without Chatt costs seconds, so the order decides whether the computer next to
you shows up after five seconds or after a minute:
- computers and phones first, then devices that gave no class, then
  headphones, watches and the rest, each group in the order the radio saw it
- an address seen only over BLE is dropped: RFCOMM to it waits out the whole
  page timeout and never connects

### The Bluetooth add-on (`test/bluetooth_addon_test.dart`, 12 tests)
Bluetooth is an add-on, and an add-on that is off must not exist. The test
mocks the `chatt/bluetooth` channel, records every call that reaches it (with
the argument of `discoverable`) and sets `BtChannel.debugSupported`, so on the
Linux CI the add-on is the only thing keeping the channel silent:
- with the add-on off, asking for the radio state, starting the transport,
  searching, adding by radio address and showing the phone make no call to the
  channel at all
- a phone shows itself only on request and only with the radio running: a
  status with no visibility fields (Windows) offers nothing, an Android status
  does, `showThisDeviceNearby` makes exactly one `showSelf` call, the visibility
  the system granted shows up in the next status, and with the add-on off the
  call stays out of the channel
- the add-on raises the radio (state, listening, discoverability on) and polls
  for links; switched off, it turns discoverability off and stops listening,
  and after that no polling and no question reaches the channel
- switching the add-on off brings the network back, in the database as well:
  with the add-on on the network can be off, and after the add-on goes off
  `wifiEnabled` is true again
- without the add-on the network works whatever the database says: with
  `wifiEnabled` false in the database, a message still travels between two
  instances and is delivered
- a write to the database alone does not raise the radio: the add-on has one
  owner, `setBluetoothAddon`
- switching off while the radio is still coming up leaves it down, in memory,
  in the database and on the channel
- a quick "off, on" while the radio is coming up ends switched on everywhere,
  because the switch calls run one after another
- a radio turned on in the system brings the transport up on the next status
  refresh
- a native listener that died (the radio switched off and on in the system) is
  raised again from the poll loop, discoverability included
- an add-on saved in the database comes up with the app, the network switch
  included; on a platform with no native code the same database gives no
  add-on at all

### The add-on on screen (`test/bluetooth_addon_ui_test.dart`, 5 tests)
- the road mark takes no space with the add-on off, padding included, and
  shows once the add-on is on
- Nearby has no road picker with the add-on off; it appears with the add-on
  and goes away with it
- the add-on's card is a single switch while the add-on is off; the local
  network switch appears only with the add-on
- a peer known only over the radio shows no radio address with the add-on off
- **Show this phone nearby** stands in Nearby only on a phone, with the radio
  running and Bluetooth picked; a visible phone gets a note in its place, and
  a PC (no visibility fields in the status) gets neither

### The keyboard add-on (`test/keyboard_addon_test.dart`, 12 tests)
The add-on that is off must not exist, as with Bluetooth. The test mocks the
`chatt/remoteinput` channel, records every call with its arguments and sets
`RemoteInputChannel.debugSupported`, so on the Linux CI the add-on is the only
thing keeping the channel silent:
- with the add-on off, two instances starting, a request from a verified peer
  (refused, no card) and forged packets (403) make no call to the channel at
  all, and the receive switch cannot be turned on
- turning the add-on on makes exactly one call, `setImeEnabled(on: true)`;
  turning it off without a grant makes exactly `setImeEnabled(on: false)`
- turning it off during a grant ends the grant (`setSession(active: false)`,
  then `setImeEnabled(on: false)`), the sender's next packet bounces with
  `no_grant`, a new request hears `not_enabled`, and the channel goes quiet
- switching the add-on off writes receiving off in the database, and switching
  it on again does not bring receiving back; the receive switch with the add-on
  off writes nothing
- a database write alone raises neither the add-on nor a call to the channel
- quick "off, on", "on, off, on" and "on, off" sequences, with the first call
  held on the channel, end in the state of the last click in memory, in the
  database and in the order of `setImeEnabled` calls
- on a platform with no sink the add-on still turns on and its sender still
  types on another device, while receiving stays off and the channel silent
- an add-on saved in the database comes up with the app without a single call,
  and a verified peer then gets a grant

### The keyboard add-on on screen (`test/keyboard_addon_ui_test.dart`, 13 tests)
- the add-on's card is a single switch while the add-on is off; the receive
  switch appears with the add-on and goes away with it
- turning receiving on with the real switches shows the safety note; turning
  the add-on off removes both and writes receiving off
- a live grant from a second instance shows the "Typing: Alicja" bar above the
  app with Stop, and Stop ends the grant (the sender's next packet bounces)
- the bar names the app being typed into, Chatt itself included, and
  disappears with the add-on
- a file card puts the focus on Accept, and on Reject while someone types on
  this device
- the overlay shows no keyboard card with the add-on off, even when a verified
  peer asks; the conversation list and the conversation screen show no
  keyboard icon
- the conversation's keyboard button appears with the add-on, is active only
  with a confirmed identity, and goes away with the add-on
- on a phone the header holds neither search nor the keyboard: both are in the
  conversation's menu, and without a confirmed identity the keyboard item is
  greyed out with the reason under it
- the consent card names the device, holds the focus on Reject after a frame,
  and Enter refuses: the sender hears `rejected` and no grant exists
- Accept alone writes nothing; "Don't ask again" with Accept writes
  `remoteInput` for the sender in the database
- "Typing without asking" in the security sheet shows only with the add-on,
  writes `remoteInput`, and goes off and inactive when the confirmation goes

### The sender's screen (`test/remote_keyboard_screen_test.dart`, 28 tests)
Through a session without a network (`RemoteKeyboardLink`), which records what
the screen sends and lets the test set the state:
- `echoOps`: an append is text, a cut from the end is Backspace, a changed
  ending is both, an emoji from a surrogate pair counts as one character, no
  change sends nothing
- waiting for consent shows the device and Cancel; Cancel closes the screen
  and stops the session; a refusal at the start closes it with a message
- typing in the echo goes out as text and Backspace; Enter empties the echo
  and goes as the field's action, Shift+Enter as a newline
- Backspace on an empty echo and Delete delete on the other side; the arrows,
  Home and Tab change nothing and keep the focus in the field
- the echo is masked for a password and for a field of unknown kind, and only
  `field: text` uncovers it
- the status line explains a locked screen, an administrator's window, no
  field and `paused`
- a field of Chatt itself takes typing like any other
- a broken session leaves the field read-only with Reconnect, which asks
  again and lets typing go on
- too much text at once brings the echo back and says so
- Compose sends the whole text with an Enter and clears the field
- Paste from clipboard empties the echo and sends the clipboard's text
- a card on this device pauses typing: the screen takes the focus back from
  the card, Enter and Backspace send nothing, and the focus returns to typing
  after the card
- leaving the screen ends the session
- a password typed under the mask stays masked after the focus over there
  moves to an ordinary field, in both modes, until it leaves the field
- text the other side did not type leaves the echo, a second such packet in
  a row too, and a ping changes nothing; the field is read-only while paused
  and without a field over there
- Ctrl+V in the echo pastes from the clipboard
- a held Ctrl+Enter sends the whole text once
- a refusal that arrives after Cancel closes nothing more and shows nothing
- a screen still animating away does not end the session of the next one
- the next card from the queue does not keep the focus either
- Tab while typing is on hold stays in the field, so Enter cannot press Stop
- a mask change in Compose keeps the field focused and connected to the
  keyboard

### The remote keyboard (`test/remote_input_test.dart`, 51 tests)
Two or three live instances paired with each other, the receiver with an
in-memory sink. A request for a session:
- with consent, the operations reach the sink in order, Polish letters and a
  newline included; the sink's target comes back to the sender and to the
  receiver's indicator; an idle ping brings the target and types nothing
- with receiving off, with the add-on off on the receiver (even with the
  database saying otherwise) and from an unverified sender (whatever the
  settings) there is no card and no call to the sink; the shield removed on the
  receiver alone gives `rejected`
- the card: Reject, Accept and Accept with "don't ask again", after which the
  next session needs no card; `peers.remoteInput` set directly does the same;
  a policy that answers `noAnswer` ends the start as `noAnswer`
- the same request again gets the same answer and no second card: while the
  card waits it waits for the same decision, under a live grant it gets the
  same grant, after a refusal the same refusal, and after a grant that ended
  `rejected`
- two requests at once from one sender leave the newer one with a single card,
  and the older one ends as `noAnswer`, whichever of them reads the database
  first
- 520 requests from an unverified device under fresh ids do not push a
  verified sender's used id out: its recording still bounces
- a `cancel` uses the id up, so the same request arriving later bounces with
  no card; a `cancel` after an acceptance the sender never heard of ends that
  grant; a `cancel` from another device does not touch someone else's card;
  Stop while the card waits takes the card down and the start ends `cancelled`
- the same sender asking again replaces its own grant (the old token stops
  working) or its own waiting request; a second sender while a grant lives
  hears `busy` and gets its card once the first one stops
- a peer without these routes (a proxy answering 404, as 0.9.0 does) gives
  `olderPeer`; a receiver that closes with a card up does not leave the start
  hanging
- a grant nobody uses ends by itself once its idle clock runs out (shortened
  for the test), indicator included, and the sender's next packet hears
  `no_grant`

Packets:
- a repeated `seq` gets `duplicate` and types nothing twice; a lower `seq` gets
  `stale_seq` and the grant goes on; a wrong token or another `input` gets
  `no_grant` and the grant goes on
- a packet under another device's session, with the right token or with the
  holder's identity inside, is refused and the sink stays untouched
- a packet outside the grant is refused at once, while the holder's packet is
  still stuck in the sink
- a `stop` from the sender ends the grant and a replayed one does nothing; Stop
  on the receiver makes the sender's next packet bounce; a `stop` with an old
  token leaves a newer grant alone; a `stop` still gets through when the packet
  ahead of it fails on the way
- a 409 in the middle of a session (the receiver forgets the sender's session)
  ends in a new handshake under the same grant: the same token, `seq` carrying
  on, the text typed once
- a file offer or a pairing code waiting on the receiver pauses typing (the
  sender sees `paused`, nothing is typed) and typing comes back after it; pings
  keep reporting the pause while the card is up and leave "typed" as it was
- under a grant the sink hears `holdOwnApp` at once when a card starts waiting
  and when this device starts typing on another one, and again when that is
  over; outside a grant nothing goes
- after `forgetPeer`, the shield removed, receiving or the add-on switched off,
  or receiving written off in the database behind the service's back, the
  sender's next packet gets `no_grant` and the sink stays as it was

The sender's queue:
- what queues up while a packet is in flight goes out merged in one packet
- a paste longer than 4096 units splits into packets without breaking a
  surrogate pair; long text and long Backspace or Delete runs stay within the
  packet limits
- more than 65536 units waiting is refused whole; the text is cleaned before
  it leaves (CR LF, tab, control characters)
- one character, one Backspace, one Delete, an action, a ping and a `stop` all
  pad to the same 512 bytes, and so does every reply, with any kind of field
  and app names of 64 Chinese characters or emoji, cut without splitting a
  character

### The keyboard on the Windows desktop (`test/remote_input_desktop_test.dart`, 6 tests)
The native bar, the tray and the window are replaced by recorders:
- attaching gives the channel the field kind of Chatt's own window, and
  detaching takes it back
- a grant shows the bar and the tray badge with the sender's name, and the
  target's program name once there is one; the same text twice makes one call;
  the end of the grant hides both; a grant alone does not move the window
- with no texts yet nothing shows, and a language change shows the bar again
  in the new language
- a consent card pulls a hidden window out and hides it after the answer; a
  minimised one goes back to the taskbar; a window already on screen is left
  alone

### Chatt's own window on Windows (`test/remote_input_own_window_test.dart`, 2 tests)
- the focused field from the widget tree: a text field is `text`, an obscured
  one `password`, a read-only one and a button `none`, and so is no focus
- the channel puts that kind into the target only when the native side says
  `ownWindow` and the target is active; another program or another Chatt
  instance keeps the native answer, and so does a platform where the app sets
  nothing

### The keyboard on Android outside the app (`test/remote_input_mobile_test.dart`, 4 tests)
- a grant accepted on the card shows the bar text and asks for the keyboard
  picker once; the following packets only change the text; the end hides it
- a grant without a card while the app is in the background posts "Switch the
  keyboard to Chatt"
- a card arriving with the window closed gets one notification, and none
  while the app is in front
- the Chatt keyboard stepping aside for the lock screen's password field
  posts "Switch the keyboard to Chatt" during a grant, and nothing without
  one

## Scenarios on live hardware

### `tool/klawiatura_android_e2e_test.dart`
The Chatt keyboard on a live device: this process is the sender, the app on
the emulator or phone is the receiver, through the same adb tunnels as
`tool/android_e2e_test.dart`. With the add-on and receiving on in the app (the
script enables the keyboard itself with `adb shell ime enable`):
`flutter test tool/klawiatura_android_e2e_test.dart`. Eight steps, all
asserted: a request before pairing is refused with no card; pairing by code;
a request accepted on the card brings up the keyboard picker, Chatt is picked
and the app moves to the back; in a new contact form the text with Polish
letters, a Backspace and the field's action arrive (read back with
`uiautomator dump`); with the screen off the target says `locked` and nothing
is typed, and a lock screen without a password leaves the Chatt keyboard
current with no notification; on the emulator only, with a text password set
for the step and cleared after it, the Chatt keyboard steps aside on the lock
screen, the password unlocks the phone, and a tap on "Switch the keyboard to
Chatt" and on the Chatt keyboard in the picker brings it back; Stop on the
keyboard bar ends the session on both sides and the
previous keyboard comes back; Chatt's own message field takes the text (no
Enter, so nothing goes out) and the text is deleted again; switching the
add-on off takes the Chatt
keyboard off the system's list, and switching it on brings it back. Shared
helpers for the device scenarios live in `tool/uiautomator.dart`. With
`CHATT_SHOTS=1` the run also saves the pictures of `docs/keyboard.md` into
`docs/screenshots/android/` (`and23` to `and30`). It first turns the Chatt
keyboard on the way a user does, in the system's keyboard settings, and saves
the add-on's card and Android's warnings (the second one only when Android
shows it). The Contacts step then saves the keyboard picker and the Chatt
keyboard's bar while typing, the emulator-only password step the "Switch the
keyboard to Chatt" notification, and the step in Chatt's own message field
the consent card and the "Typing" bar in the app. The notification picture is
cropped to Chatt's two notifications only on a Windows host, with rows fixed
for the Pixel 9 Pro emulator (1280x2856), and on a phone the run saves no
`and30`. The sender is called "Office PC" then. Without the variable the run
changes nothing in the repository.

The run on the emulator (Pixel 9 Pro, API 37) found two things the unit tests
cannot: the navigation bar drawn over the keyboard bar, with the
keyboard-switch button on top of Stop, and a pairing reply that went nowhere
through the tunnel, because every request from the device rewrites the port
the host keeps for it (the script pairs host first and then pins the tunnel
port back). The password step found a third: a tap on the notification
opened Chatt, but Android dropped the keyboard picker it asked for
(`Ignoring showInputMethodPickerFromClient`), because the window's focus
reaches the input method manager only after the activity hears about it. The
picker now goes 300 ms after the focus.

### `tool/klawiatura_check.dart`
The `chatt/remoteinput` sink on a live Windows runner, with no consent and no
network: `flutter run -d windows -t tool/klawiatura_check.dart`. It prints the
target every second until Notepad (or the program in `CHATT_KLAWIATURA_CEL`) is
in front, then shows the floating bar, types `Chatt ąęł 124`, a Backspace, `3`,
Enter and `koniec`, and waits 30 seconds for Stop on the bar. Notepad has to
show two lines, `Chatt ąęł 123` and `koniec`; Stop prints `STOP`, hides the bar
and leaves Notepad with the focus. By hand at the same time: Chatt itself in
front gives `ownApp=true` and the kind of its focused field, Notepad run as
administrator `elevated=true`, a password field on a web page
`field=password`.

### `tool/klawiatura_e2e_test.dart`
The whole road on one PC: `flutter test tool/klawiatura_e2e_test.dart` is the
sender, and the Chatt app running next to it (keyboard add-on and receiving on,
port `CHATT_KLAWIATURA_PORT`, 47780 by default) is the receiver; a second
instance with its own `CHATT_DATA_DIR` keeps the everyday database out of it.
The script pairs by code (confirm "They match" in the app), asks for a session
(accept the card), waits up to a minute for Notepad to come to the front, and
sends text, Backspace, Enter and a 600-character paste, each packet only while
the target is `notepad.exe`. With `CHATT_ADMIN=1` it then waits for Notepad
run as administrator in front (the UAC prompt is yours to answer), sends
` ADMIN` and expects a refusal with `elevated`, and sends 3000 sevens into the
ordinary Notepad in one packet: bringing the administrator's Notepad to the
front halfway has to drop the rest (`applied: false`). Then it waits for the
Chatt window in front and checks that the target is `ownApp` and still open
to typing; with
`CHATT_W_CHATT=1` (a test instance only) it also waits for a click into a
Chatt text field, types `do Chatt` there and deletes it 10 seconds later.
Last, it waits for Stop on the floating bar; with `CHATT_STOP_W_TRAKCIE=1` it
first waits for Notepad again and sends 3000 fives in one packet, half a
minute of typing, for Stop to cut short. The app's
window, hidden in the tray, comes out for the cards and goes back after them;
the bar and the tray badge stay for the session.

The run on 16 October 2026 (Windows 11, the Windows 11 Notepad) found the pace
of typing wrong: with 1 ms between characters "Chatt ąęł 124" landed as
"Chatt 4444443". Now it types 10 ms apart and 40 ms after a space or Enter
(see the architecture), and the same run passes: the Polish line, the
Backspace, the 600 digits matching one for one (6.5 s), and Stop clicked on
the floating bar. (That run still refused with Chatt in front; Chatt's own
fields have taken typing since.)

The second run that day, with `CHATT_W_CHATT=1`, found that Chatt's own
window always reported `field=none` and froze for 400 ms on every ping
(`rtt=405ms` in the log): UI Automation asked the platform thread that was
waiting for its answer. The native side no longer asks about its own window,
Dart fills in the field from the widget tree, and the run passes: Notepad
exact as before, `do Chatt` typed into Chatt's search field and deleted
(`field=text`, `applied=true`), `rtt=7ms` with Chatt in front, Stop on the
bar.

A review of that change found that a long packet typed into Chatt's own
window could carry an Enter onto a file card that came up in the middle, and
that Stop let a packet already being typed run to its end. After
`holdOwnApp` and the Stop counter, the third run (`CHATT_W_CHATT=1
CHATT_STOP_W_TRAKCIE=1`) passes the same steps, and Stop pressed during the
3000 fives left 1494 of them in Notepad, the count still the same 5 seconds
later; the sender got `applied=false` and then `no_grant`.

The run with `CHATT_ADMIN=1` the same day: Notepad started as administrator
gave `elevated=true` and `active=false`, ` ADMIN` was refused at once
(`applied=false`) and its file stayed empty; the administrator's Notepad
brought to the front during the sevens left 994 of them in the ordinary
Notepad, the count unchanged 3 seconds later, and the packet's reply said
`applied=false`, `elevated=true`. A script cannot click an elevated window,
and Windows refuses to bring it to the front from a script without a key
press of its own first (a lone Alt does it).

### `tool/klawiatura_telefon_test.dart`
The keyboard on a phone someone uses every day: this process is the sender,
the Chatt app on the phone (over USB, `CHATT_DEVICE`) the receiver. It sends
no message and types only into a new contact form, checking before every
packet that the target is still that form; at the end it deletes what it
typed, closes the form without saving and puts the phone's keyboards back as
they were. Pairing goes through adb tunnels; with `CHATT_PHONE_IP` the session
and the measurements go over Wi-Fi straight to the phone. Steps: pairing by
code, consent on the card with the Chatt keyboard picked, text with Polish
letters, Backspace and an emoji in the form, then 30 seconds of idle pings,
100 characters one by one every 100 ms and 50 characters every 20 ms; then the
same session follows the focus through other apps (the Settings search, a new
calendar event's title, the contact form again), each field checked and
cleared; typing into Chatt's own search field, the lock screen (skipped with
`CHATT_BLOKADA=0`, otherwise it waits for you to unlock and types again
afterwards) and the end of the session. Error messages there give only the
number of nodes on the screen (`ukryjTrescEkranu` in `tool/uiautomator.dart`):
the screen of an everyday phone holds private conversations.

The runs on 16 October 2026: a Pixel 9 Pro with Android 17, first on 2.4 GHz
Wi-Fi (channel 6), later the same day on 5 GHz (channel 48, 5240 MHz, the
same network, a 585 Mbit/s link), the PC on Ethernet in the same network.
100 characters a run: three runs on 2.4 GHz, six on 5 GHz.

| What | 2.4 GHz p50 | 2.4 GHz p95 | 5 GHz p50 | 5 GHz p95 |
|---|---|---|---|---|
| a character, from sending to the answer | 28 to 29 ms | 34 to 39 ms | 28 to 30 ms | 33 to 38 ms |
| a character, the packet's exchange alone (the sender's `rtt`, three runs) | not measured | not measured | 28 ms | 32 to 37 ms |
| an idle ping, once a second | 67 to 110 ms | 137 to 170 ms | 77 to 123 ms | 152 to 450 ms |

Typing stays well under the 60 ms the plan allowed, and 5 GHz changes nothing
that matters: a character costs about 28 ms on either band, so the band is not
what limits it. The script's own waiting adds about 1 ms, so those 28 ms are
the packet's whole round trip, typing on the phone included. Fifty characters
queued 20 ms apart on 5 GHz went as 48 to 50 packets: nearly every answer came
back before the next character was due; at 100 ms a character every one went
as its own packet. The idle pings are slower because the phone's Wi-Fi dozes
between them; while you type, the radio stays awake. The first session took three taps on the phone (Accept, Chatt keyboard
in the picker, the field), and the lock screen showed the ordinary keyboard
with no Chatt bar. Within one session the typing went into the Settings
search, a calendar event's title and a contact form in turn, with no new
consent and no new picker. Typing over the radio is measured by the next
tool.

### `tool/klawiatura_bt_pomiar.dart`
The same measurement over Bluetooth. `flutter test` has no radio (the
`chatt/bluetooth` channel lives in the runner), so this one runs as a Windows
app: the sender with an in-memory database, the Chatt app on a phone on USB
the receiver, adb only for taps and for checking what is on the screen. It is
as careful with an everyday phone as the tool above: it sends no message,
types only into a new contact form after checking the target before every
packet, deletes what it typed, closes the form without saving, puts the
system keyboards back, and logs the number of nodes on the screen, never its
content. When the app's Bluetooth add-on is not listening (an RFCOMM socket
"Chatt" in `dumpsys bluetooth_manager`), it switches it on in the app's
settings and off again at the end. It reaches the phone at its radio address
only, pairs by code (it taps "They match" itself), accepts the card, picks the
Chatt keyboard, checks that the session goes over `bluetooth`, and measures
as the tool above: pings at rest for 30 seconds, 100 characters 100 ms apart,
50 characters queued 20 ms apart.

```
set ADB=C:\...\platform-tools\adb.exe
set CHATT_DEVICE=<id from adb devices>
flutter run -d windows -t tool/klawiatura_bt_pomiar.dart --dart-define=CHATT_BT_ADDR=<phone radio address>
```

The phone's radio address: `adb shell settings get secure bluetooth_address`.
With `--dart-define=CHATT_PHONE_IP=<address>` the same session goes over
Wi-Fi instead: the comparison with the same sender in the same process.

The runs on 16 October 2026: the same Pixel 9 Pro, the PC's built-in radio
next to it, three runs over Bluetooth and one over Wi-Fi (5 GHz) in the same
tool.

| What | Bluetooth p50 | Bluetooth p95 | Wi-Fi p50 | Wi-Fi p95 |
|---|---|---|---|---|
| a character, from sending to the answer | 70 to 78 ms | 187 to 243 ms | 28 ms | 34 ms |
| a character, the packet's exchange alone | 68 to 77 ms | 185 to 243 ms | 27 ms | 34 ms |
| an idle ping, once a second | 58 to 95 ms | 178 to 185 ms | 80 ms | 172 ms |

A character over the radio takes about 2.5 times as long as over Wi-Fi, and
one in twenty waits around 200 ms, which is visible while typing; the 60 ms
of the plan holds only for the network. Fast typing does not pile up: fifty
characters queued 20 ms apart went as 17 or 18 packets over the radio (0.34
to 0.36 a character, 2.2 to 2.3 s in all), because what comes in while a
packet is on its way leaves in the next one. Over Wi-Fi the same series went
one packet a character. At rest the radio is no slower than Wi-Fi: Wi-Fi
dozes between the pings, the radio link stays up.

### `tool/bt_rozmowa_check.dart`
A conversation over the radio, on real hardware. It raises the whole app stack
on both sides (its own in-memory database, server, client, transports),
switches the Bluetooth add-on on in that database and pushes a message and a
file through Bluetooth, with the handshake and the
encryption that normally go over the network:

```
cd app
flutter run -d windows -t tool/bt_rozmowa_check.dart --dart-define=CHATT_BT_ROLE=serwer
flutter run -d <device> -t tool/bt_rozmowa_check.dart --dart-define=CHATT_BT_ROLE=klient
```

`CHATT_BT_ADDR` skips the search and goes straight to an address. That matters
more than it sounds: searching and carrying bytes break separately, and Android
hands out no discovery results at all while location services are off, whatever
permissions the app holds. `CHATT_BT_VERBOSE=true` prints every frame and the
reason each link ended, on both the Dart and the native side.

Against the real app on the other side, a file waits for somebody to tap
**Accept**, and after two minutes with no answer it ends as not delivered. The
script receives without asking and the app asks every time, so a "failed"
file at 2 kB/s after exactly 120 s means an unanswered question; the radio is
fine.

The script touches none of the user's data: the database lives in memory, the
received files go to a temporary directory, UDP discovery is off and the server
takes a port from the system. It can run next to an ordinary Chatt.

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
`CHATT_SHOTS_LANG=en` gives the English version, `CHATT_SHOTS_STYLE=precyzja`
(or `cieplo`) another style, and `CHATT_SHOTS_DIR` sends the pictures
somewhere other than `docs/screenshots/windows/`. One trap: the harness replaces
`HttpClient` with a fake answering 400, so the script restores the real one
(`HttpOverrides.global = null`). Three more tests, run alone with
`--plain-name klawiatury`, take the keyboard add-on for `docs/keyboard.md`:
the sender's screen typing to a phone (06); the keyboard button in the
conversation (09), "Typing without asking" in the security sheet (10) and
the sender's screen in every state, driven by a link the test controls
(waiting 11, a password field 12, Compose 13, paused 14, an administrator's
window 15, the link dropped 16); and the consent card on this PC (07) with
the "Typing" bar over the add-on's card (08). They do all their networking
before `pumpWidget`: a request sent under the harness's fake clock can fail on
a pooled connection, though the same run outside the harness takes
milliseconds. Before every capture the script repaints every node with
shadows on (cards in scrolled lists sit on layers of their own and kept the
outline the harness draws while shadows are off), and it loads every font
family `pubspec.yaml` declares, the three styles' fonts and the icons, because
the harness loads none by itself. The floating bar (17) is the one
picture taken from the live desktop: `GetWindowRect` of the
`ChattRemoteInputBar` window during a session, cropped to the bar alone.

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

- **Typing into a real field.** `flutter test` has no native side, so
  `SendInput` on Windows and the Chatt keyboard on Android are never reached
  there. The Android side is covered by `tool/klawiatura_android_e2e_test.dart`
  on an emulator; the Windows side by `tool/klawiatura_check.dart` and
  `tool/klawiatura_e2e_test.dart`, run by hand.
- **The keyboard over a real Bluetooth link**, for the same reason as any other
  Bluetooth traffic.
- **The keyboard's 8-hour limit, the card's two-minute timeout and the cap of
  8 waiting requests**: no test waits that long or raises nine cards. The idle
  clock has a test of its own, with a shortened duration.

- **Router behaviour**: client isolation on a guest network, broadcasts between
  the 2.4 and 5 GHz bands, masks other than /24 (the scanner computes the
  broadcast address as if for a /24 and adds the global 255.255.255.255).
- **A Bluetooth link between two devices**: CI has no radio, so `flutter test`
  never opens one. The framing is checked over a pipe, and the link itself is
  checked by hand on two machines at release time.
- **Bluetooth listening with the screen off** on Android: nobody has put the
  foreground service through that on hardware yet.
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
- **Handing a file to another app on Android**: whether FileProvider accepts a
  path depends on `res/xml/file_paths.xml` against the real directories the
  system hands the app, and no test sees either. At release time, on a phone:
  send a photo from the picker, from the clipboard and from the keyboard, then
  tap each one in the conversation and use "Share" on each one. All six have
  to work; before 0.8.2 all six failed with "Could not open the file."
- **What a broken image looks like in the preview**: in the test environment
  the image decoder never finishes, so neither the picture nor `errorBuilder`
  ever reaches the view. `image_view_test.dart` checks that the screen stands
  and that the error handler is wired; that it actually says "Could not load
  the image." is checked by hand, by renaming a text file to `.png` and
  sending it.
