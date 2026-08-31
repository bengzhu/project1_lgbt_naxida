#!/usr/bin/env python3
"""Static contract for v3.301 conservative Japanese SFX kind hints."""

from __future__ import annotations

import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


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
                return source[brace + 1 : index]
    raise AssertionError(f"unterminated function body: {signature}")


class JapaneseSFXKindInferenceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.runtime = read("scripts/test-v3214-image-japanese-manga-ocr-runtime.sh")
        cls.runtime_harness = read(
            "scripts/fixtures/v3214-manga-ocr-runtime-harness.swift"
        )
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.update_log = read("update_log.md")
        cls.test_log = read("md/test/test.md")

    def test_classifier_requires_high_signal_sfx_shape(self) -> None:
        body = function_body(
            self.context,
            "static func inferJapaneseKind(\n",
        )
        for marker in (
            "boundingBox.normalizedToUnit()",
            "(2...12).contains(compact.count)",
            "japaneseLetters.count >= 2",
            "katakanaRatio >= 0.65",
            "hasSoundEffectMarker",
            "hasRepeatedKatakana",
            "return .sfx",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("return .narration", body)
        self.assertNotIn("return .title", body)
        self.assertNotIn("return .dialogue", body)

    def test_only_new_japanese_page_blocks_receive_inferred_kind(self) -> None:
        layout_start = self.vision.index(
            "let laidOutBlocks = { () -> [ImageTranslationBlock] in"
        )
        recovery_start = self.vision.index(
            "let blocks = sourceLanguage == .japanese\n"
        )
        page_block_creation = self.vision[layout_start:recovery_start]
        self.assertIn("var imageBlock = ImageTranslationBlock(", page_block_creation)
        self.assertIn("if sourceLanguage == .japanese", page_block_creation)
        self.assertIn(
            "TranslationTextKindClassifier.inferJapaneseKind(",
            page_block_creation,
        )
        self.assertIn("text: imageBlock.original", page_block_creation)
        self.assertIn("boundingBox: imageBlock.boundingBox", page_block_creation)
        self.assertIn("recoverWeakJapaneseBlocks", self.vision)

    def test_kind_is_persisted_semantic_state_and_legacy_default_stays_optional(self) -> None:
        self.assertIn("var textKind: TranslationTextKind?", self.models)
        self.assertIn("&& lhs.textKind == rhs.textKind", self.models)
        self.assertIn("textKind: TranslationTextKind? = nil", self.models)
        self.assertIn("ambigu", self.context)
        self.assertNotIn("textKind: .narration", self.vision)
        self.assertNotIn("textKind: .title", self.vision)

    def test_existing_ocr_translation_boundaries_are_unchanged(self) -> None:
        for marker in (
            "ImageOCRLayoutEngine.layout(",
            "Self.imageTranslationBatches(recognizedBlocks)",
            "maximumJapaneseWeakBlockRecoveryRequests",
            "maximumBlocks = 8",
            "maximumCharacters = 1_800",
        ):
            source = self.vision + read("AITRANS/Services/TranslationSessionStore.swift")
            self.assertIn(marker, source)
        self.assertNotIn("recognizeTextBlocks(in: data", self.vision)

    def test_cloud_runtime_harness_receives_the_new_kind_dependency(self) -> None:
        self.assertIn("TranslationContextQuality.swift in Sources", self.project)
        runtime_harnesses = (
            (
                "scripts/test-v3214-image-japanese-manga-ocr-runtime.sh",
                "scripts/fixtures/v3214-manga-ocr-runtime-harness.swift",
            ),
            (
                "scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh",
                "scripts/fixtures/v3218-long-page-manga-ocr-runtime-harness.swift",
            ),
            (
                "scripts/test-v3238-image-japanese-quad-bbox-fallback-runtime.sh",
                "scripts/fixtures/v3238-manga-ocr-quad-bbox-fallback-runtime-harness.swift",
            ),
            (
                "scripts/test-v3239-image-japanese-manga-ocr-bbox-primary-runtime.sh",
                "scripts/fixtures/v3239-manga-ocr-bbox-primary-runtime-harness.swift",
            ),
            (
                "scripts/test-v3245-image-japanese-directional-manga-ocr-crop-runtime.sh",
                "scripts/fixtures/v3245-directional-manga-ocr-crop-runtime-harness.swift",
            ),
            (
                "scripts/test-v3254-image-japanese-region-diagnostic-runtime.sh",
                "scripts/fixtures/v3254-japanese-region-diagnostic-harness.swift",
            ),
        )
        harness_markers = (
            "enum SupportedLanguage: String, CaseIterable, Identifiable, Codable, Sendable",
            'case englishUS = "英语(美国)"',
            'case french = "法语"',
            'case german = "德语"',
            "var id: String { rawValue }",
            "func normalizedToUnit() -> Self?",
            "var textKind: TranslationTextKind? = nil",
        )
        for runtime_path, harness_path in runtime_harnesses:
            runtime = read(runtime_path)
            harness = read(harness_path)
            self.assertIn(
                '"$repo_root/AITRANS/Models/TranslationContextQuality.swift"',
                runtime,
                runtime_path,
            )
            self.assertIn(harness_path.removesuffix(".swift"), runtime, runtime_path)
            for marker in harness_markers:
                self.assertIn(marker, harness, harness_path)
            self.assertIn(runtime_path, self.workflow)
            self.assertIn(
                harness_path.removeprefix("scripts/fixtures/").removesuffix(".swift"),
                self.workflow,
                harness_path,
            )

    def test_version_workflow_and_docs_are_current(self) -> None:
        combined = self.workflow + self.route + self.flow + self.update_log + self.test_log
        for marker in (
            "scripts/test-v3301-japanese-sfx-kind-inference-contract.py",
            "v3.301",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, combined)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.376", "3.376"],
        )

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3301-japanese-sfx-kind-inference-contract.py")
        for source in (self.context, self.models, self.vision, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
