#!/usr/bin/env python3
"""Contracts for v3.0 image OCR result summary and explicit rerun."""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing function signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unterminated function body: {signature}")


class ImageOCRRerunContractTests(unittest.TestCase):
    def test_executable_summary_evaluator_uses_product_models(self) -> None:
        with tempfile.TemporaryDirectory(prefix="aitrans-v300-swift-") as temporary_directory:
            executable = Path(temporary_directory) / "v300-image-ocr-rerun"
            environment = os.environ.copy()
            if Path("/Applications/Xcode.app/Contents/Developer").is_dir():
                environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    "-module-cache-path", str(Path(temporary_directory) / "module-cache"),
                    "AITRANS/Models/ImageOCRResultSummary.swift",
                    "scripts/test-v300-image-ocr-rerun-evaluator.swift",
                    "-o", str(executable),
                ],
                cwd=ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run([str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertIn("v3.0 image OCR rerun evaluator passed", result.stdout)

    def test_summary_preserves_confidence_and_direction_evidence(self) -> None:
        summary = read("AITRANS/Models/ImageOCRResultSummary.swift")
        self.assertIn("static let lowConfidenceThreshold: Float = 0.55", summary)
        self.assertIn("blocks.count(where: { !$0.translation.isEmpty })", summary)
        self.assertIn("Self.hasLowConfidence($0, lowConfidenceThreshold: lowConfidenceThreshold)", summary)
        self.assertIn("return confidence < threshold", summary)
        self.assertIn("(0...1).contains(rawConfidence)", summary)
        self.assertTrue(
            "$0.effectiveSourceDirection == .vertical" in summary
            or "$0.sourceDirection == .vertical" in summary
        )
        self.assertTrue(
            "$0.effectiveSourceDirection == nil || $0.effectiveSourceDirection == .unknown" in summary
            or "$0.sourceDirection == nil || $0.sourceDirection == .unknown" in summary
        )

    def test_store_only_reruns_completed_content_with_a_live_source(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        capability = function_body(store, "var canRerunImageRecognition: Bool")
        rerun = function_body(store, "func rerunImageRecognition()")
        retry = function_body(store, "func retryImageTranslation()")
        self.assertIn("imageTranslationState == .translated", capability)
        self.assertIn("let url = imageTranslationSourceURL", capability)
        self.assertIn("FileManager.default.fileExists(atPath: url.path)", capability)
        self.assertLess(rerun.index("guard canRerunImageRecognition"), rerun.index("retryImageTranslation()"))
        self.assertIn("imageTranslationRetrySourceLanguage", retry)
        self.assertIn("imageTranslationContentSourceLanguage", retry)
        self.assertIn("imageTranslationRetryTargetLanguage", retry)
        self.assertIn("imageTranslationContentTargetLanguage", retry)
        self.assertIn("preservingSourceURL: url", retry)

    def test_view_exposes_summary_and_store_owned_rerun(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        view = read("AITRANS/Views/ImageTranslationViews.swift")
        summary = function_body(store, "var imageTranslationSummary: String")
        self.assertIn("ImageOCRResultSummary(blocks: imageTranslationBlocks)", summary)
        self.assertIn("averageConfidence.formatted(.percent", summary)
        self.assertIn('parts.append("低置信 \\(summary.lowConfidenceBlockCount)")', summary)
        self.assertIn('parts.append("竖排 \\(summary.verticalBlockCount)")', summary)
        self.assertIn('parts.append("方向待定 \\(summary.unknownDirectionBlockCount)")', summary)
        self.assertIn("if store.canRerunImageRecognition", view)
        self.assertIn('title: "重新识别"', view)
        self.assertIn('systemImage: "text.viewfinder"', view)
        self.assertIn("action: store.rerunImageRecognition", view)
        self.assertNotIn("FileManager.default", view)

    def test_ci_runs_v30_after_render_feedback(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        self.assertLess(
            workflow.index("scripts/test-v209-image-render-feedback-contract.py"),
            workflow.index("scripts/test-v300-image-ocr-rerun-contract.py"),
        )
        self.assertIn("300-image-ocr-rerun", workflow)
        self.assertIn("AITRANS/Models/ImageOCR(ResultSummary|ReviewFilter)", workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
