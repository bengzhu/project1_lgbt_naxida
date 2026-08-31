#!/usr/bin/env python3
"""Static contract for mixed-script Japanese OCR text fidelity."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class JapaneseMixedScriptNormalizationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.normalizer = read("AITRANS/Models/JapaneseOCRTextNormalizer.swift")
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.manga = read("AITRANS/Services/MangaOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.flow = read("md/flow/flow.md")
        self.flowchart = read("md/flow/flowchart.md")
        self.test_log = read("md/test/test.md")
        self.update_log = read("update_log.md")

    def test_mixed_script_helper_preserves_ascii_tokens_and_required_spaces(self) -> None:
        for marker in [
            "mixedScriptCandidate",
            "split(whereSeparator: { $0.isWhitespace })",
            "containsASCIIWord",
            "output.append(\" \")",
            "preservesASCII",
            "0x30...0x39",
            "0x41...0x5A",
            "0x61...0x7A",
            "URL punctuation",
            "separators inside a technical/Latin token",
        ]:
            self.assertIn(marker, self.normalizer)

    def test_dot_and_punctuation_normalization_remain_bounded(self) -> None:
        for marker in [
            'replacingOccurrences(of: "…", with: "...")',
            "scalar.value == 0x2E || scalar.value == 0xFF0E",
            'String(repeating: ".", count: dotCount)',
            "0xFEE0",
        ]:
            self.assertIn(marker, self.normalizer)
        self.assertIn("historical pure-Japanese post-processing", self.normalizer)

    def test_both_ocr_engines_use_the_same_mixed_script_boundary(self) -> None:
        self.assertIn(
            "JapaneseOCRTextNormalizer.mixedScriptCandidate(text)",
            self.vision,
        )
        self.assertIn(
            "JapaneseOCRTextNormalizer.mixedScriptCandidate(text)",
            self.manga,
        )
        self.assertLess(
            self.vision.index("JapaneseOCRTextNormalizer.mixedScriptCandidate(text)"),
            self.vision.index("let withoutWhitespace = canonicalText.filter"),
        )
        self.assertLess(
            self.manga.index("JapaneseOCRTextNormalizer.mixedScriptCandidate(text)"),
            self.manga.index("let noWhitespace = canonicalText.filter"),
        )

    def test_normalizer_is_product_source_without_ocr_or_translation_side_effects(self) -> None:
        for forbidden in [
            "VisionOCRService",
            "MangaOCRService",
            "TranslationSessionStore",
            "VNRecognizeTextRequest",
            "groundTruth",
            "subprocess",
        ]:
            self.assertNotIn(forbidden, self.normalizer)
        self.assertIn(
            "JapaneseOCRTextNormalizer.swift in Sources",
            self.project,
        )
        self.assertIn(
            "JapaneseOCRTextNormalizer.swift",
            self.project[self.project.index("/* Models */") :],
        )

    def test_ocr_geometry_budget_and_manga_translation_paths_are_unchanged(self) -> None:
        for marker in [
            "try await Self.recognizeJapaneseMangaOCR(",
            "recognizeJapaneseVerticalCrops(",
            "recoverWeakJapaneseBlocks(",
            "recognizeObservations(",
        ]:
            self.assertIn(marker, self.vision)
        self.assertIn("maximumBatchSize", self.manga)
        self.assertNotIn("TranslationSessionStore", self.vision)
        self.assertNotIn("TranslationSessionStore", self.manga)

    def test_version_workflow_and_docs_are_current(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)
        self.assertEqual(versions, ["3.386", "3.386"])
        self.assertIn(
            "python3 -B scripts/test-v3305-japanese-mixed-script-normalization-contract.py",
            self.workflow,
        )
        self.assertIn("v3.306", self.workflow)
        self.assertIn("japanese-benchmark-v3.306-", self.workflow)
        for document in (
            self.flow,
            self.flowchart,
            self.test_log,
            self.update_log,
        ):
            self.assertIn("v3.306", document)


if __name__ == "__main__":
    unittest.main(verbosity=2)
