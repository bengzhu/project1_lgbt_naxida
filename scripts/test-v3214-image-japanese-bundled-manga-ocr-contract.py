#!/usr/bin/env python3
"""Contract for the bundled Koharu-aligned Manga OCR Core ML path."""

from hashlib import sha256
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def digest(relative_path: str) -> str:
    return sha256((ROOT / relative_path).read_bytes()).hexdigest()


class JapaneseBundledMangaOCRContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOCRService.swift")
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.converter = read("scripts/convert-manga-ocr-coreml.py")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_exact_quantized_model_artifacts_are_bundled(self) -> None:
        files = {
            "AITRANS/Resources/MangaOCR/MangaOCREncoderINT8.mlpackage/Data/com.apple.CoreML/weights/weight.bin": (
                86_110_336,
                "33b18e3b3cbda45b6dd365b836263362fb75b74e494048bd703ac1b6e9dbf744",
            ),
            "AITRANS/Resources/MangaOCR/MangaOCRDecoderINT8.mlpackage/Data/com.apple.CoreML/weights/weight.bin": (
                24_864_640,
                "c76ed618af753c4a0f8890b9ecda703fc698431e7214445267bb8c69202169b6",
            ),
        }
        for path, (size, expected_digest) in files.items():
            artifact = ROOT / path
            self.assertTrue(artifact.is_file(), path)
            self.assertEqual(artifact.stat().st_size, size)
            self.assertEqual(digest(path), expected_digest)
        self.assertEqual(
            len(read("AITRANS/Resources/MangaOCR/MangaOCRVocab.txt").splitlines()),
            6_144,
        )

    def test_model_license_and_conversion_provenance_are_present(self) -> None:
        notice = read("AITRANS/Resources/MangaOCR/NOTICE.md")
        license_text = read("AITRANS/Resources/MangaOCR/LICENSE-APACHE")
        self.assertIn("kha-white/manga-ocr-base", notice)
        self.assertIn("aa6573bd10b0d446cbf622e29c3e084914df9741", notice)
        self.assertIn("Apache License", license_text)
        self.assertIn("Version 2.0", license_text)

    def test_runtime_is_actor_isolated_batched_and_cpu_only(self) -> None:
        for marker in [
            "actor MangaOCRService",
            "static let shared = MangaOCRService()",
            "private var runtime: MangaOCRRuntime?",
            "image: CGImage",
            "requests: [MangaOCRRequest]",
            "configuration.computeUnits = .cpuOnly",
            "Task.checkCancellation()",
        ]:
            self.assertIn(marker, self.service)
        self.assertNotIn("CGImageSourceCreateImageAtIndex", self.service)

    def test_runtime_matches_manga_ocr_preprocess_and_greedy_decode(self) -> None:
        for marker in [
            "private static let imageSize = 224",
            "Float(grayscale[index]) / 127.5 - 1",
            "private static let vocabularySize = 6_144",
            "private static let decoderStartToken = 2",
            "private static let decoderEndToken = 3",
            "private static let maximumTokens = 300",
            "encoder_hidden_states",
            "next_token_logits",
            "containsJapaneseLetter",
        ]:
            self.assertIn(marker, self.service)

    def test_manga_ocr_runs_before_vision_crop_fallback(self) -> None:
        call = "await Self.recognizeJapaneseMangaOCR("
        fallback = "let cropRefinedObservations = Self.recognizeJapaneseVerticalCrops("
        self.assertIn(call, self.vision)
        self.assertIn(fallback, self.vision)
        self.assertLess(self.vision.index(call), self.vision.index(fallback))
        for marker in [
            "detectJapanesePixelFirstVerticalRegions(",
            "MangaOCRRequest(",
            "image: image,",
            "sourceDirectionHint: .vertical",
            "observationRole: .detectorTextRegion",
        ]:
            self.assertIn(marker, self.vision)
        self.assertTrue(
            "try await MangaOCRService.shared.recognize(" in self.vision
            or "try? await MangaOCRService.shared.recognize(" in self.vision
        )

    def test_converter_preserves_fp32_decoder_and_int8_weights(self) -> None:
        for marker in [
            'MODEL_ID = "kha-white/manga-ocr-base"',
            'MODEL_REVISION = "aa6573bd10b0d446cbf622e29c3e084914df9741"',
            "compute_precision=ct.precision.FLOAT16",
            "compute_precision=ct.precision.FLOAT32",
            'dtype="int8"',
            "upper_bound=300",
        ]:
            self.assertIn(marker, self.converter)

    def test_project_version_and_ci_route_follow_v3213(self) -> None:
        for marker in [
            "MangaOCRService.swift in Sources",
            "MangaOCREncoderINT8.mlpackage in Resources",
            "MangaOCRDecoderINT8.mlpackage in Resources",
            "MangaOCRVocab.txt in Resources",
        ]:
            self.assertIn(marker, self.project)
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 214) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.213;", self.project)
        previous = "python3 -B scripts/test-v3213-image-japanese-koharu-character-envelope-contract.py"
        current = "python3 -B scripts/test-v3214-image-japanese-bundled-manga-ocr-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3214-image-japanese-bundled-manga-ocr-contract.py'",
            self.workflow,
        )
        self.assertIn(
            "bash scripts/test-v3214-image-japanese-manga-ocr-runtime.sh",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
