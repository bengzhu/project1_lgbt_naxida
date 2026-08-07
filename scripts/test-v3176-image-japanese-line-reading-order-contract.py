#!/usr/bin/env python3
"""Contract for direction-aware assembly of Japanese perspective line OCR."""

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


class JapaneseLineReadingOrderContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.perspective = braced_body(
            self.vision,
            "private static func recognizeJapanesePerspectiveLineCrop(",
        )
        self.order = braced_body(
            self.vision,
            "private static func orderedJapanesePerspectiveLineObservations(",
        )

    def test_perspective_lines_use_shared_direction_aware_order(self) -> None:
        self.assertIn(
            "let ordered = orderedJapanesePerspectiveLineObservations(\n            observations,\n            angle: angle\n        )",
            self.perspective,
        )
        self.assertNotIn("let ordered = observations.sorted", self.perspective)
        for marker in [
            "let xTolerance = 0.02",
            "let readsRightToLeft = angle == 270",
            "let xDelta = abs(lhs.rect.midX - rhs.rect.midX)",
            "lhs.rect.midX > rhs.rect.midX",
            "lhs.rect.midX < rhs.rect.midX",
            "let yDelta = abs(lhs.rect.midY - rhs.rect.midY)",
            "return isBetterJapaneseObservation(lhs, rhs)",
        ]:
            self.assertIn(marker, self.order)

    def test_koharu_rotation_direction_and_safe_tie_breaker_are_explicit(self) -> None:
        for marker in [
            "same reading",
            "direction as Koharu's `rotate270` vertical line crop",
            "the 90-degree pass reads left-to-right",
            "the 270-degree pass reads",
            "right-to-left",
            "guard observations.count > 1 else { return observations }",
        ]:
            self.assertIn(marker, self.vision)
        self.assertIn("angle: angle", self.perspective)

    def test_scope_stays_in_japanese_perspective_line_assembly(self) -> None:
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "FileManager",
            "TranslationSessionStore",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3175(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 176) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.175;", self.project)
        old = "python3 -B scripts/test-v3175-image-japanese-font-size-padding-contract.py"
        new = "python3 -B scripts/test-v3176-image-japanese-line-reading-order-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
