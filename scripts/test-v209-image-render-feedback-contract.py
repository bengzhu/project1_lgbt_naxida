#!/usr/bin/env python3
"""Contracts for v2.9 image export rerender feedback."""

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


class ImageRenderFeedbackContractTests(unittest.TestCase):
    def test_executable_render_feedback_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v209-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v209-image-render-feedback"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                    "scripts/test-v209-image-render-feedback-evaluator.swift",
                    "-o", str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run([str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertIn("v2.9 image render feedback evaluator passed", result.stdout)

    def test_store_owns_render_state_and_rejects_duplicate_modes(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        select_mode = function_body(store, "func setImageOverlayMode(_ mode: ImageTranslationOverlayMode)")
        rerender = function_body(store, "private func rerenderImageTranslationExport()")
        self.assertIn("@Published private(set) var imageTranslationExportRenderState", store)
        self.assertLess(select_mode.index("imageTranslationExportRenderState != .rendering"), select_mode.index("imageOverlayMode = mode"))
        self.assertLess(rerender.index("imageOverlayRenderID = renderID"), rerender.index("imageTranslationExportRenderState = .rendering"))
        self.assertLess(rerender.index("imageTranslationExportRenderState = .rendering"), rerender.index("Task { [weak self]"))

    def test_current_render_identity_gates_success_failure_and_cancellation(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        rerender = function_body(store, "private func rerenderImageTranslationExport()")
        success_guard = rerender.index("guard self.imageOverlayRenderID == renderID")
        self.assertLess(success_guard, rerender.index("self.imageTranslationExportRenderState = .idle"))
        failure = rerender[rerender.rindex("} catch {") :]
        self.assertLess(failure.index("self.imageOverlayRenderID == renderID"), failure.index("self.imageTranslationExportRenderState = .failed(message)"))
        cancellation = rerender[rerender.index("catch is CancellationError") : rerender.rindex("} catch {")]
        self.assertLess(cancellation.index("self.imageOverlayRenderID == renderID"), cancellation.index("self.imageTranslationExportRenderState = .idle"))

    def test_invalidation_and_retry_close_the_state_machine(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        invalidate = function_body(store, "private func invalidateImageOverlayRender()")
        retry = function_body(store, "func retryImageTranslationExportRender()")
        self.assertIn("imageOverlayRenderID = UUID()", invalidate)
        self.assertIn("imageTranslationExportRenderState = .idle", invalidate)
        self.assertIn("guard case .failed = imageTranslationExportRenderState", retry)
        self.assertIn("rerenderImageTranslationExport()", retry)

    def test_view_prioritizes_render_feedback_and_disables_picker(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.assertIn("isRunning || isRenderingExport", view)
        self.assertIn('case .rendering: return "正在更新导出图"', view)
        self.assertIn('case .failed: return "导出图生成失败"', view)
        self.assertIn("case .failed(let message): return message", view)
        self.assertIn('title: "重试导出"', view)
        self.assertIn("action: store.retryImageTranslationExportRender", view)
        share_index = view.index("switch store.imageTranslationShareState")
        render_index = view.index("switch store.imageTranslationExportRenderState")
        translation_index = view.index("switch store.imageTranslationState", render_index)
        self.assertLess(share_index, render_index)
        self.assertLess(render_index, translation_index)

    def test_ci_runs_v29_after_share_feedback(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        self.assertLess(
            workflow.index("scripts/test-v208-image-share-feedback-contract.py"),
            workflow.index("scripts/test-v209-image-render-feedback-contract.py"),
        )
        self.assertIn("209-image-render-feedback", workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
