#!/usr/bin/env python3
"""Contract for v3.129 actionable empty image-review filter state."""

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


class ImageReviewFilterEmptyActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.inspector = braced_body(self.panel, "private var inspector: some View")
        self.empty_filter = braced_body(self.inspector, "else if reviewFilter != .all")

    def test_filtered_empty_state_has_visible_and_voiceover_recovery_actions(self) -> None:
        self.assertIn('title: "当前筛选没有结果"', self.empty_filter)
        self.assertIn("AppSecondaryButton", self.empty_filter)
        self.assertIn('title: "显示全部结果"', self.empty_filter)
        self.assertIn("action: showAllReviewResults", self.empty_filter)
        self.assertIn('.accessibilityAction(named: "显示全部结果")', self.empty_filter)
        self.assertIn("Self.reviewFilterEmptyAccessibilityFocusID", self.empty_filter)

    def test_empty_state_explains_direct_recovery(self) -> None:
        self.assertIn("reviewFilterEmptyStateAccessibilityValue", self.empty_filter)
        self.assertIn("显示全部结果", self.empty_filter)
        self.assertIn("reviewFilterEmptyAccessibilityFocusID", self.empty_filter)

    def test_recovery_only_changes_view_filter_and_reuses_existing_focus_path(self) -> None:
        helper = braced_body(self.panel, "private func showAllReviewResults")
        self.assertIn("guard reviewFilter != .all else { return }", helper)
        self.assertIn("prepareReviewFilterChange(to: .all, focusID: nil)", helper)
        self.assertNotIn("store.", helper)
        self.assertNotIn("runBubbleFirstProbe", self.panel)
        self.assertNotIn("showAllReviewResults", self.store)

    def test_completion_state_keeps_its_distinct_action(self) -> None:
        completion_index = self.inspector.index("reviewFilter == .needsReview, reviewCompletedBlockCount > 0")
        empty_index = self.inspector.index("else if reviewFilter != .all")
        self.assertLess(completion_index, empty_index)
        # The completion state may attach its action directly to the container,
        # or route it through a View-only helper so locked states can omit the
        # action while retaining the same accessibility context and hint.
        if '.accessibilityAction(named: "重新复查")' not in self.inspector:
            helper = braced_body(
                self.panel,
                "private func reviewCompletionEmptyStateAccessibility<Content: View>",
            )
            self.assertIn("reviewCompletionEmptyStateAccessibility(", self.inspector)
            self.assertIn("if canReviewImageTranslation", helper)
            self.assertIn('.accessibilityAction(named: "重新复查")', helper)
            self.assertIn("restartReviewQueue()", helper)
            locked_branch = helper[helper.index("else"):]
            self.assertNotIn('.accessibilityAction(named: "重新复查")', locked_branch)
        else:
            self.assertIn('.accessibilityAction(named: "重新复查")', self.inspector)

    def test_version_and_ci_route_follow_v3128(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 129) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.128;", self.project)
        script = "scripts/test-v3129-image-review-filter-empty-action-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3128-image-review-completion-action-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))
        self.assertRegex(
            self.workflow,
            r"test-v3\(1\[1-9\]|\[2-7\]\[0-9\]|8\[01\]|12\[2-9\]\)-",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
