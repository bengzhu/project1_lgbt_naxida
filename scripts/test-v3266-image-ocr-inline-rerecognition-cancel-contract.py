#!/usr/bin/env python3
"""Contract for cancelling one in-flight image OCR block rerecognition inline."""

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


class ImageOCRInlineRerecognitionCancelContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.view = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.focus_modifier = braced_body(
            cls.view,
            "private struct ImageFocusPreviewRerecognitionAccessibilityModifier",
        )
        cls.row_modifier = braced_body(
            cls.view,
            "private struct ImageReviewRowRerecognitionAccessibilityModifier",
        )
        cls.store_cancel = braced_body(
            cls.store,
            "func cancelImageTranslationBlockRerecognition()",
        )

    def test_preview_and_row_wire_the_existing_scoped_cancel_api(self) -> None:
        self.assertIn("let cancelRerecognize: (UUID) -> Void", self.view)
        self.assertIn("let cancelRerecognize: () -> Void", self.view)
        self.assertIn(
            "cancelRerecognize: { _ in\n                    store.cancelImageTranslationBlockRerecognition()",
            self.view,
        )
        self.assertIn(
            "cancelRerecognize: {\n                                store.cancelImageTranslationBlockRerecognition()",
            self.view,
        )
        self.assertEqual(
            self.view.count("store.cancelImageTranslationBlockRerecognition()"),
            2,
        )

    def test_busy_button_switches_from_rerecognize_to_cancel(self) -> None:
        for body in (self.focus_modifier, self.row_modifier):
            self.assertIn("if isRerecognizing", body)
            self.assertIn("取消重新识别此文字块", body)
            self.assertIn("accessibilityAction(named: \"取消重新识别此文字块\")", body)
            self.assertIn("accessibilityAction(named: \"重新识别此文字块\")", body)

        self.assertIn(
            "action: isRerecognizing ? cancelRerecognize : rerecognize",
            self.view,
        )
        self.assertIn(
            ".disabled(!canRerecognize && !isRerecognizing)",
            self.view,
        )
        self.assertIn("systemImage: isRerecognizing ? \"xmark.circle\"", self.view)
        self.assertIn("可取消当前文字块的重新识别", self.view)

    def test_store_cancel_is_scoped_and_preserves_session_cleanup_boundary(self) -> None:
        self.assertIn("guard imageTranslationRerecognizingBlockID != nil else { return }", self.store_cancel)
        self.assertIn("imageTranslationBlockRerecognitionTask?.cancel()", self.store_cancel)
        self.assertNotIn("cancelImageTranslation()", self.store_cancel)
        self.assertNotIn("imageTranslationTask?.cancel()", self.store_cancel)
        self.assertNotIn("imageTranslationReviewedBlockIDs = []", self.store_cancel)

    def test_busy_value_and_hint_explain_the_scoped_boundary(self) -> None:
        self.assertIn("正在重新识别此块，可取消当前文字块的重新识别", self.view)
        self.assertIn("取消只针对当前文字块的重新识别；保留其它 OCR、译文和复查进度", self.view)
        self.assertIn("VoiceOver 可执行：", self.view)
        self.assertIn("取消重新识别此文字块", self.view)

    def test_view_only_change_does_not_start_pipeline_or_call_global_cancel(self) -> None:
        self.assertNotIn("recognizeTextBlocks(", self.view)
        self.assertNotIn("cancelImageTranslation()", self.view)
        self.assertEqual(self.view.count("rerecognize()"), 2)

    def test_rotated_japanese_reconnaissance_preserves_column_direction_provenance(self) -> None:
        vision = read("AITRANS/Services/VisionOCRService.swift")
        mapper = braced_body(vision, "private static func mapRotatedObservation(")
        for marker in [
            "let directionRect = originalLineRegionRect ?? originalRect",
            "japaneseScriptDensity(in: observation.text) >= 0.5",
            "directionRect.height / max(directionRect.width, 0.001) >= 1.05",
            "sourceDirectionHint: verticalSourceHint",
        ]:
            self.assertIn(marker, mapper)
        self.assertIn("sourceDirectionHint == .vertical", read("AITRANS/Services/ImageOCRLayoutEngine.swift"))

    def test_version_and_ci_route_follow_v3265(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.352", "3.352"])
        previous = "python3 -B scripts/test-v3265-koharu-vision-vertical-quad-warp-contract.py"
        current = "python3 -B scripts/test-v3266-image-ocr-inline-rerecognition-cancel-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3266-image-ocr-inline-rerecognition-cancel-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
