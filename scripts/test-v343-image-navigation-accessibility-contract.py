#!/usr/bin/env python3
"""Static contracts for v3.43 image navigation accessibility feedback."""

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


class ImageNavigationAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_focus_navigation_explains_boundaries(self) -> None:
        focus = braced_body(self.view, "private struct ImageTranslationFocusPreview: View")
        self.assertIn(".disabled(!canSelectPrevious)", focus)
        self.assertIn("当前已是筛选结果中的第一个文字块", focus)
        self.assertIn(".disabled(!canSelectNext)", focus)
        self.assertIn("当前已是筛选结果中的最后一个文字块", focus)
        self.assertIn("? \"定位上一个文字块\"", focus)
        self.assertIn("? \"定位下一个文字块\"", focus)

    def test_result_row_selection_hint_matches_current_state(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        self.assertIn(".accessibilityValue(accessibilityValue)", row)
        self.assertIn("isSelected ? \"已在图片中定位\" : \"未定位\"", row)
        self.assertIn("? \"取消此文字块在图片中的定位\"", row)
        self.assertIn(": \"在图片预览中定位此文字块\"", row)

    def test_version_is_bumped_consistently(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.43;", self.project)

    def test_ci_runs_v343_after_v342(self) -> None:
        old = "python3 -B scripts/test-v342-image-action-lock-feedback-contract.py"
        new = "python3 -B scripts/test-v343-image-navigation-accessibility-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v343-image-navigation-accessibility-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
