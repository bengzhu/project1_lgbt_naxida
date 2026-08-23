#!/usr/bin/env python3
"""Static contract for v3.300 global block ordinals in kind metadata."""

from __future__ import annotations

import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class JapaneseTranslationKindIndexContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.update_log = read("update_log.md")
        cls.test_log = read("md/test/test.md")

    def test_context_preserves_global_batch_ordinal_metadata(self) -> None:
        for marker in (
            "var batchTextKinds: [TranslationTextKind]",
            "var batchStartIndex: Int?",
            "batchStartIndex: Int? = nil",
            "case batchStartIndex",
            "batchStartIndex = try container.decodeIfPresent(\n            Int.self",
            "batchStartIndex: batchStartIndex.map { max($0, 0) }",
            "let ordinal = (context.batchStartIndex ?? 0) + index + 1",
            'lines.append("第\\(ordinal)块：\\(kind.promptLabel)")',
        ):
            self.assertIn(marker, self.context)
        self.assertIn("batchStartIndex == nil", self.context)
        self.assertIn("batchTextKinds: Array(batchTextKinds.prefix(8))", self.context)

    def test_second_batch_hint_matches_tagged_input_ordinal(self) -> None:
        self.assertEqual(
            "\n".join(
                f"第{8 + index + 1}块：{kind}"
                for index, kind in enumerate(["对白", "旁白"])
            ),
            "第9块：对白\n第10块：旁白",
        )
        self.assertNotRegex("第9块：对白\n第10块：旁白", r"\[\d+\]")
        self.assertIn("提示不是待翻译输入", self.context)
        self.assertIn("编号标签", self.context)

    def test_image_pipeline_passes_batch_start_without_rerunning_ocr(self) -> None:
        pipeline_start = self.store.index("private func runImageTranslationPipeline(")
        batch_start = self.store.index("private func translateJapaneseImageBatch(")
        pipeline = self.store[pipeline_start:batch_start]
        for marker in (
            "let batchTextKinds = batch.blocks.map { $0.textKind ?? .dialogue }",
            "batchTextKinds: batchTextKinds",
            "batchStartIndex: batch.startIndex",
            "let expectedIDs = blocks.indices.map { startIndex + $0 + 1 }",
        ):
            self.assertIn(marker, pipeline + self.store[batch_start:])
        self.assertNotIn(
            "recognizeTextBlocks(in: data",
            self.store[
                self.store.index("private func translateJapaneseImageBatch(") :
                self.store.index("private static func imageTranslationBatches(")
            ],
        )

    def test_existing_tag_and_budget_contracts_are_unchanged(self) -> None:
        batch_start = self.store.index("private func translateJapaneseImageBatch(")
        batch_end = self.store.index("private static func imageTranslationBatches(")
        batch = self.store[batch_start:batch_end]
        for marker in (
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
        combined = self.workflow + self.route + self.flow + self.update_log + self.test_log
        for marker in (
            "scripts/test-v3300-japanese-translation-kind-index-contract.py",
            "v3.300",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, combined)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.322", "3.322"],
        )

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3300-japanese-translation-kind-index-contract.py")
        for source in (self.context, self.store, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
