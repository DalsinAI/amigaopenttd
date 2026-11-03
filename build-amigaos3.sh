#!/bin/sh
# The Amiga build has one recipe, build-amiga.sh (the name Cradle's
# stove_build runs); this name is kept for older notes and scripts.
set -eu
exec sh "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/build-amiga.sh" "$@"
