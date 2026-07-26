#!/usr/bin/env python3
"""Contracts for v2.2 Store-owned image import run isolation."""

from pathlib import Path
import os
import re
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
    if brace < 0:
        raise AssertionError(f"missing function body: {signature}")
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unterminated function body: {signature}")


class ImageImportRunIsolationContractTests(unittest.TestCase):
    def test_executable_run_isolation_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v202-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v202-image-import-run-isolation"
            module_cache = Path(temporary_directory) / "module-cache"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-module-cache-path",
                    str(module_cache),
                    "scripts/test-v202-image-import-run-isolation-evaluator.swift",
                    "-o",
                    str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(executable)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("v2.2 image import run isolation evaluator passed", result.stdout)

    def test_photos_picker_transfer_is_owned_by_store(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        transfer = function_body(store, "func translateImageTransfer(")
        picker = function_body(view, "private func loadSelectedPhoto(")

        self.assertIn("loadData", transfer)
        self.assertIn("imageTranslationTask = Task", transfer)
        self.assertIn("store.translateImageTransfer", picker)
        self.assertIn("loadTransferable(type: Data.self)", picker)
        self.assertIn("imageFileSelectionID = nil", picker)
        self.assertNotIn("Task {", picker)
        for forbidden in [
            r"store\.imageTranslationState\s*=(?!=)",
            r"store\.imageTranslationMessage\s*=(?!=)",
            r"store\.dataTransferMessage\s*=(?!=)",
        ]:
            self.assertNotRegex(view, forbidden)

    def test_new_photo_or_file_supersedes_the_running_import(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        file_import = function_body(store, "func translateImage(from url: URL)")
        photo_import = function_body(store, "func translateImageTransfer(")
        begin = function_body(store, "private func beginImageTranslationTask(")

        running_guard = "imageTranslationState != .loading"
        self.assertNotIn(running_guard, file_import)
        self.assertNotIn(running_guard, photo_import)
        self.assertIn("imageTranslationTask?.cancel()", begin)
        self.assertIn("imageTranslationTaskID = taskID", begin)
        self.assertIn("imageTranslationSourceURL = nil", begin)
        self.assertIn("removeImageTranslationInputFile(imageTranslationSourceURL)", begin)

    def test_transfer_nil_and_all_late_results_are_task_id_gated(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        transfer = function_body(store, "func translateImageTransfer(")

        self.assertRegex(transfer, r"guard let \w+\s*=\s*try await loadData\(\)")
        self.assertRegex(
            transfer,
            re.compile(r"guard let \w+.*?else\s*\{.*?(?:throw|finishImageTranslation)", re.DOTALL),
        )
        self.assertGreaterEqual(transfer.count("isCurrentImageTranslationTask(taskID)"), 3)
        self.assertIn("writeImageDataIntoSandbox", transfer)
        write_end = transfer.index("writeImageDataIntoSandbox")
        source_publish = transfer.index("imageTranslationSourceURL =", write_end)
        identity_check = transfer.index("isCurrentImageTranslationTask(taskID)", write_end)
        self.assertLess(identity_check, source_publish, "sandbox URL must not publish before identity recheck")
        self.assertIn("finishImageTranslation(taskID: taskID", transfer)

    def test_file_copy_cannot_publish_source_url_before_identity_check(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        copier = function_body(store, "private func copyImageFileIntoSandbox(")
        file_import = function_body(store, "func translateImage(from url: URL)")

        self.assertNotIn("imageTranslationSourceURL =", copier)
        copy_end = file_import.index("copyImageFileIntoSandbox")
        source_publish = file_import.index("imageTranslationSourceURL =", copy_end)
        identity_check = file_import.index("isCurrentImageTranslationTask(taskID)", copy_end)
        self.assertLess(identity_check, source_publish, "file sandbox URL must be task-gated")

    def test_pending_file_selection_is_invalidated_by_new_photo_cancel_or_clear(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        begin_selection = function_body(store, "func beginImageFileSelection()")
        handle_selection = function_body(store, "func handleSelectedImageFile(")
        begin_task = function_body(store, "private func beginImageTranslationTask(")
        cancel = function_body(store, "func cancelImageTranslation()")
        clear = function_body(store, "func clearImageTranslation()")

        self.assertIn("let selectionID = UUID()", begin_selection)
        self.assertIn("imageTranslationFileSelectionID = selectionID", begin_selection)
        self.assertIn("return selectionID", begin_selection)
        self.assertIn("guard imageTranslationFileSelectionID == selectionID else { return }", handle_selection)
        self.assertIn("imageTranslationFileSelectionID = nil", handle_selection)
        for body in [begin_task, cancel, clear]:
            self.assertIn("imageTranslationFileSelectionID = nil", body)
        self.assertIn("imageFileSelectionID = store.beginImageFileSelection()", view)
        self.assertIn("store.handleSelectedImageFile(result, selectionID: selectionID)", view)
        self.assertIn("cocoaError.code == .userCancelled", handle_selection)
        self.assertIn("guard imageTranslationState == .idle", handle_selection)
        self.assertIn("imageTranslationData == nil", handle_selection)

    def test_retry_is_only_offered_for_a_retained_source(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        retry_gate = function_body(store, "var canRetryImageTranslation: Bool")

        self.assertIn("imageTranslationState == .failed", retry_gate)
        self.assertIn("let url = imageTranslationSourceURL", retry_gate)
        self.assertIn("FileManager.default.fileExists(atPath: url.path)", retry_gate)
        self.assertIn("else if store.canRetryImageTranslation", view)
        self.assertNotIn("else if store.imageTranslationState == .failed", view)

    def test_combined_ui_contracts_fail_fast(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        step = workflow[workflow.index("- name: UI interaction contract"):]
        step = step[:step.index("- name: v1.88 home UI contract")]
        self.assertIn("set -euo pipefail", step)
        self.assertLess(
            step.index("scripts/test-v187-ui-interaction-contract.py"),
            step.index("scripts/test-v202-image-import-run-isolation-contract.py"),
        )

    def test_task_scoped_filenames_and_stale_input_cleanup(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        copier = function_body(store, "private func copyImageFileIntoSandbox(")
        writer = function_body(store, "private func writeImageDataIntoSandbox(")
        file_import = function_body(store, "func translateImage(from url: URL)")
        transfer = function_body(store, "func translateImageTransfer(")

        self.assertIn('"\\(taskID.uuidString)-\\(Self.sanitizedImageFilename(from: url))"', copier)
        self.assertIn('"\\(taskID.uuidString)-\\(cleanName)"', writer)
        self.assertIn("let cleanFilename = Self.sanitizedImageFilename", file_import)
        self.assertIn("let cleanFilename = Self.sanitizedImageFilename", transfer)
        self.assertIn('filename: "photo-library-image.png"', view)
        self.assertNotIn("newItem.itemIdentifier", view)
        self.assertGreaterEqual(file_import.count("removeImageTranslationInputFile"), 2)
        self.assertGreaterEqual(transfer.count("removeImageTranslationInputFile"), 2)

        commands = function_body(view, "@ViewBuilder private var commands: some View")
        source_commands = commands.split("if isRunning", 1)[0]
        self.assertNotIn(".disabled(isRunning)", source_commands)

        retry = function_body(store, "func retryImageTranslation()")
        clear = function_body(store, "func clearImageTranslation()")
        self.assertIn("preservingSourceURL: url", retry)
        self.assertIn("removeImageTranslationInputFile(imageTranslationSourceURL)", clear)

    def test_cancel_clear_and_failure_cannot_restore_stale_state(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        cancel = function_body(store, "func cancelImageTranslation()")
        clear = function_body(store, "func clearImageTranslation()")
        finish = function_body(store, "private func finishImageTranslation(taskID: UUID, with error: Error)")
        begin = function_body(store, "private func beginImageTranslationTask(")

        for body in [cancel, clear]:
            self.assertIn("imageTranslationTask?.cancel()", body)
            self.assertIn("imageTranslationTaskID = UUID()", body)
        self.assertIn("guard imageTranslationTaskID == taskID else { return }", finish)
        self.assertIn("imageTranslationSourceURL = nil", begin)
        self.assertNotIn("imageTranslationSourceURL =", finish)


if __name__ == "__main__":
    unittest.main(verbosity=2)
