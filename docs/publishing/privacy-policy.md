# Chatt Privacy Policy

Last updated: 4 September 2026.

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
network.

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
| Internet, network state, Wi-Fi state, multicast | talking to and discovering devices on the local network; the app does not connect to the internet |
| Camera | scanning a QR code shown by the other device, only when you ask; the image never leaves the device |
| Notifications | new message alerts and the persistent "listening" notice |
| Foreground service | receiving messages while the window is closed |
| Battery optimisation exemption | optional, so the system does not cut the network with the screen off |

On Windows the app asks the system firewall to allow incoming connections on
private networks; it needs no other permissions.

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
