#!/usr/bin/env python3
"""Contracts for v3.16 one-tap image review queue entry."""

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


class ImageReviewQueueEntryContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")

    def test_review_command_only_appears_for_a_nonempty_queue(self) -> None:
        self.assertIn("if !reviewRequiredBlocks.isEmpty", self.view)
        self.assertIn("title: reviewQueueActionTitle", self.view)
        self.assertIn('systemImage: "checklist"', self.view)
        self.assertIn("tone: .warning", self.view)
        self.assertIn("action: beginReviewQueue", self.view)
        self.assertIn(".disabled(!canReviewImageTranslation)", self.view)
        self.assertIn('"显示待复查结果并定位当前或第一个文字块"', self.view)
        self.assertIn('"图片翻译完成后可开始复查"', self.view)

    def test_review_queue_uses_the_shared_product_review_filter(self) -> None:
        review_blocks = braced_body(
            self.view,
            "private var reviewRequiredBlocks: [ImageTranslationBlock]",
        )
        self.assertIn(
            "ImageOCRReviewFilter.needsReview.blocks(from: store.imageTranslationBlocks)",
            review_blocks,
        )

    def test_review_entry_retains_a_visible_selection_or_uses_first(self) -> None:
        begin = braced_body(self.view, "private func beginReviewQueue()")
        self.assertIn("canReviewImageTranslation", begin)
        self.assertIn("let firstBlockID = reviewRequiredBlocks.first?.id", begin)
        self.assertIn("selectedImageTranslationBlockID.flatMap", begin)
        self.assertIn("reviewRequiredBlocks.contains", begin)
        self.assertIn("reviewFilter = .needsReview", begin)
        self.assertIn("let targetBlockID = retainedBlockID ?? firstBlockID", begin)
        self.assertIn("selectedImageTranslationBlockID = targetBlockID", begin)
        self.assertEqual(begin.count("revealPreview()"), 1)
        self.assertLess(
            begin.index("reviewFilter = .needsReview"),
            begin.index("selectedImageTranslationBlockID = targetBlockID"),
        )

    def test_review_entry_remains_view_private_and_uses_a_44pt_component(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        components = read("AITRANS/Views/AppComponents.swift")
        secondary = braced_body(components, "struct AppSecondaryButton: View")
        self.assertNotIn("beginReviewQueue", store)
        self.assertNotIn("reviewRequiredBlocks", store)
        self.assertIn(
            ".frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTarget)",
            secondary,
        )

    def test_ci_runs_v316_after_v315(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        contract_step = workflow[
            workflow.index("- name: UI interaction contract"):
            workflow.index("- name: v1.88 home UI contract")
        ]
        self.assertLess(
            contract_step.index("scripts/test-v315-image-preview-direct-selection-contract.py"),
            contract_step.index("scripts/test-v316-image-review-queue-entry-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
