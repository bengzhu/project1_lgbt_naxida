#!/usr/bin/env python3
"""Static contracts for v3.18 image review progress and runtime evidence."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class V318ImageReviewProgressEvidenceContractTests(unittest.TestCase):
    def test_progress_is_scoped_to_nonempty_review_collection(self) -> None:
        source = read("AITRANS/Views/ImageTranslationViews.swift")
        body = re.search(
            r"if !allReviewRequiredBlocks\.isEmpty \{(?P<body>.*?)\n\s*\}\n\n\s*if !reviewRequiredBlocks\.isEmpty",
            source,
            re.S,
        )
        self.assertIsNotNone(body)
        self.assertIn("ProgressView(", body.group("body"))

    def test_progress_uses_completed_and_total_counts(self) -> None:
        source = read("AITRANS/Views/ImageTranslationViews.swift")
        self.assertIn("value: Double(reviewCompletedBlockCount)", source)
        self.assertIn("total: Double(allReviewRequiredBlocks.count)", source)
        self.assertIn("已完成 \\(reviewCompletedBlockCount) / \\(allReviewRequiredBlocks.count)", source)

    def test_progress_accessibility_reports_remaining_count(self) -> None:
        source = read("AITRANS/Views/ImageTranslationViews.swift")
        self.assertIn('.accessibilityLabel("本次复查进度")', source)
        self.assertIn("剩余 \\(reviewRequiredBlocks.count) 个", source)
        self.assertIn("Color.appSuccess : Color.appWarning", source)

    def test_preview_fixture_covers_two_explicit_risk_reasons(self) -> None:
        source = read("AITRANS/Views/AppPreviewSupport.swift")
        fixture = re.search(r"case \.imageSuccess:(?P<body>.*?)case \.audioRecognizing:", source, re.S)
        self.assertIsNotNone(fixture)
        body = fixture.group("body")
        self.assertRegex(body, r"(?s)confidence: 0\.42,.*?sourceDirection: \.horizontal")
        self.assertRegex(body, r"(?s)confidence: 0\.88,.*?sourceDirection: \.unknown")

    def test_wide_image_success_capture_is_required(self) -> None:
        capture = read("scripts/capture-ui-evidence.sh")
        self.assertIn(
            'capture "$wide_id" "wide-iPad" imageSuccess large portrait image-success-wide-ipad-day.png false 日间',
            capture,
        )

    def test_evidence_matrix_requires_two_wide_scenarios(self) -> None:
        capture = read("scripts/capture-ui-evidence.sh")
        self.assertIn("Expected 14 screenshots (12 compact iPhone + 2 wide iPad)", capture)
        self.assertIn('if len(compact) != 12:', capture)
        self.assertIn('if len(wide) != 2:', capture)
        self.assertIn('{item["scenario"] for item in wide} != {"empty", "imageSuccess"}', capture)
        self.assertIn('item["orientation"] != "portrait" for item in wide', capture)

    def test_ci_runs_v318_after_v317(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        old = "python3 -B scripts/test-v317-image-review-progress-contract.py"
        new = "python3 -B scripts/test-v318-image-review-progress-evidence-contract.py"
        self.assertIn(new, workflow)
        self.assertLess(workflow.index(old), workflow.index(new))


if __name__ == "__main__":
    unittest.main()
