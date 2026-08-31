#!/usr/bin/env python3
"""Static and pure-policy contract for v3.378 Japanese standard translation prompts."""

from pathlib import Path
import re
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


def japanese_pair_instruction(source: str, target: str) -> str | None:
    pairs = {
        ("日语", "简体中文"): (
            "源语言是日语，目标语言是简体中文。",
            "只输出译文，不输出日语原文、解释、注释、罗马音或提示词。",
        ),
        ("日语", "英语(美国)"): (
            "The source language is Japanese and the target language is English.",
            "Output only the translation, without the Japanese source, explanations, notes, romanization, or prompt text.",
        ),
    }
    pair = pairs.get((source, target))
    if pair is None:
        return None
    return " ".join(pair)


class JapaneseStandardTranslationPromptContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("README.md")
            + read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("update_log.md")
        )

    def test_japanese_standard_pairs_are_explicit_and_plain_text(self) -> None:
        body = function_body(
            self.gemma,
            "private func translationPromptBodies(for request: ModelGenerationRequest)",
        )
        for marker in (
            "let japaneseLanguagePairInstruction: String?",
            "case (.japanese, .simplifiedChinese):",
            "case (.japanese, .englishUS):",
            "源语言是日语，目标语言是简体中文",
            "The source language is Japanese and the target language is English",
            "只输出译文，不输出日语原文、解释、注释、罗马音或提示词",
            "Output only the translation, without the Japanese source, explanations, notes, romanization, or prompt text",
            "if let japaneseLanguagePairInstruction",
            "用户补充要求：\\(instruction)",
            "\\(request.inputText)",
        ):
            self.assertIn(marker, body)

        self.assertIn("request.translationProfile == .mangaBlocks", body)
        self.assertIn("必须原样保留每个 [N] 标签", body)
        self.assertIn("不要合并、拆分、遗漏或重排文字块", body)

    def test_pair_policy_covers_supported_free_targets_only(self) -> None:
        self.assertIn("源语言是日语，目标语言是简体中文。", japanese_pair_instruction("日语", "简体中文"))
        self.assertIn("The source language is Japanese", japanese_pair_instruction("日语", "英语(美国)"))
        self.assertIsNone(japanese_pair_instruction("英语(美国)", "简体中文"))
        self.assertIsNone(japanese_pair_instruction("日语", "法语"))

    def test_single_block_fallback_keeps_scoped_plain_translation_qa(self) -> None:
        body = function_body(
            self.store,
            "private func translateJapaneseImageBlockWithQA(",
        )
        for marker in (
            "let candidate = try await translate(",
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "japaneseTranslationQAConfiguration(",
            "try Task.checkCancellation()",
            "throw ImageMangaBatchTranslationError.qualityFailure([expectedID])",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("translationProfile: .mangaBlocks", body)

        translate_body = function_body(
            self.store,
            "private func translate(\n        _ text: String,",
        )
        self.assertIn("translationContext: TranslationPromptContext? = nil", self.store)
        self.assertIn("translationContext: translationContext", translate_body)
        self.assertNotIn("recognizeTextBlocks(in: data", body)

    def test_batch_tag_path_and_image_budget_are_unchanged(self) -> None:
        batch_body = function_body(
            self.store,
            "private static func imageTranslationBatches(",
        )
        for marker in ("let maximumBlocks = 8", "let maximumCharacters = 1_800"):
            self.assertIn(marker, batch_body)

        for marker in (
            "translationProfile: .mangaBlocks",
            "TranslationBatchQualityEvaluator.evaluate(",
            "translateJapaneseImageBlockWithQA(",
        ):
            self.assertIn(marker, self.store)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.378", "3.378"],
        )
        self.assertIn(
            "python3 -B scripts/test-v3363-japanese-standard-translation-prompt-contract.py",
            self.workflow,
        )
        for marker in (
            "scripts/test-v3363-japanese-standard-translation-prompt-contract.py",
            "v3.378",
            "japanese-benchmark-v3.378-",
        ):
            self.assertIn(marker, self.workflow + self.docs)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3363-japanese-standard-translation-prompt-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
