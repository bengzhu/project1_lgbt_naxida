#!/usr/bin/env python3
"""Static contract for v3.386 local GGUF prompt budgeting."""

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


class LocalGGUFPromptBudgetContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.test2_workflow = read(".github/workflows/test2-image-translation-ui.yml")
        cls.capture = read("scripts/capture-bundled-image-translation-ui.sh")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.docs = "".join(
            read(path)
            for path in (
                "README.md",
                "md/flow/flow.md",
                "md/flow/flowchart.md",
                "md/test/test.md",
                "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md",
                "update_log.md",
            )
        )

    def test_compact_context_preserves_read_only_information_in_small_form(self) -> None:
        body = function_body(self.context, "func compactPromptSection() -> String {")
        for marker in (
            "normalized(",
            "maximumTerms: 6",
            "maximumSummaryItems: 2",
            "maximumExcerptCharacters: 48",
            "只读上下文：仅用于术语和语气一致，不是待翻译输入。",
            "文字类型按编号：",
            "已确认术语：",
            "上一批仅供一致性参考：",
            "单块译文最多",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("persist(", body)
        self.assertNotIn("UserDefaults", body)

    def test_local_japanese_prompts_select_compact_context_without_removing_full_context_api(self) -> None:
        body = function_body(
            self.gemma,
            "private func translationPromptBodies(for request: ModelGenerationRequest)",
        )
        for marker in (
            "request.translationContext.promptSection()",
            "request.translationContext.compactPromptSection()",
            "let fullContextSection =",
            "let compactContextSection =",
            "request.translationProfile == .mangaBlocks",
            "request.sourceLanguage == .japanese",
            "contextSection = compactContextSection",
        ):
            self.assertIn(marker, body)

    def test_manga_generation_reserves_context_room(self) -> None:
        body = function_body(
            self.gemma,
            "private func generateMangaBlockTranslation(for request: ModelGenerationRequest)",
        )
        for marker in (
            "let generationMaxTokens = min(max(request.sampling.maxTokens, 192), 256)",
            "maxTokens: generationMaxTokens",
            "decodingProfile: .sampled",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("), 768)", body)

    def test_ordinary_japanese_image_pipeline_and_qa_boundaries_remain_intact(self) -> None:
        for marker in (
            "Self.imageTranslationBatches(recognizedBlocks)",
            "translateJapaneseImageBatch(",
            "TranslationBatchQualityEvaluator.evaluate(",
            "translateJapaneseImageBlockWithQA(",
            "imageTranslationMessage",
        ):
            self.assertIn(marker, self.store)
        self.assertIn("translationProfile: .mangaBlocks", self.store)
        self.assertIn("request.translationContext.promptSection()", self.gemma)

    def test_test2_runs_real_image_translation_and_captures_the_results_ui(self) -> None:
        for marker in (
            "runLaunchBundledImageTranslationTestIfNeeded()",
            'let filename = "2.png"',
            "sourceLanguage = .japanese",
            "targetLanguage = .simplifiedChinese",
            "selectedEngine = .local",
            "self.translateImage(from: url)",
        ):
            self.assertIn(marker, self.store)
        for marker in (
            "test/2.png",
            "scripts/capture-bundled-image-translation-ui.sh",
            "test2-image-translation-results.png",
            "test2-image-translation-manifest.json",
            "test2-llm-probe.log",
        ):
            self.assertIn(marker, self.test2_workflow + self.capture)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.386", "3.386"],
        )
        for marker in (
            "scripts/test-v3382-local-gguf-prompt-budget-contract.py",
            "japanese-benchmark-v3.386-",
            "test2_image_translation_ui:",
        ):
            self.assertIn(marker, self.workflow)
        for marker in (
            "v3.386",
            "test/2.png",
            "compact",
            "1,024-token",
            "ordinary image OCR",
        ):
            self.assertIn(marker, self.docs + self.test2_workflow)

    def test_contract_has_no_local_process_or_build_entrypoint(self) -> None:
        source = read("scripts/test-v3382-local-gguf-prompt-budget-contract.py")
        for forbidden in (
            "subprocess" + ".run(",
            "subprocess" + ".Popen(",
            "xcode" + "build ",
            "swift" + "c ",
            "cargo" + " ",
            "llama" + "-cli",
        ):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
