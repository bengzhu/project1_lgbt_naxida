#!/usr/bin/env python3
"""Static contract for v3.357 Japanese kana SFX translation hints."""

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


class JapaneseSFXTranslationRecallContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.test_log = read("md/test/test.md")
        cls.update_log = read("update_log.md")

    def test_classifier_keeps_old_gate_and_adds_kana_sfx_shapes(self) -> None:
        body = function_body(
            self.context,
            "static func inferJapaneseKind(\n",
        )
        for marker in (
            "boundingBox.normalizedToUnit()",
            "(2...12).contains(compact.count)",
            "japaneseLetters.count >= 2",
            "katakanaRatio >= 0.65",
            "let kanaLetters = japaneseLetters.filter",
            "0x3041...0x309F",
            "0x2025, 0x2026, 0x30FC",
            "hasRepeatedKatakana",
            "hasRepeatedKanaUnit",
            "hasRepeatedKana",
            "hasKatakanaMarkerShape",
            "hasShortMarkerShape",
            "hasSmallTsuEnding",
            "return .sfx",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("return .narration", body)
        self.assertNotIn("return .title", body)
        self.assertNotIn("return .dialogue", body)

    def test_shape_policy_is_conservative_and_dialogue_quotes_still_win(self) -> None:
        body = function_body(
            self.context,
            "static func inferJapaneseKind(\n",
        )
        self.assertIn("guard !hasDialogueQuote else { return nil }", body)
        self.assertIn("kanaRatio >= 0.65", body)
        self.assertIn("japaneseLetters.count <= 4", body)
        self.assertIn("japaneseLetters.count <= 2", body)
        self.assertIn("japaneseLetters.last.map", body)
        self.assertIn("0x3063, 0x30C3, 0xFF6F", body)
        self.assertIn("hasSoundEffectMarker\n            &&", body)
        self.assertIn("kanaValues.count.isMultiple(of: 2)", body)

    def test_sfx_prompt_preserves_short_manga_style(self) -> None:
        prompt_body = function_body(
            self.context,
            "func promptSection() -> String {",
        )
        for marker in (
            "context.textKind == .sfx",
            "context.batchTextKinds.contains(.sfx)",
            "拟声词/状态字",
            "保留节奏",
            "不要补写主语",
            "不要扩写成完整句子",
        ):
            self.assertIn(marker, prompt_body)
        manga_prompt = function_body(
            self.gemma,
            "private func translationPromptBodies(for request: ModelGenerationRequest) -> [String] {",
        )
        self.assertIn("拟声词/状态字", manga_prompt)
        self.assertIn("不补写主语或解释动作", manga_prompt)

    def test_kind_remains_metadata_only_and_uses_existing_translation_path(self) -> None:
        self.assertIn(
            "TranslationTextKindClassifier.inferJapaneseKind(",
            self.vision,
        )
        self.assertIn("Self.imageTranslationBatches(recognizedBlocks)", self.store)
        self.assertIn("translationContext: TranslationPromptContext(", self.store)
        self.assertIn("batchTextKinds: batchTextKinds", self.store)
        self.assertIn("var textKind: TranslationTextKind?", self.models)
        self.assertNotIn("recognizeTextBlocks(in: data", self.vision)
        self.assertNotIn("maximumJapanese", self.context)

    def test_ocr_translation_budget_and_safety_boundaries_are_unchanged(self) -> None:
        combined = self.vision + self.store
        for marker in (
            "maximumJapaneseMangaLineOCRRequests",
            "maximumJapaneseWeakBlockRecoveryRequests",
            "maximumBlocks = 8",
            "maximumCharacters = 1_800",
            "ImageMangaBatchTranslationError",
            "TranslationBatchQualityEvaluator",
            "try Task.checkCancellation()",
            "persist()",
        ):
            self.assertIn(marker, combined)
        self.assertNotIn("test/3.png", self.context)

    def test_version_workflow_and_route_record_are_current(self) -> None:
        combined = self.workflow + self.route + self.flow + self.test_log + self.update_log
        for marker in (
            "scripts/test-v3357-japanese-sfx-translation-recall-contract.py",
            "v3.357",
            "japanese-benchmark-v3.357-",
            "普通图片 OCR→日语翻译是持续推进的主线",
            "test/3.png",
        ):
            self.assertIn(marker, combined)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.372", "3.372"],
        )

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3357-japanese-sfx-translation-recall-contract.py")
        for source in (self.context, self.gemma, self.vision, self.store, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
