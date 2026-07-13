#!/usr/bin/env python3
"""Contract tests for v1.94 task-scoped CI validation tiers."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
CI_WORKFLOW = ROOT / ".github/workflows/ci-results.yml"
IPA_WORKFLOW = ROOT / ".github/workflows/build.yml"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class CIValidationTierContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = read(CI_WORKFLOW)
        cls.ipa_workflow = read(IPA_WORKFLOW)

    def test_pr_followup_runs_once_without_synchronize_duplication(self) -> None:
        trigger = self.workflow.split("  workflow_dispatch:", 1)[0]
        self.assertIn("  pull_request:\n", trigger)
        self.assertIn("      - opened\n", trigger)
        self.assertIn("      - reopened\n", trigger)
        self.assertIn("      - ready_for_review\n", trigger)
        self.assertNotIn("synchronize", trigger)
        self.assertIn('validation_reason="pull_request_followup_no_synchronize"', self.workflow)

    def test_candidate_push_is_full_and_merge_requires_receipt(self) -> None:
        self.assertIn('validation_reason="candidate_development_push"', self.workflow)
        self.assertIn("AITRANS CI/full-validation", self.workflow)
        self.assertIn('reused_full_validation_sha="$(git rev-parse HEAD^2)"', self.workflow)
        self.assertIn('if [ "$reused_full_validation_state" = "success" ]; then', self.workflow)
        self.assertIn(
            'validation_reason="merge_reuses_successful_candidate_full_validation"',
            self.workflow,
        )
        self.assertIn(
            'validation_reason="merge_missing_successful_candidate_full_validation"',
            self.workflow,
        )
        self.assertIn("statuses: write", self.workflow)

    def test_metadata_followup_cannot_hide_failed_core_validation(self) -> None:
        self.assertIn(
            'validation_reason="candidate_metadata_followup_reuses_parent_full_validation"',
            self.workflow,
        )
        self.assertIn("candidate_parent_full_validation_state", self.workflow)
        self.assertIn("candidate_merge_base", self.workflow)
        self.assertIn("receipt_propagation_allowed=true", self.workflow)
        self.assertIn(
            "Metadata-only follow-up has no successful parent receipt; expanding scope",
            self.workflow,
        )

    def test_fast_followup_skips_expensive_task_suites(self) -> None:
        fast_block = re.search(
            r'if \[ "\$validation_profile" = "fast" \]; then(?P<body>.*?)\n\s*fi',
            self.workflow,
            re.DOTALL,
        )
        self.assertIsNotNone(fast_block)
        body = fast_block.group("body")
        for output in (
            "speech_contract_required=false",
            "ui_interaction_contract_required=false",
            "home_ui_contract_required=false",
            "paste_matrix_contract_required=false",
            "koharu_contract_required=false",
        ):
            self.assertIn(output, body)
        self.assertIn('xcode_build_skip_reason="fast_followup_reuses_candidate_full_validation"', self.workflow)

    def test_domain_contracts_are_task_scoped(self) -> None:
        expected_conditions = (
            "if: steps.ci_scope.outputs.speech_contract_required == 'true'",
            "if: steps.ci_scope.outputs.ui_interaction_contract_required == 'true'",
            "if: steps.ci_scope.outputs.home_ui_contract_required == 'true'",
            "if: steps.ci_scope.outputs.paste_matrix_contract_required == 'true'",
        )
        for condition in expected_conditions:
            self.assertIn(condition, self.workflow)
        self.assertIn(
            'if [ "${{ steps.ci_scope.outputs.koharu_contract_required }}" = "true" ]; then',
            self.workflow,
        )

    def test_ui_evidence_is_explicit_not_version_branch_wide(self) -> None:
        capture_step = self.workflow.split("      - name: Capture current HEAD UI evidence", 1)[1]
        capture_step = capture_step.split("      - name:", 1)[0]
        self.assertIn("steps.ci_scope.outputs.ui_evidence_required == 'true'", capture_step)
        self.assertNotIn("startsWith(github.ref_name", capture_step)
        self.assertIn("[ui evidence]", self.workflow)
        self.assertIn("requested_ui_evidence_mode", self.workflow)

    def test_manifest_exposes_reuse_and_scope_evidence(self) -> None:
        for key in (
            '"validationProfile"',
            '"validationReason"',
            '"reusedFullValidationSha"',
            '"reusedFullValidationState"',
            '"candidateParentFullValidationState"',
            '"receiptPropagationAllowed"',
            '"speechRecognitionContractRequired"',
            '"uiEvidenceRequired"',
            '"koharuContractRequired"',
        ):
            self.assertIn(key, self.workflow)
        self.assertIn('"commitSha": "${CI_COMMIT_SHA}"', self.workflow)

    def test_large_manifest_script_has_no_inline_actions_expressions(self) -> None:
        manifest_step = self.workflow.split("      - name: Write manifest", 1)[1]
        manifest_step = manifest_step.split("      - name: Append v1.88", 1)[0]
        run_script = manifest_step.split("        run: |", 1)[1]
        self.assertNotIn("${{", run_script)
        self.assertIn('os.environ["MANIFEST_VALIDATION_PROFILE"]', run_script)

    def test_ipa_packaging_is_manual_only(self) -> None:
        trigger = self.ipa_workflow.split("jobs:", 1)[0]
        self.assertIn("  workflow_dispatch:", trigger)
        self.assertNotIn("  push:", trigger)


if __name__ == "__main__":
    unittest.main()
