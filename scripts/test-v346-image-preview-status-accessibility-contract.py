#!/usr/bin/env python3
"""Static contracts for v3.46 image preview loading/failure accessibility feedback."""

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


class ImagePreviewStatusAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_preview_states_expose_stable_accessibility_label_and_value(self) -> None:
        preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        status = braced_body(preview, "@ViewBuilder private var previewStatus: some View")
        self.assertIn(".accessibilityElement(children: .contain)", status)
        self.assertIn(".accessibilityLabel(previewStatusAccessibilityLabel)", status)
        self.assertIn(".accessibilityValue(previewStatusAccessibilityValue)", status)
        self.assertIn('previewFailedForCurrentRevision ? "图片预览生成失败" : "正在准备图片预览"', preview)
        self.assertIn('? "原图仍保留用于 OCR 与导出；可以重试屏幕预览"', preview)
        self.assertIn(': "图片已载入，正在后台生成屏幕预览"', preview)

    def test_retry_explains_preview_only_scope(self) -> None:
        preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        status = braced_body(preview, "@ViewBuilder private var previewStatus: some View")
        self.assertIn('title: "重试预览"', status)
        self.assertIn(
            '.accessibilityHint("重新生成屏幕预览；不会重新识别或翻译图片")',
            status,
        )
        self.assertIn("previewAttempt += 1", preview)

    def test_version_is_bumped_consistently(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.46;", self.project)

    def test_ci_runs_v346_after_v345(self) -> None:
        old = "python3 -B scripts/test-v345-image-overlay-accessibility-contract.py"
        new = "python3 -B scripts/test-v346-image-preview-status-accessibility-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v346-image-preview-status-accessibility-contract.py' "
            '"$RESULT_ROOT/changed-files.txt" >/dev/null; then'
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
