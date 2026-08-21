#!/usr/bin/env python3
"""Static contract for the v3.270 Koharu vertical-crop quality boundary."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class KoharuMit48CloudOrientationQualityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.smoke = read("scripts/run-koharu-mit48px-cloud-smoke.sh")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_pillow_rotation_matches_koharu_vertical_orientation(self) -> None:
        for marker in [
            "image-rs rotate270",
            "rotate(90, expand=True)",
            '("compact-niko", (532, 1050, 578, 1142))',
            '"orientation": "Pillow rotate90 equivalent to Koharu image-rs rotate270"',
        ]:
            self.assertIn(marker, self.smoke)
        self.assertNotIn("rotate(270, expand=True)", self.smoke)

    def test_quality_evidence_keeps_finite_japanese_density_gate(self) -> None:
        for marker in [
            "math.isfinite(confidence)",
            "density >= 0.5",
            "acceptedJapanesePredictions",
            "len(accepted) < 7",
            'compact["text"] != "ニコッ"',
            'compact["confidence"] < 0.55',
            'left_column_c["text"] != "今度こそ"',
            'left_column_c["confidence"] < 0.55',
            '"compactNikoText": "ニコッ"',
            '"leftColumnCText": "今度こそ"',
            '"qualityClaim": "cloud reference smoke only; no general OCR quality claim"',
        ]:
            self.assertIn(marker, self.smoke)

    def test_ci_route_and_version_are_current(self) -> None:
        current = "python3 -B scripts/test-v3270-koharu-mit48-cloud-orientation-quality-contract.py"
        self.assertIn(current, self.workflow)
        self.assertIn(
            "if grep -Fx 'scripts/test-v3270-koharu-mit48-cloud-orientation-quality-contract.py'",
            self.workflow,
        )
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project),
            ["3.310", "3.310"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
