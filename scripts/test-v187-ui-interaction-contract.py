#!/usr/bin/env python3
"""Static interaction contracts paired with v1.87 runtime UI evidence."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing function signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unterminated function body: {signature}")


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
            r"case \.audioRecognizing:(?P<body>.*?)case \.audioTranslating:",
            scenarios,
            re.DOTALL,
        )
        self.assertIsNotNone(scenario, "audioRecognizing scenario is missing")
        self.assertIn("store.isCapturingProSpeech = true", scenario.group("body"))
        self.assertIn("store.isCapturingProSpeech && !shouldReduceMotion", audio)
        self.assertRegex(capture, r"audioRecognizing\s+large\s+portrait\s+\S+\s+true\s+夜间")

    def test_translating_scenario_captures_cancel_state(self) -> None:
        scenarios = read("AITRANS/Views/AppPreviewSupport.swift")
        capture = read("scripts/capture-ui-evidence.sh")
        scenario = re.search(
            r"case \.audioTranslating:(?P<body>.*?)case \.audioFailure:",
            scenarios,
            re.DOTALL,
        )
        self.assertIsNotNone(scenario, "audioTranslating scenario is missing")
        body = scenario.group("body")
        self.assertIn("store.isProcessing = true", body)
        self.assertIn("store.proLiveTranscriptText", body)
        self.assertIn("store.audioRecognitionState = .translating", body)
        self.assertRegex(
            capture,
            r"audioTranslating\s+large\s+portrait\s+audio-translating-compact-night\.png\s+false\s+夜间",
        )

    def test_keyboard_header_stays_outside_automatic_scroll(self) -> None:
        text_view = read("AITRANS/Views/TextTranslationView.swift")
        scroll_start = text_view.index("ScrollView {")
        scroll_end = text_view.index(".scrollDismissesKeyboard(.interactively)")
        header_inset = text_view.index(".safeAreaInset(edge: .top, spacing: 0)")
        header = text_view.index("AppPageHeader(")
        self.assertLess(scroll_start, scroll_end)
        self.assertLess(scroll_end, header_inset)
        self.assertLess(header_inset, header)
        self.assertRegex(text_view, r"\.safeAreaInset\(edge: \.top, spacing: 0\)\s*\{\s*AppPageHeader\(")
        self.assertIn(".background(Color.appCanvas)", text_view)

    def test_runtime_evidence_covers_required_workflows(self) -> None:
        capture = read("scripts/capture-ui-evidence.sh")
        required_scenarios = {
            "textSuccess",
            "imageEmpty",
            "history",
            "promptLibrary",
            "localMissing",
            "audioRecognizing",
            "audioTranslating",
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
                "store.beginImageFileSelection()",
                "store.handleSelectedImageFile(result, selectionID: selectionID)",
                "store.translateImageTransfer(",
                "store.selectImageTargetLanguage(language)",
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

    def test_image_target_language_control_uses_store_and_retries_completed_images(self) -> None:
        image = read("AITRANS/Views/ImageTranslationViews.swift")
        store = read("AITRANS/Services/TranslationSessionStore.swift")

        self.assertIn("ImageTargetLanguageControl()", image)
        self.assertIn("store.availableTargetLanguages", image)
        self.assertIn("store.selectImageTargetLanguage(language)", image)
        self.assertGreaterEqual(image.count("store.imageTranslationDisplayedTargetLanguage"), 4)
        self.assertIn("已完成的图片会重新翻译", image)

        selector = re.search(
            r"func selectImageTargetLanguage\(_ language: SupportedLanguage\) \{(?P<body>.*?)\n    \}",
            store,
            re.DOTALL,
        )
        self.assertIsNotNone(selector, "image target language selector is missing")
        self.assertIn("selectTargetLanguage(language)", selector.group("body"))
        self.assertIn("imageTranslationState == .translated", selector.group("body"))
        self.assertIn("imageTranslationContentTargetLanguage != language", selector.group("body"))
        self.assertNotIn("guard language != targetLanguage else", selector.group("body"))
        self.assertIn("retryImageTranslation()", selector.group("body"))

        self.assertIn(
            "imageTranslationContentTargetLanguage = targetLanguage",
            store,
        )

    def test_image_content_language_survives_failure_and_cancel_until_content_is_cleared(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")

        displayed_language = re.search(
            r"var imageTranslationDisplayedTargetLanguage: SupportedLanguage \{(?P<body>.*?)\n    \}",
            store,
            re.DOTALL,
        )
        self.assertIsNotNone(displayed_language, "image displayed target language is missing")
        self.assertIn("imageTranslationData != nil", displayed_language.group("body"))
        self.assertIn("!imageTranslationBlocks.isEmpty", displayed_language.group("body"))
        self.assertRegex(
            displayed_language.group("body"),
            r"case \.idle, \.translated, \.failed:",
        )

        finish = re.search(
            r"private func finishImageTranslation\(taskID: UUID, with error: Error\) \{(?P<body>.*?)\n    \}",
            store,
            re.DOTALL,
        )
        empty_ocr = re.search(
            r"guard !recognizedBlocks\.isEmpty else \{(?P<body>.*?)\n        \}",
            store,
            re.DOTALL,
        )
        cancel = re.search(
            r"func cancelImageTranslation\(\) \{(?P<body>.*?)\n    \}",
            store,
            re.DOTALL,
        )
        clear = re.search(
            r"func clearImageTranslation\(\) \{(?P<body>.*?)\n    \}",
            store,
            re.DOTALL,
        )
        self.assertIsNotNone(finish, "image translation finish handler is missing")
        self.assertIsNotNone(empty_ocr, "empty OCR failure handler is missing")
        self.assertIsNotNone(cancel, "image translation cancel handler is missing")
        self.assertIsNotNone(clear, "image translation clear handler is missing")
        self.assertNotIn("imageTranslationContentTargetLanguage = nil", finish.group("body"))
        self.assertNotIn("imageTranslationContentTargetLanguage = nil", empty_ocr.group("body"))
        self.assertNotIn("imageTranslationContentTargetLanguage = nil", cancel.group("body"))
        self.assertIn("imageTranslationContentTargetLanguage = nil", clear.group("body"))

    def test_image_loading_uses_fixed_task_language_before_image_data_arrives(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")

        begin = re.search(
            r"private func beginImageTranslationTask\((?P<body>.*?)\n    \}",
            store,
            re.DOTALL,
        )
        displayed_language = re.search(
            r"var imageTranslationDisplayedTargetLanguage: SupportedLanguage \{(?P<body>.*?)\n    \}",
            store,
            re.DOTALL,
        )
        self.assertIsNotNone(begin, "image translation task initializer is missing")
        self.assertIsNotNone(displayed_language, "image displayed target language is missing")
        self.assertLess(
            begin.group("body").index("imageTranslationContentTargetLanguage = targetLanguage"),
            begin.group("body").index("imageTranslationState = .loading"),
        )

        running_case = re.search(
            r"case \.loading, \.recognizing, \.translating:(?P<body>.*?)"
            r"case \.idle, \.translated, \.failed:",
            displayed_language.group("body"),
            re.DOTALL,
        )
        self.assertIsNotNone(running_case, "running image task language branch is missing")
        self.assertIn(
            "return imageTranslationContentTargetLanguage ?? targetLanguage",
            running_case.group("body"),
        )
        self.assertNotIn("imageTranslationData", running_case.group("body"))
        self.assertNotIn("imageTranslationBlocks", running_case.group("body"))

    def test_image_export_uses_top_left_coordinates_and_selected_mode(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")

        renderer = re.search(
            r"nonisolated private static func renderImageTranslationOverlay\((?P<body>.*?)"
            r"\n    nonisolated private static func publishImageTranslationOverlay",
            store,
            re.DOTALL,
        )
        self.assertIsNotNone(renderer, "image export renderer is missing")
        body = renderer.group("body")
        self.assertIn("mode: ImageTranslationOverlayMode", body)
        self.assertIn("renderID: UUID", body)
        self.assertIn("UIGraphicsImageRenderer", body)
        self.assertIn("y: canvas.height * box.y", store)
        self.assertIn("guard mode == .adjacent else { return sourceRect }", store)
        self.assertIn("mode == .adjacent", body)
        self.assertIn("renderID.uuidString", body)
        self.assertIn(".staging.png", body)
        self.assertNotIn("CGImageDestinationCreateWithURL", body)
        self.assertNotIn('appendingPathComponent("\\(baseName)-translated.png")', body)

    def test_image_overlay_mode_rerenders_without_stale_export(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        image = read("AITRANS/Views/ImageTranslationViews.swift")

        setter = re.search(
            r"func setImageOverlayMode\(_ mode: ImageTranslationOverlayMode\) "
            r"\{(?P<body>.*?)\n    \}",
            store,
            re.DOTALL,
        )
        rerender = re.search(
            r"private func rerenderImageTranslationExport\(\) \{(?P<body>.*?)"
            r"\n    \}\n\n    func retryImageTranslation",
            store,
            re.DOTALL,
        )
        self.assertIsNotNone(setter, "overlay mode setter is missing")
        self.assertIsNotNone(rerender, "overlay export rerender path is missing")
        self.assertIn("rerenderImageTranslationExport()", setter.group("body"))
        self.assertIn("discardImageTranslationExport()", rerender.group("body"))
        self.assertNotIn("imageTranslationExportURL = nil", rerender.group("body"))
        discard = function_body(store, "private func discardImageTranslationExport()")
        self.assertIn("imageTranslationExportURL = nil", discard)
        self.assertIn("removeImageTranslationManagedExport", discard)
        self.assertLess(
            discard.index("imageTranslationExportURL = nil"),
            discard.index("removeImageTranslationManagedExport"),
        )
        self.assertIn("imageOverlayRenderID == renderID", rerender.group("body"))
        self.assertIn("imageTranslationTaskID == contentTaskID", rerender.group("body"))
        self.assertIn("imageOverlayMode == mode", rerender.group("body"))
        self.assertLess(
            rerender.group("body").index("imageOverlayRenderID == renderID"),
            rerender.group("body").index("publishImageTranslationOverlay("),
            "stable export must only be published after stale-render identity checks",
        )
        self.assertIn(
            "self.removeImageTranslationStagingFile(stagedURL, directory: directory)",
            rerender.group("body"),
        )
        publisher = function_body(
            store,
            "nonisolated private static func publishImageTranslationOverlay(",
        )
        self.assertIn('"aitrans-export-\\(renderID.uuidString)-\\(baseName)-translated.png"', publisher)
        self.assertIn("replaceItemAt(outputURL, withItemAt: stagedURL)", publisher)
        initial_pipeline = re.search(
            r"private func runImageTranslationPipeline\((?P<body>.*?)"
            r"\n    private func finishImageTranslation",
            store,
            re.DOTALL,
        )
        self.assertIsNotNone(initial_pipeline, "initial image pipeline is missing")
        self.assertRegex(
            initial_pipeline.group("body"),
            r"defer\s*\{\s*removeImageTranslationStagingFile\(\s*"
            r"stagedExportURL,\s*directory:\s*imageTranslationDirectory\s*\)\s*\}",
            "failed initial publication must not leave a staging PNG",
        )
        self.assertIn(
            ".disabled(store.imageTranslationData == nil || isRunning)",
            image,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
