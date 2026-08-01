#!/usr/bin/env python3
"""Static contracts for v3.48 image preview accessibility context."""

from pathlib import Path
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
                return source[brace:index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImagePreviewContextAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_ready_preview_has_context_and_hides_duplicate_background(self) -> None:
        preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        ready = preview[:preview.index("} else if store.imageTranslationData != nil")]
        self.assertIn(".accessibilityHidden(true)", ready)
        self.assertIn(".accessibilityElement(children: .contain)", ready)
        self.assertIn('.accessibilityLabel("图片翻译预览")', ready)
        self.assertIn(".accessibilityValue(previewAccessibilityValue)", ready)
        self.assertIn(".accessibilityHint(previewAccessibilityHint)", ready)

    def test_preview_value_reports_blocks_review_and_selection(self) -> None:
        preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        value = braced_body(preview, "private var previewAccessibilityValue: String")
        self.assertIn("当前没有识别到文字块", value)
        self.assertIn("store.imageTranslationBlocks", value)
        self.assertIn("ImageOCRResultSummary.requiresReview", value)
        self.assertIn("reviewedBlockIDs.contains", value)
        self.assertIn(r"识别到 \(blocks.count) 个文字块", value)
        self.assertIn(r"待复查 \(max(0, reviewTotal - reviewCompleted)) 个", value)
        self.assertIn(r"当前定位 \(positionText)", value)
        self.assertIn("尚未定位文字块", value)

    def test_preview_hint_reflects_available_operations(self) -> None:
        preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        hint = braced_body(preview, "private var previewAccessibilityHint: String")
        self.assertIn("当前没有可定位的 OCR 文字块", hint)
        self.assertIn("点按文字块可定位并打开局部放大", hint)
        self.assertIn("var unavailableDetails: [String] = []", hint)
        self.assertIn("if !canEdit", hint)
        self.assertIn("modificationUnavailableHint", hint)
        self.assertIn("if !canReview", hint)
        self.assertIn("reviewUnavailableHint", hint)
        self.assertIn("当前图片已完成翻译，可修正文字或更新复查进度", hint)
        self.assertIn("unavailableDetails.joined(separator: \" \")", hint)

    def test_version_and_ci_route_follow_v347(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.48;", self.project)
        old = "python3 -B scripts/test-v347-image-command-accessibility-contract.py"
        new = "python3 -B scripts/test-v348-image-preview-context-accessibility-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75|76|77|78|79)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
