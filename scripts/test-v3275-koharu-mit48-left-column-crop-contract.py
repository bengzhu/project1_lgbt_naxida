#!/usr/bin/env python3
"""Static contract for the v3.275 Koharu left-column crop recovery gate."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class KoharuMit48LeftColumnCropContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.smoke = read("scripts/run-koharu-mit48px-cloud-smoke.sh")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_crop_uses_measured_glyph_envelope(self) -> None:
        self.assertIn(
            '("left-column-c", (388, 86, 452, 448))',
            self.smoke,
        )
        self.assertNotIn(
            '("left-column-c", (405, 86, 491, 448))',
            self.smoke,
        )
        self.assertIn("Connected-component bounds for 今度こそ", self.smoke)

    def test_quality_gate_requires_complete_seven_crop_recovery(self) -> None:
        for marker in [
            "len(accepted) < 7",
            'left_column_c["text"] != "今度こそ"',
            'left_column_c["confidence"] < 0.55',
            '"minimumAcceptedJapanesePredictions": 7',
            '"leftColumnCText": "今度こそ"',
        ]:
            self.assertIn(marker, self.smoke)

    def test_ci_route_and_version_are_current(self) -> None:
        current = "scripts/test-v3275-koharu-mit48-left-column-crop-contract.py"
        self.assertIn(
            f"if grep -Fx '{current}'",
            self.workflow,
        )
        self.assertIn(f"python3 -B {current}", self.workflow)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project),
            ["3.325", "3.325"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
