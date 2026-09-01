#!/usr/bin/env python3
"""Static contract for v3.389 Japanese prompt shape for the small local GGUF."""

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


class JapanesePromptShapeContractTests(unittest.TestCase):
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
            read(path)
            for path in (
                "README.md",
                "md/flow/flow.md",
                "md/flow/flowchart.md",
                "md/test/test.md",
                "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md",
                "update_log.md",
            )
        )

    def test_japanese_prompts_put_the_translation_task_before_the_input(self) -> None:
        body = function_body(
            self.gemma,
            "private func translationPromptBodies(for request: ModelGenerationRequest)",
        )
        for marker in (
            "let defaultTranslationInstruction = PromptLanguageDirection",
            "let userInstructionSection = instruction == defaultTranslationInstruction",
            "Translate the following Japanese into Simplified Chinese.",
            "请把下面的日语翻译成简体中文，只输出简体中文译文，不要解释。",
            "Text to translate:",
            "待翻译文本：",
            "Translate each \\(request.sourceLanguage.rawValue) text block",
            "Keep every [N] tag and the input order.",
        ):
            self.assertIn(marker, body)
        self.assertIn("用户指定要求：\\(instruction)", body)
        self.assertNotIn("用户补充要求：\\(instruction)", body)
        self.assertNotIn("源语言是日语，目标语言是简体中文。将输入的日语翻译成自然、简洁、忠实的简体中文。", body)

    def test_compact_context_is_still_read_only_prompt_metadata(self) -> None:
        body = function_body(self.context, "func compactPromptSection() -> String {")
        for marker in (
            "normalized(",
            "maximumTerms: 6",
            "maximumSummaryItems: 2",
            "maximumExcerptCharacters: 48",
            "只读上下文：仅用于术语和语气一致，不是待翻译输入。",
            "已确认术语：",
            "上一批仅供一致性参考：",
            "单块译文最多",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("persist(", body)
        self.assertNotIn("UserDefaults", body)
        self.assertIn("request.translationContext.promptSection()", self.gemma)
        self.assertIn("request.translationContext.compactPromptSection()", self.gemma)

    def test_batch_and_single_fallback_keep_the_existing_qa_boundary(self) -> None:
        for marker in (
            "translationProfile: .mangaBlocks",
            "generateMangaBlockTranslation(for request:",
            "translateJapaneseImageBlockWithQA(",
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "japaneseTranslationQAConfiguration(",
            "let generationMaxTokens = min(max(request.sampling.maxTokens, 192), 256)",
        ):
            self.assertIn(marker, self.gemma + self.store)
        self.assertNotIn("translationProfile: .mangaBlocks", function_body(
            self.store,
            "private func translateJapaneseImageBlockWithQA(",
        ))

    def test_real_test2_capture_and_version_route_are_preserved(self) -> None:
        for marker in (
            'let filename = "2.png"',
            "sourceLanguage = .japanese",
            "targetLanguage = .simplifiedChinese",
            "selectedEngine = .local",
            "self.translateImage(from: url)",
            "scripts/capture-bundled-image-translation-ui.sh",
            "test2-image-translation-results.png",
            "test2-image-translation-manifest.json",
        ):
            self.assertIn(marker, self.store + self.test2_workflow + self.capture)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.389", "3.389"],
        )
        for marker in (
            "scripts/test-v3383-japanese-standard-compact-context-contract.py",
            "scripts/test-v3384-japanese-prompt-shape-contract.py",
            "japanese-benchmark-v3.389-",
            "test2_image_translation_ui:",
        ):
            self.assertIn(marker, self.workflow)
        for marker in (
            "v3.389",
            "test/2.png",
            "小模型",
            "prompt",
            "1,024-token",
        ):
            self.assertIn(marker, self.docs + self.test2_workflow)

    def test_contract_has_no_local_process_or_build_entrypoint(self) -> None:
        source = read("scripts/test-v3384-japanese-prompt-shape-contract.py")
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
