#!/usr/bin/env python3
"""Static contract for v3.389 Japanese standard prompt compaction."""

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


class JapaneseStandardCompactContextContractTests(unittest.TestCase):
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
                "md/人工空间/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md",
                "md/log/update_log.md",
            )
        )

    def test_every_japanese_standard_prompt_can_use_compact_context(self) -> None:
        body = function_body(
            self.gemma,
            "private func translationPromptBodies(for request: ModelGenerationRequest)",
        )
        for marker in (
            "let defaultTranslationInstruction =",
            "let userInstructionSection =",
            "let fullContextSection = request.translationContext.promptSection()",
            "let compactContextSection = request.translationContext.compactPromptSection()",
            "} else if request.sourceLanguage == .japanese,",
            "!compactContextSection.isEmpty",
            "contextSection = compactContextSection",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("fullContextSection.count > 320", body)

    def test_standard_fallback_remains_block_scoped_and_qa_uses_context(self) -> None:
        for marker in (
            "scopedToSingleBlock(",
            "translateJapaneseImageBlockWithQA(",
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "japaneseTranslationQAConfiguration(",
        ):
            self.assertIn(marker, self.store)
        self.assertIn("request.translationContext.promptSection()", self.gemma)
        self.assertIn("用户指定要求：\\(instruction)", self.gemma)
        self.assertNotIn("用户补充要求：\\(instruction)", self.gemma)
        compact_body = function_body(self.context, "func compactPromptSection() -> String {")
        self.assertNotIn("persist(", compact_body)
        self.assertNotIn("CodingKeys", compact_body)

    def test_test2_still_uses_real_ordinary_image_translation_and_result_capture(self) -> None:
        for marker in (
            'let filename = "2.png"',
            "sourceLanguage = .japanese",
            "targetLanguage = .simplifiedChinese",
            "selectedEngine = .local",
            "self.translateImage(from: url)",
        ):
            self.assertIn(marker, self.store)
        for marker in (
            "test/2.png",
            "test2-image-translation-results.png",
            "test2-image-translation-manifest.json",
            "test2-llm-probe.log",
        ):
            self.assertIn(marker, self.test2_workflow + self.capture)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.390", "3.390"],
        )
        for marker in (
            "scripts/test-v3382-local-gguf-prompt-budget-contract.py",
            "scripts/test-v3383-japanese-standard-compact-context-contract.py",
            "japanese-benchmark-v3.389-",
            "test2_image_translation_ui:",
        ):
            self.assertIn(marker, self.workflow)
        for marker in (
            "v3.389",
            "test/2.png",
            "compact context",
            "提示词回显",
            "1,024-token",
        ):
            self.assertIn(marker, self.docs + self.test2_workflow)

    def test_contract_has_no_local_process_or_build_entrypoint(self) -> None:
        source = read("scripts/test-v3383-japanese-standard-compact-context-contract.py")
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
