#!/usr/bin/env python3
"""Contract for Koharu-style Japanese vertical punctuation rendering."""

from pathlib import Path
import os
import re
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
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class JapaneseVerticalPunctuationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.models = read("AITRANS/Models/TranscriptModels.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.layout = braced_body(
            self.models,
            "enum ImageTranslationVerticalTextLayout",
        )
        self.preview = braced_body(
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

    def test_shared_layout_normalizes_koharu_emphasis_pairs(self) -> None:
        for marker in [
            "static func normalizedCharacters(in text: String) -> [String]",
            "normalizeVerticalEmphasisPunctuation(",
            "text.filter { !$0.isNewline }",
            "private static func emphasisMarkKind",
            "private static func emphasisPairSymbol",
            'case (.bang, .bang): "‼"',
            'case (.question, .question): "⁇"',
            'case (.bang, .question): "⁉"',
            'case (.question, .bang): "⁈"',
            'case "!", "！": .bang',
            'case "?", "？": .question',
        ]:
            self.assertIn(marker, self.layout)

    def test_shared_layout_maps_vertical_glyphs_and_classifies_fullwidth_punctuation(self) -> None:
        for marker in [
            "static func verticalGlyph(for character: String) -> String",
            'case "、": "︑"',
            'case "。": "︒"',
            'case "「": "﹁"',
            'case "」": "﹂"',
            'case "！": "﹗"',
            'case "？": "﹖"',
            "static func isFullwidthPunctuation(_ character: String) -> Bool",
            "0x3008...0x3011",
            "0x3014...0x301F",
            "0xFF01...0xFF0F",
            "0xFF5B...0xFF65",
        ]:
            self.assertIn(marker, self.layout)

    def test_preview_consumes_shared_normalized_vertical_cells(self) -> None:
        for marker in [
            "ImageTranslationVerticalTextLayout.normalizedCharacters(in: text)",
            "ImageTranslationVerticalTextLayout.verticalGlyph(for: character)",
            "let isFullwidthPunctuation = ImageTranslationVerticalTextLayout",
            "alignment: isFullwidthPunctuation ? .center : .top",
            "columns.indices.reversed()",
            "alignment: .topTrailing",
            ".clipped()",
        ]:
            self.assertIn(marker, self.preview)
        self.assertNotIn("text.map(String.init)", self.preview)

    def test_export_uses_same_cells_and_centers_fullwidth_punctuation(self) -> None:
        for marker in [
            "let usesVerticalWriting = mode == .replace && block.prefersVerticalWriting",
            "Self.drawImageTranslationText(",
            "vertical: usesVerticalWriting",
            "let characters = ImageTranslationVerticalTextLayout.normalizedCharacters(in: text)",
        ]:
            self.assertIn(marker, self.renderer if "usesVertical" in marker or "drawImage" in marker else self.draw)
        for marker in [
            "ImageTranslationVerticalTextLayout.verticalGlyph(for: character)",
            "Self.centeredVerticalGlyphRect(",
            "fullwidthPunctuation: ImageTranslationVerticalTextLayout.isFullwidthPunctuation(character)",
            "let cell = CGRect(",
            "cell.midY - glyphSize.height / 2",
            "fullwidthPunctuation ? centeredY : baselineAwareY",
        ]:
            self.assertIn(marker, self.store)
        self.assertIn("guard vertical else {", self.draw)
        self.assertIn("mode == .adjacent", self.renderer)

    def test_latin_and_non_replace_paths_keep_horizontal_rendering(self) -> None:
        self.assertIn(
            "let usesVerticalWriting = mode == .replace && block.prefersVerticalWriting",
            self.renderer,
        )
        self.assertIn(
            "NSAttributedString(string: text, attributes: attributes).draw(",
            self.draw,
        )
        self.assertIn(
            "guard sourceDirection == .vertical else { return false }",
            braced_body(self.models, "struct ImageTranslationBlock:"),
        )

    def test_executable_shared_layout_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v3242-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v3242-image-japanese-vertical-punctuation"
            environment = os.environ.copy()
            developer_directory = Path("/Applications/Xcode.app/Contents/Developer")
            if developer_directory.is_dir():
                environment["DEVELOPER_DIR"] = str(developer_directory)
            try:
                subprocess.run(
                    [
                        "xcrun", "--sdk", "macosx", "swiftc",
                        "-parse-as-library",
                        "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                        "AITRANS/Models/TranscriptModels.swift",
                        "scripts/test-v3242-image-japanese-vertical-punctuation-evaluator.swift",
                        "-o", str(executable),
                    ],
                    cwd=ROOT,
                    env=environment,
                    check=True,
                    capture_output=True,
                    text=True,
                )
            except subprocess.CalledProcessError as error:
                self.fail(
                    "vertical punctuation evaluator compilation failed:\n"
                    f"stdout={error.stdout}\nstderr={error.stderr}"
                )
            result = subprocess.run(
                [str(executable)], cwd=ROOT, check=True, capture_output=True, text=True
            )
            self.assertIn("v3.242 Japanese vertical punctuation evaluator passed", result.stdout)

    def test_version_and_ci_route_follow_v3241(self) -> None:
        previous = "python3 -B scripts/test-v3241-image-japanese-manga-ocr-vertical-quad-warp-contract.py"
        current = "python3 -B scripts/test-v3242-image-japanese-vertical-punctuation-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3242-image-japanese-vertical-punctuation-contract.py'",
            self.workflow,
        )
        self.assertIn(
            "scripts/test-v3242-image-japanese-vertical-punctuation-evaluator.swift",
            current + read("scripts/test-v3242-image-japanese-vertical-punctuation-contract.py"),
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 242) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.241;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
