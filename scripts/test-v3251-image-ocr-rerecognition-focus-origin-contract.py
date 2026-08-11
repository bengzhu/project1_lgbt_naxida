#!/usr/bin/env python3
"""Contract for preserving the rerecognition focus origin in the image UI."""

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


class ImageOCRRerecognitionFocusOriginContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.request = braced_body(
            self.view,
            "private func requestImageTranslationRerecognition(",
        )
        self.completion = braced_body(
            self.view,
            "private func focusImageTranslationRerecognitionCompletionIfNeeded(",
        )
        self.failure = braced_body(
            self.view,
            "private func focusImageTranslationRerecognitionFailureIfNeeded(",
        )
        self.revision = braced_body(
            self.view,
            ".onChange(of: store.imageTranslationRevision)",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_panel_tracks_preview_and_row_origins(self) -> None:
        for marker in [
            "private enum ImageTranslationRerecognitionFocusOrigin",
            "case row",
            "case preview",
            "@State private var imageTranslationRerecognitionFocusOrigin:",
            "ImageTranslationPreview(",
            "focusOrigin: .preview",
            "ImageTranslationBlockRow(",
            "focusOrigin: .row",
        ]:
            self.assertIn(marker, self.panel)
        self.assertLess(
            self.panel.index("ImageTranslationPreview("),
            self.panel.index("focusOrigin: .preview"),
        )
        self.assertLess(
            self.panel.index("ImageTranslationBlockRow("),
            self.panel.index("focusOrigin: .row"),
        )

    def test_request_helper_sets_origin_only_for_an_accepted_request(self) -> None:
        for marker in [
            "guard store.canRerecognizeImageTranslationBlock(blockID) else { return }",
            "imageTranslationRerecognitionFocusOrigin = focusOrigin",
            "store.rerecognizeImageTranslationBlock(blockID)",
        ]:
            self.assertIn(marker, self.request)
        self.assertEqual(
            self.panel.count("store.rerecognizeImageTranslationBlock("),
            1,
        )

    def test_success_focus_selects_preview_or_row_and_keeps_guards(self) -> None:
        for marker in [
            "let focusOrigin = imageTranslationRerecognitionFocusOrigin ?? .row",
            "revision == store.imageTranslationRevision",
            "generation == store.imageTranslationBlockRerecognitionCompletionGeneration",
            "store.imageTranslationBlockRerecognitionCompletedBlockID == blockID",
            "store.imageTranslationState == .translated || store.imageTranslationState == .failed",
            "switch focusOrigin",
            "case .row:",
            "focusID = reviewRowAccessibilityFocusID(blockID)",
            "case .preview:",
            "focusID = reviewPreviewAccessibilityFocusID(blockID)",
            "imageTranslationRerecognitionFocusOrigin = nil",
        ]:
            self.assertIn(marker, self.completion)
        self.assertIn(
            "visibleImageTranslationBlocks.contains(where: { $0.id == blockID })",
            self.completion,
        )
        self.assertIn("clearHiddenReviewSelection()", self.completion)

    def test_failure_focus_still_wins_and_clears_origin(self) -> None:
        for marker in [
            "revision == store.imageTranslationRevision",
            "generation == store.imageTranslationBlockRerecognitionFailureGeneration",
            "store.imageTranslationRerecognizingBlockID == nil",
            "store.imageTranslationState == .translated || store.imageTranslationState == .failed",
            "imageTranslationRerecognitionFocusOrigin = nil",
            "moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)",
        ]:
            self.assertIn(marker, self.failure)

    def test_revision_change_clears_stale_origin(self) -> None:
        self.assertIn("imageTranslationRerecognitionFocusOrigin = nil", self.revision)
        self.assertIn(
            ".onChange(of: store.imageTranslationBlockRerecognitionCompletionGeneration)",
            self.view,
        )
        self.assertIn(
            ".onChange(of: store.imageTranslationBlockRerecognitionFailureGeneration)",
            self.view,
        )

    def test_version_and_ci_route_follow_v3250(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 251) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.250;", self.project)
        previous = "python3 -B scripts/test-v3250-image-japanese-detector-role-boundary-contract.py"
        current = "python3 -B scripts/test-v3251-image-ocr-rerecognition-focus-origin-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3251-image-ocr-rerecognition-focus-origin-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
