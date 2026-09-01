#!/usr/bin/env python3
"""Static and pure-policy contract for v3.389 inline manga batch preambles."""

from __future__ import annotations

import re
from pathlib import Path
import unicodedata
import unittest


ROOT = Path(__file__).resolve().parents[1]

KNOWN_PREAMBLES = (
    "以下是翻译",
    "以下为翻译",
    "翻译如下",
    "译文如下",
    "翻译结果如下",
    "Translation",
    "Translations",
    "Here is the translation",
    "Here are the translations",
    "You are a translation engine",
    "Hard rules",
    "Translate the following text",
    "Translate from",
    "User instruction",
    "Output only",
)


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


def folded(value: str) -> str:
    return unicodedata.normalize("NFKC", value).casefold()


def edge_trimmed(value: str) -> str:
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


def is_known_preamble_line(value: str) -> bool:
    candidate = folded(edge_trimmed(value))
    return any(candidate == folded(marker) for marker in KNOWN_PREAMBLES)


def is_tagged_payload(value: str) -> bool:
    return re.match(r"^\[\d+\]", value) is not None


def inline_tagged_line(value: str) -> str | None:
    try:
        bracket = value.index("[")
    except ValueError:
        return None
    if not is_known_preamble_line(value[:bracket]):
        return None
    payload = value[bracket:].strip()
    return payload if is_tagged_payload(payload) else None


def strip_leading_manga_batch_preamble(value: str) -> str:
    lines = value.split("\n")
    cursor = 0
    removed_preamble = False
    while cursor < len(lines):
        trimmed = lines[cursor].strip()
        if not trimmed:
            cursor += 1
            continue
        if trimmed.startswith("["):
            break
        inline = inline_tagged_line(trimmed)
        if inline is not None:
            lines[cursor] = inline
            removed_preamble = True
            break
        if not is_known_preamble_line(trimmed):
            return value
        removed_preamble = True
        cursor += 1
    if not removed_preamble:
        return value
    return "\n".join(lines[cursor:]).strip()


class TranslationBatchInlinePreambleContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.context = read("AITRANS/Models/TranslationContextQuality.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = "".join(
            read(path)
            for path in (
                "README.md",
                "md/flow/flow.md",
                "md/flow/flowchart.md",
                "md/test/test.md",
                "md/人工空间/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md",
                "md/log/update_log.md",
            )
        )
        cls.cleaner = function_body(
            cls.gemma,
            "private func cleanMangaBlockOutput(\n",
        )
        cls.inline = function_body(
            cls.gemma,
            "private func inlineMangaBatchTaggedLine(from line: String)",
        )
        cls.preamble = function_body(
            cls.gemma,
            "private func stripLeadingMangaBatchPreamble(from value: String)",
        )

    def test_known_inline_preambles_preserve_the_first_tag_and_payload(self) -> None:
        cases = {
            "Translation: [1] 你好。\n[2] 世界。": "[1] 你好。\n[2] 世界。",
            "以下是翻译：[1] 你好。\n[2] 世界。": "[1] 你好。\n[2] 世界。",
            "You are a translation engine. [1] 你好。": "[1] 你好。",
            "ＴＲＡＮＳＬＡＴＩＯＮ： [1] 你好。": "[1] 你好。",
        }
        for raw, expected in cases.items():
            with self.subTest(raw=raw):
                self.assertEqual(strip_leading_manga_batch_preamble(raw), expected)

    def test_known_standalone_and_inline_preambles_can_be_chained(self) -> None:
        raw = "Translation:\nOutput only: [1] 一\n[2] 二"
        self.assertEqual(
            strip_leading_manga_batch_preamble(raw),
            "[1] 一\n[2] 二",
        )

    def test_unknown_inline_prefix_is_not_partially_sanitized(self) -> None:
        for value in (
            "The answer is: [1] 你好。",
            "Translation:\nThe answer is: [1] 你好。",
            "Translation with extra prose: [1] 你好。",
        ):
            with self.subTest(value=value):
                self.assertEqual(strip_leading_manga_batch_preamble(value), value)

    def test_first_tag_payload_is_never_treated_as_a_preamble(self) -> None:
        tagged = "[1] Translation: 你好。\n[2] 世界。"
        self.assertEqual(strip_leading_manga_batch_preamble(tagged), tagged)

    def test_cleaner_keeps_inline_recovery_before_the_existing_first_tag_guard(self) -> None:
        expected_ids_index = self.cleaner.index("let expectedIDs =")
        first_tag_index = self.cleaner.index("matchesFirstTagAtStart(in: text)")
        self.assertIn(
            "if let inlineTaggedLine = inlineMangaBatchTaggedLine(from: trimmed)",
            self.preamble,
        )
        self.assertIn("text = stripLeadingMangaBatchPreamble(from: text)", self.cleaner)
        self.assertLess(
            self.cleaner.index("text = stripLeadingMangaBatchPreamble(from: text)"),
            expected_ids_index,
        )
        self.assertLess(expected_ids_index, first_tag_index)
        for marker in (
            "lines[cursor] = inlineTaggedLine",
            "private func inlineMangaBatchTaggedLine(from line: String)",
            "private func isKnownMangaBatchPreambleLine(_ line: String)",
            "NSRegularExpression(pattern: #\"^\\[\\d+\\]\"#)",
            "text.first == \"[\"",
        ):
            self.assertIn(marker, self.gemma)

    def test_inline_helper_requires_known_prefix_and_numeric_tag(self) -> None:
        self.assertIn("let prefix = String(line[..<bracket])", self.inline)
        self.assertIn("isKnownMangaBatchPreambleLine(prefix)", self.inline)
        self.assertIn("let taggedPayload = String(line[bracket...])", self.inline)
        self.assertIn("NSRegularExpression", self.inline)
        self.assertIn("return taggedPayload", self.inline)

    def test_batch_parser_and_qa_boundaries_remain_strict(self) -> None:
        parser = function_body(
            self.store,
            "private static func parseMangaTaggedTranslations(\n",
        )
        for marker in (
            "let expectedIndexByID = Dictionary(",
            "guard !matches.isEmpty else",
            "guard recognizedCount > 0 else",
            "throw ImageMangaBatchTranslationError.missingTags",
            "throw ImageMangaBatchTranslationError.unexpectedTags",
        ):
            self.assertIn(marker, parser)
        self.assertIn("TranslationBatchQualityEvaluator.evaluate(", self.store)
        self.assertIn("translationProfile: .mangaBlocks", self.store)
        self.assertIn("targetLanguageDensity", self.context)

    def test_version_workflow_docs_and_fixture_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.390", "3.390"],
        )
        previous = "python3 -B scripts/test-v3376-translation-metadata-content-boundary-contract.py"
        current = "python3 -B scripts/test-v3377-translation-batch-inline-preamble-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        combined = self.workflow + self.docs
        for marker in (current, "v3.389", "japanese-benchmark-v3.389-"):
            self.assertIn(marker, combined)
        self.assertFalse((ROOT / "test/3.png").exists())

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3377-translation-batch-inline-preamble-contract.py")
        for source in (self.gemma, self.store, self.context, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("xcode" + "build", source)
            self.assertNotIn("reference/" + "koharu-main", source)
            self.assertNotIn("KOHARU_" + "DATA_ROOT", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
