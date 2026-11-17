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

# the game, unless BUILD already holds a build from these exact inputs (BUILD
# set to a finished build-amiga.sh OUT): its receipt's recipe and patch
# SHA-256 must all match this checkout's, so a change to the build, the
# toolchain file or any patch always rebuilds
same_inputs() {
    [ -f "$BUILD/receipt.json" ] || return 1
    python3 - "$ROOT" "$BUILD/receipt.json" <<'PY'
import hashlib, json, sys
from pathlib import Path
root, r = Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text())
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
now = {"recipe": {k: sha(root / k) for k in r.get("recipe", {})},
       "patches": {p.name: sha(p) for p in sorted((root / "patches").glob("*.patch"))}}
ok = r.get("recipe") and now["recipe"] == r["recipe"] and now["patches"] == r.get("patches")
ok = ok and set(r["recipe"]) == {"build-amiga.sh", "toolchain/amigaos3-opengpu.cmake"}
sys.exit(0 if ok else 1)
PY
}
if same_inputs; then
    echo "reusing the build in $BUILD (same recipe and patches)"
else
    OUT="$BUILD" sh "$ROOT/build-amiga.sh"
fi
[ -f "$BUILD/OpenTTD/openttd" ] && [ -f "$BUILD/openttd-data.tar" ] || { echo "the build left no OpenTTD/openttd or openttd-data.tar"; exit 1; }

python3 "$ROOT/tools/make_package.py" --build "$BUILD" --version "$VERSION" --out "$OUT"
