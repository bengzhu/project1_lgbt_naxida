#!/usr/bin/env python3
"""Contract for keeping Koharu's detector bbox primary in Manga OCR."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


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
    raise AssertionError(f"unclosed body for {marker}")


class JapaneseMangaOCRBBoxPrimaryContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.runtime = read(
            "scripts/test-v3239-image-japanese-manga-ocr-bbox-primary-runtime.sh"
        )
        self.harness = read(
            "scripts/fixtures/v3239-manga-ocr-bbox-primary-runtime-harness.swift"
        )
        self.crop_images = braced_body(
            self.service,
            "private static func cropImages(",
        )
        self.retry = braced_body(
            self.service,
            "private static func shouldRetryLineQuad(",
        )
        self.preference = braced_body(
            self.service,
            "private static func preferredRecognition(",
        )

    def test_koharu_bbox_is_primary_and_quad_is_optional_fallback(self) -> None:
        for marker in [
            "var primaryBoundingBoxCrop: CGImage",
            "var lineQuadFallbackCrop: CGImage?",
            "let boundingBoxCrop = cropImage(image, normalizedRect: request.cropRect)",
            "let perspectiveCrop = request.cropQuad.flatMap",
            "primaryBoundingBoxCrop: boundingBoxCrop",
            "lineQuadFallbackCrop: perspectiveCrop",
            "guard let perspectiveCrop else { return nil }",
        ]:
            self.assertIn(marker, self.service)
        self.assertIn("chunk.map(\\.primaryBoundingBoxCrop)", self.service)
        self.assertIn("chunk[index].lineQuadFallbackCrop != nil", self.service)
        self.assertIn("CIPerspectiveCorrection", self.service)

    def test_only_weak_bbox_results_pay_for_line_quad(self) -> None:
        self.assertIn("guard let recognition else { return true }", self.retry)
        self.assertIn("!isPreferredRecognition(recognition)", self.retry)
        self.assertIn(
            "Self.shouldRetryLineQuad(after: primaryRecognitions[index])",
            self.service,
        )
        for marker in [
            "recognition.confidence.isFinite",
            "recognition.confidence >= preferredCropConfidence",
            "containsJapaneseLetter(recognition.text)",
            "japaneseScriptDensity(in: recognition.text)",
            ">= preferredJapaneseScriptDensity",
        ]:
            self.assertIn(marker, self.service)

    def test_fallback_selection_keeps_existing_quality_order(self) -> None:
        for marker in [
            "recognitionQualityRank(boundingBox)",
            "recognitionQualityRank(lineQuadFallback)",
            "finiteConfidence(boundingBox.confidence)",
            "finiteConfidence(lineQuadFallback.confidence)",
            "japaneseLetterCount(lineQuadFallback.text)",
            "japaneseLetterCount(boundingBox.text)",
        ]:
            self.assertIn(marker, self.preference)

    def test_runtime_rejects_reliable_neighbor_quad_ownership(self) -> None:
        for marker in [
            "ComicTextBubbleDetectorService.shared.detectTextRegions",
            "let distractorQuad = quad(for: distractorCrop)",
            "cropRect: targetCrop",
            "cropQuad: distractorQuad",
            "adversarialText=\\(adversarialResult.text)",
        ]:
            self.assertIn(marker, self.harness)
        for marker in [
            "misplaced reliable quad replaced detector bbox owner",
            "neighboring quad text leaked into detector owner",
            '"爆乳" not in target',
            '"生意気" not in distractor',
        ]:
            self.assertIn(marker, self.runtime)
        self.assertIn(
            "bash scripts/test-v3239-image-japanese-manga-ocr-bbox-primary-runtime.sh",
            self.workflow,
        )

    def test_version_and_ci_route_follow_v3238(self) -> None:
        previous = "python3 -B scripts/test-v3238-image-japanese-quad-bbox-fallback-contract.py"
        current = "python3 -B scripts/test-v3239-image-japanese-manga-ocr-bbox-primary-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3239-image-japanese-manga-ocr-bbox-primary-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 239) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.238;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
