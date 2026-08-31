#!/usr/bin/env python3
"""Static and pure-policy contract for the v3.381 cloud shared-Han QA gate."""

from __future__ import annotations

import importlib.util
import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing function signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1 : index]
    raise AssertionError(f"unterminated function body: {signature}")


def python_function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing function signature: {signature}")
    end = source.find("\ndef ", start + len(signature))
    if end < 0:
        end = len(source)
    return source[start:end]


def load_evaluator():
    path = ROOT / "scripts/evaluate-japanese-translation-context-qa.py"
    spec = importlib.util.spec_from_file_location("v3380_cloud_evaluator", path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load evaluator: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseSharedHanCloudQAContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.evaluator_source = read("scripts/evaluate-japanese-translation-context-qa.py")
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.content_view = read("AITRANS/Views/ContentView.swift")
        cls.image_views = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.test2_workflow = read(".github/workflows/test2-image-translation-ui.yml")
        cls.test2_capture = read("scripts/capture-bundled-image-translation-ui.sh")
        cls.docs = (
            read("README.md")
            + read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("update_log.md")
        )
        cls.module = load_evaluator()

    def leakage(self, source: str, output: str, source_language: str = "ja", target_language: str = "zh-CN") -> bool:
        return self.module.is_source_leakage(
            source,
            output,
            self.module.normalize_text(source),
            self.module.normalize_text(output),
            source_language,
            target_language,
        )

    def test_exact_shared_han_exception_is_narrow(self) -> None:
        self.assertFalse(self.leakage("日本", "日本"))
        self.assertFalse(self.leakage("東京。", "東京"))
        self.assertTrue(self.leakage("日本", "日本人"))
        self.assertTrue(self.leakage("日本", "日本 東京"))
        self.assertTrue(self.leakage("日", "日"))
        self.assertTrue(self.leakage("日本の", "日本の"))

    def test_shared_han_exception_is_language_bound(self) -> None:
        self.assertTrue(self.leakage("東京", "東京", "en-US", "zh-CN"))
        self.assertTrue(self.leakage("東京", "東京", "ja", "en-US"))
        self.assertFalse(self.leakage("日本", "东京"))

    def test_helper_matches_product_exact_policy(self) -> None:
        for source, output, source_language, target_language, expected in (
            ("日本", "日本", "ja", "zh-CN", True),
            ("日本", "日本人", "ja", "zh-CN", False),
            ("日本 東京", "日本東京", "ja", "zh-CN", True),
            ("日本の", "日本の", "ja", "zh-CN", False),
            ("日本", "日本", "ja", "en-US", False),
        ):
            self.assertEqual(
                self.module.allows_unchanged_japanese_han_translation(
                    source, output, source_language, target_language
                ),
                expected,
                (source, output, source_language, target_language),
            )

    def test_cloud_gate_passes_original_output_into_exact_helper(self) -> None:
        call = python_function_body(self.evaluator_source, "def text_failures(\n")
        self.assertIn("source,\n        output,\n        source_normalized,", call)
        body = python_function_body(self.evaluator_source, "def is_source_leakage(\n")
        for marker in (
            "output: str,",
            "return not allows_unchanged_japanese_han_translation(",
            "source,\n            output,\n            source_language,\n            target_language,",
        ):
            self.assertIn(marker, body)

    def test_cloud_helper_has_the_same_narrow_markers_as_product(self) -> None:
        helper = python_function_body(
            self.evaluator_source,
            "def allows_unchanged_japanese_han_translation(\n",
        )
        for marker in (
            'source_language == "ja"',
            'target_language == "zh-CN"',
            "len(normalized_source) > 1",
            "normalized_source == normalized_output",
            "is_shared_han_only_japanese_source(source)",
        ):
            self.assertIn(marker, helper)
        product = function_body(
            self.context,
            "static func allowsUnchangedJapaneseHanTranslation(\n",
        )
        for marker in (
            "sourceLanguage == .japanese",
            "targetLanguage == .simplifiedChinese",
            "normalizedSource.count > 1",
            "normalizedSource == normalizedOutput",
            "isSharedHanOnlyJapaneseSource(source)",
        ):
            self.assertIn(marker, product)

    def test_qa_remains_block_scoped_and_product_boundary_is_untouched(self) -> None:
        for marker in (
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "TranslationBatchQualityEvaluator.evaluate(",
            "translateJapaneseImageBlockWithQA(",
            "正在只补译",
        ):
            self.assertIn(marker, self.store)
        self.assertIn("allowsUnchangedJapaneseHanTranslation(", self.gemma)
        self.assertIn("failures.append(\"sourceLeakage\")", self.context)
        self.assertIn("isSharedHanOnlyJapaneseSource(source)", self.context)

    def test_test2_uses_real_image_pipeline_and_results_ui(self) -> None:
        for marker in (
            "runLaunchBundledImageTranslationTestIfNeeded()",
            "AITRANS_RUN_BUNDLED_IMAGE_TRANSLATION_TEST",
            'let filename = "2.png"',
            "sourceLanguage = .japanese",
            "targetLanguage = .simplifiedChinese",
            "selectedEngine = .local",
            "self.translateImage(from: url)",
        ):
            self.assertIn(marker, self.store)
        self.assertIn("AITRANS_RUN_BUNDLED_IMAGE_TRANSLATION_TEST", self.content_view)
        self.assertIn("launchesBundledImageTranslationTest ? .image : .text", self.content_view)
        for marker in (
            'AITRANS_IMAGE_TRANSLATION_UI_FOCUS"] == "results"',
            'static let inspectorScrollID = "imageTranslationInspector"',
            "proxy.scrollTo(ImageTranslationPanel.inspectorScrollID, anchor: .top)",
        ):
            self.assertIn(marker, self.image_views)

    def test_test2_cloud_runner_polls_persisted_real_output_and_captures_screenshot(self) -> None:
        for marker in (
            "test/2.png",
            "xcodebuild",
            "scripts/capture-bundled-image-translation-ui.sh",
            "MODEL_SHA256",
            "imageTranslationSession",
            "sourceLanguage",
        ):
            self.assertIn(marker, self.test2_workflow + self.test2_capture)
        for marker in (
            "SIMCTL_CHILD_AITRANS_RUN_BUNDLED_IMAGE_TRANSLATION_TEST=1",
            "SIMCTL_CHILD_AITRANS_IMAGE_TRANSLATION_UI_FOCUS=results",
            "launchctl setenv AITRANS_RUN_BUNDLED_IMAGE_TRANSLATION_TEST 1",
            "launchctl setenv AITRANS_IMAGE_TRANSLATION_UI_FOCUS results",
            'session.get("state")',
            'session.get("filename")',
            'session.get("sourceLanguage") != "日语"',
            'session.get("targetLanguage") != "简体中文"',
            "test2-image-translation-results.png",
            "test2-image-translation-manifest.json",
        ):
            self.assertIn(marker, self.test2_capture)
        for marker in (
            "test2_image_translation_ui:",
            "github.ref == 'refs/heads/smalldata_test'",
            "inputs.validation_profile == 'fast'",
            "inputs.ui_evidence_mode == 'full'",
        ):
            self.assertIn(marker, self.workflow)

    def test_test2_fixture_is_explicitly_unignored_and_bundled(self) -> None:
        ignore = read(".gitignore")
        self.assertIn("!test/2.png", ignore)
        self.assertIn("path = test;", self.project)
        self.assertIn("test/2.png", self.test2_workflow)
        fixture = ROOT / "test/2.png"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 50_000)

    def test_version_workflow_docs_and_execution_boundary(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.381", "3.381"],
        )
        combined = self.workflow + self.test2_workflow + self.docs
        for marker in (
            "scripts/test-v3380-japanese-shared-han-cloud-qa-contract.py",
            "v3.381",
            "japanese-benchmark-v3.381-",
            "test/2.png",
            "stopUntilArtifactsProvided",
        ):
            self.assertIn(marker, combined)
        for forbidden in (
            "subprocess" + ".run(",
            "subprocess" + ".Popen(",
            "xcodebuild" + " ",
            "swiftc" + " ",
            "cargo" + " ",
            "llama" + "-cli",
        ):
            self.assertNotIn(forbidden, read("scripts/test-v3380-japanese-shared-han-cloud-qa-contract.py"))


if __name__ == "__main__":
    unittest.main()
