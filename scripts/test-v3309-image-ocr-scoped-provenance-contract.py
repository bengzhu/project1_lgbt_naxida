#!/usr/bin/env python3
"""Static contract for v3.309 scoped OCR provenance handoff."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


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
                return source[brace + 1 : index]
    raise AssertionError(f"unterminated function body: {signature}")


class ImageOCRScopedProvenanceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.provenance = read("AITRANS/Models/ImageOCRProvenance.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.test_log = read("md/test/test.md")
        cls.update_log = read("update_log.md")

    def test_accepted_scoped_candidate_replaces_diagnostic_provenance(self) -> None:
        body = function_body(
            self.store,
            "func rerecognizeImageTranslationBlock(\n",
        )
        for marker in (
            "let recognized = try await self.visionOCRService.recognizeTextBlock(",
            "var replacement = block",
            "replacement.original = recognizedOriginal",
            "replacement.confidence = recognized.confidence",
            "replacement.ocrProvenance = recognized.ocrProvenance",
            "replacement.textKind = recognized.textKind",
            "self.imageTranslationBlocks[currentIndex] = replacement",
        ):
            self.assertIn(marker, body)
        self.assertLess(
            body.index("replacement.ocrProvenance = recognized.ocrProvenance"),
            body.index("self.imageTranslationBlocks[currentIndex] = replacement"),
        )

    def test_original_block_is_retained_as_restore_baseline(self) -> None:
        restore = function_body(
            self.store,
            "func restoreImageTranslationBlockToVisionOCR(",
        )
        self.assertIn("var restoredBlock = originalBlock", restore)
        self.assertIn(
            "imageTranslationBlocks[blockIndex] = restoredBlock",
            restore,
        )
        self.assertNotIn("recognizeTextBlock(", restore)

    def test_scoped_commit_preserves_identity_geometry_and_existing_qa(self) -> None:
        body = function_body(
            self.store,
            "func rerecognizeImageTranslationBlock(\n",
        )
        for marker in (
            "self.imageTranslationBlockRerecognitionID == requestID",
            "self.imageTranslationTaskID == contentTaskID",
            "self.imageTranslationBlocks[blockIndex] == block",
            "applyEditedImageTranslationBoundingBox(",
            "translateJapaneseImageBlockWithQA(",
            "self.imageTranslationReviewedBlockIDs.remove(blockID)",
            "self.persist()",
        ):
            self.assertIn(marker, body)
        for forbidden in (
            "recognizeTextBlocks(",
            "ImageOCRLayoutEngine.layout",
            "imageTranslationOriginalBlockOrder =",
            "imageTranslationJapaneseBatchPlan = []",
        ):
            self.assertNotIn(forbidden, body)

    def test_provenance_is_codable_diagnostic_metadata(self) -> None:
        block_start = self.models.index("struct ImageTranslationBlock:")
        block_end = self.models.index("\n}\n", block_start)
        block = self.models[block_start:block_end]
        self.assertIn("var ocrProvenance: ImageOCRBlockProvenance?", block)
        equality_start = self.models.index("static func ==", block_start)
        equality_end = self.models.index(
            "\n    /// Keeps detector/Vision provenance intact",
            equality_start,
        )
        equality = self.models[equality_start:equality_end]
        self.assertNotIn("ocrProvenance", equality)
        self.assertIn("struct ImageOCRBlockProvenance: Equatable, Codable, Sendable", self.provenance)
        self.assertIn("var candidates: [ImageOCRCandidateProvenance]", self.provenance)

    def test_no_new_ocr_request_or_optional_koharu_dependency(self) -> None:
        body = function_body(
            self.store,
            "func rerecognizeImageTranslationBlock(\n",
        )
        self.assertEqual(body.count("recognizeTextBlock("), 1)
        self.assertNotIn("Koharu", body)
        self.assertNotIn("MangaOCRService", body)
        self.assertNotIn("while ", body)
        for marker in (
            "koharu_parity_required:",
            "inputs.koharu_parity_required == 'true'",
            "Koharu MIT48 parity is optional for ordinary OCR validation",
        ):
            self.assertIn(marker, self.workflow)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.327", "3.327"],
        )
        for marker in (
            "scripts/test-v3309-image-ocr-scoped-provenance-contract.py",
            "v3.309",
            "japanese-benchmark-v3.309-",
        ):
            self.assertIn(marker, self.workflow)
        for document in (
            self.flow,
            self.route,
            self.test_log,
            self.update_log,
        ):
            self.assertIn("v3.309", document)

    def test_contract_and_store_have_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3309-image-ocr-scoped-provenance-contract.py"
        )
        for source in (contract, self.store):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
