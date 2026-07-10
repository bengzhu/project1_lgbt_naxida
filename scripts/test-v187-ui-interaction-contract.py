#!/usr/bin/env python3
"""Static interaction contracts paired with v1.87 runtime UI evidence."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class V187UIInteractionContractTests(unittest.TestCase):
    def test_live_speech_has_default_accessibility_toggle(self) -> None:
        audio = read("AITRANS/Views/AudioTranslationView.swift")
        self.assertRegex(audio, r"\.accessibilityAction\s*\{\s*toggleAccessibleCapture\(\)")
        toggle = re.search(
            r"private func toggleAccessibleCapture\(\) \{(?P<body>.*?)\n    \}",
            audio,
            re.DOTALL,
        )
        self.assertIsNotNone(toggle, "accessible speech toggle is missing")
        self.assertIn("store.beginProLiveSpeechCapture()", toggle.group("body"))
        self.assertIn("store.endProLiveSpeechCapture()", toggle.group("body"))

    def test_developer_navigation_resets_when_access_is_disabled(self) -> None:
        settings = read("AITRANS/Views/SettingsView.swift")
        content = read("AITRANS/Views/ContentView.swift")
        self.assertIn("@State private var navigationPath = NavigationPath()", settings)
        self.assertIn("NavigationStack(path: $navigationPath)", settings)
        self.assertIn(".onChange(of: store.isDeveloperModeEnabled)", settings)
        self.assertIn("navigationPath = NavigationPath()", settings)
        self.assertNotIn("selectedTab = .settings\n            }\n        }", content)

    def test_reduce_motion_scenario_enters_capturing_branch(self) -> None:
        scenarios = read("AITRANS/Views/AppPreviewSupport.swift")
        audio = read("AITRANS/Views/AudioTranslationView.swift")
        capture = read("scripts/capture-ui-evidence.sh")
        scenario = re.search(
            r"case \.audioRecognizing:(?P<body>.*?)case \.audioFailure:",
            scenarios,
            re.DOTALL,
        )
        self.assertIsNotNone(scenario, "audioRecognizing scenario is missing")
        self.assertIn("store.isCapturingProSpeech = true", scenario.group("body"))
        self.assertIn("store.isCapturingProSpeech && !shouldReduceMotion", audio)
        self.assertRegex(capture, r"audioRecognizing\s+large\s+portrait\s+\S+\s+true\s+夜间")

    def test_runtime_evidence_covers_required_workflows(self) -> None:
        capture = read("scripts/capture-ui-evidence.sh")
        required_scenarios = {
            "textSuccess",
            "imageEmpty",
            "history",
            "promptLibrary",
            "localMissing",
            "audioRecognizing",
            "proLocked",
            "developerConsole",
        }
        captured = set(
            re.findall(r'^capture\s+"\$small_id"\s+"compact-iPhone"\s+(\w+)', capture, re.MULTILINE)
        )
        self.assertTrue(required_scenarios.issubset(captured), required_scenarios - captured)

    def test_required_workflow_actions_remain_wired(self) -> None:
        contracts = {
            "AITRANS/Views/TextTranslationView.swift": [
                "store.submitDraft",
                "store.swapLanguages",
                "store.selectTargetLanguage(language)",
                "store.startNewSession()",
            ],
            "AITRANS/Views/HistoryView.swift": [
                "store.loadSession(record)",
                "store.deleteSession(pendingDeletion)",
                "store.importSnapshot(from: url)",
                "store.exportSnapshot()",
                "store.clearHistory()",
            ],
            "AITRANS/Views/PromptLibraryView.swift": [
                "store.selectPrompt(prompt)",
                "store.createPrompt(",
                "store.updatePrompt(",
                "store.duplicatePrompt(prompt)",
                "store.deletePrompt(pendingDeletion)",
            ],
            "AITRANS/Views/ModelManagementView.swift": [
                "store.selectEngine($0)",
                "store.downloadBuiltInModel",
                "store.importLocalModel(from: url)",
                "store.removeLocalModel",
            ],
            "AITRANS/Views/ImageTranslationViews.swift": [
                "store.translateImage(from: url)",
                "store.cancelImageTranslation",
                "store.retryImageTranslation",
                "store.imageTranslationExportURL",
            ],
            "AITRANS/Views/AudioTranslationView.swift": [
                "store.recognizeAudioFileAndTranslate(from: url)",
                "store.cancelAudioRecognition()",
                "store.translateProLiveTranscript",
            ],
            "AITRANS/Views/ProFeatureViews.swift": [
                "store.purchaseProSubscription",
                "store.refreshProEntitlements",
                "store.activateProForDevelopment",
            ],
            "AITRANS/Views/DeveloperConsoleView.swift": [
                "store.runDeveloperRawProbe",
                "store.runDeveloperRawProbeSuite",
                "store.runMangaOverlayProbe",
                "store.disableDeveloperMode",
            ],
        }
        for relative_path, required in contracts.items():
            source = read(relative_path)
            with self.subTest(path=relative_path):
                missing = [needle for needle in required if needle not in source]
                self.assertEqual(missing, [], f"unwired workflow actions in {relative_path}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
