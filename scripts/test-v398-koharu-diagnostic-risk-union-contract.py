#!/usr/bin/env python3
"""Contract for v3.98 shared OCR/translation report-only risk sets."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def braced_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unterminated body: {signature}")


class KoharuDiagnosticRiskUnionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_shared_sets_consume_existing_ocr_and_translation_evidence(self) -> None:
        ocr = braced_body(self.view, "private func mangaProbeOCRRiskBlockSet")
        self.assertIn("report.diagnostics.likelyOCRIssueBlocks", ocr)
        self.assertIn("translationUsableButOCRSuspectBlocks", ocr)
        self.assertIn("noisyOCRSuspectBlocks", ocr)
        self.assertIn('failureCategory == "ocrInputSuspect"', ocr)

        translation = braced_body(self.view, "private func mangaProbeTranslationRiskBlockSet")
        self.assertIn("translationLanguageQualityFailedBlocks", translation)
        self.assertIn("noisyModelFloorBlocks", translation)
        self.assertIn("noisyTranslationLanguageQualityBlocks", translation)
        self.assertIn('failureCategory == "modelOutputFailure"', translation)
        self.assertIn('failureCategory == "translationLanguageQualityFailure"', translation)

    def test_filter_and_triage_share_sets_without_product_state(self) -> None:
        filter_body = braced_body(self.view, "func matches(_ block: MangaOverlayProbeBlock")
        self.assertIn("mangaProbeOCRRiskBlockSet(report).contains(block.index)", filter_body)
        self.assertIn("mangaProbeTranslationRiskBlockSet(report).contains(block.index)", filter_body)
        self.assertIn("mangaProbeRenderRiskBlockSet(report).contains(block.index)", filter_body)
        self.assertIn("private var ocrBlocks: Set<Int>", self.view)
        self.assertIn("mangaProbeOCRRiskBlockSet(report)", self.view)
        self.assertIn("mangaProbeTranslationRiskBlockSet(report)", self.view)
        self.assertNotIn("mangaProbeOCRRiskBlockSet", self.store)
        self.assertNotIn("mangaProbeTranslationRiskBlockSet", self.store)
        self.assertIn("只筛选下方逐块诊断结果，不修改 probe_report", self.view)

    def test_version_and_ci_route_follow_v397(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 98) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.97;", self.project)
        script = "scripts/test-v398-koharu-diagnostic-risk-union-contract.py"
        self.assertIn(script, self.workflow)
        old = "python3 -B scripts/test-v397-koharu-layout-triage-contract.py"
        new = f"python3 -B {script}"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
