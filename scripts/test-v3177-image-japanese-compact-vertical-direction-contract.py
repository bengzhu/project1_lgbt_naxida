#!/usr/bin/env python3
"""Contract for compact Japanese vertical text-run direction inference."""

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


class JapaneseCompactVerticalDirectionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.layout_body = braced_body(self.layout, "static func layout(")
        self.resolve = braced_body(self.layout, "private static func resolveDirection(")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_japanese_layout_preference_reaches_direction_resolution(self) -> None:
        self.assertIn("prefersMangaReadingOrder: prefersMangaReadingOrder", self.layout_body)
        self.assertIn("prefersMangaReadingOrder: Bool", self.layout)

    def test_compact_gate_precedes_tall_fallback(self) -> None:
        for marker in [
            "let containsTextRun = cjkCount >= 2",
            "prefersMangaReadingOrder",
            "verticalRatio >= 1.35",
            "height >= 0.022",
            "hasColumnNeighbor",
            "!hasRowNeighbor",
            'reason: "cjkCompactColumnTextRun"',
        ]:
            self.assertIn(marker, self.resolve)
        compact_gate = self.resolve.index('reason: "cjkCompactColumnTextRun"')
        tall_gate = self.resolve.index("guard allowsVerticalText, verticalRatio >= 1.6")
        self.assertLess(compact_gate, tall_gate)
        compact_prefix = self.resolve[self.resolve.index("if allowsVerticalText,") : compact_gate]
        self.assertIn("prefersMangaReadingOrder", compact_prefix)

    def test_existing_direction_boundaries_remain(self) -> None:
        for marker in [
            "if horizontalRatio >= 1.35",
            "let isShortCJKObservation = cjkCount > 0 && observation.text.count <= 2",
            "verticalRatio >= 1.05",
            "reason: \"cjkGlyphColumnNeighbors\"",
            "guard allowsVerticalText, verticalRatio >= 1.6, height >= 0.035",
            'reason: hasRowNeighbor ? "horizontalCJKFragment" : "isolatedTallCJKBox"',
        ]:
            self.assertIn(marker, self.resolve)

    def test_scope_stays_layout_only_and_fixture_is_present(self) -> None:
        for forbidden in [
            "VisionOCRService",
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.layout)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3176(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 177) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.176;", self.project)
        old = "python3 -B scripts/test-v3176-image-japanese-line-reading-order-contract.py"
        new = "python3 -B scripts/test-v3177-image-japanese-compact-vertical-direction-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
