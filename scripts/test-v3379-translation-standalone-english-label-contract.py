#!/usr/bin/env python3
"""Static and pure-policy contract for v3.382 standalone English labels."""

from __future__ import annotations

import re
from pathlib import Path
import unicodedata
import unittest


ROOT = Path(__file__).resolve().parents[1]

STANDALONE_LABELS = (
    "Here are the translations",
    "Here is the translation",
    "Translations",
    "Translation",
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


def is_label_only(line: str) -> bool:
    folded_line = folded(line.strip())
    for marker in STANDALONE_LABELS:
        marker_folded = folded(marker)
        start = folded_line.find(marker_folded)
        if start < 0:
            continue
        before = folded_line[:start]
        after = folded_line[start + len(marker_folded) :]
        if not edge_trimmed(before) and not edge_trimmed(after):
            return True
    return False


def normalize_translation_lines(value: str) -> str:
    return "\n".join(
        line
        for raw_line in value.splitlines()
        if (line := raw_line.strip()) and not is_label_only(line)
    )


class TranslationStandaloneEnglishLabelContractTests(unittest.TestCase):
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
                "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md",
                "update_log.md",
            )
        )
        cls.cleaner = function_body(
            cls.gemma,
            "private func cleanTranslationOutput(\n",
        )

    def test_exact_standalone_english_labels_are_removed(self) -> None:
        self.assertEqual(
            normalize_translation_lines(
                "Here is the translation\n你好。\n第二句。"
            ),
            "你好。\n第二句。",
        )
        self.assertEqual(
            normalize_translation_lines(
                "【Here are the translations:】\n你好。"
            ),
            "你好。",
        )
        self.assertEqual(
            normalize_translation_lines("Translation\nhello."),
            "hello.",
        )

    def test_content_after_a_label_is_not_dropped(self) -> None:
        for value in (
            "Here is the translation of the sign.",
            "Here are the translations for the next panel.",
            "The narrator says: Here is the translation.",
            "Translation matters in this scene.",
        ):
            with self.subTest(value=value):
                self.assertEqual(normalize_translation_lines(value), value)

    def test_empty_or_punctuation_only_label_lines_are_removed(self) -> None:
        for value in (
            "Here is the translation:",
            "Here are the translations...",
            "[Translation]",
        ):
            with self.subTest(value=value):
                self.assertEqual(normalize_translation_lines(value), "")

    def test_product_uses_exact_line_boundary_after_leading_label_recovery(self) -> None:
        self.assertIn("text = stripLeadingTranslationLabel(from: text)", self.cleaner)
        self.assertLess(
            self.cleaner.index("text = stripLeadingTranslationLabel(from: text)"),
            self.cleaner.index("var lines ="),
        )
        for marker in (
            '"Here are the translations"',
            '"Here is the translation"',
            "let isTranslationLabelOnly = translationLabelMarkers.contains",
            "lines.removeAll { line in",
            "return isMetadataBullet",
            "return try validateTranslationOutput(",
        ):
            self.assertIn(marker, self.cleaner)

    def test_tagged_batch_and_shared_qa_boundaries_remain_separate(self) -> None:
        manga_cleaner = function_body(
            self.gemma,
            "private func cleanMangaBlockOutput(\n",
        )
        self.assertNotIn("isTranslationLabelOnly", manga_cleaner)
        self.assertIn("text = stripLeadingMangaBatchPreamble(from: text)", manga_cleaner)
        for marker in (
            "TranslationBatchQualityEvaluator.evaluate(",
            "TranslationOutputPolicy.isPlaceholderResponse",
            "targetLanguageDensity",
            "numberMismatch",
            "confirmedTermMismatch",
            "previousContextLeakage",
        ):
            self.assertIn(marker, self.context + self.store)

    def test_version_workflow_docs_and_missing_fixture_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.382", "3.382"],
        )
        previous = "python3 -B scripts/test-v3378-translation-leading-label-boundary-contract.py"
        current = "python3 -B scripts/test-v3379-translation-standalone-english-label-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        combined = self.workflow + self.docs
        for marker in (current, "v3.382", "japanese-benchmark-v3.382-"):
            self.assertIn(marker, combined)
        self.assertFalse((ROOT / "test/3.png").exists())

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read("scripts/test-v3379-translation-standalone-english-label-contract.py")
        for source in (self.gemma, self.store, self.context, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("xcode" + "build", source)
            self.assertNotIn("reference/" + "koharu-main", source)
            self.assertNotIn("KOHARU_" + "DATA_ROOT", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
