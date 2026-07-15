#!/usr/bin/env python3
"""Static contract tests for the Speech state machine and cloud bundle lookup."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def swift_body(source: str, declaration: str) -> str:
    start = source.find(declaration)
    if start < 0:
        raise AssertionError(f"Swift declaration missing: {declaration}")
    opening_brace = source.find("{", start)
    if opening_brace < 0:
        raise AssertionError(f"Swift body missing: {declaration}")

    depth = 0
    for index in range(opening_brace, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[opening_brace + 1:index]
    raise AssertionError(f"Swift body is unbalanced: {declaration}")


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
            "runToken",
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

    def test_microphone_authorization_revalidates_run_after_await(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        body = swift_body(store, "func beginProLiveSpeechCapture()")
        permission_await = body.index(
            "let microphoneGranted = await self.requestMicrophoneAccess()"
        )
        run_guard = body.index(
            "guard self.speechRecognitionRunID == runID,", permission_await
        )
        permission_result = body.index("guard microphoneGranted else", permission_await)
        start_recognition = body.index(
            "self.startProLiveSpeechRecognition(capability: capability, runID: runID)"
        )
        self.assertLess(permission_await, run_guard)
        self.assertLess(run_guard, permission_result)
        self.assertLess(permission_result, start_recognition)

    def test_translation_awaits_revalidate_before_shared_state_writes(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")

        submit = swift_body(store, "private func submit(")
        submit_await = submit.index("let translation = try await translate(text)")
        submit_guard = submit.index(
            "guard isCurrentSpeechTranslation(expectedSpeechRunID) else", submit_await
        )
        transcript_write = submit.index("transcript.insert(line, at: 0)")
        self.assertLess(submit_await, submit_guard)
        self.assertLess(submit_guard, transcript_write)

        audio_file = swift_body(store, "private func startAudioFileTranslation(")
        file_await = audio_file.index("let didTranslate = await self.submit(")
        file_guard = audio_file.index(
            "guard !Task.isCancelled, self.speechRecognitionRunID == runID else",
            file_await,
        )
        file_state_write = audio_file.index("self.audioRecognitionState = .translated")
        self.assertLess(file_await, file_guard)
        self.assertLess(file_guard, file_state_write)

        live = swift_body(store, "func translateProLiveTranscript()")
        live_await = live.index("let translation = try await self.translate(text)")
        live_guard = live.index(
            "guard !Task.isCancelled, self.speechRecognitionRunID == runID else",
            live_await,
        )
        live_write = live.index("self.proLiveTranslationText = translation")
        self.assertLess(live_await, live_guard)
        self.assertLess(live_guard, live_write)

    def test_summary_await_revalidates_before_summary_write(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        body = swift_body(store, "private func refreshSummaryAfterTranslation(")
        summary_await = body.index("let refreshedSummary = try await summarize()")
        run_guard = body.index(
            "guard isCurrentSpeechTranslation(expectedSpeechRunID) else",
            summary_await,
        )
        summary_write = body.index("summary = refreshedSummary")
        self.assertLess(summary_await, run_guard)
        self.assertLess(run_guard, summary_write)

    def test_ui_exposes_summary_and_cancellation(self) -> None:
        audio_views = read("AITRANS/Views/AudioTranslationView.swift")
        pro_views = read("AITRANS/Views/ProFeatureViews.swift")
        self.assertIn("store.cancelAudioRecognition()", audio_views)
        self.assertIn("case .translating: \"翻译中\"", audio_views)
        self.assertIn("struct SpeechRecognitionRunSummaryPanel: View", pro_views)
        self.assertIn("summary.inputName", pro_views)
        self.assertIn("summary.averageConfidence", pro_views)


    def test_cancel_invalidates_run_before_idle_and_records_failure(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        body = swift_body(store, "func cancelAudioRecognition()")
        self.assertIn("invalidateSpeechRecognitionRun()", body)
        self.assertIn("speechTranslationTask?.cancel()", body)
        self.assertLess(
            body.index("invalidateSpeechRecognitionRun()"),
            body.index("speechTranslationTask?.cancel()"),
        )
        self.assertLess(
            body.index("speechTranslationTask?.cancel()"),
            body.index("audioRecognitionState = .idle"),
        )
        self.assertIn('failSpeechRecognitionRun("用户取消")', body)
        self.assertIn("audioRecognitionMessage = \"语音识别已取消\"", body)

    def test_new_run_cancels_stale_translation_before_replacing_run_id(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        body = swift_body(store, "private func beginSpeechRecognitionRun(")
        cancel = body.index("speechTranslationTask?.cancel()")
        clear = body.index("speechTranslationTask = nil")
        new_id = body.index("let runID = UUID()")
        self.assertLess(cancel, clear)
        self.assertLess(clear, new_id)

    def test_preview_and_store_summary_initializers_include_run_token(self) -> None:
        preview = read("AITRANS/Views/AppPreviewSupport.swift")
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertIn("runToken:", preview)
        self.assertIn("runToken: String(runID.uuidString.prefix(8))", store)

    def test_summary_panel_exposes_offline_capability_finality_and_run_token(self) -> None:
        pro_views = read("AITRANS/Views/ProFeatureViews.swift")
        self.assertIn('AppMetric(title: "离线"', pro_views)
        self.assertIn("summary.requiresOnDeviceRecognition", pro_views)
        self.assertIn("summary.supportsOnDeviceRecognition", pro_views)
        self.assertIn("summary.isFinal", pro_views)
        self.assertIn("summary.runToken", pro_views)
        self.assertIn("store.cancelAudioRecognition()", read("AITRANS/Views/AudioTranslationView.swift"))

    def test_translating_state_exposes_cancel_for_file_and_live_paths(self) -> None:
        audio_views = read("AITRANS/Views/AudioTranslationView.swift")
        can_cancel = swift_body(audio_views, "private var canCancel: Bool")
        self.assertIn("case .checking, .recognizing, .translating: true", can_cancel)
        live_panel = swift_body(audio_views, "private struct LiveSpeechPanel: View")
        self.assertIn("store.audioRecognitionState == .translating", live_panel)
        self.assertIn('title: "取消翻译"', live_panel)
        self.assertIn("action: store.cancelAudioRecognition", live_panel)
        file_actions = swift_body(audio_views, "@ViewBuilder private var actions: some View")
        cancel_action = file_actions.index("store.cancelAudioRecognition()")
        select_action = file_actions.index('AppPrimaryButton(title: "选择音频"')
        self.assertLess(cancel_action, select_action)
        self.assertIn(
            'store.audioRecognitionState == .translating ? "取消翻译" : "取消识别"',
            file_actions,
        )
        capture = read("scripts/capture-ui-evidence.sh")
        self.assertIn("audioTranslating", capture)
        self.assertIn("audio-translating-compact-night.png", capture)

    def test_speech_contract_runs_once_and_is_a_required_ci_gate(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        command = "python3 -B scripts/test-speech-recognition-contract.py"
        self.assertEqual(workflow.count(command), 1)
        self.assertIn("- name: Speech recognition contract", workflow)
        self.assertIn(
            "if: steps.ci_scope.outputs.speech_contract_required == 'true'",
            workflow,
        )
        required_gate = '[ "${{ steps.speech_contract.outcome }}" != "success" ]'
        self.assertGreaterEqual(workflow.count(required_gate), 2)

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
        self.assertEqual(marketing_versions, {"1.95"})
        self.assertNotIn("BUNDLE_ID: com.local.aitrans\n", workflow)
        self.assertIn("Print :CFBundleIdentifier", workflow)
        self.assertIn("steps.simulator_build.outputs.bundle_id", workflow)
        self.assertIn('elif [[ "$branch" =~ ^([0-9]+(\\.[0-9]+)*)$ ]]', workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
