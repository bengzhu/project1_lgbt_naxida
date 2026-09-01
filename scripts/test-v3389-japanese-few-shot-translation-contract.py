#!/usr/bin/env python3
"""Static contract for v3.389's Japanese few-shot translation fallback."""

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


class JapaneseFewShotTranslationContractTests(unittest.TestCase):
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
                "md/人工空间/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md",
                "md/log/update_log.md",
            )
        )

    def test_chat_candidates_run_before_raw_fallback(self) -> None:
        body = function_body(
            self.gemma,
            "private func generateTranslation(for request: ModelGenerationRequest)",
        )
        chat_start = body.index("translationMessages(for: request)")
        raw_start = body.index("japaneseRawCompletionPrompt(for: request)")
        self.assertLess(chat_start, raw_start)
        for marker in (
            "Self.runtime.generate(",
            "decodingProfile: .sampled",
            "cleanTranslationOutput(",
            "local-attempt-start",
            "local-attempt-error",
            "Self.runtime.generateRaw(",
            "cleanJapaneseRawCompletionOutput(",
            "local-raw-attempt-start",
            "local-raw-attempt-error",
            "max(1, min(request.sampling.maxTokens, 160))",
        ):
            self.assertIn(marker, body)
        self.assertIn("if request.translationProfile == .mangaBlocks", body)
        self.assertLess(
            body.index("if request.translationProfile == .mangaBlocks"),
            chat_start,
        )

    def test_raw_completion_is_strictly_single_line_and_metadata_free(self) -> None:
        body = function_body(
            self.gemma,
            "private func cleanJapaneseRawCompletionOutput(",
        )
        for marker in (
            'raw.contains("\\n")',
            'raw.contains("\\r")',
            "metadataMarkers",
            "日本語：",
            "日语：",
            "Japanese:",
            "简体中文：",
            "Simplified Chinese:",
            "English:",
            "localizedCaseInsensitiveContains",
            "cleanTranslationOutput(",
        ):
            self.assertIn(marker, body)

    def test_few_shot_prompt_is_pair_specific_and_first_chat_candidate(self) -> None:
        body = function_body(
            self.gemma,
            "private func translationPromptBodies(for request: ModelGenerationRequest)",
        )
        japanese_branch = body.index("if let japaneseLanguagePairInstruction")
        japanese_body = body[japanese_branch:]
        first_return = body.index("return [", japanese_branch)
        first_candidate = body[first_return :]
        for marker in (
            "japaneseFewShotFallbackInstruction",
            "Answer:",
        ):
            self.assertIn(marker, first_candidate)
        for marker in (
            "Use the examples only as translation hints.",
            "Output only the final Chinese translation; do not output labels, explanations, or the examples.",
            "Example Japanese: ありがとう",
            "Example Simplified Chinese: 谢谢",
            "Example Japanese: つかれた",
            "Example Simplified Chinese: 累了",
            "Final Japanese:",
        ):
            self.assertIn(marker, japanese_body)
        self.assertIn("Example English: Thank you.", japanese_body)
        self.assertIn("Example English: Tired.", japanese_body)
        self.assertLess(
            first_candidate.index("japaneseFewShotFallbackInstruction)"),
            first_candidate.index("japaneseLanguagePairInstruction)"),
        )

    def test_existing_qa_manga_and_context_boundaries_remain(self) -> None:
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
            ["3.390", "3.390"],
        )
        for marker in (
            "scripts/test-v3388-japanese-raw-completion-contract.py",
            "scripts/test-v3389-japanese-few-shot-translation-contract.py",
            "japanese-benchmark-v3.389-",
            "test2_image_translation_ui:",
        ):
            self.assertIn(marker, self.workflow)
        for marker in (
            "v3.389",
            "test/2.png",
            "few-shot",
            "原始补全",
            "prompt",
        ):
            self.assertIn(marker, self.docs + self.test2_workflow)

    def test_contract_has_no_local_process_or_build_entrypoint(self) -> None:
        source = read("scripts/test-v3389-japanese-few-shot-translation-contract.py")
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
