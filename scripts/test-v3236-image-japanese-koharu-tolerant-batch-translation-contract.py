#!/usr/bin/env python3
"""Contract for Koharu-style tolerant numbered manga translation batches."""

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


class JapaneseKoharuTolerantBatchTranslationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        self.mock = read("AITRANS/Services/MockGemmaService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.batch = braced_body(
            self.store,
            "private func translateJapaneseImageBatch(",
        )
        self.parser = braced_body(
            self.store,
            "private static func parseMangaTaggedTranslations(",
        )
        self.cleaner = braced_body(
            self.gemma,
            "private func cleanMangaBlockOutput(",
        )

    def test_global_ids_are_resolved_without_requiring_model_order(self) -> None:
        for marker in [
            "let expectedIDs = blocks.indices.map { startIndex + $0 + 1 }",
            "let parsedTranslations = try Self.parseMangaTaggedTranslations(",
            "var translations = Array(repeating: \"\", count: blocks.count)",
            "var missingOffsets: [Int] = []",
            "if let translation = parsedTranslations[offset]",
            "let candidate = try await translateJapaneseImageBlockWithQA(",
            "translations[offset] = candidate",
            "missing=\\(missingOffsets.count)",
        ]:
            self.assertIn(marker, self.batch)

    def test_parser_matches_koharu_partial_and_out_of_order_semantics(self) -> None:
        for marker in [
            "let expectedIndexByID = Dictionary(",
            "var values = Array<String?>(repeating: nil, count: expectedIDs.count)",
            "var recognizedCount = 0",
            "var sawExpectedTag = false",
            "guard let expectedIndex = expectedIndexByID[id] else",
            "keep all recognized blocks addressable",
            "return values",
        ]:
            self.assertIn(marker, self.parser)
        self.assertNotIn("guard ids == expectedIDs else", self.parser)
        self.assertNotIn("ids == expectedIDs", self.parser)

    def test_local_adapter_keeps_valid_subset_for_store_recovery(self) -> None:
        for marker in [
            "let expectedPartsByID = Dictionary(",
            "let recognizedOutputParts = outputParts.filter",
            "expectedPartsByID[$0.id] != nil",
            "recognizedOutputParts.allSatisfy",
            "ordering and completeness are",
            "recovered by the caller",
        ]:
            self.assertIn(marker, self.cleaner)
        self.assertNotIn("outputIDs == expectedIDs", self.cleaner)

    def test_invalid_or_empty_batch_still_has_safe_single_block_fallback(self) -> None:
        for marker in [
            "if error is CancellationError",
            "manga-batch-result state=fallback",
            "for (offset, block) in blocks.enumerated()",
            "let candidate = try await translateJapaneseImageBlockWithQA(",
            "fallbackTranslations.append(candidate)",
            "try Task.checkCancellation()",
        ]:
            self.assertIn(marker, self.batch)
        self.assertIn("throw ImageMangaBatchTranslationError.missingTags", self.parser)
        self.assertIn("throw ImageMangaBatchTranslationError.emptyTranslation", self.parser)

    def test_cancellation_and_scope_boundaries_remain_intact(self) -> None:
        self.assertIn("if error is CancellationError", self.batch)
        self.assertIn("try Task.checkCancellation()", self.batch)
        changed = self.batch + self.cleaner
        for forbidden in [
            "reference/koharu-main",
            "test/koharu_artifacts",
            "test/speech_corpus",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, changed)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)

    def test_version_and_ci_route(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 236) for version in versions)
        )
        previous = "python3 -B scripts/test-v3235-image-japanese-manga-ocr-token-budget-contract.py"
        current = "python3 -B scripts/test-v3236-image-japanese-koharu-tolerant-batch-translation-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))


if __name__ == "__main__":
    unittest.main(verbosity=2)
