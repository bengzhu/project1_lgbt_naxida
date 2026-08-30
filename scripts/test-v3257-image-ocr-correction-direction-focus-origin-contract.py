#!/usr/bin/env python3
"""Contract for preserving the row/preview focus origin through correction-sheet direction changes."""

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


class ImageOCRCorrectionDirectionFocusOriginContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.row_entry = braced_body(
            self.panel,
            "private func beginCorrection(of block: ImageTranslationBlock)",
        )
        self.preview_entry = braced_body(
            self.panel,
            "private func beginCorrectionFromFocusPreview(of block: ImageTranslationBlock)",
        )
        self.direction = braced_body(
            self.panel,
            "private func setImageTranslationBlockDirection(",
        )
        self.apply = braced_body(
            self.panel,
            "private func applyPendingCorrectionSheetDismissalFocus()",
        )
        self.completion = braced_body(
            self.panel,
            "private func completeReviewAfterCorrection(_ blockID: UUID)",
        )
        self.ignore = braced_body(
            self.panel,
            "private func ignoreImageTranslationBlock(_ block: ImageTranslationBlock) -> Bool",
        )
        self.revision = braced_body(
            self.panel,
            ".onChange(of: store.imageTranslationRevision)",
        )
        self.workflow = read(".github/workflows/ci-results.yml")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_row_and_preview_entries_record_independent_origins(self) -> None:
        for marker in [
            "private enum ImageTranslationCorrectionFocusOrigin",
            "case row",
            "case preview",
            "@State private var imageTranslationCorrectionFocusOrigin:",
        ]:
            self.assertIn(marker, self.panel)
        self.assertIn(
            "imageTranslationCorrectionFocusOrigin = .row",
            self.row_entry,
        )
        self.assertIn(
            "imageTranslationCorrectionFocusOrigin = .preview",
            self.preview_entry,
        )
        self.assertLess(
            self.row_entry.index("imageTranslationCorrectionFocusOrigin = .row"),
            self.row_entry.index("editingImageTranslationBlock = block"),
        )
        self.assertLess(
            self.preview_entry.index("imageTranslationCorrectionFocusOrigin = .preview"),
            self.preview_entry.index("editingImageTranslationBlock = block"),
        )

    def test_direction_picker_consumes_the_correction_origin(self) -> None:
        for marker in [
            "imageTranslationCorrectionFocusOrigin == .preview",
            "deferFocusUntilCorrectionSheetDismissal: true",
            "setImageTranslationBlockDirectionOverride(blockID, direction: direction)",
        ]:
            self.assertIn(marker, self.view)
        self.assertNotIn(
            "focusInPreview: false,\n                        deferFocusUntilCorrectionSheetDismissal: true",
            self.view,
        )
        self.assertNotIn("recognizeTextBlock(", self.direction)
        self.assertNotIn("rerunImageRecognition", self.direction)

    def test_hidden_filter_fallback_remains_the_final_focus_guard(self) -> None:
        for marker in [
            "focusAfterHiddenCorrectionSheetTargetIfNeeded(focusID)",
            "reviewFocusIDAfterHiddenDirectionBlock()",
            "isVisibleReviewBlockFocusID",
            'focusID.hasPrefix("image-review-preview-")',
        ]:
            self.assertIn(marker, self.panel)
        self.assertIn("clearHiddenReviewSelection()", self.panel)

    def test_origin_is_cleared_on_revision_and_sheet_terminal_paths(self) -> None:
        self.assertIn("imageTranslationCorrectionFocusOrigin = nil", self.revision)
        self.assertIn("imageTranslationCorrectionFocusOrigin = nil", self.apply)
        self.assertIn("imageTranslationCorrectionFocusOrigin = nil", self.completion)
        self.assertIn("imageTranslationCorrectionFocusOrigin = nil", self.ignore)
        self.assertIn("pendingCorrectionSheetDismissalRevision == store.imageTranslationRevision", self.apply)

    def test_correction_direction_stays_display_only(self) -> None:
        setter = braced_body(
            read("AITRANS/Services/TranslationSessionStore.swift"),
            "func setImageTranslationBlockDirectionOverride(",
        )
        for forbidden in [
            "recognizeTextBlock(",
            "recognizeJapaneseMangaOCR(",
            "rerunImageRecognition()",
        ]:
            self.assertNotIn(forbidden, setter)

    def test_version_and_ci_route_are_advanced(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.357", "3.357"])
        previous = "python3 -B scripts/test-v3256-image-review-direction-filter-focus-contract.py"
        current = "python3 -B scripts/test-v3257-image-ocr-correction-direction-focus-origin-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3257-image-ocr-correction-direction-focus-origin-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
