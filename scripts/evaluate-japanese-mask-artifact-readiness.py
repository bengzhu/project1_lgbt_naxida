#!/usr/bin/env python3
"""Evaluate the v3.291+ BubbleMask/SegmentMask readiness envelope.

This evaluator is deliberately fail-closed and model-agnostic.  It validates
artifact identity, license/distribution boundaries, authorized corpus status,
and real target-device evidence.  It never loads a model, reads the App mask
proxy, changes renderer selection, or enables a product mask path.
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
BENCHMARK = "japanese-render-mask-artifacts"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
ROLES = ("BubbleMask", "SegmentMask")
ROOT = Path(__file__).resolve().parents[1]


class MaskArtifactReadinessError(ValueError):
    """Raised for malformed or unsafe readiness evidence."""


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def json_sha256(value: Any) -> str:
    return hashlib.sha256(canonical_json(value)).hexdigest()


def manifest_sha256(manifest: dict[str, Any]) -> str:
    payload = copy.deepcopy(manifest)
    payload["manifestSha256"] = None
    return json_sha256(payload)


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise MaskArtifactReadinessError(f"cannot read JSON {path}: {error}") from error


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise MaskArtifactReadinessError(message)


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


def _finite_nonnegative(value: Any, label: str) -> float:
    _require(isinstance(value, (int, float)) and not isinstance(value, bool), f"{label} must be numeric")
    number = float(value)
    _require(math.isfinite(number) and number >= 0, f"{label} must be finite and non-negative")
    return number


def _validate_run(run: Any) -> None:
    _require(isinstance(run, dict), "run must be an object")
    _reject_unknown(run, {"appSha", "evaluatorVersion", "invocationMode"}, "run")
    _require(bool(HEX40.fullmatch(run.get("appSha", ""))), "run.appSha is invalid")
    _string(run.get("evaluatorVersion"), "run.evaluatorVersion")
    _require(run.get("invocationMode") == "cloud-only-shadow", "run.invocationMode must be cloud-only-shadow")


def _validate_corpus(corpus: Any) -> None:
    _require(isinstance(corpus, dict), "evaluationCorpus must be an object")
    _reject_unknown(corpus, {"status", "path", "sha256", "license", "authorized", "permittedUses"}, "evaluationCorpus")
    for key in ("status", "path", "sha256", "license", "authorized", "permittedUses"):
        _require(key in corpus, f"evaluationCorpus missing {key}")
    _require(corpus["status"] in {"missing", "available", "failed"}, "evaluationCorpus.status is invalid")
    if corpus["path"] is not None:
        _string(corpus["path"], "evaluationCorpus.path")
    _sha(corpus["sha256"], "evaluationCorpus.sha256", nullable=True)
    _string(corpus["license"], "evaluationCorpus.license")
    _require(isinstance(corpus["authorized"], bool), "evaluationCorpus.authorized must be boolean")
    _require(isinstance(corpus["permittedUses"], list), "evaluationCorpus.permittedUses must be an array")
    for index, use in enumerate(corpus["permittedUses"]):
        _string(use, f"evaluationCorpus.permittedUses[{index}]")
    if corpus["status"] == "available":
        _require(corpus["path"] is not None and corpus["sha256"] is not None, "available corpus needs path and SHA-256")
        _require(corpus["authorized"], "available corpus must be authorized")
    else:
        _require(not corpus["authorized"], "missing/failed corpus cannot be authorized")


def _validate_artifact(artifact: Any, index: int) -> dict[str, Any]:
    label = f"artifacts[{index}]"
    _require(isinstance(artifact, dict), f"{label} must be an object")
    allowed = {
        "artifactID", "role", "modelID", "modelRevision", "runtimeID", "runtimeRevision",
        "filename", "sha256", "sizeBytes", "quantization", "sourceRevision", "license",
        "licenseReviewed", "distribution", "referenceOnly", "defaultEnabled", "artifactStatus",
    }
    _reject_unknown(artifact, allowed, label)
    for key in allowed:
        _require(key in artifact, f"{label} missing {key}")
    _string(artifact["artifactID"], f"{label}.artifactID")
    _require(artifact["role"] in ROLES, f"{label}.role is invalid")
    for key in ("modelID", "modelRevision", "runtimeID", "runtimeRevision", "sourceRevision", "license"):
        _string(artifact[key], f"{label}.{key}")
    _require(artifact["artifactStatus"] in {"missing", "available", "failed"}, f"{label}.artifactStatus is invalid")
    _require(isinstance(artifact["licenseReviewed"], bool), f"{label}.licenseReviewed must be boolean")
    _require(artifact["distribution"] in {"bundled", "userProvided", "cloudOnlyReference", "notDistributable"}, f"{label}.distribution is invalid")
    _require(isinstance(artifact["referenceOnly"], bool), f"{label}.referenceOnly must be boolean")
    _require(isinstance(artifact["defaultEnabled"], bool), f"{label}.defaultEnabled must be boolean")
    if artifact["artifactStatus"] == "available":
        _string(artifact["filename"], f"{label}.filename")
        _sha(artifact["sha256"], f"{label}.sha256")
        _require(isinstance(artifact["sizeBytes"], int) and not isinstance(artifact["sizeBytes"], bool) and artifact["sizeBytes"] > 0, f"{label}.sizeBytes is invalid")
        _string(artifact["quantization"], f"{label}.quantization")
    else:
        for key in ("filename", "sha256", "sizeBytes", "quantization"):
            _require(artifact[key] is None, f"{label}.{key} must be null for an unavailable artifact")
    if artifact["referenceOnly"]:
        _require(artifact["distribution"] in {"cloudOnlyReference", "notDistributable"}, f"{label}.referenceOnly has unsafe distribution")
    else:
        _require(artifact["distribution"] in {"bundled", "userProvided"}, f"{label}.distributable artifact has unsafe distribution")
    _require(not artifact["defaultEnabled"], f"{label}.defaultEnabled must remain false in readiness preflight")
    return artifact


def _validate_device_evidence(evidence: Any, artifact_ids: set[str]) -> None:
    _require(isinstance(evidence, dict), "targetDeviceEvidence must be an object")
    _reject_unknown(evidence, {"status", "runs"}, "targetDeviceEvidence")
    _require(evidence.get("status") in {"missing", "available", "failed"}, "targetDeviceEvidence.status is invalid")
    runs = evidence.get("runs")
    _require(isinstance(runs, list), "targetDeviceEvidence.runs must be an array")
    seen: set[str] = set()
    for index, run in enumerate(runs):
        label = f"targetDeviceEvidence.runs[{index}]"
        _require(isinstance(run, dict), f"{label} must be an object")
        allowed = {
            "runID", "artifactID", "deviceID", "deviceClass", "platform", "hardware", "os", "runtime",
            "status", "targetDevice", "coldLatencyMs", "warmLatencyMs", "peakMemoryBytes",
            "energyMilliwattHours", "sampleCount", "measurementSource", "failureReason",
        }
        _reject_unknown(run, allowed, label)
        for key in allowed:
            _require(key in run, f"{label} missing {key}")
        run_id = _string(run["runID"], f"{label}.runID")
        _require(run_id not in seen, f"duplicate device runID: {run_id}")
        seen.add(run_id)
        _require(run["artifactID"] in artifact_ids, f"{label}.artifactID is unknown")
        for key in ("deviceID", "deviceClass", "platform", "hardware", "os", "runtime", "measurementSource"):
            _string(run[key], f"{label}.{key}")
        _require(run["status"] in {"missing", "complete", "partial", "failed"}, f"{label}.status is invalid")
        _require(isinstance(run["targetDevice"], bool), f"{label}.targetDevice must be boolean")
        for key in ("coldLatencyMs", "warmLatencyMs"):
            if run[key] is not None:
                _finite_nonnegative(run[key], f"{label}.{key}")
        for key in ("peakMemoryBytes",):
            if run[key] is not None:
                _require(isinstance(run[key], int) and not isinstance(run[key], bool) and run[key] > 0, f"{label}.{key} is invalid")
        if run["energyMilliwattHours"] is not None:
            _finite_nonnegative(run["energyMilliwattHours"], f"{label}.energyMilliwattHours")
        _require(isinstance(run["sampleCount"], int) and not isinstance(run["sampleCount"], bool) and run["sampleCount"] >= 0, f"{label}.sampleCount is invalid")
        if run["status"] == "complete":
            _require(run["targetDevice"], f"{label}.complete run must be a target device")
            _require(run["coldLatencyMs"] is not None and run["warmLatencyMs"] is not None, f"{label}.complete run needs cold/warm latency")
            _require(run["peakMemoryBytes"] is not None and run["energyMilliwattHours"] is not None, f"{label}.complete run needs memory/energy")
            _require(run["sampleCount"] > 0 and run["failureReason"] is None, f"{label}.complete run is inconsistent")
        else:
            _require(isinstance(run["failureReason"], str) and bool(run["failureReason"].strip()), f"{label}.failureReason is required")


def _validate_promotion(promotion: Any) -> None:
    _require(isinstance(promotion, dict), "promotion must be an object")
    _reject_unknown(promotion, {"status", "productPathEnabled", "productSelectionChanged", "groundTruthUsedForDecision", "reasons", "requiredEvidence"}, "promotion")
    _require(promotion.get("status") in {"blocked", "ready"}, "promotion.status is invalid")
    _require(promotion.get("productPathEnabled") is False, "productPathEnabled must remain false")
    _require(promotion.get("productSelectionChanged") is False, "productSelectionChanged must remain false")
    _require(promotion.get("groundTruthUsedForDecision") is False, "groundTruthUsedForDecision must remain false")
    for key in ("reasons", "requiredEvidence"):
        values = promotion.get(key)
        _require(isinstance(values, list) and values, f"promotion.{key} must be non-empty")
        for index, value in enumerate(values):
            _string(value, f"promotion.{key}[{index}]")


def validate_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    _require(isinstance(manifest, dict), "mask artifact manifest must be an object")
    _reject_unknown(
        manifest,
        {"schemaVersion", "benchmark", "contractExampleOnly", "manifestSha256", "run", "evaluationCorpus", "artifacts", "targetDeviceEvidence", "promotion"},
        "manifest",
    )
    _require(manifest.get("schemaVersion") == SCHEMA_VERSION, "manifest.schemaVersion is invalid")
    _require(manifest.get("benchmark") == BENCHMARK, "manifest.benchmark is invalid")
    _require(isinstance(manifest.get("contractExampleOnly"), bool), "manifest.contractExampleOnly must be boolean")
    declared_hash = manifest.get("manifestSha256")
    _sha(declared_hash, "manifest.manifestSha256")
    actual_hash = manifest_sha256(manifest)
    _require(declared_hash == actual_hash, f"manifest SHA mismatch: {actual_hash} != {declared_hash}")
    _validate_run(manifest.get("run"))
    _validate_corpus(manifest.get("evaluationCorpus"))
    artifacts_payload = manifest.get("artifacts")
    _require(isinstance(artifacts_payload, list) and artifacts_payload, "manifest.artifacts must be non-empty")
    artifacts: dict[str, dict[str, Any]] = {}
    roles: set[str] = set()
    for index, artifact in enumerate(artifacts_payload):
        validated = _validate_artifact(artifact, index)
        _require(validated["artifactID"] not in artifacts, f"duplicate artifactID: {validated['artifactID']}")
        _require(validated["role"] not in roles, f"duplicate artifact role: {validated['role']}")
        artifacts[validated["artifactID"]] = validated
        roles.add(validated["role"])
    _require(roles == set(ROLES), "manifest must contain exactly one BubbleMask and one SegmentMask artifact")
    _validate_device_evidence(manifest.get("targetDeviceEvidence"), set(artifacts))
    _validate_promotion(manifest.get("promotion"))
    return {"manifestSha256": declared_hash, "artifacts": artifacts, "roles": roles}


def evaluate_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    validated = validate_manifest(manifest)
    reasons: list[str] = []
    corpus = manifest["evaluationCorpus"]
    if manifest["contractExampleOnly"]:
        reasons.append("contract-only example")
    if corpus["status"] != "available" or not corpus["authorized"]:
        reasons.append("authorized render-quality corpus is not available")

    artifact_status_by_role: dict[str, str] = {}
    for role in ROLES:
        artifact = next(item for item in validated["artifacts"].values() if item["role"] == role)
        artifact_status_by_role[role] = artifact["artifactStatus"]
        if artifact["artifactStatus"] != "available":
            reasons.append(f"{role} artifact is {artifact['artifactStatus']}")
        if not artifact["licenseReviewed"]:
            reasons.append(f"{role} license is not reviewed")
        if artifact["referenceOnly"]:
            reasons.append(f"{role} is reference-only")
        if artifact["distribution"] not in {"bundled", "userProvided"}:
            reasons.append(f"{role} distribution is not product-distributable")

    runs = manifest["targetDeviceEvidence"]["runs"]
    complete_target_artifacts = {
        run["artifactID"]
        for run in runs
        if run["status"] == "complete" and run["targetDevice"]
    }
    for artifact_id in validated["artifacts"]:
        if artifact_id not in complete_target_artifacts:
            reasons.append(f"target-device evidence is missing for {artifact_id}")
    if manifest["targetDeviceEvidence"]["status"] != "available":
        reasons.append("target-device evidence manifest is not available")

    # A readiness report is never permission to alter the product path.  The
    # separate benchmark must still prove the final mask/shaping
    # behavior before any future product integration.
    unique_reasons = list(dict.fromkeys(reasons))
    status = "ready" if not unique_reasons else "blocked"
    _require(
        manifest["promotion"]["status"] == status,
        f"promotion.status does not match evaluated status: {manifest['promotion']['status']} != {status}",
    )
    return {
        "schemaVersion": SCHEMA_VERSION,
        "benchmark": BENCHMARK,
        "manifestSha256": validated["manifestSha256"],
        "status": status,
        "artifactStatusByRole": artifact_status_by_role,
        "targetDeviceEvidenceStatus": manifest["targetDeviceEvidence"]["status"],
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
    except MaskArtifactReadinessError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
