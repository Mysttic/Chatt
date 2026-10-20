# Changelog

Everything worth knowing about each release of Chatt. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the numbering
follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

The release number lives in [VERSION.md](VERSION.md) and is what triggers a
release: the workflow starts only when that file was among the changes merged
into `master`.

## [0.12.0] - 2026-10-20

Three new things around the app's data and the rest of the new look. With
Keyboard from a PC both devices now keep a typing history in their encrypted
database (on by default, with its own switch), each device keeps an app log
for diagnostics, and Settings can export the app's data to one ZIP file. In
every style each conversation is its own card, and each style moves in its
own way. Short messages keep their time with Remove animations on, and a
screen reader reads the message field as a field of its own.

### Added
- **Typing history for Keyboard from a PC** (issue #50). Both devices keep a
  record of every typing session in their encrypted database: which device
  typed on which, when, how the request was answered and why the session
  ended, and what was typed, piece by piece, with the app it went into and
  whether it landed (typed, not typed, paused, refused, unconfirmed, not
  sent). Text typed into a password field or a field of unknown kind is kept
  as a number of characters, and so is a piece the typing device sent with no
  answer saying where it went. A **Save typing history** switch on the
  add-on's card, on by default, turns it off on that device, since each device
  keeps its own history, and an add-on that is off records nothing. During
  steady typing a piece goes to the database about 5 seconds after it
  started. **Delete messages older than** and **Clear history** take the
  typing history along, and **Clear typing history** deletes it alone. Both
  sides write a session under the same request id, so the two records can be
  laid side by side.
- **App log** (issue #50). Each device keeps a diagnostic log in its
  encrypted database: connections and their road, pairing, file transfers,
  shared history, Bluetooth, keyboard sessions, update checks and uncaught
  errors, each entry with a level and an area. It never holds message text,
  typed text, pairing codes, keys, remote-input tokens or window titles.
  Identical entries in a burst are written once, followed by one entry with
  ` (repeated N times)`. Entries older than 30 days go, at most 20,000 stay,
  and **Clear the log** on the App log screen deletes them all. **Quit Chatt**
  in the Windows tray menu and every move to the background save what the log
  and the typing history hold in memory.
- **Export data** (issue #50). One ZIP with the parts picked in a dialog:
  conversations with devices and settings, the typing history, the app log,
  and received files with their size shown. JSON for programs, text for
  reading, a `README.txt` and a `manifest.json`. No private key, session key
  or database key goes in, and the file is not encrypted. Android 10 and newer
  save it to Downloads. Older Android, or a failed copy to Downloads, hands it
  to the share sheet, and that copy waits in the app's cache until the next
  export, **Clear history**, **Clear typing history**, or the next start once
  it is an hour old. Windows asks with the save dialog, and the app asks
  before replacing a file the dialog did not ask about. The archive is
  written to `<name>.part` and replaces the target only when complete, so a
  failed export leaves no partial file.
- **Data and diagnostics**, a new Settings section between Privacy and
  Add-ons, holds App log and Export data, plus Typing history once at least
  one session is saved.
- Schema 16: the tables `typing_sessions`, `typing_entries` and `app_log`, and
  `settings.typingHistory`, on by default.

### Changed
- **The keyboard keeps a typing history.** The 0.10.0 notes said that typed
  text is stored nowhere. Since this release, with the keyboard add-on and
  **Save typing history** on (the default), both devices keep what was typed
  in their encrypted database, text for password fields as a number of
  characters. The app log holds no typed text.
- **Clear history** and **Delete messages older than** cover the typing
  history as well. The app log keeps its own 30 days and has its own
  **Clear the log**.
- **The documentation follows.** The privacy policy covers the typing
  history, the app log, the export and how each is deleted.
  `docs/SECURITY.md` takes the three into scope and lists the plaintext
  export, the typing history and the missing app lock among the intended
  things. `docs/architecture.md` describes schema 16, the typing history, the
  app log, the export and a fifth FileProvider root. Both keyboard pages gain
  a Typing history section, both guides a Data and diagnostics section, and
  the READMEs and the documentation index list the new features. The bug
  report form suggests attaching an export with the app log alone.
- **Every conversation is its own card, in every style** (issue #54). Calm
  and Precise laid the list in one panel on the screen background, which gave
  a double background and a panel running on under the system navigation bar.
  Each conversation is now a separate card with the style's surface, corners
  and shadow (an outline in Precise), 8 dp apart, and the last one scrolls out
  from under the Nearby button.
- **Each style moves in its own way** (issue #54). Screens slide in along a
  shared axis, consent cards and dialogs come in with the style's scale and
  offset (Warm with a small bounce), a new message rises into place, progress
  bars glide between readings, short messages in the corner slide in and fade
  out, and the scrim behind dialogs and sheets fades in the style's time.
  Changing the style, the theme or the background is a crossfade. With
  Android's **Remove animations** every transition is a 100 ms fade.
- On Windows the security panel opens as a window in the middle, at most
  460 px wide; on a phone it stays a sheet from the bottom.
- Short messages in the corner stay 3.2 s in Calm and Warm, 4.2 s in Precise.
- The banner (`docs/promo.png`) in Calm's colours and font. The app icon stays
  the same.
- The Windows screenshots in the documentation show the new list, the
  security panel as a window and the density of the app on a PC.
- The Android screenshots in the documentation and in the Polish guide show
  Calm, light and dark, in Polish and in English.

### Fixed
- **Short messages vanished at once with Remove animations on.** Android's
  setting makes Flutter shorten animations to a twentieth, and the message's
  countdown was one of them, so "Copied" stood for a fifth of a second. The
  countdown and every transition the app runs itself now keep their time.
- **A screen reader read the whole conversation as one text field.** The
  message field now has a node of its own, the size of the field.
- On a phone the theme picker in Settings wrapped "Systemowy" in the middle of
  the word; on a narrow screen it shows the names alone, as the style picker
  does.
- The save button on a file bubble and the search field at the top of a
  conversation and of the list are 48 dp tall on a phone.

## [0.11.0] - 2026-10-19

Two bigger things and two fixes. A conversation's history can come back from
the other device after a reinstall or a new phone. The app has three looks to
pick from, each light and dark. A phone can show itself over Bluetooth so that
another phone finds it, and on Windows a link with `=` in it opens in the
browser again.

### Added
- **Getting a conversation's history back** (issue #36). A conversation lives
  on both devices, so when one loses it (a reinstall, a new phone, "Clear
  history", automatic deletion) the other can hand its copy back: **Share
  history** in the conversation's menu (everything or since a date, with files
  or without), or **Ask for history** on the side that lost it. The receiving
  side gets a card with the counts, the date range, the shield and what comes
  back; restored messages keep their times and directions, arrive read,
  raise no notification and carry a history icon. Files follow under the same
  consent, received files still on disk are linked without travelling again,
  and sharing again resumes without duplicates. After a reinstall or on a new
  phone the old conversation stays under the old entry; once the new entry has
  a green shield, the share dialog can hand the older conversation over and
  merge the two on the sharing side. Both progress bars have **Stop**. New
  routes `/history-offer` and `/history-chunk`, schema 14
  (`messages.restoredAt`).
- **Dates in the conversation.** The first message of each day gets "Today",
  "Yesterday" or the full date above it.
- **"File not available"** on a file bubble whose content is not on this device.
- **Three styles** (issue #37): **Calm** (Cisza), **Precise** (Precyzja) and
  **Warm** (Ciepło), each in a light and a dark variant, picked in Settings
  under Appearance. They change looks alone (colours, fonts, corners, density,
  avatars, bubbles); every screen shows the same information in each. Each
  style has its own fixed-width font for addresses, identifiers, fingerprints,
  the pairing code and file sizes, and the five backgrounds follow the style.
  Schema 15 (`settings.style`), Calm by default.
- **"This device" panel** at the bottom of Settings: the addresses the device
  listens on, its Bluetooth address, the identifier and the key fingerprint,
  each with a copy button.

### Changed
- The top of the conversation list shows this device's name; the version
  number moved to Settings, under Updates.
- On a phone the conversation's header holds only the shield and the menu;
  search and the keyboard from a PC moved into the menu. The shield sits on a
  background in the colour of its state.
- Settings follow a new order (Profile, Appearance, background listening,
  Windows, Links, Updates, Privacy, Add-ons, This device), and the add-on cards
  carry a one-line description.
- Security warnings use the style's warning frame: red in Calm, amber in
  Precise and Warm. No encryption stays red everywhere.
- The route on the conversation list is an icon alone, with its name in the
  tooltip.

### Fixed
- **A link with `=` in it opened the Documents folder on Windows** (issue #31).
  The address went to `explorer.exe` as an argument, and Explorer splits its
  command line on commas and equals signs. It now goes to `ShellExecuteW` as
  one string, through a small native channel that checks the scheme once more.
- **A phone can show itself to devices nearby.** Android is visible over the
  radio only while its own pairing screen stands open, so a Bluetooth search
  from one phone never found another. In Nearby, with Bluetooth picked,
  Android has **Show this phone nearby**: it opens the system's prompt that
  makes the phone discoverable for two minutes, and while it is, a note stands
  in place of the button. A search that finds nothing now says to show the
  other phone first. A PC needs none of this: the add-on keeps it visible.
  New permission `BLUETOOTH_ADVERTISE`, granted together with the add-on's
  Nearby devices permission, without a question of its own.

## [0.10.0] - 2026-10-16

A second add-on: typing on a PC's keyboard into the field that has focus on
another device, in any app, for phones, tablets and touch-only PCs with no
keyboard of their own. Windows types into the window in front, Android through
a keyboard of Chatt's own, and every session starts with consent on the
receiving device.

**Keyboard from a PC, in short.** Turn the add-on on in Settings, Add-ons, on
both devices, and on the device you want to type on also "Allow typing on
this device" (on Android, turn the Chatt keyboard on once in the system, from
the add-on's card). Then open the conversation with that device on the PC and
pick the keyboard button at the top. Over there a card asks for consent; on
Android, Accept also offers the keyboard picker. Tap the field you want, and
what you type on the PC lands there: Live sends each character as you type
it, Compose sends a whole text in one go, and Paste from clipboard sends the
PC's clipboard text. On Windows a floating bar with Stop stays on top for the
whole session; on Android the Chatt keyboard's bar with Stop shows where the
keyboard usually is, and the permanent notification says who is typing until
the session ends. A line on the PC says where the typing goes or why nothing
gets typed. Only between devices with a confirmed identity, encrypted like
messages, over the network or the radio, and nothing typed is stored
anywhere. Every step is pictured in
[docs/keyboard.md](docs/keyboard.md) ([polski](docs/keyboard.pl.md)).

### Added
- **Keyboard from a PC, the second add-on.** Settings → Add-ons gains a card
  for it, off by default and under the rules the Bluetooth add-on set: while it
  is off no other screen shows it and its native channel gets no call apart
  from the switch itself. With it on, the card holds a second switch, "Allow
  typing on this device", which also starts off: turning the add-on on at the
  PC that types lets nobody type on that PC. Turning the add-on off turns
  receiving off in the same step, so turning it on again does not quietly
  bring receiving back.
- **A consent card for every typing session.** Only a device with a confirmed
  identity can ask. The card puts the focus on Reject, so an Enter pressed
  while typing elsewhere can only refuse, and two minutes of silence count as
  no answer. A "Don't ask again for this device" checkbox on the card, and
  "Typing without asking" in the conversation's security sheet, skip the card
  for one verified device. While a session lasts, a bar above the whole app
  shows who is typing and where, with Stop.
- **The sender's screen.** A keyboard button in the conversation's bar, there
  only with the add-on on and active only for a verified device, opens a
  screen of its own. Live mode sends each character as it is typed: Enter is
  the field's action, Shift+Enter a newline, Backspace and Delete delete over
  there. Compose mode sends a whole text at once. Paste from clipboard sends
  the clipboard's text. The field is masked until the other side reports an
  ordinary text field, and a password typed under the mask stays masked;
  undo shortcuts and suggestions are off. Typing is possible only while the
  other side can take it: a status line says where the typing goes or why
  nothing is typed (a locked screen, an administrator's window, no field, a
  question waiting on either device), and a session that broke off can be
  reconnected.
- **`POST /input-session` and `POST /input`**, on both roads, the network and
  the radio. A session starts with a request; the sender's packets then carry
  text, Backspace, Delete and the field's action (Enter, or Search, Send, Go,
  Next, Previous and Done on Android), one packet in flight, with everything that queued
  up meanwhile merged into the next. A packet that got no answer goes again
  under the same number and lands once. The protocol version stays 5: a peer
  without these routes answers 404.
- Schema v13: `settings.keyboardEnabled`, `settings.remoteInputReceive` and
  `peers.remoteInput` ("don't ask again" per device), all false. The last one
  can be set only for a verified device and goes with the shield, like
  `autoAccept`.
- `chatt/remoteinput`, the channel to the native receivers: `status`, `apply`,
  `setSession`, `holdOwnApp`, `setImeEnabled`, `showIndicator` and
  `hideIndicator`, plus
  `stopRequested` from the native side.
- **Typing on Windows.** A PC with Windows 10 or 11, touch screen or not, types
  what arrives into the window with the focus (`SendInput`, independent of the
  keyboard layout), one character at a time: 10 ms apart and 40 ms after a
  space or Enter, because the Windows 11 Notepad lost or repeated characters
  typed faster, Polish letters most of all. It refuses while the lock screen
  or an administrator's window is in front; Chatt's own window takes typing
  like any other, except while a question card waits there or the PC is
  itself typing on another device. Stop cuts even a long paste short at
  once. The sender learns
  the program's name and whether the field is a password (UI Automation). A
  floating bar with Stop stays on top for the whole session without ever taking
  the focus, the tray icon gets a badge and a Stop in its menu, and a consent
  card pulls the hidden window out and sends it back after the answer.
- **Typing on Android through the Chatt keyboard.** The add-on brings a
  keyboard with no keys: a bar saying who types and where, with "Switch
  keyboard" and Stop. It types into the focused field of any app, Chatt and
  password fields included, following the focus from app to app, and refuses
  on a locked screen. After a lock screen with a text password, which gets the
  ordinary keyboard back, "Switch the keyboard to Chatt" comes again once the
  phone is unlocked.
  It is listed among the system's keyboards only while the add-on is on; the
  add-on's card leads to turning it on once. A consent accepted on the card
  offers the keyboard picker and steps out of the way; the previous keyboard
  comes back when the session ends. The permanent notification says who is
  typing for the whole session.

### Security
- **The first sealed replies in the protocol.** Both routes answer 200 and
  403 inside an envelope, refusals included, padded like the requests to 512
  bytes and above that to a multiple of 64, so one keystroke looks like any
  other. The plain answers left (409, 400, 404, 413, 500) say nothing about the
  add-on. An
  unverified sender hears `rejected` whatever the settings, so only a verified
  device can learn that the add-on is on.
- **Consent is checked again on every packet**: the shield, the add-on and the
  receive switch, read from the database. A grant lives in memory, ends after
  30 minutes without typing or 8 hours in all, and is bound to a token the
  receiver draws, so a packet recorded earlier types nothing. A request id
  works once, remembered per sender and only for verified senders, so a flood
  of requests from elsewhere cannot make a recorded one count again.
- **Nothing is typed while a card waits** on the receiving device, so a remote
  Enter cannot answer a question nobody read.
- **The typed text is stored nowhere** on either side: no database, no log, no
  app state.
- **A handshake answer cannot take over another session's number.** The
  responder picks the session number, and numbers travel in the clear. The
  side that opened the handshake refuses a number that already names a session
  on its side, so another device's incoming session keeps its key.
- The threat model grows: the add-on gives a verified device typing on an
  unlocked, running device, over the radio too when Bluetooth is on.
  `docs/architecture.md` and `docs/SECURITY.md` say what that means for a
  stolen verified device.

### Changed
- **A page of its own for the keyboard**: `docs/keyboard.md` and
  `docs/keyboard.pl.md`, step by step with screenshots from Windows (both
  languages) and Android: turning it on, the Chatt keyboard and Android's
  two warnings, consent, the picker, Live and Compose, passwords, the bars and
  notifications on the device being typed on, every status line, lock
  screens, stopping, typing without asking, Bluetooth, security, the measured
  speed and a troubleshooting table. The READMEs, the documentation index and
  the guide link to it.
- **Both READMEs, the user guide and the privacy policy cover the add-ons.**
  The READMEs gain an Add-ons section for Bluetooth and the keyboard, the guide
  a section on typing from a PC's keyboard in both languages, and the privacy
  policy the Bluetooth permissions and name, the Chatt keyboard and the typed
  text, which Chatt stores nowhere. The bug report form lists both add-ons.
- `docs/building.md` and `VERSION.md` name all three files that carry the
  version number, `app/lib/core/version.dart` included, and so does the
  release workflow's error when the numbers disagree.
- The add-on's card on Android says that the Chatt keyboard sends nothing
  from your fields. It does look at the kind of field and whether something
  is selected, which "reads no fields" left out.

### Fixed
- The conversation's security sheet scrolls. On a low window or with a large
  font its switches and pairing buttons ran off the bottom of the screen.

## [0.9.0] - 2026-10-14

A conversation can travel over Bluetooth, so two devices talk with nothing
between them: no shared network, no router, no system pairing. Bluetooth is an
add-on, off by default. While it is off, nothing in the app touches the radio
and every conversation travels over the local network, as before.

This release also carries 0.8.2, which was never published on its own: a
photo in a conversation opens in a preview with zooming and turning.

### Added
- **Add-ons, with Bluetooth as the first one.** Settings gains an "Add-ons"
  section. While the Bluetooth add-on is off it exists nowhere else in the app:
  no other screen shows it, nothing listens on the radio, the native side gets
  no call apart from the permission check while the switch is being turned on,
  and the local network is the only road. Android asks for the Bluetooth
  permission when the add-on goes on, and again only from the add-on's card
  if the permission is taken away later.
- **Bluetooth as a second way of reaching the other device.** With the add-on
  on, the network and the radio run side by side: the app tries the network
  first and falls back to the radio by itself, so there is nothing to choose
  per conversation. The add-on's card shows the radio and permission state,
  this radio's address on Windows, and a local network switch for when the
  radio should be the only road. A radio turned on later, or switched off and
  on in the system, brings the add-on back up by itself.
- **The "Nearby" screen asks which way to look**, the network or Bluetooth,
  while the add-on is on. Bluetooth is offered once the radio is running. The
  radio cannot say who is running Chatt, so every device in range is asked,
  and one that does not answer as Chatt never appears on the list. Computers
  and phones are asked first and each device appears the moment it answers. On
  Android the screen says when location services are off, since without them
  the system hands out no search results, and a radio address can also be
  typed in by hand.
- **The conversation list and the conversation header say which way a
  conversation is going** while the add-on is on: a Wi-Fi or a Bluetooth mark,
  with a caption inside the conversation.

### Changed
- **A device added by its address shows the padlock at once.** The key it
  reports when it answers is pinned right away, after a check that it matches
  the device's identity. Until now the key was pinned with the first message.

### Fixed
- **Presence and the key exchange count only an answer from the device
  itself.** When addresses on the network shift, another Chatt device can end
  up at the old address. It used to show the conversation as online; now the
  app moves on and looks for the right device.

### Security
- **System pairing is not required and buys nothing here.** The handshake, the
  encrypted envelopes, the file stream, the consent for a batch of files and
  the confirmation by code or QR run over the radio exactly as they are. The
  green shield still comes only from a code or a QR scan.
- With the add-on on, a new neighbour joins the threat model: somebody in
  radio range, about 10 m, next to somebody on the same network. In the clear
  are the device's Bluetooth name and the radio's MAC address, exactly as UDP
  discovery is in the clear today.
- With the add-on on, a computer is discoverable to everybody nearby, and the
  add-on's card says so. Turning the add-on off takes the discoverability with
  it.

### Known cost
Bluetooth carries 90 to 165 kB/s, which is 50 to 100 times slower than Wi-Fi:
a megabyte takes 6 to 12 seconds. A short message turns around in 22 to 25 ms,
so text feels the same either way. Files are where it hurts.

## 0.8.2 - 2026-09-21

Never published on its own: it reaches users inside 0.9.0.

A photo in a conversation opens right where it is, in a preview of its own.

### Added
- **Tapping a photo opens it full screen, with zooming and turning.** Pinch or
  scroll to zoom, drag to move around, double-tap to zoom in on a spot and
  again to fit it back; the button in the corner turns it ninety degrees at a
  time. Turning affects what you are looking at and never the file, which stays
  byte for byte what arrived. The actions from the conversation — save, share,
  copy the image, open it with the system — are in the top bar, and Esc closes
  it on a PC.

  Chatt draws the picture itself, with the decoder it already used for
  thumbnails and under the same rule: only a file you have accepted and that
  already lies on disk. Nothing is handed to another app, so the commonest
  thing anyone does with a received photo no longer depends on there being an
  app installed that shows pictures, nor on the file being one Android lets us
  hand out at all. Other files open with the system association as before.

### Fixed
- **Tapping a photo you sent yourself said "Could not open the file."** On
  Android a file only reaches another app through FileProvider, and FileProvider
  serves nothing outside the roots listed in `res/xml/file_paths.xml`. That list
  held the received files and a downloaded release — but an outgoing message
  keeps the path it was handed, and every way of sending a picture from a phone
  puts it in the app cache first: the picker, the clipboard, and the keyboard's
  own "insert image". So the thumbnail drew fine, and touching it failed. The
  cache directories holding those copies are now served too, which also fixes
  "Share" on your own file, and which is the narrow fix: the two subdirectories
  the user actually picked from, not the whole cache.

  Received photos were never affected, which is why this looked like it
  depended on the photo rather than on who sent it.
- **"Could not open the file." no longer covers a file that is simply gone.**
  The channel answered `true`/`false`, so a missing file and a refused handover
  arrived as the same failure; it now answers with a word, and a file Android
  swept out of the cache says so. The exception behind a failure goes to logcat
  instead of vanishing into a `catch`, because the old message said nothing
  anyone could act on — including us, while working out what this issue even
  was.

## [0.8.1] - 2026-09-18

Sending someone a handful of files asked them a handful of times. Now it asks
once, and the question says what it is asking about.

### Changed
- **Several files sent together now cost one question, not one per file.** The
  card names every file in the batch and gives the total size, and a single
  "Accept all" covers the lot; the files still travel one after another, each
  with its own progress. A refusal refuses the whole batch and travels back as
  `batch-rejected`, so the sender stops instead of announcing the rest, which
  matters more than it sounds: every announcement means a full sha256 of the
  file, and three hundred phone videos are hundreds of gigabytes read off the
  disk for nothing.

  The consent is worth exactly what was announced. The first announcement
  carries the batch identifier, the count, the total size and the names; the
  recipient remembers the decision per (sender, batch) and honours it for at
  most that many files, at most that many bytes and only those names. A
  description that does not describe its own announcement is dropped on
  arrival, so nobody attaches a list of three innocent names to something else
  and gets it accepted under them. Re-announcing a file that was already let in
  is free, which is how a resumed transfer works, but only while it is still
  the same name and the same size. Two clocks bound the consent: thirty minutes
  of silence counted from the last file that used it, and six hours from the
  moment it was given, which nothing can push. Anything outside all that falls
  back to an ordinary per-file question. Silence is not a refusal: the
  two-minute timeout decides nothing, the sender keeps repeating the
  description until somebody answers, and a refusal of any file of a known
  batch stops it. The fields are optional, so a peer running an older version
  asks per file as before.

### Fixed
- **The size in the transfer header is now checked against the announcement.**
  Under encryption the headers are not authenticated and the announcement is,
  but the write loop was bounded by the header alone, so a consent for one
  100 kB file let the sender push as many bytes as it liked and, with no
  checksum in the announcement, keep them. Found while working out what a
  batch consent could promise: it could not promise anything about bytes until
  this was closed.

## [0.8.0] - 2026-09-18

What lies on the clipboard goes into a conversation without a detour through a
folder.

### Added
- **A file or an image goes from the clipboard straight into a conversation.**
  On the desktop that is Ctrl+V on the conversation screen, wherever the focus
  happens to be except somebody else's text field, where Ctrl+V already means
  something; the paperclip also asks "a file from this device" or "paste from
  the clipboard",
  but only when there is something to paste, so the ordinary path stays one
  click. Files copied in Explorer travel as they are, without a copy, exactly
  like files dragged onto the window. An image with no file behind it
  (Win+Shift+S, "copy image" in a browser) is written out as a PNG in the
  temporary directory first, under a name that follows the app language.
  Text on the clipboard wins over a picture: a range of cells copied in Excel
  or a paragraph from Word carries a bitmap of itself, and Windows will even
  synthesise one from a bare `CF_BITMAP`, so without that rule pasting a few
  numbers into the message field would have sent the other side a screenshot
  of them as well.
- **The keyboard's own "insert image" button works on Android.** GIFs,
  stickers and screenshots offered by Gboard used to end in "this field does
  not accept that", because a Flutter text field declares no content types
  unless it is told to. On a phone this is the shortest way to send a picture,
  and the clipboard is not involved at all: the bytes arrive from the engine.
- The `chatt/clipboard` channel grew the reading direction: `hasFiles` and
  `pasteFiles`. On Windows (`windows/runner/chatt_clipboard.cpp`) `CF_HDROP`
  gives the paths back untouched, the registered `PNG` format is written out
  byte for byte, and only a bitmap goes through WIC. Two traps cost a while
  each. The `CF_DIBV5` the system synthesises from a plain bitmap carries the
  channel masks **twice**, in the header and again behind it, and a reader
  that trusts `biSize` starts three pixels early and skews the whole image;
  the pixels are now located by where they have to end, not by where the
  header says they begin. And `GlobalSize` measures the memory block rather
  than the data, so the `PNG` payload is cut at its `IEND` chunk instead of
  carrying whatever lay past the end. On Android (`ChattClipboard.kt`) the
  cheap question goes to `getPrimaryClipDescription`, the one read that
  Android 12 does not announce with "app pasted from your clipboard", so the
  paste entry can appear exactly when it is useful without the system
  accusing Chatt of watching the clipboard.

### Changed
- **The release workflow no longer goes through Actions artifacts.** The
  first run of 0.7.1 built the APK and the installer and then died on
  `upload-artifact` with "Artifact storage quota has been hit", which is a
  limit shared by the whole account. Now the `wersja` job opens a draft
  release, each build uploads its file straight into it with
  `gh release upload`, and the `wydanie` job publishes the draft once all
  three files are there. A draft is invisible to people and to the in-app
  update check, and the tag appears only at publication, so a failed run
  leaves nothing half-done behind; the next run deletes stale drafts first.

## [0.7.1] - 2026-09-16

A phone handed a large file used to die on the spot. Now it sends it.

### Fixed
- **Attaching a large file on Android no longer kills the app.** The paperclip
  went through `file_selector`, whose Android side reads the whole chosen file
  into a byte array and ships it over the platform channel to Dart, which only
  ever looked at the path. A 150 MB zip needed two copies of itself in a
  256 MB Java heap and died with `OutOfMemoryError` in `onActivityResult`,
  twice in a row on a Pixel 9 Pro. Android now has its own picker on the
  `chatt/files` channel (`ChattFilePicker.kt`): the system document picker,
  then a buffered copy of each file into the app cache on a worker thread, and
  only the paths cross to Dart. Desktop keeps `file_selector`, whose Windows
  and Linux pickers return paths only. Found in logcat's crash buffer; tried
  afterwards with a 1 GB file from an Android emulator with a 192 MB heap to
  the Windows app, checksum intact, Java heap flat at 5 MB.

## [0.7.0] - 2026-09-08

Links in messages look like links, ask before they lead anywhere, and can carry
a preview card. The preview is text and an image, and it stays off until you
turn it on.

### Added
- **Links in messages are tappable, and tapping one always asks first.** The
  card shows the server name on a line of its own, above the full address,
  because that name is the only part that decides whose page it is. Below it
  come warnings where they apply: an `@` in the address, letters from outside
  the Latin alphabet in the server name, no encryption, and an address on the
  local network. "Copy address" sits next to "Open". The same links appear as
  entries in the bubble's long-press menu, which is the reliable route on the
  desktop, where the tap belongs to `SelectionArea`.
- **Link previews**: a card under the message with the page's title,
  description and image, the way other messengers do it. Settings gains a
  **Links** section with the switch, off by default.
- Schema v11: `settings.linkPreviews`. Turning the switch off stops the
  fetching at once and drops what was already fetched.
- `openUrl` on the `chatt/files` channel, so a link opens in the Android
  browser without a plugin from pub.dev.

### Security
- **Only `http` and `https` become links.** `javascript:`, `data:`, `file:`,
  `intent:` and `content:` stay plain text, an address carrying invisible or
  direction-changing characters is not linkified at all, and the scheme is
  checked once more immediately before the address is handed to the system —
  a third time on the Android side.
- **Nothing from a previewed page is executed.** No WebView, no browser, no
  HTML tree: `<meta>` tags are read as text and the image bytes go to
  Flutter's own decoder. `image/svg+xml` is refused, because SVG is a document
  that can carry scripts. What is drawn has its entities decoded, whitespace
  collapsed, and control and bidi characters removed.
- **A preview is never fetched from the local network.** Loopback, private,
  CGNAT, link-local and unique-local addresses are refused, as are names that
  look local, and every DNS answer is checked rather than the first. Without
  this, a message reading `http://192.168.0.1/reboot` would make the app visit
  the router. Redirects are followed by hand, three at most, with the scheme
  and host re-checked at every hop.
- Hard limits on a preview: 8 s, 512 KB of HTML, 2 MB of image, a content type
  that has to match, and at most one card per message.

### Changed
- **The promise about the local network now names both exceptions.** README,
  the user guide, `architecture.md` and the privacy policy say that two things
  can reach outside, the update check and link previews, and that both are off
  until switched on.

## [0.6.0] - 2026-09-06

The app can now tell you a newer release is out, and put it on the machine for
you. It asks nothing until you let it.

### Added
- **Updating from inside the app.** Settings gains an **Updates** section: a
  switch for a daily question to GitHub about a newer release, a **Check now**
  button that asks regardless, and a card with the number, the release notes
  and a **Download and install** button. On Windows the Inno Setup installer
  runs with `/SILENT /CLOSEAPPLICATIONS` and the app steps aside; on Android
  the download goes to the system package installer, which asks for
  confirmation. The portable copy from the zip gets the release page address
  instead, because an installer would leave the running directory untouched.
- Schema v10: `settings.updateChecks` and `settings.lastUpdateCheck`.

### Changed
- **The promise about the local network now names its exception.** The switch
  starts off, and with it off nothing reaches outside. Turned on, the app asks
  `api.github.com` once a day with no token and no identifiers, and GitHub
  sees what any HTTPS server sees. README, `SECURITY.md` and `architecture.md`
  say so instead of claiming nothing ever leaves.

## [0.5.4] - 2026-09-06

The one button that leads out of an unreadable database now does something
when pressed, plus the housekeeping a repository needs before it goes public.

### Fixed
- **The "Start over" button on the startup screen now opens its confirmation.**
  It handed `showDialog` the state's context, which sits above `MaterialApp`
  and therefore above the navigator the dialog needs. Every tap threw
  `Null check operator used on a null value` into the log and left the screen
  exactly as it was, so the one way out of an unreadable database did nothing.
  Found on a phone with logcat open.

### Changed
- The test workflow asks for `contents: read` and nothing else. In a public
  repository it runs on code from other people's forks, and the default token
  is wider than a run that only reads the code needs.

### Removed
- Seven screenshots at the top of `docs/screenshots/`, left over from the
  first pass at the documentation. No page linked them and no tool rebuilds
  them.

## [0.5.3] - 2026-09-06

The Android side of the same story as 0.5.2: a phone that opened on a screen
saying it could not read its own database, with nothing to do about it.

### Fixed
- **Android no longer ends up with a database it has no key to.** The system
  backup was on (the default), so `chatt.key` travelled to the cloud and back
  while the Keystore material that wraps it never leaves the device. A
  restored phone woke up with a wrapped key nothing could unwrap. Both cloud
  backup and device-to-device transfer are now off, which also settles the
  older question of the conversation database quietly going to Google.
- **An unwrappable key is now a dead end you can walk out of.** The startup
  screen offers to start over: it deletes the database and the key, keeps
  received files, and asks first, because the history is gone either way.
  Until now the only way out was clearing the app's storage, which took the
  received files with it.
- The Keystore no longer mints a fresh key while unwrapping. A missing key
  used to turn into a failed decryption, which reads like a corrupted file
  rather than a missing key.

## [0.5.2] - 2026-09-06

Two ways of not starting, one of which hid the other. Found on a real
installation that stayed dead through 0.5.0 and 0.5.1.

### Fixed
- **A database whose column layout runs ahead of its own version number no
  longer kills the app.** If a process dies between an `ALTER TABLE` and the
  write of `user_version`, the column stays and the counter does not. The
  migration then started over and died on `duplicate column name: alias`,
  every single time, so the app never opened again. Each migration step now
  checks `PRAGMA table_info` and adds only what is missing, which also repairs
  a database already in that state.
- **A failure before the first frame is now visible.** The window appears only
  after the first frame, and the whole stack starts before `runApp`, so
  anything that threw on the way left a living process with no window, no
  error dialog and no entry in the event log. Startup failures now get their
  own screen with the error, and a `chatt-startup-error.txt` next to the data
  with the stack trace.

## [0.5.1] - 2026-09-05

A package that starts on a computer which has never had Visual Studio on it,
and marks on the conversation list that say who is confirmed and who is
answering right now. The licence and the files a public repository needs land
here as well.

### Fixed
- **The Windows release starts on a computer that has never seen Visual
  Studio.** `chatt.exe` and two of the plugins link against the MSVC runtime
  (`MSVCP140.dll`, `VCRUNTIME140.dll`, `VCRUNTIME140_1.dll`), and neither the
  zip nor the installer carried it. Without those libraries the process ends
  before it draws a window: no error dialog, nothing in the event log, the same
  silence from both packages. The build now puts them next to the executable,
  and the release workflow refuses to publish a package without them.

### Added
- **The version number is visible in the app**: next to the name in the
  conversation-list bar, and in Settings under "This device". One constant in
  `lib/core/version.dart`, raised together with `VERSION.md` and `pubspec.yaml`
  by `tool/wersja.py`, with a test that catches a file left behind.
- **A green shield on the conversation list** for a device whose identity you
  confirmed, the same mark the device list and the conversation header use.
- **A green dot on the avatar** for a device that is answering right now. The
  list asks every known device every 30 seconds, and only while it is on
  screen.
- **A licence.** Apache 2.0, in [LICENSE](LICENSE) and [NOTICE](NOTICE), the
  same one the other Mysttic project uses. Until now the repository had none,
  which means nobody was allowed to use any of it.
- **[Third-party notices](docs/THIRD-PARTY-NOTICES.md)**: every component that
  ships inside the app, with its licence and copyright. The Dart packages split
  into Apache-2.0, MIT and BSD-3-Clause; alongside them are SQLite,
  SQLite3MultipleCiphers, the bundled Roboto and Material Icons fonts, and
  Google ML Kit, which is proprietary and rides along in the Android APK
  through `mobile_scanner`.
- `app/fonts/LICENSE`, because four font files sat in the repository with no
  licence next to them.
- **[docs/README.md](docs/README.md)** as the documentation index, plus
  [CONTRIBUTING.md](docs/CONTRIBUTING.md),
  [SECURITY.md](docs/SECURITY.md) and
  [CODE_OF_CONDUCT.md](docs/CODE_OF_CONDUCT.md) (Contributor Covenant 2.1).
- Issue templates for a bug and a feature request, and a pull request template.
- `brand/icon.svg`: the app icon as vector, matching the geometry that
  `app/tool/make_icons.py` draws.

### Changed
- Both READMEs open with the banner, the one-line pitch and three badges
  (licence, latest release, tests), and close with the licence.
- **The device list starts empty.** It used to open with everything the app had
  ever seen on the network, which reads like the result of a scan that never
  ran. Now it shows what the last scan answered, plus anything added by
  address.
- Nine interface strings in each language lost the em dash they were written
  with: a colon, a comma or a full stop carries the same sentence.

### Removed
- The store materials (`docs/publishing/`): finished Google Play and Microsoft
  Store copy, graphic dimensions, questionnaire answers, a publication
  checklist and positioning notes, for a channel that was rejected. The privacy
  policy stays, as `docs/privacy-policy.md`, because it is useful to anyone who
  runs the app.
- The prototype mockups (`docs/mockups/`) and `tool/ui_e2e.sh`, a UI scenario
  under Xvfb for a platform that is not released.
- `tool/store_assets.py` now only draws the README banner; the store-sized
  assets went with the rest.

### Changed
- The documentation describes what the app does. Gone:
  the claim that Linux desktop and web are targets, the history of the .NET
  MAUI prototype, and the release-by-release narrative in `architecture.md`
  and `testing.md`. The rationale that would let somebody undo a deliberate
  decision stays; the anecdotes moved out, and the release history is in this
  file anyway.

## [0.5.0] - 2026-09-04

Comfort inside a conversation, and a phone that answers scans again. Reported
after using 0.4.0 on both platforms; the Android fix came out of verifying the
rest of it on a device.

### Added
- **A name of your own for a peer.** A device announces its own name, so a PC
  arrives as something like `DESKTOP-8F2A1C`. The security panel now has a
  rename button; the name stays on this device, is never sent anywhere, and the
  announced one keeps showing under it, so the other side quietly renaming
  itself is still visible. An empty field brings the announced name back
  (schema v9, `peers.alias`).
- **Accepting files without asking**, per peer, off by default (schema v9,
  `peers.autoAccept`). It can only be turned on with a confirmed identity, and
  removing the confirmation turns it off. The database enforces both, because
  this is the boundary of the user's consent: the flag alone,
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
  inside that menu.
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
  example, the test connected to **that** Chatt, every assertion passed, and
  the phone was never touched. The tunnel is now
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
- `docs/guide.pl.md`, the user guide in Polish. It is the one document written
  for an end user, so it is worth having in both languages.
  It carries three screenshots the English guide does not, because those exist
  only with a Polish interface.

### Changed
- The documentation is English, in one version, with two exceptions:
  `README.pl.md` and the user guide, both written for end users.
  `docs/instrukcja.md`, `architektura.md`, `budowanie.md` and
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
  `tool/store_assets.py` now fits the font to the available width.

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
  require the account to be maintained over time, which for a showcase app is
  a cost with no return. A release gives three files again: the
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
- **A device's identity is its key.** The identifier is now
  derived from the public key (`sha256(key)`, the first 16 bytes, formatted
  like a UUID), so nobody can claim another device's identifier without its
  private key. The cost, accepted deliberately: every device gets a new
  identifier, so the migration to schema v6 clears the device list and the
  history, because the old entries would match nothing on the network.
  Conversations and pairings have to be set up again.
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
  fingerprints of both keys, openable at any time.
- **An encrypted database on disk** (SQLite3MultipleCiphers). The 32 byte key
  sits in `chatt.key` wrapped by the system keystore: AES-GCM under Android
  Keystore, DPAPI on Windows. A plaintext database from an older version is
  rewritten on the first start with its history intact.
- **Clear history** and automatic deletion of messages older than 7, 30, 90 or
  365 days, off by default (schema v7).
- **Windows: a tray icon, starting minimised and autostart.** The X hides the
  window and listening continues; quitting is in the icon menu.
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
  to a live session gets a 409.
- The sender's guid left the clear part of the envelope. Only the session
  number remains, changed at every handshake, so an eavesdropper cannot even
  see who is talking to whom.
- The file key is derived from the session key, and its tag travels in the
  announcement and is stored next to the partial transfer. A mismatch starts
  the transfer from zero.

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

[0.12.0]: https://github.com/Mysttic/Chatt/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/Mysttic/Chatt/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/Mysttic/Chatt/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/Mysttic/Chatt/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/Mysttic/Chatt/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/Mysttic/Chatt/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/Mysttic/Chatt/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/Mysttic/Chatt/compare/v0.6.2...v0.7.0
[0.6.0]: https://github.com/Mysttic/Chatt/compare/v0.5.4...v0.6.0
[0.5.4]: https://github.com/Mysttic/Chatt/compare/v0.5.3...v0.5.4
[0.5.3]: https://github.com/Mysttic/Chatt/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/Mysttic/Chatt/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/Mysttic/Chatt/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/Mysttic/Chatt/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Mysttic/Chatt/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/Mysttic/Chatt/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/Mysttic/Chatt/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Mysttic/Chatt/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Mysttic/Chatt/releases/tag/v0.1.0
