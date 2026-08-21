#!/usr/bin/env python3
"""Static contract for the v3.289 read-only OCR provenance disclosure."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class ImageOCRProvenanceDisclosureContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.view = read("AITRANS/Views/ImageOCRProvenanceDisclosureView.swift")
        cls.rows = read("AITRANS/Views/ImageTranslationViews.swift")
        cls.provenance = read("AITRANS/Models/ImageOCRProvenance.swift")
        cls.models = read("AITRANS/Models/TranscriptModels.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.route = read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")

    def test_disclosure_is_review_scoped_read_only_and_provenance_backed(self) -> None:
        for marker in (
            "struct ImageOCRProvenanceDisclosureView: View",
            "DisclosureGroup(isExpanded: $isExpanded)",
            "ImageOCRResultSummary.requiresReview(block)",
            "block.ocrProvenance?.candidates.isEmpty == false",
            "LabeledContent(\"记录状态\", value: \"只读；不改变 OCR、翻译或复查\")",
            "候选 \\(index + 1)",
            "引擎内部置信度",
            "不跨引擎比较",
            "accessibilityLabel(\"识别来源，只读\")",
            "不会选择候选或改变复查状态",
        ):
            self.assertIn(marker, self.view)

    def test_disclosure_does_not_mutate_product_selection_or_leak_ephemeral_identity(self) -> None:
        for forbidden in (
            "TranslationSessionStore",
            "@EnvironmentObject",
            "@Binding",
            "ImageOCRSelectorPolicy",
            "ImageOCRShadowLedger",
            "groundTruth",
            "verticalTextRegionOwner",
            ".onTapGesture",
            "setImageTranslationBlock",
            "rerun",
        ):
            self.assertNotIn(forbidden, self.view)
        self.assertIn("ImageOCRProvenanceDisclosureView(block: block)", self.rows)
        self.assertIn("var ocrProvenance: ImageOCRBlockProvenance?", self.models)
        self.assertIn("struct ImageOCRBlockProvenance", self.provenance)

    def test_project_membership_workflow_route_and_current_version_are_explicit(self) -> None:
        for marker in (
            "ImageOCRProvenanceDisclosureView.swift in Sources",
            "path = ImageOCRProvenanceDisclosureView.swift;",
            "scripts/test-v3289-image-ocr-provenance-disclosure-contract.py",
            "japanese-benchmark-v3.301-",
            "v3.289",
        ):
            self.assertIn(marker, self.project + self.workflow + self.route)
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.313", "3.313"],
        )

    def test_static_contract_has_no_process_entry(self) -> None:
        process_word = "sub" + "process"
        popen_word = "Po" + "pen"
        system_word = "os." + "system"
        contract = read("scripts/test-v3289-image-ocr-provenance-disclosure-contract.py")
        for source in (contract, self.view):
            self.assertNotIn(process_word, source)
            self.assertNotIn(popen_word, source)
            self.assertNotIn(system_word, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
