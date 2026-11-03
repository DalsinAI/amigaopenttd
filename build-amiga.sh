#!/bin/sh
# OpenTTD for AmigaOS 3.x / AmiCradle (68040 + FPU, libnix, SDL 2 through
# GFOpenGPU), built with the os32-gcc16 stove: OpenAmigaGCC 16.2.0-open3 or
# open4, known by their archives' SHA-256, or GFOpenAmigaGCC 16.2.0-open5
# (Cradle's os32-gcc16 stove), which has no published archive: its receipt
# records the SHA-256 of the compiler's own programs instead. This is the
# build Cradle's stove_build runs (STOVE= and OUT= set, target .).
#   STOVE   the stove (default ~/AmiCradle/stoves/os32-gcc16, then
#           ~/AmigaChrome/stoves/os32-gcc16)
#   OUT     the output directory (default build-amiga)
#   JOBS    parallel compiles (default: every core)
#   CACHE   where the downloads are kept (default build/cache)
# The source is OpenTTD's own release archive and the base sets are the
# OpenTTD project's own release packages, all fetched by URL and checked
# against the SHA-256 in gameports/catalog.json before use; patches/ is
# applied to the unpacked source with no fuzz. OpenTTD's code generators
# (strgen, settingsgen and the script API tools) run on the build PC, so they
# are built first for it (OPTION_TOOLS_ONLY), then the game for the Amiga.
# Outputs: OpenTTD/openttd (the program), openttd-data.tar (everything the
# game reads beside itself: lang/, baseset/ with OpenGFX and OpenSFX, ai/,
# game/, scripts/ and the licences), untar (the Amiga unpacker for it),
# SHA256SUMS (one line a data file), receipt.json and build.log.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -z "${STOVE:-}" ]; then
    STOVE="$HOME/AmiCradle/stoves/os32-gcc16"
    [ -d "$STOVE" ] || STOVE="$HOME/AmigaChrome/stoves/os32-gcc16"
fi
OUT=${OUT:-"$HERE/build-amiga"}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
CACHE=${CACHE:-"$HERE/build/cache"}
OPEN3=9fcc136ab59e3bb5b91d2764d0bf290b709d72d7380be4ce0cdf005edf8eff21
OPEN4=495319a2ffd803278f8827cad70074029c7aa9ecbe05d037e8646ba43ab94ab2
P="$STOVE/prefix"
SDK="$P/m68k-amigaos"
CC="$P/bin/m68k-amigaos-gcc"
CXX="$P/bin/m68k-amigaos-g++"
START=$(date +%s)
mkdir -p "$OUT" "$CACHE"
OUT=$(CDPATH= cd -- "$OUT" && pwd)
CACHE=$(CDPATH= cd -- "$CACHE" && pwd)
echo "host: $(uname -srm), $(nproc 2>/dev/null || echo '?') cores, jobs $JOBS"

