# Changelog

Everything worth knowing about each release of Chatt. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the numbering
follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

The release number lives in [VERSION.md](VERSION.md) and is what triggers a
release: the workflow starts only when that file was among the changes merged
into `master`.

## [Unreleased]

Comfort work reported after using 0.4.0 on both platforms.

### Added
- **A name of your own for a peer.** A device announces its own name, so a PC
  arrives as something like `DESKTOP-8F2A1C`. The security panel now has a
  rename button; the name stays on this device, is never sent anywhere, and the
  announced one keeps showing under it, so the other side quietly renaming
  itself is still visible. An empty field brings the announced name back
  (schema v9, `peers.alias`).
- **Accepting files without asking**, per peer, off by default (schema v9,
  `peers.autoAccept`). It can only be turned on with a confirmed identity, and
  removing the confirmation turns it off. The database enforces both, not the
  screen, because this is the boundary of the user's consent: the flag alone,
  without a green shield, would mean "take files from anyone claiming that
  name".
- **Copy image** on Windows for received pictures. Flutter's `Clipboard` only
  handles text, so the runner grew a `chatt/clipboard` channel that decodes the
  file with WIC and puts it on the clipboard as `CF_DIB` (pastes into an editor
  or a document) and `CF_HDROP` (pastes into Explorer). Transparency is
  composited onto white, because alpha on the clipboard is read differently
  from program to program and the usual result is a black background.
- **Selecting message text.** On the desktop the conversation is wrapped in a
  `SelectionArea`, so the cursor selects across several bubbles at once and
  Ctrl+C copies. On a phone the same gesture belongs to the bubble menu, which
  is the only way to delete a message, so selection is a "Select text" entry
  inside that menu instead of a fight in the gesture arena.
- On the desktop the bubble menu also opens with a right click, which is the
  gesture people actually reach for there.

### Fixed
- **Android stopped answering other devices' scans.** Dart does not support
  `SO_REUSEPORT` on Android, so the discovery responder's bind threw, and
  `AppServices.start` swallowed the exception without a trace. The phone kept
  working in every other way and could find others itself, but nobody could
  find it with a scan; it had to be added by address. Verified on a device
  before and after: UDP 47777 has a listener now, and the
  `reusePort not supported on this platform` line is gone from the log.
- A failed `adb forward` in `tool/android_e2e_test.dart` was silent. With the
  port already taken, by an ordinary Chatt running on the same desktop for
  example, the test connected to **that** instead of the phone and every
  assertion passed while the device was never touched. The tunnel is now
  asserted, and `CHATT_PROXY_PORT` moves it out of the way.

### Changed
- **A discovery failure is now visible.** Settings shows a warning when the
  responder is not listening, next to the one about the system keystore.
  Without it the symptom looks like a network problem on the other side.
- **Short messages moved from the bottom of the screen to the top right corner**
  and got a bar counting down to when they go away; a tap closes one at once.
  A `SnackBar` covers exactly what was just used: the "Nearby" button on the
  conversation list, the text field in a conversation. All 18 call sites across
  six files now go through one place (`ui/widgets/toasts.dart`).

## [0.4.0] - 2026-09-04

An English repository: everything a reader meets is in one language, and a
fresh installation starts in English. No change to the protocol, the database
schema or the way the app behaves once it is running.

### Added
- `docs/guide.pl.md`, the user guide in Polish. It is the one document an end
  user reads rather than a developer, so it is worth having in both languages.
  It carries three screenshots the English guide does not, because those exist
  only with a Polish interface.

### Changed
- The documentation is English, in one version, with two exceptions:
  `README.pl.md` and the user guide, both of which face readers rather than
  developers. `docs/instrukcja.md`, `architektura.md`, `budowanie.md` and
  `testy.md` became `guide.md`, `architecture.md`, `building.md` and
  `testing.md`; `docs/publikacja/` became `docs/publishing/` and
  `docs/makiety/` became `docs/mockups/`. The code comments stay in Polish.
- **English is the default language for a new installation.** The interface was
  already fully bilingual (160 strings in `app_en.arb` and `app_pl.arb`, a
  picker in settings), but a fresh install followed the system language. The
  column default in `settings.language` is now English. Existing installations
  keep whatever they chose.
- Screenshots in the documentation are constrained with an `<img>` width tag. A
  1280x2856 phone screenshot rendered at full page width turned every document
  into a scroll.
- `ROADMAP.md` was replaced by this changelog. The parts of it that were not
  release history moved into `docs/architecture.md`.

### Fixed
- The headline on the README banner no longer runs off the right edge:
  `tool/store_assets.py` now fits the font to the available width instead of
  using a fixed size.

### Removed
- `.claude/` is out of the repository, and local machine paths are out of the
  documentation.

