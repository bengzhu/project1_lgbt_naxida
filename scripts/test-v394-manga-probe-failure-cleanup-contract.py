#!/usr/bin/env python3
"""Contract for keeping failed manga probe attempts isolated from stale output/state."""

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


class MangaProbeFailureCleanupContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_new_attempt_clears_previous_report_before_bundle_lookup(self) -> None:
        body = braced_body(self.store, "func runMangaOverlayProbe()")
        self.assertIn("mangaOverlayProbeState = .loading", body)
        self.assertIn('mangaOverlayProbeMessage = "正在准备读取 test/1.png"', body)
        self.assertIn("mangaOverlayProbeReport = nil", body)
        self.assertIn("mangaOverlayProbeBlocks = []", body)
        self.assertLess(body.index("mangaOverlayProbeReport = nil"), body.index('guard let url = bundledTestFile(named: "1.png")'))

    def test_missing_bundle_image_rebuilds_output_and_reports_cleanup_state(self) -> None:
        body = braced_body(self.store, "func runMangaOverlayProbe()")
        missing_branch = body[body.index('guard let url = bundledTestFile(named: "1.png")'):]
        self.assertIn("MangaOverlayProbeService.recreateDirectory(mangaOverlayOutputDirectory)", missing_branch)
        self.assertIn('stage: "output-cleaned"', missing_branch)
        self.assertIn('stage: "output-cleanup-failed"', missing_branch)
        self.assertIn('stage: "missing-test-image"', missing_branch)
        self.assertIn("outputCleanupRemovedItemCount: cleanupResult.removedItemCount", missing_branch)
        self.assertIn("outputDirectoryCleaned: cleanupResult.cleaned", missing_branch)

    def test_async_failure_propagates_cleanup_state_and_policy_is_truthful(self) -> None:
        self.assertIn("var outputCleanupRemovedItemCount = 0", self.store)
        self.assertIn("var outputDirectoryCleaned = false", self.store)
        self.assertIn("outputDirectoryCleaned = true", self.store)
        self.assertIn("outputCleanupRemovedItemCount: outputCleanupRemovedItemCount", self.store)
        self.assertIn("outputDirectoryCleaned: outputDirectoryCleaned", self.store)
        self.assertIn("旧输出可能残留，不能作为本轮输出", self.store)

    def test_version_and_ci_route(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 94) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.93;", self.project)
        self.assertIn("scripts/test-v394-manga-probe-failure-cleanup-contract.py", self.workflow)
        self.assertIn("python3 -B scripts/test-v394-manga-probe-failure-cleanup-contract.py", self.workflow)
        self.assertLess(
            self.workflow.index("python3 -B scripts/test-v391-koharu-diagnostic-triage-contract.py"),
            self.workflow.index("python3 -B scripts/test-v394-manga-probe-failure-cleanup-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
