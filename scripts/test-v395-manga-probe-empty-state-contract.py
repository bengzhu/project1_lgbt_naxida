#!/usr/bin/env python3
"""Contract for explaining a manga probe report that has no OCR blocks."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def braced_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unterminated body: {signature}")


class MangaProbeEmptyStateContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_empty_report_has_explicit_no_blocks_context_and_hides_filter(self) -> None:
        body = braced_body(self.view, "private struct MangaProbeSection: View")
        self.assertIn("if store.mangaOverlayProbeBlocks.isEmpty", body)
        self.assertIn('title: "未生成逐块诊断"', body)
        self.assertIn("emptyProbeBlocksDetail", body)
        self.assertIn('title: "本次探针未生成文字块"', body)
        self.assertIn('title: "当前诊断筛选没有结果"', body)
        self.assertIn("else if store.mangaOverlayProbeReport != nil, filteredProbeBlocks.isEmpty", body)
        self.assertLess(body.index('title: "本次探针未生成文字块"'), body.index('title: "当前诊断筛选没有结果"'))

    def test_empty_state_explains_retry_scope_to_voiceover(self) -> None:
        body = braced_body(self.view, "private struct MangaProbeSection: View")
        self.assertIn('accessibilityLabel("漫画探针未生成逐块诊断")', body)
        self.assertIn("确认 test/1.png 与 Output 状态后重试", body)
        self.assertIn("private var emptyProbeBlocksDetail", body)
        self.assertIn("Output 清理状态后重试", body)

    def test_version_and_ci_route(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 95) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.94;", self.project)
        self.assertIn("scripts/test-v395-manga-probe-empty-state-contract.py", self.workflow)
        self.assertIn("python3 -B scripts/test-v395-manga-probe-empty-state-contract.py", self.workflow)
        self.assertLess(
            self.workflow.index("python3 -B scripts/test-v394-manga-probe-failure-cleanup-contract.py"),
            self.workflow.index("python3 -B scripts/test-v395-manga-probe-empty-state-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
