# Chatt

![Chatt](docs/promo.png)

*Wersja polska: [README.pl.md](README.pl.md)*

Chatt puts your PC and your phone in one conversation. Messages and files go
straight from one device to the other over your local Wi‑Fi: **no server, no
account, no cloud, always encrypted.**

| Conversation | File request | Nearby devices |
|---|---|---|
| <img src="docs/screenshots/produkt/en/android_rozmowa_z_plikiem.png" alt="Conversation" width="230"> | <img src="docs/screenshots/produkt/en/android_prosba_o_plik.png" alt="File request" width="230"> | <img src="docs/screenshots/produkt/en/android_urzadzenia_w_poblizu.png" alt="Nearby devices" width="230"> |

## Why another one

Sending a link from your phone to your PC through a chat app, or emailing a
photo to your own address, routes your stuff through someone else's server.
Tools like LocalSend fix the file part but keep no conversation; KDE Connect
does a lot but is not a messenger. Chatt is the missing piece:

- **A conversation, not just a file drop.** History stays, is searchable, and
  both devices see the same thing.
- **Always encrypted, not "once paired".** Every connection negotiates its own
  key; the first message to an unknown device is protected exactly like the
  hundredth to a paired one. Recorded traffic cannot be decrypted after a
  device is stolen (forward secrecy).
- **Nothing leaves your network.** No server, no telemetry, no ads. The app
  needs no internet at all.

## What it does

- **Finds devices by itself**: one UDP broadcast and the devices see each
  other. When a router isolates clients, add the other device by IP address.
- **Messages with delivery status**: saved locally → delivered → acknowledged.
  Failed ones retry with one tap; if the other device changes IP, it is found
  again by its identity.
- **Files with consent**: the recipient sees name, size and checksum first,
  bytes flow only after accepting. Interrupted transfers resume where they
  stopped and are verified with sha256. Several files at once, on the PC also
  by dragging them onto the window.
- **Encrypted at rest**: conversation history lives in an encrypted database
  with the key held by the OS (Android Keystore, Windows DPAPI). Clear history
  or auto‑delete messages older than N days.
- **Identity confirmation**: scan a QR code from the other screen or compare
  six digits. Anyone can type any device name; nobody can fake the key.
- **Works in the background**: the phone receives with the window closed and
  the screen off; on Windows the app sits in the tray and can start with the
  system.
- **Comfort**: image thumbnails, one‑tap save to Pictures/Downloads, search,
  per‑message delete, two‑pane layout on wide windows, backgrounds, light and
  dark themes, English and Polish.

Platforms: **Windows** and **Android**. Both devices must be on the same
network. There is no internet mode, and there will not be one: the whole
point is that nothing leaves your network.

## Download

Releases ship three files: an Android APK, a Windows installer and a portable
Windows zip. See the [Releases](../../releases) page. Chatt is not in any app
store: both of them want an account that is maintained rather than a one-off
upload, which for an app given away for free is a cost with no return.

The Windows installer is not code‑signed, so SmartScreen shows a warning on
first run ("More info" → "Run anyway"). A signing certificate would change
nothing about what the program does.

## How it works, in five lines

Every device is both client and server: a small HTTP server plus a UDP
responder, the same shape as LocalSend. Identity is an X25519 key pair and the
device ID is derived from the public key, so an ID cannot be claimed without
the matching private key. Each connection runs a Noise‑KK‑style handshake and
gets a session key that lives an hour, in memory only. Messages travel in
AES‑GCM envelopes, file streams in AES‑CTR with a sha256 announced inside the
encrypted offer. The database is SQLite3MultipleCiphers with the key wrapped
by the platform keystore.

The full threat model, protocol and decisions are in
[docs/architecture.md](docs/architecture.md).

## Documentation

| Document | For whom |
|---|---|
| [docs/guide.md](docs/guide.md) | users: pairing, files, background listening, troubleshooting |
| [docs/building.md](docs/building.md) | building for Windows and Android, signing, branches and releases |
| [docs/testing.md](docs/testing.md) | what is tested, how to run it, what tests cannot catch |
| [docs/architecture.md](docs/architecture.md) | protocol, database, threat model |
| [CHANGELOG.md](CHANGELOG.md) | what changed in each release |

## Development

```
cd app
flutter test        # 94 tests: database, discovery, messages, files, identity, encryption, attacker on the wire
flutter analyze
```

Layout of `app/lib/`:

- `core/`: device identity, cryptography, platform channels
- `data/db.dart`: the SQLite schema (drift) and queries
- `network/`: the protocol, UDP discovery, HTTP server and client
- `services/`: `AppServices`, the root that ties everything together, plus Riverpod providers
- `ui/screens/`: conversations, chat, nearby devices, settings

Device scenarios in `app/tool/` are described in
[docs/testing.md](docs/testing.md).
