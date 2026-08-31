#!/usr/bin/env python3
"""Contract for durable feedback after cancelling one OCR block reread."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def catch_body(source: str, function_marker: str) -> str:
    function_start = source.index(function_marker)
    catch_start = source.index("} catch is CancellationError {", function_start)
    catch_end = source.index("} catch {", catch_start)
    return source[catch_start:catch_end]


class ScopedCancelPersistenceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.cancel_catch = catch_body(
            cls.store,
            "func rerecognizeImageTranslationBlock(",
        )

    def test_cancel_restores_state_and_persists_the_user_visible_status(self) -> None:
        for marker in [
            "self.imageTranslationState = previousState",
            "self.isProcessing = false",
            "self.imageTranslationMessage = \"此图片文字块重新识别已取消\"",
            "self.dataTransferMessage = self.imageTranslationMessage",
            "self.imageTranslationBlockRerecognitionFailureGeneration &+= 1",
            "self.persist()",
        ]:
            self.assertIn(marker, self.cancel_catch)

    def test_cancel_does_not_clear_the_full_image_session(self) -> None:
        for forbidden in [
            "self.imageTranslationReviewedBlockIDs = []",
            "self.imageTranslationTaskID = UUID()",
            "self.imageTranslationState = .idle",
            "self.invalidateImageTranslationBlockRerecognition()",
        ]:
            self.assertNotIn(forbidden, self.cancel_catch)

    def test_route_and_version_are_advanced(self) -> None:
        current = "python3 -B scripts/test-v3269-image-ocr-scoped-cancel-persistence-contract.py"
        self.assertIn(current, self.workflow)
        self.assertIn(
            "if grep -Fx 'scripts/test-v3269-image-ocr-scoped-cancel-persistence-contract.py'",
            self.workflow,
        )
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project),
            ["3.371", "3.371"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
