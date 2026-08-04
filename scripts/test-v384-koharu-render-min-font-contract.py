#!/usr/bin/env python3
"""Contract for preserving minimum-font evidence in the Koharu fit ledger."""

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


class KoharuRenderMinFontContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.model = read("AITRANS/Models/TranscriptModels.swift")
        self.service = read("AITRANS/Services/MangaOverlayProbeService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.report = braced_body(
            self.service,
            "func makeKoharuRenderSpriteFitPlannerReport(",
        )

    def test_block_ledger_carries_existing_minimum_font_evidence(self) -> None:
        ledger = braced_body(
            self.model,
            "struct MangaKoharuRenderSpriteFitBlockLedger",
        )
        self.assertIn("var renderMinFontSizeReached: Bool", ledger)
        self.assertIn(
            "let renderMinFontSizeReached = block.renderMinFontSizeReached || (renderLock?.renderMinFontSizeReached ?? false)",
            self.report,
        )
        self.assertIn(
            "renderMinFontSizeReached: renderMinFontSizeReached",
            self.report,
        )
        self.assertIn(
            'signal("renderMinFontSizeReached", String(renderMinFontSizeReached)',
            self.report,
        )

    def test_summary_and_gate_expose_minimum_font_blocks_without_promotion(self) -> None:
        planner = braced_body(
            self.model,
            "struct MangaKoharuRenderSpriteFitPlannerReport",
        )
        self.assertIn("var renderMinFontSizeReachedBlocks: [Int]", planner)
        self.assertIn(
            "let renderMinFontSizeReachedBlocks = uniqueSorted(blockLedgers.filter(\\.renderMinFontSizeReached).map(\\.blockIndex))",
            self.report,
        )
        self.assertIn('G-render-sprite-fit-min-font-evidence', self.report)
        self.assertIn(
            "renderMinFontSizeReachedBlocks: renderMinFontSizeReachedBlocks",
            self.report,
        )
        self.assertIn("wouldChangeMainFlow: false", self.report)
        self.assertIn("diagnosticOnly: true", self.report)

    def test_version_and_ci_route_follow_v383(self) -> None:
        import re

        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 84) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.83;", self.project)
        old = "python3 -B scripts/test-v383-koharu-fit-budget-contract.py"
        new = "python3 -B scripts/test-v384-koharu-render-min-font-contract.py"
        route = "scripts/test-v38(2-manga-render-newline|3-koharu-fit-budget|4-koharu-render-min-font|5-koharu-render-lock-min-font|6-koharu-render-output-ledger|7-koharu-render-output-action)-contract\\.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
