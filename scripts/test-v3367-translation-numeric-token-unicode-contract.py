#!/usr/bin/env python3
"""Static and pure-policy contract for v3.387 numeric token Unicode QA."""

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


FULLWIDTH_NUMERIC_TRANSLATION = str.maketrans(
    "０１２３４５６７８９，．／：－",
    "0123456789,./:-",
)
NUMERIC_TOKEN_PATTERN = re.compile(r"[0-9]+(?:[.,:/-][0-9]+)*")


def numeric_tokens(value: str) -> list[str]:
    canonical = value.translate(FULLWIDTH_NUMERIC_TRANSLATION)
    return [match.group().lower() for match in NUMERIC_TOKEN_PATTERN.finditer(canonical)]


class TranslationNumericTokenUnicodeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
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

    def test_numeric_policy_canonicalizes_fullwidth_digits_and_separators(self) -> None:
        numeric = function_body(
            self.context,
            "private static func canonicalNumericTokenText(_ text: String) -> String",
        )
        for marker in (
            "0xFF10...0xFF19",
            "scalar.value - 0xFEE0",
            "case 0xFF0C:",
            "case 0xFF0E:",
            "case 0xFF0F:",
            "case 0xFF1A:",
            "case 0xFF0D:",
            "canonical.unicodeScalars.append(scalar)",
        ):
            self.assertIn(marker, numeric)

    def test_numeric_matching_happens_after_narrow_canonicalization(self) -> None:
        numeric = function_body(
            self.context,
            "private static func numericTokens(in text: String)",
        )
        self.assertIn("let canonicalText = canonicalNumericTokenText(text)", numeric)
        self.assertIn(r"[0-9]+(?:[.,:/-][0-9]+)*", numeric)
        self.assertNotIn(r"#" + r"""\d+(?:[.,:/-]\d+)*""" + r"#", numeric)
        self.assertLess(
            numeric.index("canonicalNumericTokenText(text)"),
            numeric.index("NSRegularExpression"),
        )
        self.assertIn("regex.matches(in: canonicalText", numeric)

    def test_fullwidth_and_ascii_equivalents_are_equal_without_widening_tokens(self) -> None:
        self.assertEqual(
            numeric_tokens("第１２．５話 ２０２６／０８／３０ １２：３０"),
            ["12.5", "2026/08/30", "12:30"],
        )
        self.assertEqual(
            numeric_tokens("第12.5話 2026/08/30 12:30"),
            ["12.5", "2026/08/30", "12:30"],
        )
        self.assertEqual(numeric_tokens("価格１２，３４５"), ["12,345"])

    def test_missing_or_changed_numeric_tokens_still_fail_closed(self) -> None:
        self.assertNotEqual(numeric_tokens("第１２話"), numeric_tokens("第話"))
        self.assertNotEqual(numeric_tokens("版本２.０"), numeric_tokens("版本2.0.0"))
        self.assertNotEqual(numeric_tokens("１２ ３"), numeric_tokens("123"))
        self.assertNotEqual(numeric_tokens("０８"), numeric_tokens("8"))

    def test_number_failure_remains_in_block_qa_without_ocr_or_persistence_changes(self) -> None:
        failures = function_body(
            self.context,
            "private static func textFailures(\n",
        )
        self.assertIn("numericTokens(in: sourceText) != numericTokens(in: translatedText)", failures)
        self.assertIn('failures.append("numberMismatch")', failures)
        for forbidden in (
            "recognizeTextBlock(",
            "recognizeTextBlocks(",
            "persist()",
            "groundTruth",
            "KOHARU_DATA_ROOT",
        ):
            self.assertNotIn(forbidden, self.context)
        self.assertIn("TranslationBatchQualityEvaluator.singleOutputFailures(", self.store)

    def test_version_workflow_docs_and_test3_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.387", "3.387"],
        )
        self.assertIn(
            "python3 -B scripts/test-v3367-translation-numeric-token-unicode-contract.py",
            self.workflow,
        )
        for marker in (
            "scripts/test-v3367-translation-numeric-token-unicode-contract.py",
            "v3.387",
            "japanese-benchmark-v3.387-",
            "test/3.png",
            "未提供",
        ):
            self.assertIn(marker, self.workflow + self.docs)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3367-translation-numeric-token-unicode-contract.py"
        )
        for source in (contract, self.context, self.store):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
