#!/usr/bin/env python3
"""Contracts for v2.5 crash-safe image workspace recovery."""

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


class ImageWorkspaceRecoveryContractTests(unittest.TestCase):
    def test_executable_workspace_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v205-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v205-image-workspace-recovery"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                    "scripts/test-v205-image-workspace-recovery-evaluator.swift",
                    "-o", str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run([str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertIn("v2.5 image workspace recovery evaluator passed", result.stdout)

    def test_startup_reconciles_only_when_startup_work_is_enabled(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        initializer = function_body(store, "init(")
        self.assertIn("guard performsStartupWork else { return }", initializer)
        self.assertIn("reconcileOrphanedImageTranslationWorkspaceAtStartup()", initializer)
        self.assertLess(
            initializer.index("guard performsStartupWork else { return }"),
            initializer.index("reconcileOrphanedImageTranslationWorkspaceAtStartup()"),
        )

    def test_startup_separates_exports_from_input_and_staging_orphans(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        startup = function_body(store, "private func reconcileOrphanedImageTranslationWorkspaceAtStartup()")
        self.assertIn("contentsOfDirectory(", startup)
        self.assertIn("isImageTranslationStableExportFilename(filename)", startup)
        self.assertIn("imageTranslationOwnedExportURLs.insert(managedFile)", startup)
        self.assertIn("isImageTranslationInputFilename(filename)", startup)
        self.assertIn("isImageTranslationStagingFilename(filename)", startup)
        self.assertIn("imageTranslationOwnedOrphanURLs.insert(managedFile)", startup)
        self.assertIn("discardImageTranslationExport()", startup)

    def test_input_and_staging_names_require_real_task_or_render_ids(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        input_name = function_body(store, "nonisolated private static func isImageTranslationInputFilename(")
        staging_name = function_body(store, "nonisolated private static func isImageTranslationStagingFilename(")
        self.assertIn("UUID(uuidString: uuid) != nil", input_name)
        self.assertIn('separator == "-"', input_name)
        self.assertIn("!remainder.isEmpty", input_name)
        self.assertIn('filename.hasPrefix(".")', staging_name)
        self.assertIn('filename.hasSuffix(suffix)', staging_name)
        self.assertIn("UUID(uuidString: uuid) != nil", staging_name)
        self.assertIn('prefix.hasSuffix("-translated-")', staging_name)

    def test_normal_input_and_staging_cleanup_use_the_generic_guard(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        input_remove = function_body(store, "private func removeImageTranslationInputFile(")
        staging_remove = function_body(store, "private func removeImageTranslationStagingFile(")
        runtime_remove = function_body(store, "private func removeImageTranslationRuntimeFile(")
        self.assertIn("removeImageTranslationRuntimeFile", input_remove)
        self.assertIn("kind: .input", input_remove)
        self.assertIn("removeImageTranslationRuntimeFile", staging_remove)
        self.assertIn("kind: .staging", staging_remove)
        self.assertIn("Self.removeImageTranslationManagedFile", runtime_remove)
        self.assertIn("imageTranslationOwnedOrphanURLs.insert(managedFile)", runtime_remove)
        self.assertIn("imageTranslationOwnedOrphanURLs.remove(managedFile)", runtime_remove)
        self.assertNotIn("try? FileManager.default.removeItem", input_remove)
        self.assertNotIn("try? FileManager.default.removeItem", staging_remove)

    def test_stable_exports_require_store_marker_and_render_id(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        publisher = function_body(store, "nonisolated private static func publishImageTranslationOverlay(")
        stable_name = function_body(store, "nonisolated private static func isImageTranslationStableExportFilename(")
        self.assertIn('"aitrans-export-\\(renderID.uuidString)-\\(baseName)-translated.png"', publisher)
        self.assertIn('let prefix = "aitrans-export-"', stable_name)
        self.assertIn("UUID(uuidString: uuid) != nil", stable_name)
        self.assertIn("baseAndSuffix.count > suffix.count", stable_name)

    def test_generic_guard_rejects_wrong_directory_symlinks_and_non_regular_files(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        helper = function_body(store, "nonisolated private static func removeImageTranslationManagedFile(")
        self.assertIn("managedFile.deletingLastPathComponent() == managedDirectory", helper)
        self.assertIn("isImageTranslationManagedFilename(filename, kind: kind)", helper)
        self.assertIn("destinationOfSymbolicLink(atPath: managedFile.path)", helper)
        self.assertIn("values.isRegularFile == true", helper)
        self.assertIn("values.isSymbolicLink != true", helper)
        self.assertLess(
            helper.index("destinationOfSymbolicLink(atPath: managedFile.path)"),
            helper.index("fileManager.fileExists(atPath: managedFile.path)"),
        )

    def test_failed_orphan_cleanup_keeps_ownership_for_later_retry(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        discard = function_body(store, "private func discardImageTranslationWorkspaceOrphans(")
        self.assertIn("private var imageTranslationOwnedOrphanURLs: Set<URL> = []", store)
        self.assertIn("for url in Array(imageTranslationOwnedOrphanURLs)", discard)
        self.assertIn("if Self.removeImageTranslationManagedFile", discard)
        self.assertIn("imageTranslationOwnedOrphanURLs.remove(url)", discard)

    def test_all_runtime_cleanup_calls_supply_the_trusted_workspace(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertNotIn("removeImageTranslationInputFile(sandboxURL)\n", store)
        self.assertNotIn("removeImageTranslationInputFile(unclaimedSandboxURL)\n", store)
        self.assertNotIn("removeImageTranslationStagingFile(stagedURL)\n", store)
        self.assertGreaterEqual(store.count("directory: self.imageTranslationDirectory"), 4)
        self.assertGreaterEqual(store.count("directory: imageTranslationDirectory"), 5)
        self.assertGreaterEqual(store.count("directory: directory"), 3)

    def test_ci_runs_v25_after_prior_image_contracts(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        v204 = workflow.index("scripts/test-v204-image-export-lifecycle-contract.py")
        v205 = workflow.index("scripts/test-v205-image-workspace-recovery-contract.py")
        self.assertLess(v204, v205)
        step_start = workflow.index("- name: UI interaction contract")
        step_end = workflow.index("- name: v1.88 home UI contract", step_start)
        self.assertIn("set -euo pipefail", workflow[step_start:step_end])


if __name__ == "__main__":
    unittest.main(verbosity=2)
