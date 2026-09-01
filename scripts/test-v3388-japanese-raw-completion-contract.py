#!/usr/bin/env python3
"""Static contract for v3.388's Japanese raw-completion translation fallback."""

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


class JapaneseRawCompletionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.test2_workflow = read(".github/workflows/test2-image-translation-ui.yml")
        cls.capture = read("scripts/capture-bundled-image-translation-ui.sh")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.docs = "".join(
            read(relative)
            for relative in (
                "README.md",
                "md/flow/flow.md",
                "md/flow/flowchart.md",
                "md/test/test.md",
                "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md",
                "update_log.md",
            )
        )

    def test_raw_completion_precedes_chat_fallback_and_reuses_qa(self) -> None:
        body = function_body(
            self.gemma,
            "private func generateTranslation(for request: ModelGenerationRequest)",
        )
        raw_start = body.index("japaneseRawCompletionPrompt(for: request)")
        chat_start = body.index("translationMessages(for: request)")
        self.assertLess(raw_start, chat_start)
        for marker in (
            "Self.runtime.generateRaw(",
            "decodingProfile: .sampled",
            "cleanTranslationOutput(",
            "local-raw-attempt-start",
            "local-raw-attempt-error",
            "max(1, min(request.sampling.maxTokens, 160))",
        ):
            self.assertIn(marker, body)
        self.assertIn("if request.translationProfile == .mangaBlocks", body)
        self.assertLess(
            body.index("if request.translationProfile == .mangaBlocks"),
            raw_start,
        )

    def test_raw_prompt_is_narrow_and_language_pair_specific(self) -> None:
        body = function_body(
            self.gemma,
            "private func japaneseRawCompletionPrompt(for request: ModelGenerationRequest)",
        )
        for marker in (
            "switch (request.sourceLanguage, request.targetLanguage)",
            'return "日语：\\(request.inputText)\\n简体中文："',
            'return "Japanese: \\(request.inputText)\\nEnglish:"',
            "default:",
            "return nil",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("translationContext", body)
        self.assertNotIn("translationProfile", body)

    def test_existing_manga_batch_and_qa_boundaries_remain(self) -> None:
        for marker in (
            "generateMangaBlockTranslation(for request:",
            "cleanMangaBlockOutput(",
            "translateJapaneseImageBlockWithQA(",
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "japaneseTranslationQAConfiguration(",
            "TranslationOutputPolicy",
            "let generationMaxTokens = min(max(request.sampling.maxTokens, 192), 256)",
        ):
            self.assertIn(marker, self.gemma + self.store)
        compact_body = function_body(self.context, "func compactPromptSection() -> String {")
        self.assertNotIn("persist(", compact_body)
        self.assertNotIn("UserDefaults", compact_body)

    def test_real_test2_route_and_version_are_current(self) -> None:
        for marker in (
            'let filename = "2.png"',
            "sourceLanguage = .japanese",
            "targetLanguage = .simplifiedChinese",
            "selectedEngine = .local",
            "scripts/capture-bundled-image-translation-ui.sh",
            "test2-image-translation-results.png",
            "test2-image-translation-manifest.json",
            "test2-image-translation-ocr.png",
            "test2-image-translation-ocr.txt",
            "ocrScreenshot",
        ):
            self.assertIn(marker, self.store + self.test2_workflow + self.capture)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.388", "3.388"],
        )
        for marker in (
            "scripts/test-v3387-japanese-bare-prompt-contract.py",
            "scripts/test-v3388-japanese-raw-completion-contract.py",
            "japanese-benchmark-v3.388-",
            "test2_image_translation_ui:",
        ):
            self.assertIn(marker, self.workflow)
        for marker in (
            "v3.388",
            "test/2.png",
            "原始补全",
            "raw-completion",
            "prompt",
        ):
            self.assertIn(marker, self.docs + self.test2_workflow)

    def test_contract_has_no_local_process_or_build_entrypoint(self) -> None:
        source = read("scripts/test-v3388-japanese-raw-completion-contract.py")
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
