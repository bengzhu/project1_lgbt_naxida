#!/usr/bin/env python3
"""Static contract for the v1.95 real-audio Speech quality probe."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class SpeechQualityContractTests(unittest.TestCase):
    def test_reference_is_evaluation_only(self) -> None:
        models = read("AITRANS/Models/SpeechQualityModels.swift")
        service = read("AITRANS/Services/SpeechQualityProbeService.swift")
        self.assertIn("referenceUsedForEvaluationOnly", models)
        self.assertIn("referenceUsedForRecognitionDecision", models)
        self.assertIn("referenceUsedForRecognitionDecision: false", service)
        request_body = service[service.index("let request = SFSpeechURLRecognitionRequest"):]
        request_body = request_body[:request_body.index("private func finishActiveRecognition")]
        self.assertNotIn("referenceTranscript", request_body)

    def test_cjk_does_not_claim_whitespace_wer(self) -> None:
        evaluator = read("AITRANS/Services/SpeechQualityEvaluator.swift")
        self.assertIn('["zh", "ja"]', evaluator)
        self.assertIn("wordMetrics = nil", evaluator)
        self.assertIn("weightedCharacterErrorRate", evaluator)

    def test_audio_identity_and_on_device_requirements_are_hard_gates(self) -> None:
        service = read("AITRANS/Services/SpeechQualityProbeService.swift")
        self.assertIn("validateAudioIdentity", service)
        self.assertIn("identity.sha256.caseInsensitiveCompare", service)
        self.assertIn("handle.read(upToCount: 1_048_576)", service)
        self.assertIn("request.requiresOnDeviceRecognition = true", service)
        self.assertIn("recognizer.supportsOnDeviceRecognition", service)

    def test_store_owns_probe_state_and_run_identity(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertIn("@Published var speechQualityProbeReport", store)
        self.assertIn("private var speechQualityProbeRunID = UUID()", store)
        self.assertIn("func runSpeechQualityProbe()", store)
        self.assertIn("func cancelSpeechQualityProbe()", store)
        self.assertIn("AITRANS_RUN_SPEECH_QUALITY_PROBE", store)

    def test_project_and_ci_wire_new_sources_and_contracts(self) -> None:
        project = read("AITRANS.xcodeproj/project.pbxproj")
        workflow = read(".github/workflows/ci-results.yml")
        for filename in (
            "SpeechQualityModels.swift",
            "SpeechQualityEvaluator.swift",
            "SpeechQualityProbeService.swift",
        ):
            self.assertGreaterEqual(project.count(filename), 3)
        self.assertEqual(set(re.findall(r"MARKETING_VERSION = ([^;]+);", project)), {"1.95"})
        self.assertIn("scripts/test-speech-quality-contract.py", workflow)
        self.assertIn("scripts/test-speech-quality-evaluator.swift", workflow)
        self.assertIn("scripts/validate-speech-corpus.py", workflow)

    def test_missing_manifest_is_auditable_without_a_quality_claim(self) -> None:
        validator = read("scripts/validate-speech-corpus.py")
        self.assertIn('"verdict": "manifestMissing"', validator)
        self.assertIn('"qualityExecuted": False', validator)
        readme = read("test/speech_corpus/README.md")
        self.assertIn("v1.96", readme)


if __name__ == "__main__":
    unittest.main(verbosity=2)
