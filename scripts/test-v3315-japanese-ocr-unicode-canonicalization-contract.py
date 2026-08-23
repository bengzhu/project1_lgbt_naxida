#!/usr/bin/env python3
"""Static contract for v3.315 Japanese OCR Unicode canonicalization."""

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


class JapaneseOCRUnicodeCanonicalizationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.normalizer = read("AITRANS/Models/JapaneseOCRTextNormalizer.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
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

    def test_shared_boundary_canonicalizes_before_mixed_script_tokenization(self) -> None:
        canonicalizer = function_body(
            self.normalizer,
            "static func canonicalized(_ text: String) -> String",
        )
        self.assertIn("precomposedStringWithCanonicalMapping", canonicalizer)
        mixed = function_body(
            self.normalizer,
            "static func mixedScriptCandidate(_ text: String) -> String?",
        )
        self.assertIn("let tokens = canonicalized(text)", mixed)
        self.assertLess(
            mixed.index("canonicalized(text)"),
            mixed.index("split(whereSeparator:"),
        )

    def test_both_ocr_engines_canonicalize_before_existing_postprocess(self) -> None:
        vision = function_body(
            self.vision,
            "private static func postProcessJapaneseOCRText(_ text: String) -> String",
        )
        manga = function_body(
            self.manga,
            "private static func postProcess(_ text: String) -> String",
        )
        for body in (vision, manga):
            self.assertIn(
                "let canonicalText = JapaneseOCRTextNormalizer.canonicalized(text)",
                body,
            )
            self.assertIn(
                "mixedScriptCandidate(text)",
                body,
            )
            self.assertLess(
                body.index("canonicalText"),
                body.index("filter { !$0.isWhitespace }"),
            )

    def test_japanese_dedupe_compares_canonical_width_equivalents(self) -> None:
        normalizer = function_body(
            self.vision,
            "private static func normalizedOCRText(\n",
        )
        self.assertIn("canonicalized(text)", normalizer)
        self.assertIn("widthInsensitive", normalizer)
        dedupe = function_body(
            self.vision,
            "private static func isDuplicateObservation(\n",
        )
        self.assertIn(
            "let widthInsensitiveLeftText = normalizedOCRText(",
            dedupe,
        )
        self.assertIn(
            "lhs.text,\n                widthInsensitive: true",
            dedupe,
        )
        self.assertIn(
            "let widthInsensitiveRightText = normalizedOCRText(",
            dedupe,
        )
        self.assertIn(
            "rhs.text,\n                widthInsensitive: true",
            dedupe,
        )

    def test_canonicalization_does_not_expand_ocr_or_session_boundaries(self) -> None:
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
        self.assertIn("JapaneseOCRTextNormalizer.swift in Sources", self.project)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.330", "3.330"],
        )
        for marker in (
            "scripts/test-v3315-japanese-ocr-unicode-canonicalization-contract.py",
            "v3.315",
            "japanese-benchmark-v3.315-",
        ):
            self.assertIn(
                marker,
                self.workflow + self.flow + self.route + self.test_log + self.update_log,
            )

    def test_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3315-japanese-ocr-unicode-canonicalization-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
