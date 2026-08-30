#!/usr/bin/env python3
"""Static contract for Koharu-style vertical line owner partitioning."""

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


class KoharuLineOwnerBoundaryContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        cls.manga = read("AITRANS/Services/MangaOCRService.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.runtime = read(
            "scripts/test-v3276-koharu-line-owner-layout-runtime.sh"
        )
        cls.evaluator = read(
            "scripts/fixtures/v3276-koharu-line-owner-layout-evaluator.swift"
        )
        cls.line_path = braced_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        cls.line_ocr = braced_body(
            cls.vision,
            "private static func recognizeJapaneseMangaLineOCR(",
        )
        cls.owner_compatibility = braced_body(
            cls.vision,
            "private static func verticalTextRegionOwnersCompatible(",
        )
        cls.block_ownership = braced_body(
            cls.vision,
            "private static func japaneseObservation(",
        )
        cls.compact_promotion = braced_body(
            cls.vision,
            "private static func promoteCompactJapaneseHorizontalObservations(",
        )

    def test_unique_vertical_block_assigns_ephemeral_owner(self) -> None:
        for marker in [
            ".prefix(16)\n        .enumerated()",
            "owned.verticalTextRegionOwner = index",
            "verticalTextRegionMatchIndices(",
            "ownerMatches.count == 1",
            "blocks[ownerMatches[0]]",
            ".verticalTextRegionOwner",
        ]:
            self.assertIn(marker, self.vision)
        self.assertIn("matchingBlocks.count == 1", self.vision)
        self.assertIn("let owner = block.verticalTextRegionOwner", self.vision)

    def test_owner_survives_crop_mapping_manga_batch_and_result_matching(self) -> None:
        for marker in [
            "verticalTextRegionOwner: candidate.verticalTextRegionOwner",
            "mapped.verticalTextRegionOwner = verticalTextRegionOwner",
            "verticalTextRegionOwner: request.verticalTextRegionOwner",
            "$0.verticalTextRegionOwner == result.verticalTextRegionOwner",
            "verticalTextRegionOwner: result.verticalTextRegionOwner",
        ]:
            self.assertIn(marker, self.vision + self.manga)
        self.assertIn("var verticalTextRegionOwner: Int?", self.manga)
        self.assertIn("verticalTextRegionOwner: Int? = nil", self.manga)
        self.assertIn("catch is CancellationError", self.line_ocr)
        self.assertIn("throw CancellationError()", self.line_ocr)

    def test_known_owners_are_hard_dedupe_and_block_partitions(self) -> None:
        self.assertIn("guard verticalTextRegionOwnersCompatible(lhs, rhs)", self.vision)
        self.assertIn("return lhsOwner == rhsOwner", self.owner_compatibility)
        self.assertIn("return true", self.owner_compatibility)
        self.assertIn("return observationOwner == blockOwner", self.block_ownership)
        self.assertIn("return true", self.block_ownership)
        for marker in [
            "japaneseObservation(observation, belongsTo: block)",
            "japaneseObservation($0, belongsTo: block)",
        ]:
            self.assertIn(marker, self.vision)
        self.assertGreaterEqual(
            self.vision.count("japaneseObservation(observation, belongsTo: block)"),
            6,
        )

    def test_layout_clusters_cannot_join_distinct_known_owners(self) -> None:
        for marker in [
            "var verticalTextRegionOwner: Int? = nil",
            "cluster.allows(verticalTextRegionOwner: line.verticalTextRegionOwner)",
            "compactMap(\\.verticalTextRegionOwner)",
            ".allSatisfy { $0 == verticalTextRegionOwner }",
            "verticalTextRegionOwner: verticalTextRegionOwner",
        ]:
            self.assertIn(marker, self.layout)
        self.assertGreaterEqual(
            self.layout.count(
                "cluster.allows(verticalTextRegionOwner: line.verticalTextRegionOwner)"
            ),
            2,
        )

    def test_owner_is_not_persisted_or_exposed_to_ui_model(self) -> None:
        translation_block = braced_body(
            self.models,
            "struct ImageTranslationBlock:",
        )
        self.assertNotIn("verticalTextRegionOwner", translation_block)
        final_mapping = self.vision[
            self.vision.index("return ImageOCRLayoutEngine.layout(") :
            self.vision.index("return try await task.value")
        ]
        self.assertNotIn("verticalTextRegionOwner:", final_mapping)

    def test_ownerless_compact_recovery_keeps_historical_block_boundary(self) -> None:
        self.assertIn("if owners.count == 1", self.compact_promotion)
        self.assertIn(
            "output[index].verticalTextRegionOwner = owners.first",
            self.compact_promotion,
        )
        self.assertIn(
            "output[index].preservesDetectorTextRegionBoundary = true",
            self.compact_promotion,
        )
        self.assertNotIn(
            "preservesDetectorTextRegionBoundary =\n"
            "                output[index].verticalTextRegionOwner != nil",
            self.compact_promotion,
        )

    def test_cloud_layout_evaluator_covers_owner_and_fallback_behavior(self) -> None:
        for marker in [
            "let distinctOwners = layout(1, 2)",
            "distinctOwners.count == 2",
            "let sameOwner = layout(7, 7)",
            "sameOwner.count == 1",
            "let ownerless = layout(nil, nil)",
            "ownerless.count == 1",
            "let mixed = layout(nil, 9)",
            "mixed.count == 1",
        ]:
            self.assertIn(marker, self.evaluator)
        self.assertIn("xcrun swiftc -parse-as-library", self.runtime)
        self.assertIn("ImageOCRLayoutEngine.swift", self.runtime)
        self.assertIn("v3276-koharu-line-owner-layout-evaluator.swift", self.runtime)

    def test_version_and_ci_route_are_current(self) -> None:
        current = "scripts/test-v3276-koharu-line-owner-boundary-contract.py"
        runtime = "scripts/test-v3276-koharu-line-owner-layout-runtime.sh"
        self.assertIn(f"# if grep -Fx '{current}'", self.workflow)
        self.assertIn(f"if grep -Fx '{current}'", self.workflow)
        self.assertIn(f"python3 -B {current}", self.workflow)
        self.assertIn(f"# if grep -Fx '{runtime}'", self.workflow)
        self.assertIn(f"if grep -Fx '{runtime}'", self.workflow)
        self.assertIn(f"bash {runtime}", self.workflow)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project),
            ["3.364", "3.364"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
