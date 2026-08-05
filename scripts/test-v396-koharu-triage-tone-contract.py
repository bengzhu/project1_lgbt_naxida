#!/usr/bin/env python3
"""Contract for truthful readiness tone in the report-only Koharu triage summary."""

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


class KoharuTriageToneContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_readiness_blocker_wins_over_report_success_tone(self) -> None:
        body = braced_body(self.view, "private struct MangaProbeDiagnosticTriageSummary: View")
        tone_body = braced_body(body, "private var statusTone: AppStatusTone")
        self.assertIn("if artifactBlocked { return .warning }", tone_body)
        self.assertIn("if report.overallPassed { return .success }", tone_body)
        self.assertLess(
            tone_body.index("if artifactBlocked"),
            tone_body.index("if report.overallPassed"),
        )
        self.assertIn("private var artifactBlocked: Bool", body)
        self.assertIn('return "等待真实 Koharu 工件"', body)

    def test_tone_fix_remains_view_only_and_report_only(self) -> None:
        body = braced_body(self.view, "private struct MangaProbeDiagnosticTriageSummary: View")
        self.assertIn("let report: MangaOverlayProbeReport", body)
        self.assertIn("不会修改普通图片 OCR、翻译 prompt、模型或覆盖图", body)
        self.assertNotIn("@State", body)
        self.assertNotIn("runMangaOverlayProbe", body)
        self.assertNotIn("TranslationSessionStore", body)

    def test_version_and_ci_route(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 96) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.95;", self.project)
        route = "scripts/test-v396-koharu-triage-tone-contract.py"
        self.assertIn(route, self.workflow)
        self.assertIn(f"python3 -B {route}", self.workflow)
        previous = "python3 -B scripts/test-v395-manga-probe-empty-state-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(f"python3 -B {route}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
