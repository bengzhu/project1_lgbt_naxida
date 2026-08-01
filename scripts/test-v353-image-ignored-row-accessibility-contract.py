#!/usr/bin/env python3
"""Static contracts for v3.53 ignored image block accessibility context."""

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


class IgnoredImageRowAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_ignored_row_keeps_children_and_adds_stable_context(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationIgnoredBlockRow: View")
        self.assertIn(".accessibilityElement(children: .contain)", row)
        self.assertIn('.accessibilityLabel("已忽略 OCR 文字块 \\(block.original)")', row)
        self.assertIn(".accessibilityValue(accessibilityValue)", row)
        self.assertIn('Button("恢复", systemImage: "arrow.uturn.backward", action: restore)', row)

    def test_ignored_row_value_explains_removal_translation_and_restore_scope(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationIgnoredBlockRow: View")
        value = braced_body(row, "private var accessibilityValue: String")
        self.assertIn("已从当前图片预览、导出和转录中移除", value)
        self.assertIn("block.translation.isEmpty", value)
        self.assertIn('"没有现有译文" : "保留已有译文"', value)
        self.assertIn('canRestore ? "可以恢复" : "当前不可恢复"', value)

    def test_restore_button_retains_disabled_reason_and_focus_identity(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationIgnoredBlockRow: View")
        self.assertIn(".disabled(!canRestore)", row)
        self.assertIn("modificationUnavailableHint", row)
        self.assertIn('equals: "image-ignored-row-\\(block.id.uuidString)"', row)

    def test_version_and_ci_route_follow_v352(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.53;", self.project)
        old = "python3 -B scripts/test-v352-image-review-row-accessibility-contract.py"
        new = "python3 -B scripts/test-v353-image-ignored-row-accessibility-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
