#!/usr/bin/env python3
"""Contract for replacing partial owned lines with a reliable block fallback."""

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


class KoharuBlockFallbackReplacementContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.cloud_smoke = read(
            "scripts/run-koharu-mit48px-cloud-smoke.sh"
        )
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.runtime = read(
            "scripts/test-v3279-koharu-block-fallback-replacement-runtime.sh"
        )
        cls.evaluator = read(
            "scripts/fixtures/v3279-koharu-block-fallback-replacement-evaluator.swift"
        )
        cls.crops = braced_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        cls.policy = braced_body(
            cls.layout,
            "static func blockFallbackCanReplacePartialLines(",
        )

    def test_cloud_reference_boundary_returns_one_prediction_per_crop(self) -> None:
        for marker in (
            'KOHARU_SOURCE_REVISION="35f3e6d1a418d9617fd922e2bc865fe5b8fff818"',
            'regions = payload.get("regions")',
            "if not isinstance(regions, list) or len(regions) != 1:",
            "expected one MIT48 region prediction",
            "prediction = regions[0]",
        ):
            self.assertIn(marker, self.cloud_smoke)

    def test_incomplete_coverage_collects_one_block_fallback_source(self) -> None:
        coverage = self.crops.index("let hasCompleteLineCoverage")
        crop = self.crops.index("koharuVerticalBlockCropRect(")
        collect = self.crops.index("var blockFallback = primary")
        replace = self.crops.index("refined.removeAll")
        append = self.crops.index("refined.append(contentsOf: blockFallback)")
        self.assertLess(coverage, crop)
        self.assertLess(crop, collect)
        self.assertLess(collect, replace)
        self.assertLess(replace, append)
        self.assertIn("blockFallback.append(contentsOf:", self.crops)

    def test_only_exact_owned_vertical_lines_are_replaced(self) -> None:
        self.assertIn("fallbackHasCompleteLineCoverage", self.crops)
        self.assertIn("sourceObservations: ownerAnnotatedObservations", self.crops)
        self.assertIn("lineRefined: blockFallback", self.crops)
        self.assertIn("allowsBlockCropResults: true", self.crops)
        self.assertIn(
            "blockFallback = deduplicateJapaneseObservations(blockFallback)",
            self.crops,
        )
        self.assertIn(
            "fallbackOwners: blockFallback.map(\\.verticalTextRegionOwner)",
            self.crops,
        )
        self.assertIn("let blockOwner = block.verticalTextRegionOwner", self.crops)
        self.assertIn("$0.observationRole == .verticalLine", self.crops)
        self.assertIn("$0.verticalTextRegionOwner == blockOwner", self.crops)
        self.assertNotIn("lineRefined.removeAll", self.crops)
        self.assertNotIn("ownerAnnotatedObservations.removeAll", self.crops)

    def test_fallback_reuses_reliable_one_to_one_line_coverage_gate(self) -> None:
        coverage = braced_body(
            self.vision,
            "private static func hasCompleteJapaneseLineCoverage(",
        )
        self.assertIn("allowsBlockCropResults: Bool = false", self.vision)
        for marker in (
            "observation.observationRole == .verticalLine",
            "allowsBlockCropResults && observation.observationRole == .crop",
            "lineCoverageOwnersProveBlock(",
            "isReliableJapaneseLineCoverageResult($0, candidate: candidate)",
            "japaneseLineCoverageMatches($0, candidate: candidate)",
            "availableLineResults.remove(at: resultIndex)",
        ):
            self.assertIn(marker, coverage)

    def test_policy_rejects_incomplete_ownerless_and_foreign_fallbacks(self) -> None:
        self.assertIn("guard hasCompleteLineCoverage", self.policy)
        self.assertIn("!fallbackOwners.isEmpty", self.policy)
        self.assertIn("let blockOwner", self.policy)
        self.assertIn(
            "return fallbackOwners.allSatisfy { $0 == blockOwner }",
            self.policy,
        )
        for marker in (
            "complete exact-owner fallback did not replace partial lines",
            "foreign-owner fallback replaced partial lines",
            "ownerless fallback replaced known-owner partial lines",
            "fallback replaced partial lines for an ownerless block",
            "incomplete exact-owner fallback replaced partial lines",
            "empty fallback replaced partial lines",
        ):
            self.assertIn(marker, self.evaluator)

    def test_request_budgets_and_ephemeral_owner_boundary_remain(self) -> None:
        self.assertIn(".prefix(16)", self.crops)
        self.assertIn("var orientationFallbacksRemaining = 8", self.crops)
        translation_block = braced_body(
            self.models,
            "struct ImageTranslationBlock:",
        )
        self.assertNotIn("verticalTextRegionOwner", translation_block)
        for forbidden in (
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "metrics/version_history.csv",
            "output/",
        ):
            self.assertNotIn(forbidden, self.policy)

    def test_version_and_cloud_runtime_route_are_current(self) -> None:
        for path in (
            "scripts/test-v3279-koharu-block-fallback-replacement-contract.py",
            "scripts/test-v3279-koharu-block-fallback-replacement-runtime.sh",
        ):
            self.assertGreaterEqual(self.workflow.count(path), 3)
        self.assertIn("xcrun swiftc -parse-as-library", self.runtime)
        self.assertIn(
            "v3279-koharu-block-fallback-replacement-evaluator.swift",
            self.runtime,
        )
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project),
            ["3.305", "3.305"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
