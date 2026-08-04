#!/usr/bin/env python3
"""Contract for preserving explicit newlines in manga overlay text fitting."""

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


class MangaRenderNewlineContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOverlayProbeService.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_wrapping_accounts_for_explicit_newlines_before_width_wrapping(self) -> None:
        wrapped = braced_body(self.service, "private static func wrappedLines(")
        self.assertIn("text.components(separatedBy: .newlines)", wrapped)
        self.assertIn("for paragraph in", wrapped)
        self.assertIn("for character in paragraph", wrapped)
        self.assertIn('lines.append("")', wrapped)
        self.assertNotIn("for character in text", wrapped)

    def test_fit_plan_and_diagnostic_draw_share_the_newline_aware_helper(self) -> None:
        fit = braced_body(self.service, "private static func makeRenderTextPlan(")
        collision = braced_body(
            self.service,
            "private static func drawCollisionCheckedText(",
        )
        fitting = braced_body(self.service, "private static func drawFittingText(")
        self.assertIn("wrappedLines(cleanText, fontSize: maxFontSize, maxWidth: rect.width)", fit)
        self.assertIn("wrappedLines(cleanText, fontSize: fontSize, maxWidth: rect.width)", fit)
        self.assertIn("makeRenderTextPlan(cleanText, in: rect", collision)
        self.assertIn("wrappedLines(cleanText, fontSize: fontSize, maxWidth: rect.width)", fitting)
        self.assertNotIn("groundTruth", wrapped := braced_body(self.service, "private static func wrappedLines("))
        self.assertNotIn("TranslationSessionStore", wrapped)

    def test_failure_overlay_fallback_remains_visible_and_reported(self) -> None:
        self.assertIn('let overlayText = passed ? translationCandidate : "翻译失败\\n\\(block.finalTextUsedForTranslation)"', self.store)
        self.assertIn("failureOverlayRequired", self.store)
        self.assertIn("failureOverlayLocked", self.store)
        self.assertIn("G-render-failure-overlay-contract", self.store)

    def test_version_and_koharu_route_follow_v381(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.82;", self.project)
        self.assertNotIn("MARKETING_VERSION = 3.81;", self.project)
        new = "python3 -B scripts/test-v382-manga-render-newline-contract.py"
        self.assertIn(new, self.workflow)
        self.assertIn(
            "scripts/test-v38(2-manga-render-newline|3-koharu-fit-budget)-contract\\.py",
            self.workflow,
        )
        old = "python3 -B scripts/test-v33-koharu-mask-topology-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
