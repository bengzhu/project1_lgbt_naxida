#!/usr/bin/env python3
"""Contract for v3.114 manga diagnostic expansion state isolation."""

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


class MangaDiagnosticExpansionStateContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.section = braced_body(self.view, "private struct MangaProbeSection: View")
        self.row = braced_body(self.view, "private struct MangaProbeBlockRow: View")

    def test_new_probe_resets_stale_expansion_without_stealing_focus(self) -> None:
        for marker in [
            "@State private var diagnosticExpansionResetID = 0",
            "diagnosticExpansionResetID += 1",
            "expansionResetID: diagnosticExpansionResetID",
            "let expansionResetID: Int",
            "@State private var suppressNextExpansionFocusHandoff = false",
            ".onChange(of: expansionResetID)",
            "guard isExpanded else { return }",
            "suppressNextExpansionFocusHandoff = true",
            "isExpanded = false",
        ]:
            self.assertIn(marker, self.section + self.row)
        loading = braced_body(self.section, ".onChange(of: store.mangaOverlayProbeState)")
        self.assertIn("guard state == .loading else { return }", loading)
        self.assertIn("diagnosticFilter = .all", loading)
        self.assertIn("diagnosticAccessibilityFocusID = nil", loading)

    def test_row_voiceover_explains_expansion_state(self) -> None:
        for marker in [
            'parts.append(isExpanded ? "详细诊断已展开" : "详细诊断已收起")',
            "let expansionHint = isExpanded",
            "收起详细诊断并回到文字块结果行",
            "展开查看 OCR 原文、译文和诊断输出",
            "guard !suppressNextExpansionFocusHandoff else",
            "suppressNextExpansionFocusHandoff = false",
            ".accessibilityValue(blockAccessibilityValue)",
            ".accessibilityFocused(accessibilityFocus, equals: detailAccessibilityFocusID)",
        ]:
            self.assertIn(marker, self.row)

    def test_expansion_state_is_view_only_report_context(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "runMangaOverlayProbe",
            "groundTruth",
            "probe_report.json",
        ]:
            self.assertNotIn(forbidden, self.row)
        self.assertNotIn("diagnosticExpansionResetID", self.store)
        for marker in [
            "mangaProbeOCRRiskBlockSet(report)",
            "mangaProbeTranslationRiskBlockSet(report)",
            "mangaProbeRenderRiskBlockSet(report)",
            "reportAction",
            "blockAccessibilityValue",
        ]:
            self.assertIn(marker, self.row)

    def test_version_and_ci_route_follow_v3113(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 114) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.113;", self.project)
        script = "scripts/test-v3114-manga-diagnostic-expansion-state-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3113-manga-diagnostic-expansion-focus-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
