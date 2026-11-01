# OpenTTD for AmigaOS 3.x

Standalone AmigaChrome port repository for OpenTTD. Upstream is pinned to
`d48d693d7ff09b643846e23a5f033cf3582ab27f`.

## Prepare and build

```sh
python3 scripts/game_port_prepare.py prepare --game openttd --allow-network
./build-host.sh
./build-amigaos3.sh
```

The pinned host build configures and compiles the native client and its build
tools. Its test pass is 94/98; the four data-driven regression tests stop only
because no OpenGFX graphics payload is bundled. The first target pass on 1
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
