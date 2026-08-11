#!/usr/bin/env python3
"""Contract for VoiceOver focus after scoped OCR rerecognition fails or cancels."""

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


class ImageOCRRerecognitionFailureFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.rerecognition = braced_body(
            self.store,
            "func rerecognizeImageTranslationBlock(",
        )
        self.failure_focus_change = braced_body(
            self.view,
            ".onChange(of: store.imageTranslationBlockRerecognitionFailureGeneration)",
        )
        self.failure_focus_helper = braced_body(
            self.view,
            "private func focusImageTranslationRerecognitionFailureIfNeeded(",
        )

    def test_store_publishes_failure_generation(self) -> None:
        marker = "@Published private(set) var imageTranslationBlockRerecognitionFailureGeneration = 0"
        self.assertIn(marker, self.store)
        self.assertEqual(
            self.rerecognition.count(
                "self.imageTranslationBlockRerecognitionFailureGeneration &+= 1"
            ),
            2,
        )

    def test_failure_and_cancellation_publish_only_after_current_message(self) -> None:
        cancellation = braced_body(self.rerecognition, "catch is CancellationError")
        failure = braced_body(self.rerecognition, "catch {")
        generation = "imageTranslationBlockRerecognitionFailureGeneration &+= 1"
        for branch, message in [
            (cancellation, 'imageTranslationMessage = "此图片文字块重新识别已取消"'),
            (failure, 'imageTranslationMessage = "此图片文字块重新识别失败：\\(error.localizedDescription)"'),
        ]:
            self.assertIn("self.imageTranslationBlockRerecognitionID == requestID", branch)
            self.assertIn("self.imageTranslationTaskID == contentTaskID", branch)
            self.assertIn(message, branch)
            self.assertGreater(branch.index(generation), branch.index(message))

        success = self.rerecognition[: self.rerecognition.index("catch is CancellationError")]
        self.assertNotIn(generation, success)

    def test_stale_requests_do_not_publish_failure_focus(self) -> None:
        for marker in [
            "let requestID = UUID()",
            "let contentTaskID = imageTranslationTaskID",
            "self.imageTranslationBlockRerecognitionID == requestID",
            "self.imageTranslationTaskID == contentTaskID",
            "self.imageTranslationRerecognizingBlockID = nil",
        ]:
            self.assertIn(marker, self.rerecognition)
        self.assertIn("invalidateImageTranslationBlockRerecognition()", self.store)

    def test_view_routes_failure_generation_to_status_focus(self) -> None:
        for marker in [
            "generation > 0",
            "store.imageTranslationRerecognizingBlockID == nil",
            "store.imageTranslationState == .translated || store.imageTranslationState == .failed",
            "focusImageTranslationRerecognitionFailureIfNeeded(generation)",
        ]:
            self.assertIn(marker, self.failure_focus_change)
        for marker in [
            "let revision = store.imageTranslationRevision",
            "await Task.yield()",
            "revision == store.imageTranslationRevision",
            "generation == store.imageTranslationBlockRerecognitionFailureGeneration",
            "store.imageTranslationRerecognizingBlockID == nil",
            "store.imageTranslationState == .translated || store.imageTranslationState == .failed",
            "moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)",
        ]:
            self.assertIn(marker, self.failure_focus_helper)

    def test_success_focus_contract_remains_separate(self) -> None:
        self.assertIn(
            ".onChange(of: store.imageTranslationBlockRerecognitionCompletionGeneration)",
            self.view,
        )
        success_helper = braced_body(
            self.view,
            "private func focusImageTranslationRerecognitionCompletionIfNeeded(",
        )
        self.assertNotIn("imageTranslationBlockRerecognitionFailureGeneration", success_helper)

    def test_version_and_ci_route_follow_v3247(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 248) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.247;", self.project)
        previous = "python3 -B scripts/test-v3247-image-ocr-rerecognition-review-focus-contract.py"
        current = "python3 -B scripts/test-v3248-image-ocr-rerecognition-failure-focus-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3248-image-ocr-rerecognition-failure-focus-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
