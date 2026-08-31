#!/usr/bin/env python3
"""Static contract for v3.387's exact bare Japanese translation prompt."""

from __future__ import annotations

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


class JapaneseBarePromptContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.views = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.test2_workflow = read(".github/workflows/test2-image-translation-ui.yml")
        cls.capture = read("scripts/capture-bundled-image-translation-ui.sh")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.docs = "".join(
            read(relative)
            for relative in (
                "README.md",
                "md/flow/flow.md",
                "md/flow/flowchart.md",
                "md/test/test.md",
                "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md",
                "update_log.md",
            )
        )

    def test_bare_standard_prompt_matches_verified_template(self) -> None:
        body = function_body(
            self.gemma,
            "private func translationPromptBodies(for request: ModelGenerationRequest)",
        )
        for marker in (
            "let japaneseBareFallbackInstruction: String",
            'japaneseBareFallbackInstruction = "把以下翻译成中文："',
            'japaneseBareFallbackInstruction = "Translate the following into English:"',
            "\\(japaneseBareFallbackInstruction)",
            "\\(request.inputText)",
        ):
            self.assertIn(marker, body)
        fallback_start = body.index("\\(japaneseBareFallbackInstruction)")
        fallback = body[fallback_start : body.index("\n                \"\"\"", fallback_start)]
        self.assertNotIn("contextualInstruction", fallback)
        self.assertNotIn("compactContextSection", fallback)
        self.assertLess(
            body.index("\\(japaneseChineseFallbackInstruction)"),
            fallback_start,
        )

    def test_bare_manga_prompt_remains_tagged_and_context_free(self) -> None:
        body = function_body(
            self.gemma,
            "private func translationPromptBodies(for request: ModelGenerationRequest)",
        )
        for marker in (
            "let mangaBareFallbackInstruction: String",
            'mangaBareFallbackInstruction = "把以下翻译成中文："',
            "\\(mangaBareFallbackInstruction)",
            "\\(request.inputText)",
            "mangaBlocks",
        ):
            self.assertIn(marker, body)
        fallback_start = body.index("\\(mangaBareFallbackInstruction)")
        fallback = body[fallback_start : body.index("\n                \"\"\"", fallback_start)]
        self.assertNotIn("contextualInstruction", fallback)
        self.assertNotIn("compactContextSection", fallback)
        self.assertLess(
            body.index("\\(mangaBareFallbackInstruction)"),
            body.index("if request.sourceLanguage == .englishUS"),
        )

    def test_existing_validation_and_boundary_contracts_remain(self) -> None:
        for marker in (
            "TranslationOutputPolicy",
            "cleanTranslationOutput(",
            "cleanMangaBlockOutput(",
            "translateJapaneseImageBlockWithQA(",
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "japaneseTranslationQAConfiguration(",
            "let generationMaxTokens = min(max(request.sampling.maxTokens, 192), 256)",
        ):
            self.assertIn(marker, self.gemma + self.store)
        compact_body = function_body(self.context, "func compactPromptSection() -> String {")
        self.assertNotIn("persist(", compact_body)
        self.assertNotIn("UserDefaults", compact_body)

    def test_real_test2_route_and_version_are_current(self) -> None:
        for marker in (
            'let filename = "2.png"',
            "sourceLanguage = .japanese",
            "targetLanguage = .simplifiedChinese",
            "selectedEngine = .local",
            "scripts/capture-bundled-image-translation-ui.sh",
            "test2-image-translation-results.png",
            "test2-image-translation-manifest.json",
            "test2-image-translation-ocr.png",
            "test2-image-translation-ocr.txt",
            "boundingBox",
            "ocrScreenshot",
        ):
            self.assertIn(marker, self.store + self.test2_workflow + self.capture)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.387", "3.387"],
        )
        for marker in (
            "scripts/test-v3386-japanese-chinese-prompt-contract.py",
            "scripts/test-v3387-japanese-bare-prompt-contract.py",
            "japanese-benchmark-v3.387-",
            "test2_image_translation_ui:",
        ):
            self.assertIn(marker, self.workflow)
        for marker in ("v3.387", "test/2.png", "小模型", "把以下翻译成中文", "prompt"):
            self.assertIn(marker, self.docs + self.test2_workflow)

    def test_ocr_diagnostic_reopens_the_real_session_without_restarting_work(self) -> None:
        for marker in (
            'SIMCTL_CHILD_AITRANS_IMAGE_TRANSLATION_UI_FOCUS=ocr',
            "-AITRANS_IMAGE_TRANSLATION_UI_FOCUS ocr",
            "launchctl unsetenv AITRANS_RUN_BUNDLED_IMAGE_TRANSLATION_TEST",
            "launchctl unsetenv AITRANS_RUN_LLM_SMOKE",
            "isOCRDiagnosticPreview",
            "diagnosticDisplayMode",
            "primaryOverlayText",
        ):
            self.assertIn(marker, self.capture + self.views)
        self.assertIn(
            "launchesImageOCRDiagnostic",
            read("AITRANS/Views/ContentView.swift"),
        )
        self.assertIn("整图 OCR", self.docs)

    def test_contract_has_no_local_process_or_build_entrypoint(self) -> None:
        source = read("scripts/test-v3387-japanese-bare-prompt-contract.py")
        for forbidden in (
            "subprocess" + ".run(",
            "subprocess" + ".Popen(",
            "xcode" + "build ",
            "swift" + "c ",
            "cargo" + " ",
            "llama" + "-cli",
        ):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
