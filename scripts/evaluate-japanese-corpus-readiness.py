#!/usr/bin/env python3
"""Evaluate the v3.292 shared Japanese corpus and holdout readiness envelope.

The evaluator is intentionally model- and product-path agnostic.  It validates
authorization, dataset identity, annotation coverage, split isolation, the
same-crop prediction matrix, and a pre-holdout policy freeze.  It never loads
an image/model, reads ground truth for a runtime decision, selects an engine,
or enables OCR/translation behavior.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
from typing import Any


SCHEMA_VERSION = "1.0.0"
BENCHMARK = "japanese-corpus-readiness"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
SPLITS = ("train", "dev", "holdout")
CROP_LEVELS = ("oracleCrop", "detectedCrop", "fullPage")
REQUIRED_ENGINES = (
    "aitrans-bundled-manga-ocr",
    "apple-vision",
    "koharu-mit48",
    "koharu-paddleocr-vl",
)
REQUIRED_ANNOTATION_FIELDS = {
    "blockPolygon",
    "linePolygonOrLineOrder",
    "writingDirection",
    "exactSourceText",
    "blockReadingOrder",
    "bubbleAssociation",
    "textType",
}
REQUIRED_TEXT_TYPES = {"dialogue", "narration", "SFX", "title", "other"}
REQUIRED_SCENARIOS = {
    "verticalDialogue",
    "horizontalDialogue",
    "slantedText",
    "narration",
    "SFX",
    "smallText",
    "lowContrast",
    "halftoneBackground",
    "nonWhiteBubble",
    "noBubbleText",
    "mixedScript",
}
ROOT = Path(__file__).resolve().parents[1]


class CorpusReadinessError(ValueError):
    """Raised for malformed or unsafe corpus readiness evidence."""


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def manifest_sha256(manifest: dict[str, Any]) -> str:
    payload = copy.deepcopy(manifest)
    payload["manifestSha256"] = None
    return hashlib.sha256(canonical_json(payload)).hexdigest()


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise CorpusReadinessError(f"cannot read JSON {path}: {error}") from error


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CorpusReadinessError(message)


def _reject_unknown(value: dict[str, Any], allowed: set[str], label: str) -> None:
    unknown = sorted(set(value) - allowed)
    _require(not unknown, f"{label} has unknown fields: {unknown}")


def _string(value: Any, label: str) -> str:
    _require(isinstance(value, str) and value.strip(), f"{label} must be a non-empty string")
    return value


def _sha(value: Any, label: str, *, nullable: bool = False) -> str | None:
    if nullable and value is None:
        return None
    _require(isinstance(value, str) and bool(HEX64.fullmatch(value)), f"{label} is not a SHA-256")
    return value


def _nonnegative_int(value: Any, label: str) -> int:
    _require(isinstance(value, int) and not isinstance(value, bool) and value >= 0, f"{label} must be a non-negative integer")
    return value


def _validate_run(run: Any) -> None:
    _require(isinstance(run, dict), "run must be an object")
    _reject_unknown(run, {"appSha", "evaluatorVersion", "invocationMode"}, "run")
    _require(bool(HEX40.fullmatch(run.get("appSha", ""))), "run.appSha is invalid")
    _string(run.get("evaluatorVersion"), "run.evaluatorVersion")
    _require(run.get("invocationMode") == "cloud-only-shadow", "run.invocationMode must be cloud-only-shadow")


def _validate_dataset(dataset: Any) -> None:
    _require(isinstance(dataset, dict), "dataset must be an object")
    allowed = {
        "status", "datasetID", "datasetVersion", "sha256", "pageCount",
        "annotatedRegionCount", "license", "authorized", "permittedUses",
        "sourceManifestPath",
    }
    _reject_unknown(dataset, allowed, "dataset")
    for key in allowed:
        _require(key in dataset, f"dataset missing {key}")
    _require(dataset["status"] in {"missing", "available", "failed"}, "dataset.status is invalid")
    _string(dataset["datasetID"], "dataset.datasetID")
    _string(dataset["datasetVersion"], "dataset.datasetVersion")
    _sha(dataset["sha256"], "dataset.sha256", nullable=True)
    _nonnegative_int(dataset["pageCount"], "dataset.pageCount")
    _nonnegative_int(dataset["annotatedRegionCount"], "dataset.annotatedRegionCount")
    _string(dataset["license"], "dataset.license")
    _require(isinstance(dataset["authorized"], bool), "dataset.authorized must be boolean")
    _require(isinstance(dataset["permittedUses"], list), "dataset.permittedUses must be an array")
    for index, permitted_use in enumerate(dataset["permittedUses"]):
        _string(permitted_use, f"dataset.permittedUses[{index}]")
    if dataset["sourceManifestPath"] is not None:
        _string(dataset["sourceManifestPath"], "dataset.sourceManifestPath")
    if dataset["status"] == "available":
        _require(dataset["sha256"] is not None, "available dataset needs SHA-256")
        _require(dataset["authorized"], "available dataset must be authorized")
        _require(dataset["sourceManifestPath"] is not None, "available dataset needs source manifest")
    else:
        _require(not dataset["authorized"], "missing/failed dataset cannot be authorized")


def _validate_splits(splits: Any) -> dict[str, dict[str, Any]]:
    _require(isinstance(splits, list) and len(splits) == len(SPLITS), "splits must contain exactly train/dev/holdout")
    by_id: dict[str, dict[str, Any]] = {}
    all_assets: set[str] = set()
    for index, split in enumerate(splits):
        label = f"splits[{index}]"
        _require(isinstance(split, dict), f"{label} must be an object")
        allowed = {"splitID", "status", "pageCount", "regionCount", "assetIDs", "annotationStatus", "groundTruthStatus"}
        _reject_unknown(split, allowed, label)
        for key in allowed:
            _require(key in split, f"{label} missing {key}")
        split_id = split["splitID"]
        _require(split_id in SPLITS, f"{label}.splitID is invalid")
        _require(split_id not in by_id, f"duplicate splitID: {split_id}")
        _require(split["status"] in {"missing", "available", "failed"}, f"{label}.status is invalid")
        _nonnegative_int(split["pageCount"], f"{label}.pageCount")
        _nonnegative_int(split["regionCount"], f"{label}.regionCount")
        _require(isinstance(split["assetIDs"], list), f"{label}.assetIDs must be an array")
        local_assets: set[str] = set()
        for asset_index, asset_id in enumerate(split["assetIDs"]):
            asset = _string(asset_id, f"{label}.assetIDs[{asset_index}]")
            _require(asset not in local_assets, f"duplicate asset ID in {split_id}: {asset}")
            _require(asset not in all_assets, f"asset ID crosses split boundary: {asset}")
            local_assets.add(asset)
            all_assets.add(asset)
        _require(split["annotationStatus"] in {"missing", "partial", "complete"}, f"{label}.annotationStatus is invalid")
        _require(split["groundTruthStatus"] in {"missing", "available", "failed"}, f"{label}.groundTruthStatus is invalid")
        if split["status"] == "available":
            _require(split["pageCount"] > 0 and local_assets, f"{label} available split is empty")
            _require(split["annotationStatus"] == "complete", f"{label} available split needs complete annotations")
            _require(split["groundTruthStatus"] == "available", f"{label} available split needs ground truth")
        by_id[split_id] = split
    _require(set(by_id) == set(SPLITS), "splits must contain each split exactly once")
    return by_id


def _validate_annotation_profile(profile: Any) -> None:
    _require(isinstance(profile, dict), "annotationProfile must be an object")
    allowed = {"requiredFields", "requiredTextTypes", "requiredScenarios", "minimumFullPages", "minimumAnnotatedRegions"}
    _reject_unknown(profile, allowed, "annotationProfile")
    for key in allowed:
        _require(key in profile, f"annotationProfile missing {key}")
    _require(set(profile["requiredFields"]) == REQUIRED_ANNOTATION_FIELDS, "annotationProfile.requiredFields is incomplete or changed")
    _require(set(profile["requiredTextTypes"]) == REQUIRED_TEXT_TYPES, "annotationProfile.requiredTextTypes is incomplete or changed")
    _require(set(profile["requiredScenarios"]) == REQUIRED_SCENARIOS, "annotationProfile.requiredScenarios is incomplete or changed")
    _require(profile["minimumFullPages"] >= 20, "annotationProfile.minimumFullPages is below route requirement")
    _require(profile["minimumAnnotatedRegions"] >= 150, "annotationProfile.minimumAnnotatedRegions is below route requirement")


def _validate_matrix_row(row: Any, label: str) -> tuple[str, str, str]:
    _require(isinstance(row, dict), f"{label} must be an object")
    allowed = {
        "artifactID", "engineID", "cropLevel", "splitID", "status", "path", "sha256",
        "datasetSha256", "sourceRevision", "license", "authorized", "referenceOnly", "predictionCount",
    }
    _reject_unknown(row, allowed, label)
    for key in allowed:
        _require(key in row, f"{label} missing {key}")
    artifact_id = _string(row["artifactID"], f"{label}.artifactID")
    engine_id = _string(row["engineID"], f"{label}.engineID")
    _require(row["cropLevel"] in CROP_LEVELS, f"{label}.cropLevel is invalid")
    _require(row["splitID"] in SPLITS, f"{label}.splitID is invalid")
    _require(row["status"] in {"missing", "available", "failed"}, f"{label}.status is invalid")
    if row["path"] is not None:
        _string(row["path"], f"{label}.path")
    _sha(row["sha256"], f"{label}.sha256", nullable=True)
    _sha(row["datasetSha256"], f"{label}.datasetSha256", nullable=True)
    _string(row["sourceRevision"], f"{label}.sourceRevision")
    _string(row["license"], f"{label}.license")
    _require(isinstance(row["authorized"], bool), f"{label}.authorized must be boolean")
    _require(isinstance(row["referenceOnly"], bool), f"{label}.referenceOnly must be boolean")
    _nonnegative_int(row["predictionCount"], f"{label}.predictionCount")
    if row["status"] == "available":
        _require(row["path"] is not None and row["sha256"] is not None, f"{label} available row needs path and SHA-256")
        _require(row["datasetSha256"] is not None, f"{label} available row needs dataset SHA-256")
        _require(row["authorized"], f"{label} available row must be authorized")
        _require(row["predictionCount"] > 0, f"{label} available row is empty")
    else:
        _require(not row["authorized"], f"{label} unavailable row cannot be authorized")
    return engine_id, row["cropLevel"], row["splitID"]


def _validate_prediction_matrix(matrix: Any) -> tuple[set[tuple[str, str, str]], set[tuple[str, str, str]]]:
    _require(isinstance(matrix, dict), "predictionMatrix must be an object")
    _reject_unknown(matrix, {"status", "requiredRows", "rows"}, "predictionMatrix")
    for key in ("status", "requiredRows", "rows"):
        _require(key in matrix, f"predictionMatrix missing {key}")
    _require(matrix["status"] in {"missing", "available", "failed"}, "predictionMatrix.status is invalid")
    _require(isinstance(matrix["requiredRows"], list) and matrix["requiredRows"], "predictionMatrix.requiredRows must be non-empty")
    _require(isinstance(matrix["rows"], list), "predictionMatrix.rows must be an array")
    required_keys: set[tuple[str, str, str]] = set()
    for index, row in enumerate(matrix["requiredRows"]):
        key = _validate_matrix_row(row, f"predictionMatrix.requiredRows[{index}]")
        _require(key not in required_keys, f"duplicate required prediction row: {key}")
        required_keys.add(key)
    actual_keys: set[tuple[str, str, str]] = set()
    for index, row in enumerate(matrix["rows"]):
        key = _validate_matrix_row(row, f"predictionMatrix.rows[{index}]")
        _require(key not in actual_keys, f"duplicate prediction row: {key}")
        _require(key in required_keys, f"unexpected prediction row: {key}")
        actual_keys.add(key)
    return required_keys, actual_keys


def _validate_holdout_policy(policy: Any) -> None:
    _require(isinstance(policy, dict), "holdoutPolicy must be an object")
    allowed = {
        "status", "splitIsolation", "datasetFrozen", "policyFrozenBeforeHoldout", "holdoutEvaluatedOnce",
        "holdoutTunedAfterEvaluation", "holdoutUsedForProductSelection", "groundTruthUsedForDecision", "protocolSha256",
    }
    _reject_unknown(policy, allowed, "holdoutPolicy")
    for key in allowed:
        _require(key in policy, f"holdoutPolicy missing {key}")
    _require(policy["status"] in {"missing", "verified", "failed"}, "holdoutPolicy.status is invalid")
    _require(policy["splitIsolation"] in {"missing", "verified", "failed"}, "holdoutPolicy.splitIsolation is invalid")
    for key in ("datasetFrozen", "policyFrozenBeforeHoldout", "holdoutEvaluatedOnce", "holdoutUsedForProductSelection", "groundTruthUsedForDecision"):
        _require(isinstance(policy[key], bool), f"holdoutPolicy.{key} must be boolean")
    _require(policy["holdoutTunedAfterEvaluation"] is False, "holdoutTunedAfterEvaluation must remain false")
    _sha(policy["protocolSha256"], "holdoutPolicy.protocolSha256", nullable=True)
    if policy["status"] == "verified":
        _require(policy["splitIsolation"] == "verified", "verified holdout policy needs verified split isolation")
        _require(policy["datasetFrozen"] and policy["policyFrozenBeforeHoldout"], "verified holdout policy must be frozen")
        _require(policy["protocolSha256"] is not None, "verified holdout policy needs protocol SHA-256")
        _require(not policy["holdoutEvaluatedOnce"], "readiness gate must precede the one-time holdout")


def _validate_promotion(promotion: Any) -> None:
    _require(isinstance(promotion, dict), "promotion must be an object")
    allowed = {"status", "productPathEnabled", "productSelectionChanged", "groundTruthUsedForDecision", "reasons", "requiredEvidence"}
    _reject_unknown(promotion, allowed, "promotion")
    for key in allowed:
        _require(key in promotion, f"promotion missing {key}")
    _require(promotion["status"] in {"blocked", "readyForHoldout"}, "promotion.status is invalid")
    for key in ("productPathEnabled", "productSelectionChanged", "groundTruthUsedForDecision"):
        _require(promotion[key] is False, f"promotion.{key} must remain false")
    for key in ("reasons", "requiredEvidence"):
        _require(isinstance(promotion[key], list) and promotion[key], f"promotion.{key} must be non-empty")
        for index, value in enumerate(promotion[key]):
            _string(value, f"promotion.{key}[{index}]")


def validate_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    _require(isinstance(manifest, dict), "corpus readiness manifest must be an object")
    allowed = {
        "schemaVersion", "benchmark", "contractExampleOnly", "manifestSha256", "run", "dataset", "splits",
        "annotationProfile", "predictionMatrix", "holdoutPolicy", "promotion",
    }
    _reject_unknown(manifest, allowed, "manifest")
    for key in allowed:
        _require(key in manifest, f"manifest missing {key}")
    _require(manifest["schemaVersion"] == SCHEMA_VERSION, "manifest.schemaVersion is invalid")
    _require(manifest["benchmark"] == BENCHMARK, "manifest.benchmark is invalid")
    _require(isinstance(manifest["contractExampleOnly"], bool), "manifest.contractExampleOnly must be boolean")
    _sha(manifest["manifestSha256"], "manifest.manifestSha256")
    _require(manifest["manifestSha256"] == manifest_sha256(manifest), "manifest SHA mismatch")
    _validate_run(manifest["run"])
    _validate_dataset(manifest["dataset"])
    splits = _validate_splits(manifest["splits"])
    _validate_annotation_profile(manifest["annotationProfile"])
    required_rows, actual_rows = _validate_prediction_matrix(manifest["predictionMatrix"])
    _validate_holdout_policy(manifest["holdoutPolicy"])
    _validate_promotion(manifest["promotion"])
    return {"splits": splits, "requiredRows": required_rows, "actualRows": actual_rows}


def evaluate_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    validated = validate_manifest(manifest)
    reasons: list[str] = []
    dataset = manifest["dataset"]
    profile = manifest["annotationProfile"]
    if manifest["contractExampleOnly"]:
        reasons.append("contract-only example")
    if dataset["status"] != "available" or not dataset["authorized"]:
        reasons.append("authorized shared corpus is not available")
    if dataset["pageCount"] < profile["minimumFullPages"]:
        reasons.append("shared corpus has fewer than the required complete pages")
    if dataset["annotatedRegionCount"] < profile["minimumAnnotatedRegions"]:
        reasons.append("shared corpus has fewer than the required annotated TextRegions")

    splits = validated["splits"]
    for split_id in SPLITS:
        split = splits[split_id]
        if split["status"] != "available":
            reasons.append(f"{split_id} split is {split['status']}")
        if split["annotationStatus"] != "complete":
            reasons.append(f"{split_id} annotations are {split['annotationStatus']}")
        if split["groundTruthStatus"] != "available":
            reasons.append(f"{split_id} ground truth is {split['groundTruthStatus']}")

    matrix = manifest["predictionMatrix"]
    if matrix["status"] != "available":
        reasons.append(f"prediction matrix is {matrix['status']}")
    if validated["actualRows"] != validated["requiredRows"]:
        reasons.append("oracle/detected/full prediction matrix is incomplete")
    for row in matrix["rows"]:
        if row["datasetSha256"] != dataset["sha256"]:
            reasons.append(f"prediction row {row['artifactID']} is tied to a different dataset SHA")

    policy = manifest["holdoutPolicy"]
    if policy["status"] != "verified":
        reasons.append(f"holdout policy is {policy['status']}")
    if policy["splitIsolation"] != "verified":
        reasons.append(f"split isolation is {policy['splitIsolation']}")
    if not policy["datasetFrozen"] or not policy["policyFrozenBeforeHoldout"]:
        reasons.append("dataset and policy are not frozen before holdout")
    if policy["holdoutEvaluatedOnce"]:
        reasons.append("holdout has already been evaluated; create a new frozen protocol")
    if policy["holdoutTunedAfterEvaluation"]:
        reasons.append("holdout tuning after evaluation is forbidden")

    unique_reasons = list(dict.fromkeys(reasons))
    status = "readyForHoldout" if not unique_reasons else "blocked"
    expected_promotion = "readyForHoldout" if status == "readyForHoldout" else "blocked"
    _require(manifest["promotion"]["status"] == expected_promotion, "promotion.status does not match evaluated status")
    return {
        "schemaVersion": SCHEMA_VERSION,
        "benchmark": BENCHMARK,
        "manifestSha256": manifest["manifestSha256"],
        "status": status,
        "datasetStatus": dataset["status"],
        "splitIsolationStatus": policy["splitIsolation"],
        "annotationStatus": "complete" if dataset["annotatedRegionCount"] >= profile["minimumAnnotatedRegions"] else "partial",
        "predictionMatrixStatus": matrix["status"],
        "holdoutPolicyStatus": policy["status"],
        "productPathEnabled": False,
        "productSelectionChanged": False,
        "groundTruthUsedForDecision": False,
        "reasons": unique_reasons,
        "requiredEvidence": manifest["promotion"]["requiredEvidence"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = evaluate_manifest(load_json(args.manifest))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except CorpusReadinessError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
