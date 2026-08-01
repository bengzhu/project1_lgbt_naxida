#!/usr/bin/env python3
"""Static contracts for v3.57 manga probe block accessibility context."""

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


class MangaProbeBlockAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.row = braced_body(self.view, "private struct MangaProbeBlockRow: View")

    def test_block_label_value_and_hint_form_one_stable_context(self) -> None:
        for marker in [
            ".accessibilityElement(children: .ignore)",
            '.accessibilityLabel("漫画探针文字块 \\(block.index)")',
            ".accessibilityValue(blockAccessibilityValue)",
            ".accessibilityHint(blockAccessibilityHint)",
        ]:
            self.assertIn(marker, self.row)

    def test_block_value_exposes_ocr_translation_and_failure_signals(self) -> None:
        for marker in [
            'let ocrText = block.ocrText.isEmpty ? "空" : block.ocrText',
            'block.blockPassed ? "通过" : "失败"',
            '"OCR 原文：\\(ocrText)"',
            '"旋转 \\(block.rotationAngleUsed) 度"',
            '"OCR 置信度 \\(percent)%"',
            '"OCR 质量：\\(qualityLabel)"',
            '"译文：\\(block.translatedText)"',
            '"失败原因：\\(block.failureReasons.joined(separator: "、"))"',
            '"翻译失败详情：\\(translationFailureDetail)"',
            "不会改变普通图片",
        ]:
            self.assertIn(marker, self.row)
        self.assertIn("min(max(confidence, 0), 1)", self.row)

    def test_block_context_does_not_expose_ground_truth_or_mutate_probe_state(self) -> None:
        self.assertNotIn("groundTruth", self.row)
        self.assertNotIn("TranslationSessionStore", self.row)
        self.assertNotIn("runMangaOverlayProbe", self.row)

    def test_version_and_ci_route_follow_v356(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.57;", self.project)
        old = "python3 -B scripts/test-v356-manga-probe-status-accessibility-contract.py"
        new = "python3 -B scripts/test-v357-manga-probe-block-accessibility-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
