#!/usr/bin/env python3
"""Static contracts for v3.149 gating the completed-review empty-state action."""

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


class ImageReviewCompletionActionGateContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.inspector = braced_body(self.panel, "private var inspector: some View")
        self.completion = braced_body(
            self.inspector,
            "if reviewFilter == .needsReview, reviewCompletedBlockCount > 0",
        )
        self.action_helper = braced_body(
            self.panel,
            "private func reviewCompletionEmptyStateAccessibility<Content: View>",
        )

    def test_completion_empty_state_hides_restart_action_when_review_is_locked(self) -> None:
        self.assertIn("reviewCompletionEmptyStateAccessibility(", self.completion)
        self.assertIn('.accessibilityLabel("本次复查完成")', self.completion)
        self.assertIn("reviewCompletionAccessibilityValue", self.completion)
        self.assertIn("imageReviewUnavailableDetail", self.completion)
        self.assertIn("if canReviewImageTranslation", self.action_helper)
        self.assertIn('.accessibilityAction(named: "重新复查")', self.action_helper)
        self.assertIn("restartReviewQueue()", self.action_helper)
        locked_branch = self.action_helper[self.action_helper.index("else"):]
        self.assertNotIn('.accessibilityAction(named: "重新复查")', locked_branch)

    def test_completion_action_reuses_existing_view_focus_and_store_guard(self) -> None:
        self.assertIn("Self.reviewCompletionAccessibilityFocusID", self.completion)
        restart = braced_body(self.panel, "private func restartReviewQueue()")
        self.assertIn("guard canReviewImageTranslation", restart)
        self.assertIn("store.resetImageTranslationReviewProgress()", restart)
        for forbidden in [
            "imageTranslationBlocks =",
            "TranslationSessionStore(",
            "VisionOCRService",
            "persist(",
            "groundTruth",
        ]:
            self.assertNotIn(forbidden, self.action_helper)

    def test_version_and_ci_route_follow_v3148(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.149;"), 2)
        self.assertNotIn("MARKETING_VERSION = 3.148;", self.project)
        old = "python3 -B scripts/test-v3148-image-ignored-empty-state-action-gate-contract.py"
        new = "python3 -B scripts/test-v3149-image-review-completion-action-gate-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v3149-image-review-completion-action-gate-contract.py' "
            '"$RESULT_ROOT/changed-files.txt" >/dev/null; then'
        )
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn(route, self.workflow)
        self.assertIn("14[9]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
