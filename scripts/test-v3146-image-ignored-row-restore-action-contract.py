#!/usr/bin/env python3
"""Static contracts for v3.146 direct restore from an ignored OCR row."""

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


class ImageIgnoredRowRestoreActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_ignored_row_exposes_gated_restore_action_and_context(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationIgnoredBlockRow: View")
        modifier = braced_body(
            self.view,
            "private struct ImageIgnoredBlockRestoreAccessibilityModifier: ViewModifier",
        )

        self.assertIn("ImageIgnoredBlockRestoreAccessibilityModifier", row)
        self.assertIn(".accessibilityHint(accessibilityHint)", row)
        self.assertIn("if canRestore", modifier)
        self.assertIn('.accessibilityAction(named: "恢复")', modifier)
        self.assertIn("restore()", modifier)
        self.assertIn("可执行“恢复”", row)
        self.assertIn("恢复到图片预览、导出和当前转录", row)
        self.assertIn("需要复查时会重新回到待复查队列", row)
        self.assertIn("modificationUnavailableHint", row)

    def test_locked_rows_keep_child_button_and_do_not_expose_parent_action(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationIgnoredBlockRow: View")
        modifier = braced_body(
            self.view,
            "private struct ImageIgnoredBlockRestoreAccessibilityModifier: ViewModifier",
        )
        gated = braced_body(modifier, "func body(content: Content) -> some View")

        self.assertIn('Button("恢复", systemImage: "arrow.uturn.backward", action: restore)', row)
        self.assertIn(".disabled(!canRestore)", row)
        self.assertIn('equals: "image-ignored-row-\\(block.id.uuidString)"', row)
        self.assertIn("else", gated)
        self.assertNotIn('.accessibilityAction(named: "恢复")', gated[gated.index("else"):])
        self.assertIn("当前不可恢复", row)

    def test_action_reuses_existing_view_callback_without_store_mutation(self) -> None:
        row = braced_body(self.view, "private struct ImageTranslationIgnoredBlockRow: View")
        modifier = braced_body(
            self.view,
            "private struct ImageIgnoredBlockRestoreAccessibilityModifier: ViewModifier",
        )

        self.assertNotIn("@State", row)
        self.assertNotIn("@State", modifier)
        self.assertNotIn("TranslationSessionStore", row)
        self.assertNotIn("store.", row)
        self.assertNotIn("imageTranslationBlocks =", row)
        self.assertNotIn("FileManager", row)

    def test_version_and_ci_route_follow_v3145(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.146;", self.project)
        old = "python3 -B scripts/test-v3145-image-file-selection-replacement-hint-contract.py"
        new = "python3 -B scripts/test-v3146-image-ignored-row-restore-action-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn("14[6]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
