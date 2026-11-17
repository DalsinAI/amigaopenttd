#!/usr/bin/env python3
"""Host checks of the release package's inputs (no compiler needed).

    python3 -B package/tests/test_package.py

- package/VERSION, installer.json's version and the Install script's $VER agree;
- every file package/package.json takes from the repository is there;
- every icon is an OS 3.5 GlowIcon (a DiskObject with a FORM ICON after it);
- the ReadMe template's lines stay within 78 characters once its fields are
  filled with values as long as a real build's;
- the Installer spec names the drawer and the program package.json ships.
MIT, Copyright (c) 2026 AmiCradle Team.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PKG = ROOT / "package"
LONGEST = {"VERSION": 24, "EXECUTABLE_SHA256": 64, "REPOSITORY_COMMIT": 40, "UPSTREAM_COMMIT": 40,
           "COMPILER_RELEASE": 16, "UPSTREAM_VERSION": 12}


class Package(unittest.TestCase):
    def setUp(self):
        self.version = (PKG / "VERSION").read_text().strip()
        self.spec = json.loads((PKG / "package.json").read_text())
        self.inst = json.loads((PKG / "installer.json").read_text())

    def test_versions_agree(self):
        self.assertEqual(self.inst["version"], self.version)
        script = PKG / "installer" / self.inst.get("script", f"Install-{self.inst['drawer']}")
        head = script.read_text(encoding="latin-1").splitlines()[0]
        self.assertTrue(head.startswith(f"; $VER: {script.name} {self.version} ("), head)

    def test_repo_files_exist(self):
        names = [self.spec["drawer_icon"]]
        names += [m["repo"] for m in self.spec["members"] if "repo" in m]
        names += [m["readme"] for m in self.spec["members"] if "readme" in m]
        names += [m["repo"] for m in self.spec.get("root", [])]
        for n in names:
            self.assertTrue((ROOT / n).is_file(), n)

    def test_icons_are_glowicons(self):
        infos = [self.spec["drawer_icon"]] + [m["repo"] for m in self.spec["members"] + self.spec.get("root", [])
                                             if m.get("repo", "").endswith(".info")]
        self.assertGreaterEqual(len(infos), 3)
        for n in infos:
            data = (ROOT / n).read_bytes()
            self.assertEqual(data[:2], b"\xe3\x10", f"{n}: not a DiskObject")
            self.assertIn(b"FORM", data, f"{n}: no OS 3.5 FORM ICON")
            self.assertIn(b"ICONFACE", data, f"{n}: no FACE chunk")

    def test_readme_fits(self):
        for m in self.spec["members"]:
            if "readme" not in m:
                continue
            text = (ROOT / m["readme"]).read_text(encoding="utf-8")
            text.encode("latin-1")
            filled = re.sub(r"@([A-Z0-9_]+)@", lambda g: "x" * LONGEST.get(g.group(1), 40), text)
            long = [i + 1 for i, line in enumerate(filled.splitlines()) if len(line) > 78]
            self.assertEqual(long, [], f"{m['readme']}: lines over 78 characters once filled")

    def test_installer_names_the_package(self):
        self.assertEqual(self.inst["drawer"], self.spec["drawer"])
        self.assertIn(self.inst["program"], [m["name"] for m in self.spec["members"]])
        self.assertIn(f"{self.inst['program']}.info", [m["name"] for m in self.spec["members"]])
        for d in self.inst.get("data", []):
            if "download" in d:
                self.assertRegex(d["download"]["sha256"], r"^[0-9a-f]{64}$")
                self.assertTrue(d["download"]["url"].startswith("https://"))


if __name__ == "__main__":
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
