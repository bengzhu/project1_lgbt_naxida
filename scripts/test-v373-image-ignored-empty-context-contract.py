#!/usr/bin/env python3
"""Contracts for v3.73 empty OCR context in ignored image rows."""

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


class IgnoredImageEmptyContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.row = braced_body(
            self.view,
            "private struct ImageTranslationIgnoredBlockRow: View",
        )

    def test_empty_original_has_visible_fallback(self) -> None:
        self.assertIn("Text(displayOriginalText)", self.row)
        self.assertIn('block.original.isEmpty ? "空 OCR 原文" : block.original', self.row)

    def test_empty_original_has_stable_accessibility_label(self) -> None:
        self.assertIn(
            '.accessibilityLabel("已忽略 OCR 文字块 \\(accessibilityOriginalText)")',
            self.row,
        )
        self.assertIn('block.original.isEmpty ? "空" : block.original', self.row)
        self.assertIn(".accessibilityValue(accessibilityValue)", self.row)

    def test_non_empty_original_and_restore_scope_remain_unchanged(self) -> None:
        self.assertIn("block.original", self.row)
        self.assertIn('Button("恢复", systemImage: "arrow.uturn.backward", action: restore)', self.row)
        self.assertIn("已从当前图片预览、导出和转录中移除", self.row)
        self.assertIn("modificationUnavailableHint", self.row)

    def test_change_is_view_only(self) -> None:
        self.assertNotIn("TranslationSessionStore", self.row)
        self.assertNotIn("VisionOCRService", self.row)
        self.assertNotIn("FileManager", self.row)
        self.assertNotIn("runMangaOverlayProbe", self.row)
        self.assertNotIn("store.", self.row)
        self.assertNotIn("@EnvironmentObject", self.row)
        self.assertIn("ImageTranslationBlock", self.row)

    def test_version_and_ci_route_follow_v372(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.73;"), 2)
        self.assertNotIn("MARKETING_VERSION = 3.72;", self.project)
        old = "python3 -B scripts/test-v372-koharu-v1-readiness-clarity-contract.py"
        new = "python3 -B scripts/test-v373-image-ignored-empty-context-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
