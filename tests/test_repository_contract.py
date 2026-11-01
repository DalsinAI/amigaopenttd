import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class RepositoryContractTests(unittest.TestCase):
    def test_pinned_source_and_amiga_build_lane(self):
        data = json.loads((ROOT / "gameports/catalog.json").read_text())
        self.assertEqual(set(data["ports"]), {"openttd"})
        self.assertRegex(data["ports"]["openttd"]["source"]["commit"], r"^[0-9a-f]{40}$")
        self.assertEqual(set(data["runtimeDependencies"]), {"opengfx", "opensfx", "openmsx"})
        for source in data["runtimeDependencies"].values():
            self.assertRegex(source["commit"], r"^[0-9a-f]{40}$")
            self.assertTrue(source["url"].startswith("https://github.com/OpenTTD/"))
        self.assertEqual(set(data["runtimePackages"]), {"opengfx", "opensfx", "openmsx"})
        for package in data["runtimePackages"].values():
            self.assertRegex(package["sha256"], r"^[0-9a-f]{64}$")
            self.assertTrue(package["url"].startswith("https://cdn.openttd.org/"))
        self.assertIn("-m68040", (ROOT / "toolchain/amigaos3-opengpu.cmake").read_text())
        patch = (ROOT / "patches/0001-amigaos3-cmake-platform.patch").read_text()
        self.assertIn("PROGDIR:", patch)
        self.assertTrue((ROOT / "scripts/import_original_ttd.py").is_file())
        self.assertTrue((ROOT / "scripts/stage_open_basesets.py").is_file())

if __name__ == "__main__": unittest.main()
