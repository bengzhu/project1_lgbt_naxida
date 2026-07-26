#!/usr/bin/env python3
"""Contracts for v2.3 image cancellation retry availability."""

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


class ImageCancelRetryContractTests(unittest.TestCase):
    def test_executable_retry_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v203-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v203-image-cancel-retry"
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
                    "scripts/test-v203-image-cancel-retry-evaluator.swift",
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
            self.assertIn("v2.3 image cancel retry evaluator passed", result.stdout)

    def test_store_allows_retry_after_cancel_only_with_a_source(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        retry_gate = function_body(store, "var canRetryImageTranslation: Bool")
        self.assertIn("imageTranslationState == .failed || imageTranslationState == .idle", retry_gate)
        self.assertIn("let url = imageTranslationSourceURL", retry_gate)
        self.assertIn("FileManager.default.fileExists(atPath: url.path)", retry_gate)

    def test_cancel_preserves_source_while_clear_removes_it(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        cancel = function_body(store, "func cancelImageTranslation()")
        clear = function_body(store, "func clearImageTranslation()")
        self.assertNotIn("imageTranslationSourceURL = nil", cancel)
        self.assertNotIn("removeImageTranslationInputFile(imageTranslationSourceURL)", cancel)
        self.assertIn("removeImageTranslationInputFile(imageTranslationSourceURL)", clear)
        self.assertIn("imageTranslationSourceURL = nil", clear)

    def test_view_and_ci_use_the_v23_retry_contract(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        workflow = read(".github/workflows/ci-results.yml")
        self.assertIn("else if store.canRetryImageTranslation", view)
        self.assertIn("scripts/test-v203-image-cancel-retry-contract.py", workflow)
        self.assertIn("203-image-cancel-retry", workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
