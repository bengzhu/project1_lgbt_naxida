#!/usr/bin/env python3
"""Contract for owner-exact proof before skipping Japanese block fallback."""

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


class KoharuLineCoverageOwnerContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        cls.runtime = read(
            "scripts/test-v3278-koharu-line-coverage-owner-runtime.sh"
        )
        cls.evaluator = read(
            "scripts/fixtures/v3278-koharu-line-coverage-owner-evaluator.swift"
        )
        cls.coverage = braced_body(
            cls.vision,
            "private static func hasCompleteJapaneseLineCoverage(",
        )
        cls.owner_proof = braced_body(
            cls.layout,
            "static func lineCoverageOwnersProveBlock(",
        )
        cls.compatibility = braced_body(
            cls.vision,
            "private static func verticalTextRegionOwnersCompatible(",
        )

    def test_owner_proof_precedes_quality_and_geometry_proof(self) -> None:
        owner = "ImageOCRLayoutEngine.lineCoverageOwnersProveBlock("
        quality = "isReliableJapaneseLineCoverageResult($0, candidate: candidate)"
        geometry = "japaneseLineCoverageMatches($0, candidate: candidate)"
        self.assertIn(owner, self.coverage)
        self.assertIn("candidateOwner: candidate.verticalTextRegionOwner", self.coverage)
        self.assertIn("blockOwner: block.verticalTextRegionOwner", self.coverage)
        self.assertLess(self.coverage.index(owner), self.coverage.index(quality))
        self.assertLess(self.coverage.index(quality), self.coverage.index(geometry))

    def test_known_block_requires_exact_candidate_and_result_owner(self) -> None:
        for marker in (
            "guard let blockOwner else",
            "candidateOwner == blockOwner",
            "lineResultOwner == blockOwner",
        ):
            self.assertIn(marker, self.owner_proof)
        self.assertNotIn("== nil", self.owner_proof)

    def test_ownerless_block_retains_historical_compatibility(self) -> None:
        self.assertIn(
            "guard let lineResultOwner, let candidateOwner else { return true }",
            self.owner_proof,
        )
        self.assertIn("return lineResultOwner == candidateOwner", self.owner_proof)
        self.assertIn("return true", self.compatibility)
        self.assertIn("return lhsOwner == rhsOwner", self.compatibility)

    def test_incomplete_owner_proof_keeps_existing_block_crop_fallback(self) -> None:
        crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.assertIn("let hasCompleteLineCoverage", crops)
        self.assertIn("&& hasCompleteLineCoverage", crops)
        self.assertIn("guard !hasLineOCRResult else { continue }", crops)
        self.assertIn("koharuVerticalBlockCropRect(", crops)
        self.assertIn("orientationFallbacksRemaining = 8", crops)

    def test_owner_remains_ephemeral_and_scope_stays_ocr_only(self) -> None:
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
            self.assertNotIn(forbidden, self.owner_proof)

    def test_version_and_cloud_contract_route_are_current(self) -> None:
        for path in (
            "scripts/test-v3278-koharu-line-coverage-owner-contract.py",
            "scripts/test-v3278-koharu-line-coverage-owner-runtime.sh",
        ):
            self.assertGreaterEqual(self.workflow.count(path), 3)
        for marker in (
            "exact known owner did not prove coverage",
            "ownerless result proved a known block",
            "ownerless candidate proved a known block",
            "foreign result owner proved a known block",
            "ownerless block lost historical mixed compatibility",
            "ownerless block accepted two distinct known owners",
        ):
            self.assertIn(marker, self.evaluator)
        self.assertIn("xcrun swiftc -parse-as-library", self.runtime)
        self.assertIn(
            "v3278-koharu-line-coverage-owner-evaluator.swift",
            self.runtime,
        )
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project),
            ["3.373", "3.373"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
