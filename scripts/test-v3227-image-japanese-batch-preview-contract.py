#!/usr/bin/env python3
"""Contract for bounded Koharu batch OCR and faithful vertical preview truncation."""

import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def braced_body(source: str, marker: str) -> str:
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class JapaneseBatchPreviewContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOCRService.swift")
        self.converter = read("scripts/convert-manga-ocr-coreml.py")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.vertical_view = braced_body(
            self.view,
            "private struct ImageTranslationVerticalText: View",
        )
        self.runtime = braced_body(self.service, "private struct MangaOCRRuntime")
        self.recognize = braced_body(self.service, "func recognize(")

    def test_preview_bounds_text_and_keeps_ellipsis_inside_capacity(self) -> None:
        for marker in [
            "let columnCapacity = max(",
            "let maximumCharacters = max(rowCapacity * columnCapacity, 1)",
            "let drawableCharacters = boundedCharacters(",
            "private func boundedCharacters(",
            "let prefixCount = max(maximumCharacters - 1, 1)",
            "return Array(characters.prefix(prefixCount)) + [\"…\"]",
            ".clipped()",
        ]:
            self.assertIn(marker, self.vertical_view)

    def test_runtime_uses_optional_bounded_batch_and_isolated_fallback(self) -> None:
        for marker in [
            "private static let maximumBatchSize = 4",
            "runtime.supportsBatchInference",
            "runtime.recognizeBatch(",
            "MangaOCREncoderINT8Batch",
            "MangaOCRDecoderINT8Batch",
            "for start in stride(from: 0, to: croppedRequests.count, by: Self.maximumBatchSize)",
            "A bad batch falls back to isolated crops below",
            "One malformed crop or model output must not discard good regions",
        ]:
            self.assertIn(marker, self.service)
        self.assertIn("try Task.checkCancellation()", self.recognize)
        self.assertIn("func recognizeBatch(", self.runtime)
        for marker in [
            "let pixels = try Self.makePixelValues(images)",
            "let inputIDs = try Self.makeInputIDs(tokenRows)",
            "let predictions = try Self.nextTokens(in: logits, batch: batch)",
            "finished.allSatisfy({ $0 })",
        ]:
            self.assertIn(marker, self.runtime)

    def test_converter_emits_flexible_batch_shapes_without_changing_legacy_default(self) -> None:
        for marker in [
            "def coreml_batch_dimension(batch_size: int)",
            "ct.RangeDim(",
            'parser.add_argument(\n        "--batch-size"',
            "shape=(coreml_batch_dimension(batch_size), 3, 224, 224)",
            "shape=(coreml_batch_dimension(batch_size), sequence)",
            "shape=(coreml_batch_dimension(batch_size), 197, 768)",
            'suffix = "" if args.batch_size == 1 else "Batch"',
            '"flexibleBatch": args.batch_size > 1',
        ]:
            self.assertIn(marker, self.converter)
        self.assertIn('"MangaOCREncoderINT8{suffix}.mlpackage"', self.converter)
        self.assertIn('"MangaOCRDecoderINT8{suffix}.mlpackage"', self.converter)

    def test_conversion_provenance_is_bundled_and_matches_source_revision(self) -> None:
        metadata = json.loads(
            read("AITRANS/Resources/MangaOCR/conversion.json")
        )
        self.assertEqual(metadata["source"], "kha-white/manga-ocr-base")
        self.assertEqual(
            metadata["revision"],
            "aa6573bd10b0d446cbf622e29c3e084914df9741",
        )
        self.assertEqual(metadata["batchInference"]["bundledModelBatchSize"], 1)
        self.assertEqual(metadata["batchInference"]["maximumBatchSize"], 4)
        self.assertIn("conversion.json in Resources", self.project)

    def test_version_and_ci_route_follow_v3226(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 227) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.226;", self.project)
        previous = "python3 -B scripts/test-v3226-image-japanese-manga-ocr-quality-gate-contract.py"
        current = "python3 -B scripts/test-v3227-image-japanese-batch-preview-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3227-image-japanese-batch-preview-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
