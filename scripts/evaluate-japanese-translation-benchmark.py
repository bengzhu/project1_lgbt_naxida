#!/usr/bin/env python3
"""Validate and score the clean/corrupted Japanese translation benchmark.

Only deterministic structural QA is automated here.  Translation quality
claims require a separately recorded blind human evaluation.
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
BENCHMARK = "japanese-translation"
SPLITS = {"train", "dev", "holdout"}
INPUT_KINDS = {"cleanSource", "ocrCorrupted"}
HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
TAG_PATTERN = re.compile(r"\[([A-Za-z0-9][A-Za-z0-9._-]*)\]")


class BenchmarkError(ValueError):
    pass


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
        raise BenchmarkError(f"cannot read JSON {path}: {error}") from error


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise BenchmarkError(message)


def _reject_unknown(value: dict[str, Any], allowed: set[str], label: str) -> None:
    unknown = sorted(set(value) - allowed)
    _require(not unknown, f"{label} has unknown fields: {unknown}")


def _safe_input_path(manifest_path: Path, relative: str, repo_root: Path) -> Path:
    path = Path(relative)
    _require(not path.is_absolute(), f"input path must be relative: {relative!r}")
    resolved = (manifest_path.parent / path).resolve()
    root = repo_root.resolve()
    _require(resolved == root or root in resolved.parents, f"input path escapes repository: {relative!r}")
    return resolved


def _validate_input(
    input_data: dict[str, Any],
    fixture_id: str,
    manifest_path: Path | None,
    repo_root: Path,
    verify_assets: bool,
) -> None:
    _require(isinstance(input_data, dict), f"{fixture_id}.input must be an object")
    _reject_unknown(input_data, {"path", "sha256", "format", "license", "permittedUses"}, f"{fixture_id}.input")
    for key in ("path", "sha256", "format", "license", "permittedUses"):
        _require(key in input_data, f"{fixture_id}.input missing {key}")
    _require(isinstance(input_data["path"], str) and input_data["path"], f"{fixture_id}.input.path is empty")
    _require(bool(HEX64.fullmatch(str(input_data["sha256"]))), f"{fixture_id}.input.sha256 is invalid")
    _require(input_data["format"] in {"json", "txt"}, f"{fixture_id}.input.format is invalid")
    _require(isinstance(input_data["license"], str) and input_data["license"], f"{fixture_id}.input.license is empty")
    _require(isinstance(input_data["permittedUses"], list) and input_data["permittedUses"], f"{fixture_id}.input.permittedUses is empty")
    if not verify_assets:
        return
    _require(manifest_path is not None, "manifest_path is required when verifying inputs")
    path = _safe_input_path(manifest_path, input_data["path"], repo_root)
    _require(path.is_file(), f"translation fixture input is missing: {path}")
    actual = sha256_bytes(path.read_bytes())
    _require(actual == input_data["sha256"], f"input SHA mismatch for {fixture_id}: {actual} != {input_data['sha256']}")


def validate_manifest(
    manifest: dict[str, Any],
    *,
    manifest_path: Path | None = None,
    repo_root: Path = ROOT,
    verify_assets: bool = True,
) -> dict[str, Any]:
    _require(isinstance(manifest, dict), "translation manifest root must be an object")
    _reject_unknown(
        manifest,
        {"schemaVersion", "benchmark", "datasetVersion", "manifestSha256", "sourceLanguage", "targetLanguage", "fixtures"},
        "translation manifest",
    )
    _require(manifest.get("schemaVersion") == SCHEMA_VERSION, "unsupported translation manifest schemaVersion")
    _require(manifest.get("benchmark") == BENCHMARK, "manifest benchmark must be japanese-translation")
    _require(manifest.get("sourceLanguage") == "ja", "translation sourceLanguage must be ja")
    _require(manifest.get("targetLanguage") in {"zh-CN", "en"}, "unsupported translation targetLanguage")
    declared_hash = manifest.get("manifestSha256")
    _require(isinstance(declared_hash, str) and bool(HEX64.fullmatch(declared_hash)), "manifestSha256 is invalid")
    actual_hash = manifest_sha256(manifest)
    _require(declared_hash == actual_hash, f"manifest SHA mismatch: {actual_hash} != {declared_hash}")
    fixtures = manifest.get("fixtures")
    _require(isinstance(fixtures, list), "translation fixtures must be an array")
    by_id: dict[str, dict[str, Any]] = {}
    for fixture in fixtures:
        _require(isinstance(fixture, dict), "translation fixture must be an object")
        _reject_unknown(
            fixture,
            {"fixtureID", "split", "inputKind", "pairedFixtureID", "input", "annotationStatus", "exampleOnly", "blocks"},
            "translation fixture",
        )
        for key in ("fixtureID", "split", "inputKind", "pairedFixtureID", "input", "annotationStatus", "exampleOnly", "blocks"):
            _require(key in fixture, f"translation fixture missing {key}")
        fixture_id = fixture["fixtureID"]
        _require(isinstance(fixture_id, str) and fixture_id, "translation fixtureID is empty")
        _require(fixture_id not in by_id, f"duplicate translation fixtureID: {fixture_id}")
        _require(fixture["split"] in SPLITS, f"invalid translation split for {fixture_id}")
        _require(fixture["inputKind"] in INPUT_KINDS, f"invalid inputKind for {fixture_id}")
        _require(fixture["annotationStatus"] in {"human", "contractExampleOnly", "pending"}, f"invalid annotationStatus for {fixture_id}")
        _require(isinstance(fixture["exampleOnly"], bool), f"exampleOnly must be boolean for {fixture_id}")
        if fixture["exampleOnly"]:
            _require(fixture["annotationStatus"] == "contractExampleOnly", f"exampleOnly fixture must be contractExampleOnly: {fixture_id}")
        _validate_input(fixture["input"], fixture_id, manifest_path, repo_root, verify_assets)
        blocks = fixture["blocks"]
        _require(isinstance(blocks, list) and blocks, f"empty translation ground truth: {fixture_id}")
        block_ids: set[str] = set()
        orders: set[int] = set()
        for block in blocks:
            _require(isinstance(block, dict), f"translation block must be an object: {fixture_id}")
            _reject_unknown(
                block,
                {"blockID", "order", "sourceText", "sourceTextNFC", "textType", "referenceTranslation", "maxTranslationCharacters"},
                f"translation block {fixture_id}",
            )
            for key in ("blockID", "order", "sourceText", "sourceTextNFC", "textType"):
                _require(key in block, f"translation block missing {key}: {fixture_id}")
            block_id = block["blockID"]
            _require(isinstance(block_id, str) and block_id and block_id not in block_ids, f"duplicate blockID: {fixture_id}/{block_id}")
            block_ids.add(block_id)
            order = block["order"]
            _require(isinstance(order, int) and order >= 0 and order not in orders, f"invalid/duplicate block order: {fixture_id}/{block_id}")
            orders.add(order)
            source_text = block["sourceText"]
            _require(isinstance(source_text, str) and source_text, f"empty source text: {fixture_id}/{block_id}")
            _require(block["sourceTextNFC"] == unicodedata.normalize("NFC", source_text), f"sourceTextNFC mismatch: {fixture_id}/{block_id}")
            _require(block["textType"] in {"dialogue", "narration", "SFX", "title", "other"}, f"invalid textType: {fixture_id}/{block_id}")
            if "maxTranslationCharacters" in block:
                _require(isinstance(block["maxTranslationCharacters"], int) and block["maxTranslationCharacters"] > 0, f"invalid maxTranslationCharacters: {fixture_id}/{block_id}")
        by_id[fixture_id] = fixture
    for fixture_id, fixture in by_id.items():
        paired_id = fixture["pairedFixtureID"]
        _require(paired_id in by_id, f"missing translation pair {paired_id} for {fixture_id}")
        paired = by_id[paired_id]
        _require(paired["pairedFixtureID"] == fixture_id, f"translation pair is not reciprocal: {fixture_id}")
        _require(paired["inputKind"] != fixture["inputKind"], f"translation pair must contain clean and corrupted inputs: {fixture_id}")
        _require(paired["split"] == fixture["split"], f"translation pair split mismatch: {fixture_id}")
    return {"fixtures": by_id, "manifestSha256": declared_hash}


def _validate_run(run: Any) -> None:
    _require(isinstance(run, dict), "translation run must be an object")
    _reject_unknown(
        run,
        {"appSha", "engineID", "engineVersion", "model", "provider", "promptTemplate", "decoding", "license", "device"},
        "translation run",
    )
    for key in ("appSha", "engineID", "engineVersion", "model", "provider", "promptTemplate", "decoding", "license", "device"):
        _require(key in run, f"translation run missing {key}")
    _require(isinstance(run["appSha"], str) and bool(HEX40.fullmatch(run["appSha"])), "translation run.appSha is invalid")
    for key in ("engineID", "engineVersion", "model", "provider", "promptTemplate", "license", "device"):
        _require(isinstance(run[key], str) and run[key], f"translation run.{key} is empty")
    _require(isinstance(run["decoding"], dict), "translation run.decoding must be an object")


def _validate_predictions(
    payload: dict[str, Any],
    manifest_info: dict[str, Any],
    *,
    split: str | None,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    _require(isinstance(payload, dict), "translation prediction root must be an object")
    _reject_unknown(
        payload,
        {"schemaVersion", "benchmark", "datasetSha256", "run", "predictions"},
        "translation prediction root",
    )
    _require(payload.get("schemaVersion") == SCHEMA_VERSION, "unsupported translation prediction schemaVersion")
    _require(payload.get("benchmark") == BENCHMARK, "prediction benchmark must be japanese-translation")
    _require(payload.get("datasetSha256") == manifest_info["manifestSha256"], "translation prediction dataset SHA mismatch")
    _validate_run(payload.get("run"))
    predictions = payload.get("predictions")
    _require(isinstance(predictions, list), "translation predictions must be an array")
    fixtures = manifest_info["fixtures"]
    selected = {fixture_id: fixture for fixture_id, fixture in fixtures.items() if split is None or fixture["split"] == split}
    _require(split is None or split in SPLITS, f"invalid requested split: {split}")
    seen_ids: set[str] = set()
    seen_fixtures: set[str] = set()
    for index, prediction in enumerate(predictions):
        _require(isinstance(prediction, dict), f"translation prediction[{index}] must be an object")
        _reject_unknown(
            prediction,
            {"predictionID", "fixtureID", "split", "engineID", "model", "provider", "promptTemplate", "decoding", "rawResponse"},
            f"translation prediction[{index}]",
        )
        for key in ("predictionID", "fixtureID", "split", "engineID", "model", "provider", "promptTemplate", "decoding", "rawResponse"):
            _require(key in prediction, f"translation prediction[{index}] missing {key}")
        prediction_id = prediction["predictionID"]
        _require(isinstance(prediction_id, str) and prediction_id and prediction_id not in seen_ids, f"duplicate/empty translation predictionID: {prediction_id}")
        seen_ids.add(prediction_id)
        fixture_id = prediction["fixtureID"]
        _require(fixture_id in selected, f"translation prediction crosses requested split or references unknown fixture: {fixture_id}")
        _require(prediction["split"] == selected[fixture_id]["split"], f"translation prediction split mismatch: {fixture_id}")
        _require(fixture_id not in seen_fixtures, f"duplicate translation prediction for fixture: {fixture_id}")
        seen_fixtures.add(fixture_id)
        for key in ("engineID", "model", "provider", "promptTemplate"):
            _require(isinstance(prediction[key], str) and prediction[key], f"translation prediction.{key} is empty: {prediction_id}")
        _require(isinstance(prediction["decoding"], dict), f"translation prediction.decoding must be an object: {prediction_id}")
        _require(isinstance(prediction["rawResponse"], str), f"translation rawResponse must be a string: {prediction_id}")
    _require(set(selected) == seen_fixtures, f"missing translation prediction rows: {sorted(set(selected) - seen_fixtures)}")
    return predictions, {"selectedFixtures": selected, "predictionSha256": json_sha256(payload)}


def _target_density(text: str, target_language: str) -> float:
    visible = [char for char in text if not char.isspace()]
    if not visible:
        return 0.0
    if target_language == "zh-CN":
        count = sum("\u3400" <= char <= "\u9fff" or "\u3000" <= char <= "\u303f" for char in visible)
    else:
        count = sum(("a" <= char.lower() <= "z") for char in visible)
    return count / len(visible)


def _is_shared_han_only_japanese_source(value: str) -> bool:
    visible = [
        character
        for character in value
        if not character.isspace() and not unicodedata.category(character).startswith("P")
    ]
    if not visible:
        return False
    return all(
        "\u3400" <= character <= "\u4dbf"
        or "\u4e00" <= character <= "\u9fff"
        or "\uf900" <= character <= "\ufaff"
        for character in visible
    )


def _source_leakage(
    source: str,
    output: str,
    source_language: str,
    target_language: str,
) -> bool:
    normalized_source = unicodedata.normalize("NFC", source)
    if not output or not (
        output == source
        or output == normalized_source
        or normalized_source in output
    ):
        return False
    if (
        source_language == "ja"
        and target_language == "zh-CN"
        and _is_shared_han_only_japanese_source(source)
    ):
        return False
    return True


def _parse_tagged_response(response: str) -> tuple[list[tuple[str, str]], list[str]]:
    matches = list(TAG_PATTERN.finditer(response))
    prefix = response[: matches[0].start()].strip() if matches else response.strip()
    rows: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(response)
        rows.append((match.group(1), response[match.end():end].strip()))
    return rows, (["prefixText"] if prefix else [])


def _evaluate_prediction(
    fixture: dict[str, Any],
    prediction: dict[str, Any],
    source_language: str,
    target_language: str,
) -> dict[str, Any]:
    expected_blocks = sorted(fixture["blocks"], key=lambda block: (block["order"], block["blockID"]))
    expected_ids = [block["blockID"] for block in expected_blocks]
    parsed, parser_failures = _parse_tagged_response(prediction["rawResponse"])
    actual_ids = [block_id for block_id, _text in parsed]
    missing = sorted(set(expected_ids) - set(actual_ids))
    extra = sorted(set(actual_ids) - set(expected_ids))
    duplicates = sorted({block_id for block_id in actual_ids if actual_ids.count(block_id) > 1})
    out_of_order = actual_ids != [block_id for block_id in expected_ids if block_id in actual_ids] or any(block_id not in expected_ids for block_id in actual_ids)
    parsed_by_id: dict[str, list[str]] = {}
    for block_id, text in parsed:
        parsed_by_id.setdefault(block_id, []).append(text)
    block_rows: list[dict[str, Any]] = []
    source_leakage = 0
    target_densities: list[float] = []
    length_violations = 0
    for block in expected_blocks:
        block_id = block["blockID"]
        texts = parsed_by_id.get(block_id, [])
        text = texts[0] if texts else ""
        leaked = _source_leakage(
            block["sourceText"],
            text,
            source_language,
            target_language,
        )
        if leaked:
            source_leakage += 1
        density = _target_density(text, target_language)
        if text:
            target_densities.append(density)
        max_length = block.get("maxTranslationCharacters")
        too_long = max_length is not None and len(text) > max_length
        length_violations += too_long
        block_rows.append({
            "blockID": block_id,
            "present": bool(texts),
            "text": text,
            "sourceLeakage": leaked,
            "targetLanguageDensity": density,
            "lengthViolation": too_long,
        })
    target_density_threshold = 0.25
    low_density = sum(row["present"] and not row["sourceLeakage"] and row["targetLanguageDensity"] < target_density_threshold for row in block_rows)
    failures = sorted(set(parser_failures + ["missingTag"] * bool(missing) + ["extraTag"] * bool(extra) + ["duplicateTag"] * bool(duplicates) + ["outOfOrderTag"] * out_of_order + ["sourceLeakage"] * bool(source_leakage) + ["lowTargetLanguageDensity"] * bool(low_density) + ["lengthViolation"] * bool(length_violations)))
    return {
        "fixtureID": fixture["fixtureID"],
        "inputKind": fixture["inputKind"],
        "expectedBlockCount": len(expected_ids),
        "parsedBlockCount": len(parsed),
        "missingTags": missing,
        "extraTags": extra,
        "duplicateTags": duplicates,
        "outOfOrder": out_of_order,
        "sourceLeakageCount": source_leakage,
        "lowTargetLanguageDensityCount": low_density,
        "lengthViolationCount": length_violations,
        "targetLanguageDensityMean": sum(target_densities) / len(target_densities) if target_densities else 0.0,
        "tagComplete": not missing and not extra and not duplicates and not out_of_order,
        "hardGatePassed": not failures,
        "failures": failures,
        "blocks": block_rows,
    }


def score(
    manifest: dict[str, Any],
    predictions_payload: dict[str, Any],
    *,
    split: str | None = None,
    manifest_path: Path | None = None,
    repo_root: Path = ROOT,
    verify_assets: bool = True,
) -> dict[str, Any]:
    manifest_info = validate_manifest(manifest, manifest_path=manifest_path, repo_root=repo_root, verify_assets=verify_assets)
    predictions, prediction_info = _validate_predictions(predictions_payload, manifest_info, split=split)
    selected = prediction_info["selectedFixtures"]
    rows = [
        _evaluate_prediction(
            selected[prediction["fixtureID"]],
            prediction,
            manifest["sourceLanguage"],
            manifest["targetLanguage"],
        )
        for prediction in predictions
    ]
    rows = sorted(rows, key=lambda row: row["fixtureID"])
    by_kind: dict[str, list[dict[str, Any]]] = {"cleanSource": [], "ocrCorrupted": []}
    for row in rows:
        by_kind[row["inputKind"]].append(row)

    def kind_summary(kind_rows: list[dict[str, Any]]) -> dict[str, Any]:
        if not kind_rows:
            return {"fixtureCount": 0, "hardGatePassRate": None, "tagCompleteRate": None, "meanTargetLanguageDensity": None, "sourceLeakageCount": 0, "missingTagCount": 0, "extraTagCount": 0, "duplicateTagCount": 0, "outOfOrderCount": 0, "lengthViolationCount": 0}
        return {
            "fixtureCount": len(kind_rows),
            "hardGatePassRate": sum(row["hardGatePassed"] for row in kind_rows) / len(kind_rows),
            "tagCompleteRate": sum(row["tagComplete"] for row in kind_rows) / len(kind_rows),
            "meanTargetLanguageDensity": sum(row["targetLanguageDensityMean"] for row in kind_rows) / len(kind_rows),
            "sourceLeakageCount": sum(row["sourceLeakageCount"] for row in kind_rows),
            "missingTagCount": sum(bool(row["missingTags"]) for row in kind_rows),
            "extraTagCount": sum(bool(row["extraTags"]) for row in kind_rows),
            "duplicateTagCount": sum(bool(row["duplicateTags"]) for row in kind_rows),
            "outOfOrderCount": sum(row["outOfOrder"] for row in kind_rows),
            "lengthViolationCount": sum(row["lengthViolationCount"] for row in kind_rows),
        }

    failures = [
        {"fixtureID": row["fixtureID"], "inputKind": row["inputKind"], "kind": failure}
        for row in rows
        for failure in row["failures"]
    ]
    failures.sort(key=lambda item: (item["fixtureID"], item["kind"]))
    return {
        "schemaVersion": SCHEMA_VERSION,
        "benchmark": BENCHMARK,
        "status": "success",
        "datasetSha256": manifest_info["manifestSha256"],
        "predictionSha256": prediction_info["predictionSha256"],
        "config": {
            "split": split or "all",
            "targetLanguage": manifest["targetLanguage"],
            "targetLanguageDensityThreshold": 0.25,
            "evaluatedFixtureIDs": sorted(selected),
        },
        "counts": {
            "fixtures": len(rows),
            "blocks": sum(row["expectedBlockCount"] for row in rows),
            "hardGateFailures": len(failures),
        },
        "metrics": {
            "all": kind_summary(rows),
            "byInputKind": {kind: kind_summary(kind_rows) for kind, kind_rows in by_kind.items()},
            "humanReviewRequired": True,
            "humanReviewDimensions": ["accuracy", "fluency", "characterVoice", "terminology", "omission", "bubbleFit"],
        },
        "failures": failures,
        "qualityClaim": "Structural translation QA only; accuracy and fluency require blind human review.",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--predictions", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--split", choices=sorted(SPLITS))
    parser.add_argument("--repo-root", type=Path, default=ROOT)
    parser.add_argument("--skip-asset-verification", action="store_true")
    args = parser.parse_args(argv or sys.argv[1:])
    try:
        manifest = load_json(args.manifest)
        predictions = load_json(args.predictions)
        report = score(
            manifest,
            predictions,
            split=args.split,
            manifest_path=args.manifest,
            repo_root=args.repo_root,
            verify_assets=not args.skip_asset_verification,
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
        return 0
    except (BenchmarkError, OSError, TypeError, ValueError) as error:
        print(f"Japanese translation benchmark failed closed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
