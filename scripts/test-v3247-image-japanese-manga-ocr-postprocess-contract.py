#!/usr/bin/env python3
"""Contract for the Koharu-equivalent bundled Manga OCR post-processing order."""

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


class JapaneseMangaOCRPostProcessContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOCRService.swift")
        self.post_process = braced_body(self.service, "private static func postProcess(")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.single_page_runtime = read(
            "scripts/test-v3214-image-japanese-manga-ocr-runtime.sh"
        )
        self.long_page_runtime = read(
            "scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh"
        )

    def test_koharu_order_collapses_dots_before_fullwidth_conversion(self) -> None:
        for marker in [
            "let canonicalText = JapaneseOCRTextNormalizer.canonicalized(text)",
            "let noWhitespace = canonicalText.filter { !$0.isWhitespace }",
            '.replacing("…", with: "...")',
            "var collapsed = \"\"",
            "func flushDots()",
            "scalar.value == 0x2E || scalar.value == 0xFF0E",
            "collapsed.unicodeScalars.append(scalar)",
            "for scalar in collapsed.unicodeScalars",
            "(0x21...0x7E).contains(scalar.value)",
            "UnicodeScalar(scalar.value + 0xFEE0)",
        ]:
            self.assertIn(marker, self.post_process)
        self.assertNotIn(
            'output.append(String(repeating: ".", count: dotCount))',
            self.post_process,
        )

    def test_spaces_and_ascii_punctuation_keep_koharu_fullwidth_boundary(self) -> None:
        self.assertIn(
            "scalar.value == 0x20",
            self.post_process,
        )
        self.assertIn(
            "UnicodeScalar(0x3000)",
            self.post_process,
        )
        self.assertIn(
            '"前は生意気に俺の誘い断りやがって．．．"',
            self.single_page_runtime,
        )
        self.assertIn(
            '"そのせいでつまんねー女に絡まれるし．．．"',
            self.single_page_runtime,
        )
        self.assertIn(
            '"前は生意気に俺の誘い断りやがって．．．"',
            self.long_page_runtime,
        )

    def test_ocr_execution_boundaries_remain_unchanged(self) -> None:
        for marker in [
            "try await MangaOCRService.shared.recognize(",
            "catch is CancellationError",
            "throw CancellationError()",
        ]:
            self.assertIn(marker, read("AITRANS/Services/VisionOCRService.swift"))
        for forbidden in [
            "VisionOCRService",
            "groundTruth",
            "test/koharu_artifacts",
            "MangaOverlayProbeService",
        ]:
            self.assertNotIn(forbidden, self.service)

    def test_version_and_ci_route_follow_v3246(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 247) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.246;", self.project)
        previous = "python3 -B scripts/test-v3246-image-japanese-directional-koharu-padding-contract.py"
        current = "python3 -B scripts/test-v3247-image-japanese-manga-ocr-postprocess-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3247-image-japanese-manga-ocr-postprocess-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
