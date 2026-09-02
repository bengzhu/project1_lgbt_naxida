#!/usr/bin/env python3
"""Focused workspace and visual-task CI contracts for v3.401."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class FocusedWorkspaceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = read("AITRANS/Views/TextTranslationView.swift")
        cls.audio = read("AITRANS/Views/AudioTranslationView.swift")
        cls.history = read("AITRANS/Views/HistoryView.swift")
        cls.settings = read("AITRANS/Views/SettingsView.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")

    def test_text_keeps_primary_session_action_and_moves_archive_to_menu(self) -> None:
        self.assertIn("TextSessionUtilityBar", self.text)
        self.assertIn('Menu("会话操作"', self.text)
        self.assertIn("store.startNewSession()", self.text)
        self.assertIn("store.archiveCurrentSession()", self.text)
        self.assertNotIn("RecentTranslationList", self.text)

    def test_compact_audio_presents_one_input_workspace_at_a_time(self) -> None:
        for token in (
            "AudioWorkspaceMode",
            "horizontalSizeClass == .regular",
            'Picker("音频输入方式"',
            "workspaceMode == .live",
            "SpeechCapabilityDisclosure",
            "if store.isDeveloperModeEnabled",
        ):
            self.assertIn(token, self.audio)
        self.assertIn("shouldReduceMotion ? nil : AppTheme.Motion.standard", self.audio)
        self.assertIn("reduceMotion || reduceMotionOverride", self.audio)

    def test_history_secondary_commands_are_grouped_without_losing_actions(self) -> None:
        self.assertIn('Menu("历史操作"', self.history)
        for action in (
            "action: store.archiveCurrentSession",
            "showImporter = true",
            "action: prepareExport",
            "showClearConfirmation = true",
        ):
            self.assertIn(action, self.history)
        self.assertIn('.accessibilityLabel("历史操作")', self.history)

    def test_settings_advanced_content_is_progressively_disclosed(self) -> None:
        for token in (
            "SettingsAdvancedSection",
            "DisclosureGroup(isExpanded: $isExpanded)",
            "ProFeatureGrid()",
            "DeveloperAccessSection(password: $password)",
        ):
            self.assertIn(token, self.settings)
        self.assertIn("store.unlockDeveloperMode(password: password)", self.settings)
        self.assertIn("store.disableDeveloperMode", self.settings)

    def test_visual_ci_route_is_bounded_and_keeps_direct_ui_contracts(self) -> None:
        for token in (
            "visual_task_scoped=false",
            "visual_task_scoped=true",
            "grep -Ev",
            "AITRANS/Views/(TextTranslationView|AudioTranslationView|HistoryView|SettingsView)",
            'if [ "$visual_task_scoped" = "true" ]; then',
            "ui_interaction_contract_required=false",
            "home_ui_contract_required=true",
            "paste_matrix_contract_required=true",
            "koharu_contract_required=false",
            "scripts/test-v187-ui-interaction-contract.py",
            "scripts/test-v188-home-ui-contract.py",
            "scripts/test-v3400-immersive-ui-contract.py",
            "scripts/test-v3401-focused-workspaces-contract.py",
        ):
            self.assertIn(token, self.workflow)


if __name__ == "__main__":
    unittest.main()
