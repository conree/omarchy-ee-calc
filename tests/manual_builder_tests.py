#!/usr/bin/env python3
"""Check version rejection and the low-ink print artifact without a browser."""
import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("manual_builder", ROOT / "docs/build_manual_pdf.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class ManualVersionTests(unittest.TestCase):
    def render(self, declared):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            source, manifest, output = root / "manual.md", root / "manifest.json", root / "manual.pdf"
            source.write_text(f"# EE Calc user manual\n\nVersion {declared}\n\n![Example](unavailable.png)\n")
            manifest.write_text(json.dumps({"version": "0.3.2"}))
            with patch.object(builder, "SOURCE", source), patch.object(builder, "MANIFEST", manifest), \
                 patch.object(builder, "OUTPUT", output), patch.object(sys, "argv", ["builder", "--html-only"]):
                builder.main()
            return output.with_suffix(".html").read_text()

    def test_candidate_and_sentence_version(self):
        for declared in ["0.3.2 (local candidate)", "0.3.2."]:
            page = self.render(declared)
            self.assertNotIn("<img", page)
            self.assertIn("Illustration in the electronic manual", page)
            self.assertIn("v0.3.2", page)

    def test_mismatched_version_is_rejected(self):
        for declared in ["0.3.20", "0.3.3", "0.3.2.1", "0.3.2-beta.1"]:
            with self.assertRaises(SystemExit):
                self.render(declared)


if __name__ == "__main__":
    unittest.main()
