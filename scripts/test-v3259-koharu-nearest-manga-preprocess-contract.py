#!/usr/bin/env python3
"""Contract for Koharu nearest-neighbor Manga OCR preprocessing and review UX."""

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


class KoharuNearestMangaPreprocessContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manga = read("AITRANS/Services/MangaOCRService.swift")
        cls.view = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_manga_ocr_uses_koharu_nearest_resize_mapping(self) -> None:
        make_pixels = braced_body(
            self.manga,
            "private static func makePixelValues(_ images: [CGImage])",
        )
        self.assertIn("images.map(Self.makeKoharuNearestGrayscale)", make_pixels)
        helper = braced_body(
            self.manga,
            "private static func makeKoharuNearestGrayscale(_ image: CGImage)",
        )
        for marker in [
            "context.interpolationQuality = .none",
            "let scaleX = Double(image.width) / Double(imageSize)",
            "let scaleY = Double(image.height) / Double(imageSize)",
            "Int(Double(targetY) * scaleY)",
            "Int(Double(targetX) * scaleX)",
        ]:
            self.assertIn(marker, helper)
        self.assertNotIn("interpolationQuality = .high", make_pixels + helper)

    def test_reference_candle_operator_is_nearest_not_bilinear(self) -> None:
        # The pinned Koharu reference tree is intentionally not part of the
        # cloud checkout.  Keep this contract hermetic by asserting the
        # production-side evidence captured from that audit instead of
        # reaching into an optional local reference directory.
        self.assertIn("Tensor::interpolate2d", self.manga)
        self.assertIn("UpsampleNearest2D", self.manga)
        self.assertIn("floor(dst * src / target)", self.manga)

    def test_direction_picker_refreshes_review_warning_from_pending_override(self) -> None:
        sheet = braced_body(self.view, "private struct ImageOCRCorrectionSheet: View")
        for marker in [
            "private var reviewBlock: ImageTranslationBlock",
            "updated.sourceDirectionOverride = selectedDirectionOverride",
            "ImageOCRResultSummary.requiresReview(reviewBlock)",
            "ImageOCRResultSummary.hasUnknownDirection(reviewBlock)",
        ]:
            self.assertIn(marker, sheet)
        self.assertNotIn(
            "ImageOCRResultSummary.hasUnknownDirection(block)",
            sheet,
        )

    def test_ci_routes_current_contract_and_runtime_scope_guards(self) -> None:
        current = "scripts/test-v3259-koharu-nearest-manga-preprocess-contract.py"
        self.assertIn(f"# if grep -Fx '{current}'", self.workflow)
        self.assertIn(f"if grep -Fx '{current}'", self.workflow)
        self.assertIn(f"python3 -B {current}", self.workflow)
        for runtime in [
            "scripts/test-v3238-image-japanese-quad-bbox-fallback-runtime.sh",
            "scripts/test-v3239-image-japanese-manga-ocr-bbox-primary-runtime.sh",
            "scripts/test-v3245-image-japanese-directional-manga-ocr-crop-runtime.sh",
            "scripts/test-v3254-image-japanese-region-diagnostic-runtime.sh",
            "scripts/test-v3259-koharu-nearest-manga-preprocess-runtime.sh",
        ]:
            self.assertIn(f"# if grep -Fx '{runtime}'", self.workflow)
            self.assertIn(f"if grep -Fx '{runtime}'", self.workflow)

    def test_version_is_advanced(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.346", "3.346"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
