#!/usr/bin/env python3
"""Contract for v3.131 bulk recovery of ignored image OCR blocks."""

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


class ImageIgnoredBlocksBulkRestoreContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.bulk_store = braced_body(
            self.store,
            "func restoreAllIgnoredImageTranslationBlocks()",
        )

    def test_store_bulk_restore_is_translated_scoped_and_preserves_block_metadata(self) -> None:
        for marker in [
            "imageTranslationCorrectionBlockID == nil",
            "imageTranslationState == .translated",
            "imageTranslationIgnoredBlockSnapshots.values.sorted",
            "snapshot.originalOrder",
            "imageTranslationBlocks.insert(snapshot.block, at: insertionIndex)",
            "if snapshot.wasManuallyCorrected",
            "imageTranslationVisionOriginalBlocks[snapshot.block.id] = visionOriginalBlock",
            "imageTranslationReviewedBlockIDs.remove(snapshot.block.id)",
            "imageTranslationIgnoredBlockSnapshots.removeAll",
            "refreshImageTranslationIgnoredBlocks()",
            "synchronizeImageTranslationTranscript(blocks: imageTranslationBlocks)",
            "invalidateImageOverlayRender()",
            "discardImageTranslationExport()",
            "rerenderImageTranslationExport()",
        ]:
            self.assertIn(marker, self.bulk_store)
        self.assertIn(
            "func restoreAllIgnoredImageTranslationBlocks() -> [UUID]",
            self.store,
        )
        self.assertNotIn("translate(", self.bulk_store)
        self.assertNotIn("VisionOCRService", self.bulk_store)

    def test_panel_exposes_confirmed_visible_bulk_action_with_state_lock(self) -> None:
        ignored_section = braced_body(
            self.panel,
            "if !store.imageTranslationIgnoredBlocks.isEmpty {\n                AppSectionHeader",
        )
        for marker in [
            'title: "已忽略的文字块"',
            'title: "恢复全部 \\(store.imageTranslationIgnoredBlocks.count)"',
            "action: requestRestoreAllIgnoredImageTranslationBlocks",
            ".disabled(!canModifyImageTranslation)",
            "imageModificationUnavailableDetail",
            "ForEach(store.imageTranslationIgnoredBlocks)",
        ]:
            self.assertIn(marker, ignored_section)
        self.assertIn('"恢复全部已忽略文字块？"', self.panel)
        self.assertIn("showRestoreAllIgnoredConfirmation", self.panel)
        self.assertIn("恢复全部文字块", self.panel)
        self.assertIn("需要复查的文字块会重新回到待复查队列", self.panel)

    def test_panel_bulk_action_restores_all_then_reuses_filter_and_focus_paths(self) -> None:
        request = braced_body(
            self.panel,
            "private func requestRestoreAllIgnoredImageTranslationBlocks()",
        )
        self.assertIn("canModifyImageTranslation", request)
        self.assertIn("!store.imageTranslationIgnoredBlocks.isEmpty", request)
        self.assertIn("showRestoreAllIgnoredConfirmation = true", request)

        restore = braced_body(
            self.panel,
            "private func restoreAllIgnoredImageTranslationBlocks()",
        )
        for marker in [
            "canModifyImageTranslation",
            "store.restoreAllIgnoredImageTranslationBlocks()",
            "restoredBlockIDs.first",
            "prepareReviewFilterChange(to: .all, focusID: focusID)",
            "selectedImageTranslationBlockID = firstRestoredBlockID",
            "moveReviewAccessibilityFocus(to: focusID)",
        ]:
            self.assertIn(marker, restore)

    def test_revision_change_dismisses_stale_bulk_confirmation(self) -> None:
        revision = braced_body(self.panel, ".onChange(of: store.imageTranslationRevision)")
        self.assertIn("showRestoreAllIgnoredConfirmation = false", revision)

    def test_bulk_restore_does_not_add_persistence_or_pipeline_work(self) -> None:
        persist = braced_body(self.store, "private func persist()")
        self.assertNotIn("restoreAllIgnoredImageTranslationBlocks", persist)
        self.assertNotIn("imageTranslationIgnoredBlockSnapshots", persist)
        self.assertNotIn("runImageTranslationPipeline", self.bulk_store)

    def test_version_and_ci_route_follow_v3130(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 131) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.130;", self.project)
        script = "scripts/test-v3131-image-ignored-blocks-bulk-restore-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3130-manga-diagnostic-filter-empty-action-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))
        self.assertRegex(
            self.workflow,
            r"test-v3\(1\[1-9\]|\[2-7\]\[0-9\]|8\[01\]|12\[2-9\]|13\[0-1\]\)-",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
