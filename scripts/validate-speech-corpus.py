#!/usr/bin/env python3
"""Validate the optional versioned Speech quality corpus and audio identities."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


SCHEMA_VERSION = "aitrans.speech_corpus.v1"
SHA256_PATTERN = re.compile(r"^[0-9a-fA-F]{64}$")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate(root: Path) -> tuple[dict[str, object], bool]:
    manifest_path = root / "manifest.json"
    if not manifest_path.is_file():
        return (
            {
                "schemaVersion": SCHEMA_VERSION,
                "verdict": "manifestMissing",
                "manifestPath": str(manifest_path),
                "qualityExecuted": False,
                "message": "Optional real-audio corpus is not present; no quality claim was produced.",
            },
            True,
        )

    errors: list[str] = []
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return (
            {
                "schemaVersion": SCHEMA_VERSION,
                "verdict": "invalidManifest",
                "manifestPath": str(manifest_path),
                "qualityExecuted": False,
                "errors": [str(error)],
            },
            False,
        )

    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        errors.append(f"schemaVersion must equal {SCHEMA_VERSION}")
    for key in ("corpusID", "corpusVersion"):
        if not isinstance(manifest.get(key), str) or not manifest[key].strip():
            errors.append(f"{key} must be a non-empty string")

    cases = manifest.get("cases")
    if not isinstance(cases, list) or not cases:
        errors.append("cases must be a non-empty array")
        cases = []

    identities: list[dict[str, object]] = []
    seen_ids: set[str] = set()
    required_strings = (
        "id",
        "audioFile",
        "audioSHA256",
        "localeIdentifier",
        "referenceTranscript",
        "sourceDescription",
    )
    for index, item in enumerate(cases):
        prefix = f"cases[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{prefix} must be an object")
            continue
        for key in required_strings:
            if not isinstance(item.get(key), str) or not item[key].strip():
                errors.append(f"{prefix}.{key} must be a non-empty string")

        case_id = item.get("id")
        if isinstance(case_id, str):
            if case_id in seen_ids:
                errors.append(f"{prefix}.id duplicates {case_id!r}")
            seen_ids.add(case_id)

        audio_file = item.get("audioFile")
        if not isinstance(audio_file, str) or Path(audio_file).name != audio_file:
            errors.append(f"{prefix}.audioFile must be a plain filename")
            continue
        audio_path = root / audio_file
        expected_size = item.get("audioByteCount")
        if not isinstance(expected_size, int) or isinstance(expected_size, bool) or expected_size <= 0:
            errors.append(f"{prefix}.audioByteCount must be a positive integer")
        expected_sha = item.get("audioSHA256")
        if not isinstance(expected_sha, str) or not SHA256_PATTERN.fullmatch(expected_sha):
            errors.append(f"{prefix}.audioSHA256 must be 64 hexadecimal characters")

        if not audio_path.is_file():
            errors.append(f"{prefix} audio file missing: {audio_file}")
            continue
        actual_size = audio_path.stat().st_size
        actual_sha = sha256(audio_path)
        if isinstance(expected_size, int) and actual_size != expected_size:
            errors.append(f"{prefix} byte count mismatch: expected {expected_size}, got {actual_size}")
        if isinstance(expected_sha, str) and actual_sha.lower() != expected_sha.lower():
            errors.append(f"{prefix} SHA256 mismatch: expected {expected_sha.lower()}, got {actual_sha}")
        identities.append(
            {
                "id": case_id,
                "audioFile": audio_file,
                "audioByteCount": actual_size,
                "audioSHA256": actual_sha,
                "localeIdentifier": item.get("localeIdentifier"),
            }
        )

    valid = not errors
    return (
        {
            "schemaVersion": SCHEMA_VERSION,
            "verdict": "valid" if valid else "invalidManifest",
            "manifestPath": str(manifest_path),
            "manifestSHA256": sha256(manifest_path),
            "corpusID": manifest.get("corpusID"),
            "corpusVersion": manifest.get("corpusVersion"),
            "caseCount": len(cases),
            "qualityExecuted": False,
            "referenceUsedForEvaluationOnly": True,
            "referenceUsedForRecognitionDecision": False,
            "audioIdentities": identities,
            "errors": errors,
        },
        valid,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("test/speech_corpus"))
    parser.add_argument("--require-manifest", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    result, valid = validate(args.root)
    if args.require_manifest and result["verdict"] == "manifestMissing":
        result["verdict"] = "invalidManifest"
        result["errors"] = ["manifest.json is required for this invocation"]
        valid = False

    rendered = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
