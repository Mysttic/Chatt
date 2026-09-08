# Chatt Privacy Policy

Last updated: 8 September 2026.

## In short

Chatt collects no data. There is no server, no account, no sign-in, no
analytics and no crash reporting. Everything you type or send goes directly
from one device to the other on your local network and stays on those two
devices.

## What data the app handles and where it lives

| Data | Where it is | Who can see it |
|---|---|---|
| Messages and files you send | on your device and on the recipient's device | only the two of you |
| Device name and welcome message | broadcast on your local network | any device on the same Wi-Fi network |
| Device identity key (public part) | broadcast on your local network | any device on the same network |
| Identity key (private part), conversation history | on your device, in an encrypted database | only you |
| Local network IP address | visible to the devices you talk to | devices on the same network |

None of the above is sent to the app's author or to anyone outside your local
network. See "Connections outside your network" below for the two things the
app can reach outside, both of which are off until you turn them on.

## Encryption

- Traffic between devices is always encrypted, from the very first message,
  with a key negotiated separately for every connection (X25519, AES-GCM,
  AES-CTR for file streams).
- Conversation history is stored in an encrypted database on disk. The key is
  held by the operating system: Android Keystore on the phone, DPAPI on
  Windows.
- Received files are saved without additional encryption in the app's folder
  and, only when you ask, copied to Pictures or Downloads.

## Permissions

| Permission (Android) | Purpose |
|---|---|
| Internet, network state, Wi-Fi state, multicast | talking to and discovering devices on the local network, and the two optional calls described below |
| Camera | scanning a QR code shown by the other device, only when you ask; the image never leaves the device |
| Notifications | new message alerts and the persistent "listening" notice |
| Foreground service | receiving messages while the window is closed |
| Battery optimisation exemption | optional, so the system does not cut the network with the screen off |

On Windows the app asks the system firewall to allow incoming connections on
private networks; it needs no other permissions.

## Connections outside your network

Two features, both **off until you turn them on** in Settings, make the app
connect to a server outside your local network. Neither carries an account, a
token or an identifier: the other side sees an IP address and a timestamp, the
same as any HTTPS server does.

| Feature | What it contacts | What the other side learns |
|---|---|---|
| Update check | `api.github.com`, once a day | your IP address and the time of the question |
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

- "Clear history" in settings deletes every message,
- automatic deletion of messages older than a chosen number of days runs on
  its own once you enable it,
- uninstalling the app removes its data (on Windows the database in Documents
  is left for you to delete, because those are your documents).

There is nothing to delete on the author's side, because the author holds
nothing.

## Children

The app is not directed at children and collects no data, so there is nothing
to regulate separately.

## Changes

Changes to this policy are published together with a new version of the app,
in the same repository as the code.

## Contact

[contact address to be filled in before publication]
