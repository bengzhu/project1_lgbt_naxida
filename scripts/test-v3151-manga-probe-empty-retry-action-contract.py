#!/usr/bin/env python3
"""Contract for the direct retry action on an empty manga probe report."""

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


class MangaProbeEmptyRetryActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.section = braced_body(self.view, "private struct MangaProbeSection: View")
        self.modifier = braced_body(
            self.view,
            "private struct MangaProbeEmptyStateRetryAccessibilityModifier",
        )

    def test_empty_report_has_visible_and_voiceover_retry_entry(self) -> None:
        empty_state = braced_body(
            self.section,
            "if store.mangaOverlayProbeReport != nil, store.mangaOverlayProbeBlocks.isEmpty",
        )
        for marker in [
            'title: "本次探针未生成文字块"',
            "MangaProbeEmptyStateRetryAccessibilityModifier(",
            "canRetry: canRetryEmptyMangaProbe",
            "retry: rerunMangaProbeAction",
            'title: "重新运行漫画覆盖翻译探针"',
            "systemImage: \"arrow.clockwise\"",
            "action: rerunMangaProbeAction",
            ".disabled(!canRetryEmptyMangaProbe)",
            "emptyProbeRetryAccessibilityHint",
        ]:
            self.assertIn(marker, empty_state)
        self.assertIn('accessibilityAction(named: "重新运行漫画覆盖翻译探针")', self.modifier)

    def test_voiceover_retry_is_gated_while_probe_is_running(self) -> None:
        self.assertIn("if canRetry {", self.modifier)
        action = braced_body(
            self.modifier,
            'accessibilityAction(named: "重新运行漫画覆盖翻译探针")',
        )
        self.assertIn("retry()", action)
        locked_branch = self.modifier[self.modifier.index("} else {") :]
        self.assertNotIn(
            'accessibilityAction(named: "重新运行漫画覆盖翻译探针")',
            locked_branch,
        )
        for marker in [
            "private var canRetryEmptyMangaProbe",
            "!store.isRunningMangaOverlayProbe",
            "private var emptyProbeRetryAccessibilityHint",
            "当前按钮不可用，完成后再重试",
        ]:
            self.assertIn(marker, self.section)

    def test_retry_reuses_store_probe_entry_without_new_pipeline(self) -> None:
        self.assertIn("private var rerunMangaProbeAction: () -> Void", self.section)
        self.assertIn("store.runMangaOverlayProbe", self.section)
        self.assertNotIn("runMangaOverlayProbe()", self.section)
        self.assertNotIn("MangaOverlayProbeService", self.modifier)
        self.assertNotIn("VisionOCRService", self.modifier)
        self.assertNotIn("TranslationSessionStore", self.modifier)
        self.assertNotIn("MangaProbeEmptyStateRetryAccessibilityModifier", self.store)

    def test_retry_hint_preserves_report_only_boundaries(self) -> None:
        for marker in [
            "test/1.png",
            "清理 Output",
            "不会影响普通图片 OCR、翻译或覆盖图",
            "漫画覆盖翻译探针正在运行",
        ]:
            self.assertIn(marker, self.section)

    def test_version_and_ci_route_follow_v3150(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 151) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.150;", self.project)
        old = "scripts/test-v3150-image-focus-restore-action-contract.py"
        new = "scripts/test-v3151-manga-probe-empty-retry-action-contract.py"
        self.assertIn(f"python3 -B {old}", self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(f"python3 -B {old}"), self.workflow.index(f"python3 -B {new}"))
        self.assertIn("15[0]", self.workflow)
        self.assertIn("15[1]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
