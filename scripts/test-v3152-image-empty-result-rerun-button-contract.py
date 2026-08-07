#!/usr/bin/env python3
"""Static contract for v3.152 visible rerun recovery on an empty image result."""

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


class ImageEmptyResultRerunButtonContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.inspector = braced_body(panel, "private var inspector: some View")
        self.empty_result_branch = braced_body(
            self.inspector,
            "if store.imageTranslationBlocks.isEmpty",
        )

    def test_translated_empty_result_has_visible_rerun_button(self) -> None:
        for marker in [
            'title: "正在准备识别结果"',
            'title: "重新识别"',
            'systemImage: "text.viewfinder"',
            "action: store.rerunImageRecognition",
            "if store.canRerunImageRecognition",
            "AppSecondaryButton(",
        ]:
            self.assertIn(marker, self.empty_result_branch)

    def test_button_reuses_existing_store_gate_and_pipeline(self) -> None:
        button_branch = braced_body(
            self.empty_result_branch,
            "if store.canRerunImageRecognition",
        )
        self.assertIn("action: store.rerunImageRecognition", button_branch)
        self.assertIn("func rerunImageRecognition()", self.store)
        self.assertIn("guard canRerunImageRecognition else { return }", self.store)
        self.assertNotIn("runImageTranslation(", button_branch)
        self.assertNotIn("VisionOCRService", button_branch)

    def test_empty_result_hint_preserves_recovery_scope(self) -> None:
        self.assertIn("imageResultEmptyStateAccessibilityHint", self.empty_result_branch)
        button_branch = braced_body(
            self.empty_result_branch,
            "if store.canRerunImageRecognition",
        )
        self.assertIn("使用当前图片语言重新运行 Vision OCR", button_branch)
        self.assertIn("重新翻译识别到的文字", button_branch)

    def test_button_is_view_only(self) -> None:
        button_branch = braced_body(
            self.empty_result_branch,
            "if store.canRerunImageRecognition",
        )
        self.assertNotIn("@State", button_branch)
        self.assertNotIn("imageTranslationState =", button_branch)
        self.assertNotIn("imageTranslationBlocks =", button_branch)
        self.assertNotIn("imageTranslationRevision", button_branch)

    def test_version_and_ci_route_follow_v3151(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 152) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.151;", self.project)
        old = "scripts/test-v3151-manga-probe-empty-retry-action-contract.py"
        new = "scripts/test-v3152-image-empty-result-rerun-button-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {new}"))
        self.assertIn("15[2]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
