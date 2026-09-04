#!/usr/bin/env python3
"""Static contract for Apple Translation on image and audio product paths."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class AppleMediaTranslationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.store = (ROOT / "AITRANS/Services/TranslationSessionStore.swift").read_text(encoding="utf-8")
        cls.service = (ROOT / "AITRANS/Services/AppleTranslationService.swift").read_text(encoding="utf-8")
        cls.host = (ROOT / "AITRANS/Views/AppleTranslationTaskHost.swift").read_text(encoding="utf-8")
        cls.root_view = (ROOT / "AITRANS/Views/ContentView.swift").read_text(encoding="utf-8")

    def test_swiftui_translation_session_host_wraps_all_product_tabs(self):
        self.assertIn("AppleTranslationTaskHost(service: store.appleTranslationService)", self.root_view)
        self.assertIn(".translationTask(service.configuration)", self.host)
        self.assertIn("await service.runPendingJob(with: session)", self.host)

    def test_image_ocr_blocks_use_the_selected_apple_adapter(self):
        for needle in (
            "runImageTranslationPipeline",
            "translateJapaneseImageBatch",
            "translateImageBlockWithQA",
            "generateWithSelectedEngine(request)",
            "requestedEngine == .appleTranslation",
            "return output.trimmingCharacters",
        ):
            self.assertIn(needle, self.store)
        self.assertIn("translationProfile == .mangaBlocks", self.service)
        self.assertIn("session.translate(batch: requests)", self.service)

    def test_audio_translation_freezes_identity_and_excludes_reference_context(self):
        for needle in (
            "struct SpeechTranslationConfiguration",
            "speechTranslationConfiguration = SpeechTranslationConfiguration(",
            "expectedSpeechRunID: runID",
            "configuration: self.speechTranslationConfiguration",
            "transcriptContext: []",
            "generateWithSelectedEngine(request, engine: configuration.engine)",
            "speechRecognitionRunID == expectedRunID",
            "speechTranslationConfiguration = nil",
        ):
            self.assertIn(needle, self.store)

    def test_configuration_change_cancels_stale_image_and_audio_runs(self):
        self.assertIn("invalidateTranslationRunsForConfigurationChange()", self.store)
        self.assertIn("appleTranslationService.cancelPendingRequest()", self.store)
        self.assertIn("cancelImageTranslation()", self.store)
        self.assertIn("cancelAudioRecognition()", self.store)
        self.assertIn("翻译配置已变化，请重新开始图片翻译", self.store)
        self.assertIn("翻译配置已变化，请重新开始音频识别或翻译", self.store)

    def test_simulator_fallback_and_apple_cancellation_race_are_explicit(self):
        self.assertIn("#if targetEnvironment(simulator)", self.store)
        self.assertIn("Simulator Apple→Local", self.store)
        self.assertIn("Simulator Apple→Mock", self.store)
        self.assertIn("模拟器不支持系统翻译", self.store)
        self.assertIn("try Task.checkCancellation()", self.service)
        self.assertIn("if Task.isCancelled", self.service)
        self.assertIn("cancel(jobID: job.id)", self.service)
        self.assertIn("runningJobID != job.id", self.service)


if __name__ == "__main__":
    unittest.main()
