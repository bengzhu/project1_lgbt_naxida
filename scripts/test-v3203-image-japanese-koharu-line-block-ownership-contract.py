#!/usr/bin/env python3
"""Contract for Koharu-style tight line ownership inside Japanese blocks."""

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


class JapaneseKoharuLineBlockOwnershipContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.line = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.synthesis = braced_body(
            self.vision,
            "private static func synthesizeJapaneseVerticalLineCandidates(",
        )
        self.block_crop = braced_body(
            self.vision,
            "private static func koharuVerticalBlockCropRect(",
        )
        self.ownership = braced_body(
            self.vision,
            "private static func japaneseLineRegionOverlapsBlock(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_line_candidate_requires_tight_geometry_to_belong_to_block(self) -> None:
        for marker in [
            "overlapRatio(observation.rect, block.rect) >= 0.25",
            "japaneseLineRegionOverlapsBlock(observation, block: block)",
            "isVerticalLineCandidate(lineRegion)",
        ]:
            self.assertIn(marker, self.line)

    def test_ownership_uses_tight_region_and_safe_fallback(self) -> None:
        self.assertIn(
            "observation.lineRegionRect?.normalizedToUnit()",
            self.ownership,
        )
        self.assertIn("guard let lineRegion", self.ownership)
        self.assertIn("return true", self.ownership)
        self.assertIn("overlapRatio(lineRegion, block.rect) >= 0.25", self.ownership)

    def test_synthesis_and_block_envelope_share_line_ownership_gate(self) -> None:
        self.assertIn(
            "japaneseLineRegionOverlapsBlock(observation, block: block)",
            self.synthesis,
        )
        self.assertIn(
            "japaneseLineRegionOverlapsBlock(observation, block: block)",
            self.block_crop,
        )
        self.assertIn(".compactMap(\\.lineRegionRect)", self.block_crop)

    def test_scope_stays_japanese_geometry_only(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3202(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 203) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.202;", self.project)
        old = "python3 -B scripts/test-v3202-image-japanese-koharu-tight-line-candidate-gate-contract.py"
        new = "python3 -B scripts/test-v3203-image-japanese-koharu-line-block-ownership-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
