#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$ROOT/build/game-ports/sources/openttd"
python3 "$ROOT/scripts/game_port_prepare.py" verify --game openttd
cmake -S "$SRC" -B "$ROOT/build/first-pass" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DOPTION_USE_ASSERTS=OFF -DOPTION_INSTALL_FHS=OFF
cmake --build "$ROOT/build/first-pass" -j"${JOBS:-2}"
