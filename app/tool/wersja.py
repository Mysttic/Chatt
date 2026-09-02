# -*- coding: utf-8 -*-
"""Podnosi numer wersji w VERSION.md i w app/pubspec.yaml naraz.

Numer wydania stoi w VERSION.md (to on decyduje, czy powstanie nowe wydanie),
ale Android bierze versionName i versionCode z pubspec.yaml — te dwa pliki
muszą mówić to samo. Workflow wydania sprawdza to i przerywa przy rozjeździe,
więc łatwiej podnieść oba jednym poleceniem.

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

WERSJA = re.compile(r"^\d+\.\d+\.\d+$")


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
    dopasowanie = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", tresc, re.M)
    if not dopasowanie:
        raise SystemExit("pubspec.yaml nie ma linii `version: x.y.z+n`")
    return dopasowanie.group(1), int(dopasowanie.group(2))


def zapisz(nowa):
    stara_md = z_version_md()
    stara_pubspec, build = z_pubspec()

    tresc = io.open(VERSION_MD, encoding="utf-8").read()
    io.open(VERSION_MD, "w", encoding="utf-8").write(
        tresc.replace(stara_md, nowa, 1)
    )

    tresc = io.open(PUBSPEC, encoding="utf-8").read()
    io.open(PUBSPEC, "w", encoding="utf-8").write(
        re.sub(
            r"^version:\s*\d+\.\d+\.\d+\+\d+\s*$",
            "version: {0}+{1}".format(nowa, build + 1),
            tresc,
            count=1,
            flags=re.M,
        )
    )
    print("VERSION.md   {0} -> {1}".format(stara_md, nowa))
    print("pubspec.yaml {0}+{1} -> {2}+{3}".format(stara_pubspec, build, nowa, build + 1))


def main():
    if len(sys.argv) == 1:
        wersja_md = z_version_md()
        wersja_pubspec, build = z_pubspec()
        print("VERSION.md  ", wersja_md)
        print("pubspec.yaml", "{0}+{1}".format(wersja_pubspec, build))
        if wersja_md != wersja_pubspec:
            raise SystemExit("ROZJAZD: oba pliki muszą mówić to samo")
        return

    nowa = sys.argv[1].lstrip("v")
    if not WERSJA.match(nowa):
        raise SystemExit("numer ma wyglądać jak 1.2.3, dostałem: " + sys.argv[1])
    if nowa == z_version_md():
        raise SystemExit("to jest bieżąca wersja, nie ma czego podnosić")
    zapisz(nowa)


if __name__ == "__main__":
    main()
