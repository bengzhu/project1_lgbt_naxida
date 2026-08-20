#!/usr/bin/env python3
"""Contract for rejecting high-confidence noise from weak detector owners."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def braced_body(source: str, marker: str) -> str:
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace : index + 1]
    raise AssertionError(f"unterminated body for {marker}")


class ImageJapaneseDetectorConfidenceGateContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manga = read("AITRANS/Services/MangaOCRService.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.view = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_manga_request_and_result_preserve_detector_provenance(self) -> None:
        for marker in [
            "var detectorConfidence: Float?",
            "detectorConfidence: Float? = nil",
            "detectorConfidence: request.detectorConfidence",
        ]:
            self.assertIn(marker, self.manga)

    def test_only_comic_detector_regions_supply_owner_confidence(self) -> None:
        self.assertIn(
            "detectorConfidence: Self.detectorConfidenceForMangaOCR(",
            self.vision,
        )
        helper = braced_body(
            self.vision,
            "private static func detectorConfidenceForMangaOCR(\n",
        )
        self.assertIn("guard case .comicTextBubble = region.detector else { return nil }", helper)
        self.assertIn("return region.detectorConfidence", helper)

    def test_owner_gate_requires_both_model_and_detector_evidence(self) -> None:
        gate = braced_body(
            self.vision,
            "private static func isReliableJapaneseMangaOCRResult(\n",
        )
        for marker in [
            "confidence.isFinite",
            "confidence >= 0.55",
            "japaneseScriptDensity(in: result.text) >= 0.5",
            "if let detectorConfidence = result.detectorConfidence",
            "detectorScore.isFinite",
            "detectorScore >= 0.55",
        ]:
            self.assertIn(marker, gate)
        self.assertLess(
            gate.index("detectorScore.isFinite"),
            gate.index("return true"),
        )

    def test_navigation_cancels_stale_rerecognition_focus_intent(self) -> None:
        for marker in [
            "@State private var imageTranslationRerecognitionFocusIntentBlockID: UUID?",
            "imageTranslationRerecognitionFocusIntentBlockID = blockID",
            "imageTranslationRerecognitionFocusIntentBlockID == blockID",
            "private func invalidateImageTranslationRerecognitionFocusIntent()",
            "invalidateImageTranslationRerecognitionFocusIntent()",
        ]:
            self.assertIn(marker, self.view)
        completion = braced_body(
            self.view,
            "private func focusImageTranslationRerecognitionCompletionIfNeeded(\n",
        )
        self.assertIn(
            "imageTranslationRerecognitionFocusIntentBlockID == blockID",
            completion,
        )
        failure = braced_body(
            self.view,
            "private func focusImageTranslationRerecognitionFailureIfNeeded(",
        )
        self.assertIn(
            "imageTranslationRerecognitionFocusIntentBlockID != nil",
            failure,
        )
        self.assertGreaterEqual(
            self.view.count("invalidateImageTranslationRerecognitionFocusIntent()"),
            5,
        )

    def test_ci_routes_v3236_and_current_contract(self) -> None:
        self.assertIn(
            "# if grep -Fx 'scripts/test-v3236-image-japanese-koharu-tolerant-batch-translation-contract.py'",
            self.workflow,
        )
        self.assertIn(
            "if grep -Fx 'scripts/test-v3236-image-japanese-koharu-tolerant-batch-translation-contract.py'",
            self.workflow,
        )
        current = "scripts/test-v3258-image-japanese-detector-confidence-gate-contract.py"
        self.assertIn(f"# if grep -Fx '{current}'", self.workflow)
        self.assertIn(f"if grep -Fx '{current}'", self.workflow)
        self.assertIn(f"python3 -B {current}", self.workflow)
        self.assertIn("bash scripts/test-v3214-image-japanese-manga-ocr-runtime.sh", self.workflow)
        self.assertIn("test/jap.jpg", read("scripts/test-v3214-image-japanese-manga-ocr-runtime.sh"))

    def test_project_version_is_v3258(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)
        self.assertEqual(versions, ["3.295", "3.295"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
