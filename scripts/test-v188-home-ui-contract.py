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
        self.assertIn("TextWorkspacePasteButton(onPaste: pasteText)", source)
        button = read("AITRANS/Views/TextWorkspacePasteButton.swift")
        self.assertIn("PasteButton(payloadType: String.self, onPaste: onPaste)", button)
        self.assertIn(".foregroundStyle(.clear)", button)
        self.assertIn('Label("粘贴", systemImage: "doc.on.clipboard")', button)
        self.assertIn("Color.appSurfaceRaised", button)
        self.assertIn(".allowsHitTesting(false)", button)
        self.assertIn(r"@Environment(\.isEnabled)", button)
        self.assertNotIn('Label("Paste"', button)
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
        scroll_start = source.index("ScrollView {")
        scroll_end = source.index(".scrollDismissesKeyboard(.interactively)")
        header_inset = source.index(".safeAreaInset(edge: .top, spacing: 0)")
        header = source.index("AppPageHeader(")
        self.assertLess(scroll_start, scroll_end)
        self.assertLess(scroll_end, header_inset)
        self.assertLess(header_inset, header)
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

    def test_compact_layout_adapts_floating_tab_bar_clearance_to_dynamic_type(self) -> None:
        source = read("AITRANS/Views/TextTranslationView.swift")
        theme = read("AITRANS/Views/AppTheme.swift")
        self.assertIn("@Environment(\\.horizontalSizeClass)", source)
        self.assertIn("@Environment(\\.dynamicTypeSize)", source)
        self.assertIn("VStack(spacing: 0) {\n            ScrollView {", source)
        scroll_start = source.index("ScrollView {")
        scroll_modifier = source.index(".scrollDismissesKeyboard(.interactively)")
        spacer = source.index("if horizontalSizeClass == .compact && dynamicTypeSize >= .xxLarge")
        toolbar = source.index(".toolbar {")
        self.assertLess(scroll_start, scroll_modifier)
        self.assertLess(scroll_modifier, spacer)
        self.assertLess(spacer, toolbar)
        self.assertIn(".frame(height: AppTheme.Layout.floatingTabBarClearance)", source)
        self.assertIn("static let floatingTabBarClearance: CGFloat = 48", theme)
        self.assertIn('title: store.isProcessing ? "翻译中" : "翻译"', source)
        self.assertNotIn("if horizontalSizeClass == .compact {", source)
        self.assertNotIn(".safeAreaInset(edge: .bottom", source)
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
