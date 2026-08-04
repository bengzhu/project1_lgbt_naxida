#!/usr/bin/env python3
"""Contracts for v3.92 image OCR risk filters and report-only manga triage filtering."""

from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def braced_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unterminated body: {signature}")


class ImageReviewRiskFilterContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.filter = read("AITRANS/Models/ImageOCRReviewFilter.swift")
        self.summary = read("AITRANS/Models/ImageOCRResultSummary.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.developer_view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_product_filter_has_two_explicit_risk_subsets(self) -> None:
        self.assertIn('case lowConfidence = "低置信"', self.filter)
        self.assertIn('case unknownDirection = "方向待定"', self.filter)
        self.assertIn("ImageOCRResultSummary.hasLowConfidence($0)", self.filter)
        self.assertIn("ImageOCRResultSummary.hasUnknownDirection($0)", self.filter)
        self.assertIn("blocks.filter { ImageOCRResultSummary.requiresReview($0) }", self.filter)
        self.assertIn("static func hasLowConfidence", self.summary)
        self.assertIn("static func hasUnknownDirection", self.summary)

    def test_filter_is_local_and_does_not_change_product_pipeline(self) -> None:
        self.assertIn("@State private var reviewFilter: ImageOCRReviewFilter = .all", self.view)
        self.assertNotIn("ImageOCRReviewFilter", self.store)
        self.assertIn('Picker("识别结果筛选", selection: $reviewFilter)', self.view)
        self.assertIn("reviewFilter.blocks(from: store.imageTranslationBlocks)", self.view)
        preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        self.assertIn("ForEach(store.imageTranslationBlocks)", preview)
        self.assertNotIn("visibleImageTranslationBlocks", preview)
        self.assertIn("let filteredBlocksBeforeMutation = visibleImageTranslationBlocks", self.view)
        self.assertIn("reviewFilter == .all", self.view)

    def test_filter_labels_and_empty_states_explain_each_risk(self) -> None:
        self.assertIn('"低置信 \\(ImageOCRReviewFilter.lowConfidence.blocks', self.view)
        self.assertIn('"方向待定 \\(ImageOCRReviewFilter.unknownDirection.blocks', self.view)
        self.assertIn("private var reviewFilterAccessibilityHint", self.view)
        self.assertIn("private var filterEmptyStateDetail", self.view)
        self.assertIn('title: "当前筛选没有结果"', self.view)
        self.assertIn("已复查的风险块仍会保留", self.view)

    def test_manga_filter_is_report_only_and_uses_existing_signals(self) -> None:
        self.assertIn("private enum MangaProbeDiagnosticFilter", self.developer_view)
        self.assertIn("@State private var diagnosticFilter: MangaProbeDiagnosticFilter = .all", self.developer_view)
        self.assertIn("MangaProbeDiagnosticFilterControl", self.developer_view)
        self.assertIn("filteredProbeBlocks", self.developer_view)
        self.assertIn("noisyOCRSuspectBlocks", self.developer_view)
        self.assertIn("noisyModelFloorBlocks", self.developer_view)
        self.assertIn("noisyTranslationLanguageQualityBlocks", self.developer_view)
        self.assertIn("renderTextTruncatedBlocks", self.developer_view)
        self.assertIn("block.failureCategory == \"ocrInputSuspect\"", self.developer_view)
        self.assertIn("block.failureCategory == \"modelOutputFailure\"", self.developer_view)
        self.assertIn("block.failureCategory == \"translationLanguageQualityFailure\"", self.developer_view)
        self.assertIn("只筛选下方逐块诊断结果，不修改 probe_report", self.developer_view)
        self.assertNotIn("diagnosticFilter =", self.store)

    def test_version_and_ci_route(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 92) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.91;", self.project)
        self.assertIn("scripts/test-v392-image-review-risk-filter-contract.py", self.workflow)
        self.assertIn("python3 -B scripts/test-v392-image-review-risk-filter-contract.py", self.workflow)
        self.assertLess(
            self.workflow.index("python3 -B scripts/test-v381-image-selection-focus-contract.py"),
            self.workflow.index("python3 -B scripts/test-v392-image-review-risk-filter-contract.py"),
        )

    def test_executable_filter_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v392-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v392-image-review-risk-filter"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                    "AITRANS/Models/ImageOCRResultSummary.swift",
                    "AITRANS/Models/ImageOCRReviewFilter.swift",
                    "scripts/test-v392-image-review-risk-filter-evaluator.swift",
                    "-o", str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(executable)], cwd=ROOT, check=True, capture_output=True, text=True
            )
            self.assertIn("v3.92 image review risk filter evaluator passed", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
