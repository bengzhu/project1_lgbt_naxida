#!/usr/bin/env python3
"""Static contracts for the v3.400 immersive visual system and navigation."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class V3400ImmersiveUIContractTests(unittest.TestCase):
    def test_phone_navigation_has_five_clear_primary_destinations(self) -> None:
        content = read("AITRANS/Views/ContentView.swift")
        self.assertIn(
            "static let phoneTabs: [AppTab] = [.text, .image, .ocr, .audio, .library]",
            content,
        )
        self.assertIn("ForEach(AppTab.phoneTabs)", content)
        self.assertNotIn("ForEach(AppTab.allCases)", content)
        self.assertIn("LibraryHubView(selectedTab: $selectedTab)", content)
        self.assertIn('title: "历史"', content)
        self.assertIn('title: "设置"', content)

    def test_tablet_navigation_exposes_task_groups(self) -> None:
        content = read("AITRANS/Views/ContentView.swift")
        for group in [
            '("创作", [.text, .image, .audio])',
            '("工具", [.ocr])',
            '("资料", [.history, .settings])',
        ]:
            self.assertIn(group, content)
        self.assertIn("ForEach(AppTab.tabletSections", content)
        self.assertIn(".accessibilityAddTraits(selectedTab == tab ? .isSelected : [])", content)

    def test_visual_identity_is_semantic_and_not_color_only(self) -> None:
        theme = read("AITRANS/Views/AppTheme.swift")
        components = read("AITRANS/Views/AppComponents.swift")
        for feature in ["text", "image", "ocr", "audio", "library", "settings"]:
            self.assertIn(f"case {feature}", theme)
        self.assertIn("var eyebrow: String", theme)
        self.assertIn("var index: String", theme)
        self.assertIn("var symbol: String", theme)
        self.assertIn("func accent(for colorScheme: ColorScheme)", theme)
        self.assertIn("Text(feature.index)", components)
        self.assertIn("Text(feature.eyebrow)", components)
        self.assertIn("Image(systemName: systemImage)", components)
        self.assertIn("@Environment(\\.colorSchemeContrast)", components)

    def test_hero_motion_respects_accessibility(self) -> None:
        components = read("AITRANS/Views/AppComponents.swift")
        self.assertIn("@Environment(\\.accessibilityReduceMotion)", components)
        self.assertIn("@Environment(\\.appReduceMotionOverride)", components)
        self.assertIn("if shouldReduceMotion", components)
        self.assertIn("withAnimation(AppTheme.Motion.reveal)", components)

    def test_primary_pages_declare_distinct_features(self) -> None:
        contracts = {
            "TextTranslationView.swift": "feature: .text",
            "ImageTranslationViews.swift": "feature: .image",
            "ImageOCRDetectionView.swift": "feature: .ocr",
            "AudioTranslationView.swift": "feature: .audio",
            "HistoryView.swift": "feature: .library",
            "SettingsView.swift": "feature: .settings",
        }
        for filename, needle in contracts.items():
            with self.subTest(filename=filename):
                self.assertIn(needle, read(f"AITRANS/Views/{filename}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
