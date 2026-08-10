#!/usr/bin/env python3
"""Contract for retrying weak line-quad Manga OCR with Koharu's bbox crop."""

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


class JapaneseQuadBBoxFallbackContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.runtime = read(
            "scripts/test-v3238-image-japanese-quad-bbox-fallback-runtime.sh"
        )
        self.harness = read(
            "scripts/fixtures/v3238-manga-ocr-quad-bbox-fallback-runtime-harness.swift"
        )
        self.crop_images = braced_body(
            self.service,
            "private static func cropImages(",
        )
        self.retry = braced_body(
            self.service,
            "private static func shouldRetryBoundingBox(",
        )
        self.preference = braced_body(
            self.service,
            "private static func preferredRecognition(",
        )

    def test_line_quad_retains_koharu_bbox_as_content_fallback(self) -> None:
        for marker in [
            "var boundingBoxFallbackCrop: CGImage?",
            "let boundingBoxCrop = cropImage(image, normalizedRect: request.cropRect)",
            "let perspectiveCrop = perspectiveCorrectedCrop(image, quad: cropQuad)",
            "boundingBoxFallbackCrop: boundingBoxCrop",
            "boundingBoxFallbackCrop: nil",
        ]:
            self.assertIn(marker, self.service)
        self.assertIn("CIPerspectiveCorrection", self.service)

    def test_only_weak_quad_results_pay_for_bbox_retry(self) -> None:
        for marker in [
            "guard let recognition else { return true }",
            "!isPreferredRecognition(recognition)",
        ]:
            self.assertIn(marker, self.retry)
        self.assertIn("private static let preferredCropConfidence: Float = 0.55", self.service)
        self.assertIn("private static let preferredJapaneseScriptDensity = 0.5", self.service)
        for marker in [
            "recognition.confidence.isFinite",
            "recognition.confidence >= preferredCropConfidence",
            "containsJapaneseLetter(recognition.text)",
            "japaneseScriptDensity(in: recognition.text)",
            ">= preferredJapaneseScriptDensity",
        ]:
            self.assertIn(marker, self.service)
        self.assertIn("Self.shouldRetryBoundingBox(after: primaryRecognitions[index])", self.service)
        self.assertIn("let fallbackCrops = fallbackIndexes.compactMap", self.service)

    def test_primary_and_bbox_retries_keep_batch_and_isolated_fallback(self) -> None:
        recognize = braced_body(self.service, "private func recognizeCrops(")
        for marker in [
            "runtime.supportsBatchInference",
            "let recognitions = try runtime.recognizeBatch(crops)",
            "recognitions.append(try runtime.recognize(crop))",
            "catch is CancellationError",
            "throw CancellationError()",
            "try Task.checkCancellation()",
            "recognitions.append(nil)",
        ]:
            self.assertIn(marker, recognize)
        self.assertGreaterEqual(self.service.count("try recognizeCrops("), 2)

    def test_preference_never_promotes_non_japanese_or_nonfinite_output(self) -> None:
        for marker in [
            "case (false, false):",
            "case (true, false):",
            "case (false, true):",
            "recognitionQualityRank(primary)",
            "recognitionQualityRank(boundingBoxFallback)",
            "finiteConfidence(primary.confidence)",
            "finiteConfidence(boundingBoxFallback.confidence)",
            "japaneseLetterCount(boundingBoxFallback.text)",
        ]:
            self.assertIn(marker, self.preference)
        self.assertIn("confidence.isFinite ? confidence : -.infinity", self.service)

    def test_real_runtime_forces_blank_quad_and_recovers_detector_bbox(self) -> None:
        for marker in [
            "ComicTextBubbleDetectorService.shared.detectTextRegions",
            "let blankQuad = ImageOCRLayoutQuad",
            "cropQuad: blankQuad",
            "blankResults=\\(blankResults.count)",
            "blankConfidence=\\(result.confidence)",
            "fallbackResults=\\(fallbackResults.count)",
        ]:
            self.assertIn(marker, self.harness)
        for marker in [
            "blankResults=1",
            "blank quad must produce a weak primary result",
            "fallbackResults=1",
            "detector bbox retry did not replace the weak quad text",
            "bbox retry did not recover Japanese Manga OCR text",
        ]:
            self.assertIn(marker, self.runtime)
        self.assertIn(
            "bash scripts/test-v3238-image-japanese-quad-bbox-fallback-runtime.sh",
            self.workflow,
        )

    def test_version_and_ci_route_follow_v3237(self) -> None:
        previous = "python3 -B scripts/test-v3237-image-japanese-detector-cancellation-contract.py"
        current = "python3 -B scripts/test-v3238-image-japanese-quad-bbox-fallback-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3238-image-japanese-quad-bbox-fallback-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 238) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.237;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
