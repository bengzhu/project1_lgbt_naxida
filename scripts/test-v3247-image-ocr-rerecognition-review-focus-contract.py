#!/usr/bin/env python3
"""Contract for review focus after a scoped OCR block rerecognition succeeds."""

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


class ImageOCRRerecognitionReviewFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.rerecognition = braced_body(
            self.store,
            "func rerecognizeImageTranslationBlock(",
        )
        self.focus_change = braced_body(
            self.view,
            ".onChange(of: store.imageTranslationBlockRerecognitionCompletionGeneration)",
        )
        self.focus_helper = braced_body(
            self.view,
            "private func focusImageTranslationRerecognitionCompletionIfNeeded(",
        )

    def test_store_publishes_completed_block_and_generation(self) -> None:
        for marker in [
            "@Published private(set) var imageTranslationBlockRerecognitionCompletionGeneration = 0",
            "@Published private(set) var imageTranslationBlockRerecognitionCompletedBlockID: UUID?",
        ]:
            self.assertIn(marker, self.store)
        self.assertIn(
            "self.imageTranslationBlockRerecognitionCompletedBlockID = blockID",
            self.rerecognition,
        )
        self.assertEqual(
            self.rerecognition.count(
                "self.imageTranslationBlockRerecognitionCompletionGeneration &+= 1"
            ),
            1,
        )

    def test_generation_follows_successful_replacement_and_terminal_state(self) -> None:
        replacement = self.rerecognition.index(
            "self.imageTranslationBlocks[currentIndex] = replacement"
        )
        translated = self.rerecognition.index(
            "self.imageTranslationState = .translated",
            replacement,
        )
        failed = self.rerecognition.index(
            "self.imageTranslationState = .failed",
            replacement,
        )
        completed_id = self.rerecognition.index(
            "self.imageTranslationBlockRerecognitionCompletedBlockID = blockID",
            replacement,
        )
        generation = self.rerecognition.index(
            "self.imageTranslationBlockRerecognitionCompletionGeneration &+= 1",
            replacement,
        )
        self.assertGreater(completed_id, replacement)
        self.assertGreater(generation, translated)
        self.assertGreater(generation, failed)

        cancellation = braced_body(self.rerecognition, "catch is CancellationError")
        failure = braced_body(self.rerecognition, "catch {")
        marker = "imageTranslationBlockRerecognitionCompletionGeneration &+= 1"
        self.assertNotIn(marker, cancellation)
        self.assertNotIn(marker, failure)

    def test_new_content_and_cancel_clear_stale_completed_block(self) -> None:
        reset = "imageTranslationBlockRerecognitionCompletedBlockID = nil"
        self.assertGreaterEqual(self.store.count(reset), 3)
        self.assertIn("invalidateImageTranslationBlockRerecognition()", self.store)

    def test_view_guards_generation_revision_and_current_block(self) -> None:
        for marker in [
            "generation > 0",
            "let blockID = store.imageTranslationBlockRerecognitionCompletedBlockID",
            "store.imageTranslationState == .translated || store.imageTranslationState == .failed",
            "focusImageTranslationRerecognitionCompletionIfNeeded(",
        ]:
            self.assertIn(marker, self.focus_change)
        for marker in [
            "let revision = store.imageTranslationRevision",
            "revision == store.imageTranslationRevision",
            "generation == store.imageTranslationBlockRerecognitionCompletionGeneration",
            "store.imageTranslationBlockRerecognitionCompletedBlockID == blockID",
            "visibleImageTranslationBlocks.contains(where: { $0.id == blockID })",
        ]:
            self.assertIn(marker, self.focus_helper)

    def test_hidden_selection_moves_to_live_row_or_empty_state(self) -> None:
        for marker in [
            "if selectedImageTranslationBlockID == blockID",
            "selectedImageTranslationBlockID = nil",
            "clearHiddenReviewSelection()",
            "focusEmptyReviewStateIfNeeded()",
            "focusReviewFilterResultIfNeeded()",
        ]:
            self.assertIn(marker, self.focus_helper)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: reviewRowAccessibilityFocusID(blockID))",
            self.focus_helper,
        )

    def test_existing_rerecognition_stale_guards_remain(self) -> None:
        for marker in [
            "let requestID = UUID()",
            "let contentTaskID = imageTranslationTaskID",
            "self.imageTranslationBlockRerecognitionID == requestID",
            "self.imageTranslationTaskID == contentTaskID",
            "self.imageTranslationRerecognizingBlockID == blockID",
            "self.imageTranslationBlocks[currentIndex] == block",
        ]:
            self.assertIn(marker, self.rerecognition)

    def test_version_and_ci_route_follow_v3246(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 247) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.246;", self.project)
        previous = "python3 -B scripts/test-v3246-image-japanese-directional-koharu-padding-contract.py"
        current = "python3 -B scripts/test-v3247-image-ocr-rerecognition-review-focus-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3247-image-ocr-rerecognition-review-focus-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
