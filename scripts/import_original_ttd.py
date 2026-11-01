#!/usr/bin/env python3
"""Import user-owned Transport Tycoon Deluxe base media for OpenTTD.

This tool copies data only from a directory supplied by the user. It neither
downloads nor contains copyrighted TTD media.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path


GRAPHICS = {
    "windows": ("trg1r.grf", "trgcr.grf", "trghr.grf", "trgir.grf", "trgtr.grf"),
    "dos": ("trg1.grf", "trgc.grf", "trgh.grf", "trgi.grf", "trgt.grf"),
}
WINDOWS_MUSIC = tuple(f"gm_tt{i:02d}.gm" for i in range(22))
COMPONENTS = {"graphics", "sound", "music"}


class ImportFailure(RuntimeError):
    pass


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for block in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def source_index(source: Path, destination: Path) -> dict[str, list[Path]]:
    index: dict[str, list[Path]] = {}
    destination = destination.resolve()
    for path in source.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        resolved = path.resolve()
        if resolved == destination or destination in resolved.parents:
            continue
        index.setdefault(path.name.casefold(), []).append(path)
    for paths in index.values():
        paths.sort(key=lambda p: (len(p.relative_to(source).parts), str(p).casefold()))
    return index


def find(index: dict[str, list[Path]], name: str) -> Path | None:
    matches = index.get(name.casefold(), [])
    return matches[0] if matches else None


def complete_group(index: dict[str, list[Path]], names: tuple[str, ...]) -> bool:
    return all(find(index, name) is not None for name in names)


def select_graphics(index: dict[str, list[Path]], requested: str) -> tuple[str, tuple[str, ...]]:
    choices = tuple(GRAPHICS) if requested == "auto" else (requested,)
    for choice in choices:
        names = GRAPHICS[choice]
        if complete_group(index, names):
            return choice, names
    details = {
        choice: [name for name in GRAPHICS[choice] if find(index, name) is None]
        for choice in choices
    }
    raise ImportFailure(f"no complete original graphics set found; missing: {details}")


def select_music(index: dict[str, list[Path]], requested: str) -> tuple[str, tuple[tuple[str, str], ...]]:
    if requested in {"auto", "windows"} and complete_group(index, WINDOWS_MUSIC):
        return "windows", tuple((name, name) for name in WINDOWS_MUSIC)
    if requested in {"auto", "dos"} and find(index, "gm.cat") is not None:
        return "dos", (("gm.cat", "gm.cat"),)
    if requested == "tto" and find(index, "gm.cat") is not None:
        return "tto", (("gm.cat", "gm-tto.cat"),)
    if requested == "windows":
        missing = [name for name in WINDOWS_MUSIC if find(index, name) is None]
        raise ImportFailure(f"incomplete Windows TTD music set; missing: {missing}")
    raise ImportFailure(f"no complete {requested} original music set found")


def copy_one(source: Path, destination: Path, *, force: bool, dry_run: bool) -> str:
    if destination.exists():
        if destination.is_file() and digest(source) == digest(destination):
            return "unchanged"
        if not force:
            raise ImportFailure(f"refusing to replace existing file: {destination}")
    if dry_run:
        return "would-copy"
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".importing")
    temporary.unlink(missing_ok=True)
    shutil.copy2(source, temporary)
    os.replace(temporary, destination)
    return "copied"


def parse_components(raw: str) -> set[str]:
    selected = {item.strip().casefold() for item in raw.split(",") if item.strip()}
    unknown = selected - COMPONENTS
    if not selected or unknown:
        raise argparse.ArgumentTypeError(
            "components must be a comma-separated selection of graphics,sound,music"
        )
    return selected


def import_media(args: argparse.Namespace) -> dict:
    source = args.source.expanduser().resolve()
    destination = args.destination.expanduser().resolve()
    if not source.is_dir():
        raise ImportFailure(f"source directory does not exist: {source}")
    if source == destination:
        raise ImportFailure("source and destination must be different directories")
    index = source_index(source, destination)
    planned: list[tuple[str, Path, str]] = []
    variants: dict[str, str] = {}

    if "graphics" in args.components:
        variant, names = select_graphics(index, args.graphics_format)
        variants["graphics"] = variant
        planned.extend((name, find(index, name), name) for name in names)  # type: ignore[arg-type]
    if "sound" in args.components:
        sample = find(index, "sample.cat")
        if sample is None:
            raise ImportFailure("original sound requested but sample.cat was not found")
        variants["sound"] = "original"
        planned.append(("sample.cat", sample, "sample.cat"))
    if "music" in args.components:
        variant, names = select_music(index, args.music_format)
        variants["music"] = variant
        for source_name, destination_name in names:
            path = find(index, source_name)
            assert path is not None
            planned.append((source_name, path, destination_name))

    files = []
    for source_name, source_path, destination_name in planned:
        target = destination / destination_name
        status = copy_one(source_path, target, force=args.force, dry_run=args.dry_run)
        files.append({
            "sourceName": source_name,
            "source": str(source_path),
            "destination": str(target),
            "sha256": digest(source_path),
            "status": status,
        })
    return {
        "ok": True,
        "copyrightedDataRedistributed": False,
        "source": str(source),
        "destination": str(destination),
        "components": sorted(args.components),
        "variants": variants,
        "files": files,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate and import user-owned original TTD base media"
    )
    parser.add_argument("source", type=Path, help="original TTD installation or CD directory")
    parser.add_argument("--destination", type=Path, required=True, help="OpenTTD baseset directory")
    parser.add_argument(
        "--components", type=parse_components, default=parse_components("graphics,sound,music")
    )
    parser.add_argument("--graphics-format", choices=("auto", "windows", "dos"), default="auto")
    parser.add_argument("--music-format", choices=("auto", "windows", "dos", "tto"), default="auto")
    parser.add_argument("--force", action="store_true", help="replace different destination files")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    try:
        result = import_media(args)
    except ImportFailure as exc:
        parser.error(str(exc))
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
