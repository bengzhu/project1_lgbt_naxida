#!/usr/bin/env python3
"""Static contracts for v3.58 image review-row identity and translation context."""

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


class ImageReviewRowContextAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")

    def test_row_has_stable_identity_value_and_location_hint(self) -> None:
        for marker in [
            ".accessibilityElement(children: .combine)",
            '.accessibilityLabel("图片文字块 \\(accessibilityOriginalText)")',
            ".accessibilityValue(accessibilityValue)",
            "isSelected",
        ]:
            self.assertIn(marker, self.row)

    def test_value_exposes_translation_and_empty_original_fallback(self) -> None:
        value = braced_body(self.row, "private var accessibilityValue: String")
        self.assertIn('parts.append(block.translation.isEmpty ? "等待翻译" : "译文：\\(block.translation)")', value)
        original = braced_body(self.row, "private var accessibilityOriginalText: String")
        self.assertIn('block.original.isEmpty ? "空" : block.original', original)
        self.assertIn("accessibilityConfidencePercent", value)
        self.assertIn("isReviewCompleted ? \"本次已复查\" : \"待复查\"", value)

    def test_context_does_not_mutate_store_or_change_ocr_path(self) -> None:
        self.assertNotIn("TranslationSessionStore", self.row)
        self.assertNotIn("VisionOCRService", self.row)
        self.assertNotIn("runImageTranslation", self.row)
        self.assertNotIn("saveImage", self.row)

    def test_version_and_ci_route_follow_v357(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.58;", self.project)
        old = "python3 -B scripts/test-v357-manga-probe-block-accessibility-contract.py"
        new = "python3 -B scripts/test-v358-image-review-row-context-accessibility-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75|76|77|78|79|80)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
