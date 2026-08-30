#!/usr/bin/env python3
"""Contract for cancelling one image OCR block without cancelling the session."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def function_body(source: str, marker: str) -> str:
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
    raise AssertionError(f"unclosed function body for {marker}")


class ScopedRerecognitionCancelContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.views = read("AITRANS/Views/ImageTranslationViews.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.scoped_cancel = function_body(
            self.store,
            "func cancelImageTranslationBlockRerecognition()",
        )
        self.global_cancel = function_body(
            self.store,
            "func cancelImageTranslation()",
        )

    def test_scoped_store_cancel_only_cancels_the_block_task(self) -> None:
        for marker in [
            "guard imageTranslationRerecognizingBlockID != nil else { return }",
            "imageTranslationBlockRerecognitionTask?.cancel()",
        ]:
            self.assertIn(marker, self.scoped_cancel)
        for forbidden in [
            "cancelImageTranslation()",
            "invalidateImageTranslationBlockRerecognition()",
            "imageTranslationReviewedBlockIDs = []",
            "imageTranslationTaskID = UUID()",
            "imageTranslationState = .idle",
        ]:
            self.assertNotIn(forbidden, self.scoped_cancel)

    def test_global_cancel_keeps_full_session_cleanup_boundary(self) -> None:
        for marker in [
            "imageTranslationTask?.cancel()",
            "imageTranslationBlockRerecognitionTask?.cancel()",
            "invalidateImageTranslationBlockRerecognition()",
            "imageTranslationReviewedBlockIDs = []",
            "imageTranslationTaskID = UUID()",
            "imageTranslationState = .idle",
        ]:
            self.assertIn(marker, self.global_cancel)

    def test_rerecognition_cancellation_catch_restores_state_and_publishes_failure(self) -> None:
        catch_start = self.store.index("} catch is CancellationError {", self.store.index("func rerecognizeImageTranslationBlock"))
        catch_body = self.store[catch_start : self.store.index("} catch {", catch_start)]
        for marker in [
            "guard self.imageTranslationBlockRerecognitionID == requestID",
            "self.imageTranslationRerecognizingBlockID = nil",
            "self.imageTranslationBlockRerecognitionTask = nil",
            "self.imageTranslationState = previousState",
            "self.isProcessing = false",
            "self.imageTranslationMessage = \"此图片文字块重新识别已取消\"",
            "self.imageTranslationBlockRerecognitionFailureGeneration &+= 1",
        ]:
            self.assertIn(marker, catch_body)
        self.assertNotIn("invalidateImageTranslationBlockRerecognition()", catch_body)

    def test_command_bar_routes_scoped_cancel_before_global_cancel(self) -> None:
        scoped_marker = "if store.imageTranslationRerecognizingBlockID != nil {"
        global_marker = "action: store.cancelImageTranslation"
        self.assertIn(scoped_marker, self.views)
        self.assertIn("title: \"取消重新识别\"", self.views)
        self.assertIn("action: store.cancelImageTranslationBlockRerecognition", self.views)
        self.assertIn("取消当前文字块重新识别；保留其它 OCR、译文和复查进度", self.views)
        self.assertLess(self.views.index(scoped_marker), self.views.index(global_marker))

    def test_status_explains_scoped_operation(self) -> None:
        for marker in [
            "正在重新识别当前图片文字块；可以取消此文字块操作，不会取消整张图片或清除复查进度",
            "当前图片文字块未替换，原文与复查进度已保留；可以继续复查或重新识别",
            "正在使用本机 OCR；可以取消或选择新图片",
        ]:
            self.assertIn(marker, self.views)

    def test_ci_route_and_version_are_advanced(self) -> None:
        previous = "python3 -B scripts/test-v3262-koharu-detector-triangle-contract.py"
        current = "python3 -B scripts/test-v3263-image-ocr-scoped-rerecognition-cancel-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3263-image-ocr-scoped-rerecognition-cancel-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.356", "3.356"])
        self.assertNotIn("MARKETING_VERSION = 3.262;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
