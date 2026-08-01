#!/usr/bin/env python3
"""Contract for hiding the decorative focus-preview badge from VoiceOver."""

from pathlib import Path
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


class FocusPreviewDecorativeLabelContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.reference = braced_body(
            self.view,
            "private struct ImageOCRCorrectionReferencePreview: View",
        )
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )

    def test_focus_badge_is_decorative_but_parent_context_remains(self) -> None:
        badge = self.focus[
            self.focus.index('Label("局部放大", systemImage: "magnifyingglass")'):
        ]
        badge = badge[:badge.index("        .overlay(alignment: .topTrailing)")]
        self.assertIn('Label("局部放大", systemImage: "magnifyingglass")', badge)
        self.assertIn(".accessibilityHidden(true)", badge)
        self.assertIn('.accessibilityLabel("已定位文字块局部放大")', self.focus)
        self.assertIn(".accessibilityValue(\"\\(positionText)，\\(accessibilityOriginalText)\")", self.focus)

    def test_reference_badge_already_remains_decorative(self) -> None:
        badge = self.reference[
            self.reference.index('Label("当前文字块", systemImage: "viewfinder")'):
        ]
        badge = badge[:badge.index("        .accessibilityHidden(true)") + len("        .accessibilityHidden(true)")]
        self.assertIn(".accessibilityHidden(true)", badge)

    def test_change_is_view_only(self) -> None:
        for body in (self.reference, self.focus):
            self.assertNotIn("TranslationSessionStore", body)
            self.assertNotIn("VisionOCRService", body)
            self.assertNotIn("FileManager", body)
            self.assertNotIn("runMangaOverlayProbe", body)
            self.assertNotIn("store.", body)

    def test_version_and_ci_route_follow_v375(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.76;", self.project)
        old = "python3 -B scripts/test-v375-image-focus-empty-ocr-context-contract.py"
        new = "python3 -B scripts/test-v376-image-focus-preview-decorative-label-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75|76|77|78)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
