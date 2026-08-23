#!/usr/bin/env python3
"""Static contract for bounded weak Japanese image-block OCR recovery."""

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


class ImageJapaneseWeakBlockRecoveryContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.update_log = read("update_log.md")
        cls.test_log = read("md/test/test.md")

    def test_page_layout_runs_bounded_recovery_only_for_japanese(self) -> None:
        layout_marker = "let laidOutBlocks = { () -> [ImageTranslationBlock] in"
        recovery_marker = "try await Self.recoverWeakJapaneseBlocks("
        self.assertIn(layout_marker, self.vision)
        self.assertIn(recovery_marker, self.vision)
        self.assertLess(self.vision.index(layout_marker), self.vision.index(recovery_marker))
        call = self.vision[self.vision.index(recovery_marker) :]
        self.assertIn("sourceLanguage == .japanese", call)
        self.assertIn(": laidOutBlocks", call)
        self.assertIn("blocks: laidOutBlocks", call)

    def test_recovery_budget_and_priority_are_explicit(self) -> None:
        self.assertIn(
            "private static let maximumJapaneseWeakBlockRecoveryRequests = 4",
            self.vision,
        )
        body = function_body(
            self.vision,
            "private static func recoverWeakJapaneseBlocks(\n",
        )
        for marker in (
            ".filter { needsJapaneseWeakBlockRecovery($0.element) }",
            ".sorted { lhs, rhs in",
            "let lhsConfidence = validOCRConfidence(lhs.element.confidence)",
            "let rhsConfidence = validOCRConfidence(rhs.element.confidence)",
            "return lhsConfidence < rhsConfidence",
            "return lhs.offset < rhs.offset",
            ".prefix(Self.maximumJapaneseWeakBlockRecoveryRequests)",
            "Task.checkCancellation()",
        ):
            self.assertIn(marker, body)

    def test_recovery_reuses_scoped_crop_reader_without_reencoding(self) -> None:
        image_data = function_body(
            self.vision,
            "private static func recognizeTextBlockDetached(\n        imageData: Data,",
        )
        self.assertIn("let image = try Self.makeOCRImage(from: imageData)", image_data)
        self.assertIn("image: image", image_data)
        body = function_body(
            self.vision,
            "private static func recoverWeakJapaneseBlocks(\n",
        )
        self.assertIn("Self.recognizeTextBlockDetached(\n                    image: image,", body)
        self.assertIn("sourceLanguage: .japanese", body)
        self.assertIn("selectionReason: .existingLayoutFusion", body)
        self.assertNotIn("makeOCRImage(from:", body)

    def test_weak_gate_and_candidate_gate_are_fail_closed(self) -> None:
        weak_gate = function_body(
            self.vision,
            "private static func needsJapaneseWeakBlockRecovery(\n",
        )
        for marker in (
            "validOCRConfidence(block.confidence) == nil",
            "block.confidence < 0.60",
            "japaneseScriptDensity(in: text) < 0.5",
            "japaneseLetterCountForRecovery(text)",
        ):
            self.assertIn(marker, weak_gate)

        candidate_gate = function_body(
            self.vision,
            "private static func isBetterJapaneseWeakBlockRecovery(\n",
        )
        for marker in (
            "candidate.confidence >= 0.55",
            "japaneseScriptDensity(in: candidateText) >= 0.5",
            "candidateLetters > originalLetters",
            "candidate.confidence >= max(originalConfidence + 0.04, 0.55)",
        ):
            self.assertIn(marker, candidate_gate)

    def test_failed_recovery_preserves_original_and_propagates_cancel(self) -> None:
        body = function_body(
            self.vision,
            "private static func recoverWeakJapaneseBlocks(\n",
        )
        for marker in (
            "recovered[candidate.offset] = reread",
            "catch is CancellationError",
            "throw CancellationError()",
            "catch {",
            "continue",
            "return recovered",
        ):
            self.assertIn(marker, body)
        self.assertIn("guard !candidates.isEmpty else { return blocks }", body)

    def test_recovery_does_not_touch_layout_translation_or_persistence(self) -> None:
        body = function_body(
            self.vision,
            "private static func recoverWeakJapaneseBlocks(\n",
        )
        for forbidden in (
            "ImageOCRLayoutEngine.layout",
            "TranslationSessionStore",
            "translate(",
            "persist(",
            "imageTranslationBlocks =",
        ):
            self.assertNotIn(forbidden, body)

    def test_koharu_parity_is_opt_in_and_cannot_block_ordinary_full_validation(self) -> None:
        for marker in (
            "koharu_parity_required:",
            "Optional Koharu MIT48 research parity; false keeps ordinary OCR validation independent",
            "inputs.koharu_parity_required == 'true'",
            "Koharu MIT48 parity is optional for ordinary OCR validation; no parity gate applied.",
            "if [ \"$KOHARU_MIT48_PARITY_REQUIRED\" = \"true\" ] &&",
            "MANIFEST_KOHARU_PARITY_REQUIRED",
            "koharuParityRequired",
        ):
            self.assertIn(marker, self.workflow)
        self.assertNotIn(
            'if [ "${{ steps.koharu_mit48_gate.outcome }}" != "success" ]; then',
            self.workflow,
        )

    def test_project_workflow_docs_and_version_are_explicit(self) -> None:
        for marker in (
            "scripts/test-v3295-image-japanese-weak-block-recovery-contract.py",
            "v3.295",
            "弱日语文字块",
            "弱日语 block",
            "Koharu 只作为可选研究/质量证明",
        ):
            self.assertIn(
                marker,
                self.project + self.workflow + self.route + self.update_log + self.test_log,
            )
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.332", "3.332"],
        )

    def test_static_contract_has_no_process_entry(self) -> None:
        contract = read(
            "scripts/test-v3295-image-japanese-weak-block-recovery-contract.py"
        )
        for source in (contract, self.vision):
            self.assertNotIn("sub" + "process", source)
            self.assertNotIn("Po" + "pen", source)
            self.assertNotIn("os." + "system", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
