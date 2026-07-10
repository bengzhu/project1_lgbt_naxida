#!/usr/bin/env python3
"""Static contract tests for the Speech state machine and cloud bundle lookup."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class SpeechRecognitionContractTests(unittest.TestCase):
    def test_audio_state_covers_recognition_and_translation(self) -> None:
        models = read("AITRANS/Models/TranscriptModels.swift")
        match = re.search(
            r"enum AudioRecognitionState[^\{]*\{(?P<body>.*?)\n\}",
            models,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "AudioRecognitionState is missing")
        cases = set(re.findall(r"\bcase\s+(\w+)", match.group("body")))
        self.assertEqual(
            cases,
            {"idle", "checking", "recognizing", "translating", "translated", "failed"},
        )

    def test_run_summary_keeps_required_diagnostics(self) -> None:
        models = read("AITRANS/Models/TranscriptModels.swift")
        required_fields = {
            "mode",
            "inputName",
            "localeIdentifier",
            "requiresOnDeviceRecognition",
            "supportsOnDeviceRecognition",
            "startedAt",
            "completedAt",
            "transcriptPreview",
            "wordCount",
            "segmentCount",
            "averageConfidence",
            "isFinal",
            "failureMessage",
        }
        match = re.search(
            r"struct SpeechRecognitionRunSummary[^\{]*\{(?P<body>.*?)\n\}",
            models,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "SpeechRecognitionRunSummary is missing")
        fields = set(re.findall(r"\bvar\s+(\w+)\s*:", match.group("body")))
        self.assertTrue(required_fields.issubset(fields), required_fields - fields)

    def test_async_callbacks_are_scoped_to_a_run_id(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertIn("private var speechRecognitionRunID = UUID()", store)
        self.assertGreaterEqual(
            store.count("guard self.speechRecognitionRunID == runID else { return }"),
            4,
        )
        self.assertIn("private func invalidateSpeechRecognitionRun()", store)
        self.assertIn("audioRecognitionState = .translating", store)

    def test_ui_exposes_summary_and_cancellation(self) -> None:
        content = read("AITRANS/Views/ContentView.swift")
        pro_views = read("AITRANS/Views/ProFeatureViews.swift")
        self.assertIn("store.cancelAudioRecognition()", content)
        self.assertIn("case .translating: \"翻译中\"", content)
        self.assertIn("struct SpeechRecognitionRunSummaryPanel: View", pro_views)
        self.assertIn("summary.inputName", pro_views)
        self.assertIn("summary.averageConfidence", pro_views)

    def test_probe_uses_the_built_app_bundle_identifier(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        project = read("AITRANS.xcodeproj/project.pbxproj")
        bundle_ids = set(
            re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", project)
        )
        marketing_versions = set(
            re.findall(r"MARKETING_VERSION = ([^;]+);", project)
        )
        self.assertEqual(bundle_ids, {"com.local.aitransform114"})
        self.assertEqual(marketing_versions, {"1.86"})
        self.assertNotIn("BUNDLE_ID: com.local.aitrans\n", workflow)
        self.assertIn("Print :CFBundleIdentifier", workflow)
        self.assertIn("steps.simulator_build.outputs.bundle_id", workflow)
        self.assertIn('elif [[ "$branch" =~ ^([0-9]+(\\.[0-9]+)*)$ ]]', workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
