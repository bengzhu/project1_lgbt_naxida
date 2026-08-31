#!/usr/bin/env python3
"""Static and pure-policy contract for v3.382 translation control markers."""

from __future__ import annotations

import re
from pathlib import Path
import unicodedata
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


TERMINAL_CONTROL_MARKERS = ("<end_of_turn>", "<start_of_turn>")
LINE_START_PROMPT_MARKERS = (
    "You are a translation engine.",
    "Hard rules:",
    "Translate the following text",
    "Translate from",
    "User instruction:",
    "Output only",
)


def folded(value: str) -> str:
    return unicodedata.normalize("NFKC", value).casefold()


def trim_edge_punctuation(value: str) -> str:
    start = 0
    end = len(value)
    while start < end and (
        value[start].isspace()
        or unicodedata.category(value[start]).startswith("P")
    ):
        start += 1
    while end > start and (
        value[end - 1].isspace()
        or unicodedata.category(value[end - 1]).startswith("P")
    ):
        end -= 1
    return value[start:end]


def line_start_marker_offset(value: str, marker: str) -> int | None:
    folded_value = folded(value)
    folded_marker = folded(marker)
    search_start = 0
    while True:
        offset = folded_value.find(folded_marker, search_start)
        if offset < 0:
            return None
        line_start = folded_value.rfind("\n", 0, offset) + 1
        if not trim_edge_punctuation(folded_value[line_start:offset]):
            return line_start
        search_start = offset + len(folded_marker)


def cut_translation_controls(output: str) -> str:
    text = output.strip()
    for marker in TERMINAL_CONTROL_MARKERS:
        if marker in text:
            text = text.split(marker, 1)[0].strip()
    for marker in LINE_START_PROMPT_MARKERS:
        offset = line_start_marker_offset(text, marker)
        if offset is not None:
            text = text[:offset].strip()
    return text


class TranslationControlMarkerBoundaryContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
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

    def test_natural_language_controls_are_line_start_scoped(self) -> None:
        cleaner = function_body(
            self.gemma,
            "private func cleanTranslationOutput(\n",
        )
        for marker in (
            "let terminalControlMarkers",
            "let lineStartPromptMarkers",
            "func lineStartPromptMarkerMatch(",
            "range: searchStart..<value.endIndex",
            "beforeMarker.isEmpty",
            "let lineEnd = value[range.upperBound...].firstIndex(of: \"\\n\")",
            "func firstLineStartPromptMarker(",
        ):
            self.assertIn(marker, cleaner)
        self.assertNotIn("let cutMarkers", cleaner)
        self.assertIn("if let range = text.range(of: marker)", cleaner)
        self.assertIn(
            "lineStartPromptMarkerMatch(",
            cleaner,
        )

    def test_embedded_prompt_phrases_remain_translation_content(self) -> None:
        self.assertEqual(
            cut_translation_controls(
                "故事里写着 Translate the following text，但这仍是译文。"
            ),
            "故事里写着 Translate the following text，但这仍是译文。",
        )
        self.assertEqual(
            cut_translation_controls("The story says Output only in the sign."),
            "The story says Output only in the sign.",
        )
        self.assertEqual(
            cut_translation_controls("关于 Hard rules: 的说明。"),
            "关于 Hard rules: 的说明。",
        )

    def test_prompt_echo_at_output_or_line_start_is_removed(self) -> None:
        self.assertEqual(
            cut_translation_controls(
                "你好。\nTranslate the following text\n待处理输入"
            ),
            "你好。",
        )
        self.assertEqual(
            cut_translation_controls("Output only: 你好。"),
            "",
        )
        self.assertEqual(
            cut_translation_controls("【Hard rules:】\n你好。"),
            "",
        )

    def test_terminal_turn_tokens_remain_hard_boundaries(self) -> None:
        self.assertEqual(
            cut_translation_controls("你好。<end_of_turn>prompt echo"),
            "你好。",
        )
        self.assertEqual(
            cut_translation_controls("你好。\n<start_of_turn>"),
            "你好。",
        )

    def test_existing_translation_validation_and_qa_remain_wired(self) -> None:
        cleaner = function_body(
            self.gemma,
            "private func cleanTranslationOutput(\n",
        )
        self.assertIn("return try validateTranslationOutput(", cleaner)
        self.assertIn("sourceLanguage: sourceLanguage", cleaner)
        self.assertIn("targetLanguage: targetLanguage", cleaner)
        for marker in (
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "TranslationBatchQualityEvaluator.evaluate(",
            "TranslationOutputPolicy.isPlaceholderResponse",
            "translateJapaneseImageBlockWithQA(",
        ):
            self.assertIn(marker, self.context + self.store)
        for source in (self.gemma, self.context):
            for forbidden in (
                "VisionOCRService",
                "MangaOCRService.shared",
                "persist()",
                "groundTruth",
                "KOHARU_DATA_ROOT",
            ):
                self.assertNotIn(forbidden, source)
        self.assertNotIn("KOHARU_DATA_ROOT", self.store)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.382", "3.382"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3370-translation-control-marker-boundary-contract.py",
            "v3.382",
            "japanese-benchmark-v3.382-",
        ):
            self.assertIn(marker, combined)

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3370-translation-control-marker-boundary-contract.py"
        )
        for source in (self.gemma, self.context, self.store, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
