#!/usr/bin/env python3
"""Static contracts for v3.20 image review VoiceOver focus continuity."""

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


class ImageReviewVoiceOverFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")

    def test_focus_state_is_view_private_and_revision_scoped(self) -> None:
        panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.assertIn(
            "@AccessibilityFocusState private var reviewAccessibilityFocusID: String?",
            panel,
        )
        revision = braced_body(
            panel,
            ".onChange(of: store.imageTranslationRevision)",
        )
        self.assertIn("reviewAccessibilityFocusID = nil", revision)

    def test_row_and_focus_preview_have_distinct_focus_targets(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        focus_preview = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )
        self.assertIn("AccessibilityFocusState<String?>.Binding", row)
        self.assertIn('equals: "image-review-row-\\(block.id.uuidString)"', row)
        self.assertIn("AccessibilityFocusState<String?>.Binding", focus_preview)
        self.assertIn(
            'equals: "image-review-preview-\\(block.id.uuidString)"',
            focus_preview,
        )

    def test_entry_and_restart_focus_the_selected_preview(self) -> None:
        begin = braced_body(self.view, "private func beginReviewQueue()")
        restart = braced_body(self.view, "private func restartReviewQueue()")
        self.assertIn("moveReviewAccessibilityFocus", begin)
        self.assertIn("reviewPreviewAccessibilityFocusID(targetBlockID)", begin)
        self.assertIn("moveReviewAccessibilityFocus", restart)
        self.assertIn("reviewPreviewAccessibilityFocusID(firstBlockID)", restart)

    def test_completion_preserves_origin_and_has_terminal_focus(self) -> None:
        transition = braced_body(
            self.view,
            "private func toggleReviewCompletion(_ blockID: UUID, focusInPreview: Bool)",
        )
        self.assertIn("reviewPreviewAccessibilityFocusID($0)", transition)
        self.assertIn("reviewRowAccessibilityFocusID($0)", transition)
        self.assertIn("Self.reviewCompletionAccessibilityFocusID", transition)
        self.assertIn("moveReviewAccessibilityFocus(to: nextFocusID)", transition)

    def test_completion_state_is_a_real_focus_destination(self) -> None:
        self.assertIn(
            ".accessibilityFocused(\n"
            "                        $reviewAccessibilityFocusID,\n"
            "                        equals: Self.reviewCompletionAccessibilityFocusID",
            self.view,
        )

    def test_focus_publish_rejects_a_new_image_revision(self) -> None:
        mover = braced_body(
            self.view,
            "private func moveReviewAccessibilityFocus(to focusID: String?)",
        )
        self.assertIn("await Task.yield()", mover)
        self.assertIn("revision == store.imageTranslationRevision", mover)
        self.assertIn("reviewAccessibilityFocusID = focusID", mover)

    def test_ci_runs_v320_after_v319(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        old = "python3 -B scripts/test-v319-image-review-quick-action-contract.py"
        new = "python3 -B scripts/test-v320-image-review-voiceover-focus-contract.py"
        self.assertIn(new, workflow)
        self.assertLess(workflow.index(old), workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
