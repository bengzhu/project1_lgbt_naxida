#!/usr/bin/env python3
"""Focused static contract for the Apple Translation engine integration."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class AppleTranslationEngineContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.adapter = read("AITRANS/Services/AppleTranslationService.swift")
        cls.host = read("AITRANS/Views/AppleTranslationTaskHost.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.settings = read("AITRANS/Views/ModelManagementView.swift")
        cls.content = read("AITRANS/Views/ContentView.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_four_user_visible_engines_are_exact_and_mock_stays_hidden(self) -> None:
        for marker in (
            "[本地] Apple Translation（系统原生）",
            "[本地] Gemma",
            "[预留] 浑元大模型",
            "[预留] 通义千问",
        ):
            self.assertIn(marker, self.models)
        all_cases = self.models.split("static let allCases: [ModelEngine] = [", 1)[1].split("\n    ]", 1)[0]
        for case in (".appleTranslation", ".local", ".hunyuan", ".qwen"):
            self.assertIn(case, all_cases)
        self.assertNotIn(".mock", all_cases)

    def test_settings_selection_uses_store_authority_and_persists(self) -> None:
        self.assertIn('Picker("翻译引擎", selection: engineBinding)', self.settings)
        self.assertIn("store.selectEngine($0)", self.settings)
        self.assertIn("func selectEngine(_ engine: ModelEngine)", self.store)
        self.assertIn("selectedEngine = engine", self.store)
        selected_engine = self.store.split("@Published var selectedEngine", 1)[1].split("@Published", 1)[0]
        self.assertIn("persist()", selected_engine)
        self.assertIn("settings.selectedEngine == .mock ? .local", self.store)
        self.assertIn("record.selectedEngine == .mock ? .local", self.store)

    def test_apple_adapter_uses_languages_availability_and_batch_identity(self) -> None:
        for marker in (
            "import Translation",
            "LanguageAvailability().status(from: source, to: target)",
            "session.prepareTranslation()",
            "session.translate(payload.sourceText)",
            "session.translate(batch: requests)",
            "clientIdentifier: $0.id",
            "response.clientIdentifier",
            'Locale.Language(identifier: "ja")',
            'Locale.Language(identifier: "zh-Hans")',
        ):
            self.assertIn(marker, self.adapter)

    def test_swiftui_session_lifecycle_restarts_same_language_jobs(self) -> None:
        self.assertIn("configuration.invalidate()", self.adapter)
        self.assertIn("invalidatesNextConfiguration.toggle()", self.adapter)
        self.assertIn(".translationTask(service.configuration)", self.host)
        self.assertIn("await service.runPendingJob(with: session)", self.host)
        self.assertIn("AppleTranslationTaskHost(service: store.appleTranslationService)", self.content)

    def test_store_routes_all_translation_calls_without_reserved_fallback(self) -> None:
        for marker in (
            "private func generateWithSelectedEngine",
            "appleTranslationService.generate(request)",
            "primary = localService",
            "ReservedTranslationService(engine: requestedEngine)",
            "if error is TranslationEngineRoutingError",
        ):
            self.assertIn(marker, self.store)
        self.assertIn("let result = try await generateWithSelectedEngine(request)", self.store)

    def test_image_translation_uses_system_result_validation_not_gemma_qa(self) -> None:
        batch = self.store.split("private func translateJapaneseImageBatch(", 1)[1].split(
            "private func japaneseTranslationQAConfiguration(", 1
        )[0]
        apple_branch = batch.split("if requestedEngine == .appleTranslation {", 1)[1].split(
            "let qualityReport = TranslationBatchQualityEvaluator.evaluate(", 1
        )[0]
        self.assertIn("guard let value", apple_branch)
        self.assertIn("guard !translation.isEmpty", apple_branch)
        self.assertIn("return translations", apple_branch)
        self.assertNotIn("TranslationBatchQualityEvaluator", apple_branch)

        validator = self.store.split("private func imageTranslationOutputFailures(", 1)[1].split(
            "private func japaneseImageTranslationPrompt(", 1
        )[0]
        self.assertIn("if engine == .appleTranslation", validator)
        self.assertIn('["emptyOutput"]', validator)
        self.assertIn("TranslationBatchQualityEvaluator.singleOutputFailures(", validator)

    def test_new_sources_are_compiled_by_the_app_target(self) -> None:
        for source in ("AppleTranslationService.swift", "AppleTranslationTaskHost.swift"):
            self.assertIn(f"{source} in Sources", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
