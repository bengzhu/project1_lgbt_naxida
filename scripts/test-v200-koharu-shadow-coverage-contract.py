#!/usr/bin/env python3
"""Contracts for v2.0 stable external TextBox shadow OCR coverage."""

from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def stable_maximum_matching(edges: dict[int, list[str]]) -> dict[int, str]:
    """Executable fixture for the augmenting-path contract used by Swift."""
    owner_by_textbox: dict[str, int] = {}
    assignment_by_block: dict[int, str] = {}

    def assign(block_index: int, visited: set[str]) -> bool:
        for textbox_id in edges.get(block_index, []):
            if textbox_id in visited:
                continue
            visited.add(textbox_id)
            owner = owner_by_textbox.get(textbox_id)
            if owner is not None and not assign(owner, visited):
                continue
            owner_by_textbox[textbox_id] = block_index
            assignment_by_block[block_index] = textbox_id
            return True
        return False

    for block_index in sorted(edges):
        assign(block_index, set())
    return assignment_by_block


class KoharuShadowCoverageContractTests(unittest.TestCase):
    def test_swift_matcher_evaluator_and_legacy_decode(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v200-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v200-shadow-coverage-contract"
            module_cache = Path(temporary_directory) / "module-cache"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-module-cache-path",
                    str(module_cache),
                    "AITRANS/Models/ImageOCRProvenance.swift",
                    "AITRANS/Services/ImageOCRLayoutEngine.swift",
                    "AITRANS/Models/TranslationContextQuality.swift",
                    "AITRANS/Models/TranscriptModels.swift",
                    "scripts/test-v200-koharu-shadow-coverage-evaluator.swift",
                    "-o",
                    str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(executable)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("v2.0 Swift shadow coverage contract passed", result.stdout)

    def test_matching_is_one_to_one_and_uses_augmenting_paths(self) -> None:
        assignment = stable_maximum_matching({0: ["box-a", "box-b"], 1: ["box-a"]})
        self.assertEqual(assignment, {0: "box-b", 1: "box-a"})
        self.assertEqual(len(set(assignment.values())), len(assignment))
        self.assertEqual(stable_maximum_matching({0: ["box-a"], 1: ["box-a"]}), {0: "box-a"})

        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertIn("stableOneToOneExternalTextBoxShadowMatching", store)
        models = read("AITRANS/Models/TranscriptModels.swift")
        self.assertIn("ownerByTextBoxID", models)
        self.assertIn("assign(currentOwner, visitedTextBoxIDs: &visitedTextBoxIDs)", models)
        self.assertIn('return $0.textBox.id < $1.textBox.id', store)
        self.assertNotIn("selectExternalTextBoxShadowCandidate(", store)

    def test_report_exposes_partition_ratios_and_duplicate_ledger(self) -> None:
        models = read("AITRANS/Models/TranscriptModels.swift")
        for field in [
            "evaluatedBlockCount",
            "matchedBlockIndexes",
            "succeededBlockIndexes",
            "failedBlockIndexes",
            "uniqueMatchedTextBoxCount",
            "duplicateAssignmentLedgers",
            "duplicateAssignedTextBoxIDs",
            "matchedCoverageRatio",
            "successfulCoverageRatio",
            "matchedOCRSuccessRatio",
            "coverageVerdict",
        ]:
            self.assertIn(f"var {field}:", models)
        self.assertIn("struct MangaOverlayExternalTextBoxDuplicateAssignmentLedger", models)
        self.assertIn(
            'id = (try? container.decode(String.self, forKey: .id)) ?? ""',
            models,
        )
        self.assertIn("MangaOverlayExternalTextBoxCoverageEvaluator.evaluate(", read("AITRANS/Services/TranslationSessionStore.swift"))

    def test_missing_and_duplicate_textbox_ids_are_rejected(self) -> None:
        result = subprocess.run(
            [
                "python3",
                "-B",
                "scripts/validate-koharu-artifacts.py",
                "--root",
                "md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid",
                "--expect-fail",
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        report = json.loads(result.stdout)
        self.assertIn("textBoxIDMissing:3", report["coordinateErrors"])
        self.assertIn("textBoxIDMissing:5", report["coordinateErrors"])
        self.assertIn(
            "duplicateTextBoxID:bad-textbox-line-polygon-detached",
            report["coordinateErrors"],
        )
        self.assertNotIn("parseFailed", " ".join(report["parseErrors"]))
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertIn('errors.append("textBoxIDMissing:', store)
        self.assertIn('errors.append("duplicateTextBoxID:', store)

    def test_partial_coverage_cannot_close_convergence_gate(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertIn('externalShadowCoverageVerdict == "complete"', store)
        for ledger in [
            "externalShadowFailedBlocks",
            "externalShadowSkippedBlocks",
            "externalShadowGeometryWeakBlocks",
            "externalShadowGeometryUnknownBubbleBlocks",
        ]:
            self.assertIn(ledger, store)
        self.assertIn('externalShadowCoverageWorkItemStatus = "blockedByPartialExternalShadowOCRCoverage"', store)
        self.assertIn('signal("successfulCoverageRatio"', store)
        self.assertIn("successfulCoverageRatio == 1", store)

    def test_ci_and_txt_require_complete_per_block_coverage(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        for needle in [
            "scripts/test-v200-koharu-shadow-coverage-contract.py",
            'external_shadow.get("coverageVerdict") != "complete"',
            'external_shadow.get("duplicateAssignedTextBoxIDs")',
            '"successfulCoverageRatio": (external_shadow or {}).get("successfulCoverageRatio")',
        ]:
            self.assertIn(needle, workflow)
        probe = read("AITRANS/Services/MangaOverlayProbeService.swift")
        self.assertIn("successfulCoverage=", probe)
        self.assertIn("coverageVerdict=", probe)


if __name__ == "__main__":
    unittest.main(verbosity=2)
