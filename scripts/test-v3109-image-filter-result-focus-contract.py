#!/usr/bin/env python3
"""Contract for v3.109 focus handoff to the first image OCR filter result."""

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
                return source[brace:index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageFilterResultFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_filter_change_focuses_first_visible_result_row(self) -> None:
        for marker in [
            ".onChange(of: reviewFilter)",
            "focusReviewFilterResultIfNeeded()",
            "private func focusReviewFilterResultIfNeeded()",
            "visibleImageTranslationBlocks.first",
            "reviewRowAccessibilityFocusID(firstVisibleBlock.id)",
            "moveReviewAccessibilityFocus(to: focusID)",
        ]:
            self.assertIn(marker, self.panel)

    def test_empty_filter_fallback_remains_after_result_focus(self) -> None:
        change = braced_body(self.panel, ".onChange(of: reviewFilter)")
        self.assertLess(
            change.index("focusReviewFilterResultIfNeeded()"),
            change.index("focusEmptyReviewStateIfNeeded()"),
        )
        helper = braced_body(self.panel, "private func focusReviewFilterResultIfNeeded()")
        self.assertIn("visibleImageTranslationBlocks.first", helper)
        empty = braced_body(self.panel, "private func focusEmptyReviewStateIfNeeded()")
        self.assertIn("visibleImageTranslationBlocks.isEmpty", empty)
        self.assertIn("reviewFilterEmptyAccessibilityFocusID", self.panel)

    def test_focus_is_view_private_and_revision_scoped(self) -> None:
        self.assertNotIn("focusReviewFilterResultIfNeeded", self.store)
        self.assertNotIn("reviewRowAccessibilityFocusID", self.store)
        self.assertIn("private func moveReviewAccessibilityFocus(to focusID: String?)", self.panel)
        self.assertIn("let revision = store.imageTranslationRevision", self.panel)
        self.assertIn("guard revision == store.imageTranslationRevision", self.panel)

    def test_version_and_ci_route_follow_v3108(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 109) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.108;", self.project)
        script = "scripts/test-v3109-image-filter-result-focus-contract.py"
        old = "scripts/test-v3108-manga-filter-result-focus-contract.py"
        new = f"python3 -B {script}"
        self.assertIn(script, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
