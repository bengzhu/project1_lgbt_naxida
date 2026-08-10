#!/usr/bin/env python3
"""Contract for applying a reviewer direction override to scoped OCR retry."""

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


class JapaneseDirectionOverrideRerecognitionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.models = read("AITRANS/Models/TranscriptModels.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.runtime_harnesses = [
            read("scripts/fixtures/v3214-manga-ocr-runtime-harness.swift"),
            read("scripts/fixtures/v3218-long-page-manga-ocr-runtime-harness.swift"),
            read("scripts/fixtures/v3238-manga-ocr-quad-bbox-fallback-runtime-harness.swift"),
            read("scripts/fixtures/v3239-manga-ocr-bbox-primary-runtime-harness.swift"),
        ]
        self.rerecognition = braced_body(
            self.vision,
            "private static func recognizeTextBlockDetached(",
        )
        self.store_rerecognition = braced_body(
            self.store,
            "func rerecognizeImageTranslationBlock(",
        )

    def test_scoped_japanese_retry_uses_effective_direction(self) -> None:
        self.assertIn("if block.effectiveSourceDirection == .vertical", self.rerecognition)
        self.assertIn("} else if block.effectiveSourceDirection == .horizontal", self.rerecognition)
        self.assertIn("angles = [270, 90]", self.rerecognition)
        self.assertIn("angles = [0]", self.rerecognition)
        self.assertIn("angles = [270, 90, 0]", self.rerecognition)
        self.assertNotIn("if block.sourceDirection == .vertical", self.rerecognition)
        self.assertNotIn("else if block.sourceDirection == .horizontal", self.rerecognition)

    def test_override_remains_provenance_only_until_user_starts_retry(self) -> None:
        self.assertIn("var replacement = block", self.store_rerecognition)
        self.assertIn("self.imageTranslationBlocks[currentIndex] = replacement", self.store_rerecognition)
        self.assertIn("var sourceDirectionOverride: ImageTextDirection?", self.models)
        self.assertIn("var effectiveSourceDirection: ImageTextDirection?", self.models)

    def test_non_japanese_and_page_paths_remain_unchanged(self) -> None:
        self.assertIn("let angles: [Int]", self.rerecognition)
        self.assertIn("angles = [0]", self.rerecognition)
        self.assertIn("recognizeTextBlocks(in imageData", self.vision)
        self.assertIn("effectiveSourceDirection", self.vision)

    def test_runtime_harnesses_match_direction_model(self) -> None:
        for harness in self.runtime_harnesses:
            self.assertIn("var sourceDirectionOverride: ImageTextDirection? = nil", harness)
            self.assertIn("var effectiveSourceDirection: ImageTextDirection", harness)
            self.assertIn("sourceDirectionOverride ?? sourceDirection", harness)

    def test_version_and_ci_route_follow_v3243(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 244) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.243;", self.project)
        previous = "python3 -B scripts/test-v3243-image-japanese-direction-override-contract.py"
        current = "python3 -B scripts/test-v3244-image-japanese-direction-override-rerecognition-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3244-image-japanese-direction-override-rerecognition-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
