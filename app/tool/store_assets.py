# -*- coding: utf-8 -*-
"""Nagłówek do README: ikona aplikacji i hasło na gradiencie.

Generuje docs/promo.png (1024x500), jedyną grafikę projektu, która
powstaje z kodu i leży w repozytorium.

Uruchomienie (z katalogu app/, wymaga Pillow):
    python tool/store_assets.py
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

KATALOG_TOOL = os.path.dirname(os.path.abspath(__file__))
KATALOG_APP = os.path.dirname(KATALOG_TOOL)
KORZEN = os.path.dirname(KATALOG_APP)
DOCS = os.path.join(KORZEN, "docs")

sys.path.insert(0, KATALOG_TOOL)
import make_icons  # noqa: E402  (ikona rysowana tym samym kodem co w aplikacji)

# Hasło na banerze, po jednym na język.
HASLO = {
    "pl": ("Komputer i telefon w jednej rozmowie", "bez serwera, zawsze zaszyfrowane"),
    "en": ("Your PC and phone in one conversation", "no server, always encrypted"),
}


def czcionka(rozmiar, gruba=True):
    plik = "Roboto-Bold.ttf" if gruba else "Roboto-Regular.ttf"
    return ImageFont.truetype(os.path.join(KATALOG_APP, "fonts", plik), rozmiar)


def dopasuj(tekst, rozmiar, maks_szer, gruba=True):
    """Największa czcionka do `rozmiar`, przy której tekst mieści się
    w `maks_szer`. Hasło ma inną długość w każdym języku, a wpisany na sztywno
    rozmiar wychodził w angielskim poza prawą krawędź grafiki."""
    while rozmiar > 12:
        font = czcionka(rozmiar, gruba)
        if font.getlength(tekst) <= maks_szer:
            return font
        rozmiar -= 1
    return czcionka(12, gruba)


def zapisz(obraz, sciezka):
    os.makedirs(os.path.dirname(sciezka), exist_ok=True)
    obraz.save(sciezka, "PNG")
    print("zapisano", os.path.relpath(sciezka, KORZEN), obraz.size)



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
    lewa, maks = 442, szer - 442 - 48
    czcionka_naglowka = dopasuj(naglowek, 34, maks)
    rysuj = ImageDraw.Draw(obraz)
    rysuj.text((440, 150), "Chatt", font=czcionka(96), fill=(255, 255, 255, 255))
    rysuj.text((lewa, 268), naglowek, font=czcionka_naglowka,
               fill=(255, 255, 255, 255))
    # Podpis nie może urosnąć ponad nagłówek, nawet gdy jest od niego krótszy.
    rysuj.text((lewa, 318), podpis,
               font=dopasuj(podpis, czcionka_naglowka.size - 5, maks, gruba=False),
               fill=(255, 255, 255, 215))
    return obraz.convert("RGB")





def main():
    zapisz(promo("en"), os.path.join(DOCS, "promo.png"))


if __name__ == "__main__":
    main()
