#!/usr/bin/env python3
"""Contracts for v3.10 bounded, orientation-aware image previews."""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class ImagePreviewDownsampleContractTests(unittest.TestCase):
    def test_executable_imageio_evaluator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v310-preview-") as temporary_directory:
            executable = Path(temporary_directory) / "v310-image-preview-downsample"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                    "AITRANS/Services/ImagePreviewService.swift",
                    "scripts/test-v310-image-preview-downsample-evaluator.swift",
                    "-o", str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(executable)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("v3.10 image preview downsample evaluator passed", result.stdout)

    def test_service_bounds_pixels_applies_orientation_and_avoids_full_cache(self) -> None:
        service = read("AITRANS/Services/ImagePreviewService.swift")

        self.assertIn("static let maximumPixelSize = 2_048", service)
        self.assertIn("kCGImageSourceShouldCache: false", service)
        self.assertIn("kCGImageSourceCreateThumbnailFromImageAlways: true", service)
        self.assertIn("kCGImageSourceCreateThumbnailWithTransform: true", service)
        self.assertIn("kCGImageSourceShouldCacheImmediately: true", service)
        self.assertIn("kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize", service)

    def test_service_runs_off_main_and_propagates_cancellation(self) -> None:
        service = read("AITRANS/Services/ImagePreviewService.swift")

        self.assertIn("Task.detached(priority: .userInitiated)", service)
        self.assertIn("withTaskCancellationHandler", service)
        self.assertIn("previewTask.cancel()", service)
        self.assertGreaterEqual(service.count("Task.isCancelled"), 3)

    def test_view_rejects_stale_preview_and_never_decodes_original_uiimage(self) -> None:
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        preview = view[
            view.index("private struct ImageTranslationPreview"):
            view.index("private struct ImageTranslationOverlayBlock")
        ]

        self.assertIn("let revision = store.imageTranslationRevision", preview)
        self.assertIn("await ImagePreviewService.makePreview(from: data)", preview)
        self.assertIn("!Task.isCancelled", preview)
        self.assertIn("revision == store.imageTranslationRevision", preview)
        self.assertIn("previewImage = UIImage(cgImage: preview.cgImage)", preview)
        self.assertNotIn("UIImage.init(data:)", preview)
        self.assertNotIn("UIImage(data:", preview)

    def test_project_and_ci_run_v310_after_v39(self) -> None:
        project = read("AITRANS.xcodeproj/project.pbxproj")
        workflow = read(".github/workflows/ci-results.yml")

        self.assertIn("ImagePreviewService.swift in Sources", project)
        self.assertIn("ImagePreviewService", workflow)
        self.assertIn("310-image-preview-downsample", workflow)
        self.assertLess(
            workflow.index("scripts/test-v39-image-clear-confirmation-contract.py"),
            workflow.index("scripts/test-v310-image-preview-downsample-contract.py"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
