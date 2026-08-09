#!/usr/bin/env python3
"""Contract for raw Japanese crop rereads aligned with Koharu Manga OCR."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class JapaneseKoharuRawCropRecognitionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_request_exposes_a_bounded_language_correction_switch(self) -> None:
        self.assertIn("usesLanguageCorrection: Bool = true", self.vision)
        self.assertIn("request.usesLanguageCorrection = true", self.vision)
        self.assertIn("if !usesLanguageCorrection", self.vision)
        self.assertIn("request.usesLanguageCorrection = false", self.vision)

    def test_japanese_crop_helper_uses_raw_model_like_decoding(self) -> None:
        helper_start = self.vision.index("private static func recognizeJapaneseCropPass(")
        helper = self.vision[helper_start : self.vision.index("private static func oppositeJapaneseOrientation", helper_start)]
        self.assertIn("postProcessJapaneseText: true", helper)
        self.assertIn("usesLanguageCorrection: false", helper)
        self.assertIn("automaticallyDetectsLanguage: false", helper)

    def test_perspective_line_crop_keeps_the_same_raw_boundary(self) -> None:
        helper_start = self.vision.index("private static func recognizeJapanesePerspectiveLineCrop(")
        helper = self.vision[helper_start : self.vision.index("private static func orderedJapanesePerspectiveLineObservations", helper_start)]
        self.assertIn("postProcessJapaneseText: true", helper)
        self.assertIn("usesLanguageCorrection: false", helper)
        self.assertIn("observationRole: .verticalLine", helper)

    def test_page_reconnaissance_and_normal_language_paths_keep_correction(self) -> None:
        request_body = self.vision[self.vision.index("private static func recognizeObservations(") : self.vision.index("/// Mirrors Koharu Manga OCR", self.vision.index("private static func recognizeObservations("))]
        self.assertIn("usesLanguageCorrection: Bool = true", request_body)
        page_branch = self.vision[: self.vision.index("private static func recognizeObservations(")]
        self.assertNotIn("usesLanguageCorrection: false", page_branch)

    def test_scope_stays_out_of_models_probe_and_active_artifacts(self) -> None:
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "VNCoreMLModel",
            "MLModel",
            "metrics/",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_fixture_version_and_ci_route(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, v.split("."))) >= (3, 212) for v in versions))
        self.assertNotIn("MARKETING_VERSION = 3.211;", self.project)

        previous = "python3 -B scripts/test-v3211-image-japanese-vertical-language-gate-contract.py"
        current = "python3 -B scripts/test-v3212-image-japanese-koharu-raw-crop-recognition-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3212-image-japanese-koharu-raw-crop-recognition-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
