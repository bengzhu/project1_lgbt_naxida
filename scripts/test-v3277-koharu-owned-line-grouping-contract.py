#!/usr/bin/env python3
"""Static contract for Koharu block_index owner-first line grouping."""

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


class KoharuOwnedLineGroupingContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.runtime = read(
            "scripts/test-v3277-koharu-owned-line-grouping-runtime.sh"
        )
        cls.evaluator = read(
            "scripts/fixtures/v3277-koharu-owned-line-grouping-evaluator.swift"
        )
        cls.layout_entry = braced_body(cls.layout, "static func layout(")
        cls.cluster = braced_body(cls.layout, "private static func cluster(")
        cls.ownerless_merge = braced_body(
            cls.layout,
            "private static func shouldMergeOwnerlessVertically(",
        )
        cls.block = braced_body(cls.layout, "var block: ImageOCRLayoutBlock")

    def test_owner_first_grouping_is_vertical_manga_only(self) -> None:
        self.assertIn(
            "groupsVerticalTextRegionsByOwner: prefersMangaReadingOrder",
            self.layout_entry,
        )
        self.assertIn(
            "if direction == .vertical, groupsVerticalTextRegionsByOwner",
            self.cluster,
        )
        self.assertIn("var clusterIndexByOwner: [Int: Int] = [:]", self.cluster)
        self.assertIn("clusterIndexByOwner[owner]", self.cluster)
        self.assertIn("clusters[clusterIndex].append(observation)", self.cluster)
        self.assertIn(
            "remaining = observations.filter { $0.verticalTextRegionOwner == nil }",
            self.cluster,
        )

    def test_ownerless_fallback_cannot_bridge_known_owners(self) -> None:
        self.assertIn("knownOwnerMatchCount", self.cluster)
        self.assertIn("containsKnownVerticalTextRegionOwner", self.cluster)
        self.assertIn("if knownOwnerMatchCount > 1", self.cluster)
        self.assertIn("compatibleIndices.removeAll", self.cluster)
        self.assertIn("shouldMergeOwnerlessVertically(", self.cluster)
        self.assertIn("cluster.observations.contains", self.ownerless_merge)
        self.assertIn("let existingLineCluster = Cluster(existingLine)", self.ownerless_merge)
        self.assertIn(
            "shouldMergeVertically(line, into: existingLineCluster)",
            self.ownerless_merge,
        )
        self.assertIn(
            "shouldMergeVertically(existingLine, into: ownerlessCluster)",
            self.ownerless_merge,
        )

    def test_block_keeps_koharu_line_order_and_mean_confidence(self) -> None:
        self.assertIn("let orderedObservations = observations.sorted", self.block)
        self.assertIn(
            "if $0.rect.y != $1.rect.y { return $0.rect.y < $1.rect.y }",
            self.block,
        )
        self.assertIn("orderedObservations.map { $0.text }.joined()", self.block)
        self.assertIn(
            "observations.reduce(Float(0)) { $0 + $1.observation.confidence } / Float(observations.count)",
            self.block,
        )

    def test_cloud_evaluator_covers_grouping_boundaries(self) -> None:
        for marker in (
            "distantSameOwner.count == 1",
            'distantSameOwner[0].text == "上下"',
            "distantSameOwner[0].confidence - 0.5",
            "distantDistinctOwners.count == 2",
            "distantOwnerless.count == 2",
            "ambiguousOwnerless.count == 3",
            "unambiguousOwnerless.count == 1",
            "ownerlessAboveKnown.count == 1",
            "ownerUnionTrap.count == 2",
            "nonManga.count == 2",
        ):
            self.assertIn(marker, self.evaluator)
        self.assertIn("xcrun swiftc -parse-as-library", self.runtime)
        self.assertIn(
            "v3277-koharu-owned-line-grouping-evaluator.swift",
            self.runtime,
        )

    def test_ci_routes_contract_and_cloud_runtime(self) -> None:
        for path in (
            "scripts/test-v3277-koharu-owned-line-grouping-contract.py",
            "scripts/test-v3277-koharu-owned-line-grouping-runtime.sh",
        ):
            self.assertGreaterEqual(self.workflow.count(path), 3)

    def test_version_is_3277(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project),
            ["3.338", "3.338"],
        )


if __name__ == "__main__":
    unittest.main()
