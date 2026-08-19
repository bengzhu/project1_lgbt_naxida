#!/usr/bin/env python3
"""Evaluate a distributable Japanese OCR candidate in shadow mode.

This evaluator composes the v3.282 same-crop OCR scorer with an explicit
artifact, license, and target-device resource matrix.  It never selects a
production engine and never imports the AITRANS target.  Missing artifacts and
partial resource rows remain visible and block promotion-quality evidence.
"""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import math
from pathlib import Path
import re
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_VERSION = "1.0.0"
BENCHMARK = "japanese-ocr-engine-candidate"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def _load_multi_engine_module():
    path = ROOT / "scripts/evaluate-japanese-ocr-multi-engine.py"
    spec = importlib.util.spec_from_file_location("aitrans_japanese_ocr_multi_engine_v3284", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load v3.282 same-crop evaluator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BASE = _load_multi_engine_module()


class EngineCandidateError(ValueError):
    """Raised for an incomplete, unsafe, or ambiguous engine envelope."""


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EngineCandidateError(f"cannot read JSON {path}: {error}") from error


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise EngineCandidateError(message)


def _reject_unknown(value: dict[str, Any], allowed: set[str], label: str) -> None:
    unknown = sorted(set(value) - allowed)
    _require(not unknown, f"{label} has unknown fields: {unknown}")


def _string(value: Any, label: str) -> str:
    _require(isinstance(value, str) and value.strip(), f"{label} must be a non-empty string")
    return value


def _finite(value: Any, label: str, *, minimum: float | None = None) -> float:
    _require(isinstance(value, (int, float)) and not isinstance(value, bool), f"{label} must be numeric")
    number = float(value)
    _require(math.isfinite(number), f"{label} must be finite")
    if minimum is not None:
        _require(number >= minimum, f"{label} is below {minimum}")
    return number


def _validate_run(run: Any) -> None:
    _require(isinstance(run, dict), "run must be an object")
    _reject_unknown(run, {"appSha", "evaluatorVersion", "invocationMode"}, "run")
    _require(bool(HEX40.fullmatch(run.get("appSha", ""))), "run.appSha must be a 40-digit lowercase SHA")
    _string(run.get("evaluatorVersion"), "run.evaluatorVersion")
    _require(run.get("invocationMode") == "cloud-only-shadow", "run.invocationMode must be cloud-only-shadow")


def _validate_corpus(corpus: Any) -> None:
    _require(isinstance(corpus, dict), "corpus must be an object")
    _reject_unknown(
        corpus,
        {"status", "source", "sourceLicense", "datasetVerified", "pageCount", "humanRegionCount", "holdoutPageCount"},
        "corpus",
    )
    for key in ("status", "source", "sourceLicense", "datasetVerified", "pageCount", "humanRegionCount", "holdoutPageCount"):
        _require(key in corpus, f"corpus missing {key}")
    _require(corpus["status"] in {"contractExampleOnly", "authorized"}, "corpus.status is invalid")
    _string(corpus["source"], "corpus.source")
    _string(corpus["sourceLicense"], "corpus.sourceLicense")
    _require(isinstance(corpus["datasetVerified"], bool), "corpus.datasetVerified must be boolean")
    for key in ("pageCount", "humanRegionCount", "holdoutPageCount"):
        _require(isinstance(corpus[key], int) and not isinstance(corpus[key], bool) and corpus[key] >= 0, f"corpus.{key} is invalid")
    if corpus["status"] == "contractExampleOnly":
        _require(corpus["datasetVerified"] is False, "contract corpus cannot be datasetVerified")
    else:
        _require(corpus["datasetVerified"] is True, "authorized corpus must be datasetVerified")


def _validate_artifact(artifact: Any, label: str, status: str, engine_license: str) -> None:
    _require(isinstance(artifact, dict), f"{label} must be an object")
    _reject_unknown(
        artifact,
        {"artifactID", "source", "sha256", "sizeBytes", "quantization", "license", "downloadPolicy"},
        label,
    )
    for key in ("artifactID", "source", "sha256", "sizeBytes", "quantization", "license", "downloadPolicy"):
        _require(key in artifact, f"{label} missing {key}")
    _string(artifact["artifactID"], f"{label}.artifactID")
    _string(artifact["source"], f"{label}.source")
    _string(artifact["license"], f"{label}.license")
    _require(artifact["license"] == engine_license, f"{label}.license must match engine license")
    _require(artifact["downloadPolicy"] in {"bundled", "cloudOnly", "userProvided", "notAvailable"}, f"{label}.downloadPolicy is invalid")
    if status == "available":
        _require(isinstance(artifact["sha256"], str) and bool(HEX64.fullmatch(artifact["sha256"])), f"{label}.sha256 is required for an available artifact")
        _require(isinstance(artifact["sizeBytes"], int) and not isinstance(artifact["sizeBytes"], bool) and artifact["sizeBytes"] > 0, f"{label}.sizeBytes is required for an available artifact")
        _string(artifact["quantization"], f"{label}.quantization")
        _require(artifact["downloadPolicy"] != "notAvailable", f"{label}.downloadPolicy cannot be notAvailable when available")
    else:
        _require(artifact["sha256"] is None, f"{label}.sha256 must be null for an unavailable artifact")
        _require(artifact["sizeBytes"] is None, f"{label}.sizeBytes must be null for an unavailable artifact")
        _require(artifact["quantization"] is None, f"{label}.quantization must be null for an unavailable artifact")


def _validate_engine(engine: Any, index: int) -> str:
    label = f"engines[{index}]"
    _require(isinstance(engine, dict), f"{label} must be an object")
    _reject_unknown(
        engine,
        {
            "engineID", "engineVersion", "candidateRole", "sourceRevision", "runtimeRevision",
            "model", "artifact", "license", "referenceOnly", "artifactStatus", "failureReason",
            "distribution", "defaultEnabled",
        },
        label,
    )
    required = (
        "engineID", "engineVersion", "candidateRole", "sourceRevision", "runtimeRevision",
        "model", "artifact", "license", "referenceOnly", "artifactStatus", "failureReason",
        "distribution", "defaultEnabled",
    )
    for key in required:
        _require(key in engine, f"{label} missing {key}")
    engine_id = _string(engine["engineID"], f"{label}.engineID")
    _require(engine["candidateRole"] in {"baseline", "candidate"}, f"{label}.candidateRole is invalid")
    for key in ("engineVersion", "sourceRevision", "runtimeRevision", "license"):
        _string(engine[key], f"{label}.{key}")
    _require(isinstance(engine["referenceOnly"], bool), f"{label}.referenceOnly must be boolean")
    _require(engine["artifactStatus"] in {"available", "missing", "failed"}, f"{label}.artifactStatus is invalid")
    if engine["artifactStatus"] == "available":
        _require(engine["failureReason"] is None, f"{label}.available artifact cannot carry failureReason")
    else:
        _string(engine["failureReason"], f"{label}.failureReason")
    model = engine["model"]
    _require(isinstance(model, dict), f"{label}.model must be an object")
    _reject_unknown(model, {"id", "version", "revision", "sha256", "license"}, f"{label}.model")
    for key in ("id", "version", "revision", "license"):
        _string(model.get(key), f"{label}.model.{key}")
    _require(model["license"] == engine["license"], f"{label}.model.license must match engine license")
    if engine["artifactStatus"] == "available":
        _require(isinstance(model["sha256"], str) and bool(HEX64.fullmatch(model["sha256"])), f"{label}.model.sha256 is required for an available artifact")
    else:
        _require(model["sha256"] is None, f"{label}.model.sha256 must be null for an unavailable artifact")
    _validate_artifact(engine["artifact"], f"{label}.artifact", engine["artifactStatus"], engine["license"])
    _require(engine["distribution"] in {"bundled", "userProvided", "cloudOnlyReference", "notDistributable"}, f"{label}.distribution is invalid")
    _require(isinstance(engine["defaultEnabled"], bool), f"{label}.defaultEnabled must be boolean")
    if engine["referenceOnly"]:
        _require(engine["distribution"] in {"cloudOnlyReference", "notDistributable"}, f"{label}.referenceOnly distribution is unsafe")
    else:
        _require(engine["distribution"] in {"bundled", "userProvided"}, f"{label}.distributable engine has an invalid distribution")
    if engine["candidateRole"] == "candidate":
        _require(engine["defaultEnabled"] is False, f"{label}.candidate cannot be default enabled")
    return engine_id


def _validate_measurements(
    measurements: Any,
    engines: dict[str, dict[str, Any]],
) -> dict[tuple[str, str], dict[str, Any]]:
    _require(isinstance(measurements, list), "measurementRuns must be an array")
    rows: dict[tuple[str, str], dict[str, Any]] = {}
    allowed = {
        "measurementID", "engineID", "deviceID", "deviceClass", "platform", "hardware", "os", "runtime",
        "status", "coldLatencyMs", "warmLatencyMs", "peakMemoryBytes", "energyMilliwattHours", "sampleCount",
        "measurementSource", "failureReason", "referenceOnly", "targetDevice",
    }
    for index, measurement in enumerate(measurements):
        label = f"measurementRuns[{index}]"
        _require(isinstance(measurement, dict), f"{label} must be an object")
        _reject_unknown(measurement, allowed, label)
        required = tuple(allowed)
        for key in required:
            _require(key in measurement, f"{label} missing {key}")
        engine_id = measurement["engineID"]
        _require(engine_id in engines, f"{label} references unknown engineID: {engine_id}")
        for key in ("measurementID", "deviceID", "deviceClass", "platform", "hardware", "os", "runtime", "measurementSource"):
            _string(measurement[key], f"{label}.{key}")
        _require(measurement["status"] in {"complete", "partial", "failed", "missing"}, f"{label}.status is invalid")
        _require(isinstance(measurement["referenceOnly"], bool), f"{label}.referenceOnly must be boolean")
        _require(measurement["referenceOnly"] == engines[engine_id]["referenceOnly"], f"{label}.referenceOnly does not match engine metadata")
        _require(isinstance(measurement["targetDevice"], bool), f"{label}.targetDevice must be boolean")
        key = (engine_id, measurement["deviceID"])
        _require(key not in rows, f"duplicate measurement run: {key}")
        for field in ("coldLatencyMs", "warmLatencyMs"):
            values = measurement[field]
            _require(isinstance(values, list), f"{label}.{field} must be an array")
            for value_index, value in enumerate(values):
                _finite(value, f"{label}.{field}[{value_index}]", minimum=0.000001)
        memory = measurement["peakMemoryBytes"]
        if memory is not None:
            _require(isinstance(memory, int) and not isinstance(memory, bool) and memory > 0, f"{label}.peakMemoryBytes is invalid")
        energy = measurement["energyMilliwattHours"]
        if energy is not None:
            _finite(energy, f"{label}.energyMilliwattHours", minimum=0.0)
        _require(isinstance(measurement["sampleCount"], int) and not isinstance(measurement["sampleCount"], bool) and measurement["sampleCount"] >= 0, f"{label}.sampleCount is invalid")
        if measurement["status"] == "complete":
            _require(engines[engine_id]["artifactStatus"] == "available", f"{label}.complete measurement requires an available artifact")
            _require(measurement["coldLatencyMs"] and measurement["warmLatencyMs"], f"{label}.complete latency samples are required")
            _require(memory is not None, f"{label}.complete peak memory is required")
            _require(energy is not None, f"{label}.complete energy is required")
            _require(measurement["sampleCount"] >= len(measurement["coldLatencyMs"]) + len(measurement["warmLatencyMs"]), f"{label}.sampleCount is smaller than latency samples")
            _require(measurement["failureReason"] is None, f"{label}.complete cannot carry failureReason")
        else:
            _string(measurement["failureReason"], f"{label}.failureReason")
        rows[key] = measurement
    for engine_id in engines:
        _require(any(key[0] == engine_id for key in rows), f"missing measurement run for engineID: {engine_id}")
    return rows


def validate_input(payload: dict[str, Any]) -> dict[str, Any]:
    _require(isinstance(payload, dict), "engine-candidate input root must be an object")
    _reject_unknown(
        payload,
        {"schemaVersion", "benchmark", "datasetSha256", "run", "corpus", "contractExampleOnly", "cropSet", "engines", "results", "measurementRuns"},
        "input",
    )
    _require(payload.get("schemaVersion") == SCHEMA_VERSION, "unsupported engine-candidate schemaVersion")
    _require(payload.get("benchmark") == BENCHMARK, "input benchmark must be japanese-ocr-engine-candidate")
    dataset_sha = payload.get("datasetSha256")
    _require(isinstance(dataset_sha, str) and bool(HEX64.fullmatch(dataset_sha)), "datasetSha256 is invalid")
    _validate_run(payload.get("run"))
    _validate_corpus(payload.get("corpus"))
    _require(isinstance(payload.get("contractExampleOnly"), bool), "contractExampleOnly must be boolean")
    crops = payload.get("cropSet")
    _require(isinstance(crops, list) and crops, "cropSet must be a non-empty array")
    engines_payload = payload.get("engines")
    _require(isinstance(engines_payload, list) and len(engines_payload) >= 2, "engines must include a baseline and candidate")
    crop_payload = copy.deepcopy(crops)
    engines: dict[str, dict[str, Any]] = {}
    for index, engine in enumerate(engines_payload):
        engine_id = _validate_engine(engine, index)
        _require(engine_id not in engines, f"duplicate engineID: {engine_id}")
        engines[engine_id] = engine
    roles = {engine["candidateRole"] for engine in engines.values()}
    _require(roles == {"baseline", "candidate"}, "engines must contain baseline and candidate roles")
    quality_payload = {
        "schemaVersion": "1.0.0",
        "benchmark": "japanese-ocr-multi-engine",
        "datasetSha256": dataset_sha,
        "cropSet": crop_payload,
        "engines": [
            {
                key: engine[key]
                for key in ("engineID", "engineVersion", "sourceRevision", "runtimeRevision", "model", "license", "referenceOnly", "artifactStatus", "failureReason")
            }
            for engine in engines.values()
        ],
        "results": copy.deepcopy(payload.get("results")),
    }
    try:
        quality_info = BASE.validate_input(quality_payload)
    except BASE.MultiEngineBenchmarkError as error:
        raise EngineCandidateError(str(error)) from error
    measurement_rows = _validate_measurements(payload.get("measurementRuns"), engines)
    return {
        "datasetSha256": dataset_sha,
        "run": payload["run"],
        "corpus": payload["corpus"],
        "contractExampleOnly": payload["contractExampleOnly"],
        "engines": engines,
        "qualityInfo": quality_info,
        "measurementRows": measurement_rows,
    }


def _nearest_rank(values: list[float], percentile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, math.ceil(percentile * len(ordered)) - 1)
    return ordered[index]


def _resource_row(measurement: dict[str, Any], engine: dict[str, Any]) -> dict[str, Any]:
    return {
        "measurementID": measurement["measurementID"],
        "engineID": measurement["engineID"],
        "deviceID": measurement["deviceID"],
        "deviceClass": measurement["deviceClass"],
        "platform": measurement["platform"],
        "hardware": measurement["hardware"],
        "os": measurement["os"],
        "runtime": measurement["runtime"],
        "status": measurement["status"],
        "targetDevice": measurement["targetDevice"],
        "coldLatencyMs": {
            "sampleCount": len(measurement["coldLatencyMs"]),
            "p50": _nearest_rank(measurement["coldLatencyMs"], 0.50),
            "p95": _nearest_rank(measurement["coldLatencyMs"], 0.95),
        },
        "warmLatencyMs": {
            "sampleCount": len(measurement["warmLatencyMs"]),
            "p50": _nearest_rank(measurement["warmLatencyMs"], 0.50),
            "p95": _nearest_rank(measurement["warmLatencyMs"], 0.95),
        },
        "peakMemoryBytes": measurement["peakMemoryBytes"],
        "energyMilliwattHours": measurement["energyMilliwattHours"],
        "sampleCount": measurement["sampleCount"],
        "measurementSource": measurement["measurementSource"],
        "failureReason": measurement["failureReason"],
        "license": engine["license"],
        "artifactStatus": engine["artifactStatus"],
        "referenceOnly": engine["referenceOnly"],
        "defaultEnabled": engine["defaultEnabled"],
    }


def evaluate(payload: dict[str, Any]) -> dict[str, Any]:
    info = validate_input(payload)
    quality = BASE.evaluate(
        {
            "schemaVersion": "1.0.0",
            "benchmark": "japanese-ocr-multi-engine",
            "datasetSha256": info["datasetSha256"],
            "cropSet": [
                {
                    key: crop[key]
                    for key in ("pageID", "regionID", "cropLevel", "cropID", "cropSha256", "source", "expectedText", "expectedTextNFC", "referenceOnly")
                }
                for crop in payload["cropSet"]
            ],
            "engines": [
                {
                    key: engine[key]
                    for key in ("engineID", "engineVersion", "sourceRevision", "runtimeRevision", "model", "license", "referenceOnly", "artifactStatus", "failureReason")
                }
                for engine in info["engines"].values()
            ],
            "results": copy.deepcopy(payload["results"]),
        }
    )
    resources = [
        _resource_row(measurement, info["engines"][measurement["engineID"]])
        for measurement in sorted(info["measurementRows"].values(), key=lambda item: (item["engineID"], item["deviceID"]))
    ]
    available_engines = [engine_id for engine_id, engine in info["engines"].items() if engine["artifactStatus"] == "available"]
    complete_available = all(
        any(row["engineID"] == engine_id and row["status"] == "complete" for row in resources)
        for engine_id in available_engines
    )
    all_artifacts_available = all(engine["artifactStatus"] == "available" for engine in info["engines"].values())
    candidate_ids = {
        engine_id
        for engine_id, engine in info["engines"].items()
        if engine["candidateRole"] == "candidate"
    }
    target_complete = any(
        row["engineID"] in candidate_ids
        and row["targetDevice"]
        and row["status"] == "complete"
        for row in resources
    )
    resource_complete = all_artifacts_available and complete_available and target_complete
    corpus_ready = (
        info["corpus"]["status"] == "authorized"
        and info["corpus"]["datasetVerified"]
        and info["corpus"]["pageCount"] >= 20
        and info["corpus"]["humanRegionCount"] >= 150
        and info["corpus"]["holdoutPageCount"] >= 20
    )
    if not all_artifacts_available or not complete_available:
        status = "blocked"
    elif info["contractExampleOnly"] or not corpus_ready or not resource_complete:
        status = "insufficientCorpus"
    else:
        status = "success"
    license_matrix = [
        {
            "engineID": engine_id,
            "candidateRole": engine["candidateRole"],
            "engineVersion": engine["engineVersion"],
            "sourceRevision": engine["sourceRevision"],
            "runtimeRevision": engine["runtimeRevision"],
            "model": engine["model"],
            "artifact": engine["artifact"],
            "license": engine["license"],
            "referenceOnly": engine["referenceOnly"],
            "distribution": engine["distribution"],
            "artifactStatus": engine["artifactStatus"],
            "failureReason": engine["failureReason"],
            "defaultEnabled": engine["defaultEnabled"],
        }
        for engine_id, engine in sorted(info["engines"].items())
    ]
    gate_reasons = []
    if not all_artifacts_available:
        gate_reasons.append("at least one declared OCR artifact is missing or failed")
    if not complete_available:
        gate_reasons.append("at least one available engine lacks a complete latency/memory/energy measurement")
    if not target_complete:
        gate_reasons.append("no complete measurement is marked as a real target-device run")
    if not corpus_ready:
        gate_reasons.append("corpus is not an authorized 20-page/150-region holdout corpus")
    return {
        "schemaVersion": SCHEMA_VERSION,
        "benchmark": BENCHMARK,
        "status": status,
        "datasetSha256": info["datasetSha256"],
        "run": info["run"],
        "corpus": info["corpus"],
        "contractExampleOnly": info["contractExampleOnly"],
        "artifactGate": {
            "allArtifactsAvailable": all_artifacts_available,
            "allAvailableEnginesHaveCompleteMeasurements": complete_available,
            "hasCompleteTargetDeviceRun": target_complete,
            "resourceMatrixComplete": resource_complete,
            "reasons": gate_reasons,
        },
        "sameCrop": quality,
        "resources": {
            "percentileMethod": "nearest-rank; p50=ceil(0.50*n), p95=ceil(0.95*n)",
            "rows": resources,
        },
        "licenseMatrix": license_matrix,
        "promotion": {
            "status": "notEligible",
            "reason": "v3.284 is shadow-only; v3.285 must freeze a GT-isolated selector and rollback policy",
            "groundTruthUsedForSelection": False,
            "productSelectionChanged": False,
            "defaultEnabledCandidateCount": sum(
                engine["candidateRole"] == "candidate" and engine["defaultEnabled"]
                for engine in info["engines"].values()
            ),
            "requires": [
                "authorized dataset with >=20 holdout pages and >=150 human regions",
                "same-crop oracle/detected/fullPage evidence",
                "complete target-device latency/memory/energy measurements",
                "license and distribution review",
            ],
        },
        "qualityClaim": (
            "blocked shadow matrix; missing artifacts or incomplete resource evidence are explicit and no OCR quality claim is made"
            if status == "blocked"
            else "shadow-only same-crop/resource evidence; no default enablement or general Japanese OCR claim"
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
    except EngineCandidateError as error:
        print(f"Japanese OCR engine candidate evaluation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
