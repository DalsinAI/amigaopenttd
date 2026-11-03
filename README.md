# OpenTTD for AmigaOS 3.x / AmiCradle

OpenTTD is the open-source transport simulation game based on Chris Sawyer's
Transport Tycoon Deluxe: build railways, roads, docks and airports, carry
passengers and cargo between towns and industries, and run a company over a
century. GPL-2.0-only (`COPYING.md` in the game drawer). This repository is
the AmiCradle port: the recipe, the patches and the notes. It does not hold
the OpenTTD tree; the build fetches OpenTTD's own 15.3 source release and
the base sets by URL and checks each against its SHA-256 before use.

Target: AmigaOS 3.x, 68040 or 68060 with FPU, libnix, SDL 2 through
GFOpenGPU's `SDL2.module`, built with the `os32-gcc16` stove
(GFOpenAmigaGCC 16.2.0-open5; OpenAmigaGCC 16.2.0-open3 and open4 are also
accepted, by their archives' SHA-256).

## What ships, and its licences

| Part | Version | Licence | Source |
|---|---|---|---|
| OpenTTD | 15.3 (commit `14ec60f2`) | GPL-2.0-only | `openttd-15.3-source.tar.xz`, SHA-256 `5ea21eea...3be7`, from cdn.openttd.org (the release's own manifest gives the same digest) |
| OpenGFX (graphics) | 8.0 | GPL-2.0-only (its `license.txt` and `readme.txt`) | `opengfx-8.0-all.zip`, SHA-256 `43a0c1da...03be` |
| OpenSFX (sounds) | 1.0.3 | CC BY-SA 3.0 for the sounds; GPL-2.0-or-later or CDDL-1.1 for the other files (its `readme.txt` section 1.1 and `license.txt`) | `opensfx-1.0.3-all.zip`, SHA-256 `e0a218b7...3759` |

Each base set ships as the project's own `.tar`, unchanged, with its
licence, readme and credits inside it; OpenTTD reads the tar as it is.
OpenSFX was licensed under CC Sampling Plus 1.0 before its 1.0 release
(its `changelog.txt`: "License: CC BY-SA 3.0, GPLv2+, CDDL 1.1 (was: CC
Sampling Plus)"); 1.0.3 is the CC BY-SA 3.0 release.

OpenMSX (music, GPL-2.0-only, 0.4.2) stays pinned in `gameports/catalog.json`
but is not shipped: OpenTTD plays music only through a MIDI driver (Windows,
macOS, an external MIDI player started with `fork()`, FluidSynth or
Allegro), and none of those exists for AmigaOS 3.x. The game runs with
OpenTTD's built-in "no music" set and the null music driver.

Original Transport Tycoon Deluxe data is never shipped. Someone who owns the
game can copy its files in with `scripts/import_original_ttd.py` (below).

## Feasibility and what was left out

- **Version.** 15.3 is OpenTTD's newest stable release (4 April 2026). Every
  release since 1.10 needs `std::thread` and `std::mutex` to compile; the
  stove's libstdc++ has them (POSIX threads on the SDK's `libpthread`), so no
  older release is easier. On AmigaOS the port starts no threads at all
  (step 2), so the game runs in one task on the 68040.
- **Network play: left out.** OpenTTD's network core is always compiled,
  but libnix has no socket library. `patches/0003-amigaos3-no-network.patch`
  gives the network code the BSD socket types and calls that always fail,
  and the network reports itself unavailable at start, so multiplayer, the
  server list, online content (BaNaNaS) and the survey are not offered.
  IPv6 goes with it.
- **Optional libraries: none.** Only SDL 2 is linked. Without zlib, LZMA and
  LZO, saved games are written uncompressed (OpenTTD's "none" format), and
  saves made by other builds in a compressed format cannot be loaded; the
  title screen's game (`opntitle.dat`, LZMA) cannot be loaded either, so the
  title shows OpenTTD's plain generated landscape. Without libpng,
  screenshots are BMP; without FreeType, the base set's sprite fonts are
  used; without ICU and HarfBuzz, right-to-left scripts are not shaped.
- **Dynamic loading: left out** (no `libdl`), which only affects the social
  integration plug-ins.
- **libnix's gaps**, in `patches/0002-amigaos3-c-runtime.patch`: no `uint`
  type, no C99 `strtof`/`strtoll` family in `<cstdlib>`, no `sigaction`
  (the crash handler uses `signal()`), `_exit()` replaced by `exit()` so the
  program's memory and libraries are given back, and `statvfs()` (which the
  C++ library calls and libnix only declares) answered through AmigaDOS
  `Info()`. The toolchain links `libatomic` for the 1- and 4-byte atomics.
- **Files:** everything is in the game's own drawer (`PROGDIR:`),
  `patches/0004-amigaos3-progdir.patch`: the data, `openttd.cfg` and the
  saves; no home directory and no XDG paths.

## Building

`build-amiga.sh` is the build Cradle's `stove_build` runs (target `.`, with
`STOVE` and `OUT` set). It replaces the earlier `build-amigaos3.sh` (which
now just runs it) because Cradle's stove build looks for that name, and
because the earlier script needed a separate native build of the whole game
and a source tree prepared by hand. In order, it:

