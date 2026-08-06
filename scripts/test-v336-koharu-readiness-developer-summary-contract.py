#!/usr/bin/env python3
"""Static contracts for v3.36 Koharu readiness summary in the developer console."""

from pathlib import Path
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
                return source[brace:index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class KoharuReadinessDeveloperSummaryContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.section = braced_body(self.view, "private struct MangaProbeSection: View")
        self.summary = braced_body(
            self.view,
            "private struct MangaKoharuArtifactReadinessSummary: View",
        )

    def test_probe_result_surfaces_existing_readiness_without_creating_a_second_probe(self) -> None:
        self.assertIn(
            "if let readiness = report.externalArtifactReadinessReport",
            self.section,
        )
        self.assertIn("MangaKoharuArtifactReadinessSummary(", self.section)
        self.assertIn("readiness: readiness", self.section)
        self.assertNotIn("runMangaOverlayProbe", self.summary)
        self.assertNotIn("@EnvironmentObject", self.summary)

    def test_summary_reads_the_existing_external_artifact_readiness_model(self) -> None:
        self.assertIn(
            "let readiness: MangaOverlayExternalArtifactReadinessReport",
            self.summary,
        )
        for field in [
            "sourceImage",
            "readinessVerdict",
            "nextAction",
            "activeArtifactsDirectory",
            "contractExampleOnly",
            "externalTextBoxesShadowOCRAllowed",
            "manifestFound",
            "textBoxesFound",
            "bubbleMaskFound",
            "segmentMaskFound",
            "missingArtifacts",
            "parseErrors",
            "generatedBy",
            "textBoxCount",
            "bubbleInstanceCount",
            "segmentGlyphPixelCount",
        ]:
            self.assertIn(f"readiness.{field}", self.summary)

    def test_missing_ready_and_invalid_states_have_distinct_accessibility_visible_status(self) -> None:
        for marker in [
            'case "readyForShadowOCR" where readiness.externalTextBoxesShadowOCRAllowed:',
            '"真实 Koharu 工件已就绪（仅 shadow OCR）"',
            'case "manifestMissing", "artifactFilesMissing":',
            '"等待真实 Koharu 四件套"',
            '"Koharu 工件需要修正"',
            "AppStatusRow(title: statusTitle, detail: statusDetail, tone: statusTone)",
        ]:
            self.assertIn(marker, self.summary)

    def test_missing_artifacts_and_next_action_are_copyable_and_do_not_claim_production_quality(self) -> None:
        for marker in [
            "readiness.missingArtifacts.isEmpty",
            "nextActionDetail",
            'DeveloperCodeBlock(title: "Koharu artifact readiness", text: summary)',
            "shadowOnly=true",
            "mainFlowChanged=false",
            "不改变普通图片 OCR、翻译或覆盖图",
        ]:
            self.assertIn(marker, self.summary)
        self.assertNotIn("correctImageTranslationBlock(", self.summary)
        self.assertNotIn("VisionOCRService", self.summary)

    def test_summary_stays_view_only_and_does_not_add_store_state(self) -> None:
        self.assertNotIn("MangaKoharuArtifactReadinessSummary", self.store)
        self.assertNotIn("koharuReadinessSummary", self.store)
        self.assertNotIn("mangaOverlayProbeReport =", self.summary)

    def test_ci_routes_v336_after_v335(self) -> None:
        old = "python3 -B scripts/test-v335-image-focus-preview-return-focus-contract.py"
        new = "python3 -B scripts/test-v336-koharu-readiness-developer-summary-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v336-koharu-readiness-developer-summary-contract.py' "
            '"$RESULT_ROOT/changed-files.txt" >/dev/null; then'
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
