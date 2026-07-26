#!/usr/bin/env python3
"""Contract tests for Koharu handoff repository, ref, and commit identity."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "scripts/validate-koharu-artifacts.py"
WORKFLOW = ROOT / ".github/workflows/ci-results.yml"
TEST_SHA = "0123456789abcdef0123456789abcdef01234567"


def load_validator():
    spec = importlib.util.spec_from_file_location("koharu_validator_v197", VALIDATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load Koharu validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class KoharuHandoffTargetContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.validator = load_validator()
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_explicit_target_identity_is_preserved(self) -> None:
        target = self.validator.resolve_handoff_target(
            "fixture-owner/fixture-repo",
            "codeb/v1.97-fixture",
            TEST_SHA.upper(),
        )
        self.assertEqual(target["repo"], "fixture-owner/fixture-repo")
        self.assertEqual(target["repoSource"], "argument")
        self.assertEqual(target["workflowRef"], "codeb/v1.97-fixture")
        self.assertEqual(target["workflowRefSource"], "argument")
        self.assertEqual(target["expectedCommitSha"], TEST_SHA)
        self.assertEqual(target["expectedCommitShaSource"], "argument")

    def test_github_environment_is_preferred_over_git_fallback(self) -> None:
        environment = {
            "GITHUB_REPOSITORY": "environment-owner/environment-repo",
            "GITHUB_REF_NAME": "codeb/environment-ref",
            "GITHUB_SHA": TEST_SHA,
        }
        with mock.patch.dict(os.environ, environment, clear=False), mock.patch.object(
            self.validator, "git_output", side_effect=AssertionError("git fallback must not run")
        ):
            target = self.validator.resolve_handoff_target(None, None, None)
        self.assertEqual(target["repoSource"], "GITHUB_REPOSITORY")
        self.assertEqual(target["workflowRefSource"], "GITHUB_REF_NAME")
        self.assertEqual(target["expectedCommitShaSource"], "GITHUB_SHA")

    def test_git_remote_branch_and_head_are_reliable_local_fallbacks(self) -> None:
        outputs = {
            ("config", "--get", "remote.origin.url"): "git@github.com:local-owner/local-repo.git",
            ("branch", "--show-current"): "codeb/local-ref",
            ("rev-parse", "HEAD"): TEST_SHA,
        }
        clean_environment = {
            key: value
            for key, value in os.environ.items()
            if key not in {"GITHUB_REPOSITORY", "GITHUB_REF_NAME", "GITHUB_SHA"}
        }
        with mock.patch.dict(os.environ, clean_environment, clear=True), mock.patch.object(
            self.validator, "git_output", side_effect=lambda *args: outputs.get(args)
        ):
            target = self.validator.resolve_handoff_target(None, None, None)
        self.assertEqual(target["repo"], "local-owner/local-repo")
        self.assertEqual(target["repoSource"], "gitRemoteOrigin")
        self.assertEqual(target["workflowRef"], "codeb/local-ref")
        self.assertEqual(target["expectedCommitSha"], TEST_SHA)

    def test_invalid_explicit_identity_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "owner/repo"):
            self.validator.resolve_handoff_target("not-a-repo", "codeb/test", TEST_SHA)
        with self.assertRaisesRegex(ValueError, "40-character"):
            self.validator.resolve_handoff_target("owner/repo", "codeb/test", "abc123")

    def test_packet_commands_and_assertions_share_one_target(self) -> None:
        result = subprocess.run(
            [
                "python3",
                "-B",
                str(VALIDATOR),
                "--root",
                "test/koharu_artifacts",
                "--allow-missing",
                "--emit-handoff-packet",
                "--repo",
                "fixture-owner/fixture-repo",
                "--workflow-ref",
                "codeb/v1.97-fixture",
                "--expected-commit-sha",
                TEST_SHA,
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        import json

        packet = json.loads(result.stdout)["handoffPacket"]
        dispatch = packet["ghWorkflowDispatchCommand"]
        run_list = packet["ghRunListCommand"]
        self.assertIn("--repo fixture-owner/fixture-repo", dispatch)
        self.assertIn("--ref codeb/v1.97-fixture", dispatch)
        self.assertIn(f"expected_commit_sha={TEST_SHA}", dispatch)
        self.assertIn("--branch codeb/v1.97-fixture", run_list)
        assertions = {
            row["jsonPath"]: row["expected"]
            for row in packet["expectedCIManifestAssertions"]
        }
        self.assertEqual(assertions["repository"], "fixture-owner/fixture-repo")
        self.assertEqual(assertions["branch"], "codeb/v1.97-fixture")
        self.assertEqual(assertions["commitSha"], TEST_SHA)
        manifest_echo = packet["expectedCIManifestEcho"]
        self.assertEqual(manifest_echo["repository"], "fixture-owner/fixture-repo")
        self.assertEqual(manifest_echo["branch"], "codeb/v1.97-fixture")
        self.assertEqual(manifest_echo["commitSha"], TEST_SHA)
        self.assertEqual(packet["ciResultReview"]["manifestIdentityChecks"]["commitSha"], TEST_SHA)

    def test_ci_fixture_passes_explicit_target_identity(self) -> None:
        self.assertIn("python3 -B scripts/test-v197-koharu-handoff-target-contract.py", self.workflow)
        self.assertIn("--repo fixture-owner/fixture-repo", self.workflow)
        self.assertIn("--workflow-ref codeb/fixture-target", self.workflow)
        self.assertIn(f"--expected-commit-sha {TEST_SHA}", self.workflow)
        self.assertIn("expected_commit_sha", self.workflow)
        self.assertIn("workflow_dispatch SHA mismatch", self.workflow)
        self.assertNotIn("Altman-sam114/x113451", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
