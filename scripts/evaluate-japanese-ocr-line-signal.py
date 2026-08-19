#!/usr/bin/env python3
"""Score native TextRegion/line geometry as a shadow-only OCR signal.

The signal is intentionally separate from OCR text selection.  Candidate
rows never carry ground-truth region IDs; the scorer performs deterministic
IoU matching offline and reports geometry recall, cut/merge/duplicate/omission
and budget evidence.  Contract-only or legacy fixtures can exercise the
protocol, but they never become a promotion-quality claim.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
from pathlib import Path
import re
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_VERSION = "1.0.0"
BENCHMARK = "japanese-ocr-line-signal"
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def _load_base_module():
    path = ROOT / "scripts/evaluate-japanese-ocr-benchmark.py"
    spec = importlib.util.spec_from_file_location("aitrans_japanese_ocr_benchmark_base", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load Japanese OCR benchmark base scorer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BASE = _load_base_module()


class LineSignalError(ValueError):
    """Raised for invalid or unsafe shadow geometry input."""


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise LineSignalError(f"cannot read JSON {path}: {error}") from error


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise LineSignalError(message)


def _reject_unknown(value: dict[str, Any], allowed: set[str], label: str) -> None:
    unknown = sorted(set(value) - allowed)
    _require(not unknown, f"{label} has unknown fields: {unknown}")


def _finite(value: Any, label: str) -> float:
    _require(isinstance(value, (int, float)) and not isinstance(value, bool), f"{label} must be numeric")
    result = float(value)
    _require(math.isfinite(result), f"{label} must be finite")
    return result


def _canonical_sha(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    import hashlib

    return hashlib.sha256(encoded).hexdigest()


def _polygon_bbox(polygon: list[list[float]]) -> list[float]:
    xs = [point[0] for point in polygon]
    ys = [point[1] for point in polygon]
    left = min(xs)
    top = min(ys)
    right = max(xs)
    bottom = max(ys)
    return [left, top, right - left, bottom - top]


def _validate_run(run: Any) -> None:
    try:
        BASE._validate_run(run)
    except BASE.BenchmarkError as error:
        raise LineSignalError(str(error)) from error


def _validate_page_status(page: dict[str, Any], index: int, page_ids: set[str]) -> str:
    label = f"pages[{index}]"
    _reject_unknown(page, {"pageID", "textRegionStatus", "lineStatus", "failureReason"}, label)
    for key in ("pageID", "textRegionStatus", "lineStatus", "failureReason"):
        _require(key in page, f"{label} missing {key}")
    page_id = page["pageID"]
    _require(isinstance(page_id, str) and page_id in page_ids, f"{label}.pageID is unknown: {page_id}")
    _require(page["textRegionStatus"] in {"success", "empty", "failure"}, f"{label}.textRegionStatus is invalid")
    _require(page["lineStatus"] in {"success", "empty", "failure"}, f"{label}.lineStatus is invalid")
    if page["textRegionStatus"] == "failure" or page["lineStatus"] == "failure":
        _require(isinstance(page["failureReason"], str) and page["failureReason"].strip(), f"{label}.failureReason is required")
    else:
        _require(page["failureReason"] is None, f"{label}.failureReason must be null for a non-failure page")
    return page_id


def _validate_candidate(
    candidate: Any,
    index: int,
    page_ids: set[str],
    seen_ids: set[str],
) -> dict[str, Any]:
    label = f"candidates[{index}]"
    _require(isinstance(candidate, dict), f"{label} must be an object")
    _reject_unknown(
        candidate,
        {
            "candidateID", "pageID", "kind", "status", "bbox", "polygon",
            "confidence", "writingDirection", "readingOrder", "parentCandidateID",
            "source", "referenceOnly", "failureReason",
        },
        label,
    )
    required = (
        "candidateID", "pageID", "kind", "status", "bbox", "polygon",
        "confidence", "writingDirection", "readingOrder", "parentCandidateID",
        "source", "referenceOnly", "failureReason",
    )
    for key in required:
        _require(key in candidate, f"{label} missing {key}")
    candidate_id = candidate["candidateID"]
    _require(isinstance(candidate_id, str) and candidate_id.strip(), f"{label}.candidateID is empty")
    _require(candidate_id not in seen_ids, f"duplicate candidateID: {candidate_id}")
    seen_ids.add(candidate_id)
    _require(isinstance(candidate["pageID"], str) and candidate["pageID"] in page_ids, f"{label}.pageID is unknown")
    _require(candidate["kind"] in {"textRegion", "line"}, f"{label}.kind is invalid")
    _require(candidate["status"] in {"success", "empty", "failure"}, f"{label}.status is invalid")
    _require(candidate["source"] in {"nativeTextRegion", "nativeLine", "detectorRect", "visionCharacterProjection"}, f"{label}.source is invalid")
    if candidate["kind"] == "textRegion":
        _require(candidate["source"] in {"nativeTextRegion", "detectorRect"}, f"{label}.textRegion source is not a region signal")
    else:
        _require(candidate["source"] in {"nativeLine", "visionCharacterProjection"}, f"{label}.line source is not a line signal")
    _require(isinstance(candidate["referenceOnly"], bool), f"{label}.referenceOnly must be boolean")
    if candidate["status"] == "success":
        _require(candidate["bbox"] is not None and candidate["polygon"] is not None, f"{label}.success geometry is required")
        try:
            bbox = BASE.validate_normalized_bbox(candidate["bbox"], f"{label}.bbox")
            polygon = BASE.validate_polygon(candidate["polygon"], f"{label}.polygon")
        except BASE.BenchmarkError as error:
            raise LineSignalError(str(error)) from error
        polygon_box = _polygon_bbox([[float(x), float(y)] for x, y in polygon])
        for coordinate, polygon_coordinate in zip(bbox, polygon_box):
            _require(abs(coordinate - polygon_coordinate) <= 0.02, f"{label}.bbox does not contain its polygon")
        confidence = candidate["confidence"]
        _require(confidence is not None, f"{label}.success confidence is required")
        confidence_value = _finite(confidence, f"{label}.confidence")
        _require(0.0 <= confidence_value <= 1.0, f"{label}.confidence is outside [0,1]")
        _require(candidate["failureReason"] is None, f"{label}.success cannot carry failureReason")
    else:
        _require(candidate["bbox"] is None and candidate["polygon"] is None, f"{label}.{candidate['status']} geometry must be null")
        _require(candidate["confidence"] is None, f"{label}.{candidate['status']} confidence must be null")
        if candidate["status"] == "failure":
            _require(isinstance(candidate["failureReason"], str) and candidate["failureReason"].strip(), f"{label}.failureReason is required")
        else:
            _require(candidate["failureReason"] is None, f"{label}.empty failureReason must be null")
    if candidate["writingDirection"] is not None:
        _require(candidate["writingDirection"] in {"vertical", "horizontal", "mixed", "unknown"}, f"{label}.writingDirection is invalid")
    if candidate["readingOrder"] is not None:
        _require(isinstance(candidate["readingOrder"], int) and not isinstance(candidate["readingOrder"], bool) and candidate["readingOrder"] >= 0, f"{label}.readingOrder is invalid")
    if candidate["parentCandidateID"] is not None:
        _require(isinstance(candidate["parentCandidateID"], str) and candidate["parentCandidateID"].strip(), f"{label}.parentCandidateID is invalid")
    return candidate


def validate_input(
    manifest: dict[str, Any],
    payload: dict[str, Any],
    *,
    manifest_path: Path | None = None,
    repo_root: Path = ROOT,
    verify_assets: bool = True,
) -> dict[str, Any]:
    try:
        manifest_info = BASE.validate_manifest(
            manifest,
            manifest_path=manifest_path,
            repo_root=repo_root,
            verify_assets=verify_assets,
        )
    except BASE.BenchmarkError as error:
        raise LineSignalError(str(error)) from error
    _require(isinstance(payload, dict), "line-signal input root must be an object")
    _reject_unknown(payload, {"schemaVersion", "benchmark", "datasetSha256", "run", "budgets", "pages", "candidates"}, "input")
    _require(payload.get("schemaVersion") == SCHEMA_VERSION, "unsupported line-signal schemaVersion")
    _require(payload.get("benchmark") == BENCHMARK, "input benchmark must be japanese-ocr-line-signal")
    dataset_sha = payload.get("datasetSha256")
    _require(isinstance(dataset_sha, str) and bool(HEX64.fullmatch(dataset_sha)), "datasetSha256 is invalid")
    _require(dataset_sha == manifest_info["manifestSha256"], "line-signal dataset SHA does not match manifest")
    _validate_run(payload.get("run"))
    budgets = payload.get("budgets")
    _require(isinstance(budgets, dict), "budgets must be an object")
    _reject_unknown(budgets, {"maxTextRegionCandidates", "maxLineCandidates", "maxTotalCandidates"}, "budgets")
    for key in ("maxTextRegionCandidates", "maxLineCandidates", "maxTotalCandidates"):
        _require(isinstance(budgets.get(key), int) and not isinstance(budgets[key], bool) and budgets[key] > 0, f"budgets.{key} must be positive")
    pages_payload = payload.get("pages")
    _require(isinstance(pages_payload, list) and pages_payload, "pages must be a non-empty array")
    manifest_pages = manifest_info["pages"]
    page_ids = set(manifest_pages)
    pages: dict[str, dict[str, Any]] = {}
    for index, page in enumerate(pages_payload):
        page_id = _validate_page_status(page, index, page_ids)
        _require(page_id not in pages, f"duplicate page status: {page_id}")
        pages[page_id] = page
    _require(set(pages) == page_ids, f"page coverage must be explicit for every manifest page: {sorted(page_ids - set(pages))}")
    candidates_payload = payload.get("candidates")
    _require(isinstance(candidates_payload, list), "candidates must be an array")
    seen_ids: set[str] = set()
    candidates = [_validate_candidate(candidate, index, page_ids, seen_ids) for index, candidate in enumerate(candidates_payload)]
    candidates_by_id = {candidate["candidateID"]: candidate for candidate in candidates}
    for candidate in candidates:
        parent_id = candidate["parentCandidateID"]
        if parent_id is not None:
            parent = candidates_by_id.get(parent_id)
            _require(parent is not None, f"candidate parent is unknown: {parent_id}")
            _require(parent["pageID"] == candidate["pageID"], f"candidate parent crosses page boundary: {candidate['candidateID']}")
            _require(parent["kind"] == "textRegion", f"line candidate parent must be a textRegion: {candidate['candidateID']}")
    for page_id, page in pages.items():
        page_candidates = [candidate for candidate in candidates if candidate["pageID"] == page_id and candidate["status"] == "success"]
        region_count = sum(candidate["kind"] == "textRegion" for candidate in page_candidates)
        line_count = sum(candidate["kind"] == "line" for candidate in page_candidates)
        if page["textRegionStatus"] == "success":
            _require(region_count > 0, f"{page_id} declares textRegion success without a candidate")
        else:
            _require(region_count == 0, f"{page_id} has textRegion candidates despite status {page['textRegionStatus']}")
        if page["lineStatus"] == "success":
            _require(line_count > 0, f"{page_id} declares line success without a candidate")
        else:
            _require(line_count == 0, f"{page_id} has line candidates despite status {page['lineStatus']}")
    successful = [candidate for candidate in candidates if candidate["status"] == "success"]
    observed_regions = sum(candidate["kind"] == "textRegion" for candidate in successful)
    observed_lines = sum(candidate["kind"] == "line" for candidate in successful)
    _require(observed_regions <= budgets["maxTextRegionCandidates"], "textRegion candidate budget exceeded")
    _require(observed_lines <= budgets["maxLineCandidates"], "line candidate budget exceeded")
    _require(len(successful) <= budgets["maxTotalCandidates"], "total candidate budget exceeded")
    return {
        "manifestInfo": manifest_info,
        "pages": pages,
        "candidates": candidates,
        "candidatesByID": candidates_by_id,
        "budgets": budgets,
        "signalSha256": _canonical_sha(payload),
    }


def _metric(
    references: list[dict[str, Any]],
    candidates: list[dict[str, Any]],
    threshold: float,
    groups: dict[str, str],
    *,
    cut_candidate_count: int = 0,
) -> tuple[dict[str, Any], dict[str, str], dict[str, list[tuple[float, str]]]]:
    matching_candidates = [
        {
            "predictionID": candidate["candidateID"],
            "regionID": None,
            "status": "success",
            "bbox": candidate["bbox"],
        }
        for candidate in candidates
    ]
    matching = BASE._maximum_iou_matching(references, matching_candidates, threshold)
    edges: dict[str, list[tuple[float, str]]] = {}
    for reference in references:
        reference_id = reference["regionID"]
        edge_list: list[tuple[float, str]] = []
        for candidate in candidates:
            iou = BASE._bbox_iou(reference["bbox"], candidate["bbox"])
            if iou >= threshold:
                edge_list.append((iou, candidate["candidateID"]))
        edges[reference_id] = sorted(edge_list, key=lambda item: (-item[0], item[1]))
    candidate_edges: dict[str, list[str]] = {candidate["candidateID"]: [] for candidate in candidates}
    for reference_id, edge_list in edges.items():
        for _iou, candidate_id in edge_list:
            candidate_edges[candidate_id].append(reference_id)
    duplicate_count = sum(max(0, len(edge_list) - 1) for edge_list in edges.values())
    omission_count = sum(not edge_list for edge_list in edges.values())
    false_positive_count = sum(not reference_ids for reference_ids in candidate_edges.values())
    cross_region_merge_count = sum(
        len({groups[reference_id] for reference_id in reference_ids}) >= 2
        for reference_ids in candidate_edges.values()
    )
    matched_count = len(matching)
    candidate_count = len(candidates)
    reference_count = len(references)
    precision = matched_count / candidate_count if candidate_count else None
    recall = matched_count / reference_count if reference_count else None
    f1 = (2 * precision * recall / (precision + recall)) if precision is not None and recall is not None and precision + recall else None
    metric = {
        "candidateCount": candidate_count,
        "referenceCount": reference_count,
        "matchedCount": matched_count,
        "recall": recall,
        "precision": precision,
        "f1": f1,
        "omissionCount": omission_count,
        "duplicateCount": duplicate_count,
        "falsePositiveCount": false_positive_count,
        "crossRegionMergeCount": cross_region_merge_count,
        "cutCandidateCount": cut_candidate_count,
    }
    return metric, matching, edges


def _line_references(page: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, str]]:
    references: list[dict[str, Any]] = []
    groups: dict[str, str] = {}
    for region in page["regions"]:
        for index, polygon in enumerate(region.get("linePolygons", [])):
            points = [[float(point[0]), float(point[1])] for point in polygon]
            line_id = f"{region['regionID']}#line-{index}"
            references.append({"regionID": line_id, "bbox": _polygon_bbox(points)})
            groups[line_id] = region["regionID"]
    return references, groups


def _aggregate(metrics: list[dict[str, Any]]) -> dict[str, Any]:
    keys = (
        "candidateCount", "referenceCount", "matchedCount", "omissionCount",
        "duplicateCount", "falsePositiveCount", "crossRegionMergeCount", "cutCandidateCount",
    )
    result = {key: sum(metric[key] for metric in metrics) for key in keys}
    candidate_count = result["candidateCount"]
    reference_count = result["referenceCount"]
    matched_count = result["matchedCount"]
    result["precision"] = matched_count / candidate_count if candidate_count else None
    result["recall"] = matched_count / reference_count if reference_count else None
    precision = result["precision"]
    recall = result["recall"]
    result["f1"] = 2 * precision * recall / (precision + recall) if precision is not None and recall is not None and precision + recall else None
    return result


def evaluate(
    manifest: dict[str, Any],
    payload: dict[str, Any],
    *,
    manifest_path: Path | None = None,
    repo_root: Path = ROOT,
    verify_assets: bool = True,
) -> dict[str, Any]:
    info = validate_input(
        manifest,
        payload,
        manifest_path=manifest_path,
        repo_root=repo_root,
        verify_assets=verify_assets,
    )
    manifest_pages = info["manifestInfo"]["pages"]
    candidates = info["candidates"]
    candidate_pages = {
        page_id: {
            "textRegion": [candidate for candidate in candidates if candidate["pageID"] == page_id and candidate["kind"] == "textRegion" and candidate["status"] == "success"],
            "line": [candidate for candidate in candidates if candidate["pageID"] == page_id and candidate["kind"] == "line" and candidate["status"] == "success"],
        }
        for page_id in manifest_pages
    }
    page_reports: list[dict[str, Any]] = []
    region_metrics: list[dict[str, Any]] = []
    line_metrics: list[dict[str, Any]] = []
    for page_id in sorted(manifest_pages):
        page = manifest_pages[page_id]
        page_candidates = candidate_pages[page_id]
        region_refs = [{"regionID": region["regionID"], "bbox": region["bbox"]} for region in page["regions"]]
        region_groups = {region["regionID"]: region["regionID"] for region in page["regions"]}
        region_metric, region_matching, _region_edges = _metric(
            region_refs,
            page_candidates["textRegion"],
            0.5,
            region_groups,
        )
        line_refs, line_groups = _line_references(page)
        line_edges_for_cut: dict[str, list[tuple[float, str]]] = {}
        for line_ref in line_refs:
            line_edges_for_cut[line_ref["regionID"]] = [
                (BASE._bbox_iou(line_ref["bbox"], candidate["bbox"]), candidate["candidateID"])
                for candidate in page_candidates["line"]
                if BASE._bbox_iou(line_ref["bbox"], candidate["bbox"]) >= 0.5
            ]
        region_edge_exists = {
            candidate["candidateID"]: any(
                BASE._bbox_iou(region["bbox"], candidate["bbox"]) >= 0.5
                for region in page["regions"]
            )
            for candidate in page_candidates["line"]
        }
        cut_count = sum(
            region_edge_exists[candidate["candidateID"]]
            and not any(candidate["candidateID"] in {candidate_id for _iou, candidate_id in edges} for edges in line_edges_for_cut.values())
            for candidate in page_candidates["line"]
        )
        line_metric, _line_matching, _line_edges = _metric(
            line_refs,
            page_candidates["line"],
            0.5,
            line_groups,
            cut_candidate_count=cut_count,
        )
        direction_values: list[bool] = []
        order_values: list[bool] = []
        for region_id, candidate_id in region_matching.items():
            region = next(region for region in page["regions"] if region["regionID"] == region_id)
            candidate = info["candidatesByID"][candidate_id]
            if candidate["writingDirection"] is not None:
                direction_values.append(candidate["writingDirection"] == region["writingDirection"])
            if candidate["readingOrder"] is not None:
                order_values.append(candidate["readingOrder"] == region["readingOrder"])
        orphan_line_count = sum(
            candidate["parentCandidateID"] is None
            or candidate["parentCandidateID"] not in info["candidatesByID"]
            or info["candidatesByID"][candidate["parentCandidateID"]]["kind"] != "textRegion"
            or info["candidatesByID"][candidate["parentCandidateID"]]["status"] != "success"
            for candidate in page_candidates["line"]
        )
        successful_count = len(page_candidates["textRegion"]) + len(page_candidates["line"])
        page_reports.append(
            {
                "pageID": page_id,
                "annotationStatus": page["annotationStatus"],
                "textRegions": region_metric,
                "lines": line_metric,
                "directionAccuracy": sum(direction_values) / len(direction_values) if direction_values else None,
                "readingOrderAccuracy": sum(order_values) / len(order_values) if order_values else None,
                "orphanLineCount": orphan_line_count,
                "budget": {
                    "observedTextRegionCandidates": len(page_candidates["textRegion"]),
                    "observedLineCandidates": len(page_candidates["line"]),
                    "observedTotalCandidates": successful_count,
                    "declaredPageTextRegionStatus": info["pages"][page_id]["textRegionStatus"],
                    "declaredPageLineStatus": info["pages"][page_id]["lineStatus"],
                },
            }
        )
        region_metrics.append(region_metric)
        line_metrics.append(line_metric)
    contract_only_pages = sum(page["annotationStatus"] in {"contractExampleOnly", "legacyRegressionOnly", "pending"} for page in manifest_pages.values())
    human_holdout_pages = sum(page["annotationStatus"] == "human" and page["split"] == "holdout" for page in manifest_pages.values())
    promotion_status = "notEligible"
    promotion_reason = (
        "requires human holdout pages and a real authorized corpus; contract/legacy fixtures are structural only"
        if contract_only_pages or human_holdout_pages == 0
        else "requires predeclared significance test and frozen train/dev policy before holdout promotion"
    )
    totals = {
        "pageCount": len(page_reports),
        "humanHoldoutPageCount": human_holdout_pages,
        "contractOrLegacyPageCount": contract_only_pages,
        "textRegions": _aggregate(region_metrics),
        "lines": _aggregate(line_metrics),
        "orphanLineCount": sum(page["orphanLineCount"] for page in page_reports),
        "budgetPassed": True,
    }
    return {
        "schemaVersion": SCHEMA_VERSION,
        "benchmark": BENCHMARK,
        "status": "insufficientCorpus",
        "datasetSha256": info["manifestInfo"]["manifestSha256"],
        "signalSha256": info["signalSha256"],
        "config": {
            "regionIoUThreshold": 0.5,
            "lineIoUThreshold": 0.5,
            "candidateLeakageRejected": True,
            "groundTruthUsedForSelection": False,
        },
        "run": payload["run"],
        "budgets": {
            **info["budgets"],
            "observedTextRegionCandidates": sum(metric["candidateCount"] for metric in region_metrics),
            "observedLineCandidates": sum(metric["candidateCount"] for metric in line_metrics),
            "observedTotalCandidates": sum(metric["candidateCount"] for metric in region_metrics + line_metrics),
            "passed": True,
        },
        "pages": page_reports,
        "totals": totals,
        "promotion": {
            "status": promotion_status,
            "reason": promotion_reason,
            "groundTruthUsedForSelection": False,
            "requiredMinimumHoldoutPages": 20,
            "requiredMinimumHumanRegions": 150,
            "statisticalSignificanceComputed": False,
        },
        "qualityClaim": "shadow geometry metrics only; no native line/TextRegion recall or general OCR quality claim",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--signal", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = evaluate(
            load_json(args.manifest),
            load_json(args.signal),
            manifest_path=args.manifest,
            repo_root=ROOT,
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False))
        return 0
    except LineSignalError as error:
        print(f"Japanese OCR line-signal evaluation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
