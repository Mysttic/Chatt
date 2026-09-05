# Contributing

Bug reports, notes from real networks and pull requests are all welcome.

- [A note on language](#a-note-on-language)
- [Repository layout](#repository-layout)
- [Building from source](#building-from-source)
- [Running the tests](#running-the-tests)
- [Documentation images](#documentation-images)
- [Pull requests and releases](#pull-requests-and-releases)

## A note on language

The documentation is in English, with two exceptions that face readers rather
than developers: `README.pl.md` and the user guide, which exist in Polish as
well. The code comments are in Polish. The app itself speaks English and
Polish, with English as the default; strings live in `app/lib/l10n/*.arb`.

## Repository layout

```
app/            the Flutter application, all of the code
  lib/          identity and crypto, database, protocol, services, screens
  test/         everything that runs without hardware
  tool/         scenarios and scripts that need a device or a desktop
  windows/      the runner and its platform channels (DPAPI, autostart, clipboard)
  android/      the foreground service, FileProvider and Keystore channel
docs/           documentation and screenshots
brand/          the app icon as SVG
```

## Building from source

The full commands, the environment and the signing setup are in
[building.md](building.md). The short version:

```
cd app
flutter pub get
flutter run -d windows        # or: flutter run -d <android device>
```

After a change to the database schema (`lib/data/db.dart`):

```
flutter pub run build_runner build
```

After a change to the strings in `lib/l10n/*.arb`:

```
flutter gen-l10n
```

## Running the tests

```
cd app
flutter analyze
flutter test
```

Both have to be clean before a pull request. What each test covers, and the
scenarios that need a real device, are described in [testing.md](testing.md).

## Documentation images

The screenshots in `docs/screenshots/` are generated:

```
cd app
flutter test tool/product_shots.dart      # Android, needs a running emulator
flutter test tool/windows_shots.dart      # Windows, renders in the test harness
python tool/store_assets.py               # the README banner
```

`CHATT_SHOTS_LANG=en` switches the app language for the screenshots. Refresh
them when the UI changes; a pull request that changes what a screen looks like
should carry the new images.

## Pull requests and releases

Work goes into `develop`. Pushing there starts nothing, so the runners are not
burned on every commit.

A pull request **into `master`** runs `flutter analyze` and the whole test
suite. Please describe what changes and how it was verified; the template asks
for both.

A release is a separate pull request. It raises the number in `VERSION.md`,
`app/pubspec.yaml` and `app/lib/core/version.dart` with one command:

```
cd app
python tool/wersja.py 0.6.0
```

Merging that into `master` builds the signed APK, the Windows installer and the
portable zip, creates the `v<version>` tag and publishes a Release. An ordinary
pull request should leave `VERSION.md` alone.

Every change worth a line goes into [CHANGELOG.md](../CHANGELOG.md), under
`Unreleased`.
