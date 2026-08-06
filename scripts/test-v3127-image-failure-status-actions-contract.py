#!/usr/bin/env python3
"""Contract for v3.127 direct retry actions on image failure status rows."""

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


class ImageFailureStatusActionsContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.row = braced_body(self.panel, "private func imageStatusAccessibilityRow")

    def test_share_failure_status_exposes_direct_retry_action(self) -> None:
        self.assertIn("if hasImageShareFailure", self.row)
        self.assertIn('.accessibilityAction(named: "重试分享")', self.row)
        self.assertIn("shareResult()", self.row)

    def test_export_failure_status_exposes_direct_retry_action(self) -> None:
        self.assertIn("else if hasImageExportRenderFailure", self.row)
        self.assertIn('.accessibilityAction(named: "重试导出")', self.row)
        self.assertIn("store.retryImageTranslationExportRender()", self.row)

    def test_failure_action_priority_matches_status_display_priority(self) -> None:
        self.assertLess(self.row.index("if hasImageShareFailure"), self.row.index("else if hasImageExportRenderFailure"))
        self.assertLess(self.row.index("else if hasImageExportRenderFailure"), self.row.index("else if canRetryFromImageStatus"))
        share_gate = braced_body(self.panel, "private var hasImageShareFailure")
        export_gate = braced_body(self.panel, "private var hasImageExportRenderFailure")
        self.assertIn("store.imageTranslationShareState", share_gate)
        self.assertIn("case .failed", share_gate)
        self.assertIn("store.imageTranslationExportRenderState", export_gate)
        self.assertIn("case .failed", export_gate)

    def test_failure_hints_explain_the_new_direct_actions(self) -> None:
        hint = braced_body(self.panel, "private var imageStatusAccessibilityHint")
        self.assertIn("执行“重试分享”", hint)
        self.assertIn("执行“重试导出”", hint)

    def test_actions_remain_view_only_and_reuse_store_operations(self) -> None:
        self.assertNotIn("imageStatusAccessibilityRow", self.store)
        self.assertNotIn("hasImageShareFailure", self.store)
        self.assertNotIn("hasImageExportRenderFailure", self.store)
        self.assertNotIn("runBubbleFirstProbe", self.panel)

    def test_version_and_ci_route_follow_v3126(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 127) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.126;", self.project)
        script = "scripts/test-v3127-image-failure-status-actions-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3126-image-export-share-failure-focus-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))
        self.assertRegex(
            self.workflow,
            r"test-v3\(1\[1-9\]|\[2-7\]\[0-9\]|8\[01\]|12\[2-7\]\)-",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
