#!/usr/bin/env python3
"""Static and pure-policy contract for v3.360 recovery-frontier block skips."""

from dataclasses import dataclass
import math
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


@dataclass(frozen=True)
class LineCandidate:
    owner: int | None
    rect: tuple[float, float, float, float]


@dataclass(frozen=True)
class RecoveryResult:
    owner: int | None
    rect: tuple[float, float, float, float]
    role: str
    text: str
    confidence: float


def overlap_ratio(
    lhs: tuple[float, float, float, float],
    rhs: tuple[float, float, float, float],
) -> float:
    lx, ly, lw, lh = lhs
    rx, ry, rw, rh = rhs
    intersection = max(0.0, min(lx + lw, rx + rw) - max(lx, rx)) * max(
        0.0, min(ly + lh, ry + rh) - max(ly, ry)
    )
    minimum_area = max(min(lw * lh, rw * rh), 0.0001)
    return intersection / minimum_area


def unique_owner(matches: list[int]) -> int | None:
    """Model annotateJapaneseVerticalTextRegionOwners' fail-closed mapping."""
    return matches[0] if len(matches) == 1 else None


def has_complete_known_owner_coverage(
    block_owner: int | None,
    candidates: list[LineCandidate],
    results: list[RecoveryResult],
) -> bool:
    """Model the shared block-skip proof and ownerless compatibility."""
    if not candidates or len(results) < len(candidates):
        return False

    available = list(results)
    for candidate in candidates:
        match_index = next(
            (
                index
                for index, result in enumerate(available)
                if result.role in {"verticalLine", "crop"}
                and (
                    (
                        block_owner is not None
                        and result.owner == block_owner
                        and candidate.owner == block_owner
                    )
                    or (
                        block_owner is None
                        and (
                            result.owner is None
                            or candidate.owner is None
                            or result.owner == candidate.owner
                        )
                    )
                )
                and bool(result.text.strip())
                and math.isfinite(result.confidence)
                and 0.0 <= result.confidence <= 1.0
                and result.confidence >= 0.48
                and overlap_ratio(result.rect, candidate.rect) >= 0.72
                and result.rect[2] * result.rect[3]
                <= candidate.rect[2] * candidate.rect[3] * 1.75
            ),
            None,
        )
        if match_index is None:
            return False
        available.pop(match_index)
    return True


class JapaneseRecoveryFrontierBlockSkipContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.crops = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        cls.annotator = function_body(
            cls.vision,
            "private static func annotateJapaneseVerticalTextRegionOwners(\n",
        )
        cls.matches = function_body(
            cls.vision,
            "private static func verticalTextRegionMatchIndices(\n",
        )
        cls.coverage_matches = function_body(
            cls.vision,
            "private static func japaneseLineCoverageMatches(\n",
        )
        cls.coverage = function_body(
            cls.vision,
            "private static func hasCompleteJapaneseLineCoverage(\n",
        )
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("README.md")
            + read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/人工空间/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("md/log/update_log.md")
        )

    def test_recovery_frontier_combines_pixel_and_tile_only_for_block_proof(self) -> None:
        pixel_call = self.crops.index(
            "let pixelFirstRefined = Self.recognizeJapanesePixelFirstVerticalCrops("
        )
        pixel_append = self.crops.index(
            "refined.append(contentsOf: pixelFirstRefined)", pixel_call
        )
        tile_frontier = self.crops.index(
            "let recoveryFrontierObservations = lineRefined + pixelFirstRefined",
            pixel_append,
        )
        tile_call = self.crops.index(
            "Self.recognizeJapaneseVerticalTileFallback(", tile_frontier
        )
        tile_argument = self.crops.index(
            "lineObservations: recoveryFrontierObservations", tile_call
        )
        tile_append = self.crops.index(
            "refined.append(contentsOf: tileRefined)", tile_argument
        )
        owner_frontier = self.crops.index(
            "let ownerAnnotatedRecoveryObservations = annotateJapaneseVerticalTextRegionOwners(",
            tile_append,
        )
        recovery_inputs = self.crops.index(
            "pixelFirstRefined + tileRefined", owner_frontier
        )
        block_frontier = self.crops.index(
            "let blockRecoveryFrontierObservations = lineRefined", recovery_inputs
        )
        combined = self.crops.index(
            "+ ownerAnnotatedRecoveryObservations", block_frontier
        )
        self.assertLess(pixel_call, pixel_append)
        self.assertLess(pixel_append, tile_frontier)
        self.assertLess(tile_frontier, tile_call)
        self.assertLess(tile_call, tile_argument)
        self.assertLess(tile_argument, tile_append)
        self.assertLess(tile_append, owner_frontier)
        self.assertLess(owner_frontier, recovery_inputs)
        self.assertLess(recovery_inputs, block_frontier)
        self.assertLess(block_frontier, combined)

    def test_owner_annotation_is_unique_match_only_and_fail_closed(self) -> None:
        for marker in (
            "let ownerMatches = verticalTextRegionMatchIndices(",
            "if ownerMatches.count == 1",
            "blocks[ownerMatches[0]]",
            ".verticalTextRegionOwner = nil",
        ):
            self.assertIn(marker, self.annotator)
        for marker in (
            "blocks.enumerated().compactMap",
            "block.direction == .vertical",
            "japaneseLineRegionOverlapsBlock(observation, block: block)",
            "isVerticalLineCandidate(lineRegion)",
        ):
            self.assertIn(marker, self.matches)
        self.assertEqual(unique_owner([7]), 7)
        self.assertIsNone(unique_owner([]))
        self.assertIsNone(unique_owner([7, 8]))

    def test_recovery_coverage_guard_reuses_strict_one_to_one_helper(self) -> None:
        block_loop = self.crops[self.crops.index("for block in verticalBlocks") :]
        old_guard = block_loop.index("guard !hasLineOCRResult else { continue }")
        recovery_check = block_loop.index(
            "let hasCompleteRecoveryCoverage = Self.hasCompleteJapaneseLineCoverage("
        )
        recovery_guard = block_loop.index(
            "guard !hasCompleteRecoveryCoverage else { continue }", recovery_check
        )
        crop = block_loop.index("guard let crop = cropImage(", recovery_guard)
        for marker in (
            "sourceObservations: ownerAnnotatedObservations",
            "lineRefined: blockRecoveryFrontierObservations",
            "allowsBlockCropResults: true",
            "guard !hasCompleteRecoveryCoverage else { continue }",
            "blockFallbackCanReplacePartialLines(",
        ):
            self.assertIn(marker, block_loop)
        self.assertLess(old_guard, recovery_check)
        self.assertLess(recovery_check, recovery_guard)
        self.assertLess(recovery_guard, crop)
        for marker in (
            "sourceLineCandidates",
            "ImageOCRLayoutEngine.lineCoverageOwnersProveBlock(",
            "availableLineResults.remove(at: resultIndex)",
        ):
            self.assertIn(marker, self.coverage)
        for marker in ("overlap >= 0.72", "resultArea <= candidateArea * 1.75"):
            self.assertIn(marker, self.coverage_matches)

    def test_complete_known_owner_coverage_skips_but_recovery_risks_do_not(self) -> None:
        candidates = [
            LineCandidate(7, (0.70, 0.10, 0.08, 0.20)),
            LineCandidate(7, (0.70, 0.34, 0.08, 0.20)),
        ]
        complete = [
            RecoveryResult(7, candidates[0].rect, "verticalLine", "今度", 0.82),
            RecoveryResult(7, candidates[1].rect, "crop", "こそ", 0.79),
        ]
        self.assertTrue(has_complete_known_owner_coverage(7, candidates, complete))
        self.assertFalse(
            has_complete_known_owner_coverage(7, candidates, complete[:1])
        )
        self.assertFalse(
            has_complete_known_owner_coverage(
                7,
                candidates,
                [
                    complete[0],
                    RecoveryResult(7, candidates[1].rect, "crop", "弱", 0.47),
                ],
            )
        )

    def test_ownerless_block_keeps_historical_geometry_compatibility(self) -> None:
        candidate = [LineCandidate(None, (0.22, 0.18, 0.08, 0.20))]
        result = RecoveryResult(None, candidate[0].rect, "verticalLine", "今度", 0.82)
        self.assertTrue(has_complete_known_owner_coverage(None, candidate, [result]))
        known_candidate = [LineCandidate(4, candidate[0].rect)]
        self.assertTrue(
            has_complete_known_owner_coverage(
                None,
                known_candidate,
                [RecoveryResult(None, candidate[0].rect, "crop", "こそ", 0.82)],
            )
        )

    def test_ownerless_foreign_and_broad_results_cannot_prove_known_block(self) -> None:
        candidate = [LineCandidate(7, (0.70, 0.20, 0.08, 0.20))]
        cases = (
            RecoveryResult(None, candidate[0].rect, "verticalLine", "今度", 0.90),
            RecoveryResult(8, candidate[0].rect, "verticalLine", "今度", 0.90),
            RecoveryResult(7, candidate[0].rect, "verticalLine", "今度", 0.90),
        )
        self.assertFalse(has_complete_known_owner_coverage(7, candidate, [cases[0]]))
        self.assertFalse(has_complete_known_owner_coverage(7, candidate, [cases[1]]))
        broad = RecoveryResult(7, (0.50, 0.05, 0.45, 0.80), "crop", "今度", 0.90)
        self.assertFalse(has_complete_known_owner_coverage(7, candidate, [broad]))

    def test_existing_budgets_and_output_replacement_boundaries_remain(self) -> None:
        for marker in (
            "limit: 16",
            ".prefix(16)",
            "var orientationFallbacksRemaining = 8",
            "orientationFallbacksRemaining > 0",
            "orientationFallbacksRemaining -= 1",
            "for candidate in candidates.prefix(12)",
            "let maximumTiles = 6",
            "let maximumWindows = 18",
            "maximumJapaneseMangaLineOCRRequests",
            "maximumJapaneseWeakBlockRecoveryRequests",
        ):
            self.assertIn(marker, self.crops + self.vision)
        self.assertEqual(self.crops.count("orientationFallbacksRemaining -= 1"), 1)
        self.assertIn("blockFallbackCanReplacePartialLines(", self.crops)
        self.assertIn("$0.observationRole == .verticalLine", self.crops)

    def test_recovery_frontier_does_not_cross_translation_persistence_or_research(self) -> None:
        for source in (self.crops, self.annotator, self.coverage):
            for forbidden in (
                "TranslationSessionStore",
                "persist(",
                "groundTruth",
                "KOHARU_DATA_ROOT",
                "test/koharu_artifacts",
                "ImageTranslationBlock",
            ):
                self.assertNotIn(forbidden, source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.390", "3.390"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3360-japanese-recovery-frontier-block-skip-contract.py",
            "v3.360",
            "japanese-benchmark-v3.360-",
        ):
            self.assertIn(marker, combined)
        contract = read(
            "scripts/test-v3360-japanese-recovery-frontier-block-skip-contract.py"
        )
        for source in (self.vision, contract):
            for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
                self.assertNotIn(marker, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
