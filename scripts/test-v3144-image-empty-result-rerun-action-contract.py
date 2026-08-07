#!/usr/bin/env python3
"""Static contracts for v3.144 direct rerun from an empty translated image result."""

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


class ImageEmptyResultRerunActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_translated_empty_result_exposes_existing_store_rerun(self) -> None:
        panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        helper = braced_body(panel, "private func imageResultEmptyStateAccessibility<Content: View>")

        self.assertIn("imageResultEmptyStateAccessibility(", panel)
        self.assertIn("if store.canRerunImageRecognition", helper)
        self.assertIn('.accessibilityAction(named: "重新识别")', helper)
        self.assertIn("store.rerunImageRecognition()", helper)
        self.assertIn("func rerunImageRecognition()", self.store)
        self.assertIn("guard canRerunImageRecognition else { return }", self.store)

    def test_hint_explains_empty_result_rerun_scope(self) -> None:
        panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        hint = braced_body(panel, "private var imageResultEmptyStateAccessibilityHint: String")

        self.assertIn("case .translated:", hint)
        self.assertIn("store.canRerunImageRecognition", hint)
        self.assertIn("当前没有可显示的 OCR 文字块", hint)
        self.assertIn("只重跑当前图片的 Vision OCR 与翻译", hint)
        self.assertIn("可选择新图片重新识别", hint)

    def test_action_is_view_only_and_does_not_bypass_store(self) -> None:
        panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        helper = braced_body(panel, "private func imageResultEmptyStateAccessibility<Content: View>")

        self.assertNotIn("@State", helper)
        self.assertNotIn("imageTranslationState =", helper)
        self.assertNotIn("imageTranslationBlocks =", helper)
        self.assertNotIn("imageTranslationRevision", helper)

    def test_version_and_ci_route_follow_v3143(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.144;", self.project)
        old = "python3 -B scripts/test-v3143-image-review-row-action-hint-contract.py"
        new = "python3 -B scripts/test-v3144-image-empty-result-rerun-action-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn("14[4]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
