#!/usr/bin/env python3
"""Static contract for bounded Japanese scoped OCR candidate selection."""

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


class ImageJapaneseScopedCandidateContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.test_log = read("md/test/test.md")
        cls.update_log = read("update_log.md")

    def test_scoped_reread_collects_manga_and_vision_candidates(self) -> None:
        body = function_body(
            self.vision,
            "private static func recognizeTextBlockDetached(\n        image: CGImage,",
        )
        for marker in (
            "var mangaCandidate: ImageTranslationBlock?",
            "MangaOCRService.shared",
            "mangaCandidate = Self.recognizedBlock(",
            "var observations: [VisionOCRObservation] = []",
            "for angle in angles",
            "let visionCandidate = Self.recognizedBlock(",
            "Self.selectJapaneseScopedBlockCandidate(",
        ):
            self.assertIn(marker, body)
        self.assertLess(
            body.index("mangaCandidate = Self.recognizedBlock("),
            body.index("let visionCandidate = Self.recognizedBlock("),
        )
        self.assertLess(
            body.index("let visionCandidate = Self.recognizedBlock("),
            body.index("Self.selectJapaneseScopedBlockCandidate("),
        )

    def test_vision_orientation_budget_remains_explicit_and_bounded(self) -> None:
        body = function_body(
            self.vision,
            "private static func recognizeTextBlockDetached(\n        image: CGImage,",
        )
        for marker in (
            "angles = [270, 90]",
            "angles = [0]",
            "angles = [270, 90, 0]",
            "for angle in angles",
            "try Task.checkCancellation()",
            "recognitionLanguages: japanese",
            "observationRole: .crop",
        ):
            self.assertIn(marker, body)
        self.assertNotIn("while ", body)
        self.assertNotIn("repeat {", body)

    def test_accepted_candidate_gate_is_japanese_and_finite(self) -> None:
        gate = function_body(
            self.vision,
            "private static func isUsableJapaneseScopedText(\n",
        )
        for marker in (
            "postProcessJapaneseOCRText(sourceText)",
            "!text.isEmpty",
            "validOCRConfidence(confidence) != nil",
            "confidence >= 0.55",
            "japaneseScriptDensity(in: text) >= 0.5",
        ):
            self.assertIn(marker, gate)
        block_gate = function_body(
            self.vision,
            "private static func isUsableJapaneseScopedBlockCandidate(\n",
        )
        self.assertIn("isUsableJapaneseScopedText(", block_gate)

    def test_replacement_requires_measurable_bounded_evidence(self) -> None:
        selector = function_body(
            self.vision,
            "private static func selectJapaneseScopedBlockCandidate(\n",
        )
        comparator = function_body(
            self.vision,
            "private static func isBetterJapaneseScopedBlockCandidate(\n",
        )
        for marker in (
            "guard let mangaCandidate else",
            "guard let visionCandidate else",
            "isUsableJapaneseScopedBlockCandidate(visionCandidate)",
            "isUsableJapaneseScopedBlockCandidate(mangaCandidate)",
            "? visionCandidate : mangaCandidate",
        ):
            self.assertIn(marker, selector)
        self.assertNotIn("isMeaningfulJapaneseScopedBlockCandidate", selector)
        for marker in (
            "japaneseLetterCountForRecovery(candidateText)",
            "japaneseLetterCountForRecovery(incumbentText)",
            "candidateLetters > incumbentLetters",
            "candidate.confidence >= max(incumbent.confidence - 0.04, 0.55)",
            "candidateDensity > incumbentDensity + 0.05",
            "candidate.confidence >= incumbent.confidence + 0.04",
        ):
            self.assertIn(marker, comparator)

    def test_model_or_vision_failure_preserves_accepted_baseline_and_cancel(self) -> None:
        body = function_body(
            self.vision,
            "private static func recognizeTextBlockDetached(\n        image: CGImage,",
        )
        for marker in (
            "catch is CancellationError",
            "throw CancellationError()",
            "if japanese {",
            "return mangaCandidate",
            "if japanese {\n                    continue",
            "throw error",
        ):
            self.assertIn(marker, body)

    def test_scoped_candidate_selection_does_not_touch_session_boundaries(self) -> None:
        body = function_body(
            self.vision,
            "private static func selectJapaneseScopedBlockCandidate(\n",
        )
        for forbidden in (
            "TranslationSessionStore",
            "ImageOCRLayoutEngine.layout",
            "translate(",
            "persist(",
            "imageTranslationBlocks =",
            "cancelImageTranslation",
        ):
            self.assertNotIn(forbidden, body)
        self.assertIn("recognizeTextBlock(", self.store)
        self.assertIn("reviewed", self.store)

    def test_ordinary_ocr_remains_independent_of_optional_koharu_artifacts(self) -> None:
        for marker in (
            "koharu_parity_required:",
            "Optional Koharu MIT48 research parity; false keeps ordinary OCR validation independent",
            "inputs.koharu_parity_required == 'true'",
            "Koharu MIT48 parity is optional for ordinary OCR validation; no parity gate applied.",
            "if [ \"$KOHARU_MIT48_PARITY_REQUIRED\" = \"true\" ] &&",
        ):
            self.assertIn(marker, self.workflow)
        self.assertNotIn(
            'if [ "${{ steps.koharu_mit48_gate.outcome }}" != "success" ]; then',
            self.workflow,
        )

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.382", "3.382"],
        )
        for marker in (
            "scripts/test-v3308-image-japanese-scoped-candidate-contract.py",
            "v3.308",
            "japanese-benchmark-v3.308-",
        ):
            self.assertIn(marker, self.workflow)
        for document in (
            self.flow,
            self.route,
            self.test_log,
            self.update_log,
        ):
            self.assertIn("v3.308", document)

    def test_static_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3308-image-japanese-scoped-candidate-contract.py"
        )
        for source in (contract, self.vision):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
