#!/usr/bin/env python3
"""Static contract for the v3.290 rectangular overlay render preflight."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing function signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1 : index]
    raise AssertionError(f"unterminated function body: {signature}")


class ImageTranslationRenderSafetyContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.model = read("AITRANS/Models/ImageTranslationRenderSafety.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.view = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.evaluator = read(
            "scripts/fixtures/v3290-image-translation-render-safety-evaluator.swift"
        )
        cls.runtime = read("scripts/test-v3290-image-translation-render-safety-runtime.sh")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )

    def test_report_is_explicitly_report_only_and_ground_truth_free(self) -> None:
        for marker in (
            "struct ImageTranslationRenderSafety",
            "static func analyze(",
            "enum IssueCode",
            "case invalidGeometry",
            "case adjacentOverlayClipped",
            "case adjacentOverlayCollidesWithOtherBlock",
            "var reportOnly: Bool",
            "groundTruthUsedForDecision: Bool",
            "changesOCR: Bool",
            "changesTranslation: Bool",
            "changesOverlayRendering: Bool",
            "reportOnly: true",
            "groundTruthUsedForDecision: false",
            "changesOCR: false",
            "changesTranslation: false",
            "changesOverlayRendering: false",
            "\\(issues.count)",
            "\\(unsafeCount)",
            "\\(warningCount)",
        ):
            self.assertIn(marker, self.model)

    def test_preflight_covers_geometry_text_clipping_and_collision_cases(self) -> None:
        body = function_body(self.model, "static func analyze(")
        for marker in (
            "normalizedToUnit()",
            ".invalidGeometry",
            ".emptyText",
            "adjacentOverlay(for:",
            ".adjacentOverlayClipped",
            ".adjacentOverlayOverlapsSource",
            ".sourceBlocksOverlap",
            ".adjacentOverlayCollidesWithOtherBlock",
            "overlapRatio(",
            "verdict: issues.isEmpty ? .clear : .needsReview",
        ):
            self.assertIn(marker, body)
        self.assertIn("sourceBlocksOverlap", self.model)
        self.assertIn("adjacentOverlayCollidesWithOtherBlock", self.model)

    def test_store_exposes_ephemeral_report_without_gating_main_flow(self) -> None:
        property_body = function_body(
            self.store,
            "var imageTranslationRenderSafetyReport: ImageTranslationRenderSafety.Report?",
        )
        for marker in (
            "imageTranslationState == .translated",
            "ImageTranslationRenderSafety.analyze(",
            "blocks: imageTranslationBlocks",
            "overlayMode: imageOverlayMode",
        ):
            self.assertIn(marker, property_body)
        renderer = function_body(
            self.store,
            "nonisolated private static func renderImageTranslationOverlay(",
        )
        self.assertNotIn("imageTranslationRenderSafetyReport", renderer)
        for forbidden in (
            "recognizeTextBlocks(",
            "generateWithSelectedEngine(",
            "translate(",
            "imageTranslationBlocks =",
        ):
            self.assertNotIn(forbidden, property_body)

    def test_ui_warning_is_accessible_and_preserves_current_renderer(self) -> None:
        for marker in (
            "store.imageTranslationRenderSafetyReport",
            "renderSafety.requiresAttention",
            "AppStatusRow(",
            "renderSafety.title",
            "renderSafety.detail",
            "只读的矩形 overlay 预检",
            "不会改变原图、OCR、翻译或导出算法",
        ):
            self.assertIn(marker, self.view)
        self.assertNotIn("BubbleMask", self.view)
        self.assertNotIn("SegmentMask", self.view)

    def test_cloud_evaluator_covers_clear_invalid_edge_and_collision_cases(self) -> None:
        for marker in (
            "ImageTranslationRenderSafety.analyze",
            "overlayMode: .replace",
            "overlayMode: .adjacent",
            "invalidGeometry",
            "adjacentOverlayClipped",
            "adjacentOverlayCollidesWithOtherBlock",
            "groundTruthUsedForDecision",
            "renderSafetyEvaluator=passed",
        ):
            self.assertIn(marker, self.evaluator)
        for marker in (
            "xcrun swiftc",
            "v3290-image-translation-render-safety-evaluator.swift",
            "ImageTranslationRenderSafety.swift",
            "ImageOCRProvenance.swift",
            "ImageOCRLayoutEngine.swift",
            "TranslationContextQuality.swift",
            "TranscriptModels.swift",
        ):
            self.assertIn(marker, self.runtime)

    def test_project_workflow_route_and_version_are_explicit(self) -> None:
        for marker in (
            "ImageTranslationRenderSafety.swift in Sources",
            "path = ImageTranslationRenderSafety.swift;",
            "scripts/test-v3290-image-translation-render-safety-contract.py",
            "scripts/test-v3290-image-translation-render-safety-runtime.sh",
            "v3.290",
            "矩形 overlay 渲染安全预检",
        ):
            self.assertIn(marker, self.project + self.workflow + self.route)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.375", "3.375"],
        )

    def test_static_contract_has_no_process_entry(self) -> None:
        contract = read("scripts/test-v3290-image-translation-render-safety-contract.py")
        for source in (contract, self.model):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
