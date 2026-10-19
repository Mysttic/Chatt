# Architecture

A document for someone about to change something in this code. The user guide
is in [guide.md](guide.md), and the build commands are in
[building.md](building.md).

## The shape

There is no server, so **every copy is a client and a server at the same
time**. Each device hosts a small HTTP server (`shelf`) and answers UDP
broadcasts. That server is reachable over two roads: a TCP socket on the local
network and a Bluetooth Classic (RFCOMM) link. Both can be on at once.

A device's identity is an **X25519 key pair**. The identifier (`guid`) is
derived from a hash of the public key, so it cannot be claimed without the
matching private key: whoever announces a foreign identifier will not finish
the handshake. Everything (conversations, sessions, deduplication) hangs off
the identifier; the address is only a hint about where the device was last
seen. There are two kinds of address now, an IP one and a radio one, and both
are hints.

## Layers

```
lib/
  core/      identity, cryptography, platform channels, environment overrides
  data/      SQLite schema (drift) and queries
  network/   protocol, UDP discovery, server, transports (HTTP, Bluetooth), client
  services/  AppServices, the root that ties everything together, plus Riverpod providers
  ui/        screens and widgets
```

**`AppServices`** holds the database, the server, the client and the discovery
responder, and decides what to do with every incoming request. It also picks
the road to a peer, which is the subject of the next section.
`AppServices.start()` builds a complete, self-contained stack, so tests can
bring up two of them in one process and make them talk over a real socket (see
[testing.md](testing.md)).

The UI does not talk to the network. Screens read **streams from the
database**, so every change reaches the view by itself. The exceptions are
things that are not in the database because they are transient: transfer
progress and consent requests, which travel through a `ValueNotifier`.

## Transports

`PeerClient` used to take a host and a port and open an HTTP connection. A radio
link has neither, so "how do I reach you" was pulled out into
[`network/transport.dart`](../app/lib/network/transport.dart): `PeerProtocol`
(`wifi`, `bluetooth`), the sealed `PeerRoute` (`IpRoute(host, port)`,
`BluetoothRoute(address)`), `TransportReply` (an HTTP-shaped status plus a body,
where `-1` means the request never left) and the `PeerTransport` interface
(`request`, `stream`, `handles`, `dispose`). `PeerClient` takes a route and
hands it to the transport that claims it; serialisation and reply codes are
unchanged.

- [`http_transport.dart`](../app/lib/network/http_transport.dart) is the old
  `PeerClient` code under the new interface, with the same timeouts and the same
  way of streaming a file.
- [`bt_transport.dart`](../app/lib/network/bt_transport.dart) is `BtChannel`
  (the Dart side of the `chatt/bluetooth` channel) plus `BluetoothTransport`,
  which keeps one link per peer.

### The Bluetooth add-on

