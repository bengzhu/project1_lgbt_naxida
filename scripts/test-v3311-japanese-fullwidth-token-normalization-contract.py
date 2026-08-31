#!/usr/bin/env python3
"""Static contract for fullwidth Latin/digit OCR token fidelity."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class JapaneseFullwidthTokenNormalizationContractTests(unittest.TestCase):
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

    def test_fullwidth_latin_and_digit_tokens_enter_the_shared_boundary(self) -> None:
        for marker in (
            "containsFullwidthWord",
            "containsLatinOrDigitWord",
            "0xFF10...0xFF19",
            "0xFF21...0xFF3A",
            "0xFF41...0xFF5A",
            "tokens.contains(where: containsLatinOrDigitWord)",
            "preservesASCII: containsLatinOrDigitWord(token)",
        ):
            self.assertIn(marker, self.normalizer)

    def test_fullwidth_technical_scalars_are_canonicalized_to_ascii(self) -> None:
        for marker in (
            "normalizedTechnicalScalar",
            "0xFF01...0xFF5E",
            "scalar.value - 0xFEE0",
            "one stable representation for dates, versions and URLs",
        ):
            self.assertIn(marker, self.normalizer)
        self.assertLess(
            self.normalizer.index("normalizedTechnicalScalar"),
            self.normalizer.index("else if (0x21...0x7E).contains"),
        )

    def test_fullwidth_period_keeps_bounded_dot_normalization(self) -> None:
        self.assertIn("scalar.value == 0xFF0E", self.normalizer)
        self.assertIn('String(repeating: ".", count: dotCount)', self.normalizer)
        self.assertIn("historical pure-Japanese post-processing", self.normalizer)

    def test_both_ocr_engines_share_the_updated_normalizer(self) -> None:
        for source in (self.vision, self.manga):
            self.assertIn(
                "JapaneseOCRTextNormalizer.mixedScriptCandidate(text)",
                source,
            )
        self.assertIn("JapaneseOCRTextNormalizer.hasMixedJapaneseAndASCII", self.vision)

    def test_normalizer_change_does_not_add_ocr_or_translation_side_effects(self) -> None:
        for forbidden in (
            "VisionOCRService",
            "MangaOCRService",
            "TranslationSessionStore",
            "VNRecognizeTextRequest",
            "groundTruth",
                "sub" + "process",
        ):
            self.assertNotIn(forbidden, self.normalizer)
        self.assertIn("JapaneseOCRTextNormalizer.swift in Sources", self.project)
        self.assertIn(
            "JapaneseOCRTextNormalizer.swift",
            self.project[self.project.index("/* Models */") :],
        )

    def test_ocr_geometry_translation_and_koharu_optional_boundaries_remain(self) -> None:
        for marker in (
            "recognizeJapaneseVerticalCrops(",
            "recoverWeakJapaneseBlocks(",
            "recognizeObservations(",
            "translateImageBlockWithQA(",
            "koharu_parity_required",
        ):
            self.assertIn(marker, self.vision + self.manga + self.store + self.workflow)
        self.assertNotIn("TranslationSessionStore", self.normalizer)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.376", "3.376"],
        )
        for marker in (
            "scripts/test-v3311-japanese-fullwidth-token-normalization-contract.py",
            "v3.311",
            "japanese-benchmark-v3.311-",
        ):
            self.assertIn(marker, self.workflow)
        for document in (
            self.flow,
            self.route,
            self.test_log,
            self.update_log,
        ):
            self.assertIn("v3.311", document)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read("scripts/test-v3311-japanese-fullwidth-token-normalization-contract.py")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
