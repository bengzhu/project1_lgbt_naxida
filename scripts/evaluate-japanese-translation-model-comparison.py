#!/usr/bin/env python3
"""Evaluate the v3.287 clean-text local translation model comparison envelope.

This is a deterministic, fail-closed scorer.  It compares the same clean-text
case set across model profiles and reports structural output signals plus
cold/warm runtime measurements.  It never selects a production model and it
does not read AITRANS source or benchmark ground truth for product decisions.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import unicodedata
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_VERSION = "1.0.0"
BENCHMARK = "japanese-translation-model-comparison"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
LANGUAGE_PAIRS = (("ja", "zh-CN"), ("ja", "en"), ("en", "zh-CN"))


class ModelComparisonError(ValueError):
    """Raised for malformed, incomplete, or unsafe comparison evidence."""


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def json_sha256(value: Any) -> str:
    return sha256_bytes(canonical_json(value))


def manifest_sha256(manifest: dict[str, Any]) -> str:
    payload = copy.deepcopy(manifest)
    payload["manifestSha256"] = None
    return json_sha256(payload)


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ModelComparisonError(f"cannot read JSON {path}: {error}") from error


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ModelComparisonError(message)


def _reject_unknown(value: dict[str, Any], allowed: set[str], label: str) -> None:
    unknown = sorted(set(value) - allowed)
    _require(not unknown, f"{label} has unknown fields: {unknown}")


def _string(value: Any, label: str) -> str:
    _require(isinstance(value, str) and value.strip(), f"{label} must be a non-empty string")
    return value


def _finite(value: Any, label: str, minimum: float | None = None) -> float:
    _require(isinstance(value, (int, float)) and not isinstance(value, bool), f"{label} must be numeric")
    number = float(value)
    _require(math.isfinite(number), f"{label} must be finite")
    if minimum is not None:
        _require(number >= minimum, f"{label} is below {minimum}")
    return number


def _safe_path(manifest_path: Path, relative: str, repo_root: Path) -> Path:
    path = Path(relative)
    _require(not path.is_absolute(), f"manifest source path must be relative: {relative!r}")
    resolved = (manifest_path.parent / path).resolve()
    root = repo_root.resolve()
    _require(resolved == root or root in resolved.parents, f"manifest source path escapes repository: {relative!r}")
    return resolved


def _validate_manifest(
    manifest: dict[str, Any],
    *,
    manifest_path: Path,
    repo_root: Path,
    verify_assets: bool,
) -> dict[str, Any]:
    _require(isinstance(manifest, dict), "comparison manifest must be an object")
    _reject_unknown(
        manifest,
        {"schemaVersion", "benchmark", "datasetVersion", "contractExampleOnly", "manifestSha256", "requiredLanguagePairs", "source", "cases"},
        "comparison manifest",
    )
    _require(manifest.get("schemaVersion") == SCHEMA_VERSION, "unsupported comparison manifest schemaVersion")
    _require(manifest.get("benchmark") == BENCHMARK, "comparison manifest benchmark is invalid")
    _string(manifest.get("datasetVersion"), "manifest.datasetVersion")
    _require(isinstance(manifest.get("contractExampleOnly"), bool), "manifest.contractExampleOnly must be boolean")
    declared_hash = manifest.get("manifestSha256")
    _require(isinstance(declared_hash, str) and bool(HEX64.fullmatch(declared_hash)), "manifestSha256 is invalid")
    actual_hash = manifest_sha256(manifest)
    _require(declared_hash == actual_hash, f"manifest SHA mismatch: {actual_hash} != {declared_hash}")

    pairs_payload = manifest.get("requiredLanguagePairs")
    _require(isinstance(pairs_payload, list), "requiredLanguagePairs must be an array")
    pairs: list[tuple[str, str]] = []
    for index, pair in enumerate(pairs_payload):
        _require(isinstance(pair, list) and len(pair) == 2, f"requiredLanguagePairs[{index}] must contain two languages")
        value = (pair[0], pair[1])
        _require(value in LANGUAGE_PAIRS, f"unsupported language pair: {value}")
        _require(value not in pairs, f"duplicate language pair: {value}")
        pairs.append(value)
    _require(set(pairs) == set(LANGUAGE_PAIRS), "comparison manifest must cover ja->zh-CN, ja->en, and en->zh-CN")

    source = manifest.get("source")
    _require(isinstance(source, dict), "manifest.source must be an object")
    _reject_unknown(source, {"path", "sha256", "format", "license", "permittedUses"}, "manifest.source")
    for key in ("path", "sha256", "format", "license", "permittedUses"):
        _require(key in source, f"manifest.source missing {key}")
    source_path = _safe_path(manifest_path, _string(source["path"], "manifest.source.path"), repo_root)
    _require(bool(HEX64.fullmatch(str(source["sha256"]))), "manifest.source.sha256 is invalid")
    _require(source["format"] == "json", "manifest.source.format must be json")
    _string(source["license"], "manifest.source.license")
    _require(isinstance(source["permittedUses"], list) and source["permittedUses"], "manifest.source.permittedUses is empty")
    if verify_assets:
        _require(source_path.is_file(), f"comparison corpus source is missing: {source_path}")
        actual_source_sha = sha256_bytes(source_path.read_bytes())
        _require(actual_source_sha == source["sha256"], f"comparison corpus source SHA mismatch: {actual_source_sha} != {source['sha256']}")
        source_payload = load_json(source_path)
        _require(isinstance(source_payload, dict), "comparison corpus source must be an object")
        _reject_unknown(source_payload, {"schemaVersion", "datasetVersion", "cases"}, "comparison corpus source")
        _require(source_payload.get("schemaVersion") == SCHEMA_VERSION, "comparison corpus source schemaVersion is invalid")
        _require(source_payload.get("datasetVersion") == manifest["datasetVersion"], "comparison corpus datasetVersion mismatch")
        source_cases = source_payload.get("cases")
        _require(isinstance(source_cases, list), "comparison corpus source cases must be an array")
    else:
        source_cases = None

    cases_payload = manifest.get("cases")
    _require(isinstance(cases_payload, list) and cases_payload, "comparison manifest cases must be non-empty")
    cases: dict[str, dict[str, Any]] = {}
    for index, case in enumerate(cases_payload):
        label = f"manifest.cases[{index}]"
        _require(isinstance(case, dict), f"{label} must be an object")
        _reject_unknown(
            case,
            {"caseID", "split", "inputKind", "sourceLanguage", "targetLanguage", "sourceText", "sourceTextNFC", "referenceTranslation", "referenceStatus", "textType", "maxTranslationCharacters"},
            label,
        )
        required = ("caseID", "split", "inputKind", "sourceLanguage", "targetLanguage", "sourceText", "sourceTextNFC", "referenceTranslation", "referenceStatus", "textType")
        for key in required:
            _require(key in case, f"{label} missing {key}")
        case_id = _string(case["caseID"], f"{label}.caseID")
        _require(case_id not in cases, f"duplicate comparison caseID: {case_id}")
        _require(case["split"] in {"train", "dev", "holdout"}, f"{label}.split is invalid")
        _require(case["inputKind"] == "cleanSource", f"{label} is not cleanSource")
        pair = (case["sourceLanguage"], case["targetLanguage"])
        _require(pair in LANGUAGE_PAIRS, f"{label} has unsupported language pair: {pair}")
        source_text = _string(case["sourceText"], f"{label}.sourceText")
        _require(case["sourceTextNFC"] == unicodedata.normalize("NFC", source_text), f"{label}.sourceTextNFC mismatch")
        _require(case["referenceStatus"] in {"human", "contractExampleOnly", "pending", "none"}, f"{label}.referenceStatus is invalid")
        if case["referenceStatus"] in {"human", "contractExampleOnly"}:
            _string(case["referenceTranslation"], f"{label}.referenceTranslation")
        else:
            _require(case["referenceTranslation"] is None, f"{label}.referenceTranslation must be null without a reference")
        _require(case["textType"] in {"dialogue", "narration", "SFX", "title", "other"}, f"{label}.textType is invalid")
        if "maxTranslationCharacters" in case and case["maxTranslationCharacters"] is not None:
            _require(isinstance(case["maxTranslationCharacters"], int) and case["maxTranslationCharacters"] > 0, f"{label}.maxTranslationCharacters is invalid")
        cases[case_id] = case

    observed_pairs = {(case["sourceLanguage"], case["targetLanguage"]) for case in cases.values()}
    _require(observed_pairs == set(LANGUAGE_PAIRS), "comparison corpus does not contain all required language pairs")
    if source_cases is not None:
        source_by_id: dict[str, dict[str, Any]] = {}
        for index, source_case in enumerate(source_cases):
            label = f"comparison corpus source.cases[{index}]"
            _require(isinstance(source_case, dict), f"{label} must be an object")
            _reject_unknown(source_case, {"caseID", "sourceLanguage", "targetLanguage", "sourceText"}, label)
            for key in ("caseID", "sourceLanguage", "targetLanguage", "sourceText"):
                _require(key in source_case, f"{label} missing {key}")
            source_id = _string(source_case["caseID"], f"{label}.caseID")
            _require(source_id not in source_by_id, f"duplicate source caseID: {source_id}")
            source_by_id[source_id] = source_case
        _require(set(source_by_id) == set(cases), "manifest/source corpus case IDs differ")
        for case_id, case in cases.items():
            source_case = source_by_id[case_id]
            for key in ("sourceLanguage", "targetLanguage", "sourceText"):
                _require(source_case[key] == case[key], f"manifest/source mismatch for {case_id}.{key}")

    return {
        "manifestSha256": declared_hash,
        "datasetVersion": manifest["datasetVersion"],
        "contractExampleOnly": manifest["contractExampleOnly"],
        "cases": cases,
        "requiredLanguagePairs": sorted(pairs),
        "holdoutCaseCount": sum(case["split"] == "holdout" for case in cases.values()),
        "sourcePath": source_path,
    }


def _validate_run(run: Any) -> None:
    _require(isinstance(run, dict), "run must be an object")
    _reject_unknown(run, {"appSha", "evaluatorVersion", "invocationMode"}, "run")
    _require(bool(HEX40.fullmatch(run.get("appSha", ""))), "run.appSha is invalid")
    _string(run.get("evaluatorVersion"), "run.evaluatorVersion")
    _require(run.get("invocationMode") == "cloud-only-shadow", "run.invocationMode must be cloud-only-shadow")


def _validate_template(template: Any, label: str) -> str:
    _require(isinstance(template, dict), f"{label} must be an object")
    _reject_unknown(template, {"source", "templateID", "templateSha256", "fallbackProfileID", "applyAPI"}, label)
    for key in ("source", "templateID", "templateSha256", "fallbackProfileID", "applyAPI"):
        _require(key in template, f"{label} missing {key}")
    _require(template["source"] in {"embedded", "explicitKnownFallback", "missingRejected", "unsupportedRejected"}, f"{label}.source is invalid")
    _require(template["applyAPI"] == "llama_chat_apply_template", f"{label}.applyAPI is invalid")
    if template["templateSha256"] is not None:
        _require(bool(HEX64.fullmatch(template["templateSha256"])), f"{label}.templateSha256 is invalid")
    if template["source"] == "missingRejected":
        _require(template["fallbackProfileID"] is None, f"{label}.missingRejected cannot have a fallback profile")
    if template["source"] == "explicitKnownFallback":
        _string(template["fallbackProfileID"], f"{label}.fallbackProfileID")
    return template["templateID"] or template["fallbackProfileID"] or "missing-template"


def _validate_decoding(decoding: Any, label: str) -> str:
    _require(isinstance(decoding, dict), f"{label} must be an object")
    _reject_unknown(decoding, {"profileID", "mode", "seed", "temperature", "topK", "topP", "minP"}, label)
    for key in ("profileID", "mode", "seed", "temperature", "topK", "topP", "minP"):
        _require(key in decoding, f"{label} missing {key}")
    profile_id = _string(decoding["profileID"], f"{label}.profileID")
    _require(decoding["mode"] in {"deterministic", "sampled"}, f"{label}.mode is invalid")
    if decoding["seed"] is not None:
        _require(isinstance(decoding["seed"], int) and decoding["seed"] >= 0, f"{label}.seed is invalid")
    _finite(decoding["temperature"], f"{label}.temperature", minimum=0)
    for key in ("topK",):
        if decoding[key] is not None:
            _require(isinstance(decoding[key], int) and decoding[key] >= 1, f"{label}.{key} is invalid")
    for key in ("topP", "minP"):
        if decoding[key] is not None:
            value = _finite(decoding[key], f"{label}.{key}", minimum=0)
            _require(value <= 1, f"{label}.{key} must be <= 1")
    return profile_id


def _validate_models(models_payload: Any, selection: dict[str, Any]) -> dict[str, dict[str, Any]]:
    _require(isinstance(models_payload, list) and len(models_payload) >= 2, "models must contain at least two profiles")
    models: dict[str, dict[str, Any]] = {}
    for index, model in enumerate(models_payload):
        label = f"models[{index}]"
        _require(isinstance(model, dict), f"{label} must be an object")
        _reject_unknown(
            model,
            {"modelID", "modelFamily", "comparisonRole", "modelFilename", "modelSha256", "quantization", "sizeBytes", "license", "licenseReviewed", "artifactStatus", "distribution", "referenceOnly", "defaultEnabled", "contextLength", "template", "decoding"},
            label,
        )
        required = ("modelID", "modelFamily", "comparisonRole", "modelFilename", "modelSha256", "quantization", "sizeBytes", "license", "licenseReviewed", "artifactStatus", "distribution", "referenceOnly", "defaultEnabled", "contextLength", "template", "decoding")
        for key in required:
            _require(key in model, f"{label} missing {key}")
        model_id = _string(model["modelID"], f"{label}.modelID")
        _require(model_id not in models, f"duplicate modelID: {model_id}")
        _require(model["modelFamily"] in {"Gemma", "Qwen", "Sakura", "Llama", "Hunyuan", "remoteProvider", "other"}, f"{label}.modelFamily is invalid")
        _require(model["comparisonRole"] in {"floor", "candidate", "reference"}, f"{label}.comparisonRole is invalid")
        _require(isinstance(model["modelFilename"], str) and model["modelFilename"].endswith(".gguf"), f"{label}.modelFilename must end in .gguf")
        if model["modelSha256"] is not None:
            _require(bool(HEX64.fullmatch(model["modelSha256"])), f"{label}.modelSha256 is invalid")
        if model["sizeBytes"] is not None:
            _require(isinstance(model["sizeBytes"], int) and model["sizeBytes"] > 0, f"{label}.sizeBytes is invalid")
        _string(model["license"], f"{label}.license")
        _require(isinstance(model["licenseReviewed"], bool), f"{label}.licenseReviewed must be boolean")
        _require(model["artifactStatus"] in {"available", "missing", "failed", "notProvided"}, f"{label}.artifactStatus is invalid")
        _require(model["distribution"] in {"bundled", "userProvided", "cloudOnlyReference", "remoteProvider", "notDistributable"}, f"{label}.distribution is invalid")
        _require(isinstance(model["referenceOnly"], bool), f"{label}.referenceOnly must be boolean")
        _require(isinstance(model["defaultEnabled"], bool), f"{label}.defaultEnabled must be boolean")
        _require(isinstance(model["contextLength"], int) and model["contextLength"] > 0, f"{label}.contextLength is invalid")
        template_id = _validate_template(model["template"], f"{label}.template")
        _validate_decoding(model["decoding"], f"{label}.decoding")
        if model["artifactStatus"] == "available":
            _require(isinstance(model["modelSha256"], str) and bool(HEX64.fullmatch(model["modelSha256"])), f"{label}.available model requires SHA-256")
            _require(isinstance(model["sizeBytes"], int) and model["sizeBytes"] > 0, f"{label}.available model requires sizeBytes")
            _require(isinstance(model["quantization"], str) and model["quantization"], f"{label}.available model requires quantization")
            if model["template"]["source"] == "embedded":
                _require(bool(HEX64.fullmatch(model["template"]["templateSha256"] or "")), f"{label}.embedded template requires SHA-256")
                _require(template_id != "missing-template", f"{label}.embedded template requires templateID")
        if model["comparisonRole"] == "candidate":
            _require(model["defaultEnabled"] is False, f"{label}.candidate cannot be defaultEnabled")
        if model["comparisonRole"] == "floor":
            _require(model["modelFamily"] == "Gemma" and "270" in model_id, f"{label}.floor must be the Gemma 270M floor")
        models[model_id] = model

    floor_models = [model for model in models.values() if model["comparisonRole"] == "floor"]
    _require(len(floor_models) == 1, "comparison must contain exactly one 270M floor")
    _require(sum(model["comparisonRole"] == "candidate" for model in models.values()) >= 1, "comparison must contain a candidate model")
    default_models = [model for model in models.values() if model["defaultEnabled"]]
    _require(len(default_models) == 1, "comparison must contain exactly one default-enabled floor")
    _require(default_models[0]["comparisonRole"] == "floor", "only the 270M floor may remain default-enabled")
    _require(selection.get("defaultModelID") == default_models[0]["modelID"], "selection.defaultModelID does not match model metadata")
    return models


def _validate_predictions(predictions_payload: Any, cases: dict[str, dict[str, Any]], models: dict[str, dict[str, Any]]) -> dict[tuple[str, str], dict[str, Any]]:
    _require(isinstance(predictions_payload, list), "predictions must be an array")
    rows: dict[tuple[str, str], dict[str, Any]] = {}
    prediction_ids: set[str] = set()
    allowed = {"predictionID", "modelID", "caseID", "split", "status", "output", "promptTemplateID", "decodingProfileID", "contextOverflow", "failureReason", "referenceOnly"}
    for index, prediction in enumerate(predictions_payload):
        label = f"predictions[{index}]"
        _require(isinstance(prediction, dict), f"{label} must be an object")
        _reject_unknown(prediction, allowed, label)
        for key in allowed:
            _require(key in prediction, f"{label} missing {key}")
        prediction_id = _string(prediction["predictionID"], f"{label}.predictionID")
        _require(prediction_id not in prediction_ids, f"duplicate predictionID: {prediction_id}")
        prediction_ids.add(prediction_id)
        model_id = prediction["modelID"]
        case_id = prediction["caseID"]
        _require(model_id in models, f"{label} references unknown modelID: {model_id}")
        _require(case_id in cases, f"{label} references unknown caseID: {case_id}")
        key = (model_id, case_id)
        _require(key not in rows, f"duplicate prediction for {key}")
        case = cases[case_id]
        model = models[model_id]
        _require(prediction["split"] == case["split"], f"{label}.split mismatch")
        _require(prediction["status"] in {"success", "empty", "failure", "notRun"}, f"{label}.status is invalid")
        _require(isinstance(prediction["contextOverflow"], bool), f"{label}.contextOverflow must be boolean")
        _require(isinstance(prediction["referenceOnly"], bool) and prediction["referenceOnly"] == model["referenceOnly"], f"{label}.referenceOnly mismatch")
        template_id = model["template"]["templateID"] or model["template"]["fallbackProfileID"] or "missing-template"
        _require(prediction["promptTemplateID"] == template_id, f"{label}.promptTemplateID does not match model template")
        _require(prediction["decodingProfileID"] == model["decoding"]["profileID"], f"{label}.decodingProfileID does not match model profile")
        if prediction["status"] == "success":
            _string(prediction["output"], f"{label}.output")
            _require(prediction["failureReason"] is None, f"{label}.success cannot carry failureReason")
            _require(prediction["contextOverflow"] is False, f"{label}.success cannot overflow context")
        elif prediction["status"] == "empty":
            _require(prediction["output"] == "", f"{label}.empty output must be an empty string")
            _string(prediction["failureReason"], f"{label}.failureReason")
        else:
            _require(prediction["output"] is None or isinstance(prediction["output"], str), f"{label}.output is invalid")
            _string(prediction["failureReason"], f"{label}.failureReason")
        rows[key] = prediction
    expected = {(model_id, case_id) for model_id in models for case_id in cases}
    _require(set(rows) == expected, f"predictions must cover every model/case pair; missing={sorted(expected - set(rows))} extra={sorted(set(rows) - expected)}")
    return rows


def _validate_measurements(measurements_payload: Any, cases: dict[str, dict[str, Any]], models: dict[str, dict[str, Any]], contract_example_only: bool) -> dict[tuple[str, str, str, int], dict[str, Any]]:
    _require(isinstance(measurements_payload, list), "measurements must be an array")
    rows: dict[tuple[str, str, str, int], dict[str, Any]] = {}
    measurement_ids: set[str] = set()
    allowed = {"measurementID", "modelID", "caseID", "warmState", "sampleIndex", "status", "latencyMilliseconds", "firstTokenMilliseconds", "peakMemoryBytes", "contextOverflow", "deviceID", "deviceClass", "platform", "hardware", "os", "runtime", "measurementSource", "targetDevice"}
    for index, measurement in enumerate(measurements_payload):
        label = f"measurements[{index}]"
        _require(isinstance(measurement, dict), f"{label} must be an object")
        _reject_unknown(measurement, allowed, label)
        for key in allowed:
            _require(key in measurement, f"{label} missing {key}")
        measurement_id = _string(measurement["measurementID"], f"{label}.measurementID")
        _require(measurement_id not in measurement_ids, f"duplicate measurementID: {measurement_id}")
        measurement_ids.add(measurement_id)
        model_id = measurement["modelID"]
        case_id = measurement["caseID"]
        _require(model_id in models, f"{label} references unknown modelID: {model_id}")
        _require(case_id in cases, f"{label} references unknown caseID: {case_id}")
        _require(measurement["warmState"] in {"cold", "warm"}, f"{label}.warmState is invalid")
        _require(isinstance(measurement["sampleIndex"], int) and measurement["sampleIndex"] >= 0, f"{label}.sampleIndex is invalid")
        key = (model_id, case_id, measurement["warmState"], measurement["sampleIndex"])
        _require(key not in rows, f"duplicate measurement sample: {key}")
        _require(measurement["status"] in {"complete", "partial", "failed", "notRun"}, f"{label}.status is invalid")
        for field in ("deviceID", "deviceClass", "platform", "hardware", "os", "runtime", "measurementSource"):
            _string(measurement[field], f"{label}.{field}")
        _require(isinstance(measurement["targetDevice"], bool), f"{label}.targetDevice must be boolean")
        for field in ("latencyMilliseconds", "firstTokenMilliseconds"):
            if measurement[field] is not None:
                _finite(measurement[field], f"{label}.{field}", minimum=0.000001)
        if measurement["peakMemoryBytes"] is not None:
            _require(isinstance(measurement["peakMemoryBytes"], int) and measurement["peakMemoryBytes"] > 0, f"{label}.peakMemoryBytes is invalid")
        if measurement["contextOverflow"] is not None:
            _require(isinstance(measurement["contextOverflow"], bool), f"{label}.contextOverflow must be boolean or null")
        if measurement["status"] == "complete":
            _require(measurement["latencyMilliseconds"] is not None, f"{label}.complete latency is required")
            _require(measurement["firstTokenMilliseconds"] is not None, f"{label}.complete first token is required")
            _require(measurement["peakMemoryBytes"] is not None, f"{label}.complete peak memory is required")
            _require(measurement["contextOverflow"] is not None, f"{label}.complete contextOverflow is required")
            if models[model_id]["artifactStatus"] != "available":
                _require(contract_example_only and measurement["measurementSource"] == "synthetic-contract", f"{label}.complete measurement requires an available artifact outside the synthetic contract")
        else:
            _require(measurement["latencyMilliseconds"] is None and measurement["firstTokenMilliseconds"] is None and measurement["peakMemoryBytes"] is None, f"{label}.non-complete measurement cannot carry runtime values")
        rows[key] = measurement
    expected_pairs = {(model_id, case_id, warm_state) for model_id in models for case_id in cases for warm_state in ("cold", "warm")}
    observed_pairs = {(model_id, case_id, warm_state) for model_id, case_id, warm_state, _sample in rows}
    _require(observed_pairs == expected_pairs, f"measurements must explicitly cover every model/case/warm pair; missing={sorted(expected_pairs - observed_pairs)}")
    return rows


def _nearest_rank(values: list[float], percentile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    rank = max(1, math.ceil(percentile * len(ordered)))
    return ordered[rank - 1]


def _percentiles(values: list[float]) -> dict[str, Any]:
    return {
        "sampleCount": len(values),
        "p50": _nearest_rank(values, 0.50),
        "p95": _nearest_rank(values, 0.95),
    }


def _target_density(text: str, target_language: str) -> float:
    visible = [char for char in text if not char.isspace()]
    if not visible:
        return 0.0
    if target_language == "zh-CN":
        count = sum("\u3400" <= char <= "\u9fff" or "\u3000" <= char <= "\u303f" for char in visible)
    else:
        count = sum("a" <= char.lower() <= "z" for char in visible)
    return count / len(visible)


def _quality_rows(cases: dict[str, dict[str, Any]], predictions: dict[tuple[str, str], dict[str, Any]], models: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for model_id in sorted(models):
        for source_language, target_language in LANGUAGE_PAIRS:
            selected_cases = [case for case in cases.values() if (case["sourceLanguage"], case["targetLanguage"]) == (source_language, target_language)]
            selected_predictions = [predictions[(model_id, case["caseID"])] for case in selected_cases]
            successful = [prediction for prediction in selected_predictions if prediction["status"] == "success"]
            densities = [
                _target_density(prediction["output"], target_language)
                for prediction in successful
                if prediction["output"]
            ]
            human_reference_cases = [case for case in selected_cases if case["referenceStatus"] == "human"]
            exact_matches = [
                prediction["output"] == case["referenceTranslation"]
                for case in human_reference_cases
                for prediction in [predictions[(model_id, case["caseID"])]]
                if prediction["status"] == "success"
            ]
            rows.append({
                "modelID": model_id,
                "languagePair": f"{source_language}->{target_language}",
                "caseCount": len(selected_cases),
                "successfulCount": len(successful),
                "emptyOrFailedCount": len(selected_cases) - len(successful),
                "contextOverflowCount": sum(prediction["contextOverflow"] for prediction in selected_predictions),
                "targetLanguageDensityMean": sum(densities) / len(densities) if densities else None,
                "humanReferenceCaseCount": len(human_reference_cases),
                "exactMatchRate": sum(exact_matches) / len(exact_matches) if exact_matches else None,
                "structuralGatePassed": all(prediction["status"] == "success" and not prediction["contextOverflow"] for prediction in selected_predictions),
            })
    return rows


def _runtime_rows(measurements: dict[tuple[str, str, str, int], dict[str, Any]], models: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for model_id in sorted(models):
        model_measurements = [row for key, row in measurements.items() if key[0] == model_id]
        by_warm_state: dict[str, dict[str, Any]] = {}
        for warm_state in ("cold", "warm"):
            selected = [row for row in model_measurements if row["warmState"] == warm_state]
            complete = [row for row in selected if row["status"] == "complete"]
            by_warm_state[warm_state] = {
                "latencyMilliseconds": _percentiles([float(row["latencyMilliseconds"]) for row in complete]),
                "firstTokenMilliseconds": _percentiles([float(row["firstTokenMilliseconds"]) for row in complete]),
                "sampleCount": len(selected),
                "completeSampleCount": len(complete),
            }
        overflow_values = [row["contextOverflow"] for row in model_measurements if row["contextOverflow"] is not None]
        complete_memory = [row["peakMemoryBytes"] for row in model_measurements if row["status"] == "complete" and row["peakMemoryBytes"] is not None]
        rows.append({
            "modelID": model_id,
            "byWarmState": by_warm_state,
            "contextOverflowCount": sum(value is True for value in overflow_values),
            "contextOverflowRate": sum(value is True for value in overflow_values) / len(overflow_values) if overflow_values else None,
            "peakMemoryBytesMax": max(complete_memory) if complete_memory else None,
            "targetDeviceSampleCount": sum(row["targetDevice"] for row in model_measurements),
            "completeSampleCount": sum(row["status"] == "complete" for row in model_measurements),
        })
    return rows


def evaluate(manifest: dict[str, Any], payload: dict[str, Any], *, manifest_path: Path, repo_root: Path = ROOT, verify_assets: bool = True) -> dict[str, Any]:
    manifest_info = _validate_manifest(manifest, manifest_path=manifest_path, repo_root=repo_root, verify_assets=verify_assets)
    _require(isinstance(payload, dict), "comparison input must be an object")
    _reject_unknown(payload, {"schemaVersion", "benchmark", "datasetSha256", "run", "corpus", "contractExampleOnly", "selection", "models", "predictions", "measurements"}, "comparison input")
    _require(payload.get("schemaVersion") == SCHEMA_VERSION, "unsupported comparison input schemaVersion")
    _require(payload.get("benchmark") == BENCHMARK, "comparison input benchmark is invalid")
    _require(payload.get("datasetSha256") == manifest_info["manifestSha256"], "comparison input datasetSha256 does not match manifest")
    _validate_run(payload.get("run"))
    corpus = payload.get("corpus")
    _require(isinstance(corpus, dict), "comparison input corpus must be an object")
    _reject_unknown(corpus, {"status", "manifestPath", "manifestSha256", "datasetVerified", "caseCount", "holdoutCaseCount", "humanReviewStatus"}, "comparison input corpus")
    for key in ("status", "manifestPath", "manifestSha256", "datasetVerified", "caseCount", "holdoutCaseCount", "humanReviewStatus"):
        _require(key in corpus, f"comparison input corpus missing {key}")
    _require(corpus["manifestSha256"] == manifest_info["manifestSha256"], "comparison input corpus manifestSha256 mismatch")
    _require(corpus["status"] == ("contractExampleOnly" if manifest_info["contractExampleOnly"] else "authorized"), "comparison corpus status mismatch")
    _require(corpus["caseCount"] == len(manifest_info["cases"]), "comparison corpus caseCount mismatch")
    _require(corpus["holdoutCaseCount"] == manifest_info["holdoutCaseCount"], "comparison corpus holdoutCaseCount mismatch")
    _require(isinstance(corpus["datasetVerified"], bool), "comparison corpus datasetVerified must be boolean")
    _require(corpus["datasetVerified"] is (not manifest_info["contractExampleOnly"]), "comparison corpus datasetVerified is unsafe")
    _require(corpus["humanReviewStatus"] in {"notStarted", "pending", "complete"}, "comparison corpus humanReviewStatus is invalid")
    contract_example_only = payload.get("contractExampleOnly")
    _require(isinstance(contract_example_only, bool) and contract_example_only == manifest_info["contractExampleOnly"], "contractExampleOnly mismatch")

    selection = payload.get("selection")
    _require(isinstance(selection, dict), "selection must be an object")
    _reject_unknown(selection, {"defaultModelID", "productSelectionChanged", "groundTruthUsedForSelection", "promotionStatus", "reason"}, "selection")
    for key in ("defaultModelID", "productSelectionChanged", "groundTruthUsedForSelection", "promotionStatus", "reason"):
        _require(key in selection, f"selection missing {key}")
    _string(selection["defaultModelID"], "selection.defaultModelID")
    _require(selection["productSelectionChanged"] is False, "productSelectionChanged must remain false")
    _require(selection["groundTruthUsedForSelection"] is False, "groundTruthUsedForSelection must remain false")
    _require(selection["promotionStatus"] == "notEligible", "selection.promotionStatus must be notEligible")
    _string(selection["reason"], "selection.reason")

    models = _validate_models(payload.get("models"), selection)
    predictions = _validate_predictions(payload.get("predictions"), manifest_info["cases"], models)
    measurements = _validate_measurements(payload.get("measurements"), manifest_info["cases"], models, contract_example_only)

    artifact_reasons: list[str] = []
    all_artifacts_available = all(model["artifactStatus"] == "available" for model in models.values())
    all_licenses_reviewed = all(model["licenseReviewed"] for model in models.values())
    has_authorized_corpus = corpus["status"] == "authorized" and corpus["datasetVerified"] is True
    has_complete_target_device_run = any(row["status"] == "complete" and row["targetDevice"] for row in measurements.values())
    resource_matrix_complete = all(
        any(row["status"] == "complete" and row["targetDevice"] for row in measurements.values() if row["modelID"] == model_id and row["warmState"] == warm_state)
        for model_id in models
        for warm_state in ("cold", "warm")
    )
    if not all_artifacts_available:
        artifact_reasons.append("one or more model artifacts are missing or not provided")
    if not all_licenses_reviewed:
        artifact_reasons.append("one or more model licenses are not reviewed")
    if not has_authorized_corpus:
        artifact_reasons.append("authorized clean-text corpus and verified holdout are not provided")
    if not has_complete_target_device_run:
        artifact_reasons.append("no complete target-device measurement is provided")
    if not resource_matrix_complete:
        artifact_reasons.append("cold/warm target-device resource matrix is incomplete")
    if contract_example_only:
        artifact_reasons.append("contractExampleOnly evidence cannot establish model quality")

    status = "blocked" if artifact_reasons else "success"
    quality_rows = _quality_rows(manifest_info["cases"], predictions, models)
    runtime_rows = _runtime_rows(measurements, models)
    floor_model = next(model for model in models.values() if model["comparisonRole"] == "floor")
    return {
        "schemaVersion": SCHEMA_VERSION,
        "benchmark": BENCHMARK,
        "status": status,
        "datasetSha256": manifest_info["manifestSha256"],
        "contractExampleOnly": contract_example_only,
        "corpus": {
            "status": corpus["status"],
            "caseCount": len(manifest_info["cases"]),
            "holdoutCaseCount": manifest_info["holdoutCaseCount"],
            "requiredLanguagePairs": [f"{source}->{target}" for source, target in manifest_info["requiredLanguagePairs"]],
            "humanReviewStatus": corpus["humanReviewStatus"],
            "cleanTextOnly": True,
            "ocrCorruptedExcluded": True,
        },
        "models": [
            {
                "modelID": model_id,
                "modelFamily": model["modelFamily"],
                "comparisonRole": model["comparisonRole"],
                "modelFilename": model["modelFilename"],
                "modelSha256": model["modelSha256"],
                "quantization": model["quantization"],
                "artifactStatus": model["artifactStatus"],
                "licenseReviewed": model["licenseReviewed"],
                "templateSource": model["template"]["source"],
                "decodingProfileID": model["decoding"]["profileID"],
                "contextLength": model["contextLength"],
                "referenceOnly": model["referenceOnly"],
                "defaultEnabled": model["defaultEnabled"],
            }
            for model_id, model in sorted(models.items())
        ],
        "quality": {
            "rows": quality_rows,
            "humanReviewRequired": True,
            "humanReviewDimensions": ["accuracy", "fluency", "characterVoice", "terminology", "omission", "bubbleFit"],
            "qualityMetricsAreNotSelectionInputs": True,
        },
        "runtime": {
            "percentileMethod": "nearest-rank: ceil(p*n), 1-indexed",
            "rows": runtime_rows,
        },
        "artifactGate": {
            "allArtifactsAvailable": all_artifacts_available,
            "allLicensesReviewed": all_licenses_reviewed,
            "hasAuthorizedCorpus": has_authorized_corpus,
            "hasCompleteTargetDeviceRun": has_complete_target_device_run,
            "resourceMatrixComplete": resource_matrix_complete,
            "reasons": sorted(set(artifact_reasons)),
        },
        "promotion": {
            "status": "notEligible",
            "reason": "comparison-only evidence never changes the product model selection",
            "groundTruthUsedForSelection": False,
            "productSelectionChanged": False,
            "defaultModelID": floor_model["modelID"],
            "defaultEnabledCandidateCount": 0,
            "requires": [
                "authorized clean-text corpus with human holdout",
                "real model/artifact/license identity",
                "cold and warm target-device measurements",
                "blind human translation review",
            ],
        },
        "qualityClaim": "Contract and structural comparison evidence only; no general translation quality or model-promotion claim.",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=ROOT)
    parser.add_argument("--skip-asset-verification", action="store_true")
    args = parser.parse_args(argv or sys.argv[1:])
    try:
        manifest = load_json(args.manifest)
        payload = load_json(args.input)
        report = evaluate(
            manifest,
            payload,
            manifest_path=args.manifest,
            repo_root=args.repo_root,
            verify_assets=not args.skip_asset_verification,
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
        return 0
    except (ModelComparisonError, OSError, TypeError, ValueError) as error:
        print(f"Japanese translation model comparison failed closed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