Everything below sits behind one switch: the Bluetooth add-on in the
**Add-ons** section of Settings (`settings.bluetoothEnabled`, off by default).
`AppServices.bluetoothAddon` is the single gate and `setBluetoothAddon` its only
writer; the rules it shares with the keyboard add-on are in
[Add-ons](#add-ons). With the add-on off:

- no transport is started, so nothing listens on RFCOMM and a PC stays
  undiscoverable;
- the `chatt/bluetooth` channel receives no call: `refreshBluetoothStatus`,
  `scanBluetooth`, `addPeerByBluetooth` and `startBluetooth` return before they
  reach it, and the native side only registers the channel. The one exception
  is the switch itself while it is being turned on: it checks and asks for the
  permission (`refreshBluetoothStatus(force: true)`,
  `askForBluetoothPermission`) before the add-on is on;
- the network is the only road and is always on: `client.useWifi` ignores
  `settings.wifiEnabled`, and switching the add-on off writes
  `wifiEnabled = true` back in the same update;
- no screen shows any of it: Nearby has no road picker and no add by radio
  address, and the conversation list and header carry no road mark
  (`ProtocolBadge` takes no space, its padding included).

The add-on's card holds what belongs to it: the radio and permission state, the
radio's own address, the discoverability notice on Windows and the local network
switch (`settings.wifiEnabled`), which counts only while the add-on is on.
Android asks for the Bluetooth permissions when the add-on goes on, and again
only from the card's button after the permission was taken away; that button
opens the app's page in system settings, where a permanently refused permission
can still be granted. The manifest declares the permissions because Android
offers no other way. `setBluetoothAddon` runs its calls one after another, and
the settings watcher drives the network switch alone, so neither a quick "off,
on" nor a late event from the database can leave the radio in a state nobody
asked for.

With the add-on on, a transport that could not start (radio off, no
permission) is retried every 10 seconds and on every `refreshBluetoothStatus`,
and a running transport whose native listener died (the radio switched off and
on in the system) raises the listener again from its poll loop, at most every
5 seconds. Switching the add-on off also cancels a radio search in progress; on
Windows the inquiry already under way cannot be aborted and runs out within
about 8 seconds, with its results thrown away. On Windows, switching off turns
discoverability off and leaves the radio's incoming connections as they were.

`BtChannel.debugSupported` lets `test/bluetooth_addon_test.dart` pretend to be a
platform with native code, so the silence of the channel is checked on the
Linux CI as well.

### Picking the road

`AppServices.routesOf(peer)` returns the routes in the order they are worth
trying: the one that worked last, then the network, then Bluetooth.
`_overRoutes` walks that list until one answers and remembers the one that did.
The network goes first because it is tens of times faster; the measurements are
in [spike-rfcomm.md](spike-rfcomm.md). The fallback is automatic, so there is
nothing to switch per peer. A short message over the radio is indistinguishable
from one over Wi-Fi; files are where the difference shows.

### The radio link is bridged to 127.0.0.1

The native code does not carry bytes over the method channel. It bridges the
RFCOMM link onto a TCP socket on `127.0.0.1` and pumps bytes between the two, so
Dart is handed an ordinary `dart:io` `Socket`. The reason is threading: the
result of a `MethodChannel` call may only be returned from the platform thread,
so a byte pump through the channel would block the interface. Every channel call
returns at once, and the things that take time (listening, connecting, scanning)
report back through `linkPoll`, polled every 500 ms, and `scanResults`, polled
every 700 ms during a search.

| Platform | Implementation |
|---|---|
| Android | [`ChattBluetooth.kt`](../app/android/app/src/main/kotlin/com/mysttic/chatt/ChattBluetooth.kt): `listenUsingInsecureRfcommWithServiceRecord` and `createInsecureRfcommSocketToServiceRecord` |
| Windows | [`chatt_bluetooth.cpp`](../app/windows/runner/chatt_bluetooth.cpp): Win32 Winsock `AF_BTH` / `BTHPROTO_RFCOMM`, the SDP record written with `WSASetServiceW`. WinRT is out: it wants C++20 and exceptions, and the runner has both off |

The service record carries our own UUID,
`c4a1f7d2-5b3e-4f1a-9c8d-6e2b0a7f3d51`. SPP is out: it is shared with every
USB-to-serial bridge and every Windows COM port.

With the add-on on, Windows raises the radio's discoverability itself
(`BluetoothEnableDiscovery` plus `BluetoothEnableIncomingConnections`), because
by default the machine is visible only while the "Add a device" window is open.
It goes down again when the add-on goes off.

### One link, several exchanges at once

[`bt_link.dart`](../app/lib/network/bt_link.dart) does the framing and the
multiplexing over that single link. A frame is `[1 byte kind][4 bytes stream
number][4 bytes length][payload]`, the kinds are `head`, `body`, `end`, `reply`
and `abort`, and a payload holds at most 8192 bytes. The side that dialled
numbers its streams odd and the side that answered numbers them even, so two
exchanges in flight cannot claim the same number. It is plain Dart over a
`BytePipe` abstraction, which is what makes it testable without a radio.

### Both roads end at the same handler

`ChattServer` builds one handler (a `shelf` `Pipeline` and a `Router`) for both
transports and exposes `handleBluetooth(BtRequest, peerAddress)`. A request off
the radio walks exactly the path a request off the TCP socket walks: the same
endpoints, the same handlers, the same error wrapper. One thing differs, and it
is "where it came from": an IP address on one road, the radio address behind the
`bt:` prefix (`btHostPrefix` in `transport.dart`) on the other.

### Finding a device over the radio

The radio cannot say who is running Chatt. Android runs an inquiry, Windows
`BluetoothFindFirstDevice` with `fIssueInquiry`, and the question is settled by
connecting on our UUID and asking `GET /info`, the same way it is settled when a
device is added by IP by hand. Devices without Chatt fall away, because they
carry no such record in SDP. A scan jams the link for as long as it runs, so it
happens only when the user asks for it from the "Nearby" screen.

## Add-ons

Settings has an **Add-ons** section for features most users can do without, so
each one is built to cost nothing while it is off. There are two:
[Bluetooth](#the-bluetooth-add-on), a second road, which is described under
Transports, and [the keyboard](#the-keyboard-add-on). Both follow the same
rules:

- **one switch** in Settings → Add-ons, off by default and stored in `settings`
  (`bluetoothEnabled`, `keyboardEnabled`);
- **one gate in memory**, a `ValueNotifier<bool>` on `AppServices`
  (`bluetoothAddon`, `keyboardAddon`), read from the database at start;
- **one writer** (`setBluetoothAddon`, `setKeyboardAddon`), which runs its
  calls one after another, so a quick "off, on" ends in the state of the last
  click, in memory, in the database and on the native side alike;
- **a database write alone never raises the gate**: no settings watcher
  touches it, so a late event from the database cannot bring an add-on back
  after it was switched off;
- **while it is off, no screen other than its own card shows it**, and its
  native channel (`chatt/bluetooth`, `chatt/remoteinput`) receives no call. The
  one exception is the switch itself while it is being flipped: Bluetooth
  checks and asks for the permission, the keyboard turns its system keyboard
  component on or off.

### The keyboard add-on

A PC's keyboard types into the field that has focus on another device, in any
app. The use is servicing devices with no physical keyboard: an Android phone
or tablet, or a Windows PC run by touch and an on-screen keyboard alone (a
tablet, a kiosk, a 2-in-1 without its keyboard). The user points at the field
on that device with a tap or a click, and the PC types into it. The MVP covers
Windows → Android and Windows → Windows.

What travels is text (Unicode, Polish letters, a newline), Backspace, Delete
and the field's action: Enter, and on Android the field's own Search, Send, Go,
Next, Previous or Done. A paste from the sender's clipboard is ordinary text to the
protocol, split into packets when it is long. Shortcuts with Ctrl, Alt or Win,
Tab, Esc, the arrows, Home and End, the mouse and anything that reads from the
receiving device are out of scope. The sender learns only what typing needs:
the kind of field, its action, the app's name and whether the receiver can type
at all.

The sender types on its own screen, opened from the conversation with the
receiving device. The receiver types with `SendInput` on Windows and with the
Chatt keyboard on Android. Issue #35 holds the plan and its phases.

The logic lives in
[`services/remote_input.dart`](../app/lib/services/remote_input.dart), a `part`
of `app_services.dart`, so it uses the sessions, envelopes and routes without
making them public; `AppServices` only delegates. The channel is
[`core/remote_input.dart`](../app/lib/core/remote_input.dart).

#### Two switches

The add-on alone lets this device type on others. Being typed on takes a second
switch in the add-on's card, "Allow typing on this device"
(`settings.remoteInputReceive`), also off by default: turning the add-on on at
the PC that types lets nobody type on that PC. The switch goes on only with the
add-on on and on a platform with a sink, Android or Windows. Turning the add-on
off writes `remoteInputReceive = false` in the same update (`saveKeyboardAddon`),
so turning it on again does not quietly bring receiving back.

Turning the add-on off closes the gate first, then withdraws the waiting
requests, ends the grant and this device's own typing session, writes the
database, and only then switches the system keyboard component off. Turning
receiving off withdraws the requests and ends the grant at once. Both go
through `AppServices` (`setKeyboardAddon`, `setRemoteInputReceive`), because
only the service knows the grants and the waiting cards.

#### Consent

A request for a session passes these gates, in this order:

1. the sender is known and **verified** here (the green shield). Anyone else
   hears `rejected`, whatever the settings say;
2. the request id (`input`) was never used by this sender before. The ids are
   remembered per sender, the last 512 of each, and only from verified
   senders, so nobody can push another device's ids out with a flood of their
   own. A repeated id raises no second card: while the first copy waits for the
   card it gets the same answer once there is one, while its grant lives it gets
   the same grant again, and after that `rejected`. A request repeated over the
   second road, because the first one broke down during the card, is answered
   that way, and a recording replayed by somebody else learns nothing it could
   open;
3. the add-on is on in memory, `keyboardEnabled` and `remoteInputReceive` are
   true in the database, and there is a sink; otherwise `not_enabled`;
4. no other device holds a live grant and fewer than 8 requests are waiting;
   otherwise `busy`;
5. the card, unless this sender has "don't ask again".

The card puts the focus on **Reject**. It appears while someone may be typing
in another field, so an Enter pressed at that moment can only refuse, and
accepting takes a deliberate click. Two minutes of silence end as `no-answer`.
Anything can change while a card waits, so after the answer the shield, both
switches and the other device's grant are checked again.

"Don't ask again" is per device, `peers.remoteInput`, and is guarded like
`autoAccept`: the database sets it only for a verified peer
(`setPeerRemoteInput`), and `setPeerVerified(false)` clears it together with
the shield. The card sets it with its "Don't ask again for this device"
checkbox (`respondToRemoteInput(remember: true)`), and the security sheet of
the conversation shows it as "Typing without asking", next to the files'
switch: visible only with the add-on on, active only with the green shield.

#### Endpoints

Both routes sit in the shared `Router`, so they answer over TCP and over the
radio alike.

```
POST /input-session   { from, op: "request", input, platform }
  200  { reply: "input-session", ok: true, accepted: true, input, token, target }
  403  { reply: "input-session", ok: false, accepted: false, input, reason }

POST /input-session   { from, op: "cancel", input }
  200  { reply: "input-session", ok: false, accepted: false, input, reason: "cancelled" }

POST /input           { from, input, token, seq, ops }
  200  { reply: "input", ok: true, input, seq, applied, duplicate?, reason?, target }
  403  { reply: "input", ok: false, input, seq, applied: false, reason }
```

Every request and every reply above travels in an envelope and carries `pad`
as well. `from` carries the sender's guid and TCP port, with an empty name,
an empty greeting and no key: the receiver checks only who owns the session and
knows the rest from its database, so the length of a packet does not depend on
what the sender called itself.

A `cancel` uses up the request id, takes the card down and ends a grant already
given to that request, which its sender never learned of. A request that
arrives after its own `cancel`, over a slower road, is refused without a card.

- `input` is drawn by the sender, a UUID v4; its shape is letters, digits and a
  hyphen, up to 64 characters. `platform` is the sender's system, for the card.
- `token` is drawn by the receiver when it accepts (`newSessionId()`, 16 random
  bytes in base64), and every packet carries it.
- `seq` starts at 1 and grows by one with every packet.
- `target` is the state of the field with focus: `active`, `field` (`text`,
  `password`, `none`), `action` (`search`, `send`, `go`, `done`, `next`,
  `previous`, `none`), `app` (a package on Android, the program's file name on
  Windows), `appLabel` (the app's label on Android, the program's name on
  Windows, from the version resource or else the file name) and the flags
  `ownApp`, `locked` and `elevated`. A window title is never sent: it carries
  content (a document's name, a mail's subject, a page's title), and reading
  content from the receiving device is out of scope.

| Operation | Meaning |
|---|---|
| `{"t":"insert","s":"…"}` | text, 1 to 4096 UTF-16 units, no control character other than `\n` (so no tab either), no lone surrogate |
| `{"t":"bs","n":1}` | Backspace, `n` from 1 to 64, counted in code points, so one `bs` removes a whole emoji |
| `{"t":"del","n":1}` | Delete, counted the same way |
| `{"t":"action"}` | the field's action; on Windows always Enter |
| `{"t":"ping"}` | types nothing; the reply brings the current target |
| `{"t":"stop"}` | ends the grant after the rest of the packet; allowed only as the last operation |

A packet holds at most 256 operations, 4096 units of text and 4096 deletions in
total. The server reads at most 32 KiB of body on these two routes
(`maxInputBodyBytes`), so an oversized packet is refused (413) before
anything is decrypted. A full packet
of 4096 three-byte characters takes more than 16 KiB once sealed and encoded in
base64, hence 32.

| `reason` | Who can hear it | When |
|---|---|---|
| `rejected` | any sender | it is unknown or unverified here, the request id was used before, or the user pressed Reject |
| `not_enabled` | a verified sender | the add-on or receiving is off, or the platform has no sink |
| `busy` | a verified sender, receiving on | another device holds a grant, or 8 requests are waiting |
| `no-answer` | a verified sender, receiving on | the card ran out of time, the request was withdrawn or replaced, or the app closed |
| `cancelled` | the sender itself | the answer (200) to its own `cancel` |
| `no_grant` | any sender with a session | `/input` with no grant, another sender's or another request's grant, a wrong token, an expired grant, or a gate that fails the database check |
| `stale_seq` | the grant's holder | `/input` with a `seq` below the last one |
| `paused` | the grant's holder, with 200 | `/input` while a card waits on the receiver; nothing typed |

These are the first sealed replies in the protocol. A 200 and a 403 travel
sealed with the key of the session the request came in, refusals included, so
nothing in the clear says whether the add-on is on. In the clear stay the
answers given before a key or a sender is known, and those that say nothing
about the add-on: 409 `no_session` (an unknown or expired session, an
envelope that does not open with its key, a session that now belongs to
somebody else, or a body without an envelope), 404 (a version
without these routes), 400 (a bad shape once the envelope is open, or a request
carrying this device's own identity), 413 and 500 (the error guard).

A sealed reply carries `reply` and never `from`. The sender registers its own
session under the same number and the cipher marks no direction, so `from` is
what tells a request from a reply: a reply bounced back to the sender's own
server fails `_openEnvelope`, and the sender opens replies with a separate
function (`_openSealedReply`) that drops anything carrying `from`.

Every payload, both ways, is padded with `pad` to at least 512 bytes of JSON
and above that to a multiple of 64 (`padInputPayload`). AES-GCM keeps the
length of what it seals, and without the padding the size of an envelope would
give away what was typed and the app's name in the reply. With it, a single
character, a single Backspace and a ping come out the same length, and every
reply fits in 512 bytes whatever the field and the app: `app` and `appLabel`
are cut to 96 bytes of JSON each, whole characters only, so a long name in
Cyrillic or Chinese stays within the budget as well.

The protocol version stays at 5: the routes are additive, and a peer without
them answers 404, which the sender reports as an older version of Chatt
(`RemoteInputStart.olderPeer`). `GET /info` carries no capability flag, so the
add-on's state reaches a verified sender alone, through a sealed
`not_enabled`.

#### Grant, token and seq

The receiver's consent is a grant, held in memory only and bound to (sender,
`input`, `token`). It outlives the crypto session: a re-handshake after a 409
always brings a new session number, and typing goes on. A grant ends at a
`stop` from either side, when the add-on or receiving is switched off, when the
sender is removed from the list (`forgetPeer`), when the app closes, after 30
minutes without typing (pings do not count) and 8 hours after it was given.
A timer looks at both clocks every 30 seconds, so a grant whose sender went
quiet (closed, asleep, out of range) ends by itself, the indicator with it;
every packet and every request checks them as well. There is one grant per
device.

- A packet without the grant's token, from another sender or for another
  `input` gets 403 `no_grant` at once and leaves the current grant alone, so a
  recorded packet from an earlier session cannot end the present one. It does
  not wait in the packet queue either, so how fast it is refused says nothing
  about whether somebody is typing. The token is compared in constant time
  (`ChattCrypto.sameTag`).
- A `seq` equal to the last one gets 200 with the cached reply and
  `duplicate: true`, and nothing is typed a second time. This is how a packet
  retried after a timeout lands once.
- A `seq` below the last one gets 403 `stale_seq`, and the grant stays.
- A 409 in the middle of a session makes the sender shake hands again and send
  the same payload once more, with the same `seq` (`_exchangeSealed`).

The request walks the routes like any other (`_overRoutes`), and a sealed
answer ends the walk, a 403 included: a refusal over the network does not
travel again over the radio and raise a second card. A 409 or a 404 ends it as
well, since Chatt answered. The route that answered carries every packet of the
session; only the last-resort `stop` after a broken link walks the routes. Over
the radio
`BluetoothTransport` triples the reply limit, so a packet there waits about
6 seconds.

#### The sender

- `startRemoteInput(peer)` needs the add-on on (`addonOff`) and the peer on
  the list and verified on this device (`notVerified`): typing includes
  passwords, so it goes only to a device whose identity was confirmed here. An
  earlier session is replaced at once, its `stop` or withdrawal going out in
  the background, so a new request never waits behind the retries of a dying
  link. The answer may take 150 seconds over the network, the card's two
  minutes plus the road, and three times that over the radio, like every
  Bluetooth request.
  A request that got no answer at all is withdrawn: the card may still be up
  on a device the link no longer reaches, and an acceptance there would
  otherwise turn into a grant nobody uses.
- `sendRemoteInput(ops)` cleans the text (`typableText`: CR LF and CR become
  LF, a tab becomes a space, other control characters and lone surrogates go)
  and queues it. It refuses, queueing nothing, without an active session or
  when the queue would pass 65536 units of text.
- **One packet in flight.** What queues up meanwhile is merged: text with text,
  Backspace with Backspace, Delete with Delete, and different kinds keep their
  order. A packet takes what fits the limits: a Backspace or Delete run over
  64 becomes several operations of at most 64, and text over 4096 units or
  deletions over 4096 in total carry on in the next packet. Text is never cut
  inside a surrogate pair.
- A packet gets 2 seconds. Without an answer the same payload goes again with
  the same `seq`, three attempts in all. A 403 ends the session
  (`disconnected`, with `reason` `no_grant` or `stale_seq`); any other failure
  ends it with no reason, which means a broken link. There is no relocation
  and no switch to another road.
- **A ping every second while idle** keeps the keep-alive connection open (the
  HTTP client closes an idle one after 15 seconds) and brings back the current
  target.
- `stopRemoteInput()` clears the state at once, sends what is still queued and
  then a `stop`. While the answer is still pending, it withdraws the request
  (`op: "cancel"`) and the card on the receiver disappears; an acceptance that
  arrives after that is answered with a `stop` at once. When the link breaks
  before the `stop` leaves the queue, one more `stop` goes out on its own over
  every road (the remembered one may be the very road that went down), so the
  receiver does not wait half an hour.
- `outgoingRemoteInput` holds the state (`waiting`, `active`, `paused`,
  `disconnected`), the last target, whether the last packet was typed, the
  round trip and the road. Typed text lives in the fields of the sender's
  screen, the sender's queue and the packet, and, with the typing history
  on, in the [typing history](#typing-history) of both sides, in the
  encrypted database. It reaches no app log and no other state of the
  service.

#### The sender's screen

[`RemoteKeyboardScreen`](../app/lib/ui/screens/remote_keyboard_screen.dart)
opens from a keyboard button in the conversation's bar. The button exists only
with the add-on on and is active only with the green shield. The screen is a
route of its own over the whole window, two-pane layout included, with a field
of its own: in the conversation's field Enter sends a message.

- **The session lives as long as the screen.** Opening it asks for the
  session and shows "Waiting for consent on X" with Cancel. A refusal closes
  the screen with a message naming the reason (declined, typing off there,
  no answer, someone else typing, an older Chatt, unreachable). The session
  ends, or the request is withdrawn, the moment the screen is popped, once:
  a screen still animating away cannot end the session of the next one, and
  a refusal that arrives after Cancel closes nothing else. A session that
  ended (Stop on the other side, a broken link) keeps the screen with
  Reconnect.
- **Live mode** types as you go. Its field is an echo of what went out since
  the last Enter: the cursor is pinned to its end, selection is off, and so
  are suggestions, autocorrect, the keyboard's learning and the undo
  shortcuts. A change of the echo goes out as the difference (`echoOps`): the
  common beginning stays, the rest of the old text goes as Backspace counted
  in code points, the rest of the new one as text. A character the keyboard is
  still composing (a dead key, an IME) goes once it is done, and the field is
  left untouched until then: moving the cursor in the middle of a composition
  breaks it on Windows. Enter sends the field's action and empties the echo,
  Shift+Enter sends a newline, Backspace on an empty echo and Delete go to the
  other side, Ctrl+V and Shift+Insert paste like the button, and Tab, the
  arrows, Home, End, PgUp and PgDn do nothing, so the focus and the cursor
  stay where they are, also while typing is on hold (a Tab there would put
  the focus on Stop, and the next Enter would press it).
- **Typing goes only where it can land.** The fields are read-only while the
  session is paused, while the other side has no field, is locked, has Chatt
  or an administrator's window in front, and while a card waits here. An
  answer saying the last text was not typed (`applied: false`) empties the
  echo, every such answer, also the second in a row (`typedReplies` counts the
  answers to typing packets): an echo holding text that never landed would
  turn the next Backspace into deleting somebody else's text over there.
- **Compose mode** sends a whole text with Send (or Ctrl+Enter, once per
  press), with an optional Enter after it; it is the only mode where the
  timing between characters does not travel. Its undo shortcuts are off too,
  so a sent password cannot come back with Ctrl+Z.
- **Paste from clipboard** sends the clipboard's text as typed text, in either
  mode.
- **The echo is masked** until the last answer says `field: text`: a password,
  or a field of unknown kind, shows dots. Text typed under the mask stays
  masked until it leaves the field (Enter, Send, a mode switch), even when the
  focus over there moves on to an ordinary field.
- **The status line** says where the typing goes ("Typing into: Notes",
  "· password field") or why nothing gets typed: a locked or dark screen, an
  administrator's window, no field, a card waiting over there (`paused`). With the Bluetooth add-on on it shows the road, and
  always the round trip.
- **A card on this device** (a file offer, a pairing code, a typing request)
  stops the typing, and the status line says so. A card takes the focus a
  frame after it shows (Accept, for a single file), while the person typing
  looks at the other device, so the next space or Enter would answer it
  unread: the screen takes the focus back to its read-only field, for every
  card that shows, the next one from the queue included, and the card is
  answered with a click. The focus returns to typing when the cards are gone.

#### The receiver

- Packets of the current grant go through one queue, one at a time. Without
  it a retried packet that arrived while the first was still being typed would
  pass the `seq` check alongside it, and the text would land twice.
- Every packet reads the database again: the sender still verified,
  `keyboardEnabled` and `remoteInputReceive` still true. A failure ends the
  grant with `no_grant`, so consent withdrawn anywhere ends typing at the next
  packet.
- **Nothing is typed while any card waits** on this device (a file offer, a
  pairing code, a typing request): the packet gets 200 with `applied: false`
  and `reason: "paused"`, so a remote Enter cannot answer a question nobody
  read.
- The typing operations of a packet go to the sink in one call. A packet with
  no typing operation (a ping, a lone `stop`) only asks the sink for the
  target, and reports `paused` too while a card waits, so the sender sees the
  pause for as long as it lasts.
- One waiting request per sender and at most 8 in all. The same sender asking
  again ends its own grant and withdraws its own older request; any other
  sender hears `busy` while a grant lives.
- `incomingRemoteInput` drives the "X is typing into app" bar with Stop above the
  whole app ([`RemoteInputBanner`](../app/lib/ui/widgets/remote_input_banner.dart),
  in `MaterialApp.builder`, under the cards and above the messages in the
  corner), on every screen for the whole grant. With Chatt or an
  administrator's window in front nothing is typed, and the bar says so; it
  names the app only while typing really lands there. With the window hidden the native
  indicators take over: the floating bar on Windows, the Chatt keyboard's bar
  and the permanent notification on Android.

#### Typing history

Both sides keep a record of every session in the encrypted database (issue
#50): the sender what it sent and what the receiver answered, the receiver
what arrived and what its sink typed. The code is
[`services/typing_journal.dart`](../app/lib/services/typing_journal.dart);
the tables are `typing_sessions` and `typing_entries` (schema 16). The
journal records only while the add-on and `settings.typingHistory` are both
on (`AppServices.typingJournal`). The switch is "Save typing history" on the
add-on's card, on by default, and `setTypingHistory` is its one writer.
Turning it off keeps what is saved, and an add-on that is off records
nothing.

**A session row per request.** `direction` says who typed: `outgoing` is
this device typing on the peer, `incoming` is the peer typing here. The row
carries `inputId`, the peer's guid and its name at the time (the alias when
there is one), `startedAt`, `endedAt`, `result` (`TypingResult`) and
`endReason` (`TypingEnd`). The peer is kept as strings, with no reference to
`peers`, so removing a device keeps what was typed with it. A request that
never became a session gets a row too, ended at once.

- **The receiver** calls `begin` when it creates a grant, with `accepted`,
  `acceptedAlways` (the card with "Don't ask again") or `automatic` (a peer
  with `remoteInput`, no card), and `refused` with `rejected`, `noAnswer`,
  `busy`, `notEnabled` or `cancelled` for a verified sender while the add-on
  is on. Requests from unverified senders are never recorded, so a device
  without the green shield cannot write a row here. The journal's calls
  return at once, so `_decide` still has no `await` between its last check
  and the creation of the grant, and the fast refusal path stays fast.
- **The sender** calls `begin` with `accepted` when `start()` succeeds, and
  `refused` with `rejected`, `noAnswer`, `busy`, `notEnabled`, `olderPeer`,
  `unreachable` or `cancelled` when it fails. `addonOff` and `notVerified`
  send nothing and record nothing.

**Entries.** The typing operations of a packet are recorded once, at the
packet's final outcome; `ping` and `stop` type nothing and drop out. The
receiver records after the duplicate check (`grant.lastSeq = seq`), so a
retried packet lands in the history once. The sender records in `_sendPacket`
once per `seq`, outside the retry loop, and the operations that rode with a
`stop` are recorded from that reply's `applied`. An entry is a run of
packets into one field with one outcome (`TypingStatus`):

| Status | Receiver | Sender |
|---|---|---|
| `typed` | the sink applied the packet | the reply says it was typed |
| `notTyped` | the sink answered `applied: false`: the field went away, the screen locked or Stop came first, and part of it may have landed | the reply says `applied: false` |
| `paused` | a card waited, nothing typed | the reply says `paused` |
| `refused` | | the reply was a refusal (`ok: false`) |
| `unconfirmed` | | no reply after the three attempts, or another failure, so nobody knows whether it landed |
| `unsent` | | still in the queue when the session ended (`_finish`, `_drain` on a dead session, `dispose`) |

**Hiding.** `hideTyping(before, after)` stores the text of a packet only when
the field was `text` both before the packet and after it. Anything else
(`password`, `none`) stores the number of code points
(`{"t":"insert","hidden":n}`) and marks the entry `masked`. The kind of field
is known only from the answer to a packet, one packet late, so counting
`before` alone would store the first packet typed into a password field that
was just tapped. Counting both hides it, at the price of also hiding the first
packet into an ordinary field right after a password field. `before` is the
target known before the packet: the receiver keeps `lastTarget` on the grant,
starting with the `status()` taken at acceptance, and the sender takes
`o.state.target`, which the pings refresh every second. `after` is the sink's
answer on the receiver and the reply's target on the sender (`before` when no
reply came). A password field that its app does not mark as one (no
`IsPassword` in UI Automation, no password input type on Android) is `text`
to the sink, and its text is stored.

**Coalescing.** Packets in a row with the same `app`, `appLabel`, field,
status and hiding go into one entry in memory, their operations merged by
`appendTypingOp` (text with text, Backspace with Backspace, Delete with
Delete). The entry goes to the database after 1 second of quiet, when any of
those five changes, and when the session ends. Every journal call returns at
once and the writes run one after another in the background, so a packet
never waits for the disk; a write that fails goes to the app log. Closing the
app gives no signal (Windows ends the process from the tray, Android kills
it), so nothing waits in memory longer than that second.

**End reasons** (`TypingEnd`):

| Reason | Side | When |
|---|---|---|
| `stoppedHere` | both | Stop on this device: `stop()` on the sender, `stopIncoming` on the receiver |
| `stoppedByPeer` | both | the other side ended it: a `stop` operation or a `cancel` on the receiver, a `no_grant` or `stale_seq` reply on the sender |
| `expired` | receiver | 30 minutes without typing, or 8 hours in all |
| `receiveOff` | receiver | "Allow typing on this device" turned off |
| `addonOff` | both | the add-on turned off |
| `replaced` | both | the same sender asked again (receiver), a new `start()` (sender) |
| `peerRemoved` | both | the peer removed from the list |
| `notAllowed` | receiver | a packet failed the database check: the shield or a switch is gone |
| `linkLost` | sender | no answer: the link went down |
| `appClosed` | both | the app closed during the session (`dispose`) |

- **The two sides match up.** `inputId` is the protocol's `input`, the same on
  both devices, so the sender's record and the receiver's can be laid side by
  side: what went out against what landed.
- **No window titles.** An entry keeps `app` and `appLabel` from the target,
  as the protocol carries them. A window title is never sent, so it cannot be
  recorded either.
- **Deleting.** `applyRetention` runs `deleteTypingOlderThan` with the age set
  for messages: entries before the cutoff go, and so do sessions that ended
  before it (or started, when no end was written), with the rest of their
  entries. `AppServices.clearHistory` clears the typing tables together with
  the messages, and `clearTypingHistory` clears them alone. Both flush the
  journal and then call `detachAll`: the rows are gone, so a session still
  running goes on with no record.
- **Reading it back.** `watchTypingSessionSummaries` gives the list
  (characters, entries, apps) and `watchTypingEntries` the entries of one
  session. `reconstructTyping` rebuilds the text as far as the operations
  allow: `bs` takes characters from the end, `action` is a new line, hidden
  text is dots, and `del` changes nothing, because the cursor's place over
  there is unknown. Text that was in the field before the session, or a
  cursor moved over there, does not show, and the operations stay the exact
  record. `describeTypingOps` writes them out for the export: text verbatim,
  keys in square brackets (`[Backspace x3]`, `[Enter]`,
  `[hidden: 8 chars]`).
- **The app log** gets the keyboard's events with no text in them
  (`LogArea.keyboard`): the request, the decision, the start, the end reason,
  and failed packets as counts.

#### The `chatt/remoteinput` channel

`RemoteInputSink` is the receiving end, and `RemoteInputChannel`, the Dart side
of the channel, is its default. Tests put in their own sink through
`AppServices.start(remoteInputSink:)`.

| Method | Arguments | Answer |
|---|---|---|
| `status` | none | the target |
| `apply` | `{ops: [...]}`, only `insert`, `bs`, `del` and `action` | the target plus `applied` |
| `setSession` | `{active, peerName}` | none |
| `holdOwnApp` | `{on}` | none |
| `setImeEnabled` | `{on}` | `{ok}` |
| `showIndicator` | `{text, stop}` | `{ok}` |
| `hideIndicator` | none | `{ok}` |

One call goes the other way: `stopRequested`, when somebody presses Stop on the
native indicator. `RemoteInputChannel.listen` routes it to
`stopIncomingRemoteInput`.

`setImeEnabled` is called by the add-on's switch alone; on Android it turns the
keyboard component on and off, so with the add-on off Chatt is absent from the
system's list of keyboards. `setSession` comes when a grant starts and ends, so
the native side can show or hide its indicator, and `status` and `apply` only
under a grant. The sink refuses by itself, answering `applied: false`, when the
screen is locked or dark (`locked`), and on Windows in front of an elevated
window (`elevated`), where `SendInput` types nothing and reports nothing.
Chatt's own fields take typing like any other (`ownApp` only tells the sender
that Chatt is in front), except while `holdOwnApp` is on: Dart turns it on
under a grant the moment a card starts waiting (a file, a pairing code, a
typing request) or this device starts typing on another one, and off when
that is over. While it is on, the native side reports Chatt's own window as
not active, and on Windows a packet that is being typed into it stops before
its next key, so a remote Enter never lands on a card that came up in the
middle of a long paste. A device's own typing screen would otherwise forward
what is typed into it to the third device, and two sessions in opposite
directions would echo forever. The channel never throws: a missing native side, a
`PlatformException` or a test without a binding all end as "nowhere to type",
and on a platform other than Android and Windows it makes no call. A call that
gets no answer within 5 seconds ends the same way, so a native side that hangs
cannot hold up the packets behind it; `apply` gets 50 ms more for every
character and every Backspace or Delete in the packet
(`remoteInputTypingTime`), because typing is paced, and the sender adds the
same to the packet's time limit.
`RemoteInputChannel.debugSupported` lets the tests pretend to be such a
platform, as `BtChannel.debugSupported` does.

#### Android

On Android the sink is the **Chatt keyboard**,
[`ChattInputMethod`](../app/android/app/src/main/kotlin/com/mysttic/chatt/ChattInputMethod.kt),
an `InputMethodService` in the app's own process, and the channel is
[`ChattRemoteInput`](../app/android/app/src/main/kotlin/com/mysttic/chatt/ChattRemoteInput.kt).
An input method gets an `InputConnection` to the focused field of any app,
password fields and WebViews included, which is why the add-on goes this way.

- **The component is off in the manifest** (`android:enabled="false"`), so
  with the add-on off Chatt is absent from the system's list of keyboards.
  The add-on's switch turns it on and off (`setImeEnabled`,
  `setComponentEnabledSetting` with `DONT_KILL_APP`); a Chatt keyboard that is
  current when the add-on goes off is replaced by the system itself.
- **Turning it on in the system** is the user's one-time step, from a button on
  the add-on's card that opens the system's keyboard settings; the card waits
  for the app to come back and asks again. Android shows two warnings on the
  way: that a keyboard can collect what is typed, and that the app cannot
  start after a reboot until the phone is unlocked.
- **The keyboard has no keys.** It is a 48 dp bar: who is typing and where
  ("Typing: PC → Contacts"), a "Switch keyboard" button and Stop. From
  Android 15 the input window reaches under the navigation bar, which draws
  its back and keyboard-switch buttons over it; on the emulator the globe
  landed on Stop, and its touch area (`tappableElement`, 48 dp) is twice the
  navigation bar's own inset (24 dp). The bar is padded by the larger of the
  two. It never goes full screen, it stays shown with a hardware keyboard, and
  during a grant it keeps the screen on.
- **Typing** goes through the connection in one batch edit per packet:
  `commitText` for text; a newline is a newline in a multi-line field and
  Enter in a single-line one, as on a keyboard; Backspace and Delete remove a
  selection first and then use `deleteSurroundingTextInCodePoints`, so one
  `bs` removes a whole emoji, with key events as the fallback for a field that
  refuses; `action` is `performEditorAction` with the field's action (Search,
  Send, Go, Next, Previous, Done) and Enter when the field has none.
- **Refusals:** a locked keyguard or a screen that is off (`locked`), and no
  bound field at all. Chatt's own fields take typing like any other app's.
  When the keyboard starts input in the lock screen's password field (a
  SystemUI field, or any password field while the keyguard is locked), it
  switches back to the previous keyboard at once, so a password lock screen
  never meets a keyboard without keys. During a grant the native side then
  calls `keyboardLost` and Dart posts "Switch the keyboard to Chatt" right
  away: the notification waits for the unlock, and one tap brings the typing
  back. (Waiting for `ACTION_USER_PRESENT` does not work: once the keyboard is
  unbound Android defers that broadcast to Chatt's cached process.) A field of
  an app under a lock screen without a password keeps the Chatt keyboard, and
  a PIN pad is not a keyboard, so with a PIN the Chatt keyboard simply stays.
- **The end of a grant** switches back to the keyboard the user had before
  (`switchToPreviousInputMethod`).
- **Picking the keyboard.** Android shows its keyboard picker only to the
  window with focus or to the current keyboard. A consent accepted on the card
  (`afterAccept`) shows the picker when Chatt is not the current keyboard and,
  once the picker closes and the window gets its focus back, moves the app to
  the back, so the app with the field is in front. A grant without a card
  ("don't ask again") with the app in the background posts a high-priority
  notification "Switch the keyboard to Chatt", whose tap opens the app, shows
  the picker and moves the app away the same way. A card that arrives with
  the window closed gets a notification too.
- **The indicator** is the bar and the text of the permanent notification of
  `ChattService`, both "Typing: …" for the whole grant, in the app's language
  (`lib/ui/remote_input_mobile.dart`).
- **The foreground service.** A process woken by the system binding the
  keyboard runs `main()` before the system counts the app as visible, so the
  service's first start is refused; the keyboard retries it in `onCreate` and
  `onStartInput`, and the system lets it through (`Background started FGS:
  Allowed ... code:CURRENT_INPUT_METHOD`, seen on the emulator).
  `startForeground` sits in a `try`, because an exception there would take
  the process, and the keyboard with it, down.

#### Windows

[`windows/runner/chatt_remote_input.cpp`](../app/windows/runner/chatt_remote_input.cpp)
types into whatever window has the focus, on any Windows 10 or 11 PC, touch
screen or not.

- **Text** goes as Unicode characters (`SendInput` with `KEYEVENTF_UNICODE`),
  independent of the keyboard layout and with no modifier key; a newline,
  `action` and Enter are `VK_RETURN`, Backspace `VK_BACK`, Delete the extended
  `VK_DELETE`.
- **One character at a time, 10 ms apart, 40 ms after a space or Enter.** A
  character sent with `KEYEVENTF_UNICODE` arrives as `VK_PACKET`, and the app
  reads it only when it handles the event; the next `SendInput` overwrites it.
  An app that falls behind loses characters or repeats the last one. The
  Windows 11 Notepad (WinUI, with its spell checker) falls behind at word
  boundaries: checked live, 1 ms between characters turned "Chatt ąęł 124"
  into "Chatt 4444443", 10 ms still lost a letter after a space, and 10 ms
  with 40 ms after spaces and Enter typed twelve lines of Polish text without
  a mistake. Typing runs on its own thread with `timeBeginPeriod(1)`, and the
  reply goes back through a message-only window, the one place where a
  channel call may be answered. Before each character the sink checks whether
  the foreground window changed or `holdOwnApp` is on; when the target is no
  longer active (the lock screen, an elevated window, Chatt's own window on
  hold), the rest of the packet is dropped and `applied` is false. Stop on
  the bar or in the tray, and the end of the grant, bump a counter that the
  typing thread checks before each character too, so even a 4096-character
  paste stops at once.
- **The target.** The foreground window's process gives `app` (the file name)
  and `appLabel` (the version resource's `FileDescription`, or else the file
  name); a Store app behind `ApplicationFrameHost.exe` is looked up in its
  child window. Any running `chatt.exe` counts as `ownApp`, which is only
  information for the sender: typing goes there too. `locked` means the
  input desktop is not `Default` (the lock screen, a UAC prompt) or cannot be
  opened. `elevated` compares integrity levels: `SendInput` cannot reach a
  window above its own and reports nothing, and a process whose token cannot
  even be read is treated as above. Only this process's own window skips the
  check; another Chatt instance run as administrator is `elevated` like any
  other program.
- **The kind of field** comes from UI Automation (`GetFocusedElement`:
  `IsPassword` gives `password`, an Edit or Document control `text`, anything
  else `none`). It runs on a thread of its own with its own COM apartment and
  the `IUIAutomation2` limits at 400 ms, and the platform thread waits at most
  600 ms; an app that hangs gives `none`, and while the thread is still stuck
  on the last question, the answer is `none` at once. The thread starts at the
  first question, which only a grant asks. Chatt's own window is never asked:
  UI Automation would ask the platform thread that is waiting for the answer,
  so the question timed out with `none` and froze the window for 400 ms on
  every ping. The native side reports `ownWindow` instead, and Dart fills in
  the field from the widget tree (`focusedFieldKind`: an `EditableText` with
  the focus is `text`, `password` when obscured, `none` when read-only).
- **The floating bar** ("Typing: Alicja → Notepad" with Stop) stays on top
  for the whole grant, also with the Chatt window in the tray. It never takes
  the focus (`WS_EX_NOACTIVATE`, `MA_NOACTIVATE`, `PA_NOACTIVATE`), like the
  on-screen keyboard, so a Stop tapped with a finger leaves the focus in the
  field being typed into. The button is at least 44 px at the window's DPI.
  It sits at the top of the work area of the monitor with the foreground
  window. Its texts come from Dart in the app's language
  (`lib/ui/remote_input_desktop.dart`).
- **The tray** swaps to `assets/tray_icon_typing.ico` (the icon with an amber
  keyboard badge, from `tool/make_icons.py zasobnik`) and gets "Stop remote
  keyboard" in its menu while a grant lives; the tooltip says who is typing.
- **The consent card** pulls a hidden or minimised window out for the time of
  the card and sends it back after the answer, so the field picked earlier on
  this PC has the focus again. A grant alone never shows the window.

## Protocol

Protocol version **5** (`lib/network/protocol.dart`, `protocolVersion`), bumped
on incompatible changes. Bluetooth left it at 5: nothing incompatible arrived,
and the identity packet carries no radio route yet.

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
| `POST /file-offer` | file announcement: name, size, sha256, key tag, and the batch or [shared history](#sharing-history) it belongs to |
| `POST /file` | raw bytes from the given offset, with the session number in a header |
| `POST /input-session` | asking for a [remote keyboard](#the-keyboard-add-on) session, or withdrawing the request; the reply is sealed |
| `POST /input` | a packet of typing operations under a granted session; the reply is sealed |
| `POST /history-offer` | announcing a [shared history](#sharing-history), asking for one, ending or cancelling it; the reply is sealed |
| `POST /history-chunk` | up to 200 messages of a granted history; the reply is sealed |

The same endpoints answer requests that arrive over an RFCOMM link; the route
decides which road a request rides.

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

The responder picks the session number, and numbers travel in the clear, so the
side that opened the handshake refuses a number that already names a session
on its side. Taking it would put the new session in the place of somebody
else's incoming one, and that sender's envelopes would stop opening.

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

### Sharing history

A peer that still has our conversation can hand it back after we lost it: a
reinstall, a new phone, "Clear history", retention. The code is
`lib/services/history.dart` (a `part` of `app_services.dart`), the shapes are
in `lib/network/protocol.dart`. Both directions start the same way:

- **Share.** The side with the history sends `POST /history-offer` with
  `op: offer`, an identifier and a summary: how many messages, how many files
  will follow with their bytes, and the date range. The recipient gets a card
  and answers with a token, or refuses (`rejected`, `no-answer` after two
  minutes, `busy` while another history is coming in).
- **Ask.** The side that lost it sends `op: request`. The other side gets a
  card ("share", "share without files", "refuse") and, on yes, starts sharing
  with `answering` set to the request's identifier. The asking side accepts
  that offer without a card, since it already said yes by asking; the request
  lives ten minutes and is used once. An empty conversation answers `empty`
  without a card.

Messages then travel as `POST /history-chunk`: at most 200 per chunk and about
256 kB of text, each one as the sharing side sees it (`m: true` for "I wrote
this"), so the recipient flips the direction. A chunk goes in whole or not at
all (`HistoryChunk.fromJson`), and only within the summary on the card: more
messages, more files or more bytes than announced, a message outside the date
range on the card, or a file announced again under another name or size is
`over_limit`; a wrong token, another identifier or an expired grant is
`no_grant`. Chunks are handled one after another, and a number that already
went in imports nothing the second time, whatever it carries now: a chunk
repeated after a timeout gets an answer, nothing more.

The import (`ChattDb.importHistory`) runs in one transaction and skips what is
already there (by `messageGuid`, in any conversation), anything older than this
device's retention would keep, and anything more than ten minutes in the future,
since the times come from the sender's clock. Incoming messages arrive already
read and nothing raises a notification: this is an old conversation, not new
mail. Every imported row carries `restoredAt`.

Files ride the ordinary `/file-offer` and `/file` with `history` set to the
history's identifier. Every file row is created by its chunk, without content;
the offer is accepted without a card only for a file announced in a chunk, with
the same name and size, and only into a restored row of that conversation with
that same name and size, still waiting for bytes. Anything else gets
`no_grant`: an offer that carries `history` never falls back to the ordinary
file card. The bytes land in `received/` as usual and the row
gets the path. A received file that survived "Clear history" is linked at
import time and never travels again. A file whose bytes the sharing side no
longer has arrives as a row without content.

Sharing again resumes an interrupted share: messages that came in are skipped,
files still missing are offered again. `op: done` ends the grant and leaves the
result on the progress bar; `op: cancel` ends it and keeps whatever arrived,
and the sharing side sends it also when a chunk is refused or anything throws.
A grant lives thirty idle minutes (a file still streaming keeps it alive) and
twelve hours at most, and a clock ends an expired one even when nothing else
arrives. **Stop** on the receiving side's bar ends the grant the same way: the
next chunk gets `no_grant` and the sharing side cancels. One card per sender
and eight at most wait at a time; anything above that is `busy`.

**An older conversation for a new entry.** The identity comes from the key, so
after a reinstall, on a new phone or after "Start over" the same person comes
back as a new device, and the old conversation stays under the old entry.
Nothing on the wire can prove the two are the same: the old key is gone. That
call is a person's, on the sharing side: the share dialog offers the other
conversations (`ChattDb.otherConversations`) as the source, and
`shareHistory(sourceConversationId:)` refuses with `needsVerified` unless the
new entry has a green shield, so somebody borrowing a friend's name does not
get the friend's conversation with us. After a successful share the dialog can
merge the old conversation into the new one on this side
(`ChattDb.mergeConversation`); the old entry stays on the device list.

An older Chatt answers 404 on both routes, which the sender reports as an
older version on the other side.

## Database

`drift` (SQLite), schema version **16**. Tables: `settings`, `peers`,
`conversations`, `messages`, `typing_sessions`, `typing_entries`, `app_log`.

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
| 12 | `peers.btAddress`, `peers.lastProtocol`, `settings.wifiEnabled`, `settings.bluetoothEnabled` |
| 13 | `settings.keyboardEnabled`, `settings.remoteInputReceive`, `peers.remoteInput` |
| 14 | `messages.restoredAt` |
| 15 | `settings.style` |
| 16 | `typing_sessions`, `typing_entries` (with the index `typing_entries_session`), `app_log`, `settings.typingHistory` |

Version 12 only adds columns and touches nothing that was there:
`peers.btAddress` is a nullable text, `peers.lastProtocol` a nullable int (0 the
network, 1 Bluetooth, null nobody knows yet), `settings.wifiEnabled` defaults to
true and `settings.bluetoothEnabled` (the add-on) to false.

Version 13 adds three booleans for the keyboard add-on, all false by default:
`settings.keyboardEnabled` (the add-on), `settings.remoteInputReceive` (others
may type here) and `peers.remoteInput` (typing without a card). An update
switches none of them on.

Version 14 adds `messages.restoredAt`, the moment a message came back from a
peer's copy of the history ([Sharing history](#sharing-history)). Everything
already in the database arrived the ordinary way and keeps it empty.

Version 15 adds `settings.style`, the look picked in Settings ([Styles](#styles-one-app-three-looks)):
an int enum `AppStyle` (0 Cisza, 1 Precyzja, 2 Ciepło), Cisza by default. New
styles go only at the end of the enum, because the index is what the database
keeps.

Version 16 adds the tables of the [typing history](#typing-history) and of
the [app log](#the-app-log), and `settings.typingHistory` ("Save typing
history"), true by default; it counts only while the keyboard add-on is on.
Nothing already in the database changes. The tables and the index are
created with `IF NOT EXISTS` and the column only when it is missing, so an
interrupted migration completes on the next start. `typing_entries.ops` holds
the operations as JSON (`TypingOp`), `chars` the number of characters typed,
masked ones included, and `masked` whether the text was replaced by its
count. `app_log.at_ms` is in milliseconds, because a diagnosis needs
fractions of a second and a `DateTimeColumn` keeps whole seconds.

`upsertPeer` keeps the two roads apart: an empty host with a zero port does not
overwrite the last good address on the network, and an empty radio address does
not erase a known Bluetooth route. Neither road can wipe the other.

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

Everything in the database sits under that key: the conversations, the
typing history and the app log. `migrateToEncrypted` copies the typing tables
and the log as well. Data leaves the database in the clear only through
[an export](#exporting-data), when the user asks for one.

## The app log

[`services/app_log.dart`](../app/lib/services/app_log.dart) keeps a
diagnostic log in the encrypted database (`app_log`, schema 16, issue #50).
There is one `AppLog` per `AppServices` (`services.log`), because the tests
run several instances in one process and their entries must not mix.
Settings, "Data and diagnostics", "App log" shows it, and it leaves the device
only through [an export](#exporting-data).

- **An entry** is `atMs`, `level` (`info`, `warning`, `error`), `area`
  (`LogArea`: `app`, `net`, `pair`, `file`, `history`, `bt`, `keyboard`,
  `update`, `error`), `message` and `details`, the exception and its stack
  trace (`describeError`). Messages are short, in English and stable,
  whatever the app's language: they are data for analysis outside the app.
- **What goes in**: what the app did and what failed, by area: start and
  stop, connections and the road they took, pairing, file transfers, shared
  history, Bluetooth, keyboard sessions, update checks, errors. Device names,
  network and radio addresses and file sizes go in, because without them the
  log cannot say with whom and over which road something failed.
- **What never goes in**: message bodies, typed text, pairing codes, keys
  (identity, session, file, database), remote-input tokens, `pad` and window
  titles. `Setting.toString()` and `Peer.toString()` print keys, so neither
  object is ever logged; `RemoteInputOp.toString` prints a length alone.
- **Buffering.** `add` returns at once and never throws. Entries collect in
  memory and go to the database as one batch after 1 second, because closing
  the app gives no signal to wait for. A write that fails is dropped: the log
  has nowhere to record its own failure, and the app carries on.
  `AppServices.dispose` closes the log after the typing history and before
  the database.
- **Size.** `trim` runs at start and every six hours with the retention
  timer: entries older than 30 days (`appLogRetention`) go, and of the rest
  the newest 20,000 stay (`appLogMaxEntries`). "Clear history" leaves the log
  alone, since it holds no content.
- **Uncaught errors.** The global handlers (`FlutterError.onError` and
  `PlatformDispatcher.instance.onError`) write what nobody caught as `error`
  entries in the `error` area, with the stack trace in `details`. A failure
  before the database opens has no log to go to and still ends up in
  `chatt-startup-error.txt`.

## Exporting data

[`services/data_export.dart`](../app/lib/services/data_export.dart) writes
one ZIP with the parts the user picks in the "Export data" dialog
(`ExportParts`): the conversations with devices and settings, the typing
history, the app log, and received files, whose count and total size the
dialog shows before anything is written (`estimateExport`). Every file inside
is UTF-8: JSON for programs, text for people.

```
README.txt            what is inside, format notes, "this file is not
                      encrypted", the app version and the export time
manifest.json         format "chatt-export", formatVersion 1, appVersion,
                      exportedAt (ISO 8601 with offset), this device's guid and
                      name, the parts chosen, counts, skippedFiles
settings.json         the settings row without identityKey
devices.json          the peers without sessionKey ("contacts")
conversations.json    every conversation with its peer and its messages; a file
                      message carries its name, size, path and archivePath
typing-history.json   every session with its entries: time, app, field, status,
                      characters, hidden, the operations as JSON and as text;
                      plus a transcript rebuilt from the entries typed and
                      not typed
typing-history.txt    the same, for reading
app-log.json          every entry: time with milliseconds, level, area,
                      message, details
app-log.txt           one line per entry, "2026-10-18 15:30:12.345 WARN  net
                      message", details indented below
files/<8-hex>_<name>  received files, only with that part chosen
```

`README.txt` and `manifest.json` are always there; the rest only for the parts
chosen. Enums go in by name and dates as ISO 8601, so the files read without
the app. A received file is referenced from `conversations.json` by
`archivePath`; the hexadecimal prefix keeps two files of the same name apart,
and a file that is gone from disk or cannot be read is listed in
`skippedFiles` with the reason.

- **No keys.** `settings.json` leaves out `identityKey` and `devices.json`
  leaves out `sessionKey`; the database key never comes near the export. The
  peers' public keys go in, since they are public.
- **Not encrypted.** The archive is a plain ZIP and `README.txt` says so. It
  holds what the user picked, the typing history included.
- **Where it goes** (`exportAndSave`). Windows asks with the system save
  dialog and writes the archive straight there. Android builds it in the app
  cache (`cache/eksport/`) and copies it to Downloads through MediaStore on
  Android 10 and newer; on Android 9 and older, which have no such copy, it
  hands the archive to the share sheet through the FileProvider root for
  that directory. The name comes from `exportFileName`:
  `chatt-export-2026-10-18-1530.zip`.

## Security

### Threat model

The attacker is **on the same local network**: they can eavesdrop, send their
own packets and claim to be anyone. Plus an attacker who **gets at the disk**
and copies the database file or the whole app directory. Not assumed: access to
an **unlocked, running** device, where the key is in process memory by
definition.

With the Bluetooth transport on there is a second attacker: someone **within
radio range**, around 10 m, who can do the same things on that road.

The [keyboard add-on](#the-keyboard-add-on) gives a verified peer what this
model otherwise does not assume: typing on an **unlocked, running** device,
into whatever field has focus, in any app, and over the radio as well when the
Bluetooth add-on is on. That makes a verified device, or a copy of its keys,
worth more to an attacker. What holds it back is consent on the receiving side:
the add-on and the receive switch, both off by default, a card for every
session unless the receiver chose "don't ask again" for that device, and the
shield and both switches read again for every packet.

The [typing history](#typing-history) raises the stakes of the unlocked,
running device as well. With it on, both devices keep what was typed, so
whoever has one of them in hand reads what was typed on it and from it, and
can [export](#exporting-data) it as a plain ZIP. Chatt has no app lock. Text
bound for a password field or a field of unknown kind is kept as a count, and
the app log keeps no typed text at all.

### Bluetooth is treated like a cable

System pairing is not required and buys nothing, so the link is opened insecure
(no `SO_BTH_AUTHENTICATE` on Windows, `listenUsingInsecureRfcomm` on Android).
Everything above the link rides the radio untouched: the Noise-KK handshake, the
AES-GCM envelopes, the AES-CTR file stream, the key-derived `guid`, the consent
for a batch of files, the six-digit code and the QR code. The green shield still
comes from the code or the QR code alone.

The radio address is a new lasting identifier in the database, and it is a hint
about where to knock. Recognition goes by `guid`, and the address is overwritten
on every contact. On the hardware in [spike-rfcomm.md](spike-rfcomm.md) a paired
phone held the PC under an LE address while an unpaired one held it under the
radio's BR/EDR address: that is the proof the address cannot stand in for an
identity.

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

### Strings from the network against the keyboard

The only place where a string from the sender becomes keystrokes is the sink,
`RemoteInputSink.apply` in
[`core/remote_input.dart`](../app/lib/core/remote_input.dart). Two barriers:

1. **The protocol filters the shape.** `RemoteInputPacket.fromJson` drops the
   whole packet when anything in it is off: an unknown operation, a text with a
   control character other than `\n` (a tab counts) or with a lone surrogate, a
   Backspace or Delete run outside 1 to 64, more than 256 operations, more than
   4096 units of text or 4096 deletions in total, a `stop` anywhere but last, a
   `seq` that is not a positive integer, an `input` or a `token` of the wrong
   shape. Half a packet typed is worse than none, so a bad packet gets a 400
   and nothing of it is typed.
2. **The sink can only type.** It receives `insert`, `bs`, `del` and `action`;
   the wire adds only `ping` and `stop`, which never reach the sink. There are
   no key codes, no shortcuts, no Tab, Esc or arrows, nothing that reads from
   the device. Text is typed as characters,
   with no modifier key and independent of the keyboard layout: `commitText` on
   Android (phase 3), `SendInput` with `KEYEVENTF_UNICODE` on Windows
   (phase 2).

On the way the text reaches no app log and no `ValueNotifier`, and
`RemoteInputOp.toString` prints its length alone. It is kept in one place, the
[typing history](#typing-history) in the encrypted database, while its switch
is on, and text bound for a password field or a field of unknown kind is kept
there as a count. What comes back goes onto the sender's screen, so
`RemoteInputTarget.fromJson` keeps known values only and clips `app` and
`appLabel` at 96 bytes of JSON, whole characters only.

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
- **The radio is in the clear in the same way**: the Bluetooth device name and
  the radio's MAC address are readable by anyone in range, exactly as the device
  name and port are on the network today. While the transport is on, the machine
  is discoverable to everybody nearby, and Settings warns about it. A phone is
  discoverable only for two minutes after **Show this phone nearby** in Nearby
  and the system's prompt (`showSelf` on the `chatt/bluetooth` channel).
- **A restored message is the peer's word.** Nothing signs a message: the
  identity keys are X25519 and an envelope only proves who is on the other end
  of the session. A shared history can therefore claim that we wrote something.
  Every restored row carries `restoredAt` and is marked on screen, the card
  says whether the sharing device has a green shield, and nothing restored
  raises a notification.
- Session key rotation is deferred, because resuming a transfer needs the same
  key across sessions.
- Received files lie on disk unencrypted. The database wraps conversation
  history; file content stays where the user opens it with other applications.
- **An export is plaintext.** The archive from "Export data" carries no
  encryption and holds whatever the user picked, the typing history
  included. It carries no key, and its `README.txt` says it is not encrypted;
  from there it is a file like any other in Downloads or wherever it was
  saved.
- **The typing history keeps the text of an unmarked password field.** The
  hiding rule trusts the kind of field the sink reports. A password box that
  its app does not mark as one (no `IsPassword`, no password input type)
  counts as `text`, and what is typed into it is stored verbatim on both
  sides.
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
- **There are no automated end-to-end tests over a real radio**: CI has none.
  `tool/bt_rozmowa_check.dart` is the manual check on two machines.
  `test/bt_link_test.dart` covers the framing over a pipe, and
  `test/migration_test.dart` covers the step from 11 to 12.
- On Android 11 and older a radio search needs `ACCESS_FINE_LOCATION`, and the
  app does not ask for it, so the search finds nothing there. Adding a device by
  its radio address works.
- Bluetooth listening from the Android foreground service with the screen off
  has not been checked on hardware.
- Receive streams in `bt_link` apply no backpressure per stream. The radio is
  slower than a write to disk, so in practice it has not hurt.
- **An envelope can be replayed for as long as its session lives.** The
  envelope carries no counter, so a recorded one opens at the responder until
  the session expires, an hour after its last use, and every packet of a
  typing session uses it. The keyboard routes close that window above the
  envelope: a request id works once, a packet needs the live `token` and a
  `seq` above the last one, and a repeated `seq` gets the cached reply with
  nothing typed again.
- **Length and timing leak from a typing session.** AES-GCM keeps the length
  of what it seals, which is why every keyboard payload is padded to at least
  512 bytes and above that to a multiple of 64. Packets of one keystroke look
  alike; a burst of typing or a paste still shows its size to that block. The
  timing is visible in full: with a fast round trip a packet goes out about
  once per keystroke, so an eavesdropper on the network, or within radio range
  with Bluetooth on, sees the rhythm of the typing and the number of packets,
  with none of their content.
- **Windows types into no elevated window** (phase 2). Without elevation
  `SendInput` reaches no administrator window, no UAC prompt and no lock
  screen, and it does not report the failure. The receiver detects the case
  itself (`elevated`) and tells the sender. `uiAccess` would lift the limit
  and needs a signed binary installed under Program Files, which is out of
  scope.
- **On Android the user has to pick the Chatt keyboard** (phase 3). It is
  enabled once in the system settings, under Android's warning that a keyboard
  can collect everything typed, and chosen as the current keyboard for a
  session. Android shows the keyboard picker only to the window with focus or
  to the current keyboard, so Chatt cannot switch keyboards from the
  background.
- **Chatt's own fields take typing.** The keyboard works as a keyboard
  everywhere the user goes, Chatt included. On Windows a remote Enter in
  Chatt's message field sends a message, as it would in any other messenger;
  on Android that field holds several lines, so the Chatt keyboard's Enter
  starts a new line there and the message goes out with the Send button. Chatt's
  cards (a file, a pairing code, a typing request) stay out of reach: while
  any card waits, the packet is answered `paused` and nothing is typed, and
  `holdOwnApp` stops a packet already being typed into Chatt's window before
  its next key. A file card that comes up during a grant takes the focus on
  Reject, so an Enter that got there first can only refuse. The same hold
  covers a device that is itself typing on another one, so its own typing
  screen never relays or echoes what it receives.

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
  foreground app;
- a refused `startForeground` stops the service quietly, and the Chatt
  keyboard starts it again once the system allows it (see the keyboard
  add-on).

A foreground service overrides Doze's network cut, so a battery optimisation
exemption is not needed on stock Android; the button in Settings stays as
insurance against manufacturers with their own app killing.

Files go out to other apps through FileProvider as `content://` (our own
`chatt/files` channel), because from API 24 a plain path ends in
`FileUriExposedException`. FileProvider serves only what
[`res/xml/file_paths.xml`](../app/android/app/src/main/res/xml/file_paths.xml)
lists, and it lists five roots: received files, a downloaded release, the
two cache directories holding copies of files the user picked or pasted to
send, and `cache/eksport/`, where an export waits for the share sheet on
Android 9 and older (see [Exporting data](#exporting-data)). A file outside
all of them cannot be handed out at all. That is what made tapping your own
sent photo fail until 0.8.2: an outgoing message keeps the source path it was
given, and nothing ever moves that file under `files/`. The channel answers
with a word (`ok`, `missing`, `failed`), so "the file is gone" and "handing it
out failed" reach the user as different sentences, and the failure is written
to logcat.

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
  resources inside the `.exe`. While somebody types on this PC with the
  keyboard add-on, the icon has a badge (`assets/tray_icon_typing.ico`) and
  the menu a Stop.
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
  from the app bar colour. The colours of each of the five walls come from the
  active style (`ChattTokens.walls`).
- **Selecting message text** is a `SelectionArea` around the conversation on
  the desktop, and a "Select text" entry in the bubble menu on a phone, where
  the long press already belongs to that menu.

## Styles: one app, three looks

Issue #37 brought three styles (Cisza, Precyzja, Ciepło), each in a light and
a dark variant. They change looks alone: every screen shows the same
information and the same controls in every style, so no code outside
`ui/styles.dart` branches on the style for content.

- **`chattTheme(style, brightness)`** builds the whole `ThemeData`: a
  `ColorScheme` filled field by field from the style's hex values (no seed
  colour), the text theme with the style's font, and the component themes
  (cards, dialogs, sheets, buttons with a 48 px minimum height, fields,
  switches, chips, the app bar).
- **`ChattTokens`** (a `ThemeExtension`) carries what `ColorScheme` has no
  slot for: bubble colours and shape, avatar palette and shape, row height and
  padding, whether rows are cards, the date separator, the route badge, radii,
  shadows, the security signals and the text styles `mono`, `code`, `overline`,
  `caption`. Widgets read them with `ChattTokens.of(context)`, which falls back
  to Cisza when a test builds a bare `MaterialApp`.
- **Security signals.** `k.security` is the unconfirmed identity warning: the
  danger colours in Cisza, the warning (amber) colours in Precyzja and Ciepło.
  `k.dangerNote` (no encryption, codes that do not match) is red everywhere,
  `k.verifiedNote` is the green of a confirmed identity. `SecurityNote` in
  `widgets/common.dart` draws a warning frame from any of them.
- **Fonts** are bundled (see `fonts/LICENSE`): Figtree, IBM Plex Sans and
  Nunito for text, DM Mono, IBM Plex Mono and Spline Sans Mono for technical
  values. Three of them are variable fonts; Flutter maps `FontWeight` to their
  `wght` axis.
- **Switching** goes through `MaterialApp`'s theme animation. `ChattTokens.lerp`
  swaps the whole set at the midpoint, so no frame mixes two styles' shapes.
- **Density.** On a phone the conversation header holds the shield and the
  menu, both 48 dp targets; search and the keyboard button move into the menu.
  Above `dwupanelOd` they stay in the header.

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
- `openExternalLink` checks the scheme once more immediately before handing
  the address over, and never goes through a shell. On Android it goes through
  the `chatt/files` channel, where `ChattChannels.openUrl` checks the scheme a
  third time and adds `CATEGORY_BROWSABLE`. On Windows it goes through the
  `chatt/links` channel (`windows/runner/chatt_links.cpp`), which checks the
  scheme a third time, refuses control characters and calls `ShellExecuteW`
  with the address as **one string**. It used to be an argument of
  `explorer.exe`, which splits its command line on commas and equals signs:
  a link with `?client=...` opened the Documents folder (issue #31). macOS and
  Linux still pass it as a list argument to `open` and `xdg-open`.
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
