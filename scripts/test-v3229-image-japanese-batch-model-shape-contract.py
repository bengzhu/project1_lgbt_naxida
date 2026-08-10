#!/usr/bin/env python3
"""Contract for the Core ML flexible-batch encoder runtime fix."""

from hashlib import sha256
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class JapaneseBatchModelShapeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.converter = read("scripts/convert-manga-ocr-coreml.py")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.encoder_spec = (
            ROOT
            / "AITRANS/Resources/MangaOCR/MangaOCREncoderINT8Batch.mlpackage"
            / "Data/com.apple.CoreML/model.mlmodel"
        )

    def test_encoder_avoids_dynamic_tile_repetition(self) -> None:
        for marker in [
            "class BatchSafeViTEmbeddings",
            "cls_tokens = self.cls_token * torch.ones(",
            "def make_batch_safe_encoder(",
            "batch_shape = coreml_batch_shape(batch_size, (3, 224, 224))",
            "ct.EnumeratedShapes(",
        ]:
            self.assertIn(marker, self.converter)
        self.assertTrue(self.encoder_spec.is_file())
        spec = self.encoder_spec.read_bytes()
        self.assertEqual(len(spec), 152_807)
        self.assertEqual(
            sha256(spec).hexdigest(),
            "58fd945e602b56a635588708e3f83455ea1d7a9e0e49fdba5454e0f2f761b3d9",
        )
        self.assertNotIn(b"tile", spec)
        self.assertIn(b"fill", spec)

    def test_decoder_keeps_dynamic_sequence_and_legacy_fallback(self) -> None:
        for marker in [
            "batch_dimension = coreml_batch_dimension(batch_size)",
            "shape=(batch_dimension, sequence)",
            "shape=(batch_dimension, 197, 768)",
            "legacySingleCropFallback",
        ]:
            self.assertIn(marker, self.converter + read("AITRANS/Resources/MangaOCR/conversion.json"))

    def test_ci_routes_shape_fix_after_v3228(self) -> None:
        previous = "python3 -B scripts/test-v3228-image-japanese-bundled-batch-runtime-contract.py"
        current = "python3 -B scripts/test-v3229-image-japanese-batch-model-shape-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3229-image-japanese-batch-model-shape-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 229) for version in versions))


if __name__ == "__main__":
    unittest.main(verbosity=2)
