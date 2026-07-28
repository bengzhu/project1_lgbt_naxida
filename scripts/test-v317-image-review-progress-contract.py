#!/usr/bin/env python3
"""Contracts for v3.17 revision-scoped image review progress."""

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


class ImageReviewProgressContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")

    def test_progress_is_view_private_and_resets_with_image_revision(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertIn(
            "@State private var reviewedImageTranslationBlockIDs: Set<UUID> = []",
            self.view,
        )
        revision_change = braced_body(
            self.view,
            ".onChange(of: store.imageTranslationRevision)",
        )
        self.assertIn("selectedImageTranslationBlockID = nil", revision_change)
        self.assertIn("reviewedImageTranslationBlockIDs.removeAll()", revision_change)
        self.assertNotIn("reviewedImageTranslationBlockIDs", store)
        self.assertNotIn("reviewCompletedBlockCount", store)

    def test_pending_queue_reuses_product_risk_definition(self) -> None:
        pending = braced_body(
            self.view,
            "private var reviewRequiredBlocks: [ImageTranslationBlock]",
        )
        self.assertIn(
            "ImageOCRReviewFilter.needsReview.blocks(from: store.imageTranslationBlocks)",
            pending,
        )
        self.assertIn("!reviewedImageTranslationBlockIDs.contains($0.id)", pending)
        visible = braced_body(
            self.view,
            "private var visibleImageTranslationBlocks: [ImageTranslationBlock]",
        )
        self.assertIn("reviewFilter.blocks(from: store.imageTranslationBlocks)", visible)
        self.assertIn("guard reviewFilter == .needsReview else", visible)

    def test_completion_advances_within_pending_order_and_supports_undo(self) -> None:
        toggle = braced_body(self.view, "private func toggleReviewCompletion(_ blockID: UUID)")
        self.assertIn("reviewedImageTranslationBlockIDs.remove(blockID)", toggle)
        self.assertIn("selectedImageTranslationBlockID = blockID", toggle)
        self.assertIn("let pendingBlocks = reviewRequiredBlocks", toggle)
        self.assertIn("pendingBlocks.dropFirst(currentIndex + 1).first?.id", toggle)
        self.assertIn("pendingBlocks[..<currentIndex].last?.id", toggle)
        self.assertIn("reviewedImageTranslationBlockIDs.insert(blockID)", toggle)
        self.assertIn("reviewFilter = .needsReview", toggle)
        self.assertIn("selectedImageTranslationBlockID = nextBlockID", toggle)

    def test_completed_queue_has_clear_state_and_restart_command(self) -> None:
        self.assertIn('title: "本次复查完成"', self.view)
        self.assertIn('title: "重新复查 \\(reviewCompletedBlockCount)"', self.view)
        self.assertIn('systemImage: "arrow.counterclockwise"', self.view)
        restart = braced_body(self.view, "private func restartReviewQueue()")
        self.assertIn("reviewedImageTranslationBlockIDs.removeAll()", restart)
        self.assertIn("reviewFilter = .needsReview", restart)
        self.assertIn("selectedImageTranslationBlockID = firstBlockID", restart)
        self.assertEqual(restart.count("revealPreview()"), 1)

    def test_focus_exposes_named_44pt_completion_and_undo(self) -> None:
        focus = braced_body(self.view, "private struct ImageTranslationFocusPreview: View")
        self.assertIn('isReviewCompleted ? "重新加入待复查" : "完成并继续复查"', focus)
        self.assertIn(
            'systemImage: isReviewCompleted ? "arrow.uturn.backward" : "checkmark"',
            focus,
        )
        self.assertIn("action: toggleReviewCompletion", focus)
        self.assertIn(
            ".frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)",
            focus,
        )
        self.assertIn("标记完成并定位下一个待复查文字块", focus)

    def test_reviewed_rows_have_non_color_status(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        self.assertIn("let isReviewCompleted: Bool", row)
        self.assertIn('Label("本次已复查", systemImage: "checkmark.circle.fill")', row)
        self.assertIn(
            "isReviewCompleted: reviewedImageTranslationBlockIDs.contains(block.id)",
            self.view,
        )

    def test_ci_runs_v317_after_v316(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        contract_step = workflow[
            workflow.index("- name: UI interaction contract"):
            workflow.index("- name: v1.88 home UI contract")
        ]
        self.assertLess(
            contract_step.index("scripts/test-v316-image-review-queue-entry-contract.py"),
            contract_step.index("scripts/test-v317-image-review-progress-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
