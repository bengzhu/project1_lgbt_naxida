#!/usr/bin/env python3
"""Contract for Koharu-style line-region geometry during Japanese OCR fusion."""

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


class JapaneseLineGeometryDedupeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.recognize = braced_body(
            self.vision,
            "func recognizeTextBlocks(in imageData: Data, sourceLanguage: SupportedLanguage)",
        )
        self.dedupe = braced_body(
            self.vision,
            "private static func deduplicateObservations(",
        )
        self.duplicate = braced_body(
            self.vision,
            "private static func isDuplicateObservation(",
        )
        self.lines = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_japanese_duplicate_geometry_requires_two_line_region_hints(self) -> None:
        self.assertIn("prefersJapanese: Bool = false", self.vision)
        for marker in [
            "if prefersJapanese,",
            "let lhsLineRegion = lhs.lineRegionRect",
            "let rhsLineRegion = rhs.lineRegionRect",
            "lhsGeometry = lhsLineRegion",
            "rhsGeometry = rhsLineRegion",
            "lhsGeometry = lhs.rect",
            "rhsGeometry = rhs.rect",
            "intersectionArea(lhsGeometry, rhsGeometry)",
            "lhsGeometry.width * lhsGeometry.height",
            "rhsGeometry.width * rhsGeometry.height",
        ]:
            self.assertIn(marker, self.duplicate)

    def test_japanese_callers_propagate_geometry_preference(self) -> None:
        self.assertIn(
            "isDuplicateObservation(\n                    observation,\n                    of: $0,\n                    prefersJapanese: prefersJapanese",
            self.dedupe,
        )
        self.assertIn(
            "isDuplicateObservation(candidate, of: $0, prefersJapanese: true)",
            self.lines,
        )
        self.assertIn(
            "deduplicateObservations(observations, prefersJapanese: true)",
            self.vision,
        )

    def test_non_japanese_path_keeps_request_box_dedupe(self) -> None:
        self.assertIn(
            ": Self.deduplicateObservations(observations)",
            self.recognize,
        )
        self.assertIn(
            "private static func isDuplicateObservation(",
            self.vision,
        )
        self.assertIn(
            "retain the request box as a safe fallback",
            self.vision,
        )

    def test_migration_stays_model_and_probe_independent(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3183(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 184) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.183;", self.project)
        old = "python3 -B scripts/test-v3183-image-japanese-line-warp-target-contract.py"
        new = "python3 -B scripts/test-v3184-image-japanese-line-geometry-dedupe-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
