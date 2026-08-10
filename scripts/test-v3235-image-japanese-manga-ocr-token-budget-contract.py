#!/usr/bin/env python3
"""Contract for matching Koharu Manga OCR decoder token budget semantics."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class JapaneseMangaOCRTokenBudgetContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_single_and_batch_decoders_match_koharu_max_length(self) -> None:
        self.assertIn("for _ in 0..<Self.maximumTokens", self.service)
        self.assertEqual(self.service.count("for _ in 0..<Self.maximumTokens"), 2)
        self.assertNotIn("for _ in 1..<Self.maximumTokens", self.service)
        self.assertIn(
            "Koharu's decoder performs max_length generation steps",
            self.service,
        )
        self.assertIn("private static let maximumTokens = 300", self.service)

    def test_decoder_safety_boundaries_remain_intact(self) -> None:
        for marker in [
            "try Task.checkCancellation()",
            "if prediction.id == Self.decoderEndToken",
            "if finished.allSatisfy({ $0 })",
            "images.count <= 4",
        ]:
            self.assertIn(marker, self.service)

    def test_version_and_ci_route_follow_v3234(self) -> None:
        previous = "python3 -B scripts/test-v3234-image-japanese-vertical-review-filter-contract.py"
        current = "python3 -B scripts/test-v3235-image-japanese-manga-ocr-token-budget-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3235-image-japanese-manga-ocr-token-budget-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 235) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.234;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
