#!/usr/bin/env python3
"""Contracts for v3.64 image confidence safety."""

from pathlib import Path
import os
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
                return source[brace:index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageConfidenceSafetyContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.summary = read("AITRANS/Models/ImageOCRResultSummary.swift")
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_product_summary_normalizes_non_finite_confidence(self) -> None:
        normalized = braced_body(self.summary, "static func normalizedConfidence")
        self.assertIn("rawConfidence.isFinite", normalized)
        self.assertIn("return 0", normalized)
        self.assertIn("Double(Self.normalizedConfidence($0.confidence))", self.summary)
        self.assertIn("let threshold = normalizedConfidence(lowConfidenceThreshold)", self.summary)
        self.assertIn("let confidence = normalizedConfidence(block.confidence)", self.summary)

    def test_layout_and_views_share_finite_confidence_boundary(self) -> None:
        self.assertTrue(
            "let safeObservations = observations.map" in self.layout
            or "let safeObservations = observations.compactMap" in self.layout
        )
        self.assertIn("safeObservation.confidence = normalizedConfidence(observation.confidence)", self.layout)
        self.assertIn("among: safeObservations", self.layout)
        self.assertGreaterEqual(
            self.view.count("ImageOCRResultSummary.normalizedConfidence(block.confidence)"),
            3,
        )

    def test_executable_evaluator_uses_product_summary_model(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v364-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v364-image-confidence-safety"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                    "AITRANS/Models/ImageOCRResultSummary.swift",
                    "scripts/test-v364-image-confidence-safety-evaluator.swift",
                    "-o", str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run([str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertIn("v3.64 image confidence safety evaluator passed", result.stdout)

    def test_version_and_ci_route_follow_v363(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.63;", self.project)
        old = "python3 -B scripts/test-v363-image-summary-accessibility-context-contract.py"
        new = "python3 -B scripts/test-v364-image-confidence-safety-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
