#!/usr/bin/env python3
"""Static and pure-policy contract for v3.380 translation metadata content boundaries."""

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
    "English ->",
    "只输出中文译文",
    "只输出译文",
    "不要输出英文原文",
    "简体中文翻译",
    "预设提示词",
    "输出风格",
)

CONTENT_SENSITIVE_LINE_LEAK_MARKERS = (
    "translation engine",
    "输出风格",
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


def prompt_metadata_line(line: str, marker: str) -> bool:
    if not marker_at_line_start(line, marker):
        return False
    if not any(folded(marker) == folded(candidate) for candidate in CONTENT_SENSITIVE_LINE_LEAK_MARKERS):
        return True
    normalized_line = folded(line)
    normalized_marker = folded(marker)
    offset = normalized_line.find(normalized_marker)
    suffix = normalized_line[offset + len(normalized_marker) :].strip()
    if not suffix:
        return True
    return unicodedata.category(suffix[0]).startswith("P")


def normalize_translation_lines(output: str) -> str:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    kept: list[str] = []
    for line in lines:
        bullet_body = line[2:].strip() if line.startswith("- ") else line
        metadata_bullet = line.startswith("- ") and (
            not bullet_body
            or any(prompt_metadata_line(bullet_body, marker) for marker in LINE_LEAK_MARKERS)
        )
        if metadata_bullet or (line.startswith("|") and line.endswith("|")):
            continue
        if any(prompt_metadata_line(line, marker) for marker in LINE_LEAK_MARKERS):
            continue
        kept.append(line)
    return "\n".join(kept)


class TranslationMetadataContentBoundaryContractTests(unittest.TestCase):
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

    def test_content_sensitive_markers_keep_natural_leading_prose(self) -> None:
        self.assertEqual(
            normalize_translation_lines(
                "Translation engine is part of the story.\n第二句。"
            ),
            "Translation engine is part of the story.\n第二句。",
        )
        self.assertEqual(
            normalize_translation_lines("输出风格很自然，角色没有解释。"),
            "输出风格很自然，角色没有解释。",
        )

    def test_content_sensitive_markers_still_remove_explicit_metadata_shapes(self) -> None:
        self.assertEqual(
            normalize_translation_lines(
                "translation engine\n你好。\n输出风格：简洁\n第二句。"
            ),
            "你好。\n第二句。",
        )
        self.assertEqual(
            normalize_translation_lines(
                "- translation engine:\n你好。\n- 输出风格\n第二句。"
            ),
            "你好。\n第二句。",
        )

    def test_explicit_instruction_markers_keep_existing_removal(self) -> None:
        self.assertEqual(
            normalize_translation_lines(
                "do not summarize this output\n你好。\n只输出译文：\n第二句。"
            ),
            "你好。\n第二句。",
        )
        self.assertEqual(
            normalize_translation_lines(
                "English -> 简体中文\n你好。\n| prompt | value |"
            ),
            "你好。",
        )

    def test_embedded_markers_and_table_boundary_remain_content_safe(self) -> None:
        self.assertEqual(
            normalize_translation_lines(
                "关于 translation engine 的说法。\n她讨论了输出风格，但没有解释。"
            ),
            "关于 translation engine 的说法。\n她讨论了输出风格，但没有解释。",
        )
        self.assertEqual(
            normalize_translation_lines("| 这是一句带竖线的译文 |"),
            "",
        )

    def test_product_uses_content_sensitive_metadata_helper(self) -> None:
        cleaner = function_body(
            self.gemma,
            "private func cleanTranslationOutput(\n",
        )
        for marker in (
            "let contentSensitiveLineLeakMarkers = [",
            '"translation engine"',
            '"输出风格"',
            "func isPromptMetadataLine(_ line: String, marker: String) -> Bool",
            "contentSensitiveLineLeakMarkers.contains(where:",
            "CharacterSet.punctuationCharacters.contains(firstScalar)",
            "isPromptMetadataLine(bulletBody, marker: marker)",
            "isPromptMetadataLine(trimmed, marker: marker)",
        ):
            self.assertIn(marker, cleaner)
        self.assertNotIn("trimmed.localizedCaseInsensitiveContains($0)", cleaner)
        self.assertNotIn("bulletBody.localizedCaseInsensitiveContains($0)", cleaner)

    def test_existing_validation_qa_and_pipeline_boundaries_remain(self) -> None:
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
            "recognizeTextBlocks(",
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
            ["3.380", "3.380"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3376-translation-metadata-content-boundary-contract.py",
            "v3.380",
            "japanese-benchmark-v3.380-",
        ):
            self.assertIn(marker, combined)

    def test_contract_and_product_sources_have_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3376-translation-metadata-content-boundary-contract.py"
        )
        for source in (self.gemma, self.context, self.store, contract):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
