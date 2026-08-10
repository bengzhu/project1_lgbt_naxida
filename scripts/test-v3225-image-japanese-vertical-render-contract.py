#!/usr/bin/env python3
"""Contract for consuming Koharu source direction in image rendering."""

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


class JapaneseVerticalRenderContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.models = read("AITRANS/Models/TranscriptModels.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.reference = read("reference/koharu-main/koharu-renderer/src/text/script.rs")
        self.block = braced_body(self.models, "struct ImageTranslationBlock:")
        self.overlay = braced_body(
            self.view,
            "private struct ImageTranslationOverlayBlock: View",
        )
        self.vertical_view = braced_body(
            self.view,
            "private struct ImageTranslationVerticalText: View",
        )
        self.renderer = braced_body(
            self.store,
            "nonisolated private static func renderImageTranslationOverlay(",
        )
        self.draw = braced_body(
            self.store,
            "nonisolated private static func drawImageTranslationText(",
        )

    def test_shared_block_matches_koharu_cjk_source_direction_gate(self) -> None:
        self.assertIn("var prefersVerticalWriting: Bool", self.block)
        self.assertIn("guard sourceDirection == .vertical else { return false }", self.block)
        self.assertIn("let displayedText = translation.isEmpty ? original : translation", self.block)
        for marker in [
            "0x3041...0x3096",
            "0x30A1...0x30FA",
            "0x4E00...0x9FFF",
            "displayedText.unicodeScalars.contains",
        ]:
            self.assertIn(marker, self.block)
        self.assertIn("Some(TextDirection::Vertical) => WritingMode::VerticalRl", self.reference)
        self.assertIn("Some(TextDirection::Horizontal) => WritingMode::Horizontal", self.reference)

    def test_preview_uses_vertical_columns_only_for_replace_mode(self) -> None:
        self.assertIn("if block.prefersVerticalWriting", self.overlay)
        self.assertIn("ImageTranslationVerticalText(text: text)", self.overlay)
        self.assertIn("case .adjacent:", self.overlay)
        self.assertIn("case .replace:", self.overlay)
        self.assertIn("columns.indices.reversed()", self.vertical_view)
        self.assertIn("rowCapacity", self.vertical_view)
        self.assertIn("alignment: .topTrailing", self.vertical_view)
        self.assertIn(".clipped()", self.vertical_view)

    def test_export_shares_vertical_mode_and_keeps_horizontal_fallback(self) -> None:
        for marker in [
            "let usesVerticalWriting = mode == .replace && block.prefersVerticalWriting",
            "overlayRect.width * 0.72",
            "Self.drawImageTranslationText(",
            "vertical: usesVerticalWriting",
        ]:
            self.assertIn(marker, self.renderer)
        for marker in [
            "guard vertical else {",
            "NSAttributedString(string: text, attributes: attributes).draw(",
            "rect.maxX - CGFloat(column + 1)",
            "let row = index % rowCapacity",
            "rect.minY + CGFloat(row) * rowHeight",
            "drawableCharacters = Array(characters.prefix(prefixCount)) + [\"…\"]",
        ]:
            self.assertIn(marker, self.draw)
        self.assertIn("mode == .adjacent && translation != block.original", self.renderer)

    def test_version_and_ci_route_follow_v3224(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 225) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.224;", self.project)
        previous = "python3 -B scripts/test-v3224-image-japanese-manga-ocr-resilience-contract.py"
        current = "python3 -B scripts/test-v3225-image-japanese-vertical-render-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3225-image-japanese-vertical-render-contract.py'",
            self.workflow,
        )

    def test_fixture_and_direction_model_are_present(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)
        self.assertIn("enum ImageTextDirection: String, Codable, Sendable", self.models)


if __name__ == "__main__":
    unittest.main(verbosity=2)