## [0.3.1] - 2026-09-03

Content and materials for a possible publication, plus the decision not to
publish in the stores after all.

### Added
- The English README as the main one, with Polish moved to `README.pl.md`.
- Positioning, a privacy policy and finished store copy for Google Play and the
  Microsoft Store, kept in `docs/publishing/` in case the decision changes.
- Screenshots in both languages: `product_shots.dart` driven by
  `CHATT_SHOTS_LANG`, and a new `tool/windows_shots.dart` that renders the app
  in the `flutter_test` harness at 1600x900 with a demonstration conversation,
  so a Windows screenshot needs no clicking around the desktop and shows no
  private conversations.
- `tool/store_assets.py`, generating the README banner and store-sized assets.

### Changed
- Store packages (an AAB next to the APK, an MSIX for the Store) were built,
  verified and then removed together with the `msix` dependency. Both stores
  require an account to be maintained rather than a one-off upload, which for a
  showcase app is a cost with no return. A release gives three files again: the
  APK, the Windows installer and the portable zip.

### Fixed
- The file request card stretched across the full window width on a monitor. It
  is now capped at 560 px.

> The commit message for this release calls it a security release. That is
> wrong: the three fixes described below shipped in 0.3.0, because the commit
> carrying them is contained in the `v0.3.0` tag. This release is content and
> tooling, plus the one UI fix above.

## [0.3.0] - 2026-09-03

"More comfortable and better looking": the app should feel at home on a large
monitor and on a phone with gestures, and a received file should be saveable
where the user looks for it.

### Added
- **Two panes from 900 px wide**: the conversation list beside the open
  conversation, with no jumping between screens. Narrower windows work as
  before.
- **Saving a received file** where the user looks for it: one tap in the
  bubble, or an entry in the menu. On Android images go to `Pictures/Chatt` and
  everything else to `Download`, through MediaStore, so with no permission at
  all from Android 10. On the desktop, the system save dialog.
- **Backgrounds**: four gradients plus "no background", each with a light and a
  dark variant, stored in settings (schema v8).
- **A Windows installer** (Inno Setup) alongside the portable zip, built in the
  same release workflow. A per-user installation, so no UAC prompt.
  Uninstalling sweeps the autostart entry but leaves the database alone.
- Tighter spacing (`VisualDensity.adaptivePlatformDensity`) with content width
  capped at 560 px for bubbles and 760 px for forms.

### Fixed
- **Android API 35**: the system draws its bars over the app without narrowing
  the window, so scrollable lists were running under the gesture bar. They now
  add a bottom margin the height of the bar.
- The brightness of the system bar icons with a transparent app bar. Flutter
  derives it from the bar colour, and that colour was gone, so the icons turned
  white on a light background.

### Security
Three holes found in a review, all exploitable by **any device on the same
network**: since 0.2.0 encryption does not require pairing, so anyone can open
a session. Every one of them has a test in `test/security_test.dart` that was
red before the fix.

- **Escaping the app directory through the message identifier** (serious). An
  identifier from the network went straight into file names under
  `.incomplete/`. `../../../x` allowed deleting an arbitrary `.json` file
  (refusing the file was enough) and, after accepting, overwriting an arbitrary
  `.part` file with the sender's content. On Windows that reaches everything
  the user account reaches. Fixed with two barriers: the protocol accepts only
  identifiers shaped like a UUID, and the on-disk name comes from a hash rather
  than from the identifier itself.
- **Filling the whole disk with an accepted file** (medium). The receive loop
  checked the announced size only after the stream ended, so agreeing to 2 MB
  let the sender pour bytes forever. Reception now aborts the moment the size
  is passed.
- **Taking the app down with a request size** (medium). A POST body was read
  into memory in full before the session was checked, so a multi-gigabyte JSON
  from anyone on the network ended in an out-of-memory failure. The body is now
  capped at one megabyte, with a 413.

## [0.2.0] - 2026-09-03

"Always encrypted": nobody on the network can eavesdrop on a conversation,
whether or not the devices have managed to pair.

### Changed (breaking)
- **A device's identity is its key, not a random GUID.** The identifier is now
  derived from the public key (`sha256(key)`, the first 16 bytes, formatted
  like a UUID), so nobody can claim another device's identifier without its
  private key. The cost, accepted deliberately: every device gets a new
  identifier, so the migration to schema v6 clears the device list and the
  history rather than leaving entries nobody can talk to. Conversations and
  pairings have to be set up again.
- Pairing changed role. It no longer establishes the encryption key, which is
  now ephemeral; it only confirms an identity, and its result is the green
  shield.

