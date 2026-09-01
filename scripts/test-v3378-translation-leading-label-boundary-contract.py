#!/usr/bin/env python3
"""Static and pure-policy contract for v3.389 leading translation labels."""

from __future__ import annotations

import re
from pathlib import Path
import unicodedata
import unittest


ROOT = Path(__file__).resolve().parents[1]

LEADING_LABELS = (
    "翻译结果如下",
    "译文如下",
    "Here are the translations",
    "Here is the translation",
    "Translations",
    "Translation",
    "翻译结果",
    "译文",
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


def is_edge_character(character: str) -> bool:
    return character.isspace() or unicodedata.category(character).startswith("P")


def edge_trimmed(value: str) -> str:
    start = 0
    end = len(value)
    while start < end and is_edge_character(value[start]):
        start += 1
    while end > start and is_edge_character(value[end - 1]):
        end -= 1
    return value[start:end]


def is_only(value: str, predicate) -> bool:
    return bool(value) and all(predicate(character) for character in value)


def strip_leading_translation_label(value: str) -> str:
    for label in sorted(LEADING_LABELS, key=len, reverse=True):
        folded_label = folded(label)
        for start in range(len(value) + 1):
            if folded(value[start : start + len(label)]) != folded_label:
                continue
            if edge_trimmed(value[:start]):
                continue
            suffix = value[start + len(label) :]
            cursor = 0
            while cursor < len(suffix) and suffix[cursor].isspace():
                cursor += 1
            delimiter_start = cursor
            while cursor < len(suffix) and unicodedata.category(suffix[cursor]).startswith("P"):
                cursor += 1
            if cursor == delimiter_start:
                continue
            while cursor < len(suffix) and suffix[cursor].isspace():
                cursor += 1
            if cursor >= len(suffix):
                continue
            payload = suffix[cursor:].strip()
            if payload:
                return payload
    return value


def normalize_translation_lines(value: str) -> str:
    label_markers = (
        "以下是翻译",
        "翻译如下",
        "翻译是：",
        "这是翻译",
        *LEADING_LABELS,
    )
    lines = [line.strip() for line in value.splitlines() if line.strip()]
    kept: list[str] = []
    for line in lines:
        folded_line = folded(line)
        label_only = any(
            not edge_trimmed(folded_line[: folded_line.find(folded(marker))])
            and not edge_trimmed(
                folded_line[folded_line.find(folded(marker)) + len(folded(marker)) :]
            )
            for marker in label_markers
            if folded(marker) in folded_line
        )
        if label_only:
            continue
        kept.append(line)
    return "\n".join(kept)


class TranslationLeadingLabelBoundaryContractTests(unittest.TestCase):
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
            "private func cleanTranslationOutput(\n",
        )
        cls.helper = function_body(
            cls.gemma,
            "private func stripLeadingTranslationLabel(from value: String)",
        )

    def test_explicit_same_line_labels_are_removed_without_losing_payload(self) -> None:
        cases = {
            "译文：你好。": "你好。",
            "译文如下 ：\n你好。\n第二句。": "你好。\n第二句。",
            "翻译结果：这是正文。": "这是正文。",
            "Translation: hello.": "hello.",
            "ＴＲＡＮＳＬＡＴＩＯＮ：你好。": "你好。",
            "「译文」：你好。": "你好。",
        }
        for raw, expected in cases.items():
            with self.subTest(raw=raw):
                self.assertEqual(strip_leading_translation_label(raw), expected)

    def test_label_requires_a_delimiter_and_payload(self) -> None:
        for value in (
            "译文你好",
            "Translation is part of the story.",
            "Translation",
            "译文：",
        ):
            with self.subTest(value=value):
                self.assertEqual(strip_leading_translation_label(value), value)

    def test_embedded_label_like_content_and_existing_ambiguous_label_are_preserved(self) -> None:
        accepted = (
            "故事里有译文：但这不是元数据。",
            "The Translation: marker is part of the dialogue.",
            "翻译是：你好。",
        )
        for value in accepted:
            with self.subTest(value=value):
                self.assertEqual(strip_leading_translation_label(value), value)

    def test_standalone_new_labels_are_removed_by_the_line_boundary(self) -> None:
        self.assertEqual(
            normalize_translation_lines("译文：\n你好。\nTranslation\n第二句。"),
            "你好。\n第二句。",
        )

    def test_product_calls_the_helper_before_line_cleanup_and_validation(self) -> None:
        self.assertIn("text = stripLeadingTranslationLabel(from: text)", self.cleaner)
        self.assertLess(
            self.cleaner.index("text = stripLeadingTranslationLabel(from: text)"),
            self.cleaner.index("var lines ="),
        )
        self.assertIn("return try validateTranslationOutput(", self.cleaner)
        for marker in (
            "let labels = [",
            '"翻译结果如下"',
            '"译文如下"',
            '"Here are the translations"',
            '"Here is the translation"',
            '"Translations"',
            '"Translation"',
            '"翻译结果"',
            '"译文"',
            "labels.sorted(by: { $0.count > $1.count })",
            "trimmingCharacters(in: whitespace.union(punctuation))",
            "guard cursor != delimiterStart else { continue }",
            "guard !payload.isEmpty else { continue }",
            "return payload",
        ):
            self.assertIn(marker, self.helper)

    def test_tagged_batch_path_remains_a_separate_strict_boundary(self) -> None:
        manga_cleaner = function_body(
            self.gemma,
            "private func cleanMangaBlockOutput(\n",
        )
        self.assertNotIn("stripLeadingTranslationLabel(from: text)", manga_cleaner)
        self.assertIn("text = stripLeadingMangaBatchPreamble(from: text)", manga_cleaner)
        parser = function_body(
            self.store,
            "private static func parseMangaTaggedTranslations(\n",
        )
        for marker in (
            "let expectedIndexByID = Dictionary(",
            "guard !matches.isEmpty else",
            "guard recognizedCount > 0 else",
            "throw ImageMangaBatchTranslationError.missingTags",
        ):
            self.assertIn(marker, parser)
        self.assertIn("TranslationBatchQualityEvaluator.evaluate(", self.store)

    def test_existing_quality_and_safety_gates_remain_after_cleanup(self) -> None:
        for marker in (
            "TranslationOutputPolicy.isPlaceholderResponse",
            "targetLanguageDensity",
            "confirmedTermMismatch",
            "numberMismatch",
            "previousContextLeakage",
            "translateJapaneseImageBlockWithQA(",
            "try Task.checkCancellation()",
            "persist()",
        ):
            self.assertIn(marker, self.context + self.store)
        self.assertIn("translationProfile: .mangaBlocks", self.store)
        self.assertNotIn("test/3.png", self.gemma + self.context)

    def test_version_workflow_docs_and_missing_fixture_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.390", "3.390"],
        )
        previous = "python3 -B scripts/test-v3377-translation-batch-inline-preamble-contract.py"
        current = "python3 -B scripts/test-v3378-translation-leading-label-boundary-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        combined = self.workflow + self.docs
        for marker in (current, "v3.389", "japanese-benchmark-v3.389-"):
            self.assertIn(marker, combined)
        self.assertFalse((ROOT / "test/3.png").exists())

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3378-translation-leading-label-boundary-contract.py")
        for source in (self.gemma, self.store, self.context, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("xcode" + "build", source)
            self.assertNotIn("reference/" + "koharu-main", source)
            self.assertNotIn("KOHARU_" + "DATA_ROOT", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
