#!/usr/bin/env python3
"""Static contract for v3.316 Japanese OCR diacritic-preserving dedupe."""

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


class JapaneseOCRDiacriticPreservationContractTests(unittest.TestCase):
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

    def test_canonical_composition_precedes_width_comparison(self) -> None:
        normalizer = function_body(
            self.vision,
            "private static func normalizedOCRText(\n",
        )
        self.assertIn("canonicalized(text)", normalizer)
        self.assertIn("widthInsensitive", normalizer)
        self.assertIn(".widthInsensitive", normalizer)
        self.assertIn(".caseInsensitive", normalizer)
        self.assertLess(
            normalizer.index("canonicalized(text)"),
            normalizer.index(".widthInsensitive"),
        )

    def test_width_folding_does_not_strip_japanese_diacritics(self) -> None:
        normalizer = function_body(
            self.vision,
            "private static func normalizedOCRText(\n",
        )
        self.assertNotIn(".diacriticInsensitive", normalizer)
        self.assertIn("dakuten", self.vision)
        self.assertIn("handakuten", self.vision)
        # These pairs must remain semantically distinct after NFC composition;
        # the source contract must not erase their combining marks.
        self.assertNotEqual("か", "が")
        self.assertNotEqual("は", "ぱ")

    def test_only_japanese_dedupe_uses_width_folding(self) -> None:
        dedupe = function_body(
            self.vision,
            "private static func isDuplicateObservation(\n",
        )
        self.assertIn("if prefersJapanese", dedupe)
        width_call = dedupe.index("widthInsensitive: true")
        self.assertLess(dedupe.index("if prefersJapanese"), width_call)
        self.assertIn("leftText == rightText", dedupe)
        self.assertIn("textSimilarity(leftText, rightText)", dedupe)

    def test_ocr_and_translation_boundaries_remain_unchanged(self) -> None:
        for source in (self.normalizer, self.vision, self.manga):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
        for marker in (
            "maximumJapaneseMangaLineOCRRequests",
            "maximumJapaneseWeakBlockRecoveryRequests",
            "recognizeJapaneseVerticalCrops(",
            "translateImageBlockWithQA(",
        ):
            self.assertIn(marker, self.vision + self.manga + self.store)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.377", "3.377"],
        )
        for marker in (
            "scripts/test-v3316-japanese-ocr-diacritic-preservation-contract.py",
            "v3.316",
            "japanese-benchmark-v3.316-",
        ):
            self.assertIn(
                marker,
                self.workflow + self.flow + self.route + self.test_log + self.update_log,
            )

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3316-japanese-ocr-diacritic-preservation-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
