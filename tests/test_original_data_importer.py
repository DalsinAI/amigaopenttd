import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IMPORTER = ROOT / "scripts/import_original_ttd.py"
WINDOWS_GRAPHICS = ("trg1r.grf", "trgcr.grf", "trghr.grf", "trgir.grf", "trgtr.grf")


class OriginalDataImporterTests(unittest.TestCase):
    def run_importer(self, *arguments):
        return subprocess.run(
            [sys.executable, str(IMPORTER), *map(str, arguments)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def test_imports_complete_windows_set_case_insensitively(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "TTD"
            music = source / "GM"
            destination = root / "baseset"
            music.mkdir(parents=True)
            for name in WINDOWS_GRAPHICS:
                (source / name.upper()).write_bytes((name + "\n").encode())
            (source / "SAMPLE.CAT").write_bytes(b"sound")
            for index in range(22):
                (music / f"GM_TT{index:02d}.GM").write_bytes(f"music-{index}".encode())

            result = self.run_importer(source, "--destination", destination)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(report["variants"], {
                "graphics": "windows", "music": "windows", "sound": "original"
            })
            self.assertEqual(len(report["files"]), 28)
            self.assertTrue((destination / "trg1r.grf").is_file())
            self.assertTrue((destination / "sample.cat").is_file())
            self.assertTrue((destination / "gm_tt21.gm").is_file())

    def test_rejects_incomplete_graphics_set(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "TTD"
            source.mkdir()
            (source / "trg1r.grf").write_bytes(b"partial")
            result = self.run_importer(
                source, "--destination", root / "baseset", "--components", "graphics"
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("no complete original graphics set", result.stderr)

    def test_tto_music_is_renamed_without_modifying_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "TTO"
            destination = root / "baseset"
            source.mkdir()
            original = source / "GM.CAT"
            original.write_bytes(b"tto-music")
            result = self.run_importer(
                source,
                "--destination", destination,
                "--components", "music",
                "--music-format", "tto",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((destination / "gm-tto.cat").read_bytes(), b"tto-music")
            self.assertEqual(original.read_bytes(), b"tto-music")


if __name__ == "__main__":
    unittest.main()
