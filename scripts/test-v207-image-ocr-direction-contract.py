#!/usr/bin/env python3
"""Contracts for v2.7 image OCR source-language and direction handling."""

from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing function signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unterminated function body: {signature}")


class ImageOCRDirectionContractTests(unittest.TestCase):
    def test_executable_layout_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v207-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v207-image-ocr-direction"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                    "AITRANS/Services/ImageOCRLayoutEngine.swift",
                    "scripts/test-v207-image-ocr-direction-evaluator.swift",
                    "-o", str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run([str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertIn("v2.7 image OCR direction evaluator passed", result.stdout)

    def test_vision_uses_conservative_direction_evidence(self) -> None:
        vision = read("AITRANS/Services/VisionOCRService.swift")
        engine = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.assertIn("sourceLanguage == .japanese || sourceLanguage == .simplifiedChinese", vision)
        self.assertIn("ImageOCRLayoutEngine.layout(", vision)
        self.assertIn("verticalRatio >= 1.6", engine)
        self.assertIn("height >= 0.035", engine)
        self.assertIn("hasColumnNeighbor && !hasRowNeighbor", engine)
        self.assertIn("horizontalCJKFragment", engine)
        self.assertIn("isolatedTallCJKBox", engine)

    def test_vertical_and_horizontal_layouts_are_isolated(self) -> None:
        engine = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        layout = function_body(engine, "static func layout(")
        self.assertIn("filter { $0.direction == .vertical }", layout)
        self.assertIn("filter { $0.direction != .vertical }", layout)
        self.assertIn("orderedHorizontalBands", engine)
        self.assertIn("orderedVerticalBands", engine)
        self.assertIn("mergeReadingOrder", engine)
        self.assertNotIn("clusterReadingOrder", engine)

    def test_product_layout_engine_is_in_the_app_target(self) -> None:
        project = read("AITRANS.xcodeproj/project.pbxproj")
        self.assertIn("ImageOCRLayoutEngine.swift in Sources", project)
        self.assertGreaterEqual(project.count("ImageOCRLayoutEngine.swift"), 4)

    def test_blocks_preserve_optional_direction_evidence(self) -> None:
        models = read("AITRANS/Models/TranscriptModels.swift")
        self.assertIn("enum ImageTextDirection: String, Codable, Sendable", models)
        self.assertIn("var sourceDirection: ImageTextDirection?", models)
        self.assertIn("var directionConfidence: Double?", models)
        self.assertIn("var directionReason: String?", models)

    def test_store_freezes_both_image_languages_before_loading(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        begin = function_body(store, "private func beginImageTranslationTask(")
        self.assertIn("imageTranslationContentSourceLanguage = sourceLanguage", begin)
        self.assertIn("imageTranslationContentTargetLanguage = targetLanguage", begin)
        self.assertLess(begin.index("imageTranslationContentSourceLanguage"), begin.index("imageTranslationState = .loading"))
        self.assertLess(begin.index("imageTranslationContentTargetLanguage"), begin.index("imageTranslationState = .loading"))

    def test_source_language_lifecycle_and_rerun_are_store_owned(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        selector = function_body(store, "func selectImageSourceLanguage(_ language: SupportedLanguage)")
        retry = function_body(store, "func retryImageTranslation()")
        clear = function_body(store, "func clearImageTranslation()")
        cancel = function_body(store, "func cancelImageTranslation()")
        self.assertIn("sourceLanguage = language", selector)
        self.assertIn("switch imageTranslationState", selector)
        self.assertIn("case .translated:", selector)
        self.assertIn("case .idle, .failed:", selector)
        self.assertIn("guard canRetryImageTranslation else { return }", selector)
        self.assertIn("FileManager.default.fileExists(atPath: url.path)", selector)
        self.assertIn("imageTranslationContentSourceLanguage = language", selector)
        self.assertIn("retryImageTranslation()", selector)
        self.assertEqual(selector.count("retryImageTranslation()"), 1)
        self.assertLess(selector.index("sourceLanguage = language"), selector.index("switch imageTranslationState"))
        translated_case = selector[
            selector.index("case .translated:"):selector.index("case .idle, .failed:")
        ]
        self.assertLess(
            translated_case.index("FileManager.default.fileExists(atPath: url.path)"),
            translated_case.index("imageTranslationContentSourceLanguage = language"),
        )
        self.assertLess(
            translated_case.index("imageTranslationContentSourceLanguage = language"),
            translated_case.index("retryImageTranslation()"),
        )
        retained_case = selector[
            selector.index("case .idle, .failed:"):
            selector.index("case .loading, .recognizing, .translating:")
        ]
        self.assertLess(
            retained_case.index("guard canRetryImageTranslation else { return }"),
            retained_case.index("imageTranslationContentSourceLanguage = language"),
        )
        self.assertNotIn("retryImageTranslation()", retained_case)
        running_case = selector[selector.index("case .loading, .recognizing, .translating:"):]
        self.assertIn("return", running_case)
        self.assertNotIn("imageTranslationContentSourceLanguage = language", running_case)
        self.assertNotIn("retryImageTranslation()", running_case)
        self.assertIn("imageTranslationContentSourceLanguage ?? sourceLanguage", retry)
        self.assertIn("imageTranslationContentTargetLanguage ?? targetLanguage", retry)
        self.assertIn("imageTranslationContentSourceLanguage = nil", clear)
        self.assertNotIn("imageTranslationContentSourceLanguage = nil", cancel)

    def test_view_exposes_source_and_target_language_credentials(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.assertIn("ImageSourceLanguageControl()", view)
        self.assertIn("store.selectImageSourceLanguage(language)", view)
        self.assertGreaterEqual(view.count("store.imageTranslationDisplayedSourceLanguage"), 4)
        self.assertIn('accessibilityLabel("输入语言")', view)
        self.assertIn("已完成的图片会重新识别和翻译", view)
        source_control = re.search(
            r"private struct ImageSourceLanguageControl: View \{(?P<body>.*?)"
            r"\n\}\n\nprivate struct ImageTargetLanguageControl",
            view,
            re.DOTALL,
        )
        self.assertIsNotNone(source_control)
        self.assertIn(".disabled(isRunning)", source_control.group("body"))

    def test_ci_runs_v27_after_share_lifecycle(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        v206 = workflow.index("scripts/test-v206-image-share-lifecycle-contract.py")
        v207 = workflow.index("scripts/test-v207-image-ocr-direction-contract.py")
        self.assertLess(v206, v207)
        step_start = workflow.index("- name: UI interaction contract")
        step_end = workflow.index("- name: v1.88 home UI contract", step_start)
        self.assertIn("set -euo pipefail", workflow[step_start:step_end])
        self.assertIn("ImageOCRLayoutEngine|TranslationSessionStore|VisionOCRService", workflow)
        self.assertIn("207-image-ocr-direction", workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
