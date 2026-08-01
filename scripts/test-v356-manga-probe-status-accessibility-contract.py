#!/usr/bin/env python3
"""Static contracts for v3.56 manga probe operator accessibility feedback."""

from pathlib import Path
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


class MangaProbeStatusAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.section = braced_body(self.view, "private struct MangaProbeSection: View")

    def test_probe_status_is_one_stable_accessibility_context(self) -> None:
        for marker in [
            "AppStatusRow(title: probeStatusTitle, detail: store.mangaOverlayProbeMessage, tone: probeTone)",
            ".accessibilityElement(children: .ignore)",
            '.accessibilityLabel("漫画覆盖翻译探针状态")',
            ".accessibilityValue(probeStatusAccessibilityValue)",
            ".accessibilityHint(probeStatusAccessibilityHint)",
        ]:
            self.assertIn(marker, self.section)

    def test_probe_status_and_action_explain_scope_and_failure_boundaries(self) -> None:
        for marker in [
            "probeStatusAccessibilityValue",
            'return "\\(probeStatusTitle)：\\(detail)"',
            "case .idle:",
            "case .loading:",
            "case .recognizing:",
            "case .translating:",
            "case .rendering:",
            "case .completed:",
            "case .failed:",
            "test/1.png",
            "Output",
            "失败 block 仍会保留",
            "不会改变普通图片 OCR、翻译或覆盖图",
            ".accessibilityHint(mangaProbeActionAccessibilityHint)",
        ]:
            self.assertIn(marker, self.section)

    def test_probe_status_context_does_not_change_store_or_run_a_second_probe(self) -> None:
        self.assertNotIn("VisionOCRService", self.section)
        self.assertEqual(self.section.count("store.runMangaOverlayProbe"), 1)

    def test_version_and_ci_route_follow_v355(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.55;", self.project)
        old = "python3 -B scripts/test-v355-koharu-readiness-accessibility-contract.py"
        new = "python3 -B scripts/test-v356-manga-probe-status-accessibility-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
