#!/usr/bin/env python3
"""Contract for Japanese manga-style RTL ordering of horizontal OCR bands."""

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


class JapaneseHorizontalReadingOrderContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.horizontal = braced_body(
            self.layout,
            "private static func orderedHorizontalBands(",
        )

    def test_manga_flag_is_explicit_and_non_manga_default_remains(self) -> None:
        self.assertIn("prefersMangaReadingOrder: Bool = false", self.layout)
        self.assertIn(
            "prefersRightToLeft: prefersMangaReadingOrder",
            self.layout,
        )
        self.assertIn(
            "prefersMangaReadingOrder: sourceLanguage == .japanese",
            self.vision,
        )
        self.assertIn(
            "prefersMangaReadingOrder: true",
            self.vision,
        )

    def test_horizontal_bands_keep_rows_and_reverse_only_the_manga_axis(self) -> None:
        self.assertIn("prefersRightToLeft: Bool", self.layout)
        self.assertGreaterEqual(
            self.horizontal.count("prefersRightToLeft ? -$0.rect.x : $0.rect.x"),
            2,
        )
        self.assertGreaterEqual(
            self.horizontal.count("prefersRightToLeft ? -$1.rect.x : $1.rect.x"),
            2,
        )
        self.assertTrue(
            "observation.rect.y - anchor <= 0.02" in self.horizontal
            or "observation.rect.y - anchor <= rowTolerance" in self.horizontal
        )
        self.assertNotIn("orderedHorizontalBands(_ observations: [ResolvedObservation])", self.layout)

    def test_scope_stays_layout_and_ocr_integration_only(self) -> None:
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

    def test_version_and_ci_route_follow_v3163(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 164) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.163;", self.project)
        old = "python3 -B scripts/test-v3163-image-japanese-reading-order-contract.py"
        new = "python3 -B scripts/test-v3164-image-japanese-horizontal-reading-order-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
