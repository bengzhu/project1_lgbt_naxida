#!/usr/bin/env python3
"""Contract for v3.128 actionable VoiceOver image-review completion state."""

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


class ImageReviewCompletionActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.inspector = braced_body(self.panel, "private var inspector: some View")
        self.completion = braced_body(
            self.inspector,
            "if reviewFilter == .needsReview, reviewCompletedBlockCount > 0",
        )
        self.completion_action_helper = braced_body(
            self.panel,
            "private func reviewCompletionEmptyStateAccessibility<Content: View>",
        )

    def test_completion_state_is_a_single_stable_accessibility_context(self) -> None:
        self.assertIn(".accessibilityElement(children: .ignore)", self.completion)
        self.assertIn('.accessibilityLabel("本次复查完成")', self.completion)
        self.assertIn(".accessibilityValue(reviewCompletionAccessibilityValue)", self.completion)
        self.assertIn("reviewCompletionEmptyStateAccessibility(", self.completion)
        self.assertIn("Self.reviewCompletionAccessibilityFocusID", self.completion)

    def test_completion_state_exposes_direct_restart_action(self) -> None:
        self.assertIn("if canReviewImageTranslation", self.completion_action_helper)
        self.assertIn('.accessibilityAction(named: "重新复查")', self.completion_action_helper)
        self.assertIn("restartReviewQueue()", self.completion_action_helper)
        locked_branch = self.completion_action_helper[self.completion_action_helper.index("else"):]
        self.assertNotIn('.accessibilityAction(named: "重新复查")', locked_branch)

    def test_completion_value_and_hint_reuse_existing_view_guards(self) -> None:
        value = braced_body(self.panel, "private var reviewCompletionAccessibilityValue")
        self.assertIn("reviewCompletedBlockCount", value)
        self.assertIn("allReviewRequiredBlocks.count", value)
        self.assertIn("reviewFilter.rawValue", value)
        self.assertIn("canReviewImageTranslation", self.completion)
        restart = braced_body(self.panel, "private func restartReviewQueue()")
        self.assertIn("guard canReviewImageTranslation", restart)
        self.assertIn("store.resetImageTranslationReviewProgress()", restart)

    def test_completion_action_remains_view_only(self) -> None:
        self.assertNotIn("reviewCompletionAccessibilityValue", self.store)
        self.assertNotIn("reviewCompletionAccessibilityFocusID", self.store)
        self.assertNotIn("runBubbleFirstProbe", self.panel)

    def test_version_and_ci_route_follow_v3127(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 128) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.127;", self.project)
        script = "scripts/test-v3128-image-review-completion-action-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3127-image-failure-status-actions-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))
        self.assertRegex(
            self.workflow,
            r"test-v3\(1\[1-9\]|\[2-7\]\[0-9\]|8\[01\]|12\[2-8\]\)-",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
