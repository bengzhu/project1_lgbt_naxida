#!/usr/bin/env python3
"""Align and score same-crop Japanese OCR engine artifacts.

The evaluator is deliberately independent from the AITRANS target.  It only
accepts an artifact envelope whose rows carry the complete comparison key:
dataset SHA, page ID, region ID, and crop level.  Results are joined by that
key and never by array position.  Oracle and detected crops are emitted as
separate tables so detector/crop failures cannot be hidden inside recognizer
metrics.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import unicodedata
from typing import Any


SCHEMA_VERSION = "1.0.0"
BENCHMARK = "japanese-ocr-multi-engine"
CROP_LEVELS = ("oracleCrop", "detectedCrop")
STATUSES = {"success", "empty", "failure"}
HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX40 = re.compile(r"^[0-9a-f]{40}$")


class MultiEngineBenchmarkError(ValueError):
    """Raised for an invalid, incomplete, or ambiguous oracle artifact."""


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise MultiEngineBenchmarkError(f"cannot read JSON {path}: {error}") from error


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise MultiEngineBenchmarkError(message)


def _reject_unknown(value: dict[str, Any], allowed: set[str], label: str) -> None:
    unknown = sorted(set(value) - allowed)
    _require(not unknown, f"{label} has unknown fields: {unknown}")


def _finite_number(value: Any, label: str) -> float:
    _require(
        isinstance(value, (int, float)) and not isinstance(value, bool),
        f"{label} must be a number",
    )
    result = float(value)
    _require(math.isfinite(result), f"{label} must be finite")
    return result


def _nfc(text: str) -> str:
    return unicodedata.normalize("NFC", text)


def _sha256_json(value: Any) -> str:
    encoded = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _levenshtein(reference: str, hypothesis: str) -> dict[str, int]:
    rows = len(reference) + 1
    columns = len(hypothesis) + 1
    table: list[list[tuple[int, int, int, int]]] = [
        [(0, 0, 0, 0) for _ in range(columns)] for _ in range(rows)
    ]
    for row in range(1, rows):
        table[row][0] = (row, 0, 0, row)
    for column in range(1, columns):
        table[0][column] = (column, 0, column, 0)
    for row in range(1, rows):
        for column in range(1, columns):
            if reference[row - 1] == hypothesis[column - 1]:
                table[row][column] = table[row - 1][column - 1]
                continue
            substitution = table[row - 1][column - 1]
            deletion = table[row - 1][column]
            insertion = table[row][column - 1]
            options = [
                (substitution[0] + 1, substitution[1] + 1, substitution[2], substitution[3]),
                (deletion[0] + 1, deletion[1], deletion[2], deletion[3] + 1),
                (insertion[0] + 1, insertion[1], insertion[2] + 1, insertion[3]),
            ]
            table[row][column] = min(options, key=lambda item: (item[0], item[1], item[2], item[3]))
    distance, substitutions, insertions, deletions = table[-1][-1]
    return {
        "editDistance": distance,
        "substitutions": substitutions,
        "insertions": insertions,
        "deletions": deletions,
        "referenceCharacters": len(reference),
    }


def comparison_key(dataset_sha: str, page_id: str, region_id: str, crop_level: str) -> str:
    """Return the only join key permitted by the v3.282 protocol."""

    return "|".join((dataset_sha, page_id, region_id, crop_level))


def _validate_model(model: Any, label: str, artifact_status: str) -> None:
    _require(isinstance(model, dict), f"{label} must be an object")
    _reject_unknown(model, {"id", "version", "revision", "sha256", "license"}, label)
    for key in ("id", "version", "revision", "license"):
        _require(isinstance(model.get(key), str) and model[key].strip(), f"{label}.{key} is required")
    model_sha = model.get("sha256")
    if artifact_status == "available":
        _require(isinstance(model_sha, str) and bool(HEX64.fullmatch(model_sha)), f"{label}.sha256 is required for an available artifact")
    else:
        _require(model_sha is None or (isinstance(model_sha, str) and bool(HEX64.fullmatch(model_sha))), f"{label}.sha256 is invalid")


def _validate_engine(engine: Any, index: int) -> str:
    label = f"engines[{index}]"
    _require(isinstance(engine, dict), f"{label} must be an object")
    _reject_unknown(
        engine,
        {
            "engineID", "engineVersion", "sourceRevision", "runtimeRevision",
            "model", "license", "referenceOnly", "artifactStatus", "failureReason",
        },
        label,
    )
    for key in (
        "engineID", "engineVersion", "sourceRevision", "runtimeRevision",
        "model", "license", "referenceOnly", "artifactStatus", "failureReason",
    ):
        _require(key in engine, f"{label} missing {key}")
    engine_id = engine["engineID"]
    _require(isinstance(engine_id, str) and engine_id.strip(), f"{label}.engineID is empty")
    _require(isinstance(engine["engineVersion"], str) and engine["engineVersion"].strip(), f"{label}.engineVersion is empty")
    _require(isinstance(engine["sourceRevision"], str) and engine["sourceRevision"].strip(), f"{label}.sourceRevision is empty")
    _require(isinstance(engine["runtimeRevision"], str) and engine["runtimeRevision"].strip(), f"{label}.runtimeRevision is empty")
    _require(isinstance(engine["license"], str) and engine["license"].strip(), f"{label}.license is empty")
    _require(isinstance(engine["referenceOnly"], bool), f"{label}.referenceOnly must be boolean")
    artifact_status = engine["artifactStatus"]
    _require(artifact_status in {"available", "missing", "failed"}, f"{label}.artifactStatus is invalid")
    failure_reason = engine["failureReason"]
    if artifact_status == "available":
        _require(failure_reason is None, f"{label}.available artifact cannot carry failureReason")
    else:
        _require(isinstance(failure_reason, str) and failure_reason.strip(), f"{label}.{artifact_status} artifact needs failureReason")
    _validate_model(engine["model"], f"{label}.model", artifact_status)
    return engine_id


def _validate_crop(crop: Any, index: int, dataset_sha: str) -> tuple[str, dict[str, Any]]:
    label = f"cropSet[{index}]"
    _require(isinstance(crop, dict), f"{label} must be an object")
    _reject_unknown(
        crop,
        {
            "pageID", "regionID", "cropLevel", "cropID", "cropSha256", "source",
            "expectedText", "expectedTextNFC", "referenceOnly",
        },
        label,
    )
    for key in ("pageID", "regionID", "cropLevel", "cropID", "cropSha256", "source", "referenceOnly"):
        _require(key in crop, f"{label} missing {key}")
    for key in ("pageID", "regionID", "cropID", "cropSha256", "source"):
        _require(isinstance(crop[key], str) and crop[key].strip(), f"{label}.{key} is empty")
    _require(bool(HEX64.fullmatch(crop["cropSha256"])), f"{label}.cropSha256 is invalid")
    crop_level = crop["cropLevel"]
    _require(crop_level in CROP_LEVELS, f"{label}.cropLevel is invalid")
    _require(isinstance(crop["referenceOnly"], bool), f"{label}.referenceOnly must be boolean")
    expected_text = crop.get("expectedText")
    expected_nfc = crop.get("expectedTextNFC")
    if crop_level == "oracleCrop":
        _require(isinstance(expected_text, str) and expected_text != "", f"{label}.expectedText is required for oracleCrop")
        _require(expected_nfc == _nfc(expected_text), f"{label}.expectedTextNFC mismatch")
    else:
        # Detected-crop results are recognizer comparisons on one observed crop.
        # Ground truth belongs to the detector benchmark and must not leak into
        # this same-crop recognizer table.
        _require(expected_text is None and expected_nfc is None, f"{label}.detectedCrop must not carry ground-truth text")
    key = comparison_key(dataset_sha, crop["pageID"], crop["regionID"], crop_level)
    return key, crop


def _validate_result(
    result: Any,
    index: int,
    dataset_sha: str,
    crops: dict[str, dict[str, Any]],
    engines: dict[str, dict[str, Any]],
) -> tuple[tuple[str, str], str, dict[str, Any]]:
    label = f"results[{index}]"
    _require(isinstance(result, dict), f"{label} must be an object")
    _reject_unknown(
        result,
        {
            "engineID", "pageID", "regionID", "cropLevel", "cropID",
            "status", "text", "rawText", "confidence", "failureReason", "referenceOnly",
        },
        label,
    )
    for key in (
        "engineID", "pageID", "regionID", "cropLevel", "cropID",
        "status", "text", "confidence", "failureReason", "referenceOnly",
    ):
        _require(key in result, f"{label} missing {key}")
    engine_id = result["engineID"]
    _require(engine_id in engines, f"{label} references unknown engineID: {engine_id}")
    crop_key = comparison_key(dataset_sha, result["pageID"], result["regionID"], result["cropLevel"])
    _require(crop_key in crops, f"{label} references unknown comparison key: {crop_key}")
    crop = crops[crop_key]
    _require(result["cropID"] == crop["cropID"], f"{label}.cropID does not match the comparison key")
    _require(result["status"] in STATUSES, f"{label}.status is invalid")
    _require(isinstance(result["text"], str), f"{label}.text must be a string")
    if result["status"] == "success":
        _require(result["text"].strip() != "", f"{label}.success text is empty")
        _require(result["failureReason"] is None, f"{label}.success cannot carry failureReason")
    else:
        _require(result["text"] == "", f"{label}.{result['status']} text must be empty")
        _require(isinstance(result["failureReason"], str) and result["failureReason"].strip(), f"{label}.{result['status']} needs failureReason")
    confidence = result["confidence"]
    if confidence is not None:
        value = _finite_number(confidence, f"{label}.confidence")
        _require(0.0 <= value <= 1.0, f"{label}.confidence is outside [0,1]")
    _require(isinstance(result["referenceOnly"], bool), f"{label}.referenceOnly must be boolean")
    _require(result["referenceOnly"] == engines[engine_id]["referenceOnly"], f"{label}.referenceOnly does not match engine metadata")
    if engines[engine_id]["artifactStatus"] != "available":
        _require(result["status"] == "failure", f"{label} must be an explicit failure when the engine artifact is unavailable")
    return (engine_id, crop_key), engine_id, result


def validate_input(payload: dict[str, Any]) -> dict[str, Any]:
    _require(isinstance(payload, dict), "multi-engine input root must be an object")
    _reject_unknown(payload, {"schemaVersion", "benchmark", "datasetSha256", "cropSet", "engines", "results"}, "input")
    _require(payload.get("schemaVersion") == SCHEMA_VERSION, "unsupported multi-engine schemaVersion")
    _require(payload.get("benchmark") == BENCHMARK, "input benchmark must be japanese-ocr-multi-engine")
    dataset_sha = payload.get("datasetSha256")
    _require(isinstance(dataset_sha, str) and bool(HEX64.fullmatch(dataset_sha)), "datasetSha256 is invalid")
    crop_set = payload.get("cropSet")
    engines_payload = payload.get("engines")
    results_payload = payload.get("results")
    _require(isinstance(crop_set, list) and crop_set, "cropSet must be a non-empty array")
    _require(isinstance(engines_payload, list) and engines_payload, "engines must be a non-empty array")
    _require(isinstance(results_payload, list), "results must be an array")

    crops: dict[str, dict[str, Any]] = {}
    for index, crop in enumerate(crop_set):
        key, validated = _validate_crop(crop, index, dataset_sha)
        _require(key not in crops, f"duplicate comparison key: {key}")
        crops[key] = validated

    engines: dict[str, dict[str, Any]] = {}
    for index, engine in enumerate(engines_payload):
        engine_id = _validate_engine(engine, index)
        _require(engine_id not in engines, f"duplicate engineID: {engine_id}")
        engines[engine_id] = engine

    rows: dict[tuple[str, str], dict[str, Any]] = {}
    for index, result in enumerate(results_payload):
        result_key, engine_id, validated = _validate_result(result, index, dataset_sha, crops, engines)
        _require(result_key not in rows, f"duplicate engine/crop result: {result_key}")
        rows[result_key] = validated

    expected_pairs = {(engine_id, crop_key) for engine_id in engines for crop_key in crops}
    actual_pairs = set(rows)
    missing = sorted(expected_pairs - actual_pairs)
    extra = sorted(actual_pairs - expected_pairs)
    _require(not missing, f"missing explicit result rows: {missing}")
    _require(not extra, f"unexpected result rows: {extra}")
    return {
        "datasetSha256": dataset_sha,
        "crops": crops,
        "engines": engines,
        "rows": rows,
    }


def _engine_metrics(
    engine_id: str,
    level: str,
    crop_items: list[tuple[str, dict[str, Any]]],
    rows: dict[tuple[str, str], dict[str, Any]],
) -> dict[str, Any]:
    selected = [rows[(engine_id, key)] for key, crop in crop_items if crop["cropLevel"] == level]
    success = sum(row["status"] == "success" for row in selected)
    empty = sum(row["status"] == "empty" for row in selected)
    failure = sum(row["status"] == "failure" for row in selected)
    result: dict[str, Any] = {
        "sampleCount": len(selected),
        "successCount": success,
        "emptyCount": empty,
        "failureCount": failure,
        "successRate": success / len(selected) if selected else None,
        "exactMatchRate": None,
        "nfcExactMatchRate": None,
        "characterErrorRate": None,
        "editDistance": 0,
        "referenceCharacters": 0,
        "substitutions": 0,
        "insertions": 0,
        "deletions": 0,
    }
    if level != "oracleCrop":
        return result
    exact = 0
    nfc_exact = 0
    for key, crop in crop_items:
        if crop["cropLevel"] != level:
            continue
        reference = crop["expectedText"]
        hypothesis = rows[(engine_id, key)]["text"]
        edits = _levenshtein(reference, hypothesis)
        result["editDistance"] += edits["editDistance"]
        result["referenceCharacters"] += edits["referenceCharacters"]
        result["substitutions"] += edits["substitutions"]
        result["insertions"] += edits["insertions"]
        result["deletions"] += edits["deletions"]
        exact += hypothesis == reference
        nfc_exact += _nfc(hypothesis) == _nfc(reference)
    result["exactMatchRate"] = exact / len(selected) if selected else None
    result["nfcExactMatchRate"] = nfc_exact / len(selected) if selected else None
    result["characterErrorRate"] = (
        result["editDistance"] / result["referenceCharacters"]
        if result["referenceCharacters"]
        else None
    )
    return result


def evaluate(payload: dict[str, Any]) -> dict[str, Any]:
    """Validate input and return a deterministic comparison report."""

    info = validate_input(payload)
    dataset_sha = info["datasetSha256"]
    crops = info["crops"]
    engines = info["engines"]
    rows = info["rows"]
    crop_items = sorted(crops.items(), key=lambda item: item[0])
    engine_items = sorted(engines.items(), key=lambda item: item[0])
    tables: dict[str, dict[str, Any]] = {}
    for level in CROP_LEVELS:
        level_items = [(key, crop) for key, crop in crop_items if crop["cropLevel"] == level]
        table_rows: list[dict[str, Any]] = []
        for key, crop in level_items:
            table_rows.append(
                {
                    "key": key,
                    "pageID": crop["pageID"],
                    "regionID": crop["regionID"],
                    "cropLevel": level,
                    "cropID": crop["cropID"],
                    "cropSha256": crop["cropSha256"],
                    "referenceText": crop.get("expectedText") if level == "oracleCrop" else None,
                    "engines": [
                        {
                            "engineID": engine_id,
                            "status": rows[(engine_id, key)]["status"],
                            "text": rows[(engine_id, key)]["text"],
                            "rawText": rows[(engine_id, key)].get("rawText"),
                            "confidence": rows[(engine_id, key)]["confidence"],
                            "failureReason": rows[(engine_id, key)]["failureReason"],
                        }
                        for engine_id, _engine in engine_items
                    ],
                }
            )
        tables[level] = {
            "sampleCount": len(level_items),
            "rows": table_rows,
            "engineMetrics": [
                {
                    "engineID": engine_id,
                    "metrics": _engine_metrics(engine_id, level, level_items, rows),
                }
                for engine_id, _engine in engine_items
            ],
        }
    all_available = all(engine["artifactStatus"] == "available" for engine in engines.values())
    return {
        "schemaVersion": SCHEMA_VERSION,
        "benchmark": BENCHMARK,
        "status": "success" if all_available else "blocked",
        "datasetSha256": dataset_sha,
        "alignment": {
            "keyFields": ["datasetSha256", "pageID", "regionID", "cropLevel"],
            "joinedByArrayIndex": False,
            "engineCount": len(engines),
            "comparisonKeyCount": len(crops),
        },
        "engines": [
            {
                "engineID": engine_id,
                "engineVersion": engine["engineVersion"],
                "sourceRevision": engine["sourceRevision"],
                "runtimeRevision": engine["runtimeRevision"],
                "model": engine["model"],
                "license": engine["license"],
                "referenceOnly": engine["referenceOnly"],
                "artifactStatus": engine["artifactStatus"],
                "failureReason": engine["failureReason"],
            }
            for engine_id, engine in engine_items
        ],
        "tables": tables,
        "qualityClaim": (
            "same-crop comparison only; blocked until every declared engine artifact is available"
            if not all_available
            else "same-crop comparison only; no generalization beyond the declared dataset"
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--allow-missing-artifacts", action="store_true")
    args = parser.parse_args()
    try:
        report = evaluate(load_json(args.input))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False))
        if report["status"] == "blocked" and not args.allow_missing_artifacts:
            return 1
        return 0
    except MultiEngineBenchmarkError as error:
        print(f"Japanese OCR multi-engine evaluation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
