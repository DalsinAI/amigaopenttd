#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${OPENTTD_SRC:-"$ROOT/build/game-ports/sources/openttd"}
OUT=${OUT:-"$ROOT/build/os3"}
HOST_BUILD=${HOST_BUILD:-"$ROOT/build/first-pass"}
STOVE=${STOVE:-"$HOME/AmigaChrome/stoves/os32-gcc16"}
WORK="$OUT/source"

[ -x "$STOVE/prefix/bin/m68k-amigaos-g++" ] || { echo "missing OpenAmigaGCC stove" >&2; exit 2; }
[ -d "$SRC/.git" ] || { echo "prepare the pinned source first" >&2; exit 2; }
[ -f "$HOST_BUILD/settingsgen.cmake" ] || { echo "missing native host tools; run ./build-host.sh first" >&2; exit 2; }
[ -f "$HOST_BUILD/strgen.cmake" ] || { echo "missing native host tools; run ./build-host.sh first" >&2; exit 2; }

expected=$(python3 -c 'import json; print(json.load(open("gameports/catalog.json"))["ports"]["openttd"]["source"]["commit"])')
actual=$(git -C "$SRC" rev-parse HEAD)
[ "$actual" = "$expected" ] || { echo "source revision mismatch" >&2; exit 2; }
[ -z "$(git -C "$SRC" status --porcelain)" ] || { echo "source cache is not pristine" >&2; exit 2; }

rm -rf "$OUT"
mkdir -p "$OUT"
git -C "$SRC" archive HEAD -o "$OUT/source.tar"
mkdir "$WORK"
tar -xf "$OUT/source.tar" -C "$WORK"
rm "$OUT/source.tar"
for patch_file in "$ROOT"/patches/*.patch; do
    patch --batch --fuzz=0 -d "$WORK" -p1 < "$patch_file"
done

cmake -S "$WORK" -B "$OUT/cmake" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$ROOT/toolchain/amigaos3-opengpu.cmake" \
    -DAMIGA_STOVE="$STOVE" \
    -DHOST_BINARY_DIR="$HOST_BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DOPTION_USE_ASSERTS=OFF \
    -DOPTION_INSTALL_FHS=OFF

cmake --build "$OUT/cmake" -j"${JOBS:-2}"
