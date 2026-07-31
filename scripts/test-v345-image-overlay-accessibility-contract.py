#!/usr/bin/env python3
"""Static contracts for v3.45 image overlay accessibility wording."""

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


class ImageOverlayAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_overlay_selection_hints_match_result_row(self) -> None:
        overlay = braced_body(self.view, "private struct ImageTranslationOverlayBlock: View")
        self.assertEqual(overlay.count(".accessibilityHint(accessibilityHint)"), 2)
        self.assertIn(
            'isSelected ? "取消此文字块在图片中的定位" : "在图片预览中定位此文字块"',
            overlay,
        )
        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        self.assertIn('? "取消此文字块在图片中的定位"', row)
        self.assertIn(': "在图片预览中定位此文字块"', row)

    def test_overlay_value_still_explains_translation_and_selection(self) -> None:
        overlay = braced_body(self.view, "private struct ImageTranslationOverlayBlock: View")
        self.assertEqual(overlay.count(".accessibilityValue(accessibilityValue)"), 2)
        self.assertIn('let translation = block.translation.isEmpty ? "等待翻译" : block.translation', overlay)
        self.assertIn('isSelected ? "已定位，\(translation)" : "未定位，\(translation)"', overlay)

    def test_version_is_bumped_consistently(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.45;"), 2)
        self.assertNotIn("MARKETING_VERSION = 3.44;", self.project)

    def test_ci_runs_v345_after_v344(self) -> None:
        old = "python3 -B scripts/test-v344-image-navigation-position-accessibility-contract.py"
        new = "python3 -B scripts/test-v345-image-overlay-accessibility-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v345-image-overlay-accessibility-contract.py' "
            '"$RESULT_ROOT/changed-files.txt" >/dev/null; then'
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
