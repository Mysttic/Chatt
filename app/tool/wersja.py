# -*- coding: utf-8 -*-
"""Podnosi numer wersji w VERSION.md, app/pubspec.yaml i lib/core/version.dart.

Numer wydania stoi w VERSION.md (to on decyduje, czy powstanie nowe wydanie),
Android bierze versionName i versionCode z pubspec.yaml, a aplikacja pokazuje
stałą z version.dart. Wszystkie trzy pliki muszą mówić to samo: workflow
wydania i test/version_test.dart sprawdzają to i przerywają przy rozjeździe,
więc łatwiej podnieść je jednym poleceniem.

Uruchomienie (z katalogu app/):
    python tool/wersja.py 0.2.0
    python tool/wersja.py            # pokazuje, co jest teraz
"""

import io
import os
import re
import sys

KATALOG_APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KORZEN = os.path.dirname(KATALOG_APP)
VERSION_MD = os.path.join(KORZEN, "VERSION.md")
PUBSPEC = os.path.join(KATALOG_APP, "pubspec.yaml")
DART = os.path.join(KATALOG_APP, "lib", "core", "version.dart")

WERSJA = re.compile(r"^\d+\.\d+\.\d+$")
STALA_DART = re.compile(r"^const String appVersion = '\d+\.\d+\.\d+';$", re.M)


def z_version_md():
    """Pierwsza linia będąca samym numerem wersji."""
    for linia in io.open(VERSION_MD, encoding="utf-8"):
        kandydat = linia.strip()
        if WERSJA.match(kandydat):
            return kandydat
    raise SystemExit("VERSION.md nie zawiera numeru wersji")


def z_pubspec():
    """(wersja, numer builda) z linii `version:`."""
    tresc = io.open(PUBSPEC, encoding="utf-8").read()
    dopasowanie = re.search(r"^version:[ \t]*(\d+\.\d+\.\d+)\+(\d+)[ \t]*$", tresc, re.M)
    if not dopasowanie:
        raise SystemExit("pubspec.yaml nie ma linii `version: x.y.z+n`")
    return dopasowanie.group(1), int(dopasowanie.group(2))


def z_dart():
    """Numer ze stałej `appVersion` w lib/core/version.dart."""
    tresc = io.open(DART, encoding="utf-8").read()
    dopasowanie = STALA_DART.search(tresc)
    if not dopasowanie:
        raise SystemExit("version.dart nie ma linii `const String appVersion = 'x.y.z';`")
    return dopasowanie.group(0).split("'")[1]


def zapisz(nowa):
    stara_md = z_version_md()
    stara_pubspec, build = z_pubspec()
    stara_dart = z_dart()

    tresc = io.open(VERSION_MD, encoding="utf-8").read()
    io.open(VERSION_MD, "w", encoding="utf-8").write(
        tresc.replace(stara_md, nowa, 1)
    )

    tresc = io.open(PUBSPEC, encoding="utf-8").read()
    io.open(PUBSPEC, "w", encoding="utf-8").write(
        re.sub(
            # `[ \t]` zamiast `\s`: `\s*$` w trybie MULTILINE zjadał pustą
            # linię pod numerem wersji i sklejał go z następną sekcją.
            r"^version:[ \t]*\d+\.\d+\.\d+\+\d+[ \t]*$",
            "version: {0}+{1}".format(nowa, build + 1),
            tresc,
            count=1,
            flags=re.M,
        )
    )
    tresc = io.open(DART, encoding="utf-8").read()
    io.open(DART, "w", encoding="utf-8").write(
        STALA_DART.sub(
            "const String appVersion = '{0}';".format(nowa), tresc, count=1
        )
    )

    print("VERSION.md   {0} -> {1}".format(stara_md, nowa))
    print("pubspec.yaml {0}+{1} -> {2}+{3}".format(stara_pubspec, build, nowa, build + 1))
    print("version.dart {0} -> {1}".format(stara_dart, nowa))


def main():
    if len(sys.argv) == 1:
        wersja_md = z_version_md()
        wersja_pubspec, build = z_pubspec()
        wersja_dart = z_dart()
        print("VERSION.md  ", wersja_md)
        print("pubspec.yaml", "{0}+{1}".format(wersja_pubspec, build))
        print("version.dart", wersja_dart)
        if len({wersja_md, wersja_pubspec, wersja_dart}) != 1:
            raise SystemExit("ROZJAZD: wszystkie trzy pliki muszą mówić to samo")
        return

    nowa = sys.argv[1].lstrip("v")
    if not WERSJA.match(nowa):
        raise SystemExit("numer ma wyglądać jak 1.2.3, dostałem: " + sys.argv[1])
    if nowa == z_version_md():
        raise SystemExit("to jest bieżąca wersja, nie ma czego podnosić")
    zapisz(nowa)


if __name__ == "__main__":
    main()
