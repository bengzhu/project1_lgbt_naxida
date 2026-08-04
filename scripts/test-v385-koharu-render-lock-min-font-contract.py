#!/usr/bin/env python3
"""Contract for surfacing minimum-font pressure in the render-lock summary."""

from pathlib import Path
import unittest
import re


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


class KoharuRenderLockMinFontContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.model = read("AITRANS/Models/TranscriptModels.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.probe = read("AITRANS/Services/MangaOverlayProbeService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.report = braced_body(
            self.store,
            "private static func makeKoharuRenderRegressionLockReport(",
        )

    def test_render_lock_summary_carries_existing_minimum_font_evidence(self) -> None:
        report_model = braced_body(
            self.model,
            "struct MangaKoharuRenderRegressionLockReport",
        )
        self.assertIn("var renderMinFontSizeReachedBlocks: [Int]", report_model)
        self.assertIn(
            "let renderMinFontSizeReachedBlocks = uniqueSorted(blockLocks.filter(\\.renderMinFontSizeReached).map(\\.blockIndex))",
            self.report,
        )
        self.assertIn(
            "renderMinFontSizeReachedBlocks: renderMinFontSizeReachedBlocks",
            self.report,
        )
        self.assertIn(
            'signal("renderMinFontSizeReached", String(block.renderMinFontSizeReached)',
            self.report,
        )

    def test_render_lock_gate_and_developer_summary_remain_report_only(self) -> None:
        self.assertIn('G-render-min-font-evidence', self.report)
        self.assertIn('restoreRenderMinFontEvidence', self.report)
        self.assertIn("wouldChangeMainFlow: false", self.report)
        self.assertIn("diagnosticOnly: true", self.report)
        self.assertIn("renderMinFontSizeReachedBlocks", self.probe)
        self.assertIn("minFont=", self.probe)

    def test_version_and_ci_route_follow_v384(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 85) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.84;", self.project)
        old = "python3 -B scripts/test-v384-koharu-render-min-font-contract.py"
        new = "python3 -B scripts/test-v385-koharu-render-lock-min-font-contract.py"
        route = "scripts/test-v(38(2-manga-render-newline|3-koharu-fit-budget|4-koharu-render-min-font|5-koharu-render-lock-min-font|6-koharu-render-output-ledger|7-koharu-render-output-action|8-koharu-render-core-output-gate-action|9-koharu-render-output-summary-action)|390-koharu-render-failure-overlay-compaction)-contract\\.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
