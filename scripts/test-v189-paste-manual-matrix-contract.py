#!/usr/bin/env python3
"""Static contracts for v1.89 manual matrix, debug paste inject, and wide evidence."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class V189PasteManualMatrixContractTests(unittest.TestCase):
    def test_manual_matrix_is_documented(self) -> None:
        test_md = read("md/test/test.md")
        self.assertIn("### 0.3 v1.89 人工交互与 a11y 矩阵", test_md)
        for marker in ["M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8", "空剪贴板", "换行追加", "VoiceOver", "wide-iPad"]:
            with self.subTest(marker=marker):
                self.assertIn(marker, test_md)
        self.assertIn("不得把未勾选项写成已验证", test_md)

    def test_debug_paste_inject_is_click_scoped_and_release_safe(self) -> None:
        source = read("AITRANS/Views/TextTranslationView.swift")
        self.assertIn("resolvedPasteText(from: items)", source)
        self.assertIn("AITRANS_UI_TEST_PASTE_TEXT", source)
        self.assertIn("#if DEBUG", source)
        self.assertIn("-AITRANS_UI_TEST_PASTE_TEXT", source)
        paste = re.search(
            r"private func pasteText\(_ items: \[String\]\) \{(?P<body>.*?)\n    \}",
            source,
            re.DOTALL,
        )
        self.assertIsNotNone(paste, "pasteText missing")
        body = paste.group("body")
        self.assertIn("resolvedPasteText", body)
        self.assertNotIn("store.submitDraft", body)
        resolver = re.search(
            r"private func resolvedPasteText\(from items: \[String\]\) -> String\? \{(?P<body>.*?)\n    \}",
            source,
            re.DOTALL,
        )
        self.assertIsNotNone(resolver, "resolvedPasteText missing")
        resolver_body = resolver.group("body")
        self.assertIn("items.first", resolver_body)
        self.assertIn("AITRANS_UI_TEST_PASTE_TEXT", resolver_body)
        # DEBUG inject must not run from lifecycle
        lifecycle_bodies = re.findall(
            r"\.(?:task|onAppear)\s*\{(?P<body>.*?)\n\s*\}",
            source,
            re.DOTALL,
        )
        for body in lifecycle_bodies:
            with self.subTest(body=body[:80]):
                self.assertNotIn("AITRANS_UI_TEST_PASTE_TEXT", body)
                self.assertNotIn("resolvedPasteText", body)
                self.assertNotIn("pasteText", body)
        button = read("AITRANS/Views/TextWorkspacePasteButton.swift")
        self.assertIn("PasteButton(payloadType: String.self, onPaste: onPaste)", button)

    def test_wide_ipad_evidence_is_required(self) -> None:
        capture = read("scripts/capture-ui-evidence.sh")
        self.assertIn("wide-iPad", capture)
        self.assertIn("text-empty-wide-ipad-day.png", capture)
        self.assertIn('productFamily") == "iPad"', capture)
        self.assertIn("Expected 13 screenshots", capture)
        self.assertIn('item["device"] == "wide-iPad"', capture)
        self.assertRegex(
            capture,
            r'capture "\$wide_id" "wide-iPad" empty large portrait text-empty-wide-ipad-day\.png false 日间',
        )

    def test_ci_wires_v189_contract_with_task_scoped_ui_evidence(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        self.assertIn("scripts/test-v189-paste-manual-matrix-contract.py", workflow)
        self.assertIn("v189-paste-manual-matrix-contract", workflow)
        self.assertIn("v189PasteManualMatrixContractOutcome", workflow)
        self.assertIn(
            "if: steps.ci_scope.outputs.paste_matrix_contract_required == 'true'",
            workflow,
        )
        self.assertIn("steps.ci_scope.outputs.ui_evidence_required == 'true'", workflow)
        self.assertNotIn("startsWith(github.ref_name, 'codeb/v1.89-')", workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
