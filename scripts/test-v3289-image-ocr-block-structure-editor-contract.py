#!/usr/bin/env python3
"""Static contract for v3.289 image OCR block structure editing."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


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


class ImageOCRBlockStructureEditorContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.editor = read("AITRANS/Views/ImageOCRBlockStructureEditor.swift")
        cls.panel = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")

    def test_structure_mutations_are_terminal_and_fail_closed(self) -> None:
        gate = function_body(self.store, "var canEditImageTranslationStructure: Bool")
        for marker in (
            "imageTranslationState == .translated",
            "imageTranslationExportRenderState != .rendering",
            "imageTranslationTask == nil",
            "imageTranslationCorrectionBlockID == nil",
            "imageTranslationRetryingBlockID == nil",
            "imageTranslationRerecognizingBlockID == nil",
            "!imageTranslationBlocks.isEmpty",
        ):
            self.assertIn(marker, gate)

        for signature in (
            "func splitImageTranslationBlock(",
            "func mergeImageTranslationBlocks(",
            "func moveImageTranslationBlock(",
        ):
            body = function_body(self.store, signature)
            self.assertIn("canEditImageTranslationStructure", body)
            self.assertIn("finalizeImageTranslationStructureMutation(", body)
            self.assertNotIn("recognizeTextBlocks(", body)
            self.assertNotIn("generateWithSelectedEngine(", body)
            self.assertNotIn("translate(", body)

    def test_split_and_merge_invalidate_stale_translation_and_ocr_state(self) -> None:
        split = function_body(self.store, "func splitImageTranslationBlock(")
        for marker in (
            "Array(block.original)",
            "offset > 0",
            "offset < characters.count",
            "replaceSubrange(",
            "Self.makeStructureMutationBlock(",
            "imageTranslationReviewedBlockIDs.remove(blockID)",
            "imageTranslationCorrectedBlockIDs.remove(blockID)",
            "imageTranslationVisionOriginalBlocks.removeValue(forKey: blockID)",
            "rebuildImageTranslationOriginalBlockOrder()",
        ):
            self.assertIn(marker, split)

        mutation = function_body(self.store, "private static func makeStructureMutationBlock(")
        for marker in (
            "translation: \"\"",
            "automaticBoundingBox: nil",
            "ocrProvenance: nil",
            "mutation.automaticBoundingBox = nil",
            "mutation.ocrProvenance = nil",
            "id: UUID()",
        ):
            self.assertIn(marker, mutation)

        merge = function_body(self.store, "func mergeImageTranslationBlocks(")
        for marker in (
            "abs(firstIndex - secondIndex) == 1",
            "firstBlock.original + secondBlock.original",
            "unionRect",
            "min(",
            "replaceSubrange(",
            "imageTranslationReviewedBlockIDs.remove(firstBlockID)",
            "imageTranslationReviewedBlockIDs.remove(secondBlockID)",
            "imageTranslationVisionOriginalBlocks.removeValue(forKey: firstBlockID)",
            "imageTranslationVisionOriginalBlocks.removeValue(forKey: secondBlockID)",
        ):
            self.assertIn(marker, merge)

    def test_order_mutation_preserves_block_payload_and_rebuilds_session_order(self) -> None:
        move = function_body(self.store, "func moveImageTranslationBlock(")
        for marker in (
            "var reorderedBlocks = imageTranslationBlocks",
            "let movedBlock = reorderedBlocks.remove(at: currentIndex)",
            "reorderedBlocks.insert(movedBlock, at: destination)",
            "imageTranslationBlocks = reorderedBlocks",
            "rebuildImageTranslationOriginalBlockOrder()",
        ):
            self.assertIn(marker, move)
        self.assertNotIn("imageTranslationBlocks[currentIndex] = ImageTranslationBlock", move)

        rebuild = function_body(
            self.store,
            "private func rebuildImageTranslationOriginalBlockOrder()",
        )
        for marker in (
            "imageTranslationBlocks.map(\\.id)",
            "imageTranslationIgnoredBlockSnapshots.values.sorted",
            "imageTranslationOriginalBlockOrder = Dictionary(",
            "refreshImageTranslationIgnoredBlocks()",
        ):
            self.assertIn(marker, rebuild)

    def test_commit_updates_existing_transcript_export_and_persistence_boundaries(self) -> None:
        finalize = function_body(
            self.store,
            "private func finalizeImageTranslationStructureMutation(message: String)",
        )
        for marker in (
            "synchronizeImageTranslationTranscript(blocks: imageTranslationBlocks)",
            "invalidateImageOverlayRender()",
            "discardImageTranslationExport()",
            "rerenderImageTranslationExport()",
            "persist()",
        ):
            self.assertIn(marker, finalize)
        self.assertIn("imageTranslationBlocks = snapshot.blocks", self.store)
        self.assertIn("originalBlockOrder: originalBlockOrder", self.store)

    def test_editor_and_panel_are_accessible_and_do_not_run_work(self) -> None:
        for marker in (
            "struct ImageOCRBlockStructureEditor: View",
            "Section(\"调整阅读顺序\")",
            "Section(\"拆分当前文字块\")",
            "Section(\"合并相邻文字块\")",
            "Button(\"上移\", systemImage: \"arrow.up\")",
            "Button(\"下移\", systemImage: \"arrow.down\")",
            "Button(\"拆分文字块\", systemImage: \"rectangle.split.2x1\")",
            "Button(\"合并已选文字块\", systemImage: \"rectangle.2.group\")",
            "Button(\"取消\", role: .cancel)",
            ".accessibilityHint",
            "不会重新识别或翻译",
        ):
            self.assertIn(marker, self.editor)
        for forbidden in ("TranslationSessionStore", "recognizeTextBlocks", "generate", "Task {"):
            self.assertNotIn(forbidden, self.editor)
        self.assertIn(
            "private let indexedBlocks: [(offset: Int, element: ImageTranslationBlock)]",
            self.editor,
        )
        self.assertIn("indexedBlocks = Array(blocks.enumerated())", self.editor)
        self.assertEqual(
            self.editor.count("ForEach(indexedBlocks, id: \\.element.id)"),
            3,
        )
        self.assertNotIn("ForEach(blocks.enumerated()", self.editor)
        for marker in (
            "ImageOCRBlockStructureEditor(",
            "store.splitImageTranslationBlock",
            "store.mergeImageTranslationBlocks",
            "store.moveImageTranslationBlock",
            "store.canEditImageTranslationStructure",
        ):
            self.assertIn(marker, self.panel)

    def test_project_workflow_route_and_version_are_explicit(self) -> None:
        for marker in (
            "ImageOCRBlockStructureEditor.swift in Sources",
            "path = ImageOCRBlockStructureEditor.swift;",
            "scripts/test-v3289-image-ocr-block-structure-editor-contract.py",
            "编辑文字块结构",
            "split/merge/order",
            "v3.289",
        ):
            self.assertIn(marker, self.project + self.workflow + self.route + self.panel)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.390", "3.390"],
        )

    def test_contract_has_no_process_entry(self) -> None:
        contract = read("scripts/test-v3289-image-ocr-block-structure-editor-contract.py")
        for source in (contract, self.editor):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
