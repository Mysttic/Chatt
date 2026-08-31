#!/bin/bash
set -euo pipefail

# Hook tylko dla sesji Claude Code on the web (kontener zdalny).
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

# --- Zależności systemowe: toolchain desktop Linux + xvfb (uruchamianie UI bez ekranu)
if ! command -v clang >/dev/null 2>&1 || ! dpkg -s libgtk-3-dev >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  # apt update konieczny: zamrożony indeks obrazu wskazuje wersje .deb usunięte
  # już z mirrorów (404). Błędy obcych PPA ignorujemy.
  $SUDO apt-get update -qq || true
  $SUDO apt-get install -y -qq clang cmake ninja-build pkg-config libgtk-3-dev \
    liblzma-dev libstdc++-12-dev xvfb
fi

# --- Flutter SDK (kanał stable, płytki klon). Stan kontenera jest cache'owany
# między sesjami, więc pełna instalacja dzieje się tylko za pierwszym razem.
FLUTTER_DIR=/opt/flutter
if [ ! -d "$FLUTTER_DIR" ] && ! mkdir -p "$FLUTTER_DIR" 2>/dev/null; then
  FLUTTER_DIR="$HOME/flutter"
fi
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  rm -rf "$FLUTTER_DIR"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
flutter --version >/dev/null              # przy pierwszym razie dociąga Dart SDK
flutter precache --linux >/dev/null 2>&1 || true

# --- Zmienne środowiskowe dla reszty sesji
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"$FLUTTER_DIR/bin:\$PATH\""
    # Testy webowe Fluttera używają preinstalowanego Chromium (Playwright).
    echo 'export CHROME_EXECUTABLE=/opt/pw-browsers/chromium'
  } >> "$CLAUDE_ENV_FILE"
fi

# --- Zależności projektu aplikacji (gdy projekt Flutter już istnieje w repo)
if [ -f "${CLAUDE_PROJECT_DIR:-.}/app/pubspec.yaml" ]; then
  (cd "${CLAUDE_PROJECT_DIR:-.}/app" && flutter pub get >/dev/null)
fi

echo "Flutter gotowy: $(flutter --version 2>/dev/null | head -1)"
