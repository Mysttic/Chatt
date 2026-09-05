"""Generator ikony aplikacji.

Rysuje dwa dymki rozmowy na fiolecie z motywu (#512BD4) i zapisuje:
  - klasyczne ikony launchera Androida (mipmap-*/ic_launcher.png),
  - warstwę pierwszoplanową ikony adaptacyjnej (ic_launcher_foreground.png),
  - ikonę Windows (windows/runner/resources/app_icon.ico).

Uruchomienie (z katalogu app/):
    python tool/make_icons.py

Rysujemy w czterokrotnym powiększeniu i zmniejszamy filtrem LANCZOS, inaczej
krawędzie dymków byłyby poszarpane.
"""

import os

from PIL import Image, ImageDraw

TLO_GORA = (107, 69, 224)
TLO_DOL = (81, 43, 212)
BIALY = (255, 255, 255, 255)
BIALY_PRZYGASZONY = (255, 255, 255, 140)

SUPERSAMPLING = 4

ANDROID_LAUNCHER = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Ikona adaptacyjna ma płótno 108 dp, z czego widoczne jest środkowe 72 dp.
ANDROID_FOREGROUND = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}

WINDOWS_SIZES = [16, 24, 32, 48, 64, 128, 256]

# Ikona powiadomień: 24 dp, biała sylwetka na przezroczystym tle (system i tak
# maluje ją swoim kolorem, kolory z niej wyrzuca).
ANDROID_NOTIFICATION = {
    "drawable-mdpi": 24,
    "drawable-hdpi": 36,
    "drawable-xhdpi": 48,
    "drawable-xxhdpi": 72,
    "drawable-xxxhdpi": 96,
}


def gradient(size):
    """Pionowy gradient w kolorach motywu."""
    obraz = Image.new("RGBA", (size, size))
    rysuj = ImageDraw.Draw(obraz)
    for y in range(size):
        t = y / max(size - 1, 1)
        kolor = tuple(
            round(TLO_GORA[i] + (TLO_DOL[i] - TLO_GORA[i]) * t) for i in range(3)
        )
        rysuj.line([(0, y), (size, y)], fill=kolor + (255,))
    return obraz


def dymki(size, skala=1.0, przesuniecie=(0.0, 0.0)):
    """Warstwa z dwoma dymkami rozmowy, wyśrodkowana na płótnie [size]."""
    warstwa = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rysuj = ImageDraw.Draw(warstwa)

    def punkt(x, y):
        return (
            size * (0.5 + (x - 0.5) * skala + przesuniecie[0]),
            size * (0.5 + (y - 0.5) * skala + przesuniecie[1]),
        )

    # Dymek z tyłu (ten „drugiej osoby").
    rysuj.rounded_rectangle(
        [punkt(0.18, 0.20), punkt(0.68, 0.54)],
        radius=size * 0.085 * skala,
        fill=BIALY_PRZYGASZONY,
    )

    # Dymek na wierzchu, z ogonkiem w lewym dolnym rogu.
    rysuj.rounded_rectangle(
        [punkt(0.32, 0.44), punkt(0.82, 0.76)],
        radius=size * 0.085 * skala,
        fill=BIALY,
    )
    rysuj.polygon(
        [punkt(0.40, 0.74), punkt(0.40, 0.88), punkt(0.56, 0.75)],
        fill=BIALY,
    )
    return warstwa


def ikona_launchera(size):
    duzy = size * SUPERSAMPLING
    tlo = gradient(duzy)

    maska = Image.new("L", (duzy, duzy), 0)
    ImageDraw.Draw(maska).rounded_rectangle(
        [0, 0, duzy - 1, duzy - 1], radius=duzy * 0.22, fill=255
    )
    tlo.putalpha(maska)

    tlo.alpha_composite(dymki(duzy, skala=0.92))
    return tlo.resize((size, size), Image.LANCZOS)


def ikona_foreground(size):
    """Sama warstwa z dymkami, tło rysuje system z koloru."""
    duzy = size * SUPERSAMPLING
    # Widoczne jest środkowe 66% płótna, więc dymki muszą się w nim zmieścić.
    warstwa = dymki(duzy, skala=0.60)
    return warstwa.resize((size, size), Image.LANCZOS)


def ikona_powiadomienia(size):
    """Biała sylwetka dwóch dymków na przezroczystym tle.

    Kolorów tu nie ma: pasek stanu i tak pokazuje taką ikonę jednym kolorem,
    więc dymki muszą się rozdzielać kształtem. Tylny dymek jest podcięty
    przezroczystą szczeliną wokół przedniego.
    """
    duzy = size * SUPERSAMPLING
    warstwa = Image.new("RGBA", (duzy, duzy), (0, 0, 0, 0))
    rysuj = ImageDraw.Draw(warstwa)

    # Wewnątrz kwadratu 24 dp ikona ma zostawić ~2 dp marginesu.
    m = duzy * 0.08

    def punkt(x, y):
        return (m + (duzy - 2 * m) * x, m + (duzy - 2 * m) * y)

    promien = (duzy - 2 * m) * 0.14
    rysuj.rounded_rectangle(
        [punkt(0.0, 0.05), punkt(0.62, 0.52)], radius=promien, fill=BIALY
    )
    # Szczelina: kasujemy fragment tylnego dymka pod przednim.
    rysuj.rounded_rectangle(
        [punkt(0.30, 0.36), punkt(1.06, 0.92)],
        radius=promien * 1.2,
        fill=(0, 0, 0, 0),
    )
    rysuj.rounded_rectangle(
        [punkt(0.38, 0.44), punkt(1.0, 0.86)], radius=promien, fill=BIALY
    )
    rysuj.polygon(
        [punkt(0.46, 0.84), punkt(0.46, 1.0), punkt(0.62, 0.85)], fill=BIALY
    )
    return warstwa.resize((size, size), Image.LANCZOS)


def zapisz(sciezka, obraz):
    os.makedirs(os.path.dirname(sciezka), exist_ok=True)
    obraz.save(sciezka)
    print("zapisano", sciezka)


def main():
    res = os.path.join("android", "app", "src", "main", "res")

    for katalog, rozmiar in ANDROID_LAUNCHER.items():
        zapisz(os.path.join(res, katalog, "ic_launcher.png"), ikona_launchera(rozmiar))

    for katalog, rozmiar in ANDROID_FOREGROUND.items():
        zapisz(
            os.path.join(res, katalog, "ic_launcher_foreground.png"),
            ikona_foreground(rozmiar),
        )

    for katalog, rozmiar in ANDROID_NOTIFICATION.items():
        zapisz(
            os.path.join(res, katalog, "ic_notification.png"),
            ikona_powiadomienia(rozmiar),
        )

    najwieksza = ikona_launchera(256)
    zapisz(
        os.path.join("windows", "runner", "resources", "app_icon.ico"),
        najwieksza,
    )
    # ICO z kilkoma rozmiarami naraz: Windows sam wybiera pasujący.
    najwieksza.save(
        os.path.join("windows", "runner", "resources", "app_icon.ico"),
        sizes=[(s, s) for s in WINDOWS_SIZES],
    )

    podglad = ikona_launchera(512)
    zapisz(os.path.join("build", "icon_preview.png"), podglad)


if __name__ == "__main__":
    main()
