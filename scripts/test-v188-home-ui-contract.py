#!/usr/bin/env python3
"""Static contracts for the v1.88 text translation workspace."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class V188HomeUIContractTests(unittest.TestCase):
    def test_paste_is_explicit_plain_text_and_appends_existing_input(self) -> None:
        source = read("AITRANS/Views/TextTranslationView.swift")
        self.assertIn("PasteButton(payloadType: String.self, onPaste: pasteText)", source)
        self.assertIn(".buttonStyle(TextWorkspacePasteButtonStyle())", source)
        style = read("AITRANS/Views/TextWorkspacePasteButtonStyle.swift")
        self.assertIn('Label("粘贴", systemImage: "doc.on.clipboard")', style)
        self.assertIn(r"@Environment(\.isEnabled)", style)
        self.assertNotIn('Label("Paste"', style)
        paste = re.search(
            r"private func pasteText\(_ items: \[String\]\) \{(?P<body>.*?)\n    \}",
            source,
            re.DOTALL,
        )
        self.assertIsNotNone(paste, "plain-text paste handler is missing")
        body = paste.group("body")
        self.assertIn("store.draftText = text", body)
        self.assertIn('store.draftText += "\\n\\(text)"', body)
        self.assertIn("guard let text = items.first, !text.isEmpty", body)
        self.assertNotIn("store.submitDraft", body)

    def test_clipboard_is_not_read_from_lifecycle_hooks(self) -> None:
        source = read("AITRANS/Views/TextTranslationView.swift")
        lifecycle_bodies = re.findall(
            r"\.(?:task|onAppear)\s*\{(?P<body>.*?)\n\s*\}",
            source,
            re.DOTALL,
        )
        for body in lifecycle_bodies:
            with self.subTest(body=body[:80]):
                self.assertNotIn("UIPasteboard", body)
                self.assertNotIn("pasteText", body)

    def test_keyboard_has_done_action_and_translation_dismisses_first(self) -> None:
        source = read("AITRANS/Views/TextTranslationView.swift")
        self.assertIn("ToolbarItemGroup(placement: .keyboard)", source)
        self.assertIn('Button("完成", action: dismissKeyboard)', source)
        dismiss = re.search(
            r"private func dismissKeyboard\(\) \{(?P<body>.*?)\n    \}",
            source,
            re.DOTALL,
        )
        self.assertIsNotNone(dismiss, "keyboard dismissal helper is missing")
        self.assertIn("inputFocused = false", dismiss.group("body"))

        submit = re.search(
            r"private func submitTranslation\(\) \{(?P<body>.*?)\n    \}",
            source,
            re.DOTALL,
        )
        self.assertIsNotNone(submit, "translation action is missing")
        body = submit.group("body")
        self.assertLess(body.index("inputFocused.wrappedValue = false"), body.index("store.submitDraft()"))

    def test_header_remains_outside_scroll_and_background_is_home_only(self) -> None:
        source = read("AITRANS/Views/TextTranslationView.swift")
        scroll_body = re.search(
            r"ScrollView\s*\{(?P<body>.*?)\n        \}\n        \.scrollDismissesKeyboard",
            source,
            re.DOTALL,
        )
        self.assertIsNotNone(scroll_body, "text workspace scroll view is missing")
        self.assertNotIn("AppPageHeader(", scroll_body.group("body"))
        self.assertIn("TextWorkspaceBackground().ignoresSafeArea()", source)
        background = read("AITRANS/Views/TextWorkspaceBackground.swift")
        self.assertIn("Canvas", background)
        self.assertIn("drawGrid", background)
        self.assertIn("drawTranslationPath", background)
        self.assertIn(".accessibilityHidden(true)", background)

        other_views = [
            "ImageTranslationViews.swift",
            "AudioTranslationView.swift",
            "HistoryView.swift",
            "PromptLibraryView.swift",
            "SettingsView.swift",
            "ModelManagementView.swift",
            "ProFeatureViews.swift",
            "DeveloperConsoleView.swift",
        ]
        for name in other_views:
            with self.subTest(view=name):
                self.assertNotIn("TextWorkspaceBackground", read(f"AITRANS/Views/{name}"))

    def test_compact_layout_reserves_floating_tab_bar_clearance(self) -> None:
        source = read("AITRANS/Views/TextTranslationView.swift")
        theme = read("AITRANS/Views/AppTheme.swift")
        self.assertIn("@Environment(\\.horizontalSizeClass)", source)
        self.assertRegex(
            source,
            r"(?s)\.safeAreaInset\(edge: \.bottom, spacing: 0\).*?horizontalSizeClass == \.compact.*?AppTheme\.Layout\.floatingTabBarClearance",
        )
        self.assertIn("static let floatingTabBarClearance: CGFloat = 88", theme)
        self.assertNotIn(".padding(.bottom, 72)", source)

    def test_required_home_actions_remain_wired(self) -> None:
        source = read("AITRANS/Views/TextTranslationView.swift")
        for needle in [
            "store.submitDraft()",
            "store.swapLanguages",
            "store.selectTargetLanguage(language)",
            "store.startNewSession()",
            "store.archiveCurrentSession()",
            "selectedTab = .settings",
        ]:
            with self.subTest(action=needle):
                self.assertIn(needle, source)

    def test_actions_have_non_color_identity_and_accessible_targets(self) -> None:
        source = read("AITRANS/Views/TextTranslationView.swift")
        self.assertIn('accessibilityLabel("粘贴剪贴板文本")', source)
        self.assertIn('systemImage: "text.badge.star"', source)
        self.assertIn('systemImage: "arrow.right.circle.fill"', source)
        self.assertIn('Button("交换语言", systemImage: "arrow.left.arrow.right"', source)
        self.assertGreaterEqual(source.count("AppTheme.Layout.minimumTarget"), 5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
