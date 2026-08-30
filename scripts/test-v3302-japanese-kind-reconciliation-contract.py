#!/usr/bin/env python3
"""Static contract for v3.302 Japanese OCR kind reconciliation."""

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


class JapaneseKindReconciliationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.update_log = read("update_log.md")
        cls.test_log = read("md/test/test.md")

    def test_automatic_recognition_exposes_kind_reconciliation_switch(self) -> None:
        self.assertIn("reconcileJapaneseTextKind: Bool = false", self.vision)
        body = function_body(self.vision, "private static func recognizedBlock(")
        for marker in (
            "if reconcileJapaneseTextKind",
            "TranslationTextKindClassifier.inferJapaneseKind(",
            "text: recognized.original",
            "boundingBox: recognized.boundingBox",
        ):
            self.assertIn(marker, body)

    def test_only_japanese_automatic_reads_reconcile_the_hint(self) -> None:
        block_reader = function_body(
            self.vision,
            "private static func recognizeTextBlockDetached(\n        image: CGImage,",
        )
        self.assertIn("reconcileJapaneseTextKind: japanese", block_reader)
        manga_reader = function_body(
            self.vision,
            "private static func recognizeTextBlockDetached(\n        imageData: Data,",
        )
        self.assertIn("Self.recognizeTextBlockDetached(", manga_reader)
        self.assertNotIn("reconcileJapaneseTextKind: true", manga_reader)

    def test_manga_and_vision_recovery_paths_reconcile_after_new_text(self) -> None:
        self.assertIn("reconcileJapaneseTextKind: true", self.vision)
        self.assertIn("reconcileJapaneseTextKind: japanese", self.vision)
        self.assertIn("recoverWeakJapaneseBlocks", self.vision)
        recovery = function_body(
            self.vision,
            "private static func recoverWeakJapaneseBlocks(\n",
        )
        self.assertIn("recovered[candidate.offset] = reread", recovery)

    def test_scoped_rerecognition_commits_the_reconciled_kind(self) -> None:
        rerecognition = function_body(
            self.store,
            "func rerecognizeImageTranslationBlock(\n",
        )
        self.assertIn("var replacement = block", rerecognition)
        self.assertIn("replacement.original = recognizedOriginal", rerecognition)
        self.assertIn("replacement.textKind = recognized.textKind", rerecognition)
        self.assertIn("self.imageTranslationBlocks[currentIndex] = replacement", rerecognition)

    def test_recovery_does_not_change_ocr_geometry_or_budget_boundaries(self) -> None:
        combined = self.vision + self.store
        for marker in (
            "ImageOCRLayoutEngine.layout(",
            "Self.imageTranslationBatches(recognizedBlocks)",
            "maximumJapaneseWeakBlockRecoveryRequests",
            "let maximumBlocks = 8",
            "let maximumCharacters = 1_800",
        ):
            self.assertIn(marker, combined)
        self.assertNotIn(
            "recognizeTextBlocks(in: data",
            rerecognition := rerecognition_body(self.store),
        )

    def test_optional_kind_remains_legacy_compatible(self) -> None:
        self.assertIn("var textKind: TranslationTextKind?", self.models)
        self.assertIn("textKind: TranslationTextKind? = nil", self.models)
        self.assertIn("TranslationTextKindClassifier", self.context)
        self.assertNotIn("return .narration", self.context)
        self.assertNotIn("return .title", self.context)

    def test_version_workflow_and_docs_are_current(self) -> None:
        combined = self.workflow + self.route + self.flow + self.update_log + self.test_log
        for marker in (
            "scripts/test-v3302-japanese-kind-reconciliation-contract.py",
            "v3.302",
            "japanese-benchmark-v3.302-",
        ):
            self.assertIn(marker, combined)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.359", "3.359"],
        )

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3302-japanese-kind-reconciliation-contract.py")
        for source in (self.vision, self.store, self.context, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


def rerecognition_body(source: str) -> str:
    return function_body(source, "func rerecognizeImageTranslationBlock(\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
