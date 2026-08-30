#!/usr/bin/env python3
"""Static contract for v3.306 mixed-script Japanese OCR candidate selection."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


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
                return source[brace + 1 : index]
    raise AssertionError(f"unterminated function body: {signature}")


class JapaneseMixedScriptCandidateSelectionContractTests(unittest.TestCase):
    RUNTIME_SCRIPTS = (
        "scripts/test-v3214-image-japanese-manga-ocr-runtime.sh",
        "scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh",
        "scripts/test-v3238-image-japanese-quad-bbox-fallback-runtime.sh",
        "scripts/test-v3239-image-japanese-manga-ocr-bbox-primary-runtime.sh",
        "scripts/test-v3245-image-japanese-directional-manga-ocr-crop-runtime.sh",
        "scripts/test-v3254-image-japanese-region-diagnostic-runtime.sh",
        "scripts/test-v3259-koharu-nearest-manga-preprocess-runtime.sh",
        "scripts/test-v3260-koharu-manga-ocr-rgb-luma-runtime.sh",
        "scripts/test-v3264-koharu-vertical-quad-warp-runtime.sh",
    )

    @classmethod
    def setUpClass(cls) -> None:
        cls.normalizer = read("AITRANS/Models/JapaneseOCRTextNormalizer.swift")
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.manga = read("AITRANS/Services/MangaOCRService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.test_log = read("md/test/test.md")
        cls.update_log = read("update_log.md")

    def test_mixed_signal_requires_japanese_and_ascii_word_characters(self) -> None:
        for marker in (
            "hasMixedJapaneseAndASCII",
            "containsASCIIWord(text)",
            "containsJapaneseScript",
            "0x3040...0x30FF",
            "0x4E00...0x9FFF",
            "0xFF66...0xFF9D",
        ):
            self.assertIn(marker, self.normalizer)

    def test_candidate_score_keeps_confidence_dominant_with_bounded_fidelity_hint(self) -> None:
        score = function_body(
            self.vision,
            "private static func japaneseCandidateScore(",
        )
        for marker in (
            "JapaneseOCRTextNormalizer.hasMixedJapaneseAndASCII(candidate.string)",
            "let mixedScriptFidelityBonus = hasMixedJapaneseAndASCII ? 0.12 : 0",
            "return confidence * 0.82",
            "+ scriptDensity * 0.14",
            "+ punctuationDensity * 0.04",
            "+ mixedScriptFidelityBonus",
        ):
            self.assertIn(marker, score)
        self.assertIn("bestConfidence - 0.14", self.vision)

    def test_shared_post_processing_and_candidate_selection_are_orthogonal(self) -> None:
        self.assertIn(
            "JapaneseOCRTextNormalizer.mixedScriptCandidate(text)",
            self.vision,
        )
        self.assertIn(
            "JapaneseOCRTextNormalizer.mixedScriptCandidate(text)",
            self.manga,
        )
        self.assertIn("selectOCRCandidate(", self.vision)
        self.assertIn("postProcessJapaneseOCRText", self.vision)
        self.assertIn("private static func postProcess(_ text: String)", self.manga)

    def test_compile_bearing_manga_harnesses_include_the_shared_model_source(self) -> None:
        for relative in self.RUNTIME_SCRIPTS:
            source = read(relative)
            self.assertIn("JapaneseOCRTextNormalizer.swift", source, relative)
            self.assertIn("MangaOCRService.swift", source, relative)
            self.assertLess(
                source.index("JapaneseOCRTextNormalizer.swift"),
                source.index("MangaOCRService.swift"),
                relative,
            )

    def test_product_and_runtime_boundaries_remain_unchanged(self) -> None:
        sources_phase = self.project[
            self.project.index("PBXSourcesBuildPhase section") :
        ]
        self.assertIn("JapaneseOCRTextNormalizer.swift in Sources", sources_phase)
        for forbidden in (
            "TranslationSessionStore",
            "VNRecognizeTextRequest",
            "groundTruth",
            "subprocess",
        ):
            self.assertNotIn(forbidden, self.normalizer)
        self.assertNotIn("TranslationSessionStore", self.vision)
        self.assertNotIn("TranslationSessionStore", self.manga)
        for marker in (
            "maximumBatchSize",
            "recognizeJapaneseVerticalCrops(",
            "recoverWeakJapaneseBlocks(",
            "recognizeObservations(",
        ):
            self.assertIn(marker, self.vision + self.manga)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.350", "3.350"],
        )
        for marker in (
            "scripts/test-v3306-japanese-mixed-script-candidate-selection-contract.py",
            "v3.306",
            "japanese-benchmark-v3.306-",
        ):
            self.assertIn(marker, self.workflow)
        for document in (
            self.flow,
            self.route,
            self.test_log,
            self.update_log,
        ):
            self.assertIn("v3.306", document)


if __name__ == "__main__":
    unittest.main(verbosity=2)
