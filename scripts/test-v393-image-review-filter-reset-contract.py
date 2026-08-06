#!/usr/bin/env python3
"""Contract for resetting the local image OCR review filter on content revisions."""

from pathlib import Path
import re
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


class ImageReviewFilterResetContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_revision_change_resets_local_filter_with_other_view_selection(self) -> None:
        revision_handler = braced_body(
            self.view,
            ".onChange(of: store.imageTranslationRevision) { _, _ in",
        )
        self.assertRegex(
            revision_handler,
            r"reviewFilter = \.all|prepareReviewFilterChange\(\s*to: \.all",
        )
        self.assertIn("selectedImageTranslationBlockID = nil", revision_handler)
        self.assertIn("editingImageTranslationBlock = nil", revision_handler)
        self.assertIn("reviewAccessibilityFocusID = nil", revision_handler)

    def test_filter_remains_view_private_and_revision_is_store_signal_only(self) -> None:
        self.assertIn("@State private var reviewFilter: ImageOCRReviewFilter = .all", self.view)
        self.assertNotIn("reviewFilter", self.store)
        self.assertIn("imageTranslationRevision += 1", self.store)

    def test_version_and_ci_route(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 93) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.92;", self.project)
        self.assertIn("scripts/test-v393-image-review-filter-reset-contract.py", self.workflow)
        old = "python3 -B scripts/test-v392-image-review-risk-filter-contract.py"
        new = "python3 -B scripts/test-v393-image-review-filter-reset-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
