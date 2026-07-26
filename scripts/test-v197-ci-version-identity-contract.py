#!/usr/bin/env python3
"""Contract tests for CI artifact version identity."""

from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RESOLVER = ROOT / "scripts/resolve-project-version.py"
WORKFLOW = ROOT / ".github/workflows/ci-results.yml"
PROJECT = ROOT / "AITRANS.xcodeproj/project.pbxproj"


class CIVersionIdentityContractTests(unittest.TestCase):
    @staticmethod
    def project_fixture(
        debug_version: str | None,
        release_version: str | None,
    ) -> str:
        blocks = []
        for identifier, name, version in (
            ("AAA", "Debug", debug_version),
            ("BBB", "Release", release_version),
        ):
            if version is None:
                continue
            blocks.append(
                f"""
        {identifier} /* {name} */ = {{
            isa = XCBuildConfiguration;
            buildSettings = {{
                PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
                MARKETING_VERSION = {version};
            }};
            name = {name};
        }};
"""
            )
        return "".join(blocks)

    def run_resolver(
        self,
        contents: str,
        ref: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / "project.pbxproj"
            project.write_text(contents, encoding="utf-8")
            command = ["python3", str(RESOLVER)]
            if ref is not None:
                command.extend(["--ref", ref])
            command.append(str(project))
            return subprocess.run(
                command,
                check=False,
                capture_output=True,
                text=True,
            )

    def test_current_project_resolves_formal_version(self) -> None:
        result = subprocess.run(
            ["python3", str(RESOLVER), str(PROJECT)],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        assignments = re.findall(
            r"^\s*MARKETING_VERSION\s*=\s*([^;]+);",
            PROJECT.read_text(encoding="utf-8"),
            re.MULTILINE,
        )
        normalized = {value.strip().strip('"').strip() for value in assignments}
        self.assertEqual(len(normalized), 1, "App build configurations must agree")
        self.assertEqual(result.stdout.strip(), f"v{normalized.pop()}")

    def test_matching_quoted_build_configurations_resolve_once(self) -> None:
        result = self.run_resolver(
            self.project_fixture("1.97", '" 1.97 "')
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "v1.97")

    def test_invalid_conflicting_or_missing_versions_are_rejected(self) -> None:
        invalid = self.run_resolver(self.project_fixture("1.97", "latest"))
        conflicting = self.run_resolver(self.project_fixture("1.97", "1.98"))
        missing_release = self.run_resolver(self.project_fixture("1.97", None))
        self.assertNotEqual(invalid.returncode, 0)
        self.assertIn("MARKETING_VERSION is invalid in Release", invalid.stderr)
        self.assertNotEqual(conflicting.returncode, 0)
        self.assertIn("values disagree", conflicting.stderr)
        self.assertNotEqual(missing_release.returncode, 0)
        self.assertIn(
            "exactly one Release XCBuildConfiguration",
            missing_release.stderr,
        )

    def test_ref_matrix_uses_only_full_version_segments(self) -> None:
        project = self.project_fixture("9.9", "9.9")
        cases = {
            "codeb/v1.97-ci-version-identity": "v1.97",
            "codeb/v2.3/followup": "v2.3",
            "1.97": "v1.97",
            "smalldata_test": "v9.9",
            "codeb/rev2026-clean": "v9.9",
            "codeb/v1-hotfix": "v9.9",
            "codeb/feature-v2.0": "v9.9",
        }
        for ref, expected in cases.items():
            with self.subTest(ref=ref):
                result = self.run_resolver(project, ref)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

        ambiguous = self.run_resolver(project, "codeb/v1.97/v1.98")
        self.assertNotEqual(ambiguous.returncode, 0)
        self.assertIn("multiple version segments", ambiguous.stderr)

    def test_workflow_uses_project_fallback_and_runs_contract(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(
            'version="$(python3 scripts/resolve-project-version.py --ref "$branch")"',
            workflow,
        )
        self.assertNotIn('[[ "$branch" =~ v(', workflow)
        self.assertIn(
            "python3 -B scripts/test-v197-ci-version-identity-contract.py",
            workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
