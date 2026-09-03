# -*- coding: utf-8 -*-
"""Grafiki: nagłówek do README i materiały w wymiarach sklepów.

Sklepy są **odłożone** (patrz docs/publikacja/README.md) — projekt wydaje się
przez GitHub Releases. Skrypt zostaje, bo nagłówek do README powstaje tym
samym kodem co ikona aplikacji, a materiały sklepowe przydadzą się, gdyby
decyzja kiedyś się zmieniła.

Generuje do docs/:
  promo.png                           nagłówek README 1024×500 (w repozytorium)

oraz do docs/publikacja/materialy/ (poza repozytorium, na żądanie):
  google-play/ikona-512.png           ikona 512×512 (Play)
  google-play/promo-1024x500.png      grafika promocyjna 1024×500 (Play)
  google-play/zrzuty/{pl,en}/*.png    zrzuty telefonu 1080×1920 (Play)
  microsoft-store/logo-1080.png       logo 1:1 do wpisu w Store
  microsoft-store/zrzuty/{pl,en}/*.png  zrzuty pulpitu (min. 1366×768)

Zrzuty z emulatora mają 1280×2856, czyli proporcję 2,23 — Play przyjmuje
najwyżej 2:1. Skalujemy je do wysokości 1920 i dokładamy po bokach tło do
1080×1920 (9:16). Zrzuty pulpitu przepuszczamy bez zmian, tylko sprawdzając
minimalny wymiar.

Źródła zrzutów:
  docs/screenshots/produkt/            (pl)   z tool/product_shots.dart
  docs/screenshots/produkt/en/         (en)   CHATT_SHOTS_LANG=en
  docs/screenshots/windows/{pl,en}/          z tool/windows_shots.dart

Uruchomienie (z katalogu app/, wymaga Pillow):
    python tool/store_assets.py
"""

import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFont

KATALOG_TOOL = os.path.dirname(os.path.abspath(__file__))
KATALOG_APP = os.path.dirname(KATALOG_TOOL)
KORZEN = os.path.dirname(KATALOG_APP)
DOCS = os.path.join(KORZEN, "docs")
WYJSCIE = os.path.join(DOCS, "publikacja", "materialy")

sys.path.insert(0, KATALOG_TOOL)
import make_icons  # noqa: E402  (ikona rysowana tym samym kodem co w aplikacji)

# Tło pod zrzuty telefonu: kolor powierzchni z jasnego motywu aplikacji,
# żeby paski po bokach wyglądały jak ciąg dalszy ekranu, a nie jak ramka.
TLO_ZRZUTU = (253, 247, 255)

# Zrzuty, które mają sens w sklepie, w kolejności pokazywania. Nazwy pod
# emulator (product_shots.dart); reszta zrzutów zostaje do dokumentacji.
ZRZUTY_TELEFONU = [
    "android_rozmowa_z_plikiem",
    "android_miniatura_obrazka",
    "android_prosba_o_plik",
    "android_lista_rozmow",
    "android_urzadzenia_w_poblizu",
    "android_szukanie_w_rozmowie",
    "android_lista_rozmow_ciemny",
]

# Tekst na grafice promocyjnej. Play pokazuje ją w języku wpisu, a wpis jest
# dwujęzyczny — dlatego po jednej wersji na język.
HASLO = {
    "pl": ("Komputer i telefon w jednej rozmowie", "bez serwera, zawsze zaszyfrowane"),
    "en": ("Your PC and phone in one conversation", "no server, always encrypted"),
}


def czcionka(rozmiar, gruba=True):
    plik = "Roboto-Bold.ttf" if gruba else "Roboto-Regular.ttf"
    return ImageFont.truetype(os.path.join(KATALOG_APP, "fonts", plik), rozmiar)


def zapisz(obraz, sciezka):
    os.makedirs(os.path.dirname(sciezka), exist_ok=True)
    obraz.save(sciezka, "PNG")
    print("zapisano", os.path.relpath(sciezka, KORZEN), obraz.size)


def ikona(rozmiar):
    """Ikona bez przezroczystości: Play chce PNG 32-bit, ale narożniki
    z alfą wyglądają w sklepie jak dziury, więc kładziemy ją na tle."""
    tlo = Image.new("RGBA", (rozmiar, rozmiar), make_icons.TLO_DOL + (255,))
    tlo.alpha_composite(make_icons.ikona_launchera(rozmiar))
    return tlo.convert("RGB")


