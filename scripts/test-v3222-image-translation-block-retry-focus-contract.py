#!/usr/bin/env python3
"""Contract for VoiceOver focus after the final scoped image translation retry."""

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


class ImageTranslationBlockRetryFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.retry = braced_body(self.store, "func retryImageTranslationBlock(")
        self.focus_change = braced_body(
            self.view,
            ".onChange(of: store.imageTranslationBlockRetryCompletionGeneration)",
        )
        self.retry_focus_helper = braced_body(
            self.view,
            "private func focusImageTranslationRetryCompletionIfNeeded(_ generation: Int)",
        )

    def test_store_publishes_a_separate_retry_completion_generation(self) -> None:
        self.assertIn(
            "@Published private(set) var imageTranslationBlockRetryCompletionGeneration = 0",
            self.store,
        )
        self.assertIn(
            "self.imageTranslationBlockRetryCompletionGeneration &+= 1",
            self.retry,
        )

    def test_generation_changes_only_after_all_blocks_are_complete(self) -> None:
        remaining_start = self.retry.index("let remainingCount =")
        remaining = self.retry[remaining_start:]
        self.assertIn("if remainingCount == 0", remaining)
        completion_start = remaining.index("if remainingCount == 0")
        completion = remaining[completion_start:]
        self.assertIn("self.imageTranslationState = .translated", completion)
        self.assertIn(
            "self.imageTranslationBlockRetryCompletionGeneration &+= 1",
            completion,
        )
        partial_start = remaining.index("} else {")
        partial = remaining[partial_start:]
        self.assertIn("self.imageTranslationState = .failed", partial)
        self.assertNotIn(
            "imageTranslationBlockRetryCompletionGeneration &+= 1",
            partial,
        )

    def test_view_handles_generation_and_keeps_state_and_content_guards(self) -> None:
        self.assertIn("generation > 0", self.focus_change)
        self.assertIn("store.imageTranslationState == .translated", self.focus_change)
        self.assertIn(
            "focusImageTranslationRetryCompletionIfNeeded(generation)",
            self.focus_change,
        )
        self.assertIn("let revision = store.imageTranslationRevision", self.retry_focus_helper)
        self.assertIn("revision == store.imageTranslationRevision", self.retry_focus_helper)
        self.assertIn(
            "generation == store.imageTranslationBlockRetryCompletionGeneration",
            self.retry_focus_helper,
        )

    def test_existing_retry_stale_result_guards_remain(self) -> None:
        for marker in [
            "let retryID = UUID()",
            "let contentTaskID = imageTranslationTaskID",
            "self.imageTranslationBlockRetryID == retryID",
            "self.imageTranslationTaskID == contentTaskID",
            "self.imageTranslationRetryingBlockID == blockID",
            "self.imageTranslationBlocks[blockIndex].original == block.original",
        ]:
            self.assertIn(marker, self.retry)

    def test_version_and_ci_route_follow_v3221(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 222) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.221;", self.project)
        previous = "python3 -B scripts/test-v3221-image-japanese-detector-owned-vision-noise-contract.py"
        current = "python3 -B scripts/test-v3222-image-translation-block-retry-focus-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3222-image-translation-block-retry-focus-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
