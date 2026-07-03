#!/usr/bin/env python3
"""Validate non-active Koharu native shadow artifact exports."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REQUIRED_FILES = [
    "1.native_manifest.json",
    "1.native_textboxes.json",
    "1.native_bubbles.json",
    "1.native_segment_mask.json",
    "1.native_artifact_bundle.json",
]


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate AITRANS Koharu shadow artifacts without converting them to active artifacts."
    )
    parser.add_argument("--root", type=Path, default=Path("output/koharu_native_shadow_artifacts"))
    parser.add_argument("--allow-missing", action="store_true")
    parser.add_argument("--expect-shadow-valid", action="store_true")
    args = parser.parse_args()

    root = args.root
    if not root.exists():
        result = {
            "validationPassed": bool(args.allow_missing),
            "verdict": "missingShadowArtifactDirectory",
            "root": str(root),
            "readyForActiveArtifact": False,
            "forbiddenAsActiveArtifact": True,
            "missingFiles": REQUIRED_FILES,
        }
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0 if args.allow_missing and not args.expect_shadow_valid else 1

    missing = [name for name in REQUIRED_FILES if not (root / name).is_file()]
    empty = [name for name in REQUIRED_FILES if (root / name).is_file() and (root / name).stat().st_size <= 0]
    errors: list[str] = []
    manifest = {}
    if "1.native_manifest.json" not in missing and "1.native_manifest.json" not in empty:
        try:
            manifest = load_json(root / "1.native_manifest.json")
        except Exception as exc:  # noqa: BLE001 - report JSON failure without hiding path.
            errors.append(f"manifestParseFailed:{exc}")

    expected_false = ["readyForActiveArtifact", "activeArtifactsDirectory", "activeArtifactsWritten", "wouldChangeMainFlow"]
    expected_true = ["shadowOnly", "contractExampleOnly", "forbiddenAsActiveArtifact"]
    for key in expected_true:
        if manifest.get(key) is not True:
            errors.append(f"{key}MustBeTrue")
    for key in expected_false:
        if manifest.get(key) is not False:
            errors.append(f"{key}MustBeFalse")
    if manifest.get("groundTruthUsedForDecision") is not False:
        errors.append("groundTruthUsedForDecisionMustBeFalse")

    record_counts: dict[str, int] = {}
    for name in REQUIRED_FILES[1:]:
        if name in missing or name in empty:
            continue
        try:
            data = load_json(root / name)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{name}:parseFailed:{exc}")
            continue
        record_counts[name] = len(data) if isinstance(data, list) else 1
        records = data if isinstance(data, list) else [data]
        for index, record in enumerate(records):
            if not isinstance(record, dict):
                errors.append(f"{name}[{index}]:recordMustBeObject")
                continue
            if record.get("forbiddenAsActiveArtifact") is not True:
                errors.append(f"{name}[{index}]:forbiddenAsActiveArtifactMustBeTrue")
            if record.get("readyForActiveArtifact") is not False:
                errors.append(f"{name}[{index}]:readyForActiveArtifactMustBeFalse")
            if record.get("wouldCreateActiveArtifact") is not False:
                errors.append(f"{name}[{index}]:wouldCreateActiveArtifactMustBeFalse")

    passed = not missing and not empty and not errors
    result = {
        "validationPassed": passed,
        "verdict": "validShadowExport" if passed else "invalidShadowExport",
        "root": str(root),
        "readyForActiveArtifact": False,
        "forbiddenAsActiveArtifact": True,
        "missingFiles": missing,
        "emptyFiles": empty,
        "recordCounts": record_counts,
        "errors": errors,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if passed or (args.allow_missing and missing) else 1


if __name__ == "__main__":
    sys.exit(main())
