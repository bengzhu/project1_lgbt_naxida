#!/usr/bin/env python3
"""Resolve one marketing version from an Xcode project file."""

from __future__ import annotations

import argparse
from pathlib import Path
import re


CONFIGURATION_PATTERN = re.compile(
    r"/\*\s*(?P<label>[^*]+?)\s*\*/\s*=\s*\{\s*"
    r"isa\s*=\s*XCBuildConfiguration;\s*"
    r"buildSettings\s*=\s*\{(?P<settings>.*?)^\s*\};\s*"
    r"name\s*=\s*(?P<name>[^;]+);",
    re.MULTILINE | re.DOTALL,
)
MARKETING_VERSION_ASSIGNMENT = re.compile(
    r"^\s*MARKETING_VERSION\s*=\s*(.*?)\s*;\s*$",
    re.MULTILINE,
)
VERSION_PATTERN = re.compile(r"[0-9]+(?:\.[0-9]+)+")
REF_VERSION_PATTERN = re.compile(
    r"(?:^|/)v([0-9]+\.[0-9]+(?:\.[0-9]+)*)(?=$|[-/])"
)
NUMERIC_REF_PATTERN = re.compile(r"([0-9]+\.[0-9]+(?:\.[0-9]+)*)")


def normalize_version(raw_value: str, configuration: str) -> str:
    value = raw_value.strip()
    if value.startswith('"') or value.endswith('"'):
        if len(value) < 2 or not (value.startswith('"') and value.endswith('"')):
            raise ValueError(
                f"MARKETING_VERSION has mismatched quotes in {configuration}: "
                f"{raw_value!r}"
            )
        value = value[1:-1].strip()
    if VERSION_PATTERN.fullmatch(value) is None:
        raise ValueError(
            f"MARKETING_VERSION is invalid in {configuration}: {raw_value!r}"
        )
    return value


def resolve_project_version(project_path: Path) -> str:
    project = project_path.read_text(encoding="utf-8")
    app_configurations: list[tuple[str, str]] = []
    for match in CONFIGURATION_PATTERN.finditer(project):
        settings = match.group("settings")
        if "PRODUCT_BUNDLE_IDENTIFIER" not in settings:
            continue
        name = match.group("name").strip().strip('"')
        app_configurations.append((name, settings))

    names = [name for name, _ in app_configurations]
    for required_name in ("Debug", "Release"):
        if names.count(required_name) != 1:
            raise ValueError(
                f"App target requires exactly one {required_name} "
                f"XCBuildConfiguration in {project_path}"
            )

    versions: list[str] = []
    for name, settings in app_configurations:
        assignments = MARKETING_VERSION_ASSIGNMENT.findall(settings)
        if len(assignments) != 1:
            raise ValueError(
                f"{name} requires exactly one MARKETING_VERSION in {project_path}"
            )
        versions.append(normalize_version(assignments[0], name))

    unique_versions = sorted(set(versions))
    if len(unique_versions) != 1:
        raise ValueError(
            f"MARKETING_VERSION values disagree in {project_path}: "
            + ", ".join(unique_versions)
        )
    return f"v{unique_versions[0]}"


def resolve_ci_version(project_path: Path, ref: str | None) -> str:
    if ref:
        ref_versions = REF_VERSION_PATTERN.findall(ref)
        numeric_ref = NUMERIC_REF_PATTERN.fullmatch(ref)
        if numeric_ref is not None:
            ref_versions.append(numeric_ref.group(1))
        unique_ref_versions = sorted(set(ref_versions))
        if len(unique_ref_versions) > 1:
            raise ValueError(
                f"multiple version segments in ref {ref!r}: "
                + ", ".join(unique_ref_versions)
            )
        if unique_ref_versions:
            return f"v{unique_ref_versions[0]}"
    return resolve_project_version(project_path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "project",
        nargs="?",
        type=Path,
        default=Path("AITRANS.xcodeproj/project.pbxproj"),
    )
    parser.add_argument("--ref", help="Git ref name; a full vX.Y segment wins")
    args = parser.parse_args()
    try:
        print(resolve_ci_version(args.project, args.ref))
    except (OSError, ValueError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
