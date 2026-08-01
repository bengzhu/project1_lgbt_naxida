#!/usr/bin/env python3
"""Static contracts for v3.62 image summary direction breakdown."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unclosed body for {signature}")


class ImageSummaryDirectionBreakdownContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_summary_surfaces_horizontal_and_vertical_direction_counts(self) -> None:
        summary = function_body(self.store, "var imageTranslationSummary: String")
        self.assertIn("summary.horizontalBlockCount", summary)
        self.assertIn('parts.append("横排 \\(summary.horizontalBlockCount)")', summary)
        self.assertIn("summary.verticalBlockCount", summary)
        self.assertIn('parts.append("竖排 \\(summary.verticalBlockCount)")', summary)
        self.assertIn('parts.append("方向待定 \\(summary.unknownDirectionBlockCount)")', summary)

    def test_summary_only_reads_existing_ocr_summary(self) -> None:
        summary = function_body(self.store, "var imageTranslationSummary: String")
        self.assertIn("ImageOCRResultSummary(blocks: imageTranslationBlocks)", summary)
        for forbidden in [
            "VisionOCRService",
            "runImageTranslation",
            "groundTruth",
            "persist",
        ]:
            self.assertNotIn(forbidden, summary)

    def test_version_and_ci_route_follow_v361(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.62;", self.project)
        old = "python3 -B scripts/test-v361-image-direction-review-context-contract.py"
        new = "python3 -B scripts/test-v362-image-summary-direction-breakdown-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
