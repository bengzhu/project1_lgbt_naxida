#!/usr/bin/env python3
"""Static and pure-policy contract for v3.346 risk-first Japanese line OCR."""

from pathlib import Path
import math
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


def valid_confidence(value: float) -> float | None:
    return value if math.isfinite(value) and 0.0 <= value <= 1.0 else None


def is_japanese_script(character: str) -> bool:
    return any(
        lower <= ord(character) <= upper
        for lower, upper in (
            (0x3000, 0x303F),
            (0x3040, 0x30FF),
            (0x3400, 0x4DBF),
            (0x4E00, 0x9FFF),
            (0xF900, 0xFAFF),
            (0xFF61, 0xFF9F),
        )
    )


def japanese_letters(text: str) -> int:
    return sum(
        any(
            lower <= ord(character) <= upper
            for lower, upper in (
                (0x3041, 0x3096),
                (0x30A1, 0x30FA),
                (0x30FD, 0x30FF),
                (0x3400, 0x4DBF),
                (0x4E00, 0x9FFF),
                (0xF900, 0xFAFF),
                (0xFF66, 0xFF9F),
            )
        )
        for character in text.strip()
    )


def script_density(text: str) -> float:
    cleaned = text.strip()
    return (
        sum(is_japanese_script(character) for character in cleaned) / len(cleaned)
        if cleaned
        else 0.0
    )


def at_risk(confidence: float, text: str) -> bool:
    cleaned = text.strip()
    return (
        valid_confidence(confidence) is None
        or confidence < 0.60
        or japanese_letters(cleaned) <= 2
        or script_density(cleaned) < 0.65
    )


def line_priority(candidate: tuple[int, float, str, float]) -> tuple:
    index, confidence, text, y = candidate
    risk = at_risk(confidence, text)
    finite_confidence = (
        valid_confidence(confidence)
        if valid_confidence(confidence) is not None
        else float("-inf")
    )
    if risk:
        return (
            0,
            finite_confidence,
            japanese_letters(text),
            script_density(text),
            len(text),
            y,
            index,
        )
    return (1, -len(text), finite_confidence, y, index)


class JapaneseLineCandidateRiskPriorityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read(
                "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
            )
            + read("update_log.md")
        )
        cls.candidates = function_body(
            cls.vision,
            "private static func japaneseMangaLineOCRCandidates(\n",
        )
        cls.risk_gate = function_body(
            cls.vision,
            "private static func isJapaneseMangaLineCandidateAtRisk(\n",
        )
        cls.sort_body = cls.candidates[
            cls.candidates.index("let textBacked =") : cls.candidates.index(
                "// Geometry-only candidates"
            )
        ]
        cls.recognizer = function_body(
            cls.vision,
            "private static func recognizeJapaneseMangaLineOCR(\n",
        )

    def test_risky_short_or_weak_lines_enter_the_prefix_before_strong_long_lines(
        self,
    ) -> None:
        candidates = [
            (0, 0.97, "持ち帰る！", 0.10),
            (1, 0.88, "ニコ", 0.20),
            (2, 0.56, "今度こそ", 0.30),
            (3, 0.94, "前は生意気に", 0.40),
        ]
        ordered = sorted(candidates, key=line_priority)
        self.assertEqual([candidate[0] for candidate in ordered[:2]], [2, 1])
        self.assertTrue(at_risk(0.88, "ニコ"))
        self.assertTrue(at_risk(0.56, "今度こそ"))
        self.assertFalse(at_risk(0.97, "持ち帰る！"))
        self.assertLessEqual(len(ordered[:6]), 6)

    def test_risk_gate_uses_existing_finite_and_meaningful_line_signals(self) -> None:
        for marker in (
            "postProcessJapaneseOCRText(candidate.text)",
            "validOCRConfidence(candidate.confidence) == nil",
            "candidate.confidence < 0.60",
            "letters <= 2",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) < 0.65",
            "japaneseScriptDensity(in: text) < 0.65",
        ):
            self.assertIn(marker, self.risk_gate)

    def test_text_backed_pool_gate_and_detector_boundary_remain_unchanged(self) -> None:
        for marker in (
            "candidate.observationRole != .detectorTextRegion",
            "isVerticalLineCandidate(region)",
            "validOCRConfidence(candidate.confidence) != nil",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
        ):
            self.assertIn(marker, self.candidates)
        self.assertNotIn("candidate.observationRole == .detectorTextRegion", self.candidates)

    def test_sort_places_risk_class_before_legacy_length_tie_break(self) -> None:
        for marker in (
            "let lhsAtRisk = isJapaneseMangaLineCandidateAtRisk(lhs)",
            "let rhsAtRisk = isJapaneseMangaLineCandidateAtRisk(rhs)",
            "return lhsAtRisk && !rhsAtRisk",
            "let lhsConfidence = validOCRConfidence(lhs.confidence) ?? -.infinity",
            "let rhsConfidence = validOCRConfidence(rhs.confidence) ?? -.infinity",
            "return lhsConfidence < rhsConfidence",
            "if lhsAtRisk {",
            "return lhsLetters < rhsLetters",
            "return lhsDensity < rhsDensity",
            "return lhsLength > rhsLength",
        ):
            self.assertIn(marker, self.sort_body)
        self.assertLess(
            self.sort_body.index("if lhsAtRisk != rhsAtRisk"),
            self.sort_body.index("let lhsLength"),
        )
        self.assertNotIn("return lhs.confidence < rhs.confidence", self.sort_body)
        self.assertNotIn("return lhs.confidence > rhs.confidence", self.sort_body)

    def test_non_risk_candidates_keep_length_before_confidence(self) -> None:
        length_index = self.sort_body.index("let lhsLength")
        confidence_tie_break = self.sort_body.index(
            "// Non-risk candidates keep the historical longest-line-first"
        )
        self.assertLess(length_index, confidence_tie_break)
        self.assertIn("return lhsLength > rhsLength", self.sort_body)

    def test_line_budget_geometry_reserve_and_final_cap_are_unchanged(self) -> None:
        for marker in (
            "maximumJapaneseMangaLineOCRRequests = 8",
            "min(2, maximumJapaneseMangaLineOCRRequests)",
            "maximumJapaneseMangaLineOCRRequests - geometryReserve",
            "let selectedGeometry = boundedJapaneseGeometryOnlyLineCandidates(",
            ".prefix(maximumJapaneseMangaLineOCRRequests)",
        ):
            self.assertIn(marker, self.candidates + self.vision)

    def test_geometry_candidates_still_follow_text_backed_budget_partition(self) -> None:
        self.assertLess(
            self.candidates.index("let textLimit ="),
            self.candidates.index("return Array(")
        )
        self.assertTrue(
            "textBacked.prefix(textLimit)" in self.candidates
            or "boundedJapaneseMangaLineTextCandidates(" in self.candidates
        )
        self.assertIn(
            "let selectedGeometry = boundedJapaneseGeometryOnlyLineCandidates(",
            self.candidates,
        )
        self.assertIn(".prefix(maximumJapaneseMangaLineOCRRequests)", self.candidates)

    def test_manga_line_result_gates_and_cancellation_remain_unchanged(self) -> None:
        for marker in (
            "try await MangaOCRService.shared.recognize(",
            "catch is CancellationError",
            "throw CancellationError()",
            "validOCRConfidence(result.confidence)",
            "confidence >= 0.55",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
        ):
            self.assertIn(marker, self.recognizer)
        self.assertIn("translateImageBlockWithQA(", self.store)

    def test_line_first_path_and_downstream_boundaries_are_not_reordered(self) -> None:
        vertical_crops = function_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        self.assertLess(
            vertical_crops.index("recognizeJapaneseVerticalLineCrops("),
            vertical_crops.index("for block in verticalBlocks"),
        )
        for source in (self.vision, self.candidates, self.recognizer):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.364", "3.364"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3337-japanese-line-candidate-risk-priority-contract.py",
            "v3.347",
            "japanese-benchmark-v3.347-",
        ):
            self.assertIn(marker, combined)
        contract = read(
            "scripts/test-v3337-japanese-line-candidate-risk-priority-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
