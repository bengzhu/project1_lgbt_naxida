#!/usr/bin/env python3
"""Static and pure-policy contract for v3.299 per-block translation kinds."""

from __future__ import annotations

import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def prompt_kind_lines(kinds: list[str]) -> str:
    return "\n".join(
        f"第{index}块：{kind}"
        for index, kind in enumerate(kinds, start=1)
    )


class JapaneseTranslationKindContextContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.update_log = read("update_log.md")
        cls.test_log = read("md/test/test.md")

    def test_context_carries_bounded_per_block_kinds(self) -> None:
        for marker in (
            "enum TranslationTextKind: String, Codable, Sendable, Hashable",
            "var batchTextKinds: [TranslationTextKind]",
            "batchTextKinds: [TranslationTextKind] = []",
            "batchTextKinds: Array(batchTextKinds.prefix(8))",
            "init(from decoder: Decoder) throws",
            "container.decodeIfPresent(\n            [TranslationTextKind].self",
            "if Set(context.batchTextKinds).count > 1",
            "本批包含多种文字类型；按输入顺序使用以下提示调整语气",
            "let ordinal = (context.batchStartIndex ?? 0) + index + 1",
            'lines.append("第\\(ordinal)块：\\(kind.promptLabel)")',
        ):
            self.assertIn(marker, self.context)
        self.assertIn("batchTextKinds.isEmpty", self.context)
        self.assertNotIn("batchTextKinds: previousBatchSummary", self.context)

    def test_mixed_kind_prompt_is_metadata_not_tagged_input(self) -> None:
        prompt = prompt_kind_lines(["对白", "旁白", "拟声词", "标题"])
        self.assertEqual(
            prompt,
            "第1块：对白\n第2块：旁白\n第3块：拟声词\n第4块：标题",
        )
        self.assertNotRegex(prompt, r"\[\d+\]")
        self.assertIn("提示不是待翻译输入", self.context)
        self.assertIn("禁止翻译、复述或为上下文生成任何编号标签", self.context)

    def test_image_pipeline_passes_every_block_kind_without_ocr_rerun(self) -> None:
        pipeline_start = self.store.index("private func runImageTranslationPipeline(")
        batch_start = self.store.index("private func translateJapaneseImageBatch(")
        pipeline = self.store[pipeline_start:batch_start]
        for marker in (
            "let batchTextKinds = batch.blocks.map { $0.textKind ?? .dialogue }",
            "textKind: batchTextKinds.first ?? .dialogue",
            "batchTextKinds: batchTextKinds",
            "Self.imageTranslationBatches(recognizedBlocks)",
            "translateJapaneseImageBatch(",
        ):
            self.assertIn(marker, pipeline)
        self.assertNotIn("recognizeTextBlocks(in: data", self.store[self.store.index("private func translateJapaneseImageBatch("):self.store.index("private static func imageTranslationBatches(")])

    def test_existing_batch_tags_and_bounds_remain_unchanged(self) -> None:
        batch_start = self.store.index("private func translateJapaneseImageBatch(")
        batch_end = self.store.index("private static func imageTranslationBatches(")
        batch = self.store[batch_start:batch_end]
        for marker in (
            "let expectedIDs = blocks.indices.map { startIndex + $0 + 1 }",
            'return "[\\(expectedIDs[offset])] \\(text)"',
            'joined(separator: "\\n")',
            "translationProfile: .mangaBlocks",
            "mangaBatchSampling(",
        ):
            self.assertIn(marker, batch)
        batching = self.store[batch_end:self.store.index("private static func parseMangaTaggedTranslations(")]
        self.assertIn("let maximumBlocks = 8", batching)
        self.assertIn("let maximumCharacters = 1_800", batching)

    def test_version_workflow_and_docs_are_current(self) -> None:
        combined = self.gemma + self.workflow + self.route + self.flow + self.update_log + self.test_log
        for marker in (
            "scripts/test-v3299-japanese-translation-kind-context-contract.py",
            "v3.299",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, combined)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.340", "3.340"],
        )

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3299-japanese-translation-kind-context-contract.py")
        for source in (self.context, self.store, self.gemma, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
