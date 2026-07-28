#!/usr/bin/env python3
"""Contracts for v3.8 image-entry Pro gating."""

from pathlib import Path
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


class ImageEntryProGateContractTests(unittest.TestCase):
    def test_store_owns_image_entry_authorization_and_feedback(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        access = function_body(store, "func requestImageTranslationAccess() -> Bool")

        self.assertIn("guard isProUnlocked else", access)
        self.assertIn('dataTransferMessage = "图片翻译需要 Pro"', access)
        self.assertIn("return false", access)
        self.assertIn("return true", access)

    def test_real_pickers_exist_only_in_the_unlocked_branch(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        commands = function_body(view, "@ViewBuilder private var commands: some View")
        unlocked, locked = commands.split("} else {", maxsplit=1)

        self.assertIn("if store.isProUnlocked", unlocked)
        self.assertIn("PhotoPickerCommand(", unlocked)
        self.assertIn("action: openImporter", unlocked)
        self.assertNotIn("PhotoPickerCommand(", locked)
        self.assertNotIn("action: openImporter", locked)

    def test_locked_commands_report_access_denial_without_opening_picker(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        command_bar = view[
            view.index("private struct ImageCommandBar"):
            view.index("private struct PhotoPickerCommand")
        ]
        commands = function_body(view, "@ViewBuilder private var commands: some View")
        locked = commands.split("} else {", maxsplit=1)[1]

        self.assertEqual(locked.count('systemImage: "lock.fill"'), 2)
        self.assertEqual(locked.count("action: requestImageTranslationAccess"), 2)
        self.assertIn("showLockedImageTranslation = !store.requestImageTranslationAccess()", command_bar)
        self.assertIn('.alert("Pro 功能", isPresented: $showLockedImageTranslation)', command_bar)
        self.assertIn("Text(store.dataTransferMessage)", command_bar)

    def test_lower_level_guards_still_precede_task_creation(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        for signature in (
            "func translateImage(from url: URL)",
            "func translateImageTransfer(",
        ):
            translation = function_body(store, signature)
            self.assertLess(
                translation.index("guard isProUnlocked else"),
                translation.index("beginImageTranslationTask("),
            )

    def test_ci_runs_v38_after_v37(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")

        self.assertIn("38-image-entry-pro-gate", workflow)
        self.assertLess(
            workflow.index("scripts/test-v37-image-source-pro-feedback-contract.py"),
            workflow.index("scripts/test-v38-image-entry-pro-gate-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
