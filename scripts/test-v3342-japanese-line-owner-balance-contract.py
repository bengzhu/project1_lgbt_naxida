#!/usr/bin/env python3
"""Static and pure-policy contract for v3.346 Japanese line-owner balance."""

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


class JapaneseLineOwnerBalanceContractTests(unittest.TestCase):
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
            + read(
                "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
            )
            + read("update_log.md")
        )
        cls.candidates = function_body(
            cls.vision,
            "private static func japaneseMangaLineOCRCandidates(\n",
        )
        cls.balancer = function_body(
            cls.vision,
            "private static func boundedJapaneseMangaLineTextCandidates(\n",
        )
        cls.recognizer = function_body(
            cls.vision,
            "private static func recognizeJapaneseMangaLineOCR(\n",
        )

    def test_one_owner_cannot_starve_another_known_owner(self) -> None:
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
        self.assertIn(7, [owner for _, owner in selected])
        self.assertEqual(len(selected), 6)

    def test_risk_order_and_under_budget_pages_remain_unchanged(self) -> None:
        candidates = [(0, 2), (1, 2), (2, 3)]
        self.assertEqual(owner_balanced_selection(candidates, 5), candidates)
        single_owner = [(0, 2), (1, 2), (2, 2)]
        self.assertEqual(owner_balanced_selection(single_owner, 2), single_owner[:2])
        already_fair = [(0, 2), (1, 3), (2, 2), (3, 3)]
        self.assertEqual(owner_balanced_selection(already_fair, 3), already_fair[:3])

    def test_selection_keeps_original_queue_order_and_budget(self) -> None:
        candidates = [(0, 4), (1, 4), (2, None), (3, 4), (4, 7), (5, 7), (6, 8)]
        selected = owner_balanced_selection(candidates, 5)
        self.assertEqual([index for index, _ in selected], sorted(index for index, _ in selected))
        self.assertLessEqual(len(selected), 5)
        self.assertEqual(len({index for index, _ in selected}), len(selected))

    def test_source_calls_owner_balancer_after_geometry_reserve(self) -> None:
        self.assertLess(
            self.candidates.index("let geometryReserve ="),
            self.candidates.index("let selectedTextBacked ="),
        )
        for marker in (
            "boundedJapaneseMangaLineTextCandidates(",
            "limit: textLimit",
            "selectedTextBacked",
            "let selectedGeometry = boundedJapaneseGeometryOnlyLineCandidates(",
            "selectedGeometry",
            ".prefix(maximumJapaneseMangaLineOCRRequests)",
        ):
            self.assertIn(marker, self.candidates)

    def test_balancer_only_promotes_missing_known_owners(self) -> None:
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
            self.assertIn(marker, self.balancer)

    def test_ownerless_is_not_invented_and_result_budget_is_unchanged(self) -> None:
        self.assertIn("guard let owner = candidate.verticalTextRegionOwner", self.balancer)
        self.assertIn(
            "ownerless candidates are not counted as owners and are only",
            self.vision,
        )
        for marker in (
            "maximumJapaneseMangaLineOCRRequests = 8",
            "min(2, maximumJapaneseMangaLineOCRRequests)",
            "maximumJapaneseMangaLineOCRRequests - geometryReserve",
            "try await MangaOCRService.shared.recognize(",
            "validOCRConfidence(result.confidence)",
            "confidence >= 0.55",
        ):
            self.assertIn(marker, self.candidates + self.recognizer + self.vision)

    def test_line_first_translation_and_cancellation_boundaries_remain(self) -> None:
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
        for source in (self.vision, self.candidates, self.balancer):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.380", "3.380"],
        )
        self.assertIn(
            "python3 -B scripts/test-v3342-japanese-line-owner-balance-contract.py",
            self.workflow,
        )
        self.assertIn("japanese-benchmark-v3.347-", self.workflow)
        self.assertIn("v3.347", self.docs)
        contract = Path(__file__).read_text(encoding="utf-8")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