# the compiler must be one of them: open3 or open4 by its archive's
# checksum, from the stove's STOVE.json (Cradle's stoves) or provenance.json
# (a staged stove); open5 by STOVE.json's release and the compiler's own
# --version, as Cradle's stove has it (no archive published)
COMPILER=$(python3 - "$STOVE" "$OPEN3" "$OPEN4" "$CC" <<'EOF'
import json, subprocess, sys
from pathlib import Path
stove = Path(sys.argv[1])
known = {sys.argv[2]: "16.2.0-open3", sys.argv[3]: "16.2.0-open4"}
got = release = None
if (stove / "STOVE.json").is_file():
    info = json.loads((stove / "STOVE.json").read_text())
    got = (info.get("compilerArchive") or {}).get("sha256")
    release = info.get("release")
if got is None and (stove / "provenance.json").is_file():
    got = json.loads((stove / "provenance.json").read_text()).get("archive_sha256")
if got in known:
    print(known[got], got)
elif got is None and release == "GFOpenAmigaGCC 16.2.0-open5":
    version = subprocess.run([sys.argv[4], "--version"], capture_output=True, text=True).stdout
    if "(GFOpenAmigaGCC 16.2.0-open5)" not in version:
        sys.exit(f"STOVE.json says {release}, the compiler says {version.splitlines()[:1]}")
    print("16.2.0-open5", "unpublished")
else:
    sys.exit(f"{stove} is not an OpenAmigaGCC 16.2.0-open3 or open4 or a GFOpenAmigaGCC 16.2.0-open5 stove (compiler archive {got}, release {release})")
EOF
)
RELEASE=${COMPILER% *}
ARCHIVE=${COMPILER#* }
"$CC" --version | head -n 1
"$CC" --version | head -n 1 | grep -q "$RELEASE" || { echo "$CC is not $RELEASE"; exit 2; }

# SDL 2 from the stove's SDK (GFOpenGPU's link stubs); OpenTTD uses SDL's
# video, events and audio, so libSDL2.a is the only library it links
SDL_INC="$SDK/include/SDL2"
SDL_LIB="$SDK/lib/libSDL2.a"
for f in "$SDL_INC/SDL.h" "$SDL_LIB"; do
    [ -f "$f" ] || { echo "the stove has no $f"; exit 2; }
done
SDL_EXTRA=m
[ -f "$SDK/lib/libGL.a" ] && SDL_EXTRA="GL;m"

# host tools: CMake 3.17 or later and Ninja; when the build PC has none (or
# an older CMake), the pinned ones from PyPI in a virtual environment
WORK=$(mktemp -d "${TMPDIR:-/tmp}/openttd-build.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
cmake_ok() {
    command -v cmake >/dev/null 2>&1 || return 1
    v=$(cmake --version | sed -n '1s/.* \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
    [ "$(printf '%s\n3.17\n' "$v" | sort -V | head -n 1)" = "3.17" ]
}
if ! cmake_ok || ! command -v ninja >/dev/null 2>&1; then
    if python3 -m venv "$WORK/venv" 2>/dev/null; then
        "$WORK/venv/bin/pip" install -q --disable-pip-version-check cmake==3.31.6 ninja==1.11.1.1
    else
        # no venv module on this PC: the same packages, installed beside WORK
        python3 -m pip install -q --disable-pip-version-check --target "$WORK/venv/lib" cmake==3.31.6 ninja==1.11.1.1
        mkdir -p "$WORK/venv/bin"
        for t in cmake ninja; do
            printf '#!/bin/sh\nPYTHONPATH="%s" exec python3 -c "import sys; from %s import %s; sys.argv[0] = \\"%s\\"; sys.exit(%s())" "$@"\n' \
                "$WORK/venv/lib" "$t" "$t" "$t" "$t" > "$WORK/venv/bin/$t"
            chmod +x "$WORK/venv/bin/$t"
        done
    fi
    PATH="$WORK/venv/bin:$PATH"
fi
echo "tools: $(cmake --version | head -n 1), ninja $(ninja --version), $(c++ --version | head -n 1)"

# the pinned inputs: OpenTTD's source release and the base sets, each by
# its SHA-256 (gameports/catalog.json)
python3 - "$HERE/gameports/catalog.json" "$CACHE" > "$WORK/inputs.env" <<'EOF'
import hashlib, json, sys, urllib.request
from pathlib import Path
catalog, cache = json.loads(Path(sys.argv[1]).read_text()), Path(sys.argv[2])
def fetch(name, url, sha):
    dest = cache / url.rsplit("/", 1)[1]
    if not dest.is_file() or hashlib.sha256(dest.read_bytes()).hexdigest() != sha:
        print(f"fetch {url}", file=sys.stderr)
        part = dest.with_suffix(dest.suffix + ".part")
        # the CDN refuses Python's own user agent
        req = urllib.request.Request(url, headers={"User-Agent": "curl/8.5.0"})
        with urllib.request.urlopen(req, timeout=120) as r, open(part, "wb") as f:
            while chunk := r.read(1 << 20):
                f.write(chunk)
        got = hashlib.sha256(part.read_bytes()).hexdigest()
        if got != sha:
            part.unlink()
            sys.exit(f"{url}: SHA-256 {got}, expected {sha}")
        part.replace(dest)
    print(f"{name}={dest}")
release = catalog["ports"]["openttd"]["release"]
fetch("SRC_ARCHIVE", release["url"], release["sha256"])
print(f"SRC_VERSION={release['version']}")
print(f"SRC_COMMIT={catalog['ports']['openttd']['source']['commit']}")
for name in ("opengfx", "opensfx"):
    pkg = catalog["runtimePackages"][name]
    fetch(name.upper(), pkg["url"], pkg["sha256"])
EOF
. "$WORK/inputs.env"

SRC="$WORK/openttd-$SRC_VERSION"
tar -xJf "$SRC_ARCHIVE" -C "$WORK"
# the release archive names its commit in .ottdrev (tab-separated)
[ "$(cut -f4 "$SRC/.ottdrev")" = "$SRC_COMMIT" ] || { echo "the source archive is not commit $SRC_COMMIT"; exit 2; }
for patch in "$HERE"/patches/*.patch; do
    [ -f "$patch" ] || continue
    echo "patch: $(basename "$patch")"
    patch --batch --forward --fuzz=0 -p1 -d "$SRC" < "$patch"
done
EPOCH=$(git -C "$HERE" show -s --format=%ct HEAD 2>/dev/null || date +%s)
REPO_REV=$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown)
export SOURCE_DATE_EPOCH="$EPOCH"

# 1. the code generators, for the build PC
echo "host tools: configure"
cmake -S "$SRC" -B "$WORK/host" -G Ninja -DCMAKE_BUILD_TYPE=Release -DOPTION_TOOLS_ONLY=ON > "$WORK/host.log" 2>&1 \
    || { tail -n 40 "$WORK/host.log"; exit 1; }
cmake --build "$WORK/host" -j "$JOBS" >> "$WORK/host.log" 2>&1 || { tail -n 40 "$WORK/host.log"; exit 1; }
echo "host tools ready after $(( $(date +%s) - START )) s"

# 2. the game, for the Amiga. SDL2 is the stove's static link stub, given to
# OpenTTD's find_package(SDL2) as a package of its own; every other optional
# library OpenTTD looks for is left out, so nothing from the build PC can be
# picked up (no zlib, LZMA, LZO, PNG, FreeType, ICU, HarfBuzz, curl, Fluidsynth,
# Opus, OpenGL renderer, Allegro).
mkdir -p "$WORK/sdl2"
cat > "$WORK/sdl2/SDL2Config.cmake" <<EOF
set(SDL2_FOUND TRUE)
add_library(SDL2::SDL2 STATIC IMPORTED)
set_target_properties(SDL2::SDL2 PROPERTIES
    IMPORTED_LOCATION "$SDL_LIB"
    INTERFACE_INCLUDE_DIRECTORIES "$SDL_INC"
    INTERFACE_LINK_LIBRARIES "$SDL_EXTRA")
EOF
NOFIND=""
for p in ZLIB PNG LibLZMA LZO CURL Freetype Fontconfig Harfbuzz ICU Fluidsynth OpusFile \
         OpenGL Allegro Grfcodec unofficial-breakpad Doxygen Iconv; do
    NOFIND="$NOFIND -DCMAKE_DISABLE_FIND_PACKAGE_$p=ON"
done
# -fno-delete-null-pointer-checks: address 0 is memory on an Amiga
echo "game: configure"
# shellcheck disable=SC2086
cmake -S "$SRC" -B "$WORK/cross" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$HERE/toolchain/amigaos3-opengpu.cmake" \
    -DAMIGA_STOVE="$STOVE" \
    -DHOST_BINARY_DIR="$WORK/host" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE="-O2 -DNDEBUG -fno-delete-null-pointer-checks -ffile-prefix-map=$WORK=." \
    -DCMAKE_CXX_FLAGS_RELEASE="-O2 -DNDEBUG -fno-delete-null-pointer-checks -ffile-prefix-map=$WORK=." \
    -DOPTION_USE_ASSERTS=OFF -DOPTION_INSTALL_FHS=OFF \
    -DSDL2_DIR="$WORK/sdl2" $NOFIND > "$WORK/cross.log" 2>&1 \
    || { tail -n 60 "$WORK/cross.log"; exit 1; }
grep -E "found -- |not found|Detecting" "$WORK/cross.log" || true
echo "game: build ($JOBS jobs)"
cmake --build "$WORK/cross" --target openttd -j "$JOBS" > "$OUT/build.log" 2>&1 \
    || { grep -E -A12 "FAILED|error:" "$OUT/build.log" | head -n 150; tail -n 20 "$OUT/build.log"; exit 1; }
grep -c "warning:" "$OUT/build.log" | sed 's/^/compiler warnings: /' || true
echo "game built after $(( $(date +%s) - START )) s"

EXE="$WORK/cross/openttd"
[ -f "$EXE" ] || { echo "no executable: see build.log"; exit 2; }
[ "$(od -An -tx1 -N4 "$EXE" | tr -d ' \n')" = "000003f3" ] || { echo "not an Amiga HUNK executable"; exit 2; }

# the program's symbols, for reading a stuck or crashed task's stack in a lab
# (tests/lab TaskPeek prints "hunk N + offset"): sorted, xz-compressed
"$P/bin/m68k-amigaos-objdump" -h "$EXE" > "$OUT/openttd.sections"
"$P/bin/m68k-amigaos-nm" -n -C --defined-only "$EXE" | xz -9 > "$OUT/openttd.map.xz"
command -v ccache >/dev/null 2>&1 && echo "ccache: $(command -v ccache)" || echo "ccache: none"

# the drawer: the program, stripped of its symbols, and the licence
D="$OUT/OpenTTD"
mkdir -p "$D"
"$P/bin/m68k-amigaos-strip" -o "$D/openttd" "$EXE"
cp "$SRC/COPYING.md" "$D/COPYING.md"

# the data, as OpenTTD's own install puts it beside the program, and the
# base sets in baseset/ as the projects ship them (one .tar each, which
# OpenTTD reads as it is)
STAGE="$WORK/stage"
cmake --install "$WORK/cross" --prefix "$STAGE" --component language_files > /dev/null
cp "$OPENGFX" "$OPENSFX" "$WORK/"
(cd "$WORK" && python3 -c '
import sys, zipfile
for z in sys.argv[1:]:
    with zipfile.ZipFile(z) as f:
        names = [n for n in f.namelist() if n.endswith(".tar") and "/" not in n]
        assert len(names) == 1, (z, names)
        f.extract(names[0], "stage/baseset")
' "$(basename "$OPENGFX")" "$(basename "$OPENSFX")")
for f in COPYING.md README.md CREDITS.md changelog.md known-bugs.md; do
    cp "$SRC/$f" "$STAGE/$f"
done
LIST="$WORK/list"
(cd "$STAGE" && find . -type f -print | sed 's|^\./||' | LC_ALL=C sort) > "$LIST"
(cd "$STAGE" && while read -r f; do sha256sum "$f"; done < "$LIST") > "$OUT/SHA256SUMS"
(cd "$STAGE" && tar --format=ustar --no-recursion --owner=0 --group=0 --numeric-owner \
    --mode='u=rw,go=r' --mtime="@$EPOCH" -cf "$OUT/openttd-data.tar" -T "$LIST")

# untar, the small unpacker for it (OS 3.2 has no tar)
"$CC" -noixemul -m68040 -O2 -Wall -Wno-stringop-truncation \
    -ffile-prefix-map="$HERE"=. -o "$OUT/untar" "$HERE/runtime-data/untar.c"
[ "$(od -An -tx1 -N4 "$OUT/untar" | tr -d ' \n')" = "000003f3" ] || { echo "untar is not an Amiga HUNK executable"; exit 2; }

python3 - "$HERE" "$OUT" "$EXE" "$SRC_COMMIT" "$SRC_VERSION" "$REPO_REV" "$EPOCH" "$STOVE" "$RELEASE" "$ARCHIVE" "$SDL_LIB" <<'EOF'
import hashlib, json, sys
from pathlib import Path
here, out, exe = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
commit, version, rev, epoch, stove, release, archive, sdl = sys.argv[4:]
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
catalog = json.loads((here / "gameports/catalog.json").read_text())
sums = (out / "SHA256SUMS").read_bytes()
receipt = {
    "upstream_version": version, "upstream_commit": commit,
    "upstream_archive_sha256": catalog["ports"]["openttd"]["release"]["sha256"],
    "repository_commit": rev, "source_date_epoch": epoch,
    "recipe": {"build-amiga.sh": sha(here / "build-amiga.sh"),
               "toolchain/amigaos3-opengpu.cmake": sha(here / "toolchain/amigaos3-opengpu.cmake")},
    "patches": {p.name: sha(p) for p in sorted((here / "patches").glob("*.patch"))},
    "compiler_release": release, "compiler_archive_sha256": archive,
    "sdk_inputs": {"lib/libSDL2.a": sha(sdl)},
    "base_sets": {n: {k: catalog["runtimePackages"][n][k] for k in ("version", "license", "sha256")}
                  for n in ("opengfx", "opensfx")},
    "network": False,
    "executable_sha256": sha(out / "OpenTTD/openttd"),
    "executable_bytes": (out / "OpenTTD/openttd").stat().st_size,
    "unstripped_sha256": sha(exe), "unstripped_bytes": exe.stat().st_size,
    "data_files": len(sums.splitlines()),
    "sha256sums_sha256": hashlib.sha256(sums).hexdigest(),
    "data_archive_sha256": sha(out / "openttd-data.tar"),
    "data_archive_bytes": (out / "openttd-data.tar").stat().st_size,
    "untar_sha256": sha(out / "untar"),
    "scope": "Source build only; network play left out (no socket library); no runtime or release pass implied",
}
if archive == "unpublished":
    prefix = Path(stove) / "prefix"
    files = ["bin/m68k-amigaos-gcc", "bin/m68k-amigaos-g++", "bin/m68k-amigaos-as", "bin/m68k-amigaos-ld"]
    files += sorted(str(p.relative_to(prefix)) for p in prefix.glob("libexec/gcc/m68k-amigaos/*/cc1*"))
    receipt["compiler_files_sha256"] = {f: sha(prefix / f) for f in files if (prefix / f).is_file()}
(out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt, indent=2))
EOF
echo "done after $(( $(date +%s) - START )) s"
