#!/usr/bin/env python3
"""Contract for v3.119 focusing the pending image retry-language status."""

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
                return source[brace:index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageRetryLanguageFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_pending_retry_language_status_is_a_stable_focus_destination(self) -> None:
        for marker in [
            'imageRetryLanguageStatusAccessibilityFocusID = "image-retry-language-status"',
            'if let retryLanguageSummary = store.imageTranslationRetryLanguageSummary',
            '.accessibilityLabel("重试语言已更新")',
            ".accessibilityValue(retryLanguageSummary)",
            ".accessibilityFocused(",
            "Self.imageRetryLanguageStatusAccessibilityFocusID",
        ]:
            self.assertIn(marker, self.panel)

    def test_summary_change_moves_focus_only_when_a_pending_language_exists(self) -> None:
        handler = braced_body(
            self.panel,
            ".onChange(of: store.imageTranslationRetryLanguageSummary) { oldSummary, newSummary in",
        )
        self.assertIn("guard newSummary != nil, newSummary != oldSummary else { return }", handler)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: Self.imageRetryLanguageStatusAccessibilityFocusID)",
            handler,
        )
        self.assertNotIn("retryImageTranslation()", handler)

    def test_focus_reuses_revision_scoped_view_generation_without_store_state(self) -> None:
        self.assertIn("reviewAccessibilityFocusRequestID &+= 1", self.panel)
        self.assertIn("revision == store.imageTranslationRevision", self.panel)
        self.assertNotIn("imageRetryLanguageStatusAccessibilityFocusID", self.store)
        self.assertNotIn("imageRetryLanguageSummary =", self.panel)

    def test_version_and_ci_route_follow_v3118(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 119) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.118;", self.project)
        script = "scripts/test-v3119-image-retry-language-focus-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3118-manga-koharu-readiness-focus-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
