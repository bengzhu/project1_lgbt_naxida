#!/usr/bin/env python3
"""Static and pure-policy contract for the v3.288 context/QA boundary."""

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


def load_json(relative: str) -> dict:
    payload = json.loads(read(relative))
    if not isinstance(payload, dict):
        raise AssertionError(f"expected object JSON: {relative}")
    return payload


def load_evaluator():
    path = ROOT / "scripts/evaluate-japanese-translation-context-qa.py"
    spec = importlib.util.spec_from_file_location("v3288_context_qa", path)
    if spec is None or spec.loader is None:
        raise AssertionError("unable to load v3.288 evaluator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TranslationContextQAContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.model = load_evaluator()
        cls.fixture = load_json("benchmarks/japanese_translation/examples/translation_context_qa/input.json")
        cls.input_schema = load_json("benchmarks/japanese_translation/schema/translation-context-qa-input.schema.json")
        cls.report_schema = load_json("benchmarks/japanese_translation/schema/translation-context-qa-report.schema.json")
        cls.context_source = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
        cls.update_log = read("update_log.md")
        cls.contract_source = read("scripts/test-v3288-japanese-translation-context-qa-contract.py")

    def test_schema_and_fixture_are_strict_and_cover_context_kinds(self) -> None:
        self.assertEqual(self.input_schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
        self.assertFalse(self.input_schema["additionalProperties"])
        self.assertFalse(self.report_schema["additionalProperties"])
        self.assertTrue(self.fixture["contractExampleOnly"])
        self.assertEqual(self.fixture["context"]["sourceLanguage"], "ja")
        self.assertEqual(self.fixture["context"]["targetLanguage"], "zh-CN")
        kinds = {term["kind"] for term in self.fixture["context"]["confirmedTerms"]}
        self.assertEqual(kinds, {"personName", "addressing"})
        self.assertIn("sfx", {block["kind"] for batch in self.fixture["batches"] for block in batch["sourceBlocks"]})
        summary = self.fixture["context"]["previousBatchSummary"]
        self.assertTrue(summary["isReadOnly"])
        self.assertFalse(summary["containsPendingInputBlocks"])
        self.assertTrue(summary["generatedFromCompletedBlocks"])

    def test_evaluator_is_fail_closed_and_reports_block_only_actions(self) -> None:
        report = self.model.evaluate(copy.deepcopy(self.fixture))
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["promotionStatus"], "notEligible")
        self.assertFalse(report["productSelectionChanged"])
        self.assertEqual(
            [(item["batchID"], item["failedBlockIDs"], item["action"]) for item in report["batchReports"]],
            [
                ("page-01-batch-01", [], "accept"),
                ("page-01-batch-02", [], "accept"),
                ("page-01-batch-03", [4], "retryFailedBlocksOnly"),
                ("page-01-batch-04", [5], "persistPartialAndStop"),
            ],
        )
        self.assertIn("G-real-artifact", {gate["gateID"] for gate in report["gateLedger"]})

    def test_quality_mutations_cover_leakage_numbers_terms_length_and_tags(self) -> None:
        valid = copy.deepcopy(self.fixture)
        batch_one = valid["batches"][0]
        batch_one["rawOutput"] = "[1] Koharu先生、9時に来て。"
        leaked = self.model.evaluate_batch(batch_one, valid["context"])
        self.assertIn("sourceLeakage", leaked["failureReasons"]["1"])

        context_leak = copy.deepcopy(self.fixture)
        context_leak["batches"][1]["rawOutput"] = "[2] 小春老师，9点来。"
        context_leak_report = self.model.evaluate_batch(
            context_leak["batches"][1], context_leak["context"]
        )
        self.assertIn(
            "previousContextLeakage",
            context_leak_report["failureReasons"]["2"],
        )

        revoked = copy.deepcopy(self.fixture)
        revoked_batch = revoked["batches"][1]
        revoked_batch["rawOutput"] = "[2] 大人等了3个人。"
        revoked_report = self.model.evaluate_batch(revoked_batch, revoked["context"])
        self.assertIn("revokedTermUse", revoked_report["failureReasons"]["2"])

        long_output = copy.deepcopy(self.fixture)
        long_batch = long_output["batches"][0]
        long_batch["rawOutput"] = "[1] " + "中文" * 80
        long_report = self.model.evaluate_batch(long_batch, long_output["context"])
        self.assertIn("outputTooLong", long_report["failureReasons"]["1"])

        duplicate = copy.deepcopy(self.fixture["batches"][2])
        duplicate["rawOutput"] = "[3] 小春老师。\n[3] 小春老师。\n[4] 你会在13点来。"
        duplicate_report = self.model.evaluate_batch(duplicate, self.fixture["context"])
        self.assertIn("duplicateTags", duplicate_report["failureReasons"]["3"])

        out_of_order = copy.deepcopy(self.fixture["batches"][2])
        out_of_order["rawOutput"] = "[4] 你会在13点来。\n[3] 小春老师。"
        order_report = self.model.evaluate_batch(out_of_order, self.fixture["context"])
        self.assertEqual(set(order_report["failedBlockIDs"]), {3, 4})
        self.assertIn("outOfOrderTags", order_report["failureReasons"]["3"])

    def test_context_cancel_and_persistence_mutations_fail_closed(self) -> None:
        mutated = copy.deepcopy(self.fixture)
        mutated["batches"][2]["cancelScenario"]["rerunsOCR"] = True
        with self.assertRaises(self.model.ContextQAError):
            self.model.evaluate(mutated)

        mutated = copy.deepcopy(self.fixture)
        mutated["context"]["previousBatchSummary"]["containsPendingInputBlocks"] = True
        with self.assertRaises(self.model.ContextQAError):
            self.model.evaluate(mutated)

        mutated = copy.deepcopy(self.fixture)
        mutated["boundary"]["defaultProductSelectionChanged"] = True
        with self.assertRaises(self.model.ContextQAError):
            self.model.evaluate(mutated)

    def test_product_request_prompt_and_store_boundaries_are_wired_without_ocr_rerun(self) -> None:
        for marker in (
            "struct TranslationPromptContext",
            "struct TranslationReadOnlyBatchSummary",
            "struct TranslationTermMemoryEntry",
            "enum TranslationTermStatus",
            "case confirmed",
            "case revoked",
            "func promptSection()",
            "sourceLeakage",
            "previousContextLeakage",
            "numberMismatch",
            "confirmedTermMismatch",
            "targetLanguageDensity",
            "outputTooLong",
            "extraTag",
            "duplicateTags",
            "outOfOrderTags",
        ):
            self.assertIn(marker, self.context_source)
        self.assertRegex(
            self.context_source,
            r'(?s)guard index < expectedRecognized\.count,.*?else \{.*?'
            r'addFailure\(offset: expectedOffset, reason: "outOfOrderTags"\).*?'
            r'\n\s+continue\n\s+\}',
        )
        for marker in (
            "var translationContext: TranslationPromptContext = .empty",
            "var translationTerms: [TranslationTermMemoryEntry]",
        ):
            self.assertIn(marker, self.models)
        self.assertIn("request.translationContext.promptSection()", self.gemma)
        for marker in (
            "只读翻译上下文",
            "禁止翻译、复述或为上下文生成任何编号标签",
            r'"本次文字类型：\(context.textKind.promptLabel)"',
            r'"- \(term.kind.rawValue)：\(term.source) => \(term.target)"',
            r'"- #\(item.ordinal) \(item.kind.promptLabel)：\(item.sourceExcerpt) => \(item.targetExcerpt)"',
            r'"单块译文最长 \(maxOutputCharacters) 个字符；超出时保持信息完整并压缩表达。"',
        ):
            self.assertIn(marker, self.context_source)
        for forbidden in (
            "本次文字类型：(context.textKind.promptLabel)",
            "- (term.kind.rawValue)：(term.source) => (term.target)",
            "- #(item.ordinal) (item.kind.promptLabel)：(item.sourceExcerpt) => (item.targetExcerpt)",
            "单块译文最长 (maxOutputCharacters) 个字符",
        ):
            self.assertNotIn(forbidden, self.context_source)
        for marker in (
            "@Published var translationTermMemory",
            "func upsertTranslationTerm(",
            "func revokeTranslationTerm(source:",
            "previousBatchSummary",
            "TranslationBatchQualityEvaluator.evaluate(",
            "qualityFailure",
            r'\(ids.map(String.init).joined(separator: ","))',
            "正在只补译",
        ):
            self.assertIn(marker, self.store)
        self.assertIn(
            "let resolvedTargetLanguage = requestTargetLanguage ?? targetLanguage\n"
            "        return ModelGenerationRequest(",
            self.store,
        )
        self.assertNotIn("recognizeTextBlocks(in: data", self.store[self.store.index("private func translateJapaneseImageBatch("):self.store.index("private static func imageTranslationBatches(")])

    def test_standalone_transcript_model_evaluators_include_dependency_closure(self) -> None:
        evaluator_sources = (
            "scripts/test-v200-koharu-shadow-coverage-contract.py",
            "scripts/test-v201-koharu-geometry-coverage-contract.py",
            "scripts/test-v3242-image-japanese-vertical-punctuation-contract.py",
            "scripts/test-v3243-image-japanese-direction-override-contract.py",
            "scripts/test-v367-image-block-geometry-safety-contract.py",
            "scripts/test-v3281-image-ocr-provenance-runtime.sh",
            "scripts/test-v3290-image-translation-render-safety-runtime.sh",
        )
        for relative in evaluator_sources:
            source = read(relative)
            self.assertIn("parse-as-library", source, relative)
            self.assertIn("TranscriptModels.swift", source, relative)
            self.assertIn("ImageOCRProvenance.swift", source, relative)
            self.assertIn("ImageOCRLayoutEngine.swift", source, relative)
            self.assertIn("TranslationContextQuality.swift", source, relative)

    def test_new_standalone_fixtures_stub_probe_only_transcript_payloads(self) -> None:
        required_stubs = (
            "struct MangaOverlayBubbleGeometryDiagnostics: Equatable, Codable, Sendable {}",
            "struct MangaOverlaySliceOCRDiagnostics: Equatable, Codable, Sendable {}",
            "struct MangaOverlayCropFallbackSelfTest: Equatable, Codable, Sendable {}",
        )
        for relative in (
            "scripts/fixtures/v3281-image-ocr-provenance-evaluator.swift",
            "scripts/fixtures/v3290-image-translation-render-safety-evaluator.swift",
        ):
            source = read(relative)
            for marker in required_stubs:
                self.assertIn(marker, source, relative)

    def test_workflow_project_route_and_contract_are_explicit(self) -> None:
        for marker in (
            "scripts/test-v3288-japanese-translation-context-qa-contract.py",
            "scripts/run-japanese-translation-context-qa-cloud-smoke.sh",
            "translation-context-qa-report.json",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, self.workflow)
        self.assertIn("TranslationContextQuality.swift in Sources", self.project)
        self.assertIn("TranslationContextQuality.swift", self.project)
        versions = re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)
        self.assertEqual(versions, ["3.330", "3.330"])
        self.assertIn("v3.288", self.route)
        self.assertIn("v3.288", self.update_log)
        for marker in (
            "跨 batch 只读摘要",
            "旧术语撤销",
            "数字/专名保留",
            "只重译失败块",
            "部分成功持久化",
        ):
            self.assertIn(marker, self.route + self.update_log)

    def test_contract_has_no_process_entry_and_cloud_wrapper_is_guarded(self) -> None:
        process_word = "sub" + "process"
        popen_word = "Po" + "pen"
        system_word = "os." + "system"
        for source in (self.contract_source, read("scripts/evaluate-japanese-translation-context-qa.py")):
            self.assertNotIn(process_word, source)
            self.assertNotIn(popen_word, source)
            self.assertNotIn(system_word, source)
        wrapper = read("scripts/run-japanese-translation-context-qa-cloud-smoke.sh")
        self.assertIn('GITHUB_ACTIONS:-false', wrapper)
        self.assertIn("cloud-only", wrapper)
        self.assertIn("evaluate-japanese-translation-context-qa.py", wrapper)


if __name__ == "__main__":
    unittest.main(verbosity=2)
