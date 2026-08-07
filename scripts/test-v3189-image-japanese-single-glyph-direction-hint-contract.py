#!/usr/bin/env python3
"""Contract for preserving vertical direction on one-glyph Japanese crop rereads."""

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


class JapaneseSingleGlyphDirectionHintContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.resolve = braced_body(self.layout, "private static func resolveDirection(")
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_explicit_vertical_hint_accepts_single_cjk_glyph(self) -> None:
        for marker in [
            "let cjkCount = cjkCharacterCount(in: observation.text)",
            "let hasCJKText = cjkCount > 0",
            "let containsTextRun = cjkCount >= 2",
            "observation.sourceDirectionHint == .vertical",
            "hasCJKText",
            'reason: "koharuVerticalCropHint"',
        ]:
            self.assertIn(marker, self.resolve)

        hint = self.resolve.index("observation.sourceDirectionHint == .vertical")
        wide = self.resolve.index("if horizontalRatio >= 1.35")
        self.assertLess(hint, wide)

        hint_block = self.resolve[hint:wide]
        self.assertNotIn("containsTextRun {", hint_block)
        self.assertIn("hasCJKText {", hint_block)

    def test_hint_remains_japanese_manga_only(self) -> None:
        hint = self.resolve.index("observation.sourceDirectionHint == .vertical")
        hint_block = self.resolve[self.resolve.rfind("if allowsVerticalText", 0, hint):]
        self.assertIn("allowsVerticalText", hint_block[: hint_block.index("observation.sourceDirectionHint")])
        self.assertIn("prefersMangaReadingOrder", hint_block[: hint_block.index("observation.sourceDirectionHint")])
        self.assertIn("hasCJKText", hint_block[: hint_block.index("observation.sourceDirectionHint") + 200])
        self.assertIn("containsTextRun", self.resolve)
        self.assertIn('reason: "cjkCompactColumnTextRun"', self.resolve)

    def test_only_vertical_crop_paths_provide_the_hint(self) -> None:
        crop_mapper = braced_body(self.vision, "private static func mapRotatedCropObservation(")
        page_mapper = braced_body(self.vision, "private static func mapRotatedObservation(")
        self.assertIn("sourceDirectionHint: .vertical", crop_mapper)
        self.assertNotIn("sourceDirectionHint: .vertical", page_mapper)
        self.assertIn("sourceDirectionHint: .vertical", braced_body(
            self.vision,
            "private static func recognizeJapanesePerspectiveLineCrop("
        ))
        self.assertIn("sourceDirectionHint: .vertical", braced_body(
            self.vision,
            "private static func synthesizeJapaneseVerticalLineCandidates("
        ))

    def test_scope_stays_layout_only_and_fixture_is_present(self) -> None:
        for forbidden in [
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

    def test_version_and_ci_route_follow_v3188(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 189) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.188;", self.project)
        old = "python3 -B scripts/test-v3188-image-japanese-vertical-cluster-reading-order-contract.py"
        new = "python3 -B scripts/test-v3189-image-japanese-single-glyph-direction-hint-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
