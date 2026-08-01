#!/usr/bin/env python3
"""Static contracts for v3.54 dynamic image status accessibility value."""

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


class ImageStatusValueContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_status_value_uses_live_title_and_detail_interpolation(self) -> None:
        panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        value = braced_body(panel, "private var imageStatusAccessibilityValue: String")
        self.assertIn('"\\(statusTitle)：\\(statusDetail)"', value)
        self.assertNotIn('"(statusTitle)：(statusDetail)"', value)

    def test_status_row_still_exposes_a_single_named_element(self) -> None:
        panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        inspector = braced_body(panel, "private var inspector: some View")
        self.assertIn(".accessibilityElement(children: .ignore)", inspector)
        self.assertIn('.accessibilityLabel("图片翻译状态")', inspector)
        self.assertIn(".accessibilityValue(imageStatusAccessibilityValue)", inspector)
        self.assertIn(".accessibilityHint(imageStatusAccessibilityHint)", inspector)

    def test_version_and_ci_route_follow_v353(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.54;", self.project)
        old = "python3 -B scripts/test-v353-image-ignored-row-accessibility-contract.py"
        new = "python3 -B scripts/test-v354-image-status-value-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
