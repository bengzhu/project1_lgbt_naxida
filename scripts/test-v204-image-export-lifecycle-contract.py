#!/usr/bin/env python3
"""Contracts for v2.4 Store-owned image export cleanup."""

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
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unterminated function body: {signature}")


class ImageExportLifecycleContractTests(unittest.TestCase):
    def test_executable_lifecycle_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v204-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v204-image-export-lifecycle"
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
                    str(Path(temporary_directory) / "module-cache"),
                    "scripts/test-v204-image-export-lifecycle-evaluator.swift",
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
            self.assertIn("v2.4 image export lifecycle evaluator passed", result.stdout)

    def test_new_task_and_clear_delete_the_owned_export(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        begin = function_body(store, "private func beginImageTranslationTask(")
        clear = function_body(store, "func clearImageTranslation()")
        for body in (begin, clear):
            self.assertIn("discardImageTranslationExport()", body)
            self.assertNotIn("imageTranslationExportURL = nil", body)

    def test_rerender_deletes_the_superseded_export_before_hiding_it(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        rerender = function_body(store, "private func rerenderImageTranslationExport()")
        self.assertIn("discardImageTranslationExport()", rerender)
        self.assertNotIn("imageTranslationExportURL = nil", rerender)
        self.assertIn("self.imageOverlayRenderID == renderID", rerender)
        self.assertIn("self.imageTranslationTaskID == contentTaskID", rerender)
        self.assertIn("self.removeImageTranslationStagingFile(stagedURL, directory: directory)", rerender)

    def test_export_deletion_is_confined_to_the_managed_directory(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        export_helper = function_body(store, "nonisolated private static func removeImageTranslationManagedExport(")
        helper = function_body(store, "nonisolated private static func removeImageTranslationManagedFile(")
        stable_name = function_body(store, "nonisolated private static func isImageTranslationStableExportFilename(")
        self.assertIn("removeImageTranslationManagedFile", export_helper)
        self.assertIn("kind: .stableExport", export_helper)
        self.assertIn("directory.standardizedFileURL", helper)
        self.assertIn("url.standardizedFileURL", helper)
        self.assertIn("managedFile.deletingLastPathComponent() == managedDirectory", helper)
        self.assertIn("isImageTranslationManagedFilename(filename, kind: kind)", helper)
        self.assertIn('let prefix = "aitrans-export-"', stable_name)
        self.assertIn("UUID(uuidString: uuid) != nil", stable_name)
        self.assertIn('baseAndSuffix.hasSuffix(suffix)', stable_name)
        self.assertIn("values.isRegularFile == true", helper)
        self.assertIn("values.isSymbolicLink != true", helper)
        self.assertIn("destinationOfSymbolicLink(atPath: managedFile.path)", helper)
        self.assertNotIn("try? fileManager.removeItem", helper)
        self.assertLess(
            helper.index("managedFile.deletingLastPathComponent() == managedDirectory"),
            helper.index("fileManager.removeItem(at: managedFile)"),
        )
        self.assertLess(
            helper.index("destinationOfSymbolicLink(atPath: managedFile.path)"),
            helper.index("fileManager.fileExists(atPath: managedFile.path)"),
        )

    def test_startup_adopts_and_discards_prior_stable_exports(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        initializer = function_body(store, "init(")
        startup = function_body(store, "private func reconcileOrphanedImageTranslationWorkspaceAtStartup()")
        self.assertIn("guard performsStartupWork else { return }", initializer)
        self.assertIn("reconcileOrphanedImageTranslationWorkspaceAtStartup()", initializer)
        self.assertLess(
            initializer.index("guard performsStartupWork else { return }"),
            initializer.index("reconcileOrphanedImageTranslationWorkspaceAtStartup()"),
        )
        self.assertIn("contentsOfDirectory(", startup)
        self.assertIn("isImageTranslationStableExportFilename(filename)", startup)
        self.assertIn("imageTranslationOwnedExportURLs.insert(managedFile)", startup)
        self.assertIn("discardImageTranslationExport()", startup)

    def test_failed_deletion_keeps_private_ownership_for_retry(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        publish = function_body(store, "private func publishImageTranslationExport(")
        discard = function_body(store, "private func discardImageTranslationExport()")
        self.assertIn("private var imageTranslationOwnedExportURLs: Set<URL> = []", store)
        self.assertIn("imageTranslationOwnedExportURLs.insert(standardizedURL)", publish)
        self.assertIn("imageTranslationExportURL = nil", discard)
        self.assertIn("if Self.removeImageTranslationManagedExport(url, directory: directory)", discard)
        self.assertIn("imageTranslationOwnedExportURLs.remove(url)", discard)
        self.assertLess(
            discard.index("if Self.removeImageTranslationManagedExport"),
            discard.index("imageTranslationOwnedExportURLs.remove(url)"),
        )

    def test_both_real_publish_paths_use_the_ownership_wrapper(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        pipeline = function_body(store, "private func runImageTranslationPipeline(")
        rerender = function_body(store, "private func rerenderImageTranslationExport()")
        self.assertIn("publishImageTranslationExport(outputURL)", pipeline)
        self.assertIn("self.publishImageTranslationExport(outputURL)", rerender)
        self.assertEqual(
            len(re.findall(r"imageTranslationExportURL\s*=(?!=)", store)),
            2,
            "only publish/discard wrappers may mutate the public export URL",
        )

    def test_cancel_retains_retry_source_and_does_not_delete_export(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        cancel = function_body(store, "func cancelImageTranslation()")
        self.assertNotIn("removeImageTranslationManagedExport", cancel)
        self.assertNotIn("discardImageTranslationExport", cancel)
        self.assertNotIn("removeImageTranslationInputFile", cancel)
        self.assertNotIn("imageTranslationSourceURL = nil", cancel)

        retry = function_body(store, "func retryImageTranslation()")
        self.assertIn("preservingSourceURL: url", retry)

    def test_ci_runs_v24_after_prior_image_contracts(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        v187 = workflow.index("scripts/test-v187-ui-interaction-contract.py")
        v202 = workflow.index("scripts/test-v202-image-import-run-isolation-contract.py")
        v203 = workflow.index("scripts/test-v203-image-cancel-retry-contract.py")
        v204 = workflow.index("scripts/test-v204-image-export-lifecycle-contract.py")
        self.assertLess(v187, v202)
        self.assertLess(v202, v203)
        self.assertLess(v203, v204)
        ui_step_start = workflow.index("- name: UI interaction contract")
        ui_step_end = workflow.index("- name: v1.88 home UI contract", ui_step_start)
        ui_step = workflow[ui_step_start:ui_step_end]
        self.assertIn("set -euo pipefail", ui_step)


if __name__ == "__main__":
    unittest.main(verbosity=2)
