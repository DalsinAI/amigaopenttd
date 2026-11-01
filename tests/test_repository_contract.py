import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class RepositoryContractTests(unittest.TestCase):
    def test_pinned_source_and_amiga_build_lane(self):
        data = json.loads((ROOT / "gameports/catalog.json").read_text())
        self.assertEqual(set(data["ports"]), {"openttd"})
        self.assertRegex(data["ports"]["openttd"]["source"]["commit"], r"^[0-9a-f]{40}$")
        self.assertIn("-m68040", (ROOT / "toolchain/amigaos3-opengpu.cmake").read_text())
        patch = (ROOT / "patches/0001-amigaos3-cmake-platform.patch").read_text()
        self.assertIn("PROGDIR:", patch)

if __name__ == "__main__": unittest.main()