1. checks the stove's compiler (open3 or open4 by archive SHA-256, open5 by
   its release and `--version`) and that the stove has SDL 2;
2. fetches OpenTTD 15.3's source release, OpenGFX 8.0 and OpenSFX 1.0.3 and
   checks each SHA-256 (`gameports/catalog.json`), and checks the source
   archive's own `.ottdrev` names commit `14ec60f2`;
3. applies `patches/` with no fuzz;
4. builds OpenTTD's code generators for the build PC (`OPTION_TOOLS_ONLY`;
   CMake 3.17 or later and Ninja, from PyPI at pinned versions when the PC
   has none);
5. configures the game with `toolchain/amigaos3-opengpu.cmake` and the
   stove's `libSDL2.a` given to OpenTTD's `find_package(SDL2)` as a package
   of its own, every other optional library switched off so nothing from the
   build PC can be picked up, and builds the `openttd` target with every
   core;
6. writes `OpenTTD/openttd` (stripped), `openttd-data.tar` (a plain ustar
   archive of everything the game reads beside itself: `lang/`, `baseset/`
   with OpenGFX and OpenSFX, `ai/`, `game/`, `scripts/` and OpenTTD's
   licence, readme and credits), `untar` (the small Amiga unpacker from
   amigakobodeluxe), `SHA256SUMS` and `receipt.json`.

From a checkout, with a staged stove and network access:

```sh
STOVE=/path/to/os32-gcc16 OUT=build-amiga sh build-amiga.sh
```

`build-host.sh` and `scripts/game_port_prepare.py` are kept for a native
(host) build of the same pinned commit, which runs OpenTTD's own tests.

## Original TTD data

A player who owns Transport Tycoon Deluxe may use its graphics, sounds and
music instead of the open sets. Validate and copy a complete Windows or DOS
set into the game's `baseset` drawer with:

```sh
python3 scripts/import_original_ttd.py /path/to/TTD \
  --destination /path/to/OpenTTD/baseset
```

The importer searches case-insensitively, accepts DOS or Windows graphics,
validates complete file groups, imports `sample.cat`, handles Windows or DOS
music, refuses to overwrite different files without `--force`, and writes a
SHA-256 manifest. It contains no original game data.

## Status

**COMPILED**, not RELEASE (`RELEASE_POLICY.md`).

| Gate | State |
|---|---|
| Pinned source, reproducible build, receipts | done (Cradle `stove_build`, open5) |
| Presentation | step 2 |
| Keyboard and mouse | step 3 |
| Sound | step 4 |
| Saves and settings across a cold restart | step 5 |
| Drawer, GlowIcons, Installer, LhA play test | step 6 |

## Observed

### Build, 3 November 2026

Cradle `stove_build`, stove `os32-gcc16` (GFOpenAmigaGCC 16.2.0-open5), job
`j20261103T090854-234471`, commit `0fc5dbd`, on a 12-core build PC: the
host tools in 14 s, the game in 543 s (545 s in all), 140 compiler
warnings, all upstream's.

| Output | Bytes | SHA-256 |
|---|---|---|
| `OpenTTD/openttd` (stripped) | 16,294,244 | `1614e28f25863f8b0732a4ceb78f7b5d435a13fb731e7969727ec480f6d6b0e2` |
| `openttd` before stripping | 17,858,428 | `6735fa591dd5f927bfd2578ee467686bee90da923d34a3a0c5e430a590d66d3f` |
| `openttd-data.tar` (129 files) | 33,843,200 | `572a8fb2...e7da` |
| `untar` | 19,048 | `2de6090b...6b7d` |

The receipt is `receipts/1-build-open5-stove_build.json`. The build's
earlier jobs on this branch failed at the link: `-ldl` (job
`j20261103T084725-c96dc1`), then libatomic and `statvfs()` (job
`j20261103T085805-7ffabc`); the fixes are in the commits after them.

Unpacked in `lab:openttd` (a copy of Instance-32) with `untar` (129 files,
33,736,707 bytes), this build opened its window and found its data
(`PROGDIR:` as configuration and personal directory, OpenGFX and OpenSFX
found in their tars, SDL's `amigaos3` video driver, the window surface in
video RAM) but did not reach the title: see step 2.
