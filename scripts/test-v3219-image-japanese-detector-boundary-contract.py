#!/usr/bin/env python3
"""Contract for preserving Koharu detector TextRegion boundaries after OCR."""

from pathlib import Path
import os
import re
import subprocess
import tempfile
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


class JapaneseDetectorBoundaryContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.runtime = read(
            "scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh"
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_bundled_manga_ocr_marks_detector_text_region_boundaries(self) -> None:
        manga = braced_body(
            self.vision,
            "private static func recognizeJapaneseMangaOCR(",
        )
        final_mapping = braced_body(
            self.vision,
            "func recognizeTextBlocks(",
        )
        self.assertIn("preservesDetectorTextRegionBoundary:", manga)
        self.assertIn("Self.isReliableJapaneseMangaOCRResult(result)", manga)
        self.assertIn(
            "preservesDetectorTextRegionBoundary: $0.preservesDetectorTextRegionBoundary",
            final_mapping,
        )

    def test_japanese_dedupe_carries_boundary_onto_selected_text(self) -> None:
        dedupe = braced_body(
            self.vision,
            "private static func deduplicateObservations(",
        )
        self.assertIn(
            "output[duplicateIndex].preservesDetectorTextRegionBoundary =",
            dedupe,
        )
        self.assertIn("let preservesDetectorTextRegionBoundary =", dedupe)
        self.assertIn("observation.preservesDetectorTextRegionBoundary", dedupe)
        self.assertIn(
            "|| output[duplicateIndex].preservesDetectorTextRegionBoundary",
            dedupe,
        )

    def test_vertical_layout_rejects_only_protected_to_protected_merge(self) -> None:
        merge = braced_body(
            self.layout,
            "private static func shouldMergeVertically(",
        )
        cluster = braced_body(self.layout, "private struct Cluster")
        for marker in [
            "line.preservesDetectorTextRegionBoundary",
            "cluster.containsPreservedDetectorTextRegionBoundary",
            "return false",
        ]:
            self.assertIn(marker, merge)
        self.assertIn(
            "observations.contains(where: \\.preservesDetectorTextRegionBoundary)",
            cluster,
        )
        self.assertIn("return sameColumn && gap >= -0.015", merge)

    def test_executable_layout_boundary_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v3219-swift-") as temporary:
            executable = Path(temporary) / "v3219-detector-boundary"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-module-cache-path",
                    str(Path(temporary) / "module-cache"),
                    "AITRANS/Services/ImageOCRLayoutEngine.swift",
                    "scripts/fixtures/v3219-detector-boundary-layout-evaluator.swift",
                    "-o",
                    str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(executable)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn(
                "v3.219 detector TextRegion boundary evaluator passed",
                result.stdout,
            )

    def test_real_long_page_runtime_rejects_cross_page_concatenation(self) -> None:
        for marker in [
            "int(match.group(1)) < 16",
            "len(vertical_rects) < 16",
            "< 4:",
            '"お願いします前は" in text',
            'sum("では最後に" in value for value in vertical_texts) < 4',
        ]:
            self.assertIn(marker, self.runtime)

    def test_scope_stays_inside_ocr_layout_and_real_fixture(self) -> None:
        for source in [self.layout, self.vision]:
            for forbidden in [
                "groundTruth",
                "test/koharu_artifacts",
                "MangaOverlayProbeService",
                "TranslationSessionStore",
            ]:
                self.assertNotIn(forbidden, source)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)

    def test_version_and_ci_route_follow_v3218(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 219) for version in versions)
        )
        previous = (
            "python3 -B "
            "scripts/test-v3218-image-japanese-long-page-ocr-budget-contract.py"
        )
        current = (
            "python3 -B "
            "scripts/test-v3219-image-japanese-detector-boundary-contract.py"
        )
        runtime = (
            "bash "
            "scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh"
        )
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertIn(runtime, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertLess(self.workflow.index(current), self.workflow.index(runtime))
        self.assertIn(
            "if grep -Fx "
            "'scripts/test-v3219-image-japanese-detector-boundary-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
