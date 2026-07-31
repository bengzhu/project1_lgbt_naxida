#!/usr/bin/env python3
"""Static contracts for v3.44 image navigation position accessibility feedback."""

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


class ImageNavigationPositionAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_navigation_buttons_expose_current_filter_position(self) -> None:
        focus = braced_body(self.view, "private struct ImageTranslationFocusPreview: View")
        self.assertEqual(focus.count(".accessibilityValue(navigationPositionAccessibilityValue)"), 2)
        self.assertIn("private var navigationPositionAccessibilityValue: String", focus)
        self.assertIn(
            r'positionText.isEmpty ? "未显示筛选位置" : "当前位置 \(positionText)"',
            focus,
        )

    def test_boundary_hints_remain_with_position_value(self) -> None:
        focus = braced_body(self.view, "private struct ImageTranslationFocusPreview: View")
        self.assertIn("当前已是筛选结果中的第一个文字块", focus)
        self.assertIn("当前已是筛选结果中的最后一个文字块", focus)
        self.assertIn('? "定位上一个文字块"', focus)
        self.assertIn('? "定位下一个文字块"', focus)

    def test_version_is_bumped_consistently(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.44;"), 2)

    def test_ci_runs_v344_after_v343(self) -> None:
        old = "python3 -B scripts/test-v343-image-navigation-accessibility-contract.py"
        new = "python3 -B scripts/test-v344-image-navigation-position-accessibility-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v344-image-navigation-position-accessibility-contract.py' "
            '"$RESULT_ROOT/changed-files.txt" >/dev/null; then'
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
