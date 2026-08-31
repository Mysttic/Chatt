#!/bin/bash
# Scenariusz E2E na żywym UI: dwie instancje aplikacji ("Komputer PC" na
# ekranie :91 i "Telefon" na :92) pod Xvfb. B znajduje A przez discovery
# i pisze pierwszy, A odpisuje; po drodze powstają zrzuty ekranu.
#
# Wymagania (Linux): Xvfb, xdotool, imagemagick (import) oraz zbudowana
# aplikacja: (cd app && flutter build linux --release).
#
# Uwagi zdobyte krwią:
# - Bez menedżera okien fokus X11 działa w trybie PointerRoot — klawiatura
#   trafia do okna pod kursorem, więc wystarczy klikać i pisać (bez
#   windowfocus, który potrafi złapać niezmapowane okno pomocnicze GTK).
# - SnackBar przez ~4 s zasłania dół ekranu i połyka kliknięcia w pole
#   tekstowe — stąd dłuższe sleep'y po skanowaniu.
# - xdotool type z polskimi znakami wymaga locale UTF-8.
set -euo pipefail

export LC_ALL=C.UTF-8 LANG=C.UTF-8

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
APP=$SCRIPT_DIR/../build/linux/x64/release/bundle/chatt
[ -x "$APP" ] || { echo "Najpierw: (cd app && flutter build linux --release)"; exit 1; }

WORK=$(mktemp -d)
SHOTS=${1:-$WORK/shots}
mkdir -p "$WORK/instA" "$WORK/instB" "$SHOTS"

cleanup() { kill $APP_A $APP_B $XVFB_A $XVFB_B 2>/dev/null || true; }
trap cleanup EXIT

Xvfb :91 -screen 0 480x860x24 & XVFB_A=$!
Xvfb :92 -screen 0 480x860x24 & XVFB_B=$!
sleep 1

DISPLAY=:91 CHATT_DATA_DIR=$WORK/instA CHATT_TCP_PORT=47780 \
  CHATT_INSTANCE_NAME="Komputer PC" "$APP" > "$WORK/a.log" 2>&1 & APP_A=$!
DISPLAY=:92 CHATT_DATA_DIR=$WORK/instB CHATT_TCP_PORT=47781 \
  CHATT_INSTANCE_NAME="Telefon" "$APP" > "$WORK/b.log" 2>&1 & APP_B=$!
sleep 6

shot() { import -display "$1" -window root "$SHOTS/$2.png"; }
click() { DISPLAY=$1 xdotool mousemove "$2" "$3" click 1; sleep "${4:-1}"; }
type_text() { DISPLAY=$1 xdotool type --delay 40 "$2"; sleep 0.5; }

# --- Telefon (B): pusta lista, przejście do "W pobliżu", skan
shot :92 b1_pusty_ekran
click :92 396 756
shot :92 b2_w_poblizu
click :92 240 92 4
shot :92 b3_po_skanie

# Pierwszy znaleziony -> czat; czekamy aż zniknie SnackBar po skanie
click :92 240 164 5

# Wiadomość i wysyłka przyciskiem (Enter w polu wieloliniowym robi nową linię)
click :92 200 768
type_text :92 "Hej! Widzisz mnie w sieci?"
click :92 448 770 2
shot :92 b4_czat_wyslane

# --- PC (A): badge nieprzeczytanych, wejście w rozmowę, odpowiedź
shot :91 a1_lista_nieprzeczytane
click :91 240 92 2
shot :91 a2_czat_odebrane
click :91 200 768
type_text :91 "Widzę! Działa jak marzenie"
click :91 448 770 2
shot :91 a3_czat_odpowiedz

# --- Telefon (B): pełna rozmowa z potwierdzeniem dostarczenia
shot :92 b5_czat_pelna_rozmowa

# --- Ustawienia na A
click :91 28 28 1
click :91 444 28 2
shot :91 a4_ustawienia

echo "OK — zrzuty w $SHOTS"
ls "$SHOTS"
