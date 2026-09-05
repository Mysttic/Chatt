# Third-party notices

Chatt is licensed under the Apache License 2.0 (see [LICENSE](../LICENSE)).
Parts of the source tree and of the published release packages come from other
projects and stay under their own licenses. This file lists them.

## Dart and Flutter packages linked into the app

| Component | License | Copyright |
|---|---|---|
| [Flutter SDK](https://github.com/flutter/flutter) and the Dart runtime | BSD-3-Clause | Copyright 2014 The Flutter Authors |
| [cryptography](https://pub.dev/packages/cryptography) | Apache-2.0 | Copyright Gohilla Ltd and contributors |
| [desktop_drop](https://pub.dev/packages/desktop_drop) | Apache-2.0 | Copyright 2021 The desktop_drop authors |
| [shelf_router](https://pub.dev/packages/shelf_router) | Apache-2.0 | Copyright 2019 the Dart project authors |
| [drift](https://pub.dev/packages/drift), [drift_flutter](https://pub.dev/packages/drift_flutter) | MIT | Copyright (c) 2019 Simon Binder |
| [sqlite3](https://pub.dev/packages/sqlite3) | MIT | Copyright (c) 2020 Simon Binder |
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) | MIT | Copyright (c) 2020 Remi Rousselet |
| [tray_manager](https://pub.dev/packages/tray_manager), [window_manager](https://pub.dev/packages/window_manager) | MIT | Copyright (c) 2022 LiJianying |
| [uuid](https://pub.dev/packages/uuid) | MIT | Copyright (c) 2021 Yulian Kuncheff |
| [crypto](https://pub.dev/packages/crypto), [http](https://pub.dev/packages/http), [path](https://pub.dev/packages/path), [shelf](https://pub.dev/packages/shelf) | BSD-3-Clause | Copyright the Dart project authors |
| [file_selector](https://pub.dev/packages/file_selector), [path_provider](https://pub.dev/packages/path_provider) | BSD-3-Clause | Copyright 2013 The Flutter Authors |
| [mobile_scanner](https://pub.dev/packages/mobile_scanner) | BSD-3-Clause | Copyright (c) 2021 Julian Steenbakker |
| [qr_flutter](https://pub.dev/packages/qr_flutter) | BSD-3-Clause | Copyright (c) 2016 Luke Freeman |

Their transitive dependencies carry the same three licenses; `flutter pub deps`
lists the full tree.

## Native components

| Component | Where | License | Copyright |
|---|---|---|---|
| [SQLite](https://sqlite.org/) | inside the SQLite3MultipleCiphers build | public domain | dedicated to the public domain by the authors |
| [SQLite3MultipleCiphers](https://github.com/utelle/SQLite3MultipleCiphers) | pulled in by `package:sqlite3` through build hooks (`hooks.user_defines.sqlite3.source: sqlite3mc` in `app/pubspec.yaml`) | MIT | Copyright (c) 2019-2024 Ulrich Telle |
| [Google ML Kit barcode scanning](https://developers.google.com/ml-kit) | Android only, pulled in by `mobile_scanner` for QR scanning | [Google APIs Terms of Service](https://developers.google.com/terms), proprietary | Copyright Google LLC |

ML Kit runs **on the device**; the camera image is not sent anywhere. It is
listed here because it is proprietary and ships inside the Android APK.

## Fonts bundled in the app

Both are in `app/fonts/` and are declared in `app/pubspec.yaml`.

| Component | License | Copyright |
|---|---|---|
| [Roboto](https://fonts.google.com/specimen/Roboto) (Regular, Medium, Bold) | Apache-2.0 | Copyright Google LLC |
| Material Icons | Apache-2.0 | Copyright Google LLC |

## Build-time only

[Inno Setup](https://jrsoftware.org/isinfo.php) (its own license, builds the
Windows installer), [build_runner](https://pub.dev/packages/build_runner) and
[drift_dev](https://pub.dev/packages/drift_dev) (BSD-3-Clause and MIT, generate
the database code), [flutter_lints](https://pub.dev/packages/flutter_lints)
(BSD-3-Clause), [Pillow](https://python-pillow.org/) (MIT-CMU, draws the icons
and the README banner).

## License texts

### MIT License

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### BSD 3-Clause License

```
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### Apache License 2.0

The full text is in [LICENSE](../LICENSE), the same license Chatt itself uses.
