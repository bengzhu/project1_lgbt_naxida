#!/usr/bin/env python3
"""Contract for scoped cancellation of one image translation block retry."""

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


class ImageTranslationBlockRetryCancelContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.view = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.retry = braced_body(cls.store, "func retryImageTranslationBlock(")
        cls.cancel = braced_body(cls.store, "func cancelImageTranslationBlockRetry(")
        cls.command_bar = braced_body(cls.view, "private struct ImageCommandBar: View")
        cls.focus = braced_body(cls.view, "private struct ImageTranslationFocusPreview: View")
        cls.row = braced_body(cls.view, "private struct ImageTranslationBlockRow: View")
        cls.retry_modifier = braced_body(
            cls.view,
            "private struct ImageReviewRowRetryAccessibilityModifier",
        )

    def test_cancel_is_scoped_and_restores_previous_terminal_state(self) -> None:
        for marker in [
            "let previousState = imageTranslationState",
            "imageTranslationBlockRetryPreviousState = previousState",
            "let restoredState = self.imageTranslationBlockRetryPreviousState ?? .failed",
            "self.imageTranslationState = restoredState",
            "self.imageTranslationMessage = \"已取消此文字块翻译重试，保留其它译文和复查进度\"",
            "self.persist()",
        ]:
            self.assertIn(marker, self.retry)
        self.assertIn("imageTranslationBlockRetryTask?.cancel()", self.cancel)
        self.assertNotIn("imageTranslationReviewedBlockIDs = []", self.retry)

    def test_command_bar_prioritizes_scoped_cancel_over_global_cancel(self) -> None:
        scoped = self.command_bar.index("store.imageTranslationRetryingBlockID != nil")
        global_cancel = self.command_bar.index("else if isRunning", scoped)
        self.assertLess(scoped, global_cancel)
        self.assertIn("action: store.cancelImageTranslationBlockRetry", self.command_bar)
        self.assertIn("取消当前文字块翻译重试", self.command_bar)

    def test_row_preview_and_voiceover_expose_the_same_cancel_action(self) -> None:
        for source in [self.focus, self.row, self.retry_modifier]:
            self.assertIn("cancelRetryTranslation", source)
        self.assertIn("action: isRetryingTranslation ? cancelRetryTranslation : retryTranslation", self.focus)
        self.assertIn("action: isRetryingTranslation ? cancelRetryTranslation : retryTranslation", self.row)
        self.assertIn(
            '.accessibilityAction(named: "取消此文字块翻译重试")',
            self.retry_modifier,
        )
        self.assertIn("取消只针对当前文字块的翻译重试", self.focus)

    def test_version_and_ci_route_follow_v3267(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.358", "3.358"])
        previous = "python3 -B scripts/test-v3267-koharu-manga-ocr-line-region-contract.py"
        current = "python3 -B scripts/test-v3267-image-translation-block-retry-cancel-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3267-image-translation-block-retry-cancel-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
