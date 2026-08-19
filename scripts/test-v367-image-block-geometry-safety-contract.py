#!/usr/bin/env python3
"""Contracts for v3.67 restored image block geometry safety."""

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
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageBlockGeometrySafetyContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.models = read("AITRANS/Models/TranscriptModels.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_model_owns_a_finite_unit_space_boundary(self) -> None:
        body = braced_body(self.models, "func normalizedToUnit()")
        for required in [
            "x.isFinite",
            "y.isFinite",
            "width.isFinite",
            "height.isFinite",
            "width > 0",
            "height > 0",
            "right.isFinite",
            "bottom.isFinite",
            "clippedRight > left",
            "clippedBottom > top",
        ]:
            self.assertIn(required, body)

    def test_focus_preview_and_overlay_skip_invalid_restored_boxes(self) -> None:
        focus = braced_body(self.view, "static func normalizedFocusRect(for block")
        relative = braced_body(self.view, "static func relativeBlockRect(")
        overlay = braced_body(self.view, "private struct ImageTranslationOverlayBlock: View")
        self.assertIn("guard let box = block.boundingBox.normalizedToUnit() else", focus)
        self.assertIn("guard let box = block.boundingBox.normalizedToUnit()", relative)
        self.assertIn("if let rect = displayRect", overlay)
        self.assertIn("private func overlayContent(for rect: CGRect)", overlay)
        self.assertIn("private var displayRect: CGRect?", overlay)
        self.assertIn("block.boundingBox.normalizedToUnit()", overlay)

    def test_export_renderer_never_draws_invalid_restored_boxes(self) -> None:
        body = braced_body(self.store, "nonisolated private static func imageTranslationPixelRect(")
        self.assertIn("guard let box = box.normalizedToUnit() else { return .zero }", body)
        self.assertIn("imageTranslationPixelRect(", self.store)

    def test_executable_model_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v367-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v367-image-block-geometry-safety"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            try:
                subprocess.run(
                    [
                        "xcrun",
                        "--sdk",
                        "macosx",
                        "swiftc",
                        "-parse-as-library",
                        "-module-cache-path",
                        str(Path(temporary_directory) / "module-cache"),
                        "AITRANS/Models/ImageOCRProvenance.swift",
                        "AITRANS/Services/ImageOCRLayoutEngine.swift",
                        "AITRANS/Models/TranslationContextQuality.swift",
                        "AITRANS/Models/TranscriptModels.swift",
                        "scripts/test-v367-image-block-geometry-safety-evaluator.swift",
                        "-o",
                        str(executable),
                    ],
                    cwd=ROOT,
                    env=environment,
                    check=True,
                    capture_output=True,
                    text=True,
                )
            except subprocess.CalledProcessError as error:
                self.fail(
                    "image block geometry evaluator compilation failed:\n"
                    f"stdout={error.stdout}\nstderr={error.stderr}"
                )
            result = subprocess.run([str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertIn("v3.67 image block geometry safety evaluator passed", result.stdout)

    def test_version_and_ci_route_follow_v366(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.67;", self.project)
        old = "python3 -B scripts/test-v366-image-ocr-geometry-safety-contract.py"
        new = "python3 -B scripts/test-v367-image-block-geometry-safety-contract.py"
        route = "grep -E '^scripts/test-v3(4[7-9]|[5-7][0-9]|8[01])-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
