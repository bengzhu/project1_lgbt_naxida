#!/usr/bin/env python3
"""Static and pure-policy contract for v3.385 scoped Japanese SFX hints."""

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


class JapaneseSFXScopeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.docs = (
            read("README.md")
            + read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + cls.route
            + read("update_log.md")
        )

    def test_mixed_batch_sfx_scope_is_derived_from_kind_ordinals(self) -> None:
        body = function_body(self.context, "func promptSection() -> String {")
        for marker in (
            "let hasSFXBatchKind = context.batchTextKinds.contains(.sfx)",
            "let sfxOrdinals = context.batchTextKinds.enumerated().compactMap",
            "guard kind == .sfx else { return nil }",
            "return (context.batchStartIndex ?? 0) + index + 1",
            'let sfxScope = sfxOrdinals\n                .map { "第\\($0)块" }',
            'joined(separator: "、")',
        ):
            self.assertIn(marker, body)

    def test_mixed_batch_sfx_rule_is_explicitly_scoped(self) -> None:
        body = function_body(self.context, "func promptSection() -> String {")
        for marker in (
            "if hasSFXBatchKind",
            "if !sfxScope.isEmpty",
            "仅对\\(sfxScope)生效的拟声词/状态字规则",
            "其它编号块仍按各自文字类型翻译",
            "保留节奏",
            "不要补写主语",
            "不要扩写成完整句子",
        ):
            self.assertIn(marker, body)
        self.assertNotIn(
            "if context.textKind == .sfx || context.batchTextKinds.contains(.sfx)",
            body,
        )

    def test_single_block_sfx_hint_remains_available(self) -> None:
        body = function_body(self.context, "func promptSection() -> String {")
        self.assertIn(
            "else if context.batchTextKinds.isEmpty && context.textKind == .sfx",
            body,
        )
        self.assertIn("本次文字块是拟声词/状态字", body)
        self.assertIn("context.batchTextKinds.isEmpty", body)

    def test_global_ordinals_match_tagged_batch_examples(self) -> None:
        self.assertEqual(
            [8 + index + 1 for index, kind in enumerate(["对白", "拟声词", "标题"]) if kind == "拟声词"],
            [10],
        )
        self.assertIn("batchStartIndex: batch.startIndex", self.store)
        self.assertIn("let expectedIDs = blocks.indices.map { startIndex + $0 + 1 }", self.store)
        self.assertIn('return "[\\(expectedIDs[offset])] \\(text)"', self.store)
        self.assertNotRegex("第10块", r"\[\d+\]")

    def test_kind_metadata_stays_prompt_only_and_batch_path_is_unchanged(self) -> None:
        for marker in (
            "var batchTextKinds: [TranslationTextKind]",
            "TranslationTextKindClassifier.inferJapaneseKind(",
            "translationProfile: .mangaBlocks",
            "TranslationBatchQualityEvaluator.evaluate(",
            "translateJapaneseImageBlockWithQA(",
            "let maximumBlocks = 8",
            "let maximumCharacters = 1_800",
        ):
            self.assertIn(marker, self.context + self.store + self.gemma + self.vision)
        self.assertNotIn("persist()", self.context)
        self.assertNotIn("recognizeTextBlocks(in: data", self.context)

    def test_manga_prompt_retains_existing_sfx_translation_boundary(self) -> None:
        body = function_body(
            self.gemma,
            "private func translationPromptBodies(for request: ModelGenerationRequest)",
        )
        for marker in (
            "request.translationProfile == .mangaBlocks",
            "Keep every [N] tag and the input order",
            "保留每个[N]标签和顺序",
            "拟声词/状态字",
            "不补写主语或解释动作",
            "\\(request.inputText)",
        ):
            self.assertIn(marker, body)

    def test_version_workflow_docs_and_contract_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.385", "3.385"],
        )
        for marker in (
            "python3 -B scripts/test-v3364-japanese-sfx-scope-contract.py",
            "scripts/test-v3364-japanese-sfx-scope-contract.py",
            "v3.385",
            "japanese-benchmark-v3.385-",
        ):
            self.assertIn(marker, self.workflow + self.docs)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read("scripts/test-v3364-japanese-sfx-scope-contract.py")
        for source in (self.context, self.store, self.gemma, self.vision, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
