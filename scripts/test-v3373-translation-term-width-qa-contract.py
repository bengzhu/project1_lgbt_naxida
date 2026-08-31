#!/usr/bin/env python3
"""Static and pure-policy contract for v3.381 translation term width QA."""

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


def canonical_term_text(value: str) -> str:
    return unicodedata.normalize("NFKC", value).casefold()


def contains_canonical_term(value: str, term: str) -> bool:
    canonical_term = canonical_term_text(term)
    return bool(canonical_term) and canonical_term in canonical_term_text(value)


class TranslationTermWidthQAContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.evaluator = read("scripts/evaluate-japanese-translation-context-qa.py")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.documents = [
            read("README.md")
            , read("md/flow/flow.md")
            , read("md/flow/flowchart.md")
            , read("md/test/test.md")
            , read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            , read("update_log.md")
        ]
        cls.docs = "\n".join(cls.documents)

    def test_product_term_match_canonicalizes_width_and_unicode(self) -> None:
        matcher = function_body(
            self.context,
            "private static func containsCanonicalTerm(_ text: String, _ term: String)",
        )
        canonical = function_body(
            self.context,
            "private static func canonicalTermText(_ text: String) -> String",
        )
        for marker in (
            "let canonicalText = canonicalTermText(text)",
            "let canonicalTerm = canonicalTermText(term)",
            "guard !canonicalTerm.isEmpty else { return false }",
            "return canonicalText.contains(canonicalTerm)",
        ):
            self.assertIn(marker, matcher)
        self.assertEqual(
            canonical.count(
                "folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)"
            ),
            1,
        )
        self.assertEqual(canonical.count("precomposedStringWithCanonicalMapping"), 2)
        self.assertNotIn("punctuationCharacters", canonical)

    def test_product_qa_uses_matcher_for_confirmed_terms_only(self) -> None:
        failures = function_body(
            self.context,
            "private static func textFailures(\n",
        )
        for marker in (
            "for term in configuration.confirmedTerms where term.status == .confirmed",
            "containsCanonicalTerm(sourceText, termSource)",
            "containsCanonicalTerm(translatedText, termTarget)",
            'failures.append("confirmedTermMismatch")',
        ):
            self.assertIn(marker, failures)
        self.assertNotIn("localizedCaseInsensitiveContains(termSource)", failures)
        self.assertNotIn("localizedCaseInsensitiveContains(termTarget)", failures)

    def test_cloud_shadow_qa_matches_product_without_stripping_punctuation(self) -> None:
        for marker in (
            "def canonical_term_text(value: str) -> str:",
            'unicodedata.normalize("NFKC", value).casefold()',
            "def contains_canonical_term(value: str, term: str) -> bool:",
            "canonical_term in canonical_term_text(value)",
            'not contains_canonical_term(source, term["source"])',
            'not contains_canonical_term(output, term["target"])',
            'contains_canonical_term(output, term["target"])',
        ):
            self.assertIn(marker, self.evaluator)
        matcher = function_body(
            self.evaluator,
            "def contains_canonical_term(value: str, term: str) -> bool:",
        )
        self.assertNotIn("unicodedata.category", matcher)

    def test_width_and_canonical_equivalents_match_but_punctuation_stays_significant(self) -> None:
        self.assertTrue(contains_canonical_term("这是ＡＢＣ作品", "ABC"))
        self.assertTrue(contains_canonical_term("半角ｶﾞｲﾄﾞ", "ガイド"))
        self.assertTrue(contains_canonical_term("Cafe\u0301作品", "Café"))
        self.assertTrue(contains_canonical_term("ABC", "ａｂｃ"))
        self.assertFalse(contains_canonical_term("A-B", "AB"))
        self.assertFalse(contains_canonical_term("ABC", "ＡＢＣＤ"))
        self.assertFalse(contains_canonical_term("", "ABC"))

    def test_term_status_and_block_boundaries_remain_fail_closed(self) -> None:
        self.assertIn('for term in terms:', self.evaluator)
        self.assertIn('term["status"] != "confirmed"', self.evaluator)
        self.assertIn('term["status"] == "revoked"', self.evaluator)
        for marker in (
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "TranslationBatchQualityEvaluator.evaluate(",
            "translateJapaneseImageBlockWithQA(",
            "qualityFailure",
            "persist()",
            "maximumJapaneseMangaLineOCRRequests",
        ):
            self.assertIn(marker, self.store + self.context + self.vision)
        for source in (self.context, self.evaluator):
            for forbidden in ("groundTruth", "KOHARU_DATA_ROOT", "recognizeTextBlocks("):
                self.assertNotIn(forbidden, source)

    def test_version_workflow_and_records_are_current(self) -> None:
        contract = "scripts/test-v3373-translation-term-width-qa-contract.py"
        current = f"python3 -B {contract}"
        previous = (
            "python3 -B scripts/test-v3372-image-japanese-line-single-rotation-contract.py"
        )
        self.assertGreaterEqual(self.workflow.count(current), 1)
        self.assertGreaterEqual(self.workflow.index(previous), 0)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.381", "3.381"],
        )
        for document in self.documents:
            self.assertIn("v3.381", document)
            self.assertIn(contract, document)
            self.assertIn("test/3.png", document)
            self.assertIn("未提供", document)
        for marker in ("v3.381", contract, "test/3.png", "未提供"):
            self.assertIn(marker, self.workflow + self.docs)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3373-translation-term-width-qa-contract.py"
        )
        for source in (self.context, self.evaluator, self.store, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
