#!/usr/bin/env python3
"""Static contracts for v3.63 image summary accessibility context."""

from pathlib import Path
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
                return source[brace:index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageSummaryAccessibilityContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_summary_header_is_one_stable_accessibility_element(self) -> None:
        header = self.panel[self.panel.index('title: "识别结果"'):]
        header = header[:header.index("if !store.imageTranslationBlocks.isEmpty")]
        self.assertIn(".accessibilityElement(children: .ignore)", header)
        self.assertIn('.accessibilityLabel("识别结果")', header)
        self.assertIn(".accessibilityValue(store.imageTranslationSummary)", header)
        self.assertIn(".accessibilityHint(imageSummaryAccessibilityHint)", header)
        self.assertIn(".accessibilityAddTraits(.isHeader)", header)

    def test_hint_describes_empty_locked_and_reviewable_states(self) -> None:
        hint = braced_body(self.panel, "private var imageSummaryAccessibilityHint")
        self.assertIn("store.imageTranslationBlocks.isEmpty", hint)
        self.assertIn("imageReviewUnavailableDetail", hint)
        self.assertIn("allReviewRequiredBlocks.isEmpty", hint)
        self.assertIn("筛选、定位、修正或更新文字块复查进度", hint)

    def test_accessibility_context_has_no_new_ocr_or_store_mutation_path(self) -> None:
        hint = braced_body(self.panel, "private var imageSummaryAccessibilityHint")
        for forbidden in [
            "VisionOCRService",
            "runImageTranslation",
            "persist",
            "groundTruth",
            "store.mark",
            "store.reopen",
            "store.reset",
        ]:
            self.assertNotIn(forbidden, hint)
        summary = braced_body(self.store, "var imageTranslationSummary: String")
        self.assertIn("ImageOCRResultSummary(blocks: imageTranslationBlocks)", summary)

    def test_version_and_ci_route_follow_v362(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.63;", self.project)
        old = "python3 -B scripts/test-v362-image-summary-direction-breakdown-contract.py"
        new = "python3 -B scripts/test-v363-image-summary-accessibility-context-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
