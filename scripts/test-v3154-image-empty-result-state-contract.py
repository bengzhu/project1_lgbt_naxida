#!/usr/bin/env python3
"""Contract for state-accurate visible copy on an empty image OCR result."""

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


class ImageEmptyResultStateContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.inspector = braced_body(self.panel, "private var inspector: some View")
        self.empty_result = braced_body(
            self.inspector,
            "if store.imageTranslationBlocks.isEmpty",
        )

    def test_empty_result_uses_state_accurate_visible_title_and_detail(self) -> None:
        for marker in [
            "title: imageResultEmptyStateTitle",
            "detail: imageResultEmptyStateDetail",
            'systemImage: "viewfinder"',
        ]:
            self.assertIn(marker, self.empty_result)
        self.assertNotIn('title: "正在准备识别结果"', self.empty_result)

    def test_title_covers_each_pipeline_state(self) -> None:
        title = braced_body(self.panel, "private var imageResultEmptyStateTitle: String")
        for marker in [
            "case .idle:",
            "case .loading, .recognizing, .translating:",
            "case .translated:",
            "case .failed:",
            '"等待重新识别"',
            '"正在准备识别结果"',
            '"没有可显示的识别结果"',
            '"识别结果不可用"',
        ]:
            self.assertIn(marker, title)

    def test_detail_explains_processing_and_recovery_scope(self) -> None:
        detail = braced_body(self.panel, "private var imageResultEmptyStateDetail: String")
        for marker in [
            "case .idle:",
            "case .loading, .recognizing, .translating:",
            "case .translated:",
            "case .failed:",
            "store.imageTranslationMessage",
            "store.canRerunImageRecognition",
            "OCR 文字块",
            "选择新图片",
        ]:
            self.assertIn(marker, detail)

    def test_existing_voiceover_context_and_rerun_gate_are_preserved(self) -> None:
        for marker in [
            "imageResultEmptyStateAccessibility(",
            ".accessibilityLabel(imageResultEmptyStateAccessibilityLabel)",
            ".accessibilityValue(store.imageTranslationMessage)",
            ".accessibilityHint(imageResultEmptyStateAccessibilityHint)",
            "if store.canRerunImageRecognition",
            'title: "重新识别"',
            "store.rerunImageRecognition",
        ]:
            self.assertIn(marker, self.empty_result)
        self.assertNotIn("imageResultEmptyStateTitle", self.store)
        self.assertNotIn("imageResultEmptyStateDetail", self.store)
        self.assertNotIn("runImageTranslationPipeline", self.panel)
        self.assertNotIn("VisionOCRService", self.panel)

    def test_version_and_ci_route_follow_v3153(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 154) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.153;", self.project)
        old = "python3 -B scripts/test-v3153-image-empty-result-focus-contract.py"
        new = "python3 -B scripts/test-v3154-image-empty-result-state-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn("15[4]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
