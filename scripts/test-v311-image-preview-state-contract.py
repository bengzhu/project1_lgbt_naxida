#!/usr/bin/env python3
"""Contracts for v3.11 revision-scoped image preview feedback and retry."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class ImagePreviewStateContractTests(unittest.TestCase):
    def setUp(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.preview = view[
            view.index("private struct ImagePreviewRequestID"):
            view.index("private struct ImageTranslationOverlayBlock")
        ]

    def test_rendered_preview_is_scoped_to_current_revision(self) -> None:
        self.assertIn("previewRevision == store.imageTranslationRevision", self.preview)
        self.assertIn("previewRevision = revision", self.preview)
        self.assertIn("revision == store.imageTranslationRevision", self.preview)
        self.assertIn("!Task.isCancelled", self.preview)

    def test_loaded_data_uses_progress_or_failure_instead_of_empty_prompt(self) -> None:
        data_branch = self.preview.index("store.imageTranslationData != nil")
        empty_branch = self.preview.index('title: "选择图片"')
        self.assertLess(data_branch, empty_branch)
        self.assertIn('Text("正在准备预览")', self.preview)
        self.assertIn('Text("预览生成失败")', self.preview)
        self.assertIn("previewPhase = .failed(revision: revision)", self.preview)

    def test_retry_only_restarts_local_preview_request(self) -> None:
        self.assertIn("struct ImagePreviewRequestID: Hashable", self.preview)
        self.assertIn("attempt: previewAttempt", self.preview)
        self.assertIn('title: "重试预览"', self.preview)
        self.assertIn("action: retryPreview", self.preview)
        self.assertIn("previewAttempt += 1", self.preview)
        self.assertNotIn("rerunImageRecognition", self.preview)
        self.assertNotIn("retryImageTranslation", self.preview)

    def test_failure_keeps_original_pipeline_ownership(self) -> None:
        self.assertIn("原图仍保留用于 OCR 与导出", self.preview)
        self.assertIn("await ImagePreviewService.makePreview(from: data)", self.preview)
        self.assertNotIn("UIImage(data:", self.preview)
        self.assertNotIn("imageTranslationData =", self.preview)

    def test_ci_runs_v311_after_v310(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        contract_step = workflow[
            workflow.index("- name: UI interaction contract"):
            workflow.index("- name: v1.88 home UI contract")
        ]
        self.assertIn("311-image-preview-state", contract_step)
        self.assertLess(
            contract_step.index("scripts/test-v310-image-preview-downsample-contract.py"),
            contract_step.index("scripts/test-v311-image-preview-state-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
