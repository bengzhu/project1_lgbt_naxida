#!/usr/bin/env python3
"""Static and pure-policy contract for v3.358 shared-Han model cleanup."""

from pathlib import Path
import re
import unicodedata
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


def comparable_text(value: str) -> str:
    folded = unicodedata.normalize("NFKC", value).casefold()
    return "".join(
        character
        for character in folded
        if not character.isspace()
        and not unicodedata.category(character).startswith("P")
    )


def is_han_only(value: str) -> bool:
    visible = [
        character
        for character in value
        if not character.isspace()
        and not unicodedata.category(character).startswith("P")
    ]
    return bool(visible) and all(
        0x3400 <= ord(character) <= 0x4DBF
        or 0x4E00 <= ord(character) <= 0x9FFF
        or 0xF900 <= ord(character) <= 0xFAFF
        for character in visible
    )


def allows_unchanged_japanese_han(
    source: str,
    output: str,
    source_language: str,
    target_language: str,
) -> bool:
    return (
        source_language == "ja"
        and target_language == "zh-CN"
        and len(comparable_text(source)) > 1
        and comparable_text(source) == comparable_text(output)
        and is_han_only(source)
    )


class JapaneseSharedHanModelCleanupContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.policy = read("AITRANS/Models/TranslationContextQuality.swift")
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

    def test_exception_is_narrow_and_language_bound(self) -> None:
        body = function_body(
            self.policy,
            "static func allowsUnchangedJapaneseHanTranslation(\n",
        )
        for marker in (
            "sourceLanguage == .japanese",
            "targetLanguage == .simplifiedChinese",
            "let normalizedSource = comparableText(source)",
            "let normalizedOutput = comparableText(output)",
            "normalizedSource.count > 1",
            "normalizedSource == normalizedOutput",
            "isSharedHanOnlyJapaneseSource(source)",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("normalizedOutput.contains(normalizedSource)", body)

    def test_standard_cleaner_passes_source_language_and_shared_policy(self) -> None:
        generation = function_body(
            self.gemma,
            "private func generateTranslation(for request: ModelGenerationRequest)",
        )
        self.assertIn("sourceLanguage: request.sourceLanguage", generation)
        declaration_start = self.gemma.index("private func cleanTranslationOutput(\n")
        declaration = self.gemma[
            declaration_start : self.gemma.index("{", declaration_start)
        ]
        cleaner = function_body(
            self.gemma,
            "private func cleanTranslationOutput(\n",
        )
        self.assertIn("sourceLanguage: SupportedLanguage", declaration)
        self.assertIn(
            "sourceLanguage: sourceLanguage,\n            targetLanguage: targetLanguage",
            cleaner,
        )
        validator = function_body(
            self.gemma,
            "private func validateTranslationOutput(\n",
        )
        self.assertIn(
            "TranslationOutputPolicy\n            .allowsUnchangedJapaneseHanTranslation(",
            validator,
        )
        self.assertIn("guard allowsUnchangedSharedHan", validator)

    def test_tagged_manga_cleaner_uses_same_per_block_policy(self) -> None:
        generation = function_body(
            self.gemma,
            "private func generateMangaBlockTranslation(for request: ModelGenerationRequest)",
        )
        self.assertIn("sourceLanguage: request.sourceLanguage", generation)
        self.assertIn("targetLanguage: request.targetLanguage", generation)
        declaration_start = self.gemma.index("private func cleanMangaBlockOutput(\n")
        declaration = self.gemma[
            declaration_start : self.gemma.index("{", declaration_start)
        ]
        cleaner = function_body(
            self.gemma,
            "private func cleanMangaBlockOutput(\n",
        )
        for marker in (
            "TranslationOutputPolicy\n                .allowsUnchangedJapaneseHanTranslation(",
            "source: sourceText",
            "output: translatedText",
            "allowsUnchangedSharedHan",
        ):
            self.assertIn(marker, cleaner)
        self.assertIn("sourceLanguage: SupportedLanguage", declaration)
        self.assertIn("targetLanguage: SupportedLanguage", declaration)
        self.assertIn("cleanMangaBlockOutput(", generation)

    def test_policy_matrix_preserves_leakage_rejections(self) -> None:
        self.assertTrue(allows_unchanged_japanese_han("日本", "日本", "ja", "zh-CN"))
        self.assertTrue(allows_unchanged_japanese_han("東京。", "東京", "ja", "zh-CN"))
        self.assertFalse(allows_unchanged_japanese_han("日", "日", "ja", "zh-CN"))
        self.assertFalse(allows_unchanged_japanese_han("日本の", "日本の", "ja", "zh-CN"))
        self.assertFalse(allows_unchanged_japanese_han("日本", "日本人", "ja", "zh-CN"))
        self.assertFalse(allows_unchanged_japanese_han("東京2", "東京2", "ja", "zh-CN"))
        self.assertFalse(allows_unchanged_japanese_han("東京", "東京", "ja", "en-US"))
        self.assertFalse(allows_unchanged_japanese_han("東京", "東京", "en-US", "zh-CN"))

    def test_qa_and_downstream_boundaries_remain_in_place(self) -> None:
        for marker in (
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "TranslationBatchQualityEvaluator.evaluate(",
            "TranslationOutputPolicy.isPlaceholderResponse",
            "translateJapaneseImageBlockWithQA(",
        ):
            self.assertIn(marker, self.store + self.policy)
        for source in (self.policy, self.gemma):
            for forbidden in (
                "VisionOCRService",
                "MangaOCRService.shared",
                "persist()",
                "groundTruth",
                "KOHARU_DATA_ROOT",
            ):
                self.assertNotIn(forbidden, source)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.385", "3.385"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3358-japanese-shared-han-model-cleanup-contract.py",
            "v3.358",
            "japanese-benchmark-v3.358-",
        ):
            self.assertIn(marker, combined)


if __name__ == "__main__":
    unittest.main(verbosity=2)
