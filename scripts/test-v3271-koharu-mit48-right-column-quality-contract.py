#!/usr/bin/env python3
"""Static contract for v3.271's bounded Koharu right-column crop diagnostic."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class KoharuMit48RightColumnQualityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.smoke = read("scripts/run-koharu-mit48px-cloud-smoke.sh")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_right_column_uses_measured_text_bounds(self) -> None:
        self.assertIn('("right-column-a", (864, 136, 908, 298))', self.smoke)
        self.assertIn('("compact-niko", (532, 1050, 578, 1142))', self.smoke)
        self.assertIn("image-rs rotate270", self.smoke)
        self.assertIn("rotate(90, expand=True)", self.smoke)

    def test_existing_compact_quality_gate_remains_strict(self) -> None:
        for marker in [
            "len(accepted) < 7",
            'compact["text"] != "ニコッ"',
            'compact["confidence"] < 0.55',
            '"compactNikoText": "ニコッ"',
        ]:
            self.assertIn(marker, self.smoke)

    def test_ci_route_and_version_are_current(self) -> None:
        current = "python3 -B scripts/test-v3271-koharu-mit48-right-column-quality-contract.py"
        self.assertIn(current, self.workflow)
        self.assertIn(
            "if grep -Fx 'scripts/test-v3271-koharu-mit48-right-column-quality-contract.py'",
            self.workflow,
        )
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project),
            ["3.350", "3.350"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
