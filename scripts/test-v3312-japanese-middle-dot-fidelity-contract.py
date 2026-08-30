#!/usr/bin/env python3
"""Static contract for Japanese middle-dot OCR fidelity."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class JapaneseMiddleDotFidelityContractTests(unittest.TestCase):
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

    def test_shared_normalizer_preserves_middle_dot(self) -> None:
        self.assertIn("scalar.value == 0x2E || scalar.value == 0xFF0E", self.normalizer)
        self.assertNotIn("scalar.value == 0x2E || scalar.value == 0x30FB", self.normalizer)
        self.assertIn("Japanese middle dot separates names and loanwords", self.normalizer)

    def test_both_ocr_fallbacks_preserve_middle_dot(self) -> None:
        self.assertIn("scalar.value == 0x2E || scalar.value == 0xFF0E", self.manga)
        self.assertIn("case 0x2E, 0xFF0E:", self.vision)
        self.assertNotIn("case 0x2E, 0x30FB:", self.vision)
        self.assertIn("remain U+30FB", self.vision)

    def test_true_period_and_ellipsis_normalization_remain_bounded(self) -> None:
        for source in (self.normalizer, self.vision, self.manga):
            self.assertIn('String(repeating: ".", count: dotCount)', source)
        for source in (self.normalizer, self.vision):
            self.assertIn('replacingOccurrences(of: "…", with: "...")', source)
        self.assertIn('replacing("…", with: "...")', self.manga)

    def test_shared_mixed_script_boundary_still_feeds_both_engines(self) -> None:
        for source in (self.vision, self.manga):
            self.assertIn(
                "JapaneseOCRTextNormalizer.mixedScriptCandidate(text)",
                source,
            )
        self.assertIn("JapaneseOCRTextNormalizer.hasMixedJapaneseAndASCII", self.vision)

    def test_punctuation_fix_does_not_add_ocr_or_translation_side_effects(self) -> None:
        for source in (self.normalizer, self.vision, self.manga):
            self.assertNotIn("TranslationSessionStore", source)
            self.assertNotIn("VNRecognizeTextRequest", self.normalizer)
            self.assertNotIn("groundTruth", source)
        self.assertIn("JapaneseOCRTextNormalizer.swift in Sources", self.project)

    def test_existing_ocr_translation_and_optional_boundaries_remain(self) -> None:
        for marker in (
            "recognizeJapaneseVerticalCrops(",
            "recoverWeakJapaneseBlocks(",
            "translateImageBlockWithQA(",
            "koharu_parity_required",
        ):
            self.assertIn(marker, self.vision + self.manga + self.store + self.workflow)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.366", "3.366"],
        )
        for marker in (
            "scripts/test-v3312-japanese-middle-dot-fidelity-contract.py",
            "v3.312",
            "japanese-benchmark-v3.312-",
        ):
            self.assertIn(marker, self.workflow)
        for document in (self.flow, self.route, self.test_log, self.update_log):
            self.assertIn("v3.312", document)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read("scripts/test-v3312-japanese-middle-dot-fidelity-contract.py")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
