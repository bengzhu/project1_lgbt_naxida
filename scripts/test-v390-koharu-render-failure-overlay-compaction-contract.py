#!/usr/bin/env python3
"""Contract for preserving complete OCR text in compact failure overlays."""

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
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class KoharuFailureOverlayCompactionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOverlayProbeService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_compaction_keeps_failure_marker_and_all_ocr_content(self) -> None:
        helper = braced_body(self.service, "private static func failureOverlayDisplayText(")
        self.assertIn('cleanText.hasPrefix("翻译失败\\n")', helper)
        self.assertIn("components(separatedBy: .newlines)", helper)
        self.assertIn('.joined(separator: " ")', helper)
        self.assertIn('return compactOCR.isEmpty ? marker : "\\(marker)\\n\\(compactOCR)"', helper)
        self.assertIn("does not alter the", self.service)
        self.assertIn("OCR text stored in the block", self.service)

    def test_fit_plan_and_draw_share_compacted_failure_text(self) -> None:
        diagnostics = braced_body(
            self.service,
            "func applySafeLayoutAndRenderingDiagnostics(",
        )
        draw = braced_body(self.service, "private static func drawCollisionCheckedText(")
        fit = braced_body(self.service, "func makeKoharuRenderSpriteFitPlannerReport(")
        self.assertIn("let text = Self.failureOverlayDisplayText(block.translatedText)", diagnostics)
        self.assertIn("let cleanText = failureOverlayDisplayText(text)", draw)
        self.assertIn("makeRenderTextPlan(cleanText, in: rect, minFontSize: minimumOverlayFontSize)", draw)
        self.assertIn("Self.failureOverlayDisplayText(fallback)", fit)
        self.assertIn(
            'Self.failureOverlayDisplayText("翻译失败\\n\\(block.finalTextUsedForTranslation)")',
            fit,
        )
        self.assertIn("drawCollisionCheckedText(", self.service)

    def test_version_and_ci_route_follow_v389(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 90) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.89;", self.project)
        old = "python3 -B scripts/test-v389-koharu-render-output-summary-action-contract.py"
        new = "python3 -B scripts/test-v390-koharu-render-failure-overlay-compaction-contract.py"
        route = "scripts/test-v(38(2-manga-render-newline|3-koharu-fit-budget|4-koharu-render-min-font|5-koharu-render-lock-min-font|6-koharu-render-output-ledger|7-koharu-render-output-action|8-koharu-render-core-output-gate-action|9-koharu-render-output-summary-action)|390-koharu-render-failure-overlay-compaction)-contract\\.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
