#!/usr/bin/env python3
"""Contract for a gated direct VoiceOver Vision OCR restore action on image rows."""

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


class ImageReviewRowRestoreActionContractTests(unittest.TestCase):
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
            "private struct ImageReviewRowRestoreAccessibilityModifier",
        )

    def test_corrected_editable_row_exposes_restore_action(self) -> None:
        self.assertIn("let isManuallyCorrected: Bool", self.modifier)
        self.assertIn("let canEdit: Bool", self.modifier)
        self.assertIn("let restoreVisionOCR: () -> Void", self.modifier)
        self.assertIn("if isManuallyCorrected && canEdit", self.modifier)
        self.assertIn('.accessibilityAction(named: "恢复 Vision OCR")', self.modifier)
        action = braced_body(
            self.modifier,
            '.accessibilityAction(named: "恢复 Vision OCR")',
        )
        self.assertIn("restoreVisionOCR()", action)
        self.assertIn("ImageReviewRowRestoreAccessibilityModifier", self.row)
        self.assertIn("isManuallyCorrected: isManuallyCorrected", self.row)
        self.assertIn("canEdit: canEdit", self.row)
        self.assertIn("restoreVisionOCR: restoreVisionOCR", self.row)

    def test_unmodified_or_locked_rows_do_not_expose_restore_action(self) -> None:
        locked_branch = self.modifier[self.modifier.index("} else {") :]
        self.assertNotIn('.accessibilityAction(named: "恢复 Vision OCR")', locked_branch)
        self.assertIn('if isManuallyCorrected {', self.row)
        self.assertIn('Button("恢复 Vision OCR", systemImage: "arrow.counterclockwise", action: restoreVisionOCR)', self.row)
        self.assertIn(".disabled(!canEdit)", self.row)
        self.assertIn("恢复此文字块的 Vision OCR 原文与初始译文", self.row)
        self.assertIn("modificationUnavailableHint", self.row)

    def test_restore_action_keeps_result_row_context_and_existing_entry(self) -> None:
        self.assertIn('.accessibilityLabel("图片文字块 \\(accessibilityOriginalText)")', self.row)
        self.assertIn(".accessibilityValue(accessibilityValue)", self.row)
        self.assertIn(".accessibilityHint(accessibilityHint)", self.row)
        self.assertIn('equals: "image-review-row-\\(block.id.uuidString)"', self.row)
        self.assertIn("Button(action: select)", self.row)
        self.assertIn("restoreVisionOCR", self.row)

    def test_restore_action_is_view_only_and_reuses_existing_store_entry(self) -> None:
        self.assertNotIn("ImageReviewRowRestoreAccessibilityModifier", self.store)
        self.assertNotIn("runImageTranslationPipeline", self.row)
        self.assertNotIn("VisionOCRService", self.row)
        self.assertNotIn("MangaOverlayProbeService", self.row)

    def test_version_and_ci_route_follow_v3140(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 141) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.140;", self.project)
        old = "scripts/test-v3140-image-review-row-edit-action-contract.py"
        new = "scripts/test-v3141-image-review-row-restore-action-contract.py"
        self.assertIn(f"python3 -B {old}", self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(f"python3 -B {old}"), self.workflow.index(f"python3 -B {new}"))
        self.assertIn("14[0]", self.workflow)
        self.assertIn("14[1]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
