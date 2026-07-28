#!/usr/bin/env python3
"""Contracts for v3.1 non-destructive OCR review filtering."""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def braced_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unterminated body: {signature}")


class ImageOCRReviewFilterContractTests(unittest.TestCase):
    def test_executable_filter_evaluator_uses_product_models(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v310-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v310-image-ocr-review-filter"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                    "AITRANS/Models/ImageOCRResultSummary.swift",
                    "AITRANS/Models/ImageOCRReviewFilter.swift",
                    "scripts/test-v310-image-ocr-review-filter-evaluator.swift",
                    "-o", str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run([str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertIn("v3.1 image OCR review filter evaluator passed", result.stdout)

    def test_product_model_owns_the_review_union(self) -> None:
        summary = read("AITRANS/Models/ImageOCRResultSummary.swift")
        review_filter = read("AITRANS/Models/ImageOCRReviewFilter.swift")
        self.assertIn("var reviewRequiredBlockCount: Int", summary)
        self.assertIn("Self.requiresReview($0, lowConfidenceThreshold: lowConfidenceThreshold)", summary)
        self.assertIn("static func hasLowConfidence", summary)
        self.assertIn("static func hasUnknownDirection", summary)
        self.assertIn(
            "hasLowConfidence(block, lowConfidenceThreshold: lowConfidenceThreshold) || hasUnknownDirection(block)",
            summary,
        )
        self.assertIn("blocks.filter { ImageOCRResultSummary.requiresReview($0) }", review_filter)

    def test_filter_is_local_presentation_state(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.assertIn("@State private var reviewFilter: ImageOCRReviewFilter = .all", view)
        self.assertNotIn("@Published var imageOCRReviewFilter", store)
        self.assertNotIn("ImageOCRReviewFilter", store)
        self.assertIn('Picker("识别结果筛选", selection: $reviewFilter)', view)
        self.assertIn("reviewFilter.blocks(from: store.imageTranslationBlocks)", view)

    def test_filter_never_changes_preview_or_product_blocks(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        inspector = braced_body(view, "private var inspector: some View")
        preview = braced_body(view, "private struct ImageTranslationPreview: View")
        rerender = braced_body(store, "private func rerenderImageTranslationExport()")

        self.assertIn("ForEach(visibleImageTranslationBlocks)", inspector)
        self.assertIn('title: "无需复查"', inspector)
        self.assertIn('detail: "当前结果没有低置信或方向待定文字块。"', inspector)
        self.assertIn("ForEach(store.imageTranslationBlocks)", preview)
        self.assertNotIn("visibleImageTranslationBlocks", preview)
        self.assertIn("let blocks = imageTranslationBlocks", rerender)
        self.assertIn("blocks: blocks", rerender)
        self.assertNotIn("ImageOCRReviewFilter", store)

    def test_review_reasons_are_visible_without_color_only_signaling(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.assertIn("ImageOCRResultSummary.hasLowConfidence(block)", view)
        self.assertIn('Label("低置信", systemImage: "exclamationmark.triangle.fill")', view)
        self.assertIn("ImageOCRResultSummary.hasUnknownDirection(block)", view)
        self.assertIn('Label("方向待定", systemImage: "questionmark.diamond.fill")', view)

    def test_project_and_ci_run_v31_after_v30(self) -> None:
        project = read("AITRANS.xcodeproj/project.pbxproj")
        workflow = read(".github/workflows/ci-results.yml")
        self.assertIn("ImageOCRReviewFilter.swift in Sources", project)
        self.assertLess(
            workflow.index("scripts/test-v300-image-ocr-rerun-contract.py"),
            workflow.index("scripts/test-v310-image-ocr-review-filter-contract.py"),
        )
        self.assertIn("310-image-ocr-review-filter", workflow)
        self.assertIn("ImageOCR(ResultSummary|ReviewFilter)", workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
