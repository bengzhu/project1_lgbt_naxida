#!/usr/bin/env python3
"""Contract for the Koharu Japanese OCR post-process ordering boundary."""

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


class JapaneseKoharuPostprocessOrderContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.postprocess = braced_body(
            self.vision,
            "private static func postProcessJapaneseOCRText(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_collapse_runs_before_fullwidth_conversion(self) -> None:
        for marker in [
            'var collapsed = ""',
            "case 0x2E, 0x30FB:",
            'String(repeating: ".", count: dotCount)',
            "collapsed.append(contentsOf:",
            "for scalar in collapsed.unicodeScalars",
            "0xFEE0",
            "UnicodeScalar(0x3000)!",
        ]:
            self.assertIn(marker, self.postprocess)
        self.assertLess(
            self.postprocess.index("collapsed.append(contentsOf:"),
            self.postprocess.index("for scalar in collapsed.unicodeScalars"),
        )
        self.assertLess(
            self.postprocess.index("for scalar in collapsed.unicodeScalars"),
            self.postprocess.index("0xFEE0"),
        )

    def test_japanese_rereads_keep_the_same_postprocess_boundary(self) -> None:
        self.assertIn(
            "postProcessJapaneseText: sourceLanguage == .japanese",
            self.vision,
        )
        self.assertGreaterEqual(self.vision.count("postProcessJapaneseText: true"), 3)
        self.assertIn("recognizeJapaneseCropPass(", self.vision)

    def test_scope_stays_in_ordinary_japanese_ocr(self) -> None:
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

    def test_version_and_ci_route_follow_v3178(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 179) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.178;", self.project)
        old = "python3 -B scripts/test-v3178-image-japanese-compact-block-crop-contract.py"
        new = "python3 -B scripts/test-v3179-image-japanese-koharu-postprocess-order-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
