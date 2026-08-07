#!/usr/bin/env python3
"""Contract for a direct VoiceOver retry action on failed image previews."""

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


class ImagePreviewStatusRetryActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.preview = braced_body(
            self.view,
            "private struct ImageTranslationPreview: View",
        )

    def test_failed_preview_status_exposes_named_retry_action(self) -> None:
        actions = braced_body(self.preview, "private func previewStatusAccessibilityActions")
        self.assertIn("if previewFailedForCurrentRevision", actions)
        self.assertIn('.accessibilityAction(named: "重试预览")', actions)
        self.assertIn("retryPreview()", actions)
        self.assertIn("else", actions)

    def test_visible_retry_button_and_status_context_remain_aligned(self) -> None:
        status = braced_body(self.preview, "@ViewBuilder private var previewStatus")
        self.assertIn('title: "重试预览"', status)
        self.assertIn('action: retryPreview', status)
        self.assertIn("重新生成屏幕预览；不会重新识别或翻译图片", status)
        self.assertIn('previewStatusAccessibilityFocusID', status)
        self.assertIn('previewStatusAccessibilityLabel', status)
        self.assertIn('previewStatusAccessibilityValue', status)

    def test_action_is_only_added_for_failed_current_revision(self) -> None:
        actions = braced_body(self.preview, "private func previewStatusAccessibilityActions")
        self.assertLess(actions.index("if previewFailedForCurrentRevision"), actions.index('.accessibilityAction(named: "重试预览")'))
        self.assertLess(actions.index('.accessibilityAction(named: "重试预览")'), actions.index("else"))
        self.assertIn("previewPhase == .failed(revision: store.imageTranslationRevision)", self.preview)

    def test_retry_action_is_view_only_and_does_not_change_pipeline(self) -> None:
        self.assertNotIn("previewStatusAccessibilityActions", self.store)
        self.assertNotIn("runImageTranslationPipeline", self.preview)
        self.assertNotIn("VisionOCRService", self.preview)
        self.assertNotIn("MangaOverlayProbeService", self.preview)

    def test_version_and_ci_route_follow_v3133(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 134) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.133;", self.project)
        script = "scripts/test-v3134-image-preview-status-retry-action-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3133-image-empty-result-accessibility-context-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))
        self.assertTrue("13[0-7]" in self.workflow or "13[0-8]" in self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
