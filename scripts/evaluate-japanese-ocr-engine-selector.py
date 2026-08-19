#!/usr/bin/env python3
"""Evaluate a GT-isolated OCR candidate selector in shadow mode.

The selector deliberately consumes only runtime capability and output signals.
Benchmark ground truth, expected region counts, benchmark filenames, and raw
cross-engine confidence are not part of the runtime input contract.  The
evidence gate is reported separately and cannot change a per-block decision.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
import sys
from typing import Any


SCHEMA_VERSION = "1.0.0"
BENCHMARK = "japanese-ocr-engine-selector"
HEX40 = re.compile(r"^[0-9a-f]{40}$")

ALLOWED_CROP_ROLES = {"detectorBBox", "lineQuadFallback", "blockCrop"}
ALLOWED_RUNTIME_SIGNALS = [
    "artifactStatus",
    "licenseReviewed",
    "supportsCropRoles",
    "outputStatus",
    "textNonEmpty",
    "calibratedQuality",
    "calibrationProfileID",
    "warmLatencyMs",
    "peakMemoryBytes",
    "geometryValid",
    "duplicateRisk",
    "cancellationState",
    "generationMatches",
    "requestBudgetRemaining",
    "pixelBudgetRemaining",
    "candidateFailureCount",
]


class EngineSelectorError(ValueError):
    """Raised for an unsafe, incomplete, or ambiguous selector envelope."""


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EngineSelectorError(f"cannot read JSON {path}: {error}") from error


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise EngineSelectorError(message)


def _reject_unknown(value: dict[str, Any], allowed: set[str], label: str) -> None:
    unknown = sorted(set(value) - allowed)
    _require(not unknown, f"{label} has unknown fields: {unknown}")


def _string(value: Any, label: str) -> str:
    _require(isinstance(value, str) and value.strip(), f"{label} must be a non-empty string")
    return value


def _finite(value: Any, label: str, *, minimum: float | None = None, maximum: float | None = None) -> float:
    _require(isinstance(value, (int, float)) and not isinstance(value, bool), f"{label} must be numeric")
    number = float(value)
    _require(math.isfinite(number), f"{label} must be finite")
    if minimum is not None:
        _require(number >= minimum, f"{label} is below {minimum}")
    if maximum is not None:
        _require(number <= maximum, f"{label} is above {maximum}")
    return number


def _validate_run(run: Any) -> None:
    _require(isinstance(run, dict), "run must be an object")
    _reject_unknown(run, {"appSha", "evaluatorVersion", "invocationMode"}, "run")
    _require(bool(HEX40.fullmatch(run.get("appSha", ""))), "run.appSha must be a 40-digit lowercase SHA")
    _string(run.get("evaluatorVersion"), "run.evaluatorVersion")
    _require(run.get("invocationMode") == "cloud-only-shadow", "run.invocationMode must be cloud-only-shadow")


def _validate_policy(policy: Any) -> None:
    _require(isinstance(policy, dict), "policy must be an object")
    allowed = {
        "policyID", "policyVersion", "selectorMode", "featureFlag", "featureFlagEnabled",
        "baselineEngineID", "candidateEngineID", "candidateMinCalibratedQuality",
        "candidateCalibrationProfileID", "candidateMaxWarmLatencyMs", "candidateMaxPeakMemoryBytes",
        "rollbackFailureThreshold", "thresholdsFrozen", "freezeSource", "groundTruthUsedForSelection",
        "benchmarkInputAvailable", "requestBudgetDelta", "pixelBudgetDelta", "storeProvenance",
        "preserveReviewStateOnRollback",
    }
    _reject_unknown(policy, allowed, "policy")
    for key in allowed:
        _require(key in policy, f"policy missing {key}")
    _string(policy["policyID"], "policy.policyID")
    _string(policy["policyVersion"], "policy.policyVersion")
    _require(policy["selectorMode"] in {"shadow-only", "controlled-rollout"}, "policy.selectorMode is invalid")
    _string(policy["featureFlag"], "policy.featureFlag")
    _require(isinstance(policy["featureFlagEnabled"], bool), "policy.featureFlagEnabled must be boolean")
    _string(policy["baselineEngineID"], "policy.baselineEngineID")
    _string(policy["candidateEngineID"], "policy.candidateEngineID")
    _require(policy["baselineEngineID"] != policy["candidateEngineID"], "baseline and candidate engine IDs must differ")
    _finite(policy["candidateMinCalibratedQuality"], "policy.candidateMinCalibratedQuality", minimum=0, maximum=1)
    _string(policy["candidateCalibrationProfileID"], "policy.candidateCalibrationProfileID")
    _finite(policy["candidateMaxWarmLatencyMs"], "policy.candidateMaxWarmLatencyMs", minimum=0.000001)
    _require(
        isinstance(policy["candidateMaxPeakMemoryBytes"], int)
        and not isinstance(policy["candidateMaxPeakMemoryBytes"], bool)
        and policy["candidateMaxPeakMemoryBytes"] > 0,
        "policy.candidateMaxPeakMemoryBytes is invalid",
    )
    _require(
        isinstance(policy["rollbackFailureThreshold"], int)
        and not isinstance(policy["rollbackFailureThreshold"], bool)
        and policy["rollbackFailureThreshold"] >= 1,
        "policy.rollbackFailureThreshold is invalid",
    )
    _require(policy["thresholdsFrozen"] is True, "policy thresholds must be frozen")
    _require(policy["freezeSource"] == "train-dev", "policy.freezeSource must be train-dev")
    _require(policy["groundTruthUsedForSelection"] is False, "ground truth cannot be used for selection")
    _require(policy["benchmarkInputAvailable"] is False, "benchmark input cannot be available to selector")
    _require(policy["requestBudgetDelta"] == 0, "selector cannot change request budget")
    _require(policy["pixelBudgetDelta"] == 0, "selector cannot change pixel budget")
    _require(policy["storeProvenance"] is True, "selector must store selection provenance")
    _require(policy["preserveReviewStateOnRollback"] is True, "rollback must preserve review state")
    if policy["selectorMode"] == "shadow-only":
        _require(policy["featureFlagEnabled"] is False, "shadow-only selector cannot enable the feature flag")


def _validate_evidence_gate(evidence: Any, contract_example_only: bool) -> None:
    _require(isinstance(evidence, dict), "evidenceGate must be an object")
    allowed = {
        "status", "candidateArtifactReady", "authorizedCorpusReady", "policyFrozenBeforeHoldout",
        "holdoutEvaluatedOnce", "holdoutTunedAfterEvaluation", "outputMetricsPassed",
        "duplicateOmissionOrderPassed", "cancellationPassed", "memoryPassed", "rollbackVerified", "reason",
    }
    _reject_unknown(evidence, allowed, "evidenceGate")
    for key in allowed:
        _require(key in evidence, f"evidenceGate missing {key}")
    _require(evidence["status"] in {"contractExampleOnly", "missing", "ready"}, "evidenceGate.status is invalid")
    for key in (
        "candidateArtifactReady", "authorizedCorpusReady", "policyFrozenBeforeHoldout", "holdoutEvaluatedOnce",
        "outputMetricsPassed", "duplicateOmissionOrderPassed", "cancellationPassed", "memoryPassed", "rollbackVerified",
    ):
        _require(isinstance(evidence[key], bool), f"evidenceGate.{key} must be boolean")
    _require(evidence["holdoutTunedAfterEvaluation"] is False, "holdout cannot tune a frozen policy")
    _string(evidence["reason"], "evidenceGate.reason")
    if contract_example_only:
        _require(evidence["status"] == "contractExampleOnly", "contract example must use contractExampleOnly evidence status")
    if evidence["status"] == "ready":
        for key in (
            "candidateArtifactReady", "authorizedCorpusReady", "policyFrozenBeforeHoldout", "holdoutEvaluatedOnce",
            "outputMetricsPassed", "duplicateOmissionOrderPassed", "cancellationPassed", "memoryPassed", "rollbackVerified",
        ):
            _require(evidence[key] is True, f"ready evidence requires {key}")


def _validate_engine_signal(signal: Any, label: str) -> None:
    _require(isinstance(signal, dict), f"{label} must be an object")
    allowed = {
        "engineID", "candidateRole", "artifactStatus", "licenseReviewed", "supportsCropRoles",
        "outputStatus", "text", "calibratedQuality", "calibrationProfileID", "warmLatencyMs",
        "peakMemoryBytes", "failureReason",
    }
    _reject_unknown(signal, allowed, label)
    for key in allowed:
        _require(key in signal, f"{label} missing {key}")
    _string(signal["engineID"], f"{label}.engineID")
    _require(signal["candidateRole"] in {"baseline", "candidate"}, f"{label}.candidateRole is invalid")
    _require(signal["artifactStatus"] in {"available", "missing", "failed"}, f"{label}.artifactStatus is invalid")
    _require(isinstance(signal["licenseReviewed"], bool), f"{label}.licenseReviewed must be boolean")
    _require(isinstance(signal["supportsCropRoles"], list), f"{label}.supportsCropRoles must be an array")
    _require(all(isinstance(role, str) for role in signal["supportsCropRoles"]), f"{label}.supportsCropRoles must contain strings")
    _require(len(signal["supportsCropRoles"]) == len(set(signal["supportsCropRoles"])), f"{label}.supportsCropRoles has duplicates")
    _require(set(signal["supportsCropRoles"]).issubset(ALLOWED_CROP_ROLES), f"{label}.supportsCropRoles has an invalid crop role")
    _require(signal["outputStatus"] in {"success", "empty", "failure"}, f"{label}.outputStatus is invalid")
    _require(isinstance(signal["text"], str), f"{label}.text must be a string")
    if signal["outputStatus"] == "success":
        _require(signal["text"].strip(), f"{label}.success output must be non-empty")
        _require(signal["failureReason"] is None, f"{label}.success cannot carry failureReason")
    else:
        _string(signal["failureReason"], f"{label}.failureReason")
    quality = signal["calibratedQuality"]
    if quality is None:
        _require(signal["calibrationProfileID"] is None, f"{label}.missing calibrated quality cannot carry a profile")
    else:
        _finite(quality, f"{label}.calibratedQuality", minimum=0, maximum=1)
        _string(signal["calibrationProfileID"], f"{label}.calibrationProfileID")
    if signal["warmLatencyMs"] is not None:
        _finite(signal["warmLatencyMs"], f"{label}.warmLatencyMs", minimum=0.000001)
    if signal["peakMemoryBytes"] is not None:
        _require(
            isinstance(signal["peakMemoryBytes"], int)
            and not isinstance(signal["peakMemoryBytes"], bool)
            and signal["peakMemoryBytes"] > 0,
            f"{label}.peakMemoryBytes is invalid",
        )


def _validate_runtime_case(case: Any, index: int, policy: dict[str, Any]) -> None:
    label = f"runtimeCases[{index}]"
    _require(isinstance(case, dict), f"{label} must be an object")
    allowed = {
        "caseID", "blockID", "cropRole", "geometryValid", "duplicateRisk", "requestBudgetRemaining",
        "pixelBudgetRemaining", "cancellationState", "generationMatches", "candidateFailureCount",
        "previousEngineID", "engines",
    }
    _reject_unknown(case, allowed, label)
    for key in allowed:
        _require(key in case, f"{label} missing {key}")
    _string(case["caseID"], f"{label}.caseID")
    _string(case["blockID"], f"{label}.blockID")
    _require(case["cropRole"] in ALLOWED_CROP_ROLES, f"{label}.cropRole is invalid")
    for key in ("geometryValid", "duplicateRisk", "generationMatches"):
        _require(isinstance(case[key], bool), f"{label}.{key} must be boolean")
    for key in ("requestBudgetRemaining", "pixelBudgetRemaining", "candidateFailureCount"):
        _require(isinstance(case[key], int) and not isinstance(case[key], bool) and case[key] >= 0, f"{label}.{key} is invalid")
    _require(case["cancellationState"] in {"active", "cancelRequested", "cancelled"}, f"{label}.cancellationState is invalid")
    if case["previousEngineID"] is not None:
        _string(case["previousEngineID"], f"{label}.previousEngineID")
    engines = case["engines"]
    _require(isinstance(engines, list) and len(engines) == 2, f"{label}.engines must contain exactly baseline and candidate")
    ids: set[str] = set()
    roles: set[str] = set()
    for engine_index, signal in enumerate(engines):
        _validate_engine_signal(signal, f"{label}.engines[{engine_index}]")
        _require(signal["engineID"] not in ids, f"{label} has duplicate engineID")
        ids.add(signal["engineID"])
        roles.add(signal["candidateRole"])
    _require(ids == {policy["baselineEngineID"], policy["candidateEngineID"]}, f"{label}.engine IDs do not match frozen policy")
    _require(roles == {"baseline", "candidate"}, f"{label}.engines must contain baseline and candidate roles")


def validate_input(payload: Any) -> dict[str, Any]:
    _require(isinstance(payload, dict), "engine-selector input root must be an object")
    allowed = {"schemaVersion", "benchmark", "contractExampleOnly", "run", "policy", "evidenceGate", "runtimeCases"}
    _reject_unknown(payload, allowed, "input")
    for key in allowed:
        _require(key in payload, f"input missing {key}")
    _require(payload["schemaVersion"] == SCHEMA_VERSION, "unsupported engine-selector schemaVersion")
    _require(payload["benchmark"] == BENCHMARK, "input benchmark must be japanese-ocr-engine-selector")
    _require(isinstance(payload["contractExampleOnly"], bool), "contractExampleOnly must be boolean")
    _validate_run(payload["run"])
    _validate_policy(payload["policy"])
    _validate_evidence_gate(payload["evidenceGate"], payload["contractExampleOnly"])
    cases = payload["runtimeCases"]
    _require(isinstance(cases, list) and cases, "runtimeCases must be a non-empty array")
    case_ids: set[str] = set()
    block_ids: set[str] = set()
    for index, case in enumerate(cases):
        _validate_runtime_case(case, index, payload["policy"])
        _require(case["caseID"] not in case_ids, f"duplicate caseID: {case['caseID']}")
        _require(case["blockID"] not in block_ids, f"duplicate blockID: {case['blockID']}")
        case_ids.add(case["caseID"])
        block_ids.add(case["blockID"])
        signals_by_id = _engine_map(case)
        _require(
            signals_by_id[payload["policy"]["baselineEngineID"]]["candidateRole"] == "baseline",
            f"runtimeCases[{index}] baseline engine role does not match policy",
        )
        _require(
            signals_by_id[payload["policy"]["candidateEngineID"]]["candidateRole"] == "candidate",
            f"runtimeCases[{index}] candidate engine role does not match policy",
        )
    return {"policy": payload["policy"], "evidenceGate": payload["evidenceGate"], "cases": cases}


def _engine_map(case: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {signal["engineID"]: signal for signal in case["engines"]}


def _candidate_rejection_reasons(policy: dict[str, Any], case: dict[str, Any], candidate: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    if not policy["featureFlagEnabled"]:
        reasons.append("featureFlagDisabled")
    if candidate["artifactStatus"] != "available":
        reasons.append("candidateArtifactUnavailable")
    if not candidate["licenseReviewed"]:
        reasons.append("candidateLicenseNotReviewed")
    if case["cropRole"] not in candidate["supportsCropRoles"]:
        reasons.append("cropRoleUnsupported")
    if not case["geometryValid"]:
        reasons.append("geometryInvalid")
    if case["duplicateRisk"]:
        reasons.append("duplicateRisk")
    if case["requestBudgetRemaining"] <= 0:
        reasons.append("requestBudgetExhausted")
    if case["pixelBudgetRemaining"] <= 0:
        reasons.append("pixelBudgetExhausted")
    if case["cancellationState"] != "active":
        reasons.append("cancelledOrCancelRequested")
    if not case["generationMatches"]:
        reasons.append("staleGeneration")
    if case["candidateFailureCount"] >= policy["rollbackFailureThreshold"]:
        reasons.append("rollbackFailureThresholdReached")
    if candidate["outputStatus"] != "success" or not candidate["text"].strip():
        reasons.append("candidateOutputUnavailable")
    if candidate["calibratedQuality"] is None:
        reasons.append("calibratedQualityUnavailable")
    elif candidate["calibratedQuality"] < policy["candidateMinCalibratedQuality"]:
        reasons.append("candidateQualityBelowThreshold")
    elif candidate["calibrationProfileID"] != policy["candidateCalibrationProfileID"]:
        reasons.append("calibrationProfileMismatch")
    if candidate["warmLatencyMs"] is None:
        reasons.append("candidateWarmLatencyUnavailable")
    elif candidate["warmLatencyMs"] > policy["candidateMaxWarmLatencyMs"]:
        reasons.append("candidateWarmLatencyExceeded")
    if candidate["peakMemoryBytes"] is None:
        reasons.append("candidatePeakMemoryUnavailable")
    elif candidate["peakMemoryBytes"] > policy["candidateMaxPeakMemoryBytes"]:
        reasons.append("candidatePeakMemoryExceeded")
    return reasons


def _baseline_available(policy: dict[str, Any], case: dict[str, Any], baseline: dict[str, Any]) -> bool:
    return (
        baseline["artifactStatus"] == "available"
        and baseline["licenseReviewed"]
        and case["cropRole"] in baseline["supportsCropRoles"]
    )


def _decision(payload: dict[str, Any], case: dict[str, Any]) -> dict[str, Any]:
    policy = payload["policy"]
    engines = _engine_map(case)
    baseline = engines[policy["baselineEngineID"]]
    candidate = engines[policy["candidateEngineID"]]
    rejection_reasons = _candidate_rejection_reasons(policy, case, candidate)
    baseline_available = _baseline_available(policy, case, baseline)
    candidate_accepted = not rejection_reasons and baseline_available
    rollback_applied = (
        case["candidateFailureCount"] >= policy["rollbackFailureThreshold"]
        or case["cancellationState"] != "active"
        or not case["generationMatches"]
    )
    if candidate_accepted:
        selected_engine = policy["candidateEngineID"]
        selection_reason = "candidateShadowEligible"
    elif baseline_available:
        selected_engine = policy["baselineEngineID"]
        selection_reason = "rollbackToBaseline" if rollback_applied else "baselineDefault"
    else:
        selected_engine = None
        selection_reason = "noEngineAvailable"
        rejection_reasons.append("baselineUnavailable")
    return {
        "caseID": case["caseID"],
        "blockID": case["blockID"],
        "selectedEngineID": selected_engine,
        "selectionReason": selection_reason,
        "candidateConsidered": True,
        "candidateAccepted": candidate_accepted,
        "fallbackReasons": rejection_reasons,
        "rollbackApplied": rollback_applied,
        "storeProvenance": policy["storeProvenance"],
        "reviewStatePreserved": policy["preserveReviewStateOnRollback"],
        "requestBudgetDelta": 0,
        "pixelBudgetDelta": 0,
    }


def _evidence_ready(evidence: dict[str, Any], contract_example_only: bool) -> bool:
    if contract_example_only or evidence["status"] != "ready":
        return False
    return all(
        evidence[key] is True
        for key in (
            "candidateArtifactReady", "authorizedCorpusReady", "policyFrozenBeforeHoldout", "holdoutEvaluatedOnce",
            "outputMetricsPassed", "duplicateOmissionOrderPassed", "cancellationPassed", "memoryPassed", "rollbackVerified",
        )
    ) and evidence["holdoutTunedAfterEvaluation"] is False


def evaluate(payload: Any) -> dict[str, Any]:
    info = validate_input(payload)
    policy = info["policy"]
    decisions = [
        _decision(info, case)
        for case in sorted(info["cases"], key=lambda item: (item["blockID"], item["caseID"]))
    ]
    candidate_selected = sum(decision["candidateAccepted"] for decision in decisions)
    ready = _evidence_ready(info["evidenceGate"], payload["contractExampleOnly"])
    if ready:
        status = "readyForReview"
        promotion_status = "eligibleForReview"
        promotion_reason = "frozen GT-isolated selector passed all declared evidence gates; product flag remains off"
    elif payload["contractExampleOnly"] or not info["evidenceGate"]["candidateArtifactReady"]:
        status = "blocked"
        promotion_status = "notEligible"
        promotion_reason = "candidate artifact or contract evidence is missing; baseline-only rollback remains active"
    else:
        status = "insufficientEvidence"
        promotion_status = "notEligible"
        promotion_reason = "selector policy is frozen but one or more holdout/output/rollback gates are incomplete"
    return {
        "schemaVersion": SCHEMA_VERSION,
        "benchmark": BENCHMARK,
        "status": status,
        "contractExampleOnly": payload["contractExampleOnly"],
        "run": payload["run"],
        "policy": policy,
        "decisions": decisions,
        "selectionInputContract": {
            "groundTruthRead": False,
            "benchmarkFixtureRead": False,
            "rawConfidenceCompared": False,
            "allowedRuntimeSignals": ALLOWED_RUNTIME_SIGNALS,
        },
        "evidenceGate": info["evidenceGate"],
        "promotion": {
            "status": promotion_status,
            "reason": promotion_reason,
            "groundTruthUsedForSelection": False,
            "productSelectionChanged": False,
            "defaultCandidateEnabled": False,
            "rollbackAvailable": True,
            "shadowCandidateSelectedCount": candidate_selected,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--allow-not-ready", action="store_true")
    args = parser.parse_args()
    try:
        report = evaluate(load_json(args.input))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False))
        if report["status"] != "readyForReview" and not args.allow_not_ready:
            return 1
        return 0
    except EngineSelectorError as error:
        print(f"Japanese OCR engine selector evaluation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