def promo(jezyk):
    """Grafika promocyjna 1024×500: ikona po lewej, hasło po prawej."""
    szer, wys = 1024, 500
    obraz = make_icons.gradient(szer).crop((0, 0, szer, wys)).convert("RGBA")
    # Gradient jest kwadratowy, więc dla proporcji 2:1 rysujemy poziomy sami.
    rysuj = ImageDraw.Draw(obraz)
    for x in range(szer):
        t = x / (szer - 1)
        kolor = tuple(
            round(make_icons.TLO_GORA[i] + (make_icons.TLO_DOL[i] - make_icons.TLO_GORA[i]) * t)
            for i in range(3)
        )
        rysuj.line([(x, 0), (x, wys)], fill=kolor + (255,))

    ikonka = make_icons.ikona_launchera(300)
    obraz.alpha_composite(ikonka, (90, (wys - 300) // 2))

    naglowek, podpis = HASLO[jezyk]
    rysuj = ImageDraw.Draw(obraz)
    rysuj.text((440, 150), "Chatt", font=czcionka(96), fill=(255, 255, 255, 255))
    rysuj.text((442, 268), naglowek, font=czcionka(34), fill=(255, 255, 255, 255))
    rysuj.text((442, 318), podpis, font=czcionka(28, gruba=False),
               fill=(255, 255, 255, 215))
    return obraz.convert("RGB")


def zrzut_telefonu(sciezka):
    """Zrzut z emulatora wpasowany w 1080×1920 z tłem po bokach."""
    zrodlo = Image.open(sciezka).convert("RGB")
    docelowa_wys = 1920
    skala = docelowa_wys / zrodlo.height
    przeskalowany = zrodlo.resize(
        (round(zrodlo.width * skala), docelowa_wys), Image.LANCZOS)
    plotno = Image.new("RGB", (1080, docelowa_wys), TLO_ZRZUTU)
    plotno.paste(przeskalowany, ((1080 - przeskalowany.width) // 2, 0))
    return plotno


def zrzuty_telefonu():
    for jezyk in ("pl", "en"):
        zrodlo = os.path.join(DOCS, "screenshots", "produkt")
        if jezyk == "en":
            zrodlo = os.path.join(zrodlo, "en")
        if not os.path.isdir(zrodlo):
            print("pomijam zrzuty telefonu", jezyk, "- brak", zrodlo)
            continue
        for numer, nazwa in enumerate(ZRZUTY_TELEFONU, start=1):
            plik = os.path.join(zrodlo, nazwa + ".png")
            if not os.path.exists(plik):
                print("brak", plik)
                continue
            zapisz(
                zrzut_telefonu(plik),
                os.path.join(WYJSCIE, "google-play", "zrzuty", jezyk,
                             "%02d_%s.png" % (numer, nazwa.replace("android_", ""))),
            )


def zrzuty_pulpitu():
    for jezyk in ("pl", "en"):
        zrodlo = os.path.join(DOCS, "screenshots", "windows", jezyk)
        if not os.path.isdir(zrodlo):
            print("pomijam zrzuty pulpitu", jezyk, "- brak", zrodlo)
            continue
        for plik in sorted(glob.glob(os.path.join(zrodlo, "*.png"))):
            obraz = Image.open(plik).convert("RGB")
            if obraz.width < 1366 or obraz.height < 768:
                raise SystemExit("%s ma %dx%d, Store wymaga co najmniej 1366x768"
                                 % (plik, obraz.width, obraz.height))
            # Nazwa źródłowa ma już numer, więc nie doklejamy drugiego.
            zapisz(obraz, os.path.join(WYJSCIE, "microsoft-store", "zrzuty",
                                       jezyk, os.path.basename(plik)))


def main():
    # Nagłówek README trzymamy w repozytorium: to jedyna z tych grafik, którą
    # widać bez uruchamiania czegokolwiek.
    zapisz(promo("en"), os.path.join(DOCS, "promo.png"))

    zapisz(ikona(512), os.path.join(WYJSCIE, "google-play", "ikona-512.png"))
    for jezyk in ("pl", "en"):
        zapisz(promo(jezyk), os.path.join(WYJSCIE, "google-play", "promo-1024x500-%s.png" % jezyk))
    zapisz(ikona(1080), os.path.join(WYJSCIE, "microsoft-store", "logo-1080.png"))
    zrzuty_telefonu()
    zrzuty_pulpitu()


if __name__ == "__main__":
    main()
