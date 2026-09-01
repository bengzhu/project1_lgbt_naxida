#!/usr/bin/env python3
"""Static and pure-policy contract for v3.346 tile scheduling."""

from pathlib import Path
import math
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


def legacy_column_first(
    starts: list[int], windows: list[int], limit: int
) -> list[tuple[int, int]]:
    output: list[tuple[int, int]] = []
    for start in sorted(starts, reverse=True):
        for window in windows:
            if len(output) >= limit:
                break
            output.append((start, window))
    return output


def balanced_band_round_robin(
    starts: list[int], windows: list[int], limit: int
) -> list[tuple[int, int]]:
    output: list[tuple[int, int]] = []
    for window in windows:
        for start in sorted(starts, reverse=True):
            if len(output) >= limit:
                return output
            output.append((start, window))
    return output


class JapaneseVerticalTileRoundRobinContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.tiles = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalTileFallback(\n",
        )
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

    def test_round_robin_reaches_other_columns_before_the_same_column_budget_is_spent(
        self,
    ) -> None:
        starts = [0, 100, 200, 300]
        windows = list(range(6))
        limit = 6
        legacy = legacy_column_first(starts, windows, limit)
        balanced = balanced_band_round_robin(starts, windows, limit)
        self.assertEqual({start for start, _ in legacy}, {300})
        self.assertEqual(
            {start for start, _ in balanced},
            {0, 100, 200, 300},
        )
        self.assertEqual(
            balanced[:4],
            [(300, 0), (200, 0), (100, 0), (0, 0)],
        )

    def test_each_column_still_visits_windows_top_to_bottom(self) -> None:
        schedule = balanced_band_round_robin(
            [0, 100, 200, 300], list(range(7)), 18
        )
        for start in [0, 100, 200, 300]:
            column_windows = [window for item_start, window in schedule if item_start == start]
            self.assertEqual(column_windows, sorted(column_windows))

    def test_schedule_is_deterministic_and_never_exceeds_the_existing_budget(
        self,
    ) -> None:
        starts = [40, 0, 120]
        windows = list(range(30))
        first = balanced_band_round_robin(starts, windows, 18)
        second = balanced_band_round_robin(starts, windows, 18)
        self.assertEqual(first, second)
        self.assertEqual(len(first), 18)
        self.assertTrue(all(math.isfinite(float(value)) for item in first for value in item))

    def test_source_uses_band_first_right_to_left_schedule(self) -> None:
        for marker in (
            "let maximumTiles = 6",
            "let maximumWindows = 18",
            "let verticalWindows = japaneseVerticalSliceWindows(",
            "let mangaOrderedStarts = starts.sorted { $0 > $1 }",
            "let shouldUseBandRoundRobin =",
            "verticalWindows.count * mangaOrderedStarts.count > maximumWindows",
            "if shouldUseBandRoundRobin",
            "for window in verticalWindows",
            "for start in mangaOrderedStarts",
            "processJapaneseVerticalTile(start: start, window: window)",
            "for start in mangaOrderedStarts",
            "for window in verticalWindows",
        ):
            self.assertIn(marker, self.tiles)
        self.assertLess(
            self.tiles.index("for window in verticalWindows"),
            self.tiles.index("for start in mangaOrderedStarts"),
        )

    def test_balancing_only_activates_when_the_existing_budget_can_starve_columns(
        self,
    ) -> None:
        self.assertIn(
            "verticalWindows.count * mangaOrderedStarts.count > maximumWindows",
            self.tiles,
        )
        self.assertFalse(2 * 4 > 18)
        self.assertEqual(
            len(legacy_column_first([0, 100, 200, 300], list(range(2)), 18)),
            8,
        )
        self.assertEqual(
            legacy_column_first([0, 100, 200, 300], list(range(2)), 18),
            [(300, 0), (300, 1), (200, 0), (200, 1), (100, 0), (100, 1), (0, 0), (0, 1)],
        )

    def test_existing_coverage_crop_and_orientation_boundaries_remain(self) -> None:
        for marker in (
            "verticalTileIsCovered($0.rect, by: tileRect)",
            "overlapRatio($0, tileRect) >= 0.60",
            "let preparedCrop = prepareJapaneseCropForVision(crop.image)",
            "let verticalPrimary = filterJapaneseVerticalTileObservations(primary)",
            "var orientationFallbacksRemaining = 4",
            "angle: 90",
            "angle: 270",
            "processedWindowCount += 1",
            "return deduplicateJapaneseObservations(refined)",
        ):
            self.assertIn(marker, self.tiles)

    def test_no_new_translation_or_external_evaluation_path_enters_vision_service(
        self,
    ) -> None:
        for forbidden in (
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "KOHARU_DATA_ROOT",
        ):
            self.assertNotIn(forbidden, self.vision)

    def test_version_workflow_docs_and_static_only_contract_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.389", "3.389"],
        )
        self.assertIn(
            "python3 -B scripts/test-v3340-image-japanese-line-coverage-source-boundary-contract.py",
            self.workflow,
        )
        self.assertIn(
            "python3 -B scripts/test-v3341-image-japanese-vertical-tile-round-robin-contract.py",
            self.workflow,
        )
        self.assertIn("japanese-benchmark-v3.347-", self.workflow)
        self.assertIn("v3.347", self.docs)
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, Path(__file__).read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
