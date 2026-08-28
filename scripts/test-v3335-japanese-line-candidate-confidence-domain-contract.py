#!/usr/bin/env python3
"""Static contract for v3.335 bounded Japanese line-candidate confidence."""

from pathlib import Path
import math
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


def line_confidence_key(confidence: float) -> float:
    return confidence if math.isfinite(confidence) and 0.0 <= confidence <= 1.0 else -math.inf


class JapaneseLineCandidateConfidenceDomainContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("update_log.md")
        )
        cls.candidates = function_body(
            cls.vision,
            "private static func japaneseMangaLineOCRCandidates(\n",
        )
        cls.recognizer = function_body(
            cls.vision,
            "private static func recognizeJapaneseMangaLineOCR(\n",
        )

    def test_text_backed_pool_is_finite_and_meaningful(self) -> None:
        pool = self.candidates[
            self.candidates.index("let textBackedCandidates") : self.candidates.index(
                "let textBacked ="
            )
        ]
        for marker in (
            "candidate.observationRole != .detectorTextRegion",
            "isVerticalLineCandidate(region)",
            "validOCRConfidence(candidate.confidence) != nil",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
        ):
            self.assertIn(marker, pool)

    def test_invalid_confidence_cannot_beat_valid_line_candidates(self) -> None:
        self.assertEqual(line_confidence_key(float("nan")), -math.inf)
        self.assertEqual(line_confidence_key(float("inf")), -math.inf)
        self.assertEqual(line_confidence_key(-0.1), -math.inf)
        self.assertEqual(line_confidence_key(1.1), -math.inf)
        self.assertLess(line_confidence_key(0.2), line_confidence_key(0.8))

    def test_line_sort_uses_finite_key_and_keeps_weak_first_priority(self) -> None:
        sort_body = self.candidates[
            self.candidates.index("let textBacked =") : self.candidates.index(
                "// Geometry-only candidates"
            )
        ]
        self.assertIn(
            "let lhsConfidence = validOCRConfidence(lhs.confidence) ?? -.infinity",
            sort_body,
        )
        self.assertIn(
            "let rhsConfidence = validOCRConfidence(rhs.confidence) ?? -.infinity",
            sort_body,
        )
        self.assertIn("return lhsConfidence < rhsConfidence", sort_body)
        self.assertNotIn("return lhs.confidence < rhs.confidence", sort_body)
        self.assertNotIn("return lhs.confidence > rhs.confidence", sort_body)

    def test_total_line_budget_and_geometry_reserve_are_unchanged(self) -> None:
        for marker in (
            "maximumJapaneseMangaLineOCRRequests = 8",
            "min(2, maximumJapaneseMangaLineOCRRequests)",
            "maximumJapaneseMangaLineOCRRequests - geometryReserve",
            "textBacked.prefix(textLimit)",
            "uncoveredGeometry.prefix(geometryReserve)",
            ".prefix(maximumJapaneseMangaLineOCRRequests)",
        ):
            self.assertIn(marker, self.candidates + self.vision)

    def test_line_recognition_keeps_existing_cancel_and_result_gates(self) -> None:
        for marker in (
            "try await MangaOCRService.shared.recognize(",
            "catch is CancellationError",
            "throw CancellationError()",
            "validOCRConfidence(result.confidence)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
        ):
            self.assertIn(marker, self.recognizer)
        self.assertIn("translateImageBlockWithQA(", self.store)

    def test_product_does_not_read_ground_truth_or_reference_runtime(self) -> None:
        for source in (self.vision, self.recognizer, self.candidates):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.341", "3.341"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3335-japanese-line-candidate-confidence-domain-contract.py",
            "v3.341",
            "japanese-benchmark-v3.341-",
        ):
            self.assertIn(marker, combined)
        contract = read("scripts/test-v3335-japanese-line-candidate-confidence-domain-contract.py")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
