#!/usr/bin/env python3
"""Static and pure-policy contract for v3.377 Japanese kind style scope."""

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


class JapaneseKindStyleScopeContractTests(unittest.TestCase):
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

    def test_each_kind_has_distinct_style_guidance(self) -> None:
        start = self.context.find("var promptStyleGuidance: String {")
        self.assertGreaterEqual(start, 0)
        body = function_body(self.context, "var promptStyleGuidance: String {")
        for marker in (
            "case .dialogue:",
            "case .narration:",
            "case .sfx:",
            "case .title:",
            "case .other:",
            "不要补写旁白或解释性句子",
            "不要改写成角色对白或添加说话人",
            "仅使用简短的中文拟声或动作表达",
            "保持紧凑的标题式表达",
            "不要套用对白、旁白或声效的专属风格",
        ):
            self.assertIn(marker, body)

    def test_mixed_kind_guidance_is_bound_to_each_global_ordinal(self) -> None:
        body = function_body(self.context, "func promptSection() -> String {")
        for marker in (
            "if Set(context.batchTextKinds).count > 1",
            "for (index, kind) in context.batchTextKinds.enumerated()",
            "let ordinal = (context.batchStartIndex ?? 0) + index + 1",
            'lines.append("第\\(ordinal)块：\\(kind.promptLabel)")',
            'lines.append("仅对第\\(ordinal)块生效的文字类型提示（\\(kind.promptLabel)）：\\(kind.promptStyleGuidance)")',
        ):
            self.assertIn(marker, body)
        self.assertNotIn(
            "本批文字类型统一使用",
            body,
        )

    def test_global_ordinal_policy_matches_tagged_batch(self) -> None:
        kinds = ["对白", "旁白", "拟声词", "标题", "其他"]
        start_index = 8
        scoped = [
            (start_index + offset + 1, kind)
            for offset, kind in enumerate(kinds)
        ]
        self.assertEqual(
            scoped,
            [(9, "对白"), (10, "旁白"), (11, "拟声词"), (12, "标题"), (13, "其他")],
        )
        self.assertIn("batchStartIndex: batch.startIndex", self.store)
        self.assertIn("let expectedIDs = blocks.indices.map { startIndex + $0 + 1 }", self.store)
        self.assertIn('return "[\\(expectedIDs[offset])] \\(text)"', self.store)
        self.assertNotRegex("第11块", r"\[\d+\]")

    def test_single_kind_prompt_remains_local(self) -> None:
        body = function_body(self.context, "func promptSection() -> String {")
        self.assertIn("else {", body)
        self.assertIn("本次文字类型：\\(context.textKind.promptLabel)", body)
        self.assertIn("本次文字类型提示：\\(context.textKind.promptStyleGuidance)", body)
        self.assertIn(
            "else if context.batchTextKinds.isEmpty && context.textKind == .sfx",
            body,
        )

    def test_existing_sfx_scope_and_translation_path_remain(self) -> None:
        body = function_body(self.context, "func promptSection() -> String {")
        for marker in (
            "let hasSFXBatchKind = context.batchTextKinds.contains(.sfx)",
            "let sfxOrdinals = context.batchTextKinds.enumerated().compactMap",
            "guard kind == .sfx else { return nil }",
            "仅对\\(sfxScope)生效的拟声词/状态字规则",
            "其它编号块仍按各自文字类型翻译",
        ):
            self.assertIn(marker, body)
        for marker in (
            "translationProfile: .mangaBlocks",
            "TranslationBatchQualityEvaluator.evaluate(",
            "translateJapaneseImageBlockWithQA(",
            "let maximumBlocks = 8",
            "let maximumCharacters = 1_800",
            "var batchTextKinds: [TranslationTextKind]",
        ):
            self.assertIn(marker, self.context + self.store + self.gemma + self.vision)

    def test_prompt_metadata_does_not_expand_state_or_persistence_boundary(self) -> None:
        self.assertNotIn("persist()", self.context)
        self.assertNotIn("recognizeTextBlocks(in: data", self.context)
        self.assertNotIn("persist()", self.gemma)
        self.assertNotIn("sub" + "process", self.context + self.store + self.gemma + self.vision)

    def test_version_workflow_docs_and_contract_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.377", "3.377"],
        )
        for marker in (
            "python3 -B scripts/test-v3365-japanese-kind-style-scope-contract.py",
            "scripts/test-v3365-japanese-kind-style-scope-contract.py",
            "v3.377",
            "japanese-benchmark-v3.377-",
        ):
            self.assertIn(marker, self.workflow + self.docs)


if __name__ == "__main__":
    unittest.main(verbosity=2)
