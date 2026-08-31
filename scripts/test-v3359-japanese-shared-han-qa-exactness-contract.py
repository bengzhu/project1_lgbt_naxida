#!/usr/bin/env python3
"""Static and pure-policy contract for v3.359 shared-Han QA exactness."""

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


def is_source_leakage(
    source: str,
    output: str,
    source_language: str,
    target_language: str,
) -> bool:
    normalized_source = comparable_text(source)
    normalized_output = comparable_text(output)
    if not normalized_source or normalized_source not in normalized_output:
        return False
    if (
        source_language == "ja"
        and target_language == "zh-CN"
        and is_han_only(source)
    ):
        return not allows_unchanged_japanese_han(
            source, output, source_language, target_language
        )
    return len(normalized_source) > 1


class JapaneseSharedHanQAExactnessContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
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

    def test_source_leakage_uses_exact_shared_han_exception(self) -> None:
        body = function_body(self.context, "private static func isSourceLeakage(\n")
        declaration_start = self.context.index("private static func isSourceLeakage(\n")
        declaration = self.context[
            declaration_start : self.context.index("{", declaration_start)
        ]
        self.assertIn("output: String", declaration)
        for marker in (
            "!normalizedSource.isEmpty",
            "normalizedOutput.contains(normalizedSource)",
            "sourceLanguage == .japanese",
            "targetLanguage == .simplifiedChinese",
            "isSharedHanOnlyJapaneseSource(source)",
            "TranslationOutputPolicy.allowsUnchangedJapaneseHanTranslation(",
            "source: source",
            "output: output",
            "return !TranslationOutputPolicy",
            "guard normalizedSource.count > 1 else",
        ):
            self.assertIn(marker, body)

    def test_evaluator_passes_original_output_to_leakage_gate(self) -> None:
        failures = function_body(self.context, "private static func textFailures(\n")
        self.assertIn(
            "source: sourceText,\n            output: translatedText,",
            failures,
        )
        self.assertIn("TranslationOutputPolicy.isPlaceholderResponse", failures)
        self.assertIn("targetLanguageDensity", failures)

    def test_shared_han_matrix_is_exact_and_language_bound(self) -> None:
        self.assertFalse(is_source_leakage("日本", "日本", "ja", "zh-CN"))
        self.assertFalse(is_source_leakage("東京。", "東京", "ja", "zh-CN"))
        self.assertTrue(is_source_leakage("日本", "日本人", "ja", "zh-CN"))
        self.assertTrue(is_source_leakage("日本", "日本 東京", "ja", "zh-CN"))
        self.assertTrue(is_source_leakage("日", "日", "ja", "zh-CN"))
        self.assertTrue(is_source_leakage("日本の", "日本の", "ja", "zh-CN"))
        self.assertTrue(is_source_leakage("東京", "東京", "en-US", "zh-CN"))
        self.assertTrue(is_source_leakage("東京", "東京", "ja", "en-US"))
        self.assertFalse(is_source_leakage("日本", "东京", "ja", "zh-CN"))

    def test_retry_and_downstream_boundaries_remain_block_scoped(self) -> None:
        for marker in (
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "TranslationBatchQualityEvaluator.evaluate(",
            "translateJapaneseImageBlockWithQA(",
            "qualityFailure",
            "正在只补译",
        ):
            self.assertIn(marker, self.store)
        for source in (self.context, self.gemma):
            for forbidden in (
                "VisionOCRService",
                "MangaOCRService.shared",
                "persist()",
                "groundTruth",
                "KOHARU_DATA_ROOT",
            ):
                self.assertNotIn(forbidden, source)

    def test_ocr_budget_cancel_and_persistence_boundaries_are_unchanged(self) -> None:
        for marker in (
            "maximumJapaneseMangaLineOCRRequests",
            "maximumJapaneseWeakBlockRecoveryRequests",
            "maximumBlocks = 8",
            "maximumCharacters = 1_800",
            "try Task.checkCancellation()",
            "persist()",
        ):
            self.assertIn(marker, self.store + read("AITRANS/Services/VisionOCRService.swift"))

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.377", "3.377"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3359-japanese-shared-han-qa-exactness-contract.py",
            "v3.359",
            "japanese-benchmark-v3.359-",
        ):
            self.assertIn(marker, combined)

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3359-japanese-shared-han-qa-exactness-contract.py"
        )
        for source in (self.context, self.gemma, self.store, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
