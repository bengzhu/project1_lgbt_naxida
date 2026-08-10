#!/usr/bin/env python3
"""Contract for shipping and exercising the bounded Manga OCR batch models."""

import json
from hashlib import sha256
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def digest(relative_path: str) -> str:
    return sha256((ROOT / relative_path).read_bytes()).hexdigest()


class JapaneseBundledBatchRuntimeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.single_runtime = read("scripts/test-v3214-image-japanese-manga-ocr-runtime.sh")
        self.long_runtime = read("scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh")
        self.metadata = json.loads(read("AITRANS/Resources/MangaOCR/conversion.json"))

    def test_exact_batch_artifacts_are_bundled(self) -> None:
        files = {
            "AITRANS/Resources/MangaOCR/MangaOCREncoderINT8Batch.mlpackage/Data/com.apple.CoreML/weights/weight.bin": (
                86_110_336,
                "33b18e3b3cbda45b6dd365b836263362fb75b74e494048bd703ac1b6e9dbf744",
            ),
            "AITRANS/Resources/MangaOCR/MangaOCRDecoderINT8Batch.mlpackage/Data/com.apple.CoreML/weights/weight.bin": (
                24_864_640,
                "c76ed618af753c4a0f8890b9ecda703fc698431e7214445267bb8c69202169b6",
            ),
        }
        for path, (size, expected_digest) in files.items():
            artifact = ROOT / path
            self.assertTrue(artifact.is_file(), path)
            self.assertEqual(artifact.stat().st_size, size)
            self.assertEqual(digest(path), expected_digest)
        for package in ("MangaOCREncoderINT8Batch.mlpackage", "MangaOCRDecoderINT8Batch.mlpackage"):
            manifest = ROOT / "AITRANS/Resources/MangaOCR" / package / "Manifest.json"
            self.assertTrue(manifest.is_file(), str(manifest))
            json.loads(manifest.read_text(encoding="utf-8"))

    def test_metadata_and_project_declare_batch_resources(self) -> None:
        self.assertEqual(self.metadata["batchInference"]["bundledModelBatchSize"], 4)
        self.assertTrue(self.metadata["batchInference"]["legacySingleCropFallback"])
        self.assertEqual(self.metadata["batchInference"]["maximumBatchSize"], 4)
        for marker in [
            "MangaOCREncoderINT8Batch.mlpackage in Resources",
            "MangaOCRDecoderINT8Batch.mlpackage in Resources",
            "MangaOCREncoderINT8Batch.mlpackage",
            "MangaOCRDecoderINT8Batch.mlpackage",
        ]:
            self.assertIn(marker, self.project)

    def test_runtime_keeps_pairing_and_isolated_fallback(self) -> None:
        for marker in [
            'named: "MangaOCREncoderINT8Batch"',
            'named: "MangaOCRDecoderINT8Batch"',
            "if let optionalBatchEncoder, let optionalBatchDecoder",
            "func batchInferenceEnabled() throws -> Bool",
            "let recognitions = try runtime.recognizeBatch(",
            "A bad batch falls back to isolated crops below",
            "One malformed crop or model output must not discard good regions",
        ]:
            self.assertIn(marker, self.service)
        self.assertIn("MangaOCREncoderINT8Batch.mlpackage", self.single_runtime)
        self.assertIn("MangaOCRDecoderINT8Batch.mlpackage", self.single_runtime)
        self.assertIn('"batchInference=\\(batchInference)"', read("scripts/fixtures/v3214-manga-ocr-runtime-harness.swift"))
        self.assertIn("MangaOCREncoderINT8Batch.mlpackage", self.long_runtime)
        self.assertIn("MangaOCRDecoderINT8Batch.mlpackage", self.long_runtime)
        self.assertIn('"batchInference=\\(batchInference)"', read("scripts/fixtures/v3218-long-page-manga-ocr-runtime-harness.swift"))

    def test_ci_runs_new_contract_after_v3227(self) -> None:
        previous = "python3 -B scripts/test-v3227-image-japanese-batch-preview-contract.py"
        current = "python3 -B scripts/test-v3228-image-japanese-bundled-batch-runtime-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3228-image-japanese-bundled-batch-runtime-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 228) for version in versions))


if __name__ == "__main__":
    unittest.main(verbosity=2)
