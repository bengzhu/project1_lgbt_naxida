#!/usr/bin/env python3
"""Contract for v3.118 prioritizing blocked Koharu readiness focus."""

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


class MangaKoharuReadinessFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.section = braced_body(self.view, "private struct MangaProbeSection: View")
        self.readiness = braced_body(
            self.view, "private struct MangaKoharuArtifactReadinessSummary: View"
        )

    def test_blocked_readiness_gets_a_stable_shared_focus_destination(self) -> None:
        for marker in [
            'diagnosticKoharuReadinessAccessibilityFocusID = "manga-diagnostic-koharu-readiness"',
            "accessibilityFocus: $diagnosticAccessibilityFocusID",
            "accessibilityFocusID: Self.diagnosticKoharuReadinessAccessibilityFocusID",
        ]:
            self.assertIn(marker, self.section)
        for marker in [
            "let accessibilityFocus: AccessibilityFocusState<String?>.Binding",
            "let accessibilityFocusID: String",
            '.accessibilityLabel("Koharu 工件就绪状态")',
            ".accessibilityFocused(accessibilityFocus, equals: accessibilityFocusID)",
        ]:
            self.assertIn(marker, self.readiness)

    def test_blocked_readiness_wins_over_block_or_empty_result_focus(self) -> None:
        handler = braced_body(self.section, "private func focusDiagnosticProbeResultIfNeeded()")
        readiness_index = handler.index("diagnosticReadinessIsBlocking(readiness)")
        blocks_index = handler.index("store.mangaOverlayProbeBlocks.isEmpty")
        self.assertLess(readiness_index, blocks_index)
        helper = braced_body(self.section, "private func diagnosticReadinessIsBlocking(")
        for action in [
            '"stopUntilArtifactsProvided"',
            '"stopUntilArtifactContractFixed"',
            '"stopUntilRealDetectorSourceDeclared"',
        ]:
            self.assertIn(action, helper)
        self.assertIn("default:\n            false", helper)

    def test_focus_is_view_only_and_report_only(self) -> None:
        self.assertNotIn("diagnosticKoharuReadinessAccessibilityFocusID", self.store)
        self.assertNotIn("diagnosticReadinessIsBlocking", self.store)
        for forbidden in [
            "runMangaOverlayProbe()",
            "groundTruth",
            "probe_report.json",
            "test/koharu_artifacts",
        ]:
            self.assertNotIn(forbidden, self.section)

    def test_version_and_ci_route_follow_v3117(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 118) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.117;", self.project)
        script = "scripts/test-v3118-manga-koharu-readiness-focus-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3117-manga-diagnostic-filter-expansion-reset-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
