#!/usr/bin/env python3
"""Contract for bounded recovery of weak compact Japanese detector crops."""

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


class JapaneseCompactCropRecoveryContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.recognition = braced_body(
            self.vision,
            "func recognizeTextBlocks(in imageData: Data",
        )
        self.recovery = braced_body(
            self.vision,
            "private static func preferCompactJapaneseCropRecovery(",
        )
        self.runtime = read(
            "scripts/test-v3214-image-japanese-manga-ocr-runtime.sh"
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_recovery_runs_after_bounded_vision_crop_reread(self) -> None:
        crop = self.recognition.index("let cropRefinedObservations")
        recovery = self.recognition.index(
            "Self.preferCompactJapaneseCropRecovery("
        )
        self.assertLess(crop, recovery)
        self.assertIn(
            "detectorObservations: detectorMangaOCRObservations",
            self.recognition,
        )

    def test_weak_detector_owner_gate_is_strict_and_local(self) -> None:
        for marker in [
            "owner.preservesDetectorTextRegionBoundary",
            "owner.confidence < 0.80",
            "owner.rect.width <= 0.08",
            "owner.rect.height <= 0.08",
            "ownerText.unicodeScalars.count <= 4",
            "candidate.observationRole == .crop",
            "|| candidate.observationRole == .verticalLine",
            "candidate.sourceDirectionHint == .vertical",
            "candidate.confidence >= 0.40",
            "overlapRatio(candidate.rect, owner.rect) >= 0.70",
            "candidate.rect.width <= max(owner.rect.width * 3.0, 0.08)",
            "candidate.rect.height <= max(owner.rect.height * 2.5, 0.08)",
            "output.remove(at: ownerIndex)",
        ]:
            self.assertIn(marker, self.recovery)

    def test_content_gate_requires_more_japanese_letters(self) -> None:
        self.assertIn(
            "japaneseLetterCountForRecovery(candidate.text)\n                              > ownerLetters",
            self.recovery,
        )
        for marker in [
            "private static func japaneseLetterCountForRecovery(",
            "0x3041...0x3096",
            "0x30A1...0x30FA",
            "0x4E00...0x9FFF",
        ]:
            self.assertIn(marker, self.vision)

    def test_bbox_primary_and_existing_budget_boundaries_remain(self) -> None:
        for marker in [
            "private static func recognizeJapaneseMangaOCR(",
            "Array(regions.prefix(12))",
            "maximumRequests = 48",
            "sourceDirectionHint: .vertical",
            "observationRole: .detectorTextRegion",
            "preservesDetectorTextRegionBoundary:",
        ]:
            self.assertIn(marker, self.vision)
        self.assertNotIn("MangaOCRRequest(\n                    textRect: candidate", self.vision)

    def test_fixed_fixture_promotes_compact_panel_without_changing_main_blocks(self) -> None:
        self.assertIn('"ニコッ"', self.runtime)
        self.assertIn('"vertical\\tこっ、"', self.runtime)
        self.assertIn('r"^blocks=(\\d+)$"', self.runtime)
        self.assertIn('"前は生意気に俺の誘い断りやがって．．．"', self.runtime)
        self.assertIn('"今度こそこの爆乳を持ち帰る！"', self.runtime)

    def test_version_and_ci_route_follow_v3251(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 252) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.251;", self.project)
        previous = "python3 -B scripts/test-v3251-image-ocr-rerecognition-focus-origin-contract.py"
        current = "python3 -B scripts/test-v3252-image-japanese-compact-crop-recovery-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3252-image-japanese-compact-crop-recovery-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
