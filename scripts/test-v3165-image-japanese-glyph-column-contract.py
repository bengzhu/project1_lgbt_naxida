#!/usr/bin/env python3
"""Contract for retaining short CJK glyphs as Japanese vertical columns."""

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


class JapaneseGlyphColumnContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.resolve = braced_body(self.layout, "private static func resolveDirection(")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_short_cjk_column_gate_precedes_tall_box_fallback(self) -> None:
        for marker in [
            "let isShortCJKObservation = cjkCount > 0 && observation.text.count <= 2",
            "verticalRatio >= 1.05",
            "height >= 0.015",
            "hasColumnNeighbor",
            "!hasRowNeighbor",
            "reason: \"cjkGlyphColumnNeighbors\"",
        ]:
            self.assertIn(marker, self.resolve)
        glyph_gate = self.resolve.index("isShortCJKObservation")
        tall_gate = self.resolve.index("guard allowsVerticalText, verticalRatio >= 1.6")
        self.assertLess(glyph_gate, tall_gate)

    def test_horizontal_and_isolated_boundaries_remain(self) -> None:
        self.assertIn("if horizontalRatio >= 1.35", self.resolve)
        self.assertIn("!hasRowNeighbor", self.resolve)
        self.assertIn("guard allowsVerticalText, verticalRatio >= 1.6, height >= 0.035", self.resolve)
        self.assertIn("reason: hasRowNeighbor ? \"horizontalCJKFragment\" : \"isolatedTallCJKBox\"", self.resolve)

    def test_scope_stays_layout_only(self) -> None:
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

    def test_version_and_ci_route_follow_v3164(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 165) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.164;", self.project)
        old = "python3 -B scripts/test-v3164-image-japanese-horizontal-reading-order-contract.py"
        new = "python3 -B scripts/test-v3165-image-japanese-glyph-column-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
