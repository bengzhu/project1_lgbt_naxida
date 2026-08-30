#!/usr/bin/env python3
"""Static contract for v3.304 stable Japanese image batch context boundaries."""

from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import re
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


def load_evaluator():
    path = ROOT / "scripts/evaluate-japanese-translation-context-qa.py"
    spec = importlib.util.spec_from_file_location("v3304_context_qa", path)
    if spec is None or spec.loader is None:
        raise AssertionError("unable to load translation context evaluator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class JapaneseTranslationBatchBoundaryContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.update_log = read("update_log.md")
        cls.test_log = read("md/test/test.md")
        cls.fixture = json.loads(
            read("benchmarks/japanese_translation/examples/translation_context_qa/input.json")
        )
        cls.evaluator = load_evaluator()

    def test_page_pipeline_freezes_identity_plan_before_translation(self) -> None:
        body = function_body(self.store, "private func runImageTranslationPipeline(")
        japanese_branch = body[body.index("if sourceLanguage == .japanese") :]
        self.assertIn("let batches = Self.imageTranslationBatches(recognizedBlocks)", japanese_branch)
        self.assertIn(
            "imageTranslationJapaneseBatchPlan = Self.imageTranslationBatchPlans(from: batches)",
            japanese_branch,
        )
        self.assertLess(
            japanese_branch.index("imageTranslationJapaneseBatchPlan ="),
            japanese_branch.index("for batch in batches"),
        )

    def test_context_reconstructs_from_active_and_ignored_identity_values(self) -> None:
        helper = function_body(self.store, "private func imageTranslationContextBlocks()")
        for marker in (
            "var blocksByID: [UUID: ImageTranslationBlock] = [:]",
            "for block in imageTranslationBlocks",
            "for snapshot in imageTranslationIgnoredBlockSnapshots.values",
            "imageTranslationOriginalBlockOrder",
            "seenIDs.insert(blockID).inserted",
        ):
            self.assertIn(marker, helper)
        prompt = function_body(
            self.store,
            "private func japaneseImageTranslationPrompt(\n",
        )
        self.assertIn("let contextBlocks = imageTranslationContextBlocks()", prompt)
        self.assertIn("let batchPlan = currentJapaneseImageTranslationBatchPlan()", prompt)
        self.assertNotIn("Self.imageTranslationBatches(imageTranslationBlocks)", prompt)

    def test_ignored_block_does_not_renumber_previous_batch(self) -> None:
        # Initial page plan: blocks 1...8 are batch zero and block 9 starts the
        # next batch. Removing visible block 1 must not turn blocks 2...9 into
        # the previous batch for a retry of block 9.
        original_plan = [list(range(1, 9)), [9]]
        visible_ids = list(range(2, 10))
        current_batch = next(
            index for index, block_ids in enumerate(original_plan) if 9 in block_ids
        )
        previous_batch = original_plan[current_batch - 1]
        naive_visible_plan = [visible_ids[:8]]
        self.assertEqual(previous_batch, list(range(1, 9)))
        self.assertNotEqual(previous_batch, naive_visible_plan[0])
        self.assertNotIn(9, previous_batch)

    def test_previous_summary_is_complete_and_fail_closed(self) -> None:
        prompt = function_body(
            self.store,
            "private func japaneseImageTranslationPrompt(\n",
        )
        for marker in (
            "let previousPlan = batchPlan[currentBatchIndex - 1]",
            "let previousBlocks = previousPlan.blockIDs.compactMap",
            "previousBlocks.count == previousPlan.blockIDs.count",
            "previousBlocks.allSatisfy",
            "TranslationReadOnlyBatchSummary(",
            "sourceExcerpt: previousBlock.original",
            "targetExcerpt: previousBlock.translation",
        ):
            self.assertIn(marker, prompt)
        self.assertNotIn("persist()", prompt)
        self.assertNotIn("recognizeText", prompt)

    def test_correction_and_reread_keep_plan_but_structure_edits_invalidate_it(self) -> None:
        correction = function_body(self.store, "func correctImageTranslationBlock(")
        reread = function_body(self.store, "func rerecognizeImageTranslationBlock(")
        self.assertNotIn("imageTranslationJapaneseBatchPlan = []", correction)
        self.assertNotIn("imageTranslationJapaneseBatchPlan = []", reread)
        rebuild = function_body(
            self.store,
            "private func rebuildImageTranslationOriginalBlockOrder()",
        )
        self.assertIn("imageTranslationJapaneseBatchPlan = []", rebuild)
        self.assertIn("structural edit creates a new block identity/order epoch", rebuild)

    def test_batch_plan_is_transient_and_restore_rebuilds_on_demand(self) -> None:
        snapshot_builder = function_body(
            self.store,
            "private func makeImageTranslationPersistenceSnapshot()",
        )
        snapshot_restore = function_body(
            self.store,
            "private func restoreImageTranslationPersistenceSnapshot(",
        )
        self.assertNotIn("imageTranslationJapaneseBatchPlan", snapshot_builder)
        self.assertIn("imageTranslationJapaneseBatchPlan = []", snapshot_restore)
        current_plan = function_body(
            self.store,
            "private func currentJapaneseImageTranslationBatchPlan()",
        )
        self.assertIn("Self.imageTranslationBatchPlans(", current_plan)
        self.assertIn("imageTranslationJapaneseBatchPlan = rebuilt", current_plan)

    def test_evaluator_still_rejects_previous_context_leakage(self) -> None:
        payload = copy.deepcopy(self.fixture)
        payload["batches"][1]["rawOutput"] = "[2] 小春老师，9点来。"
        report = self.evaluator.evaluate_batch(payload["batches"][1], payload["context"])
        self.assertIn("previousContextLeakage", report["failureReasons"]["2"])

    def test_version_workflow_and_docs_are_current(self) -> None:
        combined = self.workflow + self.route + self.flow + self.update_log + self.test_log
        for marker in (
            "scripts/test-v3304-japanese-translation-batch-boundary-contract.py",
            "v3.304",
            "japanese-benchmark-v3.306-",
        ):
            self.assertIn(marker, combined)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.359", "3.359"],
        )

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3304-japanese-translation-batch-boundary-contract.py"
        )
        for source in (self.store, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
