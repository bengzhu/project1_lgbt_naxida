#!/usr/bin/env python3
"""Contract for aligning the retained-core-output gate with its output actions."""

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


class KoharuRenderCoreOutputGateActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.report = braced_body(
            self.store,
            "private static func makeKoharuRenderRegressionLockReport(",
        )

    def test_core_output_gate_action_matches_retained_output_state(self) -> None:
        self.assertIn(
            "let coreOutputRecommendedAction = coreOutputFilesNonEmpty",
            self.report,
        )
        self.assertIn('? "keepReportOnly"', self.report)
        self.assertIn('? "keepReportOnly"\n            : "inspectRenderOutputExport"', self.report)
        self.assertIn(
            'gate("G-render-core-png-retained", name: "Core PNG retained"',
            self.report,
        )
        gate_line = next(
            line
            for line in self.report.splitlines()
            if 'gate("G-render-core-png-retained"' in line
        )
        self.assertIn(
            'status: coreOutputFilesNonEmpty ? "passed" : "blocked"',
            gate_line,
        )
        self.assertIn("action: coreOutputRecommendedAction", gate_line)
        self.assertNotIn('action: "inspectRenderOutputExport"', gate_line)

    def test_version_and_ci_route_follow_v387(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.89;"), 2)
        self.assertNotIn("MARKETING_VERSION = 3.88;", self.project)
        old = "python3 -B scripts/test-v387-koharu-render-output-action-contract.py"
        new = "python3 -B scripts/test-v388-koharu-render-core-output-gate-action-contract.py"
        route = "scripts/test-v38(2-manga-render-newline|3-koharu-fit-budget|4-koharu-render-min-font|5-koharu-render-lock-min-font|6-koharu-render-output-ledger|7-koharu-render-output-action|8-koharu-render-core-output-gate-action|9-koharu-render-output-summary-action)-contract\\.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
