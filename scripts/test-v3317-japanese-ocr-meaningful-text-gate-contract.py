#!/usr/bin/env python3
"""Static contract for v3.317 Japanese OCR meaningful-text quality gates."""

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


class JapaneseOCRMeaningfulTextGateContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.normalizer = read("AITRANS/Models/JapaneseOCRTextNormalizer.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.manga = read("AITRANS/Services/MangaOCRService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.test_log = read("md/test/test.md")
        cls.update_log = read("update_log.md")

    def test_shared_letter_signal_excludes_japanese_punctuation(self) -> None:
        count = function_body(
            self.normalizer,
            "static func japaneseLetterCount(_ text: String) -> Int",
        )
        self.assertIn("0x3041...0x3096", count)
        self.assertIn("0x30A1...0x30FA", count)
        self.assertIn("0x4E00...0x9FFF", count)
        self.assertNotIn("0x3000...0x303F", count)
        self.assertIn("static func containsJapaneseLetter(_ text: String) -> Bool", self.normalizer)

    def test_reliable_manga_owner_requires_meaningful_japanese_text(self) -> None:
        body = function_body(
            self.vision,
            "private static func isReliableJapaneseMangaOCRResult(\n",
        )
        self.assertIn("JapaneseOCRTextNormalizer.containsJapaneseLetter(result.text)", body)
        self.assertIn("japaneseScriptDensity(in: result.text) >= 0.5", body)
        self.assertLess(
            body.index("containsJapaneseLetter"),
            body.index("japaneseScriptDensity"),
        )

    def test_line_coverage_requires_meaningful_japanese_text(self) -> None:
        body = function_body(
            self.vision,
            "private static func isReliableJapaneseLineCoverageResult(\n",
        )
        self.assertIn("JapaneseOCRTextNormalizer.containsJapaneseLetter(text)", body)
        self.assertIn("japaneseScriptDensity(in: text) >= 0.5", body)
        self.assertIn("candidateLength < 2 || resultLength >= 2", body)

    def test_scoped_candidate_gate_cannot_promote_punctuation_only_text(self) -> None:
        body = function_body(
            self.vision,
            "private static func isUsableJapaneseScopedText(\n",
        )
        self.assertIn("JapaneseOCRTextNormalizer.containsJapaneseLetter(text)", body)
        self.assertIn("confidence >= 0.55", body)
        self.assertIn("japaneseScriptDensity(in: text) >= 0.5", body)
        block_gate = function_body(
            self.vision,
            "private static func isUsableJapaneseScopedBlockCandidate(\n",
        )
        self.assertIn("isUsableJapaneseScopedText(", block_gate)

    def test_punctuation_observations_remain_available_as_fallback(self) -> None:
        selector = function_body(
            self.vision,
            "private static func selectOCRCandidate(\n",
        )
        self.assertNotIn("containsJapaneseLetter", selector)
        self.assertIn("let candidatesToScore = letterBearingCandidates.isEmpty", selector)
        self.assertIn("? confidenceWindow", selector)
        self.assertIn("punctuation-only Japanese text is still valid input", selector)

    def test_budget_and_translation_boundaries_remain_unchanged(self) -> None:
        self.assertIn("maximumJapaneseMangaLineOCRRequests = 8", self.vision)
        self.assertIn("maximumJapaneseWeakBlockRecoveryRequests = 4", self.vision)
        for source in (self.normalizer, self.vision, self.manga):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
        self.assertIn("translateImageBlockWithQA(", read("AITRANS/Services/TranslationSessionStore.swift"))

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.354", "3.354"],
        )
        for marker in (
            "scripts/test-v3317-japanese-ocr-meaningful-text-gate-contract.py",
            "v3.317",
            "japanese-benchmark-v3.317-",
        ):
            self.assertIn(
                marker,
                self.workflow + self.flow + self.route + self.test_log + self.update_log,
            )

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3317-japanese-ocr-meaningful-text-gate-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
