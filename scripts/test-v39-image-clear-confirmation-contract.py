#!/usr/bin/env python3
"""Contracts for v3.9 destructive image-clear confirmation."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class ImageClearConfirmationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.command_bar = view[
            view.index("private struct ImageCommandBar"):
            view.index("private struct PhotoPickerCommand")
        ]

    def test_clear_button_requests_confirmation_instead_of_deleting(self) -> None:
        self.assertIn("@State private var showClearConfirmation = false", self.command_bar)
        self.assertIn('title: "清空图片翻译"', self.command_bar)
        self.assertIn("action: requestClearImageTranslation", self.command_bar)
        self.assertNotIn(
            'AppIconButton(title: "清空图片翻译", systemImage: "trash", '
            'tone: .danger, action: store.clearImageTranslation)',
            self.command_bar,
        )

    def test_dialog_is_attached_to_the_triggering_command_bar(self) -> None:
        self.assertIn(
            '.confirmationDialog(\n            "清空图片翻译？",',
            self.command_bar,
        )
        self.assertIn("isPresented: $showClearConfirmation", self.command_bar)
        self.assertIn("titleVisibility: .visible", self.command_bar)

    def test_only_destructive_confirmation_calls_store_clear(self) -> None:
        self.assertEqual(self.command_bar.count("store.clearImageTranslation"), 1)
        self.assertIn(
            'Button("清空图片与翻译结果", role: .destructive, '
            "action: store.clearImageTranslation)",
            self.command_bar,
        )
        self.assertIn('Button("取消", role: .cancel) {}', self.command_bar)
        self.assertIn("showClearConfirmation = true", self.command_bar)

    def test_dialog_explains_all_deleted_user_content_and_ci_order(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")

        self.assertIn("这会删除当前图片、识别结果、译文和导出文件。", self.command_bar)
        self.assertIn("39-image-clear-confirmation", workflow)
        self.assertLess(
            workflow.index("scripts/test-v38-image-entry-pro-gate-contract.py"),
            workflow.index("scripts/test-v39-image-clear-confirmation-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
