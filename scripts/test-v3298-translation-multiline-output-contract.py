#!/usr/bin/env python3
"""Static and pure-policy contract for v3.298 multiline translation output."""

from __future__ import annotations

import re
import unicodedata
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


def normalize_translation_lines(output: str) -> str:
    instruction_markers = (
        "translation engine",
        "do not summarize",
        "do not add explanations",
        "english ->",
        "只输出中文译文",
        "只输出译文",
        "不要输出英文原文",
        "简体中文翻译",
        "预设提示词",
        "输出风格",
    )
    label_markers = (
        "以下是翻译",
        "翻译如下",
        "翻译是：",
        "这是翻译",
    )
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    kept: list[str] = []

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

    for line in lines:
        bullet_body = line[2:].strip() if line.startswith("- ") else line
        metadata_bullet = line.startswith("- ") and (
            not bullet_body
            or any(marker in bullet_body.casefold() for marker in instruction_markers)
        )
        if metadata_bullet or (line.startswith("|") and line.endswith("|")):
            continue
        if any(marker in line.casefold() for marker in instruction_markers):
            continue
        folded_line = line.casefold()
        if any(
            (offset := folded_line.find(marker.casefold())) >= 0
            and not trim_edge_punctuation(folded_line[:offset])
            and not trim_edge_punctuation(
                folded_line[offset + len(marker.casefold()) :]
            )
            for marker in label_markers
        ):
            continue
        kept.append(line)
    return "\n".join(kept)


class TranslationMultilineOutputContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.update_log = read("update_log.md")
        cls.test_log = read("md/test/test.md")

    def test_cleaner_preserves_all_valid_translation_lines(self) -> None:
        body = function_body(
            self.gemma,
            "private func cleanTranslationOutput(\n",
        )
        self.assertIn('let candidate = lines.joined(separator: "\\n")', body)
        self.assertIn(
            "return try validateTranslationOutput(\n            candidate,\n            input: input,\n            sourceLanguage: sourceLanguage,\n            targetLanguage: targetLanguage\n        )",
            body,
        )
        self.assertNotIn("lines.last", body)
        self.assertNotIn("if let last", body)

    def test_legitimate_multiline_dialogue_and_bullets_are_not_truncated(self) -> None:
        self.assertEqual(
            normalize_translation_lines("第一句。\n第二句。"),
            "第一句。\n第二句。",
        )
        self.assertEqual(
            normalize_translation_lines("- 先走。\n- 我随后跟上。"),
            "- 先走。\n- 我随后跟上。",
        )

    def test_only_explicit_metadata_lines_are_removed(self) -> None:
        self.assertEqual(
            normalize_translation_lines("以下是翻译\n你好。\n翻译如下"),
            "你好。",
        )
        self.assertEqual(
            normalize_translation_lines("翻译是：你好。\n第二句。"),
            "翻译是：你好。\n第二句。",
        )
        self.assertEqual(
            normalize_translation_lines("- 只输出译文\n你好。\n| prompt |"),
            "你好。",
        )

    def test_version_workflow_and_docs_are_current(self) -> None:
        combined = self.gemma + self.workflow + self.route + self.update_log + self.test_log
        for marker in (
            "scripts/test-v3298-translation-multiline-output-contract.py",
            "v3.298",
            "lines.joined(separator: \"\\n\")",
            "japanese-benchmark-v3.301-",
        ):
            self.assertIn(marker, combined)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.383", "3.383"],
        )

    def test_contract_and_product_source_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3298-translation-multiline-output-contract.py")
        for source in (self.gemma, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
