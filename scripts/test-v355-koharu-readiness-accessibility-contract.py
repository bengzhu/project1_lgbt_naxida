#!/usr/bin/env python3
"""Static contracts for v3.55 Koharu readiness operator accessibility feedback."""

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


class KoharuReadinessAccessibilityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.summary = braced_body(
            self.view,
            "private struct MangaKoharuArtifactReadinessSummary: View",
        )

    def test_readiness_status_is_one_stable_accessibility_context(self) -> None:
        for marker in [
            "AppStatusRow(title: statusTitle, detail: statusDetail, tone: statusTone)",
            ".accessibilityElement(children: .ignore)",
            '.accessibilityLabel("Koharu 工件就绪状态")',
            ".accessibilityValue(readinessAccessibilityValue)",
            ".accessibilityHint(readinessAccessibilityHint)",
        ]:
            self.assertIn(marker, self.summary)

    def test_missing_artifact_guidance_is_actionable_and_report_only(self) -> None:
        for marker in [
            "test/koharu_artifacts/",
            "1.manifest.json",
            "1.textboxes.json",
            "1.bubbles.json",
            "1.segment_mask.json",
            "readinessAccessibilityHint",
            "shadowOnly=true",
            "mainFlowChanged=false",
            "不影响普通图片 OCR、翻译或覆盖图",
        ]:
            self.assertIn(marker, self.summary)

    def test_readiness_context_does_not_run_probe_or_mutate_store(self) -> None:
        self.assertNotIn("runMangaOverlayProbe", self.summary)
        self.assertNotIn("VisionOCRService", self.summary)
        self.assertNotIn("@EnvironmentObject", self.summary)
        self.assertNotIn("MangaKoharuArtifactReadinessSummary", self.store)
        self.assertNotIn("koharuReadinessSummary", self.store)

    def test_version_and_ci_route_follow_v354(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.54;", self.project)
        old = "python3 -B scripts/test-v354-image-status-value-contract.py"
        new = "python3 -B scripts/test-v355-koharu-readiness-accessibility-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
