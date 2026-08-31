#!/usr/bin/env python3
"""Static and pure-policy contract for v3.378 leading prompt recovery."""

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


def line_start_prompt_match(value: str, marker: str):
    folded_value = folded(value)
    folded_marker = folded(marker)
    search_start = 0
    while search_start < len(folded_value):
        offset = folded_value.find(folded_marker, search_start)
        if offset < 0:
            return None
        line_start = folded_value.rfind("\n", 0, offset) + 1
        if not trim_edge_punctuation(folded_value[line_start:offset]):
            line_end = folded_value.find("\n", offset + len(folded_marker))
            if line_end < 0:
                line_end = len(value)
            return {
                "line_start": line_start,
                "marker_start": offset,
                "marker_end": offset + len(folded_marker),
                "line_end": line_end,
                "marker": marker,
            }
        search_start = offset + len(folded_marker)
    return None


def first_line_start_prompt_marker(value: str):
    matches = [
        match
        for marker in LINE_START_PROMPT_MARKERS
        if (match := line_start_prompt_match(value, marker)) is not None
    ]
    return min(matches, key=lambda item: (item["line_start"], item["marker_start"])) if matches else None


def is_separator(character: str) -> bool:
    return character.isspace() or unicodedata.category(character).startswith("P")


def leading_prompt_payload(value: str, match) -> str | None:
    if match["marker"] != "Output only":
        return None
    suffix = value[match["marker_end"] : match["line_end"]]
    cursor = 0
    saw_punctuation = False
    while cursor < len(suffix) and is_separator(suffix[cursor]):
        saw_punctuation = saw_punctuation or unicodedata.category(
            suffix[cursor]
        ).startswith("P")
        cursor += 1
    if not saw_punctuation or cursor >= len(suffix):
        return None
    payload = suffix[cursor:].strip()
    return payload or None


def cut_translation_controls(output: str) -> str:
    text = output.strip()
    for marker in TERMINAL_CONTROL_MARKERS:
        if marker in text:
            text = text.split(marker, 1)[0].strip()

    while True:
        match = first_line_start_prompt_marker(text)
        if match is None:
            break
        prefix = text[: match["line_start"]]
        if trim_edge_punctuation(prefix):
            text = prefix.strip()
            break
        suffix_start = (
            match["line_end"] + 1
            if match["line_end"] < len(text)
            else len(text)
        )
        suffix = text[suffix_start:]
        payload = leading_prompt_payload(text, match)
        text = payload if payload and not suffix else (
            f"{payload}\n{suffix}" if payload else suffix
        )
    return text.strip()


class TranslationLeadingPromptRecoveryContractTests(unittest.TestCase):
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

    def test_leading_prompt_lines_are_removed_without_losing_following_translation(self) -> None:
        self.assertEqual(
            cut_translation_controls("Output only\n你好。"),
            "你好。",
        )
        self.assertEqual(
            cut_translation_controls("You are a translation engine.\n你好。"),
            "你好。",
        )
        self.assertEqual(
            cut_translation_controls("【Hard rules:】\n你好。"),
            "你好。",
        )

    def test_output_only_inline_translation_payload_is_preserved(self) -> None:
        self.assertEqual(
            cut_translation_controls("Output only: 你好。"),
            "你好。",
        )
        self.assertEqual(
            cut_translation_controls("Output only the translation:\n你好。"),
            "你好。",
        )

    def test_multiple_leading_prompt_lines_are_recovered_in_order(self) -> None:
        self.assertEqual(
            cut_translation_controls(
                "You are a translation engine.\nOutput only\n你好。"
            ),
            "你好。",
        )
        self.assertEqual(
            cut_translation_controls(
                "Output only\nHard rules:\n你好。"
            ),
            "你好。",
        )

    def test_prompt_after_real_translation_still_cuts_the_echo_suffix(self) -> None:
        self.assertEqual(
            cut_translation_controls(
                "你好。\nTranslate the following text\n待处理输入"
            ),
            "你好。",
        )

    def test_embedded_prompt_phrases_and_terminal_tokens_keep_existing_boundaries(self) -> None:
        self.assertEqual(
            cut_translation_controls("故事里写着 Translate the following text，但这仍是译文。"),
            "故事里写着 Translate the following text，但这仍是译文。",
        )
        self.assertEqual(
            cut_translation_controls("你好。<end_of_turn>prompt echo"),
            "你好。",
        )

    def test_source_wires_recovery_before_existing_validation_and_qa(self) -> None:
        cleaner = function_body(
            self.gemma,
            "private func cleanTranslationOutput(\n",
        )
        for marker in (
            "func lineStartPromptMarkerMatch(",
            "func firstLineStartPromptMarker(",
            "func leadingPromptPayload(",
            "func removeLeadingPromptLine(",
            "while let match = firstLineStartPromptMarker(in: text)",
            "let hasPriorContent = !prefix",
            "return try validateTranslationOutput(",
        ):
            self.assertIn(marker, cleaner)
        for marker in (
            "TranslationBatchQualityEvaluator.singleOutputFailures(",
            "TranslationBatchQualityEvaluator.evaluate(",
            "TranslationOutputPolicy.isPlaceholderResponse",
            "translateJapaneseImageBlockWithQA(",
        ):
            self.assertIn(marker, self.context + self.store)

    def test_ocr_layout_budget_persistence_and_optional_research_boundaries_remain(self) -> None:
        for source in (self.gemma, self.context):
            for forbidden in (
                "VisionOCRService",
                "MangaOCRService.shared",
                "persist()",
                "groundTruth",
                "KOHARU_DATA_ROOT",
            ):
                self.assertNotIn(forbidden, source)
        self.assertIn("VisionOCRService()", self.store)
        self.assertIn("persist()", self.store)
        self.assertNotIn("KOHARU_DATA_ROOT", self.store)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.378", "3.378"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3371-translation-leading-prompt-recovery-contract.py",
            "v3.378",
            "japanese-benchmark-v3.378-",
        ):
            self.assertIn(marker, combined)

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3371-translation-leading-prompt-recovery-contract.py"
        )
        for source in (self.gemma, self.context, self.store, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
