#!/usr/bin/env python3
"""Contract for user-controlled Japanese image text direction overrides."""

from pathlib import Path
import os
import re
import subprocess
import tempfile
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


class JapaneseDirectionOverrideContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.models = read("AITRANS/Models/TranscriptModels.swift")
        self.summary = read("AITRANS/Models/ImageOCRResultSummary.swift")
        self.filter = read("AITRANS/Models/ImageOCRReviewFilter.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.block = braced_body(self.models, "struct ImageTranslationBlock:")
        self.setter = braced_body(
            self.store,
            "func setImageTranslationBlockDirectionOverride(",
        )
        self.row = braced_body(
            self.view,
            "private struct ImageTranslationBlockRow: View",
        )
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )
        self.sheet = braced_body(
            self.view,
            "private struct ImageOCRCorrectionSheet: View",
        )

    def test_model_separates_raw_and_effective_direction(self) -> None:
        for marker in [
            "enum ImageTextDirectionOverrideChoice: String, CaseIterable, Identifiable, Codable, Sendable",
            'case automatic = "自动（OCR）"',
            'case horizontal = "横排"',
            'case vertical = "竖排"',
            "var sourceDirectionOverride: ImageTextDirection?",
            "var effectiveSourceDirection: ImageTextDirection?",
            "var hasSourceDirectionOverride: Bool",
            "switch sourceDirectionOverride",
            "let sourceDirection = effectiveSourceDirection",
            "guard sourceDirection == .vertical else { return false }",
        ]:
            self.assertIn(marker, self.block if marker.startswith("var source") or marker.startswith("var effective") or marker.startswith("var has") or marker.startswith("switch") or marker.startswith("let source") or marker.startswith("guard") else self.models)
        self.assertIn("sourceDirectionOverride: ImageTextDirection? = nil", self.models)

    def test_summary_and_filter_use_effective_direction(self) -> None:
        for marker in [
            "$0.effectiveSourceDirection == .horizontal",
            "$0.effectiveSourceDirection == .vertical",
            "$0.effectiveSourceDirection == nil || $0.effectiveSourceDirection == .unknown",
            "block.effectiveSourceDirection == nil || block.effectiveSourceDirection == .unknown",
        ]:
            self.assertIn(marker, self.summary)
        self.assertIn("blocks.filter { $0.effectiveSourceDirection == .vertical }", self.filter)

    def test_store_changes_only_one_block_and_reuses_render_pipeline(self) -> None:
        for marker in [
            "direction == nil || direction == .horizontal || direction == .vertical",
            "imageTranslationCorrectionBlockID == nil",
            "imageTranslationState == .translated",
            "imageTranslationExportRenderState != .rendering",
            "let blockIndex = imageTranslationBlocks.firstIndex(where: { $0.id == blockID })",
            "var updatedBlock = imageTranslationBlocks[blockIndex]",
            "updatedBlock.sourceDirectionOverride = direction",
            "imageTranslationBlocks[blockIndex] = updatedBlock",
            "imageTranslationReviewedBlockIDs.remove(blockID)",
            "updateImageTranslationTranscript(blocks: imageTranslationBlocks)",
            "invalidateImageOverlayRender()",
            "discardImageTranslationExport()",
            "rerenderImageTranslationExport()",
            "persist()",
        ]:
            self.assertIn(marker, self.setter)
        for forbidden in [
            "visionOCRService",
            "translate(",
            "recognizeTextBlocks(",
            "imageTranslationBlocks =",
            "imageTranslationBlocks.remove",
            "imageTranslationBlocks.insert",
        ]:
            self.assertNotIn(forbidden, self.setter)

    def test_row_focus_and_correction_sheet_expose_direction_action(self) -> None:
        for body in [self.row, self.focus]:
            self.assertIn("ImageOCRDirectionOverrideMenu(", body)
            self.assertIn("setDirectionOverride", body)
        for marker in [
            '"设为横排"',
            '"设为竖排"',
            '"恢复自动方向"',
            "ImageReviewRowDirectionOverrideAccessibilityModifier",
            "ImageFocusPreviewDirectionOverrideAccessibilityModifier",
        ]:
            self.assertIn(marker, self.view)
        for marker in [
            'Section("文字方向")',
            'Picker("文字方向", selection: directionOverrideBinding)',
            "只更新当前文字块的显示、筛选和导出方向，不会重新识别或翻译",
            "setDirectionOverride: @escaping (ImageTextDirection?) -> Bool",
        ]:
            self.assertIn(marker, self.sheet if marker.startswith("Section") or marker.startswith("Picker") or marker.startswith("只") else self.view)

    def test_rerecognition_and_ignore_restore_keep_override_by_copying_block(self) -> None:
        rerecognition = braced_body(
            self.store,
            "func rerecognizeImageTranslationBlock(",
        )
        for marker in [
            "var replacement = block",
            "self.imageTranslationBlocks[currentIndex] = replacement",
        ]:
            self.assertIn(marker, rerecognition)
        self.assertIn("block: ImageTranslationBlock", self.store)
        self.assertIn("snapshot.block", self.store)

    def test_executable_model_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v3243-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v3243-image-japanese-direction-override"
            environment = os.environ.copy()
            developer_directory = Path("/Applications/Xcode.app/Contents/Developer")
            if developer_directory.is_dir():
                environment["DEVELOPER_DIR"] = str(developer_directory)
            try:
                subprocess.run(
                    [
                        "xcrun", "--sdk", "macosx", "swiftc",
                        "-parse-as-library",
                        "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                        "AITRANS/Models/ImageOCRProvenance.swift",
                        "AITRANS/Services/ImageOCRLayoutEngine.swift",
                        "AITRANS/Models/TranslationContextQuality.swift",
                        "AITRANS/Models/TranscriptModels.swift",
                        "AITRANS/Models/ImageOCRResultSummary.swift",
                        "AITRANS/Models/ImageOCRReviewFilter.swift",
                        "scripts/test-v3243-image-japanese-direction-override-evaluator.swift",
                        "-o", str(executable),
                    ],
                    cwd=ROOT,
                    env=environment,
                    check=True,
                    capture_output=True,
                    text=True,
                )
            except subprocess.CalledProcessError as error:
                self.fail(
                    "direction override evaluator compilation failed:\n"
                    f"stdout={error.stdout}\nstderr={error.stderr}"
                )
            result = subprocess.run(
                [str(executable)], cwd=ROOT, check=True, capture_output=True, text=True
            )
            self.assertIn("v3.243 Japanese direction override evaluator passed", result.stdout)

    def test_version_and_ci_route_follow_v3242(self) -> None:
        previous = "python3 -B scripts/test-v3242-image-ocr-block-crop-retry-contract.py"
        current = "python3 -B scripts/test-v3243-image-japanese-direction-override-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3243-image-japanese-direction-override-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 243) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.242;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
