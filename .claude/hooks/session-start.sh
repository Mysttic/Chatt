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

# .NET SDK 10 (LTS) z repozytoriów Ubuntu — potrzebny do budowania i testowania
# bibliotek solucji (protokół, discovery, dane). Idempotentny: nic nie robi,
# gdy SDK już jest (stan kontenera jest cache'owany między sesjami).
if ! command -v dotnet >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  # apt update jest konieczny: zamrożony indeks w obrazie wskazuje wersje .deb,
  # których nie ma już na mirrorach (404). Błędy obcych PPA ignorujemy.
  $SUDO apt-get update -qq || true
  $SUDO apt-get install -y -qq dotnet-sdk-10.0
fi

echo "dotnet SDK: $(dotnet --version)"
