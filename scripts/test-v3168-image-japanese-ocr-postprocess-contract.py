#!/usr/bin/env python3
"""Contract for Koharu-style Japanese OCR candidate post-processing."""

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


class JapaneseOCRPostprocessContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.recognize = braced_body(
            self.vision,
            "private static func recognizeObservations(",
        )
        self.select = braced_body(
            self.vision,
            "private static func selectOCRCandidate(",
        )
        self.postprocess = braced_body(
            self.vision,
            "private static func postProcessJapaneseOCRText(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_japanese_path_uses_bounded_top_candidates_and_non_japanese_top_one(self) -> None:
        self.assertIn(
            "observation.topCandidates(postProcessJapaneseText ? 5 : 1)",
            self.recognize,
        )
        self.assertIn(
            "selectOCRCandidate(",
            self.recognize,
        )
        self.assertIn("japanese: postProcessJapaneseText", self.recognize)
        self.assertIn("guard japanese else { return candidates.first }", self.select)
        self.assertIn("bestConfidence - 0.14", self.select)

    def test_postprocess_matches_koharu_normalization_boundary(self) -> None:
        for marker in [
            "filter { !$0.isWhitespace }",
            'replacingOccurrences(of: "…", with: "...")',
            "case 0x2E, 0xFF0E:",
            "String(repeating: \".\", count: dotCount)",
            "0xFEE0",
            "UnicodeScalar(0x3000)!",
        ]:
            self.assertIn(marker, self.postprocess)
        self.assertIn("japaneseCandidateScore", self.select)
        self.assertIn("scriptDensity", self.vision)
        self.assertIn("punctuationDensity", self.vision)

    def test_every_japanese_vision_reread_enables_postprocess(self) -> None:
        self.assertIn(
            "postProcessJapaneseText: sourceLanguage == .japanese",
            self.vision,
        )
        self.assertGreaterEqual(self.vision.count("postProcessJapaneseText: true"), 3)
        self.assertIn("recognizeJapaneseCropPass(", self.vision)
        self.assertIn(
            "let text = postProcessJapaneseText",
            self.recognize,
        )

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

    def test_version_and_ci_route_follow_v3167(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 168) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.167;", self.project)
        old = "python3 -B scripts/test-v3167-image-horizontal-band-dynamic-tolerance-contract.py"
        new = "python3 -B scripts/test-v3168-image-japanese-ocr-postprocess-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
