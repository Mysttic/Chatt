# -*- coding: utf-8 -*-
"""Nagłówek do README: ikona aplikacji i hasło w stylu Cisza.

Generuje docs/promo.png (1024x500), jedyną grafikę projektu, która
powstaje z kodu i leży w repozytorium.

Uruchomienie (z katalogu app/, wymaga Pillow):
    python tool/store_assets.py
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

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


def czcionka(rozmiar, waga="Bold"):
    """Figtree, font stylu Cisza, w podanej grubości (font zmienny)."""
    font = ImageFont.truetype(os.path.join(KATALOG_APP, "fonts", "Figtree-VariableFont.ttf"), rozmiar)
    font.set_variation_by_name(waga)
    return font


def dopasuj(tekst, rozmiar, maks_szer, waga="Bold"):
    """Największa czcionka do `rozmiar`, przy której tekst mieści się
    w `maks_szer`. Hasło ma inną długość w każdym języku, a wpisany na sztywno
    rozmiar wychodził w angielskim poza prawą krawędź grafiki."""
    while rozmiar > 12:
        font = czcionka(rozmiar, waga)
        if font.getlength(tekst) <= maks_szer:
            return font
        rozmiar -= 1
    return czcionka(12, waga)


def zapisz(obraz, sciezka):
    os.makedirs(os.path.dirname(sciezka), exist_ok=True)
    obraz.save(sciezka, "PNG")
    print("zapisano", os.path.relpath(sciezka, KORZEN), obraz.size)


# Cisza, motyw jasny (app/lib/ui/styles.dart): tło „Ocean”, tekst, tekst
# drugorzędny i akcent.
TLO = ((0xD9, 0xEC, 0xF0), (0xE8, 0xEF, 0xF7))
TEKST = (0x16, 0x21, 0x20)
AKCENT = (0x0F, 0x6A, 0x73)
CIEN = (0x16, 0x28, 0x26)


def tlo_165(szer, wys):
    """Gradient pod kątem 165°, jak `wallDecoration` w aplikacji."""
    kierunek = (0.26, 0.97)
    rzut = [abs(kierunek[0]) * szer, abs(kierunek[1]) * wys]
    dlugosc = rzut[0] + rzut[1]
    obraz = Image.new("RGB", (szer, wys))
    piksele = obraz.load()
    for y in range(wys):
        for x in range(szer):
            t = (x * kierunek[0] + y * kierunek[1]) / dlugosc
            piksele[x, y] = tuple(round(TLO[0][i] + (TLO[1][i] - TLO[0][i]) * t) for i in range(3))
    return obraz.convert("RGBA")


def promo(jezyk):
    """Grafika promocyjna 1024×500 w stylu Cisza: ikona po lewej, hasło po
    prawej. Ikona jest ta sama co w systemie, jedna dla wszystkich stylów."""
    szer, wys = 1024, 500
    obraz = tlo_165(szer, wys)

    rozmiar_ikony = 300
    x_ikony, y_ikony = 90, (wys - rozmiar_ikony) // 2
    ikonka = make_icons.ikona_launchera(rozmiar_ikony)
    # Miękki cień jak `shadow2` Ciszy, w skali ikony.
    cien = Image.new("RGBA", obraz.size, (0, 0, 0, 0))
    maska = ikonka.getchannel("A").point(lambda a: a * 0.16)
    cien.paste(CIEN + (255,), (x_ikony, y_ikony + 14), maska)
    cien = cien.filter(ImageFilter.GaussianBlur(22))
    obraz.alpha_composite(cien)
    obraz.alpha_composite(ikonka, (x_ikony, y_ikony))

    naglowek, podpis = HASLO[jezyk]
    lewa, maks = 442, szer - 442 - 48
    czcionka_naglowka = dopasuj(naglowek, 34, maks, "SemiBold")
    rysuj = ImageDraw.Draw(obraz)
    rysuj.text((436, 140), "Chatt", font=czcionka(100, "Bold"), fill=TEKST + (255,))
    rysuj.text((lewa, 270), naglowek, font=czcionka_naglowka, fill=TEKST + (255,))
    # Podpis nie może urosnąć ponad nagłówek, nawet gdy jest od niego krótszy.
    rysuj.text((lewa, 320), podpis,
               font=dopasuj(podpis, czcionka_naglowka.size - 5, maks, "Medium"),
               fill=AKCENT + (255,))
    return obraz.convert("RGB")


def main():
    zapisz(promo("en"), os.path.join(DOCS, "promo.png"))


if __name__ == "__main__":
    main()
