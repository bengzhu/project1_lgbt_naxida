#!/usr/bin/env python3
"""Contract for discoverable image OCR block rerecognition VoiceOver hints."""

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


class ImageOCRRerecognitionAccessibilityHintContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.focus_hint = braced_body(
            self.view,
            "private var focusPreviewAccessibilityHint: String",
        )
        self.focus_modification = braced_body(
            self.view,
            "private func focusPreviewModificationHint(",
        )
        self.row_hint = braced_body(
            self.view,
            "private func rowAccessibilityHint(",
        )
        self.rerecognition_modifier = braced_body(
            self.view,
            "private struct ImageReviewRowRerecognitionAccessibilityModifier",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_row_hint_matches_the_enabled_action_gate(self) -> None:
        self.assertIn("if canRerecognize && !isRerecognizing", self.row_hint)
        self.assertIn("重新识别此文字块", self.row_hint)
        self.assertIn("if canRerecognize && !isRerecognizing", self.rerecognition_modifier)
        self.assertIn("accessibilityAction(named: \"重新识别此文字块\")", self.view)

    def test_focus_preview_appends_actions_after_every_geometry_branch(self) -> None:
        self.assertIn("if focusCrop == nil", self.focus_hint)
        self.assertIn("} else if canEdit {", self.focus_hint)
        self.assertIn("let modificationHint = focusPreviewModificationHint(appendingTo: base)", self.focus_hint)
        self.assertIn("return reviewAccessibilityHint(appendingTo: modificationHint)", self.focus_hint)
        self.assertNotIn("return focusPreviewModificationHint(", self.focus_hint)

    def test_focus_action_hint_respects_busy_and_edit_gates(self) -> None:
        self.assertIn("if canRerecognize || isRerecognizing", self.focus_modification)
        self.assertIn("正在重新识别此文字块", self.focus_modification)
        self.assertIn("也可执行“重新识别此文字块”", self.focus_modification)
        self.assertIn("guard isManuallyCorrected, canEdit else { return detail }", self.focus_modification)
        self.assertIn("也可执行“恢复 Vision OCR”", self.focus_modification)

    def test_view_only_boundary_does_not_add_pipeline_calls(self) -> None:
        self.assertNotIn("recognizeTextBlocks(", self.view)
        self.assertEqual(self.view.count("rerecognize()"), 2)

    def test_version_and_ci_route_follow_v3252(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 253) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.252;", self.project)
        previous = "python3 -B scripts/test-v3252-image-japanese-compact-crop-recovery-contract.py"
        current = "python3 -B scripts/test-v3253-image-ocr-rerecognition-accessibility-hint-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3253-image-ocr-rerecognition-accessibility-hint-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
