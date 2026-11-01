# OpenTTD for AmigaOS 3.x

Standalone AmiCradle port repository for OpenTTD. Upstream is pinned to
`d48d693d7ff09b643846e23a5f033cf3582ab27f`.

## Prepare and build

```sh
python3 scripts/game_port_prepare.py prepare --game openttd --allow-network
./build-host.sh
./build-amigaos3.sh
```

Preparation fetches exact commits of OpenTTD and the official OpenGFX,
OpenSFX and OpenMSX repositories. It also fetches the complete official stable
base-set packages by immutable version and SHA-256. Their revisions, package
URLs, licences and hashes live in `gameports/catalog.json`; moving branches or
unverified downloads are never consumed by the build. Stage the verified open
sets into a build or package with:

```sh
python3 scripts/stage_open_basesets.py build/first-pass/baseset
```

That command writes the three directly loadable tar files and an
`OPEN_BASESETS.json` provenance manifest.

## Base data and original TTD import

OpenGFX, OpenSFX and OpenMSX are the redistributable default graphics, sound
and music sets. A user may instead use data from a legally owned Transport
Tycoon Deluxe installation or CD. Validate and copy a complete Windows or DOS
set into a package or installation with:

```sh
python3 scripts/import_original_ttd.py /path/to/TTD \
  --destination /path/to/OpenTTD/baseset
```

The importer searches case-insensitively, accepts DOS or Windows graphics,
validates complete file groups, imports `sample.cat`, handles Windows or DOS
music, refuses to overwrite different files without `--force`, and emits a
SHA-256 manifest. For Transport Tycoon Original music use `--components music
--music-format tto`; `GM.CAT` is installed as `gm-tto.cat`. The importer only
copies user-supplied local files and contains no original game data.

The pinned host build configures and compiles the native client and its build
tools. Its initial test pass was 94/98; the four data-driven regression tests
required an OpenGFX graphics payload, which is now pinned as a reproducible
runtime input. The first target pass on 1
November 2026 added AmigaOS `PROGDIR:`
directory and package handling to upstream CMake, imports the native
`settingsgen`/`strgen` tools through `HOST_BINARY_DIR`, and suppresses the
inappropriate ELF `-rdynamic` flag. OpenAmigaGCC then generated every language
and script binding and advanced into the target C++ client. The current first
platform boundary is OpenTTD's socket abstraction: it has Windows and UNIX
lanes but no Amiga bsdsocket lane. The bundled JSON implementation also needs
small Amiga C-library namespace compatibility changes.

SDL2 and OpenGPU GL were found in the existing stove. PNG/zlib and other open
libraries must be mapped from the target SDK, never from the host. OpenGFX,
OpenSFX and OpenMSX remain separately sourced payloads. This is not yet a
playable build or release.
