#!/usr/bin/env python3
"""Contracts for v2.6 readable, Store-owned image sharing."""

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


class ImageShareLifecycleContractTests(unittest.TestCase):
    def test_executable_share_lifecycle_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v206-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v206-image-share-lifecycle"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                    "scripts/test-v206-image-share-lifecycle-evaluator.swift",
                    "-o", str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run([str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertIn("v2.6 image share lifecycle evaluator passed", result.stdout)

    def test_store_prepares_readable_share_without_exposing_internal_marker(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        prepare = function_body(store, "func prepareImageTranslationShareURL()")
        self.assertIn('appendingPathComponent("ImageTranslationShares"', store)
        self.assertIn('appendingPathComponent("\\(baseName)-translated.png")', prepare)
        self.assertIn("Task.detached(priority: .userInitiated)", prepare)
        self.assertIn("linkItem(at: sourceURL, to: shareURL)", prepare)
        self.assertIn("copyItem(at: sourceURL, to: shareURL)", prepare)
        self.assertNotIn("aitrans-export-", prepare)

    def test_request_identity_rejects_late_share_results(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        prepare = function_body(store, "func prepareImageTranslationShareURL()")
        discard = function_body(store, "private func discardImageTranslationShareCopies()")
        self.assertIn("private var imageTranslationShareRequestID = UUID()", store)
        self.assertIn("imageTranslationShareRequestID = requestID", prepare)
        self.assertIn("imageTranslationShareRequestID == requestID", prepare)
        self.assertIn("imageTranslationExportURL?.standardizedFileURL == sourceURL", prepare)
        self.assertIn("imageTranslationShareRequestID = UUID()", discard)

    def test_share_cleanup_is_store_owned_and_retried(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        discard_export = function_body(store, "private func discardImageTranslationExport()")
        discard_share = function_body(store, "private func discardImageTranslationShareCopies()")
        retain = function_body(store, "private func retainImageTranslationShareDirectoryIfCleanupFails(")
        self.assertIn("discardImageTranslationShareCopies()", discard_export)
        self.assertIn("imageTranslationOwnedShareDirectories", discard_share)
        self.assertIn("if Self.removeImageTranslationShareDirectory", discard_share)
        self.assertIn("imageTranslationOwnedShareDirectories.remove(directory)", discard_share)
        self.assertIn("imageTranslationOwnedShareDirectories.insert(managedDirectory)", retain)

    def test_startup_only_adopts_direct_uuid_directories(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        initializer = function_body(store, "init(")
        startup = function_body(store, "private func reconcileOrphanedImageTranslationSharesAtStartup()")
        remove = function_body(store, "nonisolated private static func removeImageTranslationShareDirectory(")
        self.assertIn("guard performsStartupWork else { return }", initializer)
        self.assertIn("reconcileOrphanedImageTranslationSharesAtStartup()", initializer)
        self.assertIn("directory.deletingLastPathComponent() == root", startup)
        self.assertIn("UUID(uuidString: directory.lastPathComponent) != nil", startup)
        self.assertIn("destinationOfSymbolicLink(atPath: managedDirectory.path)", remove)
        self.assertIn("values.isDirectory == true", remove)
        self.assertIn("values.isSymbolicLink != true", remove)

    def test_view_only_requests_store_and_cleans_presentation_lifecycle(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        share = function_body(view, "private func shareResult()")
        finish = function_body(view, "private func finishSharing()")
        self.assertIn("await store.prepareImageTranslationShareURL()", share)
        self.assertIn("sharePresentationID = presentationID", share)
        self.assertIn("guard sharePresentationID == presentationID", share)
        self.assertIn("onDismiss: finishSharing", view)
        self.assertIn(".onChange(of: store.imageTranslationExportURL)", view)
        self.assertIn(".onDisappear", view)
        self.assertIn("sharePresentationID = UUID()", finish)
        self.assertIn("store.finishImageTranslationSharing()", finish)
        self.assertNotIn("FileManager.default", view)

    def test_ci_runs_v26_after_workspace_recovery(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        v205 = workflow.index("scripts/test-v205-image-workspace-recovery-contract.py")
        v206 = workflow.index("scripts/test-v206-image-share-lifecycle-contract.py")
        self.assertLess(v205, v206)
        step_start = workflow.index("- name: UI interaction contract")
        step_end = workflow.index("- name: v1.88 home UI contract", step_start)
        self.assertIn("set -euo pipefail", workflow[step_start:step_end])


if __name__ == "__main__":
    unittest.main(verbosity=2)
