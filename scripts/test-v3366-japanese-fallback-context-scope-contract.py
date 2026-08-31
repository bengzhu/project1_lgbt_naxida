#!/usr/bin/env python3
"""Static and pure-policy contract for v3.386 Japanese fallback scoping."""

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


def aligned_kind(kinds: list[str], offset: int, fallback: str = "dialogue") -> str:
    if 0 <= offset < len(kinds):
        return kinds[offset]
    return fallback


class JapaneseFallbackContextScopeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("README.md")
            + read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("update_log.md")
        )

    def test_aligned_kind_policy_does_not_inherit_batch_first_kind(self) -> None:
        mixed = ["sfx", "dialogue", "title"]
        self.assertEqual(aligned_kind(mixed, 0), "sfx")
        self.assertEqual(aligned_kind(mixed, 1), "dialogue")
        self.assertEqual(aligned_kind([], 0), "dialogue")
        self.assertEqual(aligned_kind(mixed, 8), "dialogue")

    def test_context_exposes_exact_batch_kind_with_safe_fallback(self) -> None:
        body = function_body(self.context, "func batchTextKind(")
        for marker in (
            "guard batchTextKinds.indices.contains(offset) else { return fallback }",
            "return batchTextKinds[offset]",
        ):
            self.assertIn(marker, body)
        self.assertIn("at offset: Int", self.context)
        self.assertIn("fallback: TranslationTextKind = .dialogue", self.context)

    def test_single_block_scope_preserves_read_only_context_and_removes_batch_metadata(self) -> None:
        body = function_body(self.context, "func scopedToSingleBlock(")
        for marker in (
            "confirmedTerms: confirmedTerms",
            "previousBatchSummary: previousBatchSummary",
            "textKind: textKind",
            "maxOutputCharacters: maxOutputCharacters",
            "textKind.defaultMaximumOutputCharacters(for: sourceCharacterCount)",
            "copy.requestSourceLanguage = requestSourceLanguage",
            "copy.requestTargetLanguage = requestTargetLanguage",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("batchTextKinds:", body)
        self.assertNotIn("batchStartIndex:", body)
        self.assertNotIn("persist()", body)

    def test_batch_qa_uses_the_kind_aligned_with_each_tag(self) -> None:
        body = function_body(self.store, "private func translateJapaneseImageBatch(")
        qa_start = body.index("let qualityReport = TranslationBatchQualityEvaluator.evaluate(")
        qa_end = body.index("var translations =", qa_start)
        qa = body[qa_start:qa_end]
        for marker in (
            "kind: translationContext.batchTextKind(",
            "at: offset",
            "fallback: block.textKind ?? .dialogue",
        ):
            self.assertIn(marker, qa)
        self.assertNotIn("kind: block.textKind ?? translationContext.textKind", qa)

    def test_plain_fallback_scopes_kind_and_length_before_model_and_qa(self) -> None:
        body = function_body(
            self.store,
            "private func translateJapaneseImageBlockWithQA(\n",
        )
        for marker in (
            "let batchOffset = translationContext.batchStartIndex.map",
            "expectedID - startIndex - 1",
            "let effectiveTextKind = block.textKind",
            "translationContext.batchTextKind(at: $0)",
            "?? .dialogue",
            "let singleBlockContext = translationContext.scopedToSingleBlock(",
            "textKind: effectiveTextKind",
            "sourceCharacterCount: block.original.count",
            "translationContext: singleBlockContext",
            "kind: effectiveTextKind",
        ):
            self.assertIn(marker, body)
        self.assertLess(
            body.index("let singleBlockContext"),
            body.index("let candidate = try await translate("),
        )
        self.assertLess(
            body.index("let candidate = try await translate("),
            body.index("TranslationBatchQualityEvaluator.singleOutputFailures("),
        )
        self.assertNotIn("translationContext: translationContext", body)

    def test_scope_does_not_change_batch_budget_or_ocr_persistence_boundaries(self) -> None:
        batch_body = function_body(self.store, "private static func imageTranslationBatches(")
        for marker in ("let maximumBlocks = 8", "let maximumCharacters = 1_800"):
            self.assertIn(marker, batch_body)
        helper = function_body(
            self.store,
            "private func translateJapaneseImageBlockWithQA(\n",
        )
        for forbidden in (
            "recognizeTextBlock(",
            "recognizeTextBlocks(",
            "imageTranslationBlocks =",
            "imageTranslationJapaneseBatchPlan =",
            "persist()",
            "MangaOCRService",
        ):
            self.assertNotIn(forbidden, helper)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.386", "3.386"],
        )
        self.assertIn(
            "python3 -B scripts/test-v3366-japanese-fallback-context-scope-contract.py",
            self.workflow,
        )
        for marker in (
            "scripts/test-v3366-japanese-fallback-context-scope-contract.py",
            "v3.386",
            "japanese-benchmark-v3.386-",
            "test/3.png",
            "未提供",
        ):
            self.assertIn(marker, self.workflow + self.docs)

    def test_contract_has_no_process_entry(self) -> None:
        contract = read("scripts/test-v3366-japanese-fallback-context-scope-contract.py")
        for source in (contract, self.context, self.store):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
