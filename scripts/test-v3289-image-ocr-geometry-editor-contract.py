#!/usr/bin/env python3
"""Static contract for the v3.289 scoped OCR bbox editor."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class ImageOCRGeometryEditorContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.editor = read("AITRANS/Views/ImageOCRGeometryEditor.swift")
        cls.rows = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")

    def test_editor_is_normalized_accessible_and_commit_only(self) -> None:
        for marker in (
            "struct ImageOCRGeometryEditor: View",
            "let onCommit: (NormalizedImageRect) -> Void",
            "@State private var draft: NormalizedImageRect",
            "block.boundingBox.normalizedToUnit()",
            "DragGesture",
            "Slider(value: binding, in: 0...1, step: 0.005)",
            "提交并重新识别此文字块",
            "恢复自动文字框",
            "Button(\"取消\", role: .cancel)",
            "private static func clamped(_ rect: NormalizedImageRect)",
            "尚未开始 OCR",
        ):
            self.assertIn(marker, self.editor)
        self.assertIn(".accessibilityHint", self.editor)
        self.assertIn("onCommit(Self.clamped(draft))", self.editor)
        self.assertNotIn("TranslationSessionStore", self.editor)
        self.assertNotIn("recognizeTextBlocks", self.editor)

    def test_store_commits_edited_geometry_only_after_scoped_success(self) -> None:
        for marker in (
            "func rerecognizeImageTranslationBlock(\n        _ blockID: UUID,\n        boundingBox: NormalizedImageRect? = nil",
            "let editedBoundingBox: NormalizedImageRect?",
            "boundingBox.normalizedToUnit()",
            "var recognitionBlock = block",
            "recognitionBlock.boundingBox = editedBoundingBox",
            "recognizeTextBlock(\n                    in: data",
            "var replacement = block",
            "applyEditedImageTranslationBoundingBox(\n                    editedBoundingBox,\n                    to: &replacement",
            "private func applyEditedImageTranslationBoundingBox(",
            "self.imageTranslationBlocks[currentIndex] = replacement",
            "catch is CancellationError",
            "self.imageTranslationBlockRerecognitionFailureGeneration &+= 1",
            "self.persist()",
        ):
            self.assertIn(marker, self.store)
        self.assertIn("imageTranslationBlocks[blockIndex] == block", self.store)
        self.assertNotIn("recognizeTextBlocks(", self.store.split(
            "func rerecognizeImageTranslationBlock(\n        _ blockID: UUID,\n        boundingBox: NormalizedImageRect?",
            1,
        )[1].split("func rerunImageRecognition", 1)[0])

    def test_row_uses_existing_scoped_task_and_keeps_controls_siblings(self) -> None:
        for marker in (
            "@State private var isGeometryEditorPresented = false",
            "Button(\"调整文字框\", systemImage: \"rectangle\")",
            "ImageOCRResultSummary.requiresReview(block)",
            ".sheet(isPresented: $isGeometryEditorPresented)",
            "ImageOCRGeometryEditor(block: block)",
            "let submitGeometryEdit: (UUID, NormalizedImageRect) -> Void",
            "boundingBox: boundingBox",
            "submitGeometryEdit(",
            "actions.append(\"调整文字框\")",
        ):
            self.assertIn(marker, self.rows)
        self.assertIn("ImageOCRProvenanceDisclosureView(block: block)", self.rows)
        self.assertIn("ImageOCRGeometryEditor(block: block)", self.rows)

    def test_project_workflow_route_and_version_are_explicit(self) -> None:
        for marker in (
            "ImageOCRGeometryEditor.swift in Sources",
            "path = ImageOCRGeometryEditor.swift;",
            "scripts/test-v3289-image-ocr-geometry-editor-contract.py",
            "v3.289",
            "scoped",
            "bbox",
        ):
            self.assertIn(marker, self.project + self.workflow + self.route)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.343", "3.343"],
        )

    def test_contract_has_no_process_entry(self) -> None:
        contract = read("scripts/test-v3289-image-ocr-geometry-editor-contract.py")
        for source in (contract, self.editor):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
