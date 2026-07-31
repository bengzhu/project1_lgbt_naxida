#!/usr/bin/env python3
"""Static contracts for v3.42 image action-lock feedback."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def braced_body(source: str, marker: str) -> str:
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace:index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageActionLockFeedbackContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_panel_explains_why_final_state_locks_remain_active(self) -> None:
        modification_detail = braced_body(
            self.panel,
            "private var imageModificationUnavailableDetail: String",
        )
        self.assertIn("isRenderingExport", modification_detail)
        self.assertIn("case .translating", modification_detail)
        self.assertIn("可继续查看和定位文字块", modification_detail)
        self.assertIn("case .failed", modification_detail)

        review_detail = braced_body(
            self.panel,
            "private var imageReviewUnavailableDetail: String",
        )
        self.assertIn("case .translating", review_detail)
        self.assertIn("更新复查进度", review_detail)

        lock_detail = braced_body(
            self.panel,
            "private var imageActionLockDetail: String?",
        )
        self.assertIn("!store.imageTranslationBlocks.isEmpty", lock_detail)
        self.assertIn("!canModifyImageTranslation", lock_detail)
        self.assertIn("!canReviewImageTranslation", lock_detail)

        inspector = braced_body(self.panel, "private var inspector: some View")
        self.assertIn("if let imageActionLockDetail", inspector)
        self.assertIn("title: imageActionLockTitle", inspector)
        self.assertIn("detail: imageActionLockDetail", inspector)
        self.assertIn(": imageReviewUnavailableDetail", inspector)

    def test_every_locked_mutating_entry_has_an_accessible_reason(self) -> None:
        inspector = braced_body(self.panel, "private var inspector: some View")
        self.assertIn("? \"选择译文以旁贴或覆盖方式呈现\"", inspector)
        self.assertIn(": imageModificationUnavailableDetail", inspector)

        focus = braced_body(self.view, "private struct ImageTranslationFocusPreview: View")
        self.assertIn("图片翻译完成且导出图更新结束后可修正当前文字块", focus)

        row = braced_body(self.view, "private struct ImageTranslationBlockRow: View")
        self.assertIn("图片翻译完成且导出图更新结束后可修正当前文字块", row)
        self.assertIn("图片翻译完成且导出图更新结束后可恢复此文字块的 OCR 结果", row)

        ignored = braced_body(self.view, "private struct ImageTranslationIgnoredBlockRow: View")
        self.assertIn("图片翻译完成且导出图更新结束后可恢复此文字块", ignored)

    def test_version_is_bumped_consistently(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.42;"), 2)

    def test_ci_runs_v342_after_v341(self) -> None:
        old = "python3 -B scripts/test-v341-image-review-final-state-lock-contract.py"
        new = "python3 -B scripts/test-v342-image-action-lock-feedback-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v342-image-action-lock-feedback-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
