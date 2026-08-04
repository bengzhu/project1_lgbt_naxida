#!/usr/bin/env python3
"""Contract for report-only actions on deferred Koharu output writes."""

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


class KoharuRenderOutputActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        report = braced_body(
            self.store,
            "private static func makeKoharuRenderRegressionLockReport(",
        )
        self.output_check = braced_body(report, "func outputCheck(")

    def test_planned_final_writes_keep_report_only_action(self) -> None:
        self.assertIn(
            'let plannedFinalWrite = fileName == "probe_report.json"',
            self.output_check,
        )
        self.assertIn(
            '|| fileName == "1_ocr_probe_text.txt"',
            self.output_check,
        )
        self.assertIn(
            'let recommendedAction = status == "presentNonEmpty" || plannedFinalWrite',
            self.output_check,
        )
        self.assertIn('"plannedFinalReportWrite"', self.output_check)
        self.assertIn('"plannedFinalOCRTextRewrite"', self.output_check)
        self.assertIn('"keepReportOnly"', self.output_check)
        self.assertIn('"inspectRenderOutputExport"', self.output_check)
        self.assertIn("recommendedAction: recommendedAction", self.output_check)
        self.assertIn("only missing or unchecked", self.output_check)

    def test_version_and_ci_route_follow_v386(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.87;"), 2)
        self.assertNotIn("MARKETING_VERSION = 3.86;", self.project)
        old = "python3 -B scripts/test-v386-koharu-render-output-ledger-contract.py"
        new = "python3 -B scripts/test-v387-koharu-render-output-action-contract.py"
        route = "scripts/test-v38(2-manga-render-newline|3-koharu-fit-budget|4-koharu-render-min-font|5-koharu-render-lock-min-font|6-koharu-render-output-ledger|7-koharu-render-output-action)-contract\\.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
