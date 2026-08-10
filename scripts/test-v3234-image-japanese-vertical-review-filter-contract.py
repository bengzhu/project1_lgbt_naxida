#!/usr/bin/env python3
"""Contract for the report-only Japanese vertical OCR review filter."""

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
                return source[brace + 1 : index]
    raise AssertionError(f"unterminated body: {signature}")


class JapaneseVerticalReviewFilterContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.filter = read("AITRANS/Models/ImageOCRReviewFilter.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_vertical_filter_is_source_direction_only(self) -> None:
        self.assertIn('case vertical = "竖排"', self.filter)
        self.assertIn(
            "blocks.filter { $0.sourceDirection == .vertical }",
            self.filter,
        )
        self.assertNotIn("ImageOCRResultSummary.hasLowConfidence", self.filter.split("case .vertical:", 1)[1])
        self.assertNotIn("ImageOCRResultSummary.requiresReview", self.filter.split("case .vertical:", 1)[1])

    def test_filter_is_local_presentation_state(self) -> None:
        self.assertIn("@State private var reviewFilter: ImageOCRReviewFilter = .all", self.view)
        self.assertNotIn("ImageOCRReviewFilter", self.store)
        self.assertIn('Picker("识别结果筛选", selection: $reviewFilter)', self.view)
        self.assertIn("reviewFilter.blocks(from: store.imageTranslationBlocks)", self.view)

    def test_labels_and_accessibility_explain_vertical_review(self) -> None:
        self.assertIn('"竖排 \\(ImageOCRReviewFilter.vertical.blocks', self.view)
        self.assertIn("case .vertical:", self.view)
        self.assertIn("来源方向为竖排", self.view)
        self.assertIn("当前没有竖排文字块", self.view)
        self.assertIn("低置信、方向待定或竖排", self.view)

    def test_preview_and_export_remain_unfiltered(self) -> None:
        preview = braced_body(self.view, "private struct ImageTranslationPreview: View")
        rerender = braced_body(self.store, "private func rerenderImageTranslationExport()")
        self.assertIn("ForEach(store.imageTranslationBlocks)", preview)
        self.assertNotIn("visibleImageTranslationBlocks", preview)
        self.assertIn("let blocks = imageTranslationBlocks", rerender)
        self.assertIn("blocks: blocks", rerender)

    def test_executable_filter_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v3234-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v3234-image-japanese-vertical-review-filter"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                    "AITRANS/Models/ImageOCRResultSummary.swift",
                    "AITRANS/Models/ImageOCRReviewFilter.swift",
                    "scripts/test-v3234-image-japanese-vertical-review-filter-evaluator.swift",
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
            self.assertIn("v3.234 Japanese vertical review filter evaluator passed", result.stdout)

    def test_version_and_ci_route_follow_v3233(self) -> None:
        previous = "python3 -B scripts/test-v3233-image-japanese-line-quad-coverage-contract.py"
        current = "python3 -B scripts/test-v3234-image-japanese-vertical-review-filter-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3234-image-japanese-vertical-review-filter-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 234) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.233;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
