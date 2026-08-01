#!/usr/bin/env python3
"""Contracts for v3.72 Koharu v1 summary-only readiness wording."""

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


class KoharuV1ReadinessClarityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.summary = braced_body(
            self.view,
            "private struct MangaKoharuArtifactReadinessSummary: View",
        )

    def test_v1_summary_only_is_not_reported_as_v2_payload_failure(self) -> None:
        for marker in [
            "isLegacySummaryOnlyArtifact",
            'readiness.coordinateValidation.schemaVersion == "aitrans.koharu_artifact_contract.v1"',
            'readiness.bubbleMaskPayloadVerdict == "legacySummaryOnly"',
            'readiness.segmentMaskPayloadVerdict == "legacySummaryOnly"',
            'return "未要求（v1 summary-only）"',
            'return "未要求（v2 拓扑）"',
        ]:
            self.assertIn(marker, self.summary)

    def test_v1_accessibility_guidance_preserves_shadow_only_boundary(self) -> None:
        for marker in [
            "当前为 v1 summary-only；v2 mask payload 和 topology 尚未要求",
            "mask payload 尚未通过",
            "mask 拓扑仍需稳定一对一分配和像素分区复核",
            "不要把 proxy 或 contract example 当作真实 Koharu 工件",
            "shadow OCR",
            "不会修改普通图片 OCR、翻译或覆盖图",
        ]:
            self.assertIn(marker, self.summary)

    def test_copyable_summary_exposes_interpreted_gate_status(self) -> None:
        for marker in [
            "maskPayloadGateStatus=",
            "maskTopologyGateStatus=",
            "coordinateSchemaVersion=",
            "bubbleMaskPayloadVerdict=",
            "segmentMaskPayloadVerdict=",
            "maskPayloadGateReady=",
            "maskTopologyGateReady=",
            "shadowOnly=true",
            "mainFlowChanged=false",
        ]:
            self.assertIn(marker, self.summary)

    def test_clarity_change_stays_view_only(self) -> None:
        self.assertNotIn("MangaKoharuArtifactReadinessSummary", self.store)
        self.assertNotIn("runMangaOverlayProbe", self.summary)
        self.assertNotIn("VisionOCRService", self.summary)
        self.assertNotIn("FileManager", self.summary)

    def test_version_and_ci_route_follow_v371(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.72;", self.project)
        old = "python3 -B scripts/test-v371-koharu-readiness-gate-detail-contract.py"
        new = "python3 -B scripts/test-v372-koharu-v1-readiness-clarity-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
