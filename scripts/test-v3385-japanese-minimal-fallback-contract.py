#!/usr/bin/env python3
"""Static contract for v3.389 Japanese minimal GGUF prompt fallback."""

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


class JapaneseMinimalFallbackContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
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
                "md/人工空间/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md",
                "md/log/update_log.md",
            )
        )

    def test_minimal_japanese_fallback_is_explicit_and_context_free(self) -> None:
        body = function_body(
            self.gemma,
            "private func translationPromptBodies(for request: ModelGenerationRequest)",
        )
        for marker in (
            "let japaneseMinimalInstruction: String",
            'japaneseMinimalInstruction = "Translate Japanese to Simplified Chinese. Output only the translation."',
            'japaneseMinimalInstruction = "Translate Japanese to English. Output only the translation."',
            "\\(japaneseMinimalInstruction)",
            "Text to translate:",
            "待翻译文本：",
        ):
            self.assertIn(marker, body)
        minimal_start = body.index("\\(japaneseMinimalInstruction)")
        minimal = body[minimal_start : body.index("\n                \"\"\"", minimal_start)]
        self.assertNotIn("contextualInstruction", minimal)
        self.assertNotIn("compactContextSection", minimal)

    def test_manga_batch_has_a_minimal_tagged_fallback(self) -> None:
        body = function_body(
            self.gemma,
            "private func translationPromptBodies(for request: ModelGenerationRequest)",
        )
        for marker in (
            "let mangaMinimalInstruction: String",
            'mangaMinimalInstruction = "Translate Japanese to Simplified Chinese."',
            "Keep each [N] tag and output only one [N] translation per line.",
            "translationProfile == .mangaBlocks",
            "request.inputText",
        ):
            self.assertIn(marker, body)
        self.assertLess(
            body.index("\(mangaMinimalInstruction) Keep each [N] tag"),
            body.index("if request.sourceLanguage == .englishUS"),
        )

    def test_context_and_qa_boundaries_are_unchanged(self) -> None:
        for marker in (
            "request.translationContext.promptSection()",
            "request.translationContext.compactPromptSection()",
            "scopedToSingleBlock(",
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
        ):
            self.assertIn(marker, self.store + self.test2_workflow + self.capture)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.390", "3.390"],
        )
        for marker in (
            "scripts/test-v3384-japanese-prompt-shape-contract.py",
            "scripts/test-v3385-japanese-minimal-fallback-contract.py",
            "japanese-benchmark-v3.389-",
            "test2_image_translation_ui:",
        ):
            self.assertIn(marker, self.workflow)
        for marker in ("v3.389", "test/2.png", "小模型", "最小", "prompt"):
            self.assertIn(marker, self.docs + self.test2_workflow)

    def test_contract_has_no_local_process_or_build_entrypoint(self) -> None:
        source = read("scripts/test-v3385-japanese-minimal-fallback-contract.py")
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
