#!/usr/bin/env python3
"""Evaluate the v3.294 shared Japanese corpus and holdout readiness envelope.

The evaluator is intentionally model- and product-path agnostic.  It validates
authorization, dataset identity, annotation coverage, split isolation, the
same-crop prediction matrix, materialized artifact identity, and a pre-holdout
policy freeze.  It never loads an image/model, reads ground truth for a runtime
decision, selects an engine, or enables OCR/translation behavior.
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


SCHEMA_VERSION = "1.1.0"
PREDICTION_SCHEMA_VERSION = "1.0.0"
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
ENGINE_ARTIFACT_PREFIX = {
    "aitrans-bundled-manga-ocr": "aitrans",
    "apple-vision": "vision",
    "koharu-mit48": "mit48",
    "koharu-paddleocr-vl": "paddle",
}
EXPECTED_REFERENCE_ONLY = {
    "aitrans-bundled-manga-ocr": False,
    "apple-vision": True,
    "koharu-mit48": True,
    "koharu-paddleocr-vl": True,
}
CROP_ARTIFACT_SUFFIX = {
    "oracleCrop": "oracle",
    "detectedCrop": "detected",
    "fullPage": "full",
}
EXPECTED_PREDICTION_MATRIX = frozenset(
    (engine, crop_level, "dev")
    for engine in REQUIRED_ENGINES
    for crop_level in CROP_LEVELS
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


def _relative_path(value: Any, label: str, *, nullable: bool = False) -> str | None:
    if nullable and value is None:
        return None
    _require(isinstance(value, str) and value.strip(), f"{label} must be a non-empty relative path")
    _require("\x00" not in value and "\\" not in value, f"{label} contains an unsafe path character")
    path = Path(value)
    _require(not path.is_absolute() and value not in {".", ".."}, f"{label} must be relative")
    _require(".." not in path.parts, f"{label} must not escape the artifact root")
    _require(all(part not in {"", "."} for part in path.parts), f"{label} is not canonical")
    return value


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise CorpusReadinessError(f"cannot read artifact {path}: {error}") from error
    return digest.hexdigest()


def _resolve_regular_file(relative_path: str, label: str, artifact_root: Path | None) -> Path:
    _require(artifact_root is not None, f"{label} requires --artifact-root for intake verification")
    root = artifact_root.resolve()
    _require(root.is_dir(), f"artifact root is not a directory: {root}")
    relative = Path(_relative_path(relative_path, label) or "")
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise CorpusReadinessError(f"{label} resolves outside the artifact root") from error
    cursor = root
    for component in relative.parts:
        cursor /= component
        _require(not cursor.is_symlink(), f"{label} must not use symlinks")
    _require(candidate.is_file() and not candidate.is_symlink(), f"{label} is not a regular file: {relative_path}")
    return candidate


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
        "artifactPath", "artifactSha256", "sourceManifestPath", "sourceManifestSha256",
    }
    _reject_unknown(dataset, allowed, "dataset")
    for key in allowed:
        _require(key in dataset, f"dataset missing {key}")
    _require(dataset["status"] in {"missing", "available", "failed"}, "dataset.status is invalid")
    _string(dataset["datasetID"], "dataset.datasetID")
    _string(dataset["datasetVersion"], "dataset.datasetVersion")
    _sha(dataset["sha256"], "dataset.sha256", nullable=True)
    _relative_path(dataset["artifactPath"], "dataset.artifactPath", nullable=True)
    _sha(dataset["artifactSha256"], "dataset.artifactSha256", nullable=True)
    _relative_path(dataset["sourceManifestPath"], "dataset.sourceManifestPath", nullable=True)
    _sha(dataset["sourceManifestSha256"], "dataset.sourceManifestSha256", nullable=True)
    _nonnegative_int(dataset["pageCount"], "dataset.pageCount")
    _nonnegative_int(dataset["annotatedRegionCount"], "dataset.annotatedRegionCount")
    _string(dataset["license"], "dataset.license")
    _require(isinstance(dataset["authorized"], bool), "dataset.authorized must be boolean")
    _require(isinstance(dataset["permittedUses"], list), "dataset.permittedUses must be an array")
    for index, permitted_use in enumerate(dataset["permittedUses"]):
        _string(permitted_use, f"dataset.permittedUses[{index}]")
    if dataset["status"] == "available":
        _require(dataset["sha256"] is not None, "available dataset needs SHA-256")
        _require(dataset["artifactPath"] is not None, "available dataset needs artifactPath")
        _require(dataset["artifactSha256"] is not None, "available dataset needs artifact SHA-256")
        _require(dataset["authorized"], "available dataset must be authorized")
        _require(dataset["sourceManifestPath"] is not None, "available dataset needs source manifest")
        _require(dataset["sourceManifestSha256"] is not None, "available dataset needs source manifest SHA-256")
    else:
        _require(not dataset["authorized"], "missing/failed dataset cannot be authorized")
        for key in ("sha256", "artifactPath", "artifactSha256", "sourceManifestPath", "sourceManifestSha256"):
            _require(dataset[key] is None, f"unavailable dataset must not carry {key}")


def _validate_splits(splits: Any) -> dict[str, dict[str, Any]]:
    _require(isinstance(splits, list) and len(splits) == len(SPLITS), "splits must contain exactly train/dev/holdout")
    by_id: dict[str, dict[str, Any]] = {}
    all_assets: set[str] = set()
    all_regions: set[str] = set()
    for index, split in enumerate(splits):
        label = f"splits[{index}]"
        _require(isinstance(split, dict), f"{label} must be an object")
        allowed = {
            "splitID", "status", "pageCount", "regionCount", "assetIDs", "regionIDs",
            "annotationStatus", "groundTruthStatus",
        }
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
        _require(isinstance(split["regionIDs"], list), f"{label}.regionIDs must be an array")
        local_assets: set[str] = set()
        for asset_index, asset_id in enumerate(split["assetIDs"]):
            asset = _string(asset_id, f"{label}.assetIDs[{asset_index}]")
            _require(asset not in local_assets, f"duplicate asset ID in {split_id}: {asset}")
            _require(asset not in all_assets, f"asset ID crosses split boundary: {asset}")
            local_assets.add(asset)
            all_assets.add(asset)
        local_regions: set[str] = set()
        for region_index, region_id in enumerate(split["regionIDs"]):
            region = _string(region_id, f"{label}.regionIDs[{region_index}]")
            _require(region not in local_regions, f"duplicate region ID in {split_id}: {region}")
            _require(region not in all_regions, f"region ID crosses split boundary: {region}")
            local_regions.add(region)
            all_regions.add(region)
        _require(split["annotationStatus"] in {"missing", "partial", "complete"}, f"{label}.annotationStatus is invalid")
        _require(split["groundTruthStatus"] in {"missing", "available", "failed"}, f"{label}.groundTruthStatus is invalid")
        if split["status"] == "available":
            _require(split["pageCount"] > 0 and local_assets, f"{label} available split is empty")
            _require(
                split["pageCount"] == len(local_assets),
                f"{label} pageCount does not match its page asset IDs",
            )
            _require(
                split["regionCount"] == len(local_regions),
                f"{label} regionCount does not match its region IDs",
            )
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
    _require(engine_id in ENGINE_ARTIFACT_PREFIX, f"{label}.engineID is not a required engine")
    _require(row["cropLevel"] in CROP_LEVELS, f"{label}.cropLevel is invalid")
    _require(row["splitID"] in SPLITS, f"{label}.splitID is invalid")
    _require(row["splitID"] == "dev", f"{label}.splitID must be dev before one-time holdout")
    expected_artifact_id = f"{ENGINE_ARTIFACT_PREFIX[engine_id]}-{CROP_ARTIFACT_SUFFIX[row['cropLevel']]}"
    _require(artifact_id == expected_artifact_id, f"{label}.artifactID is not canonical for its engine/crop")
    _require(row["status"] in {"missing", "available", "failed"}, f"{label}.status is invalid")
    if row["path"] is not None:
        _relative_path(row["path"], f"{label}.path")
    _sha(row["sha256"], f"{label}.sha256", nullable=True)
    _sha(row["datasetSha256"], f"{label}.datasetSha256", nullable=True)
    _string(row["sourceRevision"], f"{label}.sourceRevision")
    _string(row["license"], f"{label}.license")
    _require(isinstance(row["authorized"], bool), f"{label}.authorized must be boolean")
    _require(isinstance(row["referenceOnly"], bool), f"{label}.referenceOnly must be boolean")
    _require(
        row["referenceOnly"] == EXPECTED_REFERENCE_ONLY[engine_id],
        f"{label}.referenceOnly does not match its engine",
    )
    _nonnegative_int(row["predictionCount"], f"{label}.predictionCount")
    if row["status"] == "available":
        _require(row["path"] is not None and row["sha256"] is not None, f"{label} available row needs path and SHA-256")
        _require(row["datasetSha256"] is not None, f"{label} available row needs dataset SHA-256")
        _require(row["authorized"], f"{label} available row must be authorized")
        _require(row["predictionCount"] > 0, f"{label} available row is empty")
    else:
        _require(not row["authorized"], f"{label} unavailable row cannot be authorized")
        for key in ("path", "sha256", "datasetSha256"):
            _require(row[key] is None, f"{label} unavailable row must not carry {key}")
        _require(row["predictionCount"] == 0, f"{label} unavailable row must have predictionCount 0")
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
    _require(
        required_keys == set(EXPECTED_PREDICTION_MATRIX),
        "predictionMatrix.requiredRows must contain the canonical four-engine dev matrix",
    )
    return required_keys, actual_keys


def _validate_prediction_artifact(
    row: dict[str, Any],
    artifact_path: Path,
    dataset_sha256: str,
    dev_split: dict[str, Any],
) -> None:
    payload = load_json(artifact_path)
    _require(isinstance(payload, dict), f"{row['artifactID']} artifact must be an object")
    _reject_unknown(payload, {"schemaVersion", "benchmark", "datasetSha256", "run", "predictions"}, f"{row['artifactID']} artifact")
    for key in ("schemaVersion", "benchmark", "datasetSha256", "run", "predictions"):
        _require(key in payload, f"{row['artifactID']} artifact missing {key}")
    _require(payload["schemaVersion"] == PREDICTION_SCHEMA_VERSION, f"{row['artifactID']} artifact schemaVersion is invalid")
    _require(payload["benchmark"] == "japanese-ocr", f"{row['artifactID']} artifact benchmark is invalid")
    _require(payload["datasetSha256"] == dataset_sha256, f"{row['artifactID']} artifact dataset SHA does not match the manifest")

    run = payload["run"]
    _require(isinstance(run, dict), f"{row['artifactID']} artifact run must be an object")
    _reject_unknown(
        run,
        {"appSha", "engineID", "engineVersion", "model", "license", "device", "parameters"},
        f"{row['artifactID']} artifact run",
    )
    for key in ("appSha", "engineID", "engineVersion", "model", "license", "device", "parameters"):
        _require(key in run, f"{row['artifactID']} artifact run missing {key}")
    _require(bool(HEX40.fullmatch(run["appSha"])), f"{row['artifactID']} artifact run.appSha is invalid")
    _require(run["engineID"] == row["engineID"], f"{row['artifactID']} artifact engineID does not match the matrix row")
    _string(run["engineVersion"], f"{row['artifactID']} artifact run.engineVersion")
    _string(run["license"], f"{row['artifactID']} artifact run.license")
    _string(run["device"], f"{row['artifactID']} artifact run.device")
    _require(isinstance(run["model"], dict), f"{row['artifactID']} artifact run.model must be an object")
    _require(isinstance(run["parameters"], dict), f"{row['artifactID']} artifact run.parameters must be an object")

    predictions = payload["predictions"]
    _require(isinstance(predictions, list), f"{row['artifactID']} artifact predictions must be an array")
    _require(
        len(predictions) == row["predictionCount"],
        f"{row['artifactID']} predictionCount does not match the artifact payload",
    )
    expected_pages = set(dev_split["assetIDs"])
    expected_regions = set(dev_split["regionIDs"])
    seen_pages: set[str] = set()
    seen_regions: set[str] = set()
    seen_prediction_ids: set[str] = set()
    prediction_keys = {
        "predictionID", "pageID", "split", "evaluationLevel", "regionID", "lineID", "status", "text",
        "rawText", "confidence", "bbox", "polygon", "writingDirection", "readingOrder", "engine",
        "cropVariant", "referenceOnly", "failureReason",
    }
    for index, prediction in enumerate(predictions):
        label = f"{row['artifactID']} artifact predictions[{index}]"
        _require(isinstance(prediction, dict), f"{label} must be an object")
        _reject_unknown(prediction, prediction_keys, label)
        for key in prediction_keys:
            _require(key in prediction, f"{label} missing {key}")
        prediction_id = _string(prediction["predictionID"], f"{label}.predictionID")
        _require(prediction_id not in seen_prediction_ids, f"duplicate predictionID in {row['artifactID']}: {prediction_id}")
        seen_prediction_ids.add(prediction_id)
        page_id = _string(prediction["pageID"], f"{label}.pageID")
        _require(page_id in expected_pages, f"{label}.pageID is outside the dev split")
        _require(prediction["split"] == row["splitID"], f"{label}.split does not match the matrix row")
        _require(prediction["evaluationLevel"] == row["cropLevel"], f"{label}.evaluationLevel does not match the matrix row")
        _require(prediction["engine"] == row["engineID"], f"{label}.engine does not match the matrix row")
        _require(prediction["referenceOnly"] == row["referenceOnly"], f"{label}.referenceOnly does not match the matrix row")
        _require(prediction["status"] in {"success", "empty", "failure"}, f"{label}.status is invalid")
        _require(isinstance(prediction["text"], str), f"{label}.text must be a string")
        seen_pages.add(page_id)
        region_id = prediction["regionID"]
        if row["cropLevel"] == "oracleCrop":
            _require(isinstance(region_id, str) and region_id, f"{label}.regionID is required for oracleCrop")
            _require(region_id in expected_regions, f"{label}.regionID is outside the dev annotations")
            seen_regions.add(region_id)
        else:
            _require(region_id is None, f"{label}.regionID must be null for detected/full predictions")
    _require(seen_pages == expected_pages, f"{row['artifactID']} artifact does not cover every dev page")
    if row["cropLevel"] == "oracleCrop":
        _require(seen_regions == expected_regions, f"{row['artifactID']} artifact does not cover every dev region")


def _validate_artifact_intake(
    manifest: dict[str, Any],
    splits: dict[str, dict[str, Any]],
    artifact_root: Path | None,
) -> str:
    dataset = manifest["dataset"]
    available_rows = [
        row for row in manifest["predictionMatrix"]["rows"]
        if row["status"] == "available"
    ]
    requires_intake = dataset["status"] == "available" or bool(available_rows)
    if not requires_intake:
        return "notRequired"

    _require(artifact_root is not None, "available evidence requires --artifact-root for intake verification")
    if dataset["status"] == "available":
        dataset_artifact = _resolve_regular_file(dataset["artifactPath"], "dataset.artifactPath", artifact_root)
        _require(
            _sha256_file(dataset_artifact) == dataset["artifactSha256"],
            "dataset artifact SHA-256 does not match dataset.artifactSha256",
        )
        source_manifest = _resolve_regular_file(dataset["sourceManifestPath"], "dataset.sourceManifestPath", artifact_root)
        _require(
            _sha256_file(source_manifest) == dataset["sourceManifestSha256"],
            "dataset source manifest SHA-256 does not match dataset.sourceManifestSha256",
        )

    dev_split = splits["dev"]
    seen_prediction_paths: set[Path] = set()
    for row in available_rows:
        _require(row["datasetSha256"] == dataset["sha256"], f"{row['artifactID']} is tied to a different dataset SHA")
        prediction_artifact = _resolve_regular_file(row["path"], f"predictionMatrix.{row['artifactID']}.path", artifact_root)
        _require(prediction_artifact not in seen_prediction_paths, f"prediction artifact path is reused: {row['path']}")
        seen_prediction_paths.add(prediction_artifact)
        _require(
            _sha256_file(prediction_artifact) == row["sha256"],
            f"{row['artifactID']} artifact SHA-256 does not match the matrix row",
        )
        _validate_prediction_artifact(row, prediction_artifact, dataset["sha256"], dev_split)
    return "verified"


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
    _require(policy["holdoutUsedForProductSelection"] is False, "holdoutUsedForProductSelection must remain false")
    _require(policy["groundTruthUsedForDecision"] is False, "holdoutPolicy.groundTruthUsedForDecision must remain false")
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


def validate_manifest(manifest: dict[str, Any], artifact_root: Path | None = None) -> dict[str, Any]:
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
    artifact_intake_status = _validate_artifact_intake(manifest, splits, artifact_root)
    return {
        "splits": splits,
        "requiredRows": required_rows,
        "actualRows": actual_rows,
        "artifactIntakeStatus": artifact_intake_status,
    }


def evaluate_manifest(manifest: dict[str, Any], artifact_root: Path | None = None) -> dict[str, Any]:
    validated = validate_manifest(manifest, artifact_root)
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
        for missing_key in sorted(validated["requiredRows"] - validated["actualRows"]):
            reasons.append(f"prediction row is missing: {missing_key[0]}/{missing_key[1]}/{missing_key[2]}")
    for row in matrix["rows"]:
        if row["status"] != "available":
            reasons.append(f"prediction row {row['artifactID']} is {row['status']}")
        elif row["datasetSha256"] != dataset["sha256"]:
            reasons.append(f"prediction row {row['artifactID']} is tied to a different dataset SHA")

    if dataset["status"] == "available":
        total_pages = sum(split["pageCount"] for split in splits.values())
        total_regions = sum(split["regionCount"] for split in splits.values())
        if total_pages != dataset["pageCount"]:
            reasons.append("split page counts do not cover the dataset page count")
        if total_regions != dataset["annotatedRegionCount"]:
            reasons.append("split region counts do not cover the dataset annotation count")

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
        "artifactIntakeStatus": validated["artifactIntakeStatus"],
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
    parser.add_argument("--artifact-root", type=Path, default=None)
    args = parser.parse_args()
    try:
        report = evaluate_manifest(load_json(args.manifest), args.artifact_root)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except CorpusReadinessError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
