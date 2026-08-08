#!/usr/bin/env python3
"""Contract for Koharu-style numbered manga block translation."""

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


class JapaneseKoharuBatchTranslationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.gemma = read("AITRANS/Services/GemmaLocalService.swift")
        self.mock = read("AITRANS/Services/MockGemmaService.swift")
        self.models = read("AITRANS/Models/TranscriptModels.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.pipeline = braced_body(
            self.store,
            "private func runImageTranslationPipeline(",
        )
        self.batch = braced_body(
            self.store,
            "private func translateJapaneseImageBatch(",
        )
        self.parser = braced_body(
            self.store,
            "private static func parseMangaTaggedTranslations(",
        )
        self.gemma_batch = braced_body(
            self.gemma,
            "private func generateMangaBlockTranslation(",
        )

    def test_japanese_image_pipeline_uses_ordered_batches_only_for_japanese(self) -> None:
        for marker in [
            "if sourceLanguage == .japanese",
            "Self.imageTranslationBatches(recognizedBlocks)",
            "translateJapaneseImageBatch(",
            "正在按漫画文本组翻译",
            "for (index, block) in recognizedBlocks.enumerated()",
            "sourceLanguage: sourceLanguage",
        ]:
            self.assertIn(marker, self.pipeline)
        self.assertIn("translationProfile: .mangaBlocks", self.batch)
        self.assertIn("translationProfile: .standard", self.store)

    def test_batch_input_preserves_global_ids_and_is_bounded(self) -> None:
        for marker in [
            "let expectedIDs = blocks.indices.map { startIndex + $0 + 1 }",
            'return "[\\(expectedIDs[offset])] \\(text)"',
            "joined(separator: \"\\n\")",
            "let maximumBlocks = 8",
            "let maximumCharacters = 1_800",
            "startIndex += current.count",
            "mangaBatchSampling(",
        ]:
            self.assertIn(marker, self.store)

    def test_parser_requires_complete_stable_tags_and_nonempty_values(self) -> None:
        for marker in [
            'let pattern = #"(?m)^\\s*\\[(\\d+)\\]\\s*"#',
            "guard !matches.isEmpty else",
            "throw ImageMangaBatchTranslationError.missingTags",
            "throw ImageMangaBatchTranslationError.emptyTranslation",
            "guard ids == expectedIDs else",
            "throw ImageMangaBatchTranslationError.unexpectedTags",
        ]:
            self.assertIn(marker, self.parser)

    def test_parse_failure_falls_back_to_existing_single_block_translation(self) -> None:
        for marker in [
            "if error is CancellationError",
            "manga-batch-result state=fallback",
            "for block in blocks",
            "fallbackTranslations.append(try await translate(",
            "try Task.checkCancellation()",
        ]:
            self.assertIn(marker, self.batch)
        self.assertNotIn("MangaOverlayProbeService", self.batch)
        self.assertNotIn("groundTruth", self.batch)

    def test_koharu_prompt_preserves_manga_voice_and_block_boundaries(self) -> None:
        for marker in [
            "你是专业的漫画翻译器",
            "只翻译每个编号后面的文字",
            "原样保留每个 [N] 标签",
            "不要合并、拆分、遗漏或重排",
            "角色语气、情绪、关系、强调和拟声词",
            "不要输出解释、注释、罗马音",
            "每个标签单独一行",
            "request.translationProfile == .mangaBlocks",
            "cleanMangaBlockOutput",
        ]:
            self.assertIn(marker, self.gemma)

    def test_local_and_mock_adapters_return_tagged_blocks(self) -> None:
        for marker in [
            "outputIDs == expectedIDs",
            "mangaBlockParts(in: input)",
            "translationProfile == .mangaBlocks",
            "mangaBlockTranslation(for: request)",
            "return \"[\\(id)] \\(translation)\"",
        ]:
            self.assertTrue(marker in self.gemma or marker in self.mock, marker)

    def test_scope_does_not_pull_probe_ground_truth_metrics_or_output(self) -> None:
        changed_sources = self.batch + self.gemma_batch + self.mock
        for forbidden in [
            "test/koharu_artifacts",
            "test/speech_corpus",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, changed_sources)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)

    def test_version_and_ci_route_follow_v3195(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.196", "3.196"])
        old = "python3 -B scripts/test-v3195-image-japanese-mixed-layout-reading-order-contract.py"
        new = "python3 -B scripts/test-v3196-image-japanese-koharu-batch-translation-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
