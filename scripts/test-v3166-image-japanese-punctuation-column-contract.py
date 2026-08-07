#!/usr/bin/env python3
"""Contract for treating Japanese CJK punctuation as vertical-column evidence."""

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


class JapanesePunctuationColumnContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.count = braced_body(self.layout, "private static func cjkCharacterCount(")
        self.resolve = braced_body(self.layout, "private static func resolveDirection(")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_cjk_punctuation_and_halfwidth_katakana_are_counted(self) -> None:
        for marker in [
            "0x3000...0x303F",
            "0x3040...0x30FF",
            "0xFF61...0xFF9F",
        ]:
            self.assertIn(marker, self.count)
        self.assertIn("let cjkCount = cjkCharacterCount(in: observation.text)", self.resolve)
        self.assertIn(
            "let isShortCJKObservation = cjkCount > 0 && observation.text.count <= 2",
            self.resolve,
        )

    def test_punctuation_still_requires_column_geometry(self) -> None:
        gate = self.resolve[self.resolve.index("if allowsVerticalText,") :]
        for marker in [
            "isShortCJKObservation",
            "verticalRatio >= 1.05",
            "height >= 0.015",
            "hasColumnNeighbor",
            "!hasRowNeighbor",
            "reason: \"cjkGlyphColumnNeighbors\"",
        ]:
            self.assertIn(marker, gate)
        self.assertIn("guard allowsVerticalText, verticalRatio >= 1.6, height >= 0.035", self.resolve)

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

    def test_version_and_ci_route_follow_v3165(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 166) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.165;", self.project)
        old = "python3 -B scripts/test-v3165-image-japanese-glyph-column-contract.py"
        new = "python3 -B scripts/test-v3166-image-japanese-punctuation-column-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
