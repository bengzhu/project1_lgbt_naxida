#!/usr/bin/env python3
"""Static and pure-policy contract for v3.346 Vision line-owner balance."""

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


def owner_balanced_selection(
    candidates: list[tuple[int, int | None]], limit: int
) -> list[tuple[int, int | None]]:
    if limit <= 0:
        return []
    if len(candidates) <= limit:
        return candidates

    owners: list[int] = []
    for _, owner in candidates:
        if owner is not None and owner not in owners:
            owners.append(owner)
    if len(owners) <= 1:
        return candidates[:limit]

    selected = list(range(min(limit, len(candidates))))
    counts: dict[int, int] = {}
    for index in selected:
        owner = candidates[index][1]
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
                for index, (_, candidate_owner) in enumerate(candidates)
                if candidate_owner == owner and index not in selected
            ),
            None,
        )
        if candidate_index is None:
            continue
        drop_index = next(
            (
                index
                for index in reversed(selected)
                if candidates[index][1] is None
                or counts.get(candidates[index][1], 0) > 1
            ),
            selected[-1],
        )
        dropped_owner = candidates[drop_index][1]
        if dropped_owner is not None:
            counts[dropped_owner] -= 1
        selected.remove(drop_index)
        selected.append(candidate_index)
        counts[owner] = counts.get(owner, 0) + 1

    return [candidates[index] for index in sorted(selected)]


class JapaneseVisionLineOwnerBalanceContractTests(unittest.TestCase):
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
            + read("md/人工空间/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("md/log/update_log.md")
        )
        cls.line_crops = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalLineCrops(\n",
        )
        cls.manga_candidates = function_body(
            cls.vision,
            "private static func japaneseMangaLineOCRCandidates(\n",
        )
        cls.vision_balancer = function_body(
            cls.vision,
            "private static func boundedJapaneseVisionLineCandidates(\n",
        )
        cls.manga_balancer = function_body(
            cls.vision,
            "private static func boundedJapaneseMangaLineTextCandidates(\n",
        )

    def test_one_known_owner_cannot_fill_both_vision_prefixes(self) -> None:
        candidates = [
            (0, 4),
            (1, 4),
            (2, 4),
            (3, 4),
            (4, 4),
            (5, 4),
            (6, 7),
            (7, 7),
        ]
        selected = owner_balanced_selection(candidates, 6)
        self.assertEqual([index for index, _ in selected], [0, 1, 2, 3, 4, 6])
        self.assertEqual({owner for _, owner in selected}, {4, 7})
        self.assertEqual(len(selected), 6)

    def test_ownerless_and_under_budget_pages_keep_historical_selection(self) -> None:
        candidates = [(0, 2), (1, None), (2, 3)]
        self.assertEqual(owner_balanced_selection(candidates, 5), candidates)
        single_owner = [(0, 2), (1, 2), (2, 2)]
        self.assertEqual(owner_balanced_selection(single_owner, 2), single_owner[:2])
        ownerless = [(0, None), (1, None), (2, 2), (3, 2)]
        selected = owner_balanced_selection(ownerless, 3)
        self.assertEqual([index for index, _ in selected], [0, 1, 2])

    def test_vision_perspective_and_axis_queues_call_the_balancer(self) -> None:
        self.assertEqual(
            self.line_crops.count("boundedJapaneseVisionLineCandidates("),
            2,
        )
        perspective_start = self.line_crops.index(
            "let perspectiveCandidates = Array("
        )
        perspective_balance = self.line_crops.index(
            "boundedJapaneseVisionLineCandidates(", perspective_start
        )
        self.assertLess(perspective_start, perspective_balance)
        self.assertIn("uniqueCandidates,", self.line_crops[perspective_balance:])

        axis_start = self.line_crops.index("let axisCandidates = Array(")
        axis_balance = self.line_crops.index(
            "boundedJapaneseVisionLineCandidates(", axis_start
        )
        self.assertLess(axis_start, axis_balance)
        self.assertIn("deduplicateJapaneseObservations(axisSeeds)", self.line_crops)
        self.assertEqual(self.line_crops.count("limit: 24"), 2)
        self.assertEqual(self.line_crops.count(".prefix(24)"), 2)
        self.assertNotIn(
            "let perspectiveCandidates = Array(uniqueCandidates.prefix(24))",
            self.line_crops,
        )

    def test_shared_vision_helper_reuses_existing_explicit_owner_policy(self) -> None:
        self.assertIn(
            "boundedJapaneseMangaLineTextCandidates(candidates, limit: limit)",
            self.vision_balancer,
        )
        for marker in (
            "guard candidates.count > limit else { return candidates }",
            "var knownOwners: [Int] = []",
            "candidate.verticalTextRegionOwner",
            "guard knownOwners.count > 1 else",
            "var selectedIndices = Array(candidates.indices.prefix(limit))",
            "selectedOwnerCounts",
            "guard selectedOwners.count < knownOwners.count else",
            "for owner in knownOwners where !selectedOwnerCounts.keys.contains(owner)",
            "selectedIndices.reversed().first",
            "selectedIndices.sorted().map",
        ):
            self.assertIn(marker, self.manga_balancer)

    def test_manga_queue_and_geometry_reserve_remain_separate(self) -> None:
        for marker in (
            "let geometryReserve =",
            "let textLimit = max(",
            "boundedJapaneseMangaLineTextCandidates(",
            "limit: textLimit",
            "let selectedGeometry = boundedJapaneseGeometryOnlyLineCandidates(",
            ".prefix(maximumJapaneseMangaLineOCRRequests)",
        ):
            self.assertIn(marker, self.manga_candidates)
        self.assertLess(
            self.manga_candidates.index("let geometryReserve ="),
            self.manga_candidates.index("let selectedTextBacked ="),
        )

    def test_vision_request_budgets_and_quality_boundaries_do_not_expand(self) -> None:
        for marker in (
            "limit: 24",
            "consumedPixels: &perspectiveWarpPixels",
            "consumedPixels + preparedPixels <= 16_000_000",
            "var orientationFallbacksRemaining = 12",
            "meaningfulJapaneseRecoveryObservations(",
            "observationRole: .verticalLine",
        ):
            self.assertIn(marker, self.line_crops + self.vision)
        self.assertIn("maximumJapaneseMangaLineOCRRequests = 8", self.vision)
        self.assertIn("min(2, maximumJapaneseMangaLineOCRRequests)", self.vision)
        self.assertIn("try await MangaOCRService.shared.recognize(", self.vision)

    def test_ownerless_is_not_invented_and_downstream_boundaries_remain(self) -> None:
        self.assertIn("guard let owner = candidate.verticalTextRegionOwner", self.manga_balancer)
        self.assertIn(
            "ownerless candidates are not counted as owners and are only",
            self.vision,
        )
        vertical_crops = function_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        self.assertLess(
            vertical_crops.index("recognizeJapaneseVerticalLineCrops("),
            vertical_crops.index("for block in verticalBlocks"),
        )
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)
        for source in (self.vision, self.line_crops, self.vision_balancer):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.390", "3.390"],
        )
        self.assertIn(
            "python3 -B scripts/test-v3343-japanese-vision-line-owner-balance-contract.py",
            self.workflow,
        )
        self.assertIn("japanese-benchmark-v3.347-", self.workflow)
        self.assertIn("v3.347", self.docs)
        contract = Path(__file__).read_text(encoding="utf-8")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
