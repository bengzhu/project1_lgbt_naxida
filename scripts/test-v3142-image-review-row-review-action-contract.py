#!/usr/bin/env python3
"""Contract for a gated direct VoiceOver review action on image result rows."""

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


class ImageReviewRowReviewActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.row = braced_body(
            self.view,
            "private struct ImageTranslationBlockRow: View",
        )
        self.modifier = braced_body(
            self.view,
            "private struct ImageReviewRowReviewAccessibilityModifier",
        )

    def test_risk_editable_row_exposes_matching_review_action(self) -> None:
        self.assertIn("let isReviewRequired: Bool", self.modifier)
        self.assertIn("let isReviewCompleted: Bool", self.modifier)
        self.assertIn("let canReview: Bool", self.modifier)
        self.assertIn("let toggleReviewCompletion: () -> Void", self.modifier)
        self.assertIn("if isReviewRequired && canReview", self.modifier)
        self.assertIn(
            '.accessibilityAction(named: isReviewCompleted ? "撤销本次复查" : "完成并继续复查")',
            self.modifier,
        )
        action = braced_body(
            self.modifier,
            '.accessibilityAction(named: isReviewCompleted ? "撤销本次复查" : "完成并继续复查")',
        )
        self.assertIn("toggleReviewCompletion()", action)
        self.assertIn("ImageReviewRowReviewAccessibilityModifier", self.row)
        self.assertIn(
            "isReviewRequired: ImageOCRResultSummary.requiresReview(block)",
            self.row,
        )
        self.assertIn("isReviewCompleted: isReviewCompleted", self.row)
        self.assertIn("canReview: canReview", self.row)
        self.assertIn("toggleReviewCompletion: toggleReviewCompletion", self.row)

    def test_non_risk_or_locked_rows_do_not_expose_review_action(self) -> None:
        locked_branch = self.modifier[self.modifier.index("} else {") :]
        self.assertNotIn("accessibilityAction", locked_branch)
        self.assertIn("if ImageOCRResultSummary.requiresReview(block)", self.row)
        self.assertIn('isReviewCompleted ? "撤销本次复查" : "完成并继续复查"', self.row)
        self.assertIn(".disabled(!canReview)", self.row)
        self.assertIn("reviewUnavailableHint", self.row)

    def test_review_action_keeps_result_row_context_and_existing_entry(self) -> None:
        self.assertIn('.accessibilityLabel("图片文字块 \\(accessibilityOriginalText)")', self.row)
        self.assertIn(".accessibilityValue(accessibilityValue)", self.row)
        self.assertIn(".accessibilityHint(accessibilityHint)", self.row)
        self.assertIn('equals: "image-review-row-\\(block.id.uuidString)"', self.row)
        self.assertIn("Button(action: select)", self.row)
        self.assertIn("action: toggleReviewCompletion", self.row)

    def test_review_action_is_view_only(self) -> None:
        self.assertNotIn("ImageReviewRowReviewAccessibilityModifier", self.store)
        self.assertNotIn("runImageTranslationPipeline", self.row)
        self.assertNotIn("VisionOCRService", self.row)
        self.assertNotIn("MangaOverlayProbeService", self.row)

    def test_version_and_ci_route_follow_v3141(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 142) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.141;", self.project)
        old = "scripts/test-v3141-image-review-row-restore-action-contract.py"
        new = "scripts/test-v3142-image-review-row-review-action-contract.py"
        self.assertIn(f"python3 -B {old}", self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(f"python3 -B {old}"), self.workflow.index(f"python3 -B {new}"))
        self.assertIn("14[1]", self.workflow)
        self.assertIn("14[2]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
