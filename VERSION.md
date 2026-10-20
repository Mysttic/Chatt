# Version

0.12.0

---

This is where the release number lives. Changing it and merging into `master`
is the only way a new release happens:
[`.github/workflows/wydanie.yml`](.github/workflows/wydanie.yml) starts only
when this file was among the merged changes.

The number follows `major.minor.patch`. The workflow reads the first line that
consists of nothing but such a number, so the rest of the file can be anything.

The number has to agree with `version:` in `app/pubspec.yaml` (which is where
Android's `versionName` and `versionCode` come from) and with `appVersion` in
`app/lib/core/version.dart` (the number the app shows and checks for updates
with). The workflow and the tests guard that, but there is no need to do it by
hand anyway:

```
cd app
python tool/wersja.py 0.4.0
```

The script raises the number in all three files and increments the build
number in `pubspec.yaml`, because Android will not accept an update with a
number lower than or equal to the previous one.
