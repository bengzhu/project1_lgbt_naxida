#!/usr/bin/env python3
"""Contract for Koharu-style tight Japanese line-region deduplication."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def braced_body(source: str, marker: str) -> str:
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class JapaneseTightRegionDedupeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.duplicate = braced_body(
            self.vision,
            "private static func isDuplicateObservation(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_geometry_only_merge_requires_two_tight_japanese_regions(self) -> None:
        for marker in [
            "let hasTightJapaneseGeometry = prefersJapanese",
            "&& lhs.lineRegionRect != nil",
            "&& rhs.lineRegionRect != nil",
            "if hasTightJapaneseGeometry && overlap >= 0.85",
            "return true",
            "Koharu's merge_slice_regions",
        ]:
            self.assertIn(marker, self.duplicate)
        self.assertLess(
            self.duplicate.index("if hasTightJapaneseGeometry && overlap >= 0.85"),
            self.duplicate.index("let leftText = normalizedOCRText(lhs.text)"),
        )

    def test_request_boxes_and_text_similarity_remain_the_fallback(self) -> None:
        for marker in [
            "lhsGeometry = lhs.rect",
            "rhsGeometry = rhs.rect",
            "guard overlap >= 0.45 else { return false }",
            "let leftText = normalizedOCRText(lhs.text)",
            "leftText == rightText || leftText.contains(rightText)",
            "overlap >= 0.72 && textSimilarity(leftText, rightText) >= 0.62",
        ]:
            self.assertIn(marker, self.duplicate)
        self.assertIn(
            "Request-level boxes remain text-dependent",
            self.duplicate,
        )

    def test_geometry_rule_is_not_a_global_or_store_level_dedupe(self) -> None:
        self.assertIn(
            "isDuplicateObservation(candidate, of: $0, prefersJapanese: true)",
            self.vision,
        )
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_fixture_and_version_route_are_present(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.193", "3.193"])
        old = "python3 -B scripts/test-v3192-image-japanese-manga-window-order-contract.py"
        new = "python3 -B scripts/test-v3193-image-japanese-tight-region-dedupe-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
