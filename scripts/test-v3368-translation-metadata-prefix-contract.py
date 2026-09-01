#!/usr/bin/env python3
"""Static and pure-policy contract for v3.388 translation metadata filtering."""

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


LINE_LEAK_MARKERS = (
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

LABEL_MARKERS = (
    "以下是翻译",
    "翻译如下",
    "翻译是：",
    "这是翻译",
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


def marker_at_line_start(line: str, marker: str) -> bool:
    normalized_line = folded(line)
    normalized_marker = folded(marker)
    offset = normalized_line.find(normalized_marker)
    return offset >= 0 and not trim_edge_punctuation(normalized_line[:offset])


def normalize_translation_lines(output: str) -> str:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    kept: list[str] = []

    for line in lines:
        bullet_body = line[2:].strip() if line.startswith("- ") else line
        metadata_bullet = line.startswith("- ") and (
            not bullet_body
            or any(marker_at_line_start(bullet_body, marker) for marker in LINE_LEAK_MARKERS)
        )
        label_only = False
        folded_line = folded(line)
        for marker in LABEL_MARKERS:
            folded_marker = folded(marker)
            offset = folded_line.find(folded_marker)
            if offset < 0:
                continue
            before = trim_edge_punctuation(folded_line[:offset])
            after = trim_edge_punctuation(folded_line[offset + len(folded_marker) :])
            if not before and not after:
                label_only = True
                break
        if metadata_bullet or (line.startswith("|") and line.endswith("|")):
            continue
        if any(marker_at_line_start(line, marker) for marker in LINE_LEAK_MARKERS):
            continue
        if label_only:
            continue
        kept.append(line)
    return "\n".join(kept)


class TranslationMetadataPrefixContractTests(unittest.TestCase):
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

    def test_filter_is_line_start_scoped(self) -> None:
        body = function_body(
            self.gemma,
            "private func cleanTranslationOutput(\n",
        )
        for marker in (
            "func isPromptMarkerAtLineStart(_ line: String, marker: String)",
            "isPromptMetadataLine(bulletBody, marker: marker)",
            "isPromptMetadataLine(trimmed, marker: marker)",
            'let candidate = lines.joined(separator: "\\n")',
        ):
            self.assertIn(marker, body)
        self.assertNotIn("trimmed.localizedCaseInsensitiveContains($0)", body)
        self.assertNotIn("bulletBody.localizedCaseInsensitiveContains($0)", body)

    def test_embedded_prompt_words_remain_translation_content(self) -> None:
        self.assertEqual(
            normalize_translation_lines(
                "关于 translation engine 的说法。\n这个输出风格很自然。"
            ),
            "关于 translation engine 的说法。\n这个输出风格很自然。",
        )
        self.assertEqual(
            normalize_translation_lines("The translation engine is part of the story."),
            "The translation engine is part of the story.",
        )

    def test_explicit_line_start_metadata_still_disappears(self) -> None:
        self.assertEqual(
            normalize_translation_lines(
                "translation engine\n你好。\n【只输出译文】\n第二句。"
            ),
            "你好。\n第二句。",
        )
        self.assertEqual(
            normalize_translation_lines("- 只输出中文译文\n你好。\n| prompt |"),
            "你好。",
        )
        self.assertEqual(
            normalize_translation_lines("以下是翻译\n你好。\n翻译如下"),
            "你好。",
        )

    def test_marker_after_translation_content_is_not_a_cut_boundary(self) -> None:
        self.assertEqual(
            normalize_translation_lines("你好。 translation engine"),
            "你好。 translation engine",
        )
        self.assertEqual(
            normalize_translation_lines("她讨论了输出风格，但没有解释。"),
            "她讨论了输出风格，但没有解释。",
        )

    def test_existing_validation_and_product_boundaries_remain(self) -> None:
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
            ["3.388", "3.388"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3368-translation-metadata-prefix-contract.py",
            "v3.388",
            "japanese-benchmark-v3.388-",
        ):
            self.assertIn(marker, combined)

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3368-translation-metadata-prefix-contract.py"
        )
        for source in (self.gemma, self.context, self.store, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
