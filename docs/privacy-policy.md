# Chatt Privacy Policy

Last updated: 19 October 2026.

## In short

Chatt sends no data to its author or to anyone else. There is no server, no
account, no sign-in, no analytics and no crash reporting. Everything you type
or send goes directly from one device to the other, on your local network or,
with the Bluetooth add-on, over the radio, and stays on those two devices.
What each device keeps (the conversations, a typing history for Keyboard from
a PC, a diagnostic log) lies in its encrypted database and leaves it only when
you take it out yourself: an export, **Share history** for a conversation, or
a copy to the clipboard from its screen.

## What data the app handles and where it lives

| Data | Where it is | Who can see it |
|---|---|---|
| Messages and files you send | on your device and on the recipient's device | only the two of you |
| Device name and welcome message | broadcast on your local network | any device on the same Wi-Fi network |
| Device identity key (public part) | broadcast on your local network | any device on the same network |
| Identity key (private part) | on your device, in an encrypted database; never in an export | only you |
| Conversation history | on your device, in an encrypted database | only you, and anyone who gets an export you made |
| Local network IP address | visible to the devices you talk to | devices on the same network |
| The PC's Bluetooth name and radio address (Bluetooth add-on only) | sent out by the PC's radio while the add-on is on; a phone shows its own for the two minutes after **Show this phone nearby** in Chatt, or when you make it visible in the system's Bluetooth settings | anyone within radio range |
| Text typed with Keyboard from a PC (add-on only) | travels encrypted to the device being typed on and lands in the field you chose there. With **Save typing history** on (the default), both devices keep it in their typing history, in the encrypted database: what was typed, into which app, when, and whether it landed. Text typed into a password field or a field of unknown kind is kept as a number of characters | the two devices, and anyone who gets an export made on either of them |
| The name of the app with the focused field and the kind of that field (ordinary or password) on the device being typed on (Keyboard from a PC only) | sent encrypted to the device that types, during a session, for its "Typing into" line; with the typing history on, both devices keep them next to what was typed | the two devices |
| App log: what the app did and what went wrong (connections, pairing, file transfers, Bluetooth, typing sessions without their text, errors), with device names, addresses and file sizes | on your device, in the encrypted database, for 30 days at most | only you, and anyone who gets an export you made |
| An export made with **Export data** | one ZIP file, not encrypted, where you saved it or whichever app you handed it to. On Android, after the share sheet, a copy waits in the app's private cache until the next export, **Clear history**, **Clear typing history**, or the next start once it is an hour old | anyone who can open that file |

None of the above is sent to the app's author or to anyone outside your local
network. An export goes only where you take it. See "Connections outside your
network" below for the two things the app can reach outside, both of which are
off until you turn them on.

## Encryption

- Traffic between devices is always encrypted, from the very first message,
  with a key negotiated separately for every connection (X25519, AES-GCM,
  AES-CTR for file streams).
- Conversation history, the typing history and the app log are stored in an
  encrypted database on disk. The key is held by the operating system:
  Android Keystore on the phone, DPAPI on Windows.
- Received files are saved without additional encryption in the app's folder
  and, only when you ask, copied to Pictures or Downloads.
- An export is a ZIP file with no encryption. It never holds the identity
  key, a session key or the database key, and the `README.txt` inside says
  that the file is not encrypted. Anyone who gets the file can read what you
  put in it.

## Typing history, app log and export

All three are in Settings, in the **Data and diagnostics** section; Typing
history shows there once at least one session is saved, and the keyboard
add-on's card opens it too while the add-on is on.

**Typing history.** With the Keyboard from a PC add-on on, both devices keep a
record of every typing session: which device typed on which, when the session
started and ended, how the request was answered, and what was typed, into
which app and whether it landed. The app is named by its name and its package
or program file; a window title is never sent or kept. Text typed into a
password field, or into a field whose kind Chatt cannot tell, is kept as a
number of characters and shown as dots. A password field that its app does
not mark as one looks like an ordinary field to Chatt, and what is typed into
it is kept as text. The **Save typing history** switch on the add-on's card
turns the record off on that device; it starts on, and each device keeps its
own history under its own switch. With the add-on off nothing is recorded,
and turning the switch off keeps what is already saved.

**App log.** Each device keeps a log of what the app did, so that a problem
can be traced: connections and the road they took, pairing, file transfers,
Bluetooth, typing sessions and errors. It holds device names, network and
radio addresses and file sizes. It never holds message text, typed text,
pairing codes, keys or window titles. Entries older than 30 days are deleted,
and the log keeps 20,000 entries at most. **Clear the log** on its screen
deletes all of it.

**Export.** **Export data** writes one ZIP file with the parts you pick:
conversations with devices and settings, the typing history, the app log, and
received files (the dialog shows their size). On Android 10 and newer the file
goes to Downloads; on older Android, or when saving to Downloads fails, the
system's share sheet lets you pick where it goes, and Chatt keeps a copy in
its private cache until the next export, **Clear history**, **Clear typing
history**, or the next start once it is an hour old. On Windows you pick the
place in the system's save dialog. The export itself sends nothing anywhere.

