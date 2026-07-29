#!/usr/bin/env python3
"""Static contracts for v3.19 image review quick actions."""

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


class ImageReviewQuickActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")

    def test_entry_distinguishes_start_from_continue(self) -> None:
        title = braced_body(self.view, "private var reviewQueueActionTitle: String")
        self.assertIn('reviewCompletedBlockCount == 0 ? "开始复查" : "继续复查"', title)
        self.assertIn('"\\(action) \\(reviewRequiredBlocks.count)"', title)
        self.assertIn("title: reviewQueueActionTitle", self.view)

    def test_row_uses_separate_locate_and_review_buttons(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        self.assertIn("HStack(alignment: .center", row)
        self.assertIn("Button(action: select)", row)
        self.assertIn("action: toggleReviewCompletion", row)
        self.assertNotIn("Button(action: select) {\n            Button(", row)

    def test_quick_action_is_risk_scoped_named_and_44pt(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        self.assertIn("if ImageOCRResultSummary.requiresReview(block)", row)
        self.assertIn('isReviewCompleted ? "撤销本次复查" : "完成并继续复查"', row)
        self.assertIn(
            ".frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)",
            row,
        )
        self.assertIn("标记完成并定位下一个待复查文字块", row)

    def test_row_reuses_the_existing_queue_transition(self) -> None:
        call = braced_body(self.view, "ForEach(visibleImageTranslationBlocks)")
        self.assertIn("toggleReviewCompletion(block.id, focusInPreview: false)", call)
        transition = braced_body(
            self.view,
            "private func toggleReviewCompletion(_ blockID: UUID, focusInPreview: Bool)",
        )
        self.assertIn("reviewedImageTranslationBlockIDs.remove(blockID)", transition)
        self.assertIn("reviewedImageTranslationBlockIDs.insert(blockID)", transition)
        self.assertIn("selectedImageTranslationBlockID = nextBlockID", transition)

    def test_risk_labels_stack_for_narrow_and_dynamic_type_layouts(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        risk = row[row.index("if ImageOCRResultSummary.requiresReview(block)"):]
        self.assertIn("VStack(alignment: .leading", risk)
        self.assertIn('Label("低置信"', risk)
        self.assertIn('Label("方向待定"', risk)
        self.assertIn('Label("本次已复查"', risk)

    def test_ci_runs_v319_after_v318(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        old = "python3 -B scripts/test-v318-image-review-progress-evidence-contract.py"
        new = "python3 -B scripts/test-v319-image-review-quick-action-contract.py"
        self.assertIn(new, workflow)
        self.assertLess(workflow.index(old), workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
