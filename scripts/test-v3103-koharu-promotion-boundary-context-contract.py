#!/usr/bin/env python3
"""Contract for v3.103 report-only Koharu promotion boundary context."""

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


class KoharuPromotionBoundaryContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.helper = braced_body(self.view, "private func mangaProbePromotionBoundary(")
        self.triage = braced_body(self.view, "private struct MangaProbeDiagnosticTriageSummary: View")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_context_consumes_existing_promotion_contract_identity_and_convergence_reports(self) -> None:
        for marker in [
            "report.koharuNativePromotionGateLiteReport",
            "promotion.promotionVerdict",
            "promotion.needsRealTextBoxesBlocks",
            "promotion.needsRealBubbleMaskBlocks",
            "promotion.needsRealSegmentMaskBlocks",
            "promotion.stopLocalTuningBlocks",
            "promotion.gateLedger",
            "report.koharuNativeArtifactContractDryRunReport",
            "contract.contractDryRunVerdict",
            "contract.blockedPreviewIDs",
            "contract.readinessVerdict",
            "report.koharuArtifactIdentityReconciliationReport",
            "identity.identityReconciliationVerdict",
            "identity.readyForCIManifestComparison",
            "identity.manualCIComparisonRequired",
            "identity.hashMissingFileKinds",
            "report.koharuArtifactConvergenceReport",
            "convergence.openWorkItems",
            "convergence.stopWorkItems",
            "convergence.needsRealArtifactBlocks",
        ]:
            self.assertIn(marker, self.helper)

    def test_boundary_is_shared_by_status_summary_and_voiceover(self) -> None:
        for marker in [
            "promotionBoundary?.isBlocked",
            "promotionBoundary?.isReportOnly",
            "晋级边界：\\($0.summary)",
            "promotionBoundary=\\(promotionBoundary?.summary ?? \"notAvailable\")",
            "promotionNextAction=\\(promotionBoundary?.nextAction ?? \"notAvailable\")",
            "晋级边界和真实 Koharu 工件的下一步",
        ]:
            self.assertIn(marker, self.triage if "promotionBoundary" in marker or "晋级边界" in marker else self.view)
        self.assertIn("promotionBoundary?.summary", self.view)
        self.assertIn("promotionBoundary?.nextAction", self.view)

    def test_context_remains_report_only_without_store_probe_or_ground_truth_ownership(self) -> None:
        for forbidden in ["TranslationSessionStore", "runMangaOverlayProbe", "groundTruth"]:
            self.assertNotIn(forbidden, self.helper)
        self.assertIn("diagnosticOnly", self.helper)
        self.assertIn("wouldChangeMainFlow", self.helper)

    def test_version_and_ci_route_follow_v3102(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 103) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.102;", self.project)
        script = "scripts/test-v3103-koharu-promotion-boundary-context-contract.py"
        old = "python3 -B scripts/test-v3102-koharu-block-execution-boundary-contract.py"
        new = f"python3 -B {script}"
        self.assertIn(script, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
