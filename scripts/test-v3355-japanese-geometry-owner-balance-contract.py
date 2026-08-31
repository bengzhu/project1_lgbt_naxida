#!/usr/bin/env python3
"""Static and pure-policy contract for v3.355 geometry-owner balance."""

from dataclasses import dataclass
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
class GeometryCandidate:
    index: int
    owner: int | None


def owner_balanced_selection(
    candidates: list[GeometryCandidate], limit: int
) -> list[GeometryCandidate]:
    """Model the bounded owner-only selector reused by geometry candidates."""
    if limit <= 0:
        return []
    if len(candidates) <= limit:
        return candidates

    owners: list[int] = []
    for candidate in candidates:
        if candidate.owner is not None and candidate.owner not in owners:
            owners.append(candidate.owner)
    if len(owners) <= 1:
        return candidates[:limit]

    selected = list(range(min(limit, len(candidates))))
    counts: dict[int, int] = {}
    for index in selected:
        owner = candidates[index].owner
        if owner is not None:
            counts[owner] = counts.get(owner, 0) + 1

    if len(counts) == len(owners):
        return [candidates[index] for index in selected]

    for owner in owners:
        if owner in counts:
            continue
        candidate_index = next(
            (
                index
                for index, candidate in enumerate(candidates)
                if candidate.owner == owner and index not in selected
            ),
            None,
        )
        if candidate_index is None:
            continue
        drop_index = next(
            (
                index
                for index in reversed(selected)
                if candidates[index].owner is None
                or counts.get(candidates[index].owner, 0) > 1
            ),
            selected[-1],
        )
        dropped_owner = candidates[drop_index].owner
        if dropped_owner is not None:
            counts[dropped_owner] -= 1
        selected.remove(drop_index)
        selected.append(candidate_index)
        counts[owner] = counts.get(owner, 0) + 1

    return [candidates[index] for index in sorted(selected)]


class JapaneseGeometryOwnerBalanceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("README.md")
            + read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("update_log.md")
        )
        cls.candidates = function_body(
            cls.vision,
            "private static func japaneseMangaLineOCRCandidates(\n",
        )
        cls.geometry_selector = function_body(
            cls.vision,
            "private static func boundedJapaneseGeometryOnlyLineCandidates(\n",
        )
        cls.owner_selector = function_body(
            cls.vision,
            "private static func boundedJapaneseMangaLineTextCandidates(\n",
        )

    def test_geometry_reserve_does_not_starve_another_known_owner(self) -> None:
        candidates = [
            GeometryCandidate(0, 4),
            GeometryCandidate(1, 4),
            GeometryCandidate(2, 7),
        ]
        selected = owner_balanced_selection(candidates, limit=2)
        self.assertEqual([candidate.index for candidate in selected], [0, 2])
        self.assertEqual({candidate.owner for candidate in selected}, {4, 7})

    def test_ownerless_candidate_is_displaced_only_when_needed(self) -> None:
        candidates = [
            GeometryCandidate(0, None),
            GeometryCandidate(1, 4),
            GeometryCandidate(2, 7),
        ]
        selected = owner_balanced_selection(candidates, limit=2)
        self.assertEqual([candidate.index for candidate in selected], [1, 2])

    def test_under_budget_and_single_owner_order_remain_unchanged(self) -> None:
        under_budget = [GeometryCandidate(0, 4), GeometryCandidate(1, 7)]
        self.assertEqual(owner_balanced_selection(under_budget, 2), under_budget)
        single_owner = [
            GeometryCandidate(0, 4),
            GeometryCandidate(1, 4),
            GeometryCandidate(2, 4),
        ]
        self.assertEqual(
            owner_balanced_selection(single_owner, 2), single_owner[:2]
        )

    def test_geometry_pool_is_balanced_after_existing_coverage_filter_and_sort(self) -> None:
        for marker in (
            "let uncoveredGeometry = geometryOnlyCandidates",
            "!textBacked.contains { textCandidate in",
            "let geometryReserve = min(",
            "let selectedGeometry = boundedJapaneseGeometryOnlyLineCandidates(",
            "uncoveredGeometry,",
            "limit: geometryReserve",
            "+ selectedGeometry",
        ):
            self.assertIn(marker, self.candidates)
        self.assertNotIn("uncoveredGeometry.prefix(geometryReserve)", self.candidates)
        self.assertLess(
            self.candidates.index("let selectedGeometry ="),
            self.candidates.index("return Array("),
        )

    def test_geometry_selector_reuses_owner_only_policy(self) -> None:
        self.assertIn(
            "boundedJapaneseMangaLineTextCandidates(candidates, limit: limit)",
            self.geometry_selector,
        )
        for marker in (
            "private static func boundedJapaneseMangaLineTextCandidates(",
            "candidate.verticalTextRegionOwner",
        ):
            self.assertIn(marker, self.vision)
        self.assertIn(
            "owner-only bounded selector",
            self.vision,
        )

    def test_two_geometry_slots_and_eight_request_cap_remain(self) -> None:
        for marker in (
            "maximumJapaneseMangaLineOCRRequests = 8",
            "min(2, maximumJapaneseMangaLineOCRRequests)",
            "maximumJapaneseMangaLineOCRRequests - geometryReserve",
            ".prefix(maximumJapaneseMangaLineOCRRequests)",
            "let selectedTextBacked = boundedJapaneseMangaLineTextCandidates(",
        ):
            self.assertIn(marker, self.candidates + self.vision)

    def test_geometry_candidates_keep_existing_coverage_and_identity_gates(self) -> None:
        geometry = function_body(
            self.vision,
            "private static func japaneseGeometryOnlyVerticalLineCandidates(\n",
        )
        for marker in (
            "guard matchingBlocks.count == 1",
            "let owner = block.verticalTextRegionOwner",
            "candidateCoverage >= 0.10",
            "areaRatio <= 1.25",
            "duplicatesTextBackedGeometry",
            "observationRole: .verticalLine",
        ):
            self.assertIn(marker, geometry)

    def test_no_translation_persistence_ground_truth_or_research_side_effect(self) -> None:
        for source in (self.candidates, self.geometry_selector):
            for forbidden in (
                "translate(",
                "persist(",
                "groundTruth",
                "KOHARU_DATA_ROOT",
                "test/koharu_artifacts",
            ):
                self.assertNotIn(forbidden, source)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.384", "3.384"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3354-japanese-direction-owner-domain-contract.py",
            "scripts/test-v3355-japanese-geometry-owner-balance-contract.py",
            "v3.355",
            "japanese-benchmark-v3.356-",
        ):
            self.assertIn(marker, combined)
        contract = Path(__file__).read_text(encoding="utf-8")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
