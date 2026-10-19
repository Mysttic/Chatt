# Security policy

## Supported versions

Only the latest released version is supported. Fixes go into `develop` and
reach users with the next release.

## Reporting a vulnerability

Please report security issues privately:

- open a [private security advisory](https://github.com/Mysttic/Chatt/security/advisories/new)
  on GitHub (preferred), or
- write to the address in the repository owner's GitHub profile.

Include what you did, what happened, and what an attacker gains. Expect an
acknowledgement within a few days. This is a hobby-scale project, so please do
not expect a same-day turnaround.

## What is in scope

Everything that processes input from the network, because any device on the
same Wi-Fi can send it. With the Bluetooth add-on on, the same input can
arrive over the radio, so the sender can be anyone in range, about 10 m. The
add-on is off by default, and while it is off the app does not touch the radio,
apart from checking and asking for the permission at the moment the switch is
turned on:

- **the protocol and the session handshake** (`app/lib/network/`): envelopes,
  the key agreement, the discovery responder,
- **file reception** (`app/lib/services/app_services.dart` and
  `app/lib/core/received_paths.dart`): a string from the sender becomes a path
  on disk there,
- **the database key** (`app/lib/core/secret_store.dart` and the platform
  channels in `app/android/` and `app/windows/`),
- **the identity confirmation flow**, including the QR code,
- **links in messages** (`app/lib/core/links.dart` and
  `app/lib/core/link_preview.dart`): the sender picks the address, so what
  becomes a link, what the confirmation card shows before anything opens, and
  where a preview is allowed to connect all belong here,
- **the remote keyboard** (`app/lib/services/remote_input.dart`,
  `app/lib/core/remote_input.dart`, the request and packet shapes in
  `app/lib/network/protocol.dart`, and the native sides once they exist:
  `app/windows/runner/chatt_remote_input.cpp`,
  `app/android/app/src/main/kotlin/com/mysttic/chatt/ChattInputMethod.kt` and
  `app/android/app/src/main/kotlin/com/mysttic/chatt/ChattRemoteInput.kt`):
  the two routes parse whatever any device with a session sends, and a string
  from a verified sender becomes keystrokes in another app there. The keyboard
  add-on is off by default, and while it is off its native channel gets no
  call apart from the switch itself,
- **shared history** (`app/lib/services/history.dart`, the history shapes in
  `app/lib/network/protocol.dart` and `ChattDb.importHistory`): a peer with a
  session sends whole conversations that end up in the database, and file
  rows that later take bytes without a per-file question.

The threat model is written down in [architecture.md](architecture.md),
together with what it deliberately does not cover.

## Things that are known and intended

These are design decisions:

- **Discovery is in the clear.** The device name and port are visible to
  everyone on the network. A broadcast goes out to somebody you do not know
  yet, so there is nothing to encrypt it with.
- **A device name is just a label.** Anyone can set it to anything; that is
  what identity confirmation and the fingerprints are for.
- **`POST /pair` is not authenticated**, so anyone on the network can raise a
  confirmation card. It gets them no further: the codes have to match on both
  screens, and a card for an already known device is marked in red.
- **Bluetooth is treated as a cable.** System pairing is not required and
  buys nothing: the link is opened insecure
  (`listenUsingInsecureRfcommWithServiceRecord` on Android, no
  `SO_BTH_AUTHENTICATE` on Windows). Everything that protects a conversation
  sits above the link and goes over the radio unchanged: the Noise-KK
  handshake, the AES-GCM envelopes, the AES-CTR file stream, the guid derived
  from the public key, the consent for a batch of files, identity confirmation
  by code and by QR. A request arriving from the radio walks the same path as
  one from a TCP socket: the same routes, the same handlers, the same error
  guard. The green shield still comes from one thing only, a code or a QR
  confirmed on both screens.
- **The radio is in the clear the way discovery is.** The Bluetooth device
  name and the radio's MAC address are visible to anyone in range, exactly as
  the device name and port are visible to everyone on the Wi-Fi. With the
  add-on on, the computer is discoverable to everyone nearby; the add-on's card
  in Settings says so. A phone is discoverable only for the two minutes after
  **Show this phone nearby** and the system's own prompt.
- **A restored message is the peer's word.** A shared history can claim
  anything, including that we wrote something: nothing signs a message.
  Restored rows are marked (`messages.restoredAt`), the card says whether the
  sending device has a green shield, and the consent is bounded by the counts
  and bytes on the card.
- **A radio address is a route.** `Peers.btAddress` is a new lasting
  identifier in the database. Who somebody is still comes from the guid, and
  the address is overwritten on every contact. Measured on hardware
  ([spike-rfcomm.md](spike-rfcomm.md)): a paired phone saw the computer under
  its LE address, an unpaired one under the BR/EDR address of the radio, so
  one machine showed up under two addresses depending on who was looking.
- **Received files lie on disk unencrypted.** The database wraps conversation
  history; file content stays where the user opens it with other applications.
- **The database key can be read by a process running as the same system
  user.** On Windows DPAPI unwraps it for any such process; on Android the app
  sandbox is what protects it. Protection covers a copied disk or a copied
  file; code already running as you can read the key.
- **Nothing leaves the local network on its own.** There is no server, no
  telemetry and no crash reporting, so there is no reporting channel to abuse
  either. Two exceptions, both off by default:
  - with update checks turned on, or when the button in Settings is pressed,
    the app asks `api.github.com` about the newest release. GitHub sees what
    any HTTPS server sees, an IP address and the time. Nothing about the
    conversations goes with it.
  - with link previews turned on, a link in a received message makes the app
    fetch that page's `<meta>` tags and image, so the server behind the link
    learns an IP address, a time and which link it was. The address is chosen
    by the sender, which is why the switch starts off. Nothing from the page
    is executed, and previews are never fetched from local-network addresses.
- **A preview loses one race by design.** Between our DNS check and the one
  the HTTP client makes, the record can change ("DNS rebinding"). The cost is
  one empty GET to a local address; the answer still cannot run anything,
  because all the app takes from it is text and image bytes.
- **A stolen verified device can type on its peers.** On a device with the
  keyboard add-on and "Allow typing on this device" both on, any device whose
  identity was confirmed there can ask to type. With "don't ask again" set for
  that device the session starts without a card; otherwise one accepted card
  is enough. From then on whoever holds the stolen device types into the field
  that has focus, a password field included, until consent or verification is
  withdrawn on the receiving side: Stop, either switch turned off, or the
  device removed from the list. A grant also ends after 30 minutes without
  typing and 8 hours in all. The receive switch starts off, like the add-on
  itself, so none of this is possible until the owner of the receiving device
  turns both on. An unverified sender is refused without a card and cannot
  tell whether the add-on is on.
