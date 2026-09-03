#!/usr/bin/env python3
"""Direct contracts for the v3.402 compact header and settings navigation fix."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class CompactHeaderSettingsContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.theme = read("AITRANS/Views/AppTheme.swift")
        cls.components = read("AITRANS/Views/AppComponents.swift")
        cls.content = read("AITRANS/Views/ContentView.swift")
        cls.settings = read("AITRANS/Views/SettingsView.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")

    def test_shared_header_has_one_compact_full_width_metric(self) -> None:
        self.assertIn("static let pageHeaderHeight: CGFloat = 92", self.theme)
        self.assertIn(
            ".frame(maxWidth: .infinity, minHeight: AppTheme.Layout.pageHeaderHeight, alignment: .leading)",
            self.components,
        )
        self.assertIn(".font(.title2.weight(.black))", self.components)
        self.assertIn(".frame(width: 48, height: 48)", self.components)
        self.assertIn("textStyle: .caption.bold()", self.components)
        self.assertNotIn(".font(.largeTitle.weight(.black))", self.components)
        self.assertNotIn(".font(.system(size: 92, weight: .black", self.components)

    def test_compact_header_preserves_current_visual_and_accessibility_identity(self) -> None:
        for token in (
            "Text(feature.index)",
            "Text(feature.eyebrow)",
            "LinearGradient(",
            "@Environment(\\.colorSchemeContrast)",
            "contrast == .increased ? accent",
            "@Environment(\\.accessibilityReduceMotion)",
            "withAnimation(AppTheme.Motion.reveal)",
            ".minimumScaleFactor(0.82)",
        ):
            self.assertIn(token, self.components)

    def test_five_primary_pages_use_the_same_header_component(self) -> None:
        contracts = {
            "AITRANS/Views/TextTranslationView.swift": "feature: .text",
            "AITRANS/Views/ImageTranslationViews.swift": "feature: .image",
            "AITRANS/Views/ImageOCRDetectionView.swift": "feature: .ocr",
            "AITRANS/Views/AudioTranslationView.swift": "feature: .audio",
            "AITRANS/Views/ContentView.swift": "feature: .library",
        }
        for path, feature in contracts.items():
            source = read(path)
            with self.subTest(path=path):
                self.assertIn("AppPageHeader(", source)
                self.assertIn(feature, source)
        ocr = read("AITRANS/Views/ImageOCRDetectionView.swift")
        self.assertIn(".padding(.vertical, AppTheme.Spacing.section)", ocr)

    def test_text_header_scrolls_with_the_workspace(self) -> None:
        text = read("AITRANS/Views/TextTranslationView.swift")
        scroll_body = text[text.index("ScrollView {"):text.index(".scrollDismissesKeyboard")]
        self.assertLess(scroll_body.index("AppPageHeader("), scroll_body.index("LanguageControlBar()"))
        self.assertNotIn(".safeAreaInset(edge: .top", text)

    def test_library_destination_cards_use_compact_module_rows(self) -> None:
        self.assertIn(
            ".frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)",
            self.content,
        )
        self.assertIn(".appSurface(padded: false, accent: accent)", self.content)
        self.assertNotIn(".frame(maxWidth: .infinity, minHeight: 220", self.content)

    def test_library_settings_reuses_the_parent_navigation_stack(self) -> None:
        self.assertIn(
            """case .settings:
                    SettingsView(
                        selectedTab: $selectedTab,
                        isEmbeddedInNavigationStack: true
                    )""",
            self.content,
        )
        self.assertIn("let isEmbeddedInNavigationStack: Bool", self.settings)
        self.assertRegex(
            self.settings,
            r"if isEmbeddedInNavigationStack \{\s+settingsContent\s+\} else \{\s+NavigationStack\(path: \$navigationPath\)",
        )
        self.assertIn(".navigationDestination(for: SettingsDestination.self)", self.settings)

    def test_runtime_evidence_covers_all_five_primary_headers(self) -> None:
        capture = read("scripts/capture-ui-evidence.sh")
        scenarios = set(
            re.findall(r'^capture\s+"\$small_id"\s+"compact-iPhone"\s+(\w+)', capture, re.MULTILINE)
        )
        self.assertTrue({"empty", "imageEmpty", "ocrEmpty", "audioTranslating", "library"}.issubset(scenarios))
        self.assertIn("Expected 16 screenshots (14 compact iPhone + 2 wide iPad)", capture)
        self.assertIn("for attempt in 1 2 3", capture)
        self.assertIn("restarting App", capture)
        self.assertIn("Warming the compact App", capture)

    def test_ui_only_ci_skips_unrelated_suites_but_keeps_build(self) -> None:
        route = re.search(
            r'if \[ "\$visual_task_scoped" = "true" \]; then(?P<body>.*?)\n\s+fi',
            self.workflow,
            re.DOTALL,
        )
        self.assertIsNotNone(route)
        body = route.group("body")
        for token in (
            "ui_interaction_contract_required=false",
            "home_ui_contract_required=true",
            "paste_matrix_contract_required=false",
            "speech_contract_required=false",
            "koharu_contract_required=false",
        ):
            self.assertIn(token, body)
        self.assertIn("scripts/test-v3402-compact-header-settings-contract.py", self.workflow)
        self.assertIn("xcode_build_required=true", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
