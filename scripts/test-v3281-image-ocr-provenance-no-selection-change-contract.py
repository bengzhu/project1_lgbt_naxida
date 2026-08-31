#!/usr/bin/env python3
"""Static contract for v3.281 OCR provenance shadowing.

The Swift evaluator is intentionally cloud-only: local validation checks this
contract without launching a compiler, while macOS CI runs the standalone
Codable/layout evaluator.
"""

from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def function_body(source: str, marker: str) -> str:
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening + 1:index]
    raise AssertionError(f"unclosed function body: {marker}")


class ImageOCRProvenanceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.provenance = read("AITRANS/Models/ImageOCRProvenance.swift")
        cls.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.manga = read("AITRANS/Services/MangaOCRService.swift")
        cls.detector = read("AITRANS/Services/ComicTextBubbleDetectorService.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.runtime = read("scripts/test-v3281-image-ocr-provenance-runtime.sh")
        cls.fixture = read("scripts/fixtures/v3281-image-ocr-provenance-evaluator.swift")

    def test_provenance_is_versioned_and_codable_without_benchmark_dependencies(self) -> None:
        for marker in (
            "struct ImageOCRCandidateProvenance: Equatable, Codable, Sendable",
            "struct ImageOCRCandidate: Equatable, Codable, Sendable",
            "struct ImageOCRShadowLedger: Equatable, Codable, Sendable",
            "static let currentSchemaVersion = 1",
            "var engine: ImageOCREngineID",
            "var role: ImageOCRCandidateRole",
            "var cropVariant: ImageOCRCropVariant",
            "var geometrySource: ImageOCRGeometrySource",
            "var regionID: ImageOCRRegionID?",
            "var lineID: ImageOCRLineID?",
            "var detectorConfidence: Float?",
            "var selectedCandidateIDs: [String]",
        ):
            self.assertIn(marker, self.provenance)
        self.assertNotIn("evaluate-japanese-ocr-benchmark", self.provenance)
        self.assertNotIn("groundTruth", self.provenance)
        self.assertNotIn("ImageTranslationBlock", self.provenance)

    def test_production_entry_discards_ledger_and_layout_does_not_select_by_provenance(self) -> None:
        wrapper = function_body(self.vision, "func recognizeTextBlocks(in imageData")
        self.assertIn("recognizeTextBlocksWithShadowLedger", wrapper)
        self.assertIn(".blocks", wrapper)
        self.assertIn("func recognizeTextBlocksWithShadowLedger(", self.vision)
        layout_body = function_body(self.layout, "static func layout(")
        self.assertNotIn("provenance.engine", layout_body)
        self.assertNotIn("selectionReason", layout_body)
        self.assertIn("provenance: ImageOCRBlockProvenance.make", self.layout)
        self.assertIn("shadowOnly", self.vision)
        self.assertIn("selectedByExistingFusion", self.vision)
        self.assertIn("ocrProvenance: block.provenance", self.vision)

    def test_detector_and_manga_boundaries_keep_existing_selection_inputs(self) -> None:
        self.assertIn("detector-region-", self.detector)
        self.assertIn("regionID: ImageOCRRegionID", self.detector)
        self.assertIn("regionID: region.regionID", self.vision)
        self.assertIn("lineID: candidate.candidateProvenance.lineID", self.vision)
        self.assertIn("regionID: candidate.candidateProvenance.regionID", self.vision)
        self.assertIn("block.provenance?.candidates.compactMap", self.vision)
        self.assertIn("PreferredRecognition", self.manga)
        self.assertIn("recognitionQualityRank", self.manga)
        self.assertIn("japaneseLetterCount(lineQuadFallback.text)", self.manga)
        self.assertIn("var ocrProvenance: ImageOCRBlockProvenance?", self.models)
        self.assertIn("ocrProvenance: ImageOCRBlockProvenance? = nil", self.models)
        self.assertIn("static func == (lhs: Self, rhs: Self) -> Bool", self.models)
        self.assertIn("lhs.directionReason == rhs.directionReason", self.models)
        self.assertNotIn("ImageOCRShadowLedger", self.models)

    def test_owner_identity_and_geometry_are_retained_without_becoming_persisted_layout_keys(self) -> None:
        for marker in (
            "verticalTextRegionOwner: Int?",
            "regionID: ImageOCRRegionID?",
            "lineID: ImageOCRLineID?",
            "geometrySource: ImageOCRGeometrySource",
            "rotationApplied: Int",
        ):
            self.assertIn(marker, self.provenance + self.vision + self.manga)
        self.assertIn("groupsVerticalTextRegionsByOwner", self.layout)
        self.assertIn("allSatisfy { $0 == blockOwner }", self.layout)
        self.assertIn("ImageOCRBlockProvenance.make", self.layout)
        self.assertNotIn("verticalTextRegionOwner", self.models.split("struct ImageTranslationBlock", 1)[-1].split("enum ModelEngine", 1)[0])

    def test_project_runtime_and_workflow_route_are_explicit(self) -> None:
        self.assertIn("ImageOCRProvenance.swift in Sources", self.project)
        self.assertIn('path = ImageOCRProvenance.swift;', self.project)
        self.assertIn("scripts/test-v3281-image-ocr-provenance-no-selection-change-contract.py", self.workflow)
        self.assertIn("scripts/test-v3281-image-ocr-provenance-runtime.sh", self.workflow)
        self.assertIn("xcrun swiftc -parse-as-library", self.runtime)
        for source_path in (
            "AITRANS/Models/TranscriptModels.swift",
            "AITRANS/Models/ImageOCRProvenance.swift",
            "AITRANS/Services/ImageOCRLayoutEngine.swift",
            "scripts/fixtures/v3281-image-ocr-provenance-evaluator.swift",
        ):
            self.assertIn(source_path, self.runtime)
        self.assertNotIn("xcodebuild", self.runtime)
        self.assertNotIn("cargo", self.runtime)
        self.assertIn("v3.281 image OCR provenance evaluator passed", self.fixture)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.384", "3.384"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