## Permissions

| Permission (Android) | Purpose |
|---|---|
| Internet, network state, Wi-Fi state, multicast | talking to and discovering devices on the local network, and the two optional calls described below |
| Camera | scanning a QR code shown by the other device, only when you ask; the image never leaves the device |
| Notifications | new message alerts and the persistent "listening" notice; with the Keyboard from a PC add-on also a request to type, the "Switch the keyboard to Chatt" prompt, and who is typing, shown in the persistent notice |
| Foreground service | receiving messages while the window is closed |
| Battery optimisation exemption | optional, so the system does not cut the network with the screen off |
| Nearby devices (Bluetooth) | the Bluetooth add-on only, asked when you turn it on (Android 12 and newer). **Show this phone nearby** uses it to make the phone visible to devices around for two minutes, after the system's own prompt. Older Android grants Bluetooth at install and would want location for a radio search; Chatt does not ask for location, and there the other device is added by its radio address |
| Install packages | installing an update fetched with **Download and install**, after the system's own confirmation |

**Keyboard (input method).** With the Keyboard from a PC add-on, Chatt brings
its own keyboard, the Chatt keyboard. It is on the system's list of keyboards
only while the add-on is on, and it works only after you turn it on in the
system's settings and pick it. Android warns that a keyboard can collect what
is typed with it. The Chatt keyboard has no keys and sends no text from any
field. It looks at the kind of the field (password or not), its Enter action,
the app it belongs to and whether something is selected, and types into the
field you chose what comes from a device you allowed, during a session you
accepted. The app's name and the kind of field go to the device that types,
encrypted, so it can show where the typing goes. With **Save typing history**
on, Chatt keeps what it typed in its typing history (see above). When the
session ends, the keyboard switches back to your previous one.

On Windows the app asks the system firewall to allow incoming connections on
private networks. Typing with the Keyboard from a PC add-on uses the ordinary
Windows input functions and needs no permission; windows running as
administrator are out of its reach. With the Bluetooth add-on on, the PC is
visible to Bluetooth devices nearby, and turning the add-on off ends that.

## Connections outside your network

Two features, both **off until you turn them on** in Settings, make the app
connect to a server outside your local network. Neither carries an account, a
token or an identifier: the other side sees an IP address and a timestamp, the
same as any HTTPS server does.

| Feature | What it contacts | What the other side learns |
|---|---|---|
| Update check | `api.github.com`, once a day; and, when you press **Download and install**, GitHub's download server for the release file | your IP address and the time of the question; for a download also which release file |
| Link previews | the page behind a link in a message | your IP address, the time, and which link it was |

Link previews are worth spelling out, because the address is chosen by
**whoever sent you the message**, not by you. With them on, receiving a message
with a link makes the app fetch that page's title, description and image so it
can draw a card. That fetch tells the server that someone opened a conversation
containing its address, and when.

Everything the app does with the answer is drawing: it reads a few `<meta>`
tags as text and hands the image bytes to the system image decoder. There is no
browser and no WebView, no script from the page is executed, no cookies are
stored or sent, and previews are never fetched from addresses on your own local
network. Answers are kept in memory only and disappear when the app closes or
when you turn the switch off.

Clicking a link is separate again: it always asks first, and shows which server
the address really leads to before anything opens.

## Third-party services

QR code scanning on Android uses Google ML Kit running **on the device**; the
camera image is not sent anywhere. The app contains no ads, no analytics, no
tracking and no external crash reporting.

## Deleting your data

All data is on your device and under your control:

- "Clear history" in settings deletes every message and conversation, and the
  typing history with them,
- "Clear typing history" deletes the typing history alone,
- both also delete an export still waiting in the app's cache on Android,
- automatic deletion of messages older than a chosen number of days runs on
  its own once you enable it, and takes the typing history of that age along,
- "Clear the log" on the App log screen deletes every log entry at once, and
  the log deletes entries older than 30 days by itself,
- uninstalling the app removes its data (on Windows the database in Documents
  is left for you to delete, because those are your documents),
- an export you saved is a file of yours: Chatt never deletes it, so delete
  it yourself when you no longer need it.

Deleting is local. The person you talk to keeps their own copy of your
conversation, and their own typing history of the sessions between your
devices. With **Share history** they can hand the conversation back to you.
When they offer it, you see a card first and decide whether to take it; when
you ask for it yourself with **Ask for history**, the answer comes in without
a second card, and **Stop** on the progress bar ends it. Nothing comes back on
its own.

There is nothing to delete on the author's side, because the author holds
nothing.

## Children

The app is not directed at children. It sends no data to its author or to
anyone else, so there is nothing to regulate separately.

## Changes

Changes to this policy are published together with a new version of the app,
in the same repository as the code.

## Contact

[contact address to be filled in before publication]
