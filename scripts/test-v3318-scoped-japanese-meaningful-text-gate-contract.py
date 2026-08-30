#!/usr/bin/env python3
"""Static contract for v3.318 scoped Japanese OCR meaningful-text gates."""

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


class ScopedJapaneseMeaningfulTextGateContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.normalizer = read("AITRANS/Models/JapaneseOCRTextNormalizer.swift")
        cls.manga = read("AITRANS/Services/MangaOCRService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.test_log = read("md/test/test.md")
        cls.update_log = read("update_log.md")

    def test_scoped_manga_crop_requires_a_japanese_letter(self) -> None:
        body = function_body(
            self.vision,
            "private static func recognizeTextBlockDetached(\n        image: CGImage",
        )
        self.assertIn(
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            body,
        )
        self.assertIn("Self.japaneseScriptDensity(in: text) >= 0.5", body)
        self.assertLess(
            body.index("containsJapaneseLetter"),
            body.index("Self.japaneseScriptDensity"),
        )

    def test_one_sided_scoped_selection_rejects_punctuation_only_vision(self) -> None:
        selector = function_body(
            self.vision,
            "private static func selectJapaneseScopedBlockCandidate(\n",
        )
        self.assertIn("isUsableJapaneseScopedBlockCandidate(visionCandidate)", selector)
        self.assertIn("return nil", selector)
        self.assertLess(
            selector.index("isUsableJapaneseScopedBlockCandidate(visionCandidate)"),
            selector.index("return visionCandidate"),
        )

    def test_scoped_usable_helper_uses_shared_normalizer(self) -> None:
        helper = function_body(
            self.vision,
            "private static func isUsableJapaneseScopedText(\n",
        )
        self.assertIn("postProcessJapaneseOCRText(sourceText)", helper)
        self.assertIn("JapaneseOCRTextNormalizer.containsJapaneseLetter(text)", helper)
        self.assertIn("JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5", helper)
        self.assertIn("japaneseScriptDensity(in: text) >= 0.5", helper)
        block_helper = function_body(
            self.vision,
            "private static func isUsableJapaneseScopedBlockCandidate(\n",
        )
        self.assertIn("isUsableJapaneseScopedText(", block_helper)
        self.assertNotIn("isMeaningfulJapaneseScopedBlockCandidate", self.vision)

    def test_page_candidate_fallback_still_allows_punctuation_only_text(self) -> None:
        selector = function_body(
            self.vision,
            "private static func selectOCRCandidate(\n",
        )
        self.assertNotIn("containsJapaneseLetter", selector)
        self.assertIn("punctuation-only Japanese text is still valid input", selector)

    def test_ocr_translation_and_budget_boundaries_remain_unchanged(self) -> None:
        self.assertIn("maximumJapaneseMangaLineOCRRequests = 8", self.vision)
        self.assertIn("maximumJapaneseWeakBlockRecoveryRequests = 4", self.vision)
        for source in (self.vision, self.normalizer, self.manga):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
        self.assertIn(
            "translateImageBlockWithQA(",
            self.store,
        )

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.360", "3.360"],
        )
        for marker in (
            "scripts/test-v3318-scoped-japanese-meaningful-text-gate-contract.py",
            "v3.318",
            "japanese-benchmark-v3.318-",
        ):
            self.assertIn(
                marker,
                self.workflow + self.flow + self.route + self.test_log + self.update_log,
            )

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3318-scoped-japanese-meaningful-text-gate-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
