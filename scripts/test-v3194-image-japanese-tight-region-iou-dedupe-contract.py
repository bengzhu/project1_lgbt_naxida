#!/usr/bin/env python3
"""Contract for Koharu-style IoU deduplication of Japanese line regions."""

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


class JapaneseTightRegionIoUDedupeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.duplicate = braced_body(
            self.vision,
            "private static func isDuplicateObservation(",
        )
        self.iou = braced_body(
            self.vision,
            "private static func intersectionOverUnion(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_iou_geometry_rule_is_tight_and_japanese_only(self) -> None:
        for marker in [
            "let hasTightJapaneseGeometry = prefersJapanese",
            "&& lhs.lineRegionRect != nil",
            "&& rhs.lineRegionRect != nil",
            "let tightRegionIoU = intersectionOverUnion(lhsGeometry, rhsGeometry)",
            "if overlap >= 0.85 || tightRegionIoU >= 0.50",
            "return true",
            "same-label",
        ]:
            self.assertIn(marker, self.duplicate)
        self.assertLess(
            self.duplicate.index("let tightRegionIoU = intersectionOverUnion(lhsGeometry, rhsGeometry)"),
            self.duplicate.index("let leftText = normalizedOCRText(lhs.text)"),
        )

    def test_iou_uses_union_area_and_safe_zero_boundary(self) -> None:
        for marker in [
            "let intersection = intersectionArea(lhs, rhs)",
            "let lhsArea = max(lhs.width * lhs.height, 0)",
            "let rhsArea = max(rhs.width * rhs.height, 0)",
            "let union = lhsArea + rhsArea - intersection",
            "guard union > 0 else { return 0 }",
            "return intersection / union",
        ]:
            self.assertIn(marker, self.iou)

    def test_request_boxes_and_non_japanese_paths_keep_text_gate(self) -> None:
        for marker in [
            "lhsGeometry = lhs.rect",
            "rhsGeometry = rhs.rect",
            "leftText == rightText || leftText.contains(rightText)",
            "overlap >= 0.72 && textSimilarity(leftText, rightText) >= 0.62",
            "Request-level boxes remain text-dependent",
        ]:
            self.assertIn(marker, self.duplicate)
        self.assertNotIn("intersectionOverUnion(lhs.rect, rhs.rect)", self.duplicate)

    def test_migration_stays_model_and_probe_independent(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)
        self.assertGreater((ROOT / "test/jap.jpg").stat().st_size, 100_000)

    def test_version_and_ci_route_follow_v3193(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.194", "3.194"])
        old = "python3 -B scripts/test-v3193-image-japanese-tight-region-dedupe-contract.py"
        new = "python3 -B scripts/test-v3194-image-japanese-tight-region-iou-dedupe-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
