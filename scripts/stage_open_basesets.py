#!/usr/bin/env python3
"""Stage verified OpenGFX, OpenSFX and OpenMSX packages into a baseset dir."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "gameports/catalog.json"
PREPARED = ROOT / "build/game-ports/PREPARED.json"


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for block in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def copy_atomic(source: Path, destination: Path, *, force: bool) -> str:
    if destination.exists():
        if destination.is_file() and digest(source) == digest(destination):
            return "unchanged"
        if not force:
            raise RuntimeError(f"refusing to replace different file: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".staging")
    temporary.unlink(missing_ok=True)
    shutil.copy2(source, temporary)
    os.replace(temporary, destination)
    return "copied"


def stage(destination: Path, *, force: bool) -> dict:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    prepared = json.loads(PREPARED.read_text(encoding="utf-8"))
    packages = catalog["runtimePackages"]
    prepared_packages = prepared.get("runtimePackages") or {}
    staged = {}
    for package_id, specification in sorted(packages.items()):
        item = prepared_packages.get(package_id)
        if not isinstance(item, dict):
            raise RuntimeError(f"{package_id}: not prepared; run game_port_prepare.py first")
        archive = Path(item["archive"])
        if digest(archive) != specification["sha256"]:
            raise RuntimeError(f"{package_id}: prepared archive SHA-256 mismatch")
        package_root = Path(item["path"])
        payloads = sorted(package_root.rglob("*.tar"))
        if len(payloads) != 1:
            raise RuntimeError(f"{package_id}: expected exactly one base-set tar, found {len(payloads)}")
        payload = payloads[0]
        target = destination / payload.name
        status = copy_atomic(payload, target, force=force)
        staged[package_id] = {
            "version": specification["version"],
            "license": specification["license"],
            "source": specification["url"],
            "archiveSha256": specification["sha256"],
            "file": target.name,
            "sha256": digest(payload),
            "status": status,
        }
    manifest = {
        "schema": "amigaopenttd-open-basesets",
        "version": 1,
        "packages": staged,
    }
    destination.mkdir(parents=True, exist_ok=True)
    manifest_path = destination / "OPEN_BASESETS.json"
    temporary = manifest_path.with_suffix(".tmp")
    temporary.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, manifest_path)
    return manifest


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path, help="OpenTTD baseset directory")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args(argv)
    result = stage(args.destination.expanduser().resolve(), force=args.force)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
