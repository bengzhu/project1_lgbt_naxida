#!/usr/bin/env python3
"""Contract for isolating Manga OCR crop failures without hiding cancellation."""

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


class JapaneseMangaOCRResilienceContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOCRService.swift")
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.views = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.recognize = braced_body(self.service, "func recognize(")
        self.recognize_crops = braced_body(
            self.service,
            "private func recognizeCrops(",
        )
        self.manga = braced_body(
            self.vision,
            "private static func recognizeJapaneseMangaOCR(",
        )
        self.message = braced_body(
            self.store,
            "private func imageOCRRecognitionMessage(for sourceLanguage: SupportedLanguage)",
        )
        self.pipeline = braced_body(
            self.store,
            "private func runImageTranslationPipeline(",
        )

    def test_model_load_is_whole_batch_but_crop_failures_are_isolated(self) -> None:
        runtime_index = self.recognize.index("let runtime = try loadedRuntime()")
        loop_index = self.recognize.index("for request in requests {")
        self.assertLess(runtime_index, loop_index)
        crop_index = self.recognize.index("guard let cropped = Self.cropImages")
        self.assertLess(crop_index, self.recognize.index("try recognizeCrops("))
        self.assertGreaterEqual(self.recognize.count("try recognizeCrops("), 2)
        self.assertIn("catch is CancellationError", self.recognize_crops)
        self.assertIn("throw CancellationError()", self.recognize_crops)
        self.assertIn("catch {", self.recognize_crops)
        self.assertIn("continue", self.recognize)
        self.assertIn("One malformed crop or model output", self.recognize_crops)
        self.assertIn("recognitions.append(nil)", self.recognize_crops)

    def test_manga_ocr_preserves_cancellation_and_vision_fallback(self) -> None:
        self.assertIn(") async throws -> [VisionOCRObservation]", self.vision)
        self.assertIn(
            "detectorMangaOCRObservations = try await Self.recognizeJapaneseMangaOCR(",
            self.vision,
        )
        self.assertIn("try await MangaOCRService.shared.recognize(", self.manga)
        self.assertIn("catch is CancellationError", self.manga)
        self.assertIn("throw CancellationError()", self.manga)
        self.assertIn("catch {", self.manga)
        self.assertIn("return []", self.manga)
        self.assertNotIn("try? await MangaOCRService.shared.recognize(", self.manga)
        self.assertIn("Self.recognizeJapaneseVerticalCrops(", self.vision)

    def test_status_copy_matches_the_actual_local_engines(self) -> None:
        self.assertIn("本机 Manga OCR 与 Vision", self.message)
        self.assertIn("正在用 Vision 本机 OCR 识别文字和位置", self.message)
        self.assertIn("本机 OCR 没有识别到可翻译文字", self.pipeline)
        self.assertIn("已完成本机 OCR、", self.store)
        self.assertIn("选择图片后，会用本机 OCR 识别文字并定位", self.store)
        self.assertNotIn("选择图片后，会用 Apple Vision 本机 OCR", self.store)
        self.assertIn("正在使用本机 OCR；可以取消或选择新图片", self.views)
        self.assertNotIn("正在使用 Vision 本机 OCR；", self.views)

    def test_version_and_ci_route_follow_v3223(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 224) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.223;", self.project)
        previous = "python3 -B scripts/test-v3223-image-japanese-detector-direction-provenance-contract.py"
        current = "python3 -B scripts/test-v3224-image-japanese-manga-ocr-resilience-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3224-image-japanese-manga-ocr-resilience-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
