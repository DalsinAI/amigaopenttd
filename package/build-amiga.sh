#!/bin/sh
# The release archive, for Cradle's stove_build (target package): the game
# built by the repository's own build-amiga.sh (STOVE= as given), then
# tools/make_package.py packs openttd-VERSION-68040.lha with its .sha256 and
# .readme: the OpenTTD drawer with its GlowIcons (icons/), the program, the
# data it reads (lang/, baseset/ with OpenGFX and OpenSFX, ai/, game/) and
# the ReadMe, and beside the drawer the Amiga Installer script
# Install-OpenTTD and its icon (package/installer/, made by amicradle
# scripts/ports/port_installer.py from package/installer.json).
# VERSION is package/VERSION. Nothing is published from here.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
OUT=${OUT:-"$ROOT/build-amiga-package"}
VERSION=$(cat "$HERE/VERSION")
mkdir -p "$OUT"
OUT=$(CDPATH= cd -- "$OUT" && pwd)
BUILD=${BUILD:-"$OUT/build"}
mkdir -p "$BUILD"

# the game (skipped when BUILD already holds this commit's build: BUILD set
# to a finished build-amiga.sh OUT)
REV=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
if [ ! -f "$BUILD/receipt.json" ] || ! grep -q "\"repository_commit\": \"$REV\"" "$BUILD/receipt.json"; then
    OUT="$BUILD" sh "$ROOT/build-amiga.sh"
fi
[ -f "$BUILD/OpenTTD/openttd" ] && [ -f "$BUILD/openttd-data.tar" ] || { echo "the build left no OpenTTD/openttd or openttd-data.tar"; exit 1; }

python3 "$ROOT/tools/make_package.py" --build "$BUILD" --version "$VERSION" --out "$OUT"
