import 'dart:io';

import 'package:chatt/core/version.dart';
import 'package:flutter_test/flutter_test.dart';

/// Numer wersji stoi w trzech miejscach: VERSION.md decyduje o wydaniu,
/// pubspec.yaml daje Androidowi versionName, a stała z version.dart trafia
/// na ekran. Podnosi je razem `tool/wersja.py`; ten test wyłapuje moment,
/// w którym ktoś ruszył jedno miejsce z ręki.
void main() {
  test('appVersion zgadza się z pubspec.yaml i VERSION.md', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final zPubspeca = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$',
            multiLine: true)
        .firstMatch(pubspec)
        ?.group(1);
    expect(zPubspeca, isNotNull, reason: 'pubspec.yaml bez linii `version:`');

    final versionMd = File('../VERSION.md').readAsStringSync();
    final zVersionMd = RegExp(r'^\d+\.\d+\.\d+$', multiLine: true)
        .firstMatch(versionMd)
        ?.group(0);
    expect(zVersionMd, isNotNull, reason: 'VERSION.md bez numeru wersji');

    expect(appVersion, zPubspeca);
    expect(appVersion, zVersionMd);
  });
}
