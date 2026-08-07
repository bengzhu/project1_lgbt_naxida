#!/usr/bin/env python3
"""Contract for explicit VoiceOver hints on image preview status states."""

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


class ImagePreviewStatusHintContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.preview = braced_body(
            self.view,
            "private struct ImageTranslationPreview: View",
        )

    def test_preview_status_exposes_dynamic_hint(self) -> None:
        status = braced_body(self.preview, "@ViewBuilder private var previewStatus")
        self.assertIn(".accessibilityLabel(previewStatusAccessibilityLabel)", status)
        self.assertIn(".accessibilityValue(previewStatusAccessibilityValue)", status)
        self.assertIn(".accessibilityHint(previewStatusAccessibilityHint)", status)
        self.assertIn("previewStatusAccessibilityFocusID", status)

    def test_failed_and_loading_hints_explain_action_boundary(self) -> None:
        hint = braced_body(self.preview, "private var previewStatusAccessibilityHint")
        self.assertIn("previewFailedForCurrentRevision", hint)
        self.assertIn("可执行“重试预览”重新生成屏幕预览", hint)
        self.assertIn("不会重新识别或翻译图片", hint)
        self.assertIn("屏幕预览生成中", hint)
        self.assertIn("若生成失败可执行“重试预览”", hint)

    def test_hint_remains_view_only(self) -> None:
        self.assertNotIn("previewStatusAccessibilityHint", self.store)
        self.assertNotIn("runImageTranslationPipeline", self.preview)
        self.assertNotIn("VisionOCRService", self.preview)
        self.assertNotIn("MangaOverlayProbeService", self.preview)

    def test_previous_retry_action_contract_remains_in_route(self) -> None:
        old = "scripts/test-v3134-image-preview-status-retry-action-contract.py"
        new = "scripts/test-v3135-image-preview-status-hint-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))

    def test_version_and_ci_route_follow_v3134(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 135) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.134;", self.project)
        self.assertIn("python3 -B scripts/test-v3135-image-preview-status-hint-contract.py", self.workflow)
        self.assertTrue("13[0-7]" in self.workflow or "13[0-8]" in self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
