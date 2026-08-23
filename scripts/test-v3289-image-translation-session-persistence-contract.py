#!/usr/bin/env python3
"""Static contract for the v3.289 image-session persistence boundary."""

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


class ImageTranslationSessionPersistenceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")

    def test_snapshot_is_versioned_and_carries_review_state(self) -> None:
        start = self.models.index("struct ImageTranslationPersistenceSnapshot:")
        end = self.models.index("\n}\n\nenum ModelEngine", start) + 2
        snapshot = self.models[start:end]
        for marker in (
            "static let currentSchemaVersion = 1",
            "var sourceFileRelativePath: String",
            "var sourceFileSHA256: String",
            "var sourceFileByteCount: Int64",
            "var state: ImageTranslationState",
            "var blocks: [ImageTranslationBlock]",
            "var ignoredBlockSnapshots: [ImageTranslationIgnoredBlockPersistenceSnapshot]",
            "var visionOriginalBlocks: [ImageTranslationBlock]",
            "var reviewedBlockIDs: [UUID]",
            "var correctedBlockIDs: [UUID]",
            "var ignoredBlockIDs: [UUID]",
            "var originalBlockOrder: [UUID]",
            "var overlayMode: ImageTranslationOverlayMode",
            "var transcriptLineID: UUID?",
        ):
            self.assertIn(marker, snapshot)
        self.assertIn("struct ImageTranslationIgnoredBlockPersistenceSnapshot", self.models)

    def test_legacy_app_snapshot_decodes_without_image_field(self) -> None:
        app_models = self.models[self.models.index("struct AppPersistenceSnapshot:") :]
        snapshot = function_body(app_models, "init(from decoder: Decoder) throws")
        self.assertIn(
            "imageTranslationSession = try container.decodeIfPresent(",
            snapshot,
        )
        self.assertIn("case imageTranslationSession", app_models)
        self.assertIn("var imageTranslationSession: ImageTranslationPersistenceSnapshot?", app_models)

    def test_write_boundary_hashes_only_terminal_nonempty_sessions(self) -> None:
        body = function_body(
            self.store,
            "private func makeImageTranslationPersistenceSnapshot()",
        )
        for marker in (
            "imageTranslationState == .translated || imageTranslationState == .failed",
            "let sourceURL = imageTranslationSourceURL?.standardizedFileURL",
            "let sourceData = imageTranslationData",
            "sourceData.isEmpty == false",
            "Self.isImageTranslationInputFilename(sourceURL.lastPathComponent)",
            "sourceFileSHA256: Self.sha256Hex(sourceData)",
            "sourceFileByteCount: Int64(sourceData.count)",
            "ignoredBlockSnapshots: ignoredSnapshots",
            "visionOriginalBlocks: visionOriginalBlocks",
            "reviewedBlockIDs: imageTranslationReviewedBlockIDs",
            "correctedBlockIDs: imageTranslationCorrectedBlockIDs",
            "overlayMode: imageOverlayMode",
        ):
            self.assertIn(marker, body)

    def test_restore_is_fail_closed_for_path_file_identity_and_state(self) -> None:
        restore = function_body(
            self.store,
            "private func restoreImageTranslationPersistenceSnapshot(",
        )
        validator = function_body(
            self.store,
            "private static func isValidImageTranslationPersistenceSnapshot(",
        )
        for marker in (
            "snapshot.schemaVersion == ImageTranslationPersistenceSnapshot.currentSchemaVersion",
            "snapshot.state == .translated || snapshot.state == .failed",
            "sourceFileRelativePath == URL(fileURLWithPath:",
            "isImageTranslationInputFilename(snapshot.sourceFileRelativePath)",
            "snapshot.sourceFileSHA256.count == 64",
            "sourceURL.deletingLastPathComponent() == directory",
            "destinationOfSymbolicLink(atPath: sourceURL.path)",
            "values.isRegularFile == true",
            "values.isSymbolicLink != true",
            "Int64(fileSize) == snapshot.sourceFileByteCount",
            "Data(contentsOf: sourceURL)",
            "Self.sha256Hex(data) == snapshot.sourceFileSHA256.lowercased()",
            "return false",
        ):
            self.assertIn(marker, restore + validator)

    def test_restore_preserves_baseline_provenance_order_and_review_maps(self) -> None:
        restore = function_body(
            self.store,
            "private func restoreImageTranslationPersistenceSnapshot(",
        )
        for marker in (
            "imageTranslationBlocks = snapshot.blocks",
            "imageTranslationCorrectedBlockIDs = Set(snapshot.correctedBlockIDs)",
            "imageTranslationReviewedBlockIDs = Set(snapshot.reviewedBlockIDs)",
            "imageTranslationOriginalBlockOrder = Dictionary(",
            "visionOriginalBlock: persisted.visionOriginalBlock",
            "imageTranslationVisionOriginalBlocks = Dictionary(",
            "snapshot.visionOriginalBlocks.map",
            "imageOverlayMode = snapshot.overlayMode",
            "refreshImageTranslationIgnoredBlocks()",
        ):
            self.assertIn(marker, restore)
        self.assertIn("automaticBoundingBox", self.models)
        self.assertIn("ocrProvenance", self.models)
        self.assertNotIn("ImageOCRShadowLedger", self.models[self.models.index("struct ImageTranslationPersistenceSnapshot:") : self.models.index("enum ModelEngine")])

    def test_startup_protects_only_authenticated_restored_input(self) -> None:
        initializer = function_body(self.store, "init(")
        self.assertLess(
            initializer.index("restoreSnapshot()"),
            initializer.index("reconcileOrphanedImageTranslationWorkspaceAtStartup()"),
        )
        startup = function_body(
            self.store,
            "private func reconcileOrphanedImageTranslationWorkspaceAtStartup()",
        )
        for marker in (
            "let restoredInputURL = imageTranslationSourceURL?.standardizedFileURL",
            "managedFile != restoredInputURL",
            "imageTranslationOwnedOrphanURLs.insert(managedFile)",
            "discardImageTranslationExport()",
        ):
            self.assertIn(marker, startup)

    def test_lifecycle_clears_or_rewrites_snapshot(self) -> None:
        for signature in (
            "private func beginImageTranslationTask(",
            "func clearImageTranslation()",
            "func cancelImageTranslation()",
            "private func finishImageTranslation(taskID: UUID, with error: Error)",
            "private func finishPhotoLibraryTransfer(taskID: UUID, with error: Error)",
        ):
            self.assertIn("persist()", function_body(self.store, signature))
        persist = function_body(self.store, "private func persist()")
        self.assertIn("imageTranslationSession: makeImageTranslationPersistenceSnapshot()", persist)
        export = function_body(self.store, "func exportSnapshot()")
        self.assertIn("imageTranslationSession: makeImageTranslationPersistenceSnapshot()", export)

    def test_scoped_mutations_and_transient_ledger_boundary_remain_explicit(self) -> None:
        for signature in (
            "func ignoreImageTranslationBlock(",
            "func restoreIgnoredImageTranslationBlock(",
            "func restoreAllIgnoredImageTranslationBlocks()",
            "func rerecognizeImageTranslationBlock(",
        ):
            self.assertIn("persist()", function_body(self.store, signature))
        snapshot = self.models[self.models.index("struct ImageTranslationPersistenceSnapshot:") : self.models.index("enum ModelEngine")]
        self.assertNotIn("ImageOCRShadowLedger", snapshot)
        self.assertIn("ocrProvenance", snapshot + self.models)

    def test_route_workflow_version_and_no_runtime_entry(self) -> None:
        for marker in (
            "scripts/test-v3289-image-translation-session-persistence-contract.py",
            "图片会话跨重启快照",
            "SHA-256",
            "旧 JSON",
            "fail closed",
        ):
            self.assertIn(marker, self.workflow + self.route + self.store)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.322", "3.322"],
        )
        contract = read("scripts/test-v3289-image-translation-session-persistence-contract.py")
        for source in (contract,):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
