#!/usr/bin/env python3
"""Contract for Japanese-only language gating on vertical crop rereads."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class JapaneseVerticalLanguageGateContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_page_reconnaissance_keeps_mixed_panel_languages(self) -> None:
        self.assertIn(
            'let japaneseOrientationLanguages = ["ja-JP", "ja", "en-US", "en"]',
            self.vision,
        )

    def test_vertical_rereads_use_japanese_only_languages(self) -> None:
        marker = 'let japaneseVerticalRecognitionLanguages = ["ja-JP", "ja"]'
        self.assertIn(marker, self.vision)
        branch = self.vision[self.vision.index("if sourceLanguage == .japanese {") :]
        crop_call = branch.index("let cropRefinedObservations = Self.recognizeJapaneseVerticalCrops(")
        crop_tail = branch[crop_call : crop_call + 500]
        self.assertIn("recognitionLanguages: japaneseVerticalRecognitionLanguages", crop_tail)
        self.assertNotIn("recognitionLanguages: japaneseOrientationLanguages", crop_tail)

    def test_language_specific_rereads_fail_closed_without_a_supported_profile(self) -> None:
        self.assertIn(
            "else if !automaticallyDetectsLanguage {",
            self.vision,
        )
        language_gate = self.vision[
            self.vision.index("let availableLanguages = recognitionLanguages.filter") :
            self.vision.index("let handler = VNImageRequestHandler", self.vision.index("let availableLanguages = recognitionLanguages.filter"))
        ]
        self.assertIn("return []", language_gate)

    def test_page_orientation_reconnaissance_is_failure_isolated(self) -> None:
        branch = self.vision[self.vision.index("if sourceLanguage == .japanese {") :]
        orientation = branch[: branch.index("let cropRefinedObservations")]
        self.assertIn("guard let rotatedOCRImage = try? Self.rotatedImage", orientation)
        self.assertIn("continue", orientation)
        self.assertIn("observations.append(contentsOf: rotatedObservations)", orientation)

    def test_no_model_or_probe_dependency_is_added(self) -> None:
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "VNCoreMLModel",
            "MLModel",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_fixture_and_version_route(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, v.split("."))) >= (3, 211) for v in versions))
        self.assertNotIn("MARKETING_VERSION = 3.210;", self.project)

    def test_ci_route_follows_v3210(self) -> None:
        previous = "python3 -B scripts/test-v3210-image-translation-block-retry-contract.py"
        current = "python3 -B scripts/test-v3211-image-japanese-vertical-language-gate-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3211-image-japanese-vertical-language-gate-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
