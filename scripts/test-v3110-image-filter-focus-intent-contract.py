#!/usr/bin/env python3
"""Contract for v3.110 image review filter focus intent arbitration."""

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


class ImageFilterFocusIntentContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_user_filter_change_focuses_results_but_explicit_intent_wins(self) -> None:
        change = braced_body(self.panel, ".onChange(of: reviewFilter)")
        for marker in [
            "let explicitFocusID = pendingReviewFilterFocusID",
            "let suppressResultFocus = suppressNextReviewFilterResultFocus",
            "pendingReviewFilterFocusID = nil",
            "suppressNextReviewFilterResultFocus = false",
            "clearHiddenReviewSelection()",
            "if let explicitFocusID",
            "moveReviewAccessibilityFocus(to: explicitFocusID)",
            "focusReviewFilterResultIfNeeded()",
            "focusEmptyReviewStateIfNeeded()",
        ]:
            self.assertIn(marker, change)
        self.assertIn("private func focusReviewFilterResultIfNeeded()", self.panel)

    def test_programmatic_filter_changes_declare_focus_intent(self) -> None:
        helper = braced_body(self.panel, "private func prepareReviewFilterChange(")
        for marker in [
            "to nextFilter: ImageOCRReviewFilter",
            "focusID: String?",
            "suppressResultFocus: Bool = false",
        ]:
            self.assertIn(marker, self.panel)
        for marker in [
            "reviewFilter != nextFilter",
            "pendingReviewFilterFocusID = focusID",
            "suppressNextReviewFilterResultFocus = suppressResultFocus",
            "reviewFilter = nextFilter",
        ]:
            self.assertIn(marker, helper)
        for marker in [
            "focusID: reviewRowAccessibilityFocusID(block.id)",
            "focusID: reviewPreviewAccessibilityFocusID(targetBlockID)",
            "focusID: nextFocusID",
            "suppressResultFocus: true",
        ]:
            self.assertIn(marker, self.panel)
        self.assertEqual(
            len(re.findall(r"^\s*reviewFilter = ", self.panel, re.MULTILINE)),
            1,
            "reviewFilter writes must go through the focus-intent helper",
        )

    def test_intent_state_is_view_private_and_stale_intent_is_cleared(self) -> None:
        for marker in [
            "@State private var pendingReviewFilterFocusID: String?",
            "@State private var suppressNextReviewFilterResultFocus = false",
            "pendingReviewFilterFocusID = nil",
            "suppressNextReviewFilterResultFocus = false",
        ]:
            self.assertIn(marker, self.panel)
        self.assertNotIn("pendingReviewFilterFocusID", self.store)
        self.assertNotIn("suppressNextReviewFilterResultFocus", self.store)

    def test_version_and_ci_route_follow_v3109(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 110) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.109;", self.project)
        script = "scripts/test-v3110-image-filter-focus-intent-contract.py"
        old = "scripts/test-v3109-image-filter-result-focus-contract.py"
        new = f"python3 -B {script}"
        self.assertIn(script, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
