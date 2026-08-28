#!/usr/bin/env python3
"""Static and pure-policy contract for v3.340 Japanese line coverage."""

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


Rect = tuple[float, float, float, float]
Observation = tuple[str, Rect]


def intersection_area(lhs: Rect, rhs: Rect) -> float:
    width = max(
        0.0,
        min(lhs[0] + lhs[2], rhs[0] + rhs[2]) - max(lhs[0], rhs[0]),
    )
    height = max(
        0.0,
        min(lhs[1] + lhs[3], rhs[1] + rhs[3]) - max(lhs[1], rhs[1]),
    )
    return width * height


def source_line_candidates(
    observations: list[Observation], block: Rect
) -> list[Observation]:
    """Model the source-role boundary, keeping line-like roles eligible."""
    return [
        observation
        for observation in observations
        if observation[0] != "detectorTextRegion"
        and intersection_area(observation[1], block) > 0.0
    ]


def can_prove_one_to_one_coverage(
    candidates: list[Observation], results: list[Rect]
) -> bool:
    """Model the existing non-empty and one-result-per-source-line proof."""
    if not candidates or len(results) < len(candidates):
        return False
    remaining = list(results)
    for _, candidate_rect in candidates:
        match = next(
            (
                index
                for index, result_rect in enumerate(remaining)
                if intersection_area(candidate_rect, result_rect) > 0.0
            ),
            None,
        )
        if match is None:
            return False
        remaining.pop(match)
    return True


class JapaneseLineCoverageSourceBoundaryContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.coverage = function_body(
            cls.vision,
            "private static func hasCompleteJapaneseLineCoverage(\n",
        )
        cls.source_candidates = function_body(
            cls.vision,
            "private static func japaneseLineCoverageSourceCandidates(\n",
        )
        cls.vertical_crops = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.docs = (
            read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("update_log.md")
        )

    def test_detector_text_region_is_not_a_source_line_candidate(self) -> None:
        guard = "guard observation.observationRole != .detectorTextRegion else"
        self.assertIn(guard, self.source_candidates)
        self.assertLess(
            self.source_candidates.index(guard),
            self.source_candidates.index("let lineRegion"),
        )
        self.assertIn(
            "A bundled detector observation is a block-level TextRegion bbox",
            self.source_candidates,
        )

    def test_detector_only_bbox_cannot_prove_a_multiline_block_is_complete(self) -> None:
        block = (0.20, 0.10, 0.20, 0.70)
        detector_bbox = (0.20, 0.10, 0.20, 0.70)
        one_line_result = (0.20, 0.10, 0.20, 0.24)
        observations = [("detectorTextRegion", detector_bbox)]
        old_candidates = [
            observation
            for observation in observations
            if intersection_area(observation[1], block) > 0.0
        ]
        self.assertTrue(
            can_prove_one_to_one_coverage(old_candidates, [one_line_result])
        )
        self.assertEqual(source_line_candidates(observations, block), [])
        self.assertFalse(
            can_prove_one_to_one_coverage(
                source_line_candidates(observations, block),
                [one_line_result],
            )
        )

    def test_page_crop_and_vertical_line_roles_remain_eligible(self) -> None:
        block = (0.10, 0.10, 0.30, 0.70)
        observations = [
            ("page", (0.12, 0.12, 0.08, 0.20)),
            ("crop", (0.20, 0.12, 0.08, 0.20)),
            ("verticalLine", (0.28, 0.12, 0.08, 0.20)),
            ("detectorTextRegion", block),
        ]
        eligible = source_line_candidates(observations, block)
        self.assertEqual(
            [observation[0] for observation in eligible],
            ["page", "crop", "verticalLine"],
        )
        for marker in (
            "japaneseObservation(observation, belongsTo: block)",
            "overlapRatio(observation.rect, block.rect) >= 0.25",
            "japaneseLineRegionOverlapsBlock(observation, block: block)",
            "isVerticalLineCandidate(lineRegion)",
        ):
            self.assertIn(marker, self.source_candidates)

    def test_owner_quality_geometry_and_one_to_one_proof_remain_required(self) -> None:
        for marker in (
            "japaneseLineCoverageSourceCandidates(",
            "guard !sourceLineCandidates.isEmpty else",
            "availableLineResults.count >= sourceLineCandidates.count",
            "lineCoverageOwnersProveBlock(",
            "isReliableJapaneseLineCoverageResult(",
            "japaneseLineCoverageMatches(",
            "availableLineResults.remove(at: resultIndex)",
        ):
            self.assertIn(marker, self.coverage)

    def test_incomplete_proof_still_reaches_existing_block_fallback(self) -> None:
        for marker in (
            "let hasCompleteLineCoverage = Self.hasCompleteJapaneseLineCoverage(",
            "guard !hasLineOCRResult else { continue }",
            "koharuVerticalBlockCropRect(",
            "var orientationFallbacksRemaining = 8",
            "let primary = recognizeJapaneseCropPass(",
            "let fallbackHasCompleteLineCoverage = Self.hasCompleteJapaneseLineCoverage(",
        ):
            self.assertIn(marker, self.vertical_crops)

    def test_ocr_budget_quality_and_language_scope_are_unchanged(self) -> None:
        for marker in (
            ".prefix(16)",
            "maximumJapaneseMangaLineOCRRequests = 8",
            "maximumJapaneseWeakBlockRecoveryRequests = 4",
            "if sourceLanguage == .japanese",
            "recognitionLanguages: japaneseVerticalRecognitionLanguages",
            "validOCRConfidence(result.confidence) != nil",
        ):
            self.assertIn(marker, self.vision)
        self.assertNotIn("groundTruth", self.vision)

    def test_contract_is_static_only_and_version_route_are_current(self) -> None:
        contract = read(
            "scripts/test-v3340-image-japanese-line-coverage-source-boundary-contract.py"
        )
        for marker in (
            "sub" + "process",
            "Po" + "pen",
            "os." + "system",
            "xc" + "run",
            "xcode" + "build",
            "swift" + "c",
            "car" + "go",
        ):
            self.assertNotIn(marker, contract)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.340", "3.340"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3340-image-japanese-line-coverage-source-boundary-contract.py",
            "v3.340",
            "japanese-benchmark-v3.340-",
        ):
            self.assertIn(marker, combined)


if __name__ == "__main__":
    unittest.main(verbosity=2)
