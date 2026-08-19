#!/usr/bin/env python3
"""Validate and score the repository-level Japanese OCR benchmark.

This module intentionally uses only the Python standard library.  It is an
offline scorer, never an app/runtime entry point, and it must not be imported
by the AITRANS target.  Ground truth is used here only for reporting metrics;
the production OCR candidate selector has no path to this directory.
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
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_VERSION = "1.0.0"
BENCHMARK = "japanese-ocr"
SPLITS = {"train", "dev", "holdout"}
EVALUATION_LEVELS = {"oracleCrop", "detectedCrop", "fullPage"}
HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX40 = re.compile(r"^[0-9a-f]{40}$")


class BenchmarkError(ValueError):
    """A fail-closed benchmark input or scoring error."""


def canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


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


def _finite_number(value: Any, label: str) -> float:
    _require(isinstance(value, (int, float)) and not isinstance(value, bool), f"{label} must be a number")
    result = float(value)
    _require(math.isfinite(result), f"{label} must be finite")
    return result


def validate_normalized_bbox(value: Any, label: str) -> tuple[float, float, float, float]:
    _require(isinstance(value, list) and len(value) == 4, f"{label} must be [x,y,width,height]")
    x, y, width, height = (_finite_number(item, f"{label}[{index}]") for index, item in enumerate(value))
    _require(0.0 <= x <= 1.0 and 0.0 <= y <= 1.0, f"{label} origin is outside normalized bounds")
    _require(width > 0.0 and height > 0.0, f"{label} must be non-degenerate")
    _require(x + width <= 1.0 and y + height <= 1.0, f"{label} exceeds normalized bounds")
    return x, y, width, height


def _orientation(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _on_segment(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> bool:
    epsilon = 1e-12
    return (
        min(a[0], c[0]) - epsilon <= b[0] <= max(a[0], c[0]) + epsilon
        and min(a[1], c[1]) - epsilon <= b[1] <= max(a[1], c[1]) + epsilon
    )


def _segments_intersect(
    a: tuple[float, float],
    b: tuple[float, float],
    c: tuple[float, float],
    d: tuple[float, float],
) -> bool:
    epsilon = 1e-12
    ab_c = _orientation(a, b, c)
    ab_d = _orientation(a, b, d)
    cd_a = _orientation(c, d, a)
    cd_b = _orientation(c, d, b)
    if abs(ab_c) <= epsilon and _on_segment(a, c, b):
        return True
    if abs(ab_d) <= epsilon and _on_segment(a, d, b):
        return True
    if abs(cd_a) <= epsilon and _on_segment(c, a, d):
        return True
    if abs(cd_b) <= epsilon and _on_segment(c, b, d):
        return True
    return (ab_c > 0) != (ab_d > 0) and (cd_a > 0) != (cd_b > 0)


def validate_polygon(value: Any, label: str) -> list[tuple[float, float]]:
    _require(isinstance(value, list) and len(value) >= 3, f"{label} needs at least three points")
    points: list[tuple[float, float]] = []
    for index, point in enumerate(value):
        _require(isinstance(point, list) and len(point) == 2, f"{label}[{index}] must be [x,y]")
        x = _finite_number(point[0], f"{label}[{index}][0]")
        y = _finite_number(point[1], f"{label}[{index}][1]")
        _require(0.0 <= x <= 1.0 and 0.0 <= y <= 1.0, f"{label}[{index}] is outside normalized bounds")
        points.append((x, y))
    area = sum(
        points[index][0] * points[(index + 1) % len(points)][1]
        - points[(index + 1) % len(points)][0] * points[index][1]
        for index in range(len(points))
    ) / 2.0
    _require(abs(area) > 1e-12, f"{label} is degenerate")
    for first in range(len(points)):
        first_next = (first + 1) % len(points)
        for second in range(first + 1, len(points)):
            second_next = (second + 1) % len(points)
            if first == second or first_next == second or second_next == first:
                continue
            _require(
                not _segments_intersect(
                    points[first], points[first_next], points[second], points[second_next]
                ),
                f"{label} self-intersects",
            )
    return points


def _safe_asset_path(manifest_path: Path, relative: str, repo_root: Path) -> Path:
    path = Path(relative)
    _require(not path.is_absolute(), f"asset path must be relative: {relative!r}")
    resolved = (manifest_path.parent / path).resolve()
    root = repo_root.resolve()
    _require(resolved == root or root in resolved.parents, f"asset path escapes repository: {relative!r}")
    return resolved


def _validate_asset(
    asset: dict[str, Any],
    fixture_id: str,
    manifest_path: Path | None,
    repo_root: Path,
    verify_assets: bool,
) -> None:
    _require(isinstance(asset, dict), f"{fixture_id}.asset must be an object")
    _reject_unknown(
        asset,
        {"path", "sha256", "width", "height", "source", "license", "permittedUses"},
        f"{fixture_id}.asset",
    )
    required = ("path", "sha256", "width", "height", "source", "license", "permittedUses")
    for key in required:
        _require(key in asset, f"{fixture_id}.asset missing {key}")
    _require(isinstance(asset["path"], str) and asset["path"], f"{fixture_id}.asset.path is empty")
    _require(bool(HEX64.fullmatch(str(asset["sha256"]))), f"{fixture_id}.asset.sha256 is invalid")
    for dimension in ("width", "height"):
        _require(isinstance(asset[dimension], int) and asset[dimension] > 0, f"{fixture_id}.asset.{dimension} is invalid")
    _require(isinstance(asset["source"], str) and asset["source"], f"{fixture_id}.asset.source is empty")
    _require(isinstance(asset["license"], str) and asset["license"], f"{fixture_id}.asset.license is empty")
    _require(
        isinstance(asset["permittedUses"], list) and asset["permittedUses"]
        and all(isinstance(item, str) and item for item in asset["permittedUses"]),
        f"{fixture_id}.asset.permittedUses is invalid",
    )
    if not verify_assets:
        return
    _require(manifest_path is not None, "manifest_path is required when verifying assets")
    path = _safe_asset_path(manifest_path, asset["path"], repo_root)
    _require(path.is_file(), f"fixture asset is missing: {path}")
    actual = sha256_bytes(path.read_bytes())
    _require(actual == asset["sha256"], f"asset SHA mismatch for {fixture_id}: {actual} != {asset['sha256']}")


def _validate_region(region: dict[str, Any], page_id: str, seen_reading_orders: set[int]) -> None:
    _reject_unknown(
        region,
        {"regionID", "bbox", "polygon", "bubbleID", "linePolygons", "sourceText", "sourceTextNFC", "writingDirection", "readingOrder", "textType", "tags"},
        f"{page_id} region",
    )
    required = (
        "regionID", "bbox", "polygon", "sourceText", "sourceTextNFC",
        "writingDirection", "readingOrder", "textType", "tags",
    )
    for key in required:
        _require(key in region, f"{page_id} region missing {key}")
    region_id = region["regionID"]
    _require(isinstance(region_id, str) and region_id, f"{page_id} has empty regionID")
    validate_normalized_bbox(region["bbox"], f"{page_id}/{region_id}.bbox")
    validate_polygon(region["polygon"], f"{page_id}/{region_id}.polygon")
    for line_index, polygon in enumerate(region.get("linePolygons", [])):
        validate_polygon(polygon, f"{page_id}/{region_id}.linePolygons[{line_index}]")
    source_text = region["sourceText"]
    _require(isinstance(source_text, str) and source_text != "", f"{page_id}/{region_id} sourceText is empty")
    _require(
        region["sourceTextNFC"] == unicodedata.normalize("NFC", source_text),
        f"{page_id}/{region_id} sourceTextNFC mismatch",
    )
    _require(region["writingDirection"] in {"vertical", "horizontal", "mixed", "unknown"}, f"{page_id}/{region_id} writingDirection invalid")
    order = region["readingOrder"]
    _require(isinstance(order, int) and order >= 0, f"{page_id}/{region_id} readingOrder invalid")
    _require(order not in seen_reading_orders, f"duplicate readingOrder on {page_id}: {order}")
    seen_reading_orders.add(order)
    _require(region["textType"] in {"dialogue", "narration", "SFX", "title", "other"}, f"{page_id}/{region_id} textType invalid")
    tags = region["tags"]
    _require(isinstance(tags, list) and all(isinstance(tag, str) and tag for tag in tags), f"{page_id}/{region_id} tags invalid")
    _require(len(tags) == len(set(tags)), f"duplicate tags on {page_id}/{region_id}")


def validate_manifest(
    manifest: dict[str, Any],
    *,
    manifest_path: Path | None = None,
    repo_root: Path = ROOT,
    verify_assets: bool = True,
) -> dict[str, Any]:
    _require(isinstance(manifest, dict), "manifest root must be an object")
    _reject_unknown(
        manifest,
        {"schemaVersion", "benchmark", "datasetVersion", "manifestSha256", "coordinateSpace", "fixtures"},
        "manifest",
    )
    _require(manifest.get("schemaVersion") == SCHEMA_VERSION, "unsupported OCR manifest schemaVersion")
    _require(manifest.get("benchmark") == BENCHMARK, "manifest benchmark must be japanese-ocr")
    _require(isinstance(manifest.get("datasetVersion"), str) and manifest["datasetVersion"], "datasetVersion is required")
    declared_hash = manifest.get("manifestSha256")
    _require(isinstance(declared_hash, str) and bool(HEX64.fullmatch(declared_hash)), "manifestSha256 is invalid")
    actual_hash = manifest_sha256(manifest)
    _require(declared_hash == actual_hash, f"manifest SHA mismatch: {actual_hash} != {declared_hash}")
    _require(manifest.get("coordinateSpace") == "normalizedTopLeft", "unsupported coordinateSpace")
    fixtures = manifest.get("fixtures")
    _require(isinstance(fixtures, list), "fixtures must be an array")
    pages: dict[str, dict[str, Any]] = {}
    all_region_ids: set[str] = set()
    for fixture in fixtures:
        _require(isinstance(fixture, dict), "fixture must be an object")
        _reject_unknown(
            fixture,
            {"pageID", "split", "asset", "annotationStatus", "legacyRegression", "exampleOnly", "regions", "oracleCrops"},
            "fixture",
        )
        for key in ("pageID", "split", "asset", "annotationStatus", "legacyRegression", "regions"):
            _require(key in fixture, f"fixture missing {key}")
        page_id = fixture["pageID"]
        _require(isinstance(page_id, str) and page_id, "fixture pageID is empty")
        _require(page_id not in pages, f"duplicate pageID: {page_id}")
        _require(fixture["split"] in SPLITS, f"invalid split for {page_id}")
        _require(fixture["annotationStatus"] in {"human", "contractExampleOnly", "legacyRegressionOnly", "pending"}, f"invalid annotationStatus for {page_id}")
        _require(isinstance(fixture["legacyRegression"], bool), f"legacyRegression must be boolean for {page_id}")
        if fixture["legacyRegression"]:
            _require(fixture["annotationStatus"] == "legacyRegressionOnly", f"legacy fixture must be marked legacyRegressionOnly: {page_id}")
        if fixture.get("exampleOnly"):
            _require(fixture["annotationStatus"] == "contractExampleOnly", f"exampleOnly fixture must be contractExampleOnly: {page_id}")
        _validate_asset(fixture["asset"], page_id, manifest_path, repo_root, verify_assets)
        regions = fixture["regions"]
        _require(isinstance(regions, list), f"regions must be an array for {page_id}")
        if not regions:
            _require(
                fixture["legacyRegression"] or fixture["annotationStatus"] in {"pending", "contractExampleOnly"},
                f"empty ground truth is not allowed for non-legacy fixture: {page_id}",
            )
        seen_page_region_ids: set[str] = set()
        seen_orders: set[int] = set()
        for region in regions:
            _require(isinstance(region, dict), f"region must be an object on {page_id}")
            region_id = region.get("regionID")
            _require(region_id not in seen_page_region_ids, f"duplicate regionID on {page_id}: {region_id}")
            _require(region_id not in all_region_ids, f"duplicate regionID across manifest: {region_id}")
            _validate_region(region, page_id, seen_orders)
            seen_page_region_ids.add(region_id)
            all_region_ids.add(region_id)
        crop_ids: set[str] = set()
        for crop in fixture.get("oracleCrops", []):
            _require(isinstance(crop, dict), f"oracle crop must be an object on {page_id}")
            _reject_unknown(crop, {"cropID", "pixelBBox", "expectedText", "expectedTextNFC", "referenceOnly"}, f"{page_id} oracle crop")
            for key in ("cropID", "pixelBBox", "expectedText", "expectedTextNFC", "referenceOnly"):
                _require(key in crop, f"oracle crop missing {key} on {page_id}")
            crop_id = crop["cropID"]
            _require(isinstance(crop_id, str) and crop_id and crop_id not in crop_ids, f"duplicate oracle crop ID on {page_id}: {crop_id}")
            crop_ids.add(crop_id)
            bbox = crop["pixelBBox"]
            _require(isinstance(bbox, list) and len(bbox) == 4 and all(isinstance(item, int) for item in bbox), f"invalid oracle crop bbox: {page_id}/{crop_id}")
            x, y, width, height = bbox
            _require(width > 0 and height > 0 and x + width <= fixture["asset"]["width"] and y + height <= fixture["asset"]["height"], f"oracle crop exceeds asset: {page_id}/{crop_id}")
            _require(isinstance(crop["expectedText"], str) and crop["expectedText"], f"oracle crop text is empty: {page_id}/{crop_id}")
            _require(crop["expectedTextNFC"] == unicodedata.normalize("NFC", crop["expectedText"]), f"oracle crop NFC mismatch: {page_id}/{crop_id}")
            _require(crop["referenceOnly"] is True, f"oracle crop must remain referenceOnly: {page_id}/{crop_id}")
        pages[page_id] = fixture
    return {"pages": pages, "regions": all_region_ids, "manifestSha256": declared_hash}


def _validate_run(run: Any) -> None:
    _require(isinstance(run, dict), "prediction run must be an object")
    _reject_unknown(
        run,
        {"appSha", "engineID", "engineVersion", "model", "license", "device", "parameters"},
        "prediction run",
    )
    for key in ("appSha", "engineID", "engineVersion", "model", "license", "device", "parameters"):
        _require(key in run, f"prediction run missing {key}")
    _require(isinstance(run["appSha"], str) and bool(HEX40.fullmatch(run["appSha"])), "run.appSha must be a 40-digit lowercase SHA")
    _require(isinstance(run["engineID"], str) and run["engineID"], "run.engineID is empty")
    _require(isinstance(run["engineVersion"], str) and run["engineVersion"], "run.engineVersion is empty")
    _require(isinstance(run["license"], str) and run["license"], "run.license is empty")
    _require(isinstance(run["device"], str) and run["device"], "run.device is empty")
    _require(isinstance(run["parameters"], dict), "run.parameters must be an object")
    model = run["model"]
    _require(isinstance(model, dict), "run.model must be an object")
    _reject_unknown(model, {"id", "version", "sha256", "license"}, "run.model")
    for key in ("id", "version", "sha256", "license"):
        _require(key in model, f"run.model missing {key}")
    _require(isinstance(model["id"], str) and model["id"], "run.model.id is empty")
    _require(isinstance(model["version"], str) and model["version"], "run.model.version is empty")
    _require(isinstance(model["sha256"], str) and bool(HEX64.fullmatch(model["sha256"])), "run.model.sha256 is invalid")
    _require(isinstance(model["license"], str) and model["license"], "run.model.license is empty")


def _validate_prediction(prediction: dict[str, Any], index: int, page: dict[str, Any]) -> None:
    _reject_unknown(
        prediction,
        {"predictionID", "pageID", "split", "evaluationLevel", "regionID", "lineID", "status", "text", "rawText", "confidence", "bbox", "polygon", "writingDirection", "readingOrder", "engine", "cropVariant", "referenceOnly", "failureReason"},
        f"prediction[{index}]",
    )
    required = (
        "predictionID", "pageID", "split", "evaluationLevel", "regionID", "status",
        "text", "confidence", "bbox", "readingOrder", "engine", "cropVariant", "referenceOnly",
    )
    for key in required:
        _require(key in prediction, f"prediction[{index}] missing {key}")
    _require(isinstance(prediction["predictionID"], str) and prediction["predictionID"], f"prediction[{index}] predictionID is empty")
    _require(prediction["split"] == page["split"], f"prediction split does not match page {prediction['pageID']}")
    _require(prediction["evaluationLevel"] in EVALUATION_LEVELS, f"invalid evaluationLevel in prediction[{index}]")
    _require(prediction["status"] in {"success", "empty", "failure"}, f"invalid prediction status in prediction[{index}]")
    _require(isinstance(prediction["text"], str), f"prediction[{index}].text must be a string")
    if prediction["status"] in {"empty", "failure"}:
        _require(prediction["text"] == "", f"{prediction['status']} prediction must have empty text: {prediction['predictionID']}")
        _require(isinstance(prediction.get("failureReason"), str) and prediction["failureReason"], f"{prediction['status']} prediction needs failureReason: {prediction['predictionID']}")
    else:
        _require(prediction["text"].strip() != "", f"success prediction has empty text: {prediction['predictionID']}")
    confidence = prediction["confidence"]
    if confidence is not None:
        value = _finite_number(confidence, f"prediction[{index}].confidence")
        _require(0.0 <= value <= 1.0, f"prediction[{index}].confidence is outside [0,1]")
    if prediction["bbox"] is not None:
        validate_normalized_bbox(prediction["bbox"], f"prediction[{index}].bbox")
    if prediction.get("polygon") is not None:
        validate_polygon(prediction["polygon"], f"prediction[{index}].polygon")
    if prediction["readingOrder"] is not None:
        _require(isinstance(prediction["readingOrder"], int) and prediction["readingOrder"] >= 0, f"prediction[{index}].readingOrder is invalid")
    _require(isinstance(prediction["engine"], str) and prediction["engine"], f"prediction[{index}].engine is empty")
    _require(isinstance(prediction["cropVariant"], str) and prediction["cropVariant"], f"prediction[{index}].cropVariant is empty")
    _require(isinstance(prediction["referenceOnly"], bool), f"prediction[{index}].referenceOnly is invalid")
    if prediction["engine"].startswith("koharu-mit48"):
        _require(prediction["referenceOnly"] is True, "Koharu MIT48 predictions must be referenceOnly")
    region_ids = {region["regionID"] for region in page["regions"]}
    region_id = prediction["regionID"]
    _require(region_id is None or region_id in region_ids, f"prediction references unknown regionID: {region_id}")


def validate_predictions(
    payload: dict[str, Any],
    manifest: dict[str, Any],
    manifest_info: dict[str, Any],
    *,
    split: str | None = None,
) -> dict[str, Any]:
    _require(isinstance(payload, dict), "prediction root must be an object")
    _reject_unknown(
        payload,
        {"schemaVersion", "benchmark", "datasetSha256", "run", "predictions"},
        "prediction root",
    )
    _require(payload.get("schemaVersion") == SCHEMA_VERSION, "unsupported OCR prediction schemaVersion")
    _require(payload.get("benchmark") == BENCHMARK, "prediction benchmark must be japanese-ocr")
    _require(payload.get("datasetSha256") == manifest_info["manifestSha256"], "prediction dataset SHA does not match manifest")
    _validate_run(payload.get("run"))
    predictions = payload.get("predictions")
    _require(isinstance(predictions, list), "predictions must be an array")
    levels = {prediction.get("evaluationLevel") for prediction in predictions if isinstance(prediction, dict)}
    _require(len(levels - {None}) <= 1, "oracleCrop, detectedCrop, and fullPage levels cannot be mixed")
    evaluation_level = next(iter(levels - {None}), None)
    pages = manifest_info["pages"]
    seen_ids: set[str] = set()
    seen_region_keys: set[tuple[str, str]] = set()
    selected_pages = {
        page_id: page
        for page_id, page in pages.items()
        if split is None or page["split"] == split
    }
    _require(split is None or split in SPLITS, f"invalid requested split: {split}")
    for index, prediction in enumerate(predictions):
        _require(isinstance(prediction, dict), f"prediction[{index}] must be an object")
        prediction_id = prediction.get("predictionID")
        _require(prediction_id not in seen_ids, f"duplicate predictionID: {prediction_id}")
        seen_ids.add(prediction_id)
        page_id = prediction.get("pageID")
        _require(page_id in pages, f"prediction references unknown pageID: {page_id}")
        _require(page_id in selected_pages, f"prediction crosses requested split boundary: {page_id}")
        _validate_prediction(prediction, index, pages[page_id])
        if evaluation_level == "oracleCrop":
            _require(
                prediction["regionID"] is not None,
                f"oracleCrop prediction must identify its region: {prediction_id}",
            )
        elif evaluation_level in {"detectedCrop", "fullPage"}:
            _require(
                prediction["regionID"] is None,
                f"{evaluation_level} prediction must not use ground-truth regionID: {prediction_id}",
            )
        region_id = prediction["regionID"]
        if region_id is not None:
            key = (page_id, region_id)
            _require(key not in seen_region_keys, f"duplicate prediction for {page_id}/{region_id}")
            seen_region_keys.add(key)
    for page_id, page in selected_pages.items():
        if page["legacyRegression"] or page["annotationStatus"] in {"pending", "contractExampleOnly"} and not page["regions"]:
            continue
        if evaluation_level == "oracleCrop":
            for region in page["regions"]:
                key = (page_id, region["regionID"])
                _require(key in seen_region_keys, f"missing explicit prediction row for {page_id}/{region['regionID']}")
        elif evaluation_level in {"detectedCrop", "fullPage"}:
            _require(
                any(prediction["pageID"] == page_id for prediction in predictions),
                f"missing explicit page prediction row for {evaluation_level}: {page_id}",
            )
        else:
            _require(False, f"missing explicit prediction row for annotated page: {page_id} (evaluation level is absent)")
    return {"predictions": predictions, "predictionSha256": json_sha256(payload), "selectedPages": selected_pages}


def _bbox_iou(first: list[float] | None, second: list[float] | None) -> float:
    if first is None or second is None:
        return 0.0
    first_x, first_y, first_w, first_h = first
    second_x, second_y, second_w, second_h = second
    left = max(first_x, second_x)
    top = max(first_y, second_y)
    right = min(first_x + first_w, second_x + second_w)
    bottom = min(first_y + first_h, second_y + second_h)
    intersection = max(0.0, right - left) * max(0.0, bottom - top)
    union = first_w * first_h + second_w * second_h - intersection
    return intersection / union if union > 0.0 else 0.0


def _maximum_iou_matching(
    regions: list[dict[str, Any]],
    predictions: list[dict[str, Any]],
    threshold: float,
) -> dict[str, str]:
    """Return a deterministic maximum-cardinality one-to-one matching.

    This is a stable augmenting-path matching, not an input-order greedy
    pairing. Edges are visited by descending IoU and then stable IDs so equal
    scores cannot change the result between runs.
    """

    candidates: dict[str, list[tuple[float, str]]] = {}
    for region in regions:
        region_id = region["regionID"]
        edges = [
            (_bbox_iou(region["bbox"], prediction.get("bbox")), prediction["predictionID"])
            for prediction in predictions
            if prediction["regionID"] is None
            and prediction["status"] not in {"empty", "failure"}
            and prediction.get("bbox") is not None
            and _bbox_iou(region["bbox"], prediction.get("bbox")) >= threshold
        ]
        candidates[region_id] = sorted(edges, key=lambda item: (-item[0], item[1]))
    prediction_by_id = {prediction["predictionID"]: prediction for prediction in predictions}
    matched_prediction_to_region: dict[str, str] = {}

    def visit(region_id: str, visited: set[str]) -> bool:
        for _iou, prediction_id in candidates[region_id]:
            if prediction_id in visited:
                continue
            visited.add(prediction_id)
            previous_region = matched_prediction_to_region.get(prediction_id)
            if previous_region is None or visit(previous_region, visited):
                matched_prediction_to_region[prediction_id] = region_id
                return True
        return False

    for region_id in sorted(candidates):
        visit(region_id, set())
    return {region_id: prediction_id for prediction_id, region_id in matched_prediction_to_region.items()}


def _levenshtein(reference: str, hypothesis: str) -> dict[str, int]:
    # Each cell is (cost, substitutions, insertions, deletions). The explicit
    # tie order keeps reports stable when multiple edit paths have equal cost.
    rows = len(reference) + 1
    columns = len(hypothesis) + 1
    table: list[list[tuple[int, int, int, int]]] = [[(0, 0, 0, 0) for _ in range(columns)] for _ in range(rows)]
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
    cost, substitutions, insertions, deletions = table[-1][-1]
    return {
        "editDistance": cost,
        "substitutions": substitutions,
        "insertions": insertions,
        "deletions": deletions,
        "referenceCharacters": len(reference),
    }


def _metric_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    if not rows:
        return {
            "sampleCount": 0,
            "exactMatchRate": None,
            "nfcExactMatchRate": None,
            "characterErrorRate": None,
            "editDistance": 0,
            "referenceCharacters": 0,
            "substitutions": 0,
            "insertions": 0,
            "deletions": 0,
        }
    reference_characters = sum(row["edits"]["referenceCharacters"] for row in rows)
    edit_distance = sum(row["edits"]["editDistance"] for row in rows)
    return {
        "sampleCount": len(rows),
        "exactMatchRate": sum(row["exact"] for row in rows) / len(rows),
        "nfcExactMatchRate": sum(row["nfcExact"] for row in rows) / len(rows),
        "characterErrorRate": edit_distance / reference_characters if reference_characters else None,
        "editDistance": edit_distance,
        "referenceCharacters": reference_characters,
        "substitutions": sum(row["edits"]["substitutions"] for row in rows),
        "insertions": sum(row["edits"]["insertions"] for row in rows),
        "deletions": sum(row["edits"]["deletions"] for row in rows),
    }


def _macro_metric_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    if not rows:
        return {"sampleCount": 0, "meanCER": None, "exactMatchRate": None, "nfcExactMatchRate": None}
    return {
        "sampleCount": len(rows),
        "meanCER": sum(row["edits"]["editDistance"] / row["edits"]["referenceCharacters"] for row in rows) / len(rows),
        "exactMatchRate": sum(row["exact"] for row in rows) / len(rows),
        "nfcExactMatchRate": sum(row["nfcExact"] for row in rows) / len(rows),
    }


def _kendall_tau(expected: list[str], actual: list[str]) -> float | None:
    common = [region_id for region_id in expected if region_id in set(actual)]
    if len(common) < 2:
        return None
    positions = {region_id: index for index, region_id in enumerate(actual)}
    values = [positions[region_id] for region_id in common]
    concordant = discordant = 0
    for first in range(len(values)):
        for second in range(first + 1, len(values)):
            if values[first] < values[second]:
                concordant += 1
            elif values[first] > values[second]:
                discordant += 1
    pairs = concordant + discordant
    return (concordant - discordant) / pairs if pairs else None


def _japanese_script_density(text: str) -> float:
    if not text:
        return 0.0
    japanese = sum(
        1
        for char in text
        if "\u3040" <= char <= "\u30ff"
        or "\u3400" <= char <= "\u4dbf"
        or "\u4e00" <= char <= "\u9fff"
        or "\uff66" <= char <= "\uff9f"
    )
    return japanese / len(text)


def score(
    manifest: dict[str, Any],
    predictions_payload: dict[str, Any],
    *,
    split: str | None = None,
    manifest_path: Path | None = None,
    repo_root: Path = ROOT,
    verify_assets: bool = True,
    allow_no_ground_truth: bool = False,
) -> dict[str, Any]:
    manifest_info = validate_manifest(
        manifest,
        manifest_path=manifest_path,
        repo_root=repo_root,
        verify_assets=verify_assets,
    )
    prediction_info = validate_predictions(predictions_payload, manifest, manifest_info, split=split)
    selected_pages = prediction_info["selectedPages"]
    predictions = prediction_info["predictions"]
    regions: list[tuple[dict[str, Any], dict[str, Any]]] = []
    for page_id, page in selected_pages.items():
        for region in page["regions"]:
            regions.append((page, region))
    if not regions:
        _require(allow_no_ground_truth, "selected benchmark split has no ground truth")
        return {
            "schemaVersion": SCHEMA_VERSION,
            "benchmark": BENCHMARK,
            "status": "noGroundTruth",
            "datasetSha256": manifest_info["manifestSha256"],
            "predictionSha256": prediction_info["predictionSha256"],
            "config": {
                "split": split or "all",
                "iouThreshold": 0.5,
                "evaluatedFixtureIDs": sorted(selected_pages),
                "evaluationLevels": sorted({item["evaluationLevel"] for item in predictions}),
            },
            "counts": {"pages": len(selected_pages), "regions": 0, "predictions": len(predictions)},
            "metrics": {},
            "failures": [],
            "qualityClaim": "No annotated ground truth is committed; legacy/oracle evidence is reference-only.",
        }

    predictions_by_page: dict[str, list[dict[str, Any]]] = {page_id: [] for page_id in selected_pages}
    for prediction in predictions:
        predictions_by_page[prediction["pageID"]].append(prediction)
    prediction_by_id = {prediction["predictionID"]: prediction for prediction in predictions}
    prediction_position = {prediction["predictionID"]: index for index, prediction in enumerate(predictions)}
    match_by_page: dict[str, dict[str, str]] = {}
    for page_id, page in selected_pages.items():
        page_predictions = predictions_by_page[page_id]
        direct_rows = {
            prediction["regionID"]: prediction["predictionID"]
            for prediction in page_predictions
            if prediction["regionID"] is not None
        }
        direct = dict(direct_rows)
        remaining_regions = [region for region in page["regions"] if region["regionID"] not in direct_rows]
        match_by_page[page_id] = dict(direct)
        match_by_page[page_id].update(_maximum_iou_matching(remaining_regions, page_predictions, 0.5))

    metric_rows: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    matched_prediction_ids: set[str] = set()
    detector_matches = 0
    direction_evaluated = 0
    direction_correct = 0
    page_order_exact: list[bool] = []
    page_taus: list[float] = []
    category_rows: dict[str, list[dict[str, Any]]] = {}
    for page_id, page in selected_pages.items():
        expected_regions = sorted(page["regions"], key=lambda region: (region["readingOrder"], region["regionID"]))
        page_matches = match_by_page[page_id]
        expected_order = [region["regionID"] for region in expected_regions]
        for region in expected_regions:
            region_id = region["regionID"]
            prediction_id = page_matches.get(region_id)
            prediction = prediction_by_id.get(prediction_id) if prediction_id else None
            if prediction is None:
                failures.append({"pageID": page_id, "regionID": region_id, "kind": "omission", "reason": "no_match"})
                continue
            predicted_text = prediction["text"]
            edits = _levenshtein(region["sourceText"], predicted_text)
            row = {
                "pageID": page_id,
                "regionID": region_id,
                "exact": predicted_text == region["sourceText"],
                "nfcExact": unicodedata.normalize("NFC", predicted_text) == region["sourceTextNFC"],
                "edits": edits,
            }
            metric_rows.append(row)
            labels = set(region.get("tags", [])) | {region["writingDirection"], region["textType"]}
            for label in sorted(labels):
                category_rows.setdefault(label, []).append(row)
            if prediction["status"] == "success":
                matched_prediction_ids.add(prediction["predictionID"])
            if prediction["status"] == "success" and _bbox_iou(region["bbox"], prediction.get("bbox")) >= 0.5:
                detector_matches += 1
            predicted_direction = prediction.get("writingDirection")
            if prediction["status"] == "success" and predicted_direction is not None:
                direction_evaluated += 1
                direction_correct += predicted_direction == region["writingDirection"]
            if prediction["status"] in {"empty", "failure"}:
                failures.append({"pageID": page_id, "regionID": region_id, "kind": "omission", "reason": prediction.get("failureReason", prediction["status"])})
            elif not row["exact"]:
                failures.append({"pageID": page_id, "regionID": region_id, "kind": "ocrMismatch", "predictionID": prediction["predictionID"], "sourceText": region["sourceText"], "predictedText": predicted_text})
        actual_order = [
            region_id
            for region_id, prediction_id in sorted(
                match_by_page[page_id].items(),
                key=lambda item: (
                    prediction_by_id[item[1]].get("readingOrder") is None,
                    prediction_by_id[item[1]].get("readingOrder") if prediction_by_id[item[1]].get("readingOrder") is not None else prediction_position[item[1]],
                    item[1],
                ),
            )
            if prediction_by_id[prediction_id]["status"] == "success"
        ]
        page_order_exact.append(actual_order == expected_order)
        tau = _kendall_tau(expected_order, actual_order)
        if tau is not None:
            page_taus.append(tau)
    unmatched_success_predictions = [
        prediction for prediction in predictions
        if prediction["status"] == "success" and prediction["predictionID"] not in matched_prediction_ids
    ]
    gt_regions_by_page = {page_id: page["regions"] for page_id, page in selected_pages.items()}
    duplicate_predictions = [
        prediction
        for prediction in unmatched_success_predictions
        if any(_bbox_iou(region["bbox"], prediction.get("bbox")) >= 0.5 for region in gt_regions_by_page[prediction["pageID"]])
    ]
    false_positive_predictions = [prediction for prediction in unmatched_success_predictions if prediction not in duplicate_predictions]
    for prediction in sorted(duplicate_predictions, key=lambda item: item["predictionID"]):
        failures.append({"pageID": prediction["pageID"], "predictionID": prediction["predictionID"], "kind": "duplicate"})
    for prediction in sorted(false_positive_predictions, key=lambda item: item["predictionID"]):
        failures.append({"pageID": prediction["pageID"], "predictionID": prediction["predictionID"], "kind": "falsePositive"})
    failures = sorted(failures, key=lambda item: (item.get("pageID", ""), item.get("regionID", ""), item.get("predictionID", ""), item["kind"]))
    gt_count = len(regions)
    successful_prediction_count = sum(prediction["status"] == "success" for prediction in predictions)
    predicted_count = successful_prediction_count
    precision = detector_matches / predicted_count if predicted_count else 0.0
    recall = detector_matches / gt_count if gt_count else 0.0
    f1 = 2.0 * precision * recall / (precision + recall) if precision + recall else 0.0
    by_category = {
        label: {"micro": _metric_summary(rows), "macro": _macro_metric_summary(rows)}
        for label, rows in sorted(category_rows.items())
    }
    line_polygon_regions = sum(bool(region.get("linePolygons")) for _page, region in regions)
    duplicate_count = len(duplicate_predictions)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "benchmark": BENCHMARK,
        "status": "success",
        "datasetSha256": manifest_info["manifestSha256"],
        "predictionSha256": prediction_info["predictionSha256"],
        "config": {
            "split": split or "all",
            "iouThreshold": 0.5,
            "evaluatedFixtureIDs": sorted(selected_pages),
            "evaluationLevels": sorted({item["evaluationLevel"] for item in predictions}),
        },
        "counts": {
            "pages": len(selected_pages),
            "regions": gt_count,
            "predictions": len(predictions),
            "successfulPredictions": successful_prediction_count,
            "omissions": sum(item["kind"] == "omission" for item in failures),
            "falsePositives": len(false_positive_predictions),
            "duplicates": duplicate_count,
        },
        "metrics": {
            "ocr": {"micro": _metric_summary(metric_rows), "macro": _macro_metric_summary(metric_rows), "byCategory": by_category},
            "detector": {
                "iouThreshold": 0.5,
                "truePositive": detector_matches,
                "predicted": predicted_count,
                "groundTruth": gt_count,
                "precision": precision,
                "recall": recall,
                "f1": f1,
            },
            "grouping": {
                "duplicateCount": duplicate_count,
                "omissionCount": sum(item["kind"] == "omission" for item in failures),
                "falsePositiveCount": len(false_positive_predictions),
                "pageCompositionExactRate": sum(page_order_exact) / len(page_order_exact) if page_order_exact else None,
            },
            "readingOrder": {
                "pageExactOrderRate": sum(page_order_exact) / len(page_order_exact) if page_order_exact else None,
                "kendallTauMean": sum(page_taus) / len(page_taus) if page_taus else None,
                "kendallTauEvaluatedPages": len(page_taus),
            },
            "direction": {
                "evaluated": direction_evaluated,
                "coverage": direction_evaluated / gt_count if gt_count else 0.0,
                "accuracy": direction_correct / direction_evaluated if direction_evaluated else None,
            },
            "lineGeometry": {
                "regionPolygonValidityRate": 1.0,
                "annotatedLinePolygonRegionCount": line_polygon_regions,
                "linePolygonAnnotationCoverage": line_polygon_regions / gt_count if gt_count else 0.0,
            },
        },
        "failures": failures,
        "qualityClaim": "Offline annotated benchmark score only; no fixed-crop or script-density generalization claim.",
    }


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--predictions", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--split", choices=sorted(SPLITS))
    parser.add_argument("--repo-root", type=Path, default=ROOT)
    parser.add_argument("--skip-asset-verification", action="store_true")
    parser.add_argument("--allow-no-ground-truth", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
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
            allow_no_ground_truth=args.allow_no_ground_truth,
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
        return 0
    except (BenchmarkError, OSError, TypeError, ValueError) as error:
        print(f"Japanese OCR benchmark failed closed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