### Added
- **A handshake per session** (`POST /handshake`) in the Noise KK pattern. Both
  sides know each other's static key, add ephemeral ones, and the combined
  agreements yield a key valid only for that session. A session lives one idle
  hour and only in memory, which is the whole mechanism behind **forward
  secrecy**: traffic recorded today does not decrypt after a later device
  theft.
- **Confirmation by QR code**: one device shows `chatt://pair?...`, the other
  scans it. The scanner is certain right away; the scanned device is asked "was
  that you scanning", because somebody else could have seen the code. Comparing
  six digits stays as the fallback where there is no camera.
- **A security panel** under the shield: the encryption state in words plus the
  fingerprints of both keys, openable at any time rather than once.
- **An encrypted database on disk** (SQLite3MultipleCiphers). The 32 byte key
  sits in `chatt.key` wrapped by the system keystore: AES-GCM under Android
  Keystore, DPAPI on Windows. A plaintext database from an older version is
  rewritten on the first start with its history intact.
- **Clear history** and automatic deletion of messages older than 7, 30, 90 or
  365 days, off by default (schema v7).
- **Windows: a tray icon, starting minimised and autostart.** The X hides the
  window instead of ending the listening; quitting is in the icon menu.
  Autostart is a user registry entry with a `--minimized` argument, with no
  administrator rights.
- Sending several files at once and dragging them onto the window on the
  desktop.
- Image thumbnails in a conversation, shown only after the file is accepted.
- Search inside a conversation and on the conversation list.
- Deleting single messages by long-pressing a bubble. The label says outright
  that the message disappears from this device only.

### Security
- **Plaintext is gone from the protocol** (version 5). An unpaired peer is
  encrypted exactly like a paired one, and a request without an envelope bound
  to a live session gets a 409 instead of an answer.
- The sender's guid left the clear part of the envelope. Only the session
  number remains, changed at every handshake, so an eavesdropper cannot even
  see who is talking to whom.
- The file key is derived from the session key, and its tag travels in the
  announcement and is stored next to the partial transfer. A mismatch forces
  the transfer to start from zero instead of decrypting garbage with a new key
  over old bytes.

### Known cost
A restart on either side during a transfer loses the progress, because the file
key hangs off the session key. A network drop of seconds or minutes resumes
normally. Deriving the file key from the static keys would fix it at the price
of decrypting every previously recorded file after an identity theft, which is
the very thing this release exists to prevent.

## [0.1.0] - 2026-09-02

The first release: a working messenger for a PC and an Android phone on one
Wi-Fi network, with no server.

### Added
- **Discovery over UDP** (port 47777). The query carries the scanner's
  identity, so one scan teaches both sides. Adding by `IP:port` by hand when a
  router isolates its clients.
- **Messages over HTTP** with a delivery status (saved, delivered,
  acknowledged), retrying failed ones with one tap, and dedupe by message GUID.
  A conversation list and a chat screen, both fed by streams from the database.
- **File transfer with the recipient's consent**: the announcement carries the
  name, size and sha256, and bytes flow only after acceptance. A refusal, or no
  answer within two minutes, means zero bytes transferred. An interrupted
  transfer resumes from an offset and is verified with a checksum; abandoned
  parts are swept after seven days. Opening, sharing and copying the path of a
  received file.
- **Pairing by comparing a six-digit code** (protocol 4), with a commitment to
  the public key sent before it is revealed, so an attacker in the middle
  cannot pick keys to make the codes match.
- **Encrypted traffic between paired devices**: AES-GCM envelopes for messages
  and file announcements, an AES-CTR stream for file content so that resuming
  keeps working. From a paired device only encrypted traffic is accepted.
- **Signed discovery answers**: a scan carries a random nonce and a paired
  device adds an HMAC, so somebody who knows a GUID cannot take its place in
  the list and capture the traffic when an IP changes.
- Following a peer's IP change: a failed send starts a scan, finds the same
  GUID at a new address, saves it and retries.
- **Background listening on Android**: a foreground service with a permanent
  notification, a MulticastLock so discovery survives with the screen off, and
  message notifications with the window closed. Verified in Doze on a real
  phone.
- A dark mode, an app icon, a Polish and English interface (schema v4 and v5)
  and a sweep of unused device entries.
- Documentation in `docs/`, CI on GitHub (tests on a pull request to `master`,
  a release on merge) and a release build signed with our own key.

### Known limitation
Traffic between devices that had not paired still travelled in plaintext. That
is what 0.2.0 is about.

[Unreleased]: https://github.com/Mysttic/Chatt/compare/v0.4.0...develop
[0.4.0]: https://github.com/Mysttic/Chatt/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/Mysttic/Chatt/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/Mysttic/Chatt/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Mysttic/Chatt/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Mysttic/Chatt/releases/tag/v0.1.0
