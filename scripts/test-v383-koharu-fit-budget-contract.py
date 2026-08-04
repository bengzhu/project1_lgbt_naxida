#!/usr/bin/env python3
"""Contract for keeping Koharu fit diagnostics aligned with the render plan."""

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
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class KoharuFitBudgetContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOverlayProbeService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.report = braced_body(
            self.service,
            "func makeKoharuRenderSpriteFitPlannerReport(",
        )
        self.budget = braced_body(self.report, "func estimateTextBudget(")

    def test_budget_reuses_render_newline_aware_wrapping(self) -> None:
        self.assertIn(
            "Self.wrappedLines(\n                    text,\n                    fontSize: CGFloat(font),\n                    maxWidth: CGFloat(width)",
            self.budget,
        )
        self.assertIn("let lineCount = max(1, lines.count)", self.budget)
        self.assertIn("let charsPerLine = max(1, lines.map(\\.count).max() ?? 1)", self.budget)
        self.assertNotIn(
            "Int(ceil(Double(max(text.count, 1)) / Double(charsPerLine)))",
            self.budget,
        )
        self.assertNotIn("groundTruth", self.budget)

    def test_actual_truncation_marks_failure_fallback_risk(self) -> None:
        self.assertIn(
            "let renderTextTruncated = block.renderTextTruncated || (renderLock?.renderTextTruncated ?? false)",
            self.report,
        )
        self.assertIn(
            "else if renderTextTruncated || budget.verdict == \"fontBudgetOverflowRisk\"",
            self.report,
        )
        self.assertIn("failureFallbackLongTextRisk", self.report)
        self.assertIn("renderTextTruncated: renderTextTruncated", self.report)
        self.assertIn("groundTruthUsedForDecision: false", self.report)

    def test_version_and_ci_route_follow_v382(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.83;"), 2)
        self.assertNotIn("MARKETING_VERSION = 3.82;", self.project)
        old = "python3 -B scripts/test-v382-manga-render-newline-contract.py"
        new = "python3 -B scripts/test-v383-koharu-fit-budget-contract.py"
        route = "scripts/test-v38(2-manga-render-newline|3-koharu-fit-budget)-contract\\.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
