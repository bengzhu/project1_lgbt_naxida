#!/usr/bin/env python3
"""Contracts for v3.71 actionable Koharu readiness gate detail."""

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


class KoharuReadinessGateDetailContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.summary = braced_body(
            self.view,
            "private struct MangaKoharuArtifactReadinessSummary: View",
        )

    def test_status_detail_surfaces_downstream_gate_state(self) -> None:
        for marker in [
            "readinessGateDetail",
            "coordinateGateStatus",
            "maskPayloadGateStatus",
            "maskTopologyGateStatus",
            "artifactIdentityGateStatus",
            "门控摘要：坐标",
            "mask payload",
            "mask 拓扑",
            "工件身份",
        ]:
            self.assertIn(marker, self.summary)

    def test_gate_summary_uses_existing_readiness_report_only(self) -> None:
        for marker in [
            "readiness.coordinateValidation.bboxValidationPassed",
            "readiness.maskPayloadGateReady",
            "readiness.maskTopologyGateReady",
            "readiness.maskTopologyReport",
            "readiness.artifactIdentityReceipt",
            "topology?.blockers",
        ]:
            self.assertIn(marker, self.summary)
        self.assertNotIn("TranslationSessionStore", self.summary)
        self.assertNotIn("runMangaOverlayProbe", self.summary)
        self.assertNotIn("VisionOCRService", self.summary)

    def test_copyable_summary_includes_payload_topology_and_identity_evidence(self) -> None:
        for marker in [
            "coordinateSchemaVersion=",
            "coordinateSpace=",
            "coordinateBboxValidationPassed=",
            "bubbleMaskPayloadVerdict=",
            "segmentMaskPayloadVerdict=",
            "maskPayloadGateReady=",
            "maskTopologyGateReady=",
            "maskTopologyEvaluated=",
            "maskTopologyVerdict=",
            "maskTopologyBlockers=",
            "artifactIdentityVerdict=",
            "artifactIdentityAllRequiredFilesPresent=",
            "artifactIdentityAllRequiredFilesHaveSHA256=",
            "sourceImageSHA256Matches=",
            "shadowOnly=true",
            "mainFlowChanged=false",
        ]:
            self.assertIn(marker, self.summary)

    def test_accessibility_hint_explains_blocked_downstream_gates_without_promoting_proxy(self) -> None:
        for marker in [
            "readinessGateAccessibilityHint",
            "mask payload 尚未通过",
            "mask 拓扑仍需稳定一对一分配和像素分区复核",
            "需保留文件哈希并完成 CI 对账",
            "不要把 proxy 或 contract example 当作真实 Koharu 工件",
        ]:
            self.assertIn(marker, self.summary)

    def test_no_store_state_or_main_flow_change(self) -> None:
        self.assertNotIn("MangaKoharuArtifactReadinessSummary", self.store)
        self.assertNotIn("externalArtifactReadinessReport =", self.summary)
        self.assertIn("仅影响探针 shadow OCR，不改变普通图片 OCR、翻译或覆盖图", self.summary)

    def test_version_and_ci_route_follow_v370(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.70;", self.project)
        old = "python3 -B scripts/test-v370-image-preview-geometry-hint-contract.py"
        new = "python3 -B scripts/test-v371-koharu-readiness-gate-detail-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
