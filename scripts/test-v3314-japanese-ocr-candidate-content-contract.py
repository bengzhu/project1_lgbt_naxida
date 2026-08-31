#!/usr/bin/env python3
"""Static contract for v3.314 Japanese OCR candidate content preference."""

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


class JapaneseOCRCandidateContentContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
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

    def test_candidate_selection_keeps_bounded_confidence_window(self) -> None:
        body = function_body(
            self.vision,
            "private static func selectOCRCandidate(\n",
        )
        self.assertIn("let validCandidates = candidates.filter", body)
        self.assertIn("validOCRConfidence($0.confidence) != nil", body)
        self.assertIn(
            "let bestConfidence = validCandidates.map(\\.confidence).max()",
            body,
        )
        self.assertIn(
            "let confidenceWindow = validCandidates.filter {",
            body,
        )
        self.assertIn("$0.confidence >= bestConfidence - 0.14", body)

    def test_letter_bearing_content_wins_without_symbol_only_global_gate(self) -> None:
        body = function_body(
            self.vision,
            "private static func selectOCRCandidate(\n",
        )
        self.assertIn("let letterBearingCandidates = confidenceWindow.filter", body)
        self.assertIn(
            "japaneseLetterCountForRecovery(postProcessJapaneseOCRText($0.string)) > 0",
            body,
        )
        self.assertIn(
            "let candidatesToScore = letterBearingCandidates.isEmpty",
            body,
        )
        self.assertIn("? confidenceWindow", body)
        self.assertIn("return candidatesToScore", body)

    def test_existing_score_and_ocr_pipeline_remain_the_selector_boundary(self) -> None:
        body = function_body(
            self.vision,
            "private static func selectOCRCandidate(\n",
        )
        self.assertIn("japaneseCandidateScore(lhs) < japaneseCandidateScore(rhs)", body)
        for marker in (
            "recognizeJapaneseVerticalCrops(",
            "recoverWeakJapaneseBlocks(",
            "recognizeObservations(",
            "translateImageBlockWithQA(",
        ):
            self.assertIn(marker, self.vision + self.manga + self.store)

    def test_content_gate_does_not_add_budget_or_external_reference_dependencies(self) -> None:
        for source in (self.vision, self.manga):
            self.assertNotIn("groundTruth", source)
        self.assertNotIn("KOHARU_DATA_ROOT", self.vision)
        self.assertNotIn("sub" + "process", self.vision)
        self.assertNotIn("Po" + "pen", self.vision)
        self.assertIn("maximumJapaneseMangaLineOCRRequests", self.vision)
        self.assertIn("maximumJapaneseWeakBlockRecoveryRequests", self.vision)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.377", "3.377"],
        )
        for marker in (
            "scripts/test-v3314-japanese-ocr-candidate-content-contract.py",
            "v3.314",
            "japanese-benchmark-v3.314-",
        ):
            self.assertIn(
                marker,
                self.workflow + self.flow + self.route + self.test_log + self.update_log,
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
