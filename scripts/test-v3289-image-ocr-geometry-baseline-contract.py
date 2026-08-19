#!/usr/bin/env python3
"""Static contract for the v3.289 automatic OCR bbox baseline."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class ImageOCRGeometryBaselineContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.editor = read("AITRANS/Views/ImageOCRGeometryEditor.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")

    def test_block_keeps_a_codable_automatic_baseline(self) -> None:
        block_start = self.models.index("struct ImageTranslationBlock:")
        block_end = self.models.index("\n}\n\n", block_start) + 2
        block = self.models[block_start:block_end]
        for marker in (
            "struct ImageTranslationBlock: Identifiable, Equatable, Codable, Sendable",
            "var boundingBox: NormalizedImageRect",
            "var automaticBoundingBox: NormalizedImageRect?",
            "automaticBoundingBox: NormalizedImageRect? = nil",
            "(automaticBoundingBox ?? boundingBox).normalizedToUnit()",
            "&& lhs.automaticBoundingBox == rhs.automaticBoundingBox",
        ):
            self.assertIn(marker, block)

    def test_editor_restores_baseline_without_starting_work(self) -> None:
        for marker in (
            "private var automaticBaseline: NormalizedImageRect?",
            "private var automaticBaselineIsCurrent: Bool",
            "if automaticBaseline != nil",
            "title: \"恢复自动文字框\"",
            ".disabled(automaticBaselineIsCurrent)",
            "guard let automaticBaseline else { return }",
            "draft = automaticBaseline",
            "onCommit(Self.clamped(draft))",
            "尚未开始 OCR",
            "没有可恢复的 automatic baseline",
        ):
            self.assertIn(marker, self.editor)
        self.assertNotIn("恢复打开时文字框", self.editor)
        self.assertNotIn("rerecognizeImageTranslationBlock", self.editor)

    def test_scoped_rerecognition_does_not_overwrite_baseline(self) -> None:
        start = self.store.index(
            "func rerecognizeImageTranslationBlock(\n        _ blockID: UUID,\n        boundingBox: NormalizedImageRect?"
        )
        body = self.store[start:self.store.index("func rerunImageRecognition", start)]
        self.assertIn("var replacement = block", body)
        self.assertIn("applyEditedImageTranslationBoundingBox(", body)
        self.assertNotIn("automaticBoundingBox =", body)
        self.assertIn("self.imageTranslationBlocks[currentIndex] = replacement", body)

    def test_contract_is_routed_without_runtime_or_model_download(self) -> None:
        for marker in (
            "scripts/test-v3289-image-ocr-geometry-baseline-contract.py",
            "v3.289",
            "automatic baseline",
            "恢复自动文字框",
        ):
            self.assertIn(marker, self.workflow + self.route + self.editor)
        contract = read("scripts/test-v3289-image-ocr-geometry-baseline-contract.py")
        for source in (contract, self.editor):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)

    def test_route_keeps_legacy_and_future_boundaries_explicit(self) -> None:
        self.assertIn("旧解码", self.route)
        self.assertIn("automatic baseline", self.route)
        self.assertIn("已有候选选择", self.route)
        self.assertIn("split/merge/order", self.route)


if __name__ == "__main__":
    unittest.main(verbosity=2)
