#!/usr/bin/env python3
"""Contract for a gated direct VoiceOver OCR-edit action on image result rows."""

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


class ImageReviewRowEditActionContractTests(unittest.TestCase):
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
            "private struct ImageReviewRowEditAccessibilityModifier",
        )

    def test_result_row_exposes_gated_edit_action(self) -> None:
        self.assertIn("let canEdit: Bool", self.modifier)
        self.assertIn("let edit: () -> Void", self.modifier)
        self.assertIn("if canEdit", self.modifier)
        self.assertIn('.accessibilityAction(named: "修正识别文字")', self.modifier)
        action = braced_body(
            self.modifier,
            '.accessibilityAction(named: "修正识别文字")',
        )
        self.assertIn("edit()", action)
        self.assertIn("ImageReviewRowEditAccessibilityModifier", self.row)
        self.assertIn("canEdit: canEdit", self.row)
        self.assertIn("edit: edit", self.row)

    def test_locked_rows_do_not_expose_direct_edit_action(self) -> None:
        locked_branch = self.modifier[self.modifier.index("} else {") :]
        self.assertNotIn('.accessibilityAction(named: "修正识别文字")', locked_branch)
        self.assertIn('Button("修正识别文字", systemImage: "pencil", action: edit)', self.row)
        self.assertIn(".disabled(!canEdit)", self.row)
        self.assertIn("编辑 OCR 原文并只重新翻译此文字块", self.row)
        self.assertIn("modificationUnavailableHint", self.row)

    def test_result_row_keeps_location_and_focus_context(self) -> None:
        self.assertIn('.accessibilityLabel("图片文字块 \\(accessibilityOriginalText)")', self.row)
        self.assertIn(".accessibilityValue(accessibilityValue)", self.row)
        self.assertIn(".accessibilityHint(accessibilityHint)", self.row)
        self.assertIn('equals: "image-review-row-\\(block.id.uuidString)"', self.row)
        self.assertIn("Button(action: select)", self.row)
        self.assertIn("action: edit", self.row)

    def test_edit_action_is_view_only(self) -> None:
        self.assertNotIn("ImageReviewRowEditAccessibilityModifier", self.store)
        self.assertNotIn("runImageTranslationPipeline", self.row)
        self.assertNotIn("VisionOCRService", self.row)
        self.assertNotIn("MangaOverlayProbeService", self.row)

    def test_version_and_ci_route_follow_v3139(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 140) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.139;", self.project)
        old = "scripts/test-v3139-image-focus-navigation-action-contract.py"
        new = "scripts/test-v3140-image-review-row-edit-action-contract.py"
        self.assertIn(f"python3 -B {old}", self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(f"python3 -B {old}"), self.workflow.index(f"python3 -B {new}"))
        self.assertIn("13[0-9]", self.workflow)
        self.assertIn("14[0]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
