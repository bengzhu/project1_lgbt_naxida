#!/usr/bin/env python3
"""Contract for v3.113 manga diagnostic expansion VoiceOver focus handoff."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def braced_body(source: str, marker: str) -> str:
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace:index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class MangaDiagnosticExpansionFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.row = braced_body(self.view, "private struct MangaProbeBlockRow: View")

    def test_expansion_focuses_detail_and_collapse_returns_to_result(self) -> None:
        for marker in [
            "@State private var isExpanded = false",
            "DisclosureGroup(isExpanded: $isExpanded)",
            "private var detailAccessibilityFocusID: String",
            '"manga-diagnostic-detail-\\(block.index)"',
            '.accessibilityLabel("漫画探针文字块 \\(block.index) 详细诊断")',
            '已展开 OCR、译文和诊断输出；收起后回到结果行',
            ".accessibilityFocused(accessibilityFocus, equals: detailAccessibilityFocusID)",
            ".onChange(of: isExpanded)",
            "focusExpandedDiagnosticDetail(expanded)",
            "private func focusExpandedDiagnosticDetail(_ expanded: Bool)",
        ]:
            self.assertIn(marker, self.row)
        legacy_handoff = all(
            marker in self.row
            for marker in [
                "await Task.yield()",
                "accessibilityFocus.wrappedValue = expanded",
                "? detailAccessibilityFocusID",
                ": accessibilityFocusID",
            ]
        )
        generation_handoff = all(
            marker in self.row
            for marker in [
                "let requestAccessibilityFocus: (String) -> Void",
                "requestAccessibilityFocus(",
                "? detailAccessibilityFocusID",
                ": accessibilityFocusID",
            ]
        )
        self.assertTrue(
            legacy_handoff or generation_handoff,
            "expansion focus must use the historical handoff or the shared generation requester",
        )

    def test_detail_keeps_report_context_and_view_only_boundary(self) -> None:
        self.assertIn(".accessibilityElement(children: .contain)", self.row)
        self.assertIn(".accessibilityValue(blockAccessibilityValue)", self.row)
        self.assertIn("let report: MangaOverlayProbeReport?", self.row)
        for forbidden in [
            "TranslationSessionStore",
            "runMangaOverlayProbe",
            "groundTruth",
            "probe_report.json",
        ]:
            self.assertNotIn(forbidden, self.row)
        for marker in [
            "mangaProbeOCRRiskBlockSet(report)",
            "mangaProbeTranslationRiskBlockSet(report)",
            "mangaProbeRenderRiskBlockSet(report)",
        ]:
            self.assertIn(marker, self.row)
        self.assertNotIn("detailAccessibilityFocusID", self.store)

    def test_version_and_ci_route_follow_v3112(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 113) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.112;", self.project)
        script = "scripts/test-v3113-manga-diagnostic-expansion-focus-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3112-image-translation-terminal-focus-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
