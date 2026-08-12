#!/usr/bin/env python3
"""Contract for variable-length bundled Manga OCR batch decoding."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def braced_body(source: str, signature: str) -> str:
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace:index + 1]
    raise AssertionError(f"unterminated body for {signature}")


class JapaneseMangaOCRBatchEOSEquivalenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.service = read("AITRANS/Services/MangaOCRService.swift")
        cls.batch = braced_body(
            cls.service,
            "func recognizeBatch(\n        _ images: [CGImage]",
        )
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")

    def test_finished_rows_keep_decoder_final_position_aligned(self) -> None:
        self.assertIn("for index in 0..<batch {", self.batch)
        finished = self.batch.index("if finished[index] {")
        append = self.batch.index(
            "tokenRows[index].append(Self.decoderEndToken)",
            finished,
        )
        continue_index = self.batch.index("continue", append)
        active = self.batch.index(
            "let prediction = predictions[index]",
            continue_index,
        )
        self.assertLess(finished, append)
        self.assertLess(append, continue_index)
        self.assertLess(continue_index, active)
        self.assertIn(
            "Core ML's decoder returns only the logits at the final",
            self.batch,
        )
        self.assertNotIn("where !finished[index]", self.batch)

    def test_eos_and_greedy_budget_remain_koharu_compatible(self) -> None:
        self.assertIn("private static let maximumTokens = 300", self.service)
        self.assertIn("if prediction.id == Self.decoderEndToken", self.batch)
        self.assertIn("if finished.allSatisfy({ $0 })", self.batch)
        self.assertIn("Self.nextTokens(in: logits, batch: batch)", self.batch)
        self.assertIn("Self.decoderStartToken", self.batch)
        self.assertRegex(self.batch, r"for _ in 0\.\.\<Self\.maximumTokens")

    def test_single_crop_path_and_batch_resources_remain_unchanged(self) -> None:
        self.assertIn("func recognize(_ image: CGImage)", self.service)
        self.assertIn('named: "MangaOCREncoderINT8Batch"', self.service)
        self.assertIn('named: "MangaOCRDecoderINT8Batch"', self.service)
        self.assertIn("batchInferenceEnabled()", self.service)
        self.assertIn("legacySingleCropFallback", read("AITRANS/Resources/MangaOCR/conversion.json"))

    def test_version_and_ci_route_are_advanced(self) -> None:
        self.assertEqual(
            set(re.findall(r"MARKETING_VERSION = ([^;]+);", self.project)),
            {"3.274"},
        )
        previous = "python3 -B scripts/test-v3255-image-japanese-manga-ocr-batch-eos-alignment-contract.py"
        current = "python3 -B scripts/test-v3256-image-review-direction-filter-focus-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))


if __name__ == "__main__":
    unittest.main()
