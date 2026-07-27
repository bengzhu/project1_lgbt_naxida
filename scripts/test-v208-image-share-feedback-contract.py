#!/usr/bin/env python3
"""Contracts for v2.8 image share preparation feedback."""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing function signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unterminated function body: {signature}")


class ImageShareFeedbackContractTests(unittest.TestCase):
    def test_executable_feedback_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v208-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v208-image-share-feedback"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                    "scripts/test-v208-image-share-feedback-evaluator.swift",
                    "-o", str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run([str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertIn("v2.8 image share feedback evaluator passed", result.stdout)

    def test_store_publishes_request_scoped_share_feedback(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        prepare = function_body(store, "func prepareImageTranslationShareURL()")
        self.assertIn("@Published private(set) var imageTranslationShareState", store)
        self.assertLess(prepare.index("guard imageTranslationShareState != .preparing"), prepare.index("discardImageTranslationShareCopies()"))
        self.assertLess(prepare.index("imageTranslationShareRequestID = requestID"), prepare.index("imageTranslationShareState = .preparing"))
        self.assertLess(prepare.index("imageTranslationShareState = .preparing"), prepare.index("Task.detached(priority: .userInitiated)"))

    def test_only_current_result_can_finish_or_fail_feedback(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        prepare = function_body(store, "func prepareImageTranslationShareURL()")
        outer_catch = prepare.rindex("} catch {")
        success = prepare[prepare.index("guard imageTranslationShareRequestID == requestID") : outer_catch]
        self.assertLess(success.index("imageTranslationShareRequestID == requestID"), success.index("imageTranslationShareState = .idle"))
        failure = prepare[outer_catch:]
        self.assertLess(failure.index("imageTranslationShareRequestID == requestID"), failure.index("imageTranslationShareState = .failed(message)"))
        self.assertNotIn("imageTranslationMessage =", failure)

    def test_discard_resets_feedback_with_request_identity(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        discard = function_body(store, "private func discardImageTranslationShareCopies()")
        self.assertLess(discard.index("imageTranslationShareRequestID = UUID()"), discard.index("imageTranslationShareState = .idle"))
        self.assertIn("discardImageTranslationShareCopies()", function_body(store, "func finishImageTranslationSharing()"))

    def test_view_disables_duplicate_share_and_prioritizes_failure(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        command_bar = function_body(view, "@ViewBuilder private var commands: some View")
        share = function_body(view, "private func shareResult()")
        self.assertIn('isPreparingShare ? "准备中" : "导出"', command_bar)
        self.assertIn(".disabled(isPreparingShare)", command_bar)
        self.assertIn("guard store.imageTranslationShareState != .preparing", share)
        self.assertIn("case .failed: return .danger", view)
        self.assertGreaterEqual(view.count("case .idle: return .neutral"), 2)
        self.assertIn('case .failed: "分享准备失败"', view)
        self.assertIn("case .failed(let message): message", view)
        self.assertNotIn("FileManager.default", view)

    def test_ci_runs_v28_after_direction_contract(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        self.assertLess(workflow.index("scripts/test-v207-image-ocr-direction-contract.py"), workflow.index("scripts/test-v208-image-share-feedback-contract.py"))
        self.assertIn("208-image-share-feedback", workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
