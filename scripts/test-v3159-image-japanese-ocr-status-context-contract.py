#!/usr/bin/env python3
"""Contract for Japanese-aware OCR progress context in the image pipeline."""

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


class JapaneseOCRStatusContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.views = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.message = braced_body(
            self.store,
            "private func imageOCRRecognitionMessage(for sourceLanguage: SupportedLanguage)",
        )
        self.pipeline = braced_body(
            self.store,
            "private func runImageTranslationPipeline(",
        )

    def test_japanese_progress_explains_vertical_review_and_generic_path_remains(self) -> None:
        self.assertIn("sourceLanguage == .japanese", self.message)
        self.assertIn("识别日语文字，复查竖排方向与文字块位置", self.message)
        self.assertIn("正在用 Vision 本机 OCR 识别文字和位置", self.message)
        self.assertIn(
            "imageTranslationMessage = imageOCRRecognitionMessage(for: sourceLanguage)",
            self.pipeline,
        )

    def test_status_is_set_after_recognizing_and_view_consumes_store_message(self) -> None:
        self.assertLess(
            self.pipeline.index("imageTranslationState = .recognizing"),
            self.pipeline.index("imageTranslationMessage = imageOCRRecognitionMessage"),
        )
        self.assertIn("case .loading, .recognizing, .translating:", self.views)
        self.assertIn("store.imageTranslationMessage", self.views)

    def test_context_change_does_not_duplicate_ocr_or_persist_status(self) -> None:
        self.assertEqual(
            self.store.count("imageOCRRecognitionMessage(for: sourceLanguage)"),
            1,
        )
        self.assertNotIn("visionOCRService.recognizeTextBlocks", self.message)
        self.assertNotIn("TranslationSessionStore", self.message)
        self.assertNotIn("persist()", self.message)

    def test_version_and_ci_route_follow_v3158(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 159) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.158;", self.project)
        old = "python3 -B scripts/test-v3158-image-japanese-crop-ocr-contract.py"
        new = "python3 -B scripts/test-v3159-image-japanese-ocr-status-context-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn("15[9]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
