#!/usr/bin/env python3
"""Contract for a gated direct VoiceOver review action on image focus previews."""

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


class ImageFocusPreviewReviewActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )
        self.modifier = braced_body(
            self.view,
            "private struct ImageFocusPreviewReviewAccessibilityModifier",
        )

    def test_focus_parent_exposes_gated_review_action(self) -> None:
        self.assertIn("let isReviewRequired: Bool", self.modifier)
        self.assertIn("let canReview: Bool", self.modifier)
        self.assertIn("let isReviewCompleted: Bool", self.modifier)
        self.assertIn("if isReviewRequired && canReview", self.modifier)
        self.assertIn(
            '.accessibilityAction(named: isReviewCompleted ? "重新加入待复查" : "完成并继续复查")',
            self.modifier,
        )
        action = braced_body(
            self.modifier,
            '.accessibilityAction(named: isReviewCompleted ? "重新加入待复查" : "完成并继续复查")',
        )
        self.assertIn("toggleReviewCompletion()", action)
        self.assertIn("ImageFocusPreviewReviewAccessibilityModifier", self.focus)
        self.assertIn("isReviewRequired: isReviewRequired", self.focus)
        self.assertIn("canReview: canReview", self.focus)

    def test_review_action_is_not_exposed_when_locked_or_not_required(self) -> None:
        locked_branch = self.modifier[self.modifier.index("} else {") :]
        self.assertNotIn("accessibilityAction", locked_branch)
        self.assertIn(".disabled(!canReview)", self.focus)
        self.assertIn("reviewUnavailableHint", self.focus)
        self.assertIn("guard isReviewRequired else", self.focus)

    def test_review_action_keeps_focus_preview_context(self) -> None:
        self.assertIn('.accessibilityLabel("已定位文字块局部放大")', self.focus)
        self.assertIn('.accessibilityValue("\\(positionText)，\\(accessibilityOriginalText)")', self.focus)
        self.assertIn('.accessibilityAction(named: "关闭局部放大")', self.focus)
        self.assertIn("ImageFocusPreviewEditAccessibilityModifier", self.focus)
        self.assertIn("reviewAccessibilityHint(appendingTo: base)", self.focus)
        self.assertIn("reviewActionAccessibilityName", self.focus)
        self.assertIn("可执行“\\(reviewActionAccessibilityName)”", self.focus)

    def test_review_button_and_action_share_existing_toggle_entry(self) -> None:
        self.assertIn("action: toggleReviewCompletion", self.focus)
        self.assertIn("toggleReviewCompletion()", self.modifier)
        self.assertIn('isReviewCompleted ? "重新加入待复查" : "完成并继续复查"', self.focus)
        self.assertIn("reviewUnavailableHint", self.focus)

    def test_review_action_is_view_only(self) -> None:
        self.assertNotIn("ImageFocusPreviewReviewAccessibilityModifier", self.store)
        self.assertNotIn("runImageTranslationPipeline", self.focus)
        self.assertNotIn("MangaOverlayProbeService", self.focus)

    def test_version_and_ci_route_follow_v3137(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 138) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.137;", self.project)
        old = "scripts/test-v3137-image-focus-edit-action-contract.py"
        new = "scripts/test-v3138-image-focus-review-action-contract.py"
        self.assertIn(f"python3 -B {old}", self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(f"python3 -B {old}"), self.workflow.index(f"python3 -B {new}"))
        self.assertIn("13[0-8]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
