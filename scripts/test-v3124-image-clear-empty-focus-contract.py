#!/usr/bin/env python3
"""Contract for v3.124 returning VoiceOver focus to the empty image state."""

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


class ImageClearEmptyFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_clear_revision_focuses_stable_empty_state_only_when_idle(self) -> None:
        self.assertIn('imageEmptyAccessibilityFocusID = "image-empty-state"', self.panel)
        revision_change = braced_body(self.panel, ".onChange(of: store.imageTranslationRevision)")
        self.assertIn("if store.imageTranslationData == nil,", revision_change)
        self.assertIn("store.imageTranslationState == .idle", revision_change)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: Self.imageEmptyAccessibilityFocusID)",
            revision_change,
        )

    def test_empty_state_exposes_focusable_next_step(self) -> None:
        empty_state = braced_body(self.panel, "if store.imageTranslationBlocks.isEmpty")
        for marker in [
            '.accessibilityLabel("等待图片")',
            '.accessibilityValue("当前没有图片")',
            '.accessibilityHint("从上方照片或文件按钮选择图片，并开始本机 OCR 与翻译")',
            ".accessibilityFocused(\n                        $reviewAccessibilityFocusID,\n                        equals: Self.imageEmptyAccessibilityFocusID",
        ]:
            self.assertIn(marker, empty_state)

    def test_empty_focus_remains_view_only_and_does_not_change_store(self) -> None:
        self.assertNotIn("imageEmptyAccessibilityFocusID", self.store)
        self.assertNotIn("image-empty-state", self.store)
        self.assertNotIn("runBubbleFirstProbe", self.panel)

    def test_version_and_ci_route_follow_v3123(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 124) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.123;", self.project)
        script = "scripts/test-v3124-image-clear-empty-focus-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3123-image-preview-status-focus-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
