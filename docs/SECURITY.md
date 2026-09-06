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
same Wi-Fi can send it:

- **the protocol and the session handshake** (`app/lib/network/`): envelopes,
  the key agreement, the discovery responder,
- **file reception** (`app/lib/services/app_services.dart` and
  `app/lib/core/received_paths.dart`): a string from the sender becomes a path
  on disk there,
- **the database key** (`app/lib/core/secret_store.dart` and the platform
  channels in `app/android/` and `app/windows/`),
- **the identity confirmation flow**, including the QR code.

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
- **Received files lie on disk unencrypted.** The database wraps conversation
  history; file content stays where the user opens it with other applications.
- **The database key can be read by a process running as the same system
  user.** On Windows DPAPI unwraps it for any such process; on Android the app
  sandbox is what protects it. Protection covers a copied disk or a copied
  file; code already running as you can read the key.
- **Nothing leaves the local network on its own.** There is no server, no
  telemetry and no crash reporting, so there is no reporting channel to abuse
  either. One exception, and it is off by default: with update checks turned
  on, or when the button in Settings is pressed, the app asks
  `api.github.com` about the newest release. GitHub sees what any HTTPS server
  sees, an IP address and the time. Nothing about the conversations goes with
  it.
