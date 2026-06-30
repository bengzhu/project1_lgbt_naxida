#!/usr/bin/env python3
"""Validate AITRANS Koharu external artifact contract files."""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Any


EXPECTED_COORDINATE_SPACE = "originalImageTopLeftPixels"
EXPECTED_SOURCE_IMAGE = "test/1.png"
DEFAULT_IMAGE_PATH = Path("test/1.png")
ACTIVE_ARTIFACT_ROOT = Path("test/koharu_artifacts")
REQUIRED_ARTIFACT_FILES = [
    {
        "path": "test/koharu_artifacts/1.manifest.json",
        "kind": "manifest",
        "required": True,
        "notes": [
            "schemaVersion must be aitrans.koharu_artifact_contract.v1",
            "sourceImage must be test/1.png",
            "coordinateSpace must be originalImageTopLeftPixels",
            "contractExampleOnly must be false for active detector output",
        ],
    },
    {
        "path": "test/koharu_artifacts/1.textboxes.json",
        "kind": "TextBoxes",
        "required": True,
        "notes": [
            "array or object with textBoxes/textboxes/items",
            "each bbox is [x, y, width, height] in original image top-left pixels",
            "confidence, when present, must be in [0, 1]",
        ],
    },
    {
        "path": "test/koharu_artifacts/1.bubbles.json",
        "kind": "BubbleMask",
        "required": True,
        "notes": [
            "array or object with bubbleInstances/bubbles/instances/items",
            "summary must include per-instance id and bbox; maskValue/pixelCount are recommended",
        ],
    },
    {
        "path": "test/koharu_artifacts/1.segment_mask.json",
        "kind": "SegmentMask",
        "required": True,
        "notes": [
            "summary object with width and height matching test/1.png",
            "glyphPixelCount and connectedComponentCount are recommended",
        ],
    },
]


def is_active_artifacts_root(root: Path) -> bool:
    normalized = Path(str(root).rstrip("/"))
    return normalized == ACTIVE_ARTIFACT_ROOT or tuple(normalized.parts[-2:]) == tuple(ACTIVE_ARTIFACT_ROOT.parts)


def read_image_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(32)
        if header.startswith(b"\x89PNG\r\n\x1a\n"):
            return struct.unpack(">II", header[16:24])
        if header.startswith(b"\xff\xd8"):
            handle.seek(2)
            while True:
                marker_prefix = handle.read(1)
                if marker_prefix == b"":
                    break
                if marker_prefix != b"\xff":
                    continue
                marker = handle.read(1)
                while marker == b"\xff":
                    marker = handle.read(1)
                if marker in {b"\xd8", b"\xd9"}:
                    continue
                length_bytes = handle.read(2)
                if len(length_bytes) != 2:
                    break
                length = struct.unpack(">H", length_bytes)[0]
                if marker in {
                    b"\xc0", b"\xc1", b"\xc2", b"\xc3", b"\xc5", b"\xc6", b"\xc7",
                    b"\xc9", b"\xca", b"\xcb", b"\xcd", b"\xce", b"\xcf",
                }:
                    data = handle.read(length - 2)
                    if len(data) < 5:
                        break
                    height, width = struct.unpack(">HH", data[1:5])
                    return width, height
                handle.seek(length - 2, 1)
    raise ValueError(f"unsupported image header: {path}")


def load_json(path: Path, label: str, parse_errors: list[str]) -> Any | None:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        return None
    except Exception as error:  # noqa: BLE001 - CLI validator should report all parse failures.
        parse_errors.append(f"{label}: {error}")
        return None


def resolve_path(root: Path, manifest: dict[str, Any] | None, key: str, fallback: str) -> Path:
    value = manifest.get(key) if isinstance(manifest, dict) else None
    if isinstance(value, str) and value.strip():
        candidate = Path(value)
        return candidate if candidate.is_absolute() else root / candidate
    return root / fallback


def list_payload(data: Any, keys: list[str], label: str, parse_errors: list[str]) -> list[dict[str, Any]]:
    if data is None:
        return []
    if isinstance(data, list):
        values = data
    elif isinstance(data, dict):
        values = None
        for key in keys:
            if key in data:
                values = data[key]
                break
        if values is None:
            parse_errors.append(f"{label}: missing supported list key {'/'.join(keys)}")
            return []
    else:
        parse_errors.append(f"{label}: expected array or object")
        return []
    if not isinstance(values, list):
        parse_errors.append(f"{label}: selected value is not an array")
        return []
    result = []
    for index, item in enumerate(values):
        if isinstance(item, dict):
            result.append(item)
        else:
            parse_errors.append(f"{label}[{index}]: expected object")
    return result


def bbox_for(item: dict[str, Any]) -> list[float] | None:
    bbox = item.get("bbox")
    if isinstance(bbox, list) and len(bbox) == 4:
        try:
            return [float(value) for value in bbox]
        except (TypeError, ValueError):
            return None
    keys = ("x", "y", "width", "height")
    if all(key in item for key in keys):
        try:
            return [float(item[key]) for key in keys]
        except (TypeError, ValueError):
            return None
    return None


def validate_boxes(
    items: list[dict[str, Any]],
    label: str,
    image_width: int,
    image_height: int,
    coordinate_errors: list[str],
) -> list[str]:
    invalid_ids = []
    for index, item in enumerate(items):
        item_id = str(item.get("id") or f"{label}-{index}")
        bbox = bbox_for(item)
        if bbox is None:
            invalid_ids.append(item_id)
            coordinate_errors.append(f"{label}:{item_id}:bboxMissingOrInvalid")
            continue
        x, y, width, height = bbox
        if width <= 0 or height <= 0 or x < 0 or y < 0 or x + width > image_width or y + height > image_height:
            invalid_ids.append(item_id)
            coordinate_errors.append(f"{label}:{item_id}:bboxOutOfBounds")
        confidence = item.get("confidence")
        if confidence is not None:
            try:
                confidence_value = float(confidence)
            except (TypeError, ValueError):
                invalid_ids.append(item_id)
                coordinate_errors.append(f"{label}:{item_id}:confidenceInvalid")
            else:
                if not 0 <= confidence_value <= 1:
                    invalid_ids.append(item_id)
                    coordinate_errors.append(f"{label}:{item_id}:confidenceOutOfRange")
        line_polygons = item.get("linePolygons")
        if line_polygons is not None and not isinstance(line_polygons, list):
            coordinate_errors.append(f"{label}:{item_id}:linePolygonsInvalid")
    return sorted(set(invalid_ids))


def verdict_for(
    manifest_found: bool,
    missing_artifacts: list[str],
    parse_errors: list[str],
    coordinate_errors: list[str],
    text_boxes: list[dict[str, Any]],
    bubbles: list[dict[str, Any]],
    segment_mask: dict[str, Any] | None,
    contract_example_only: bool,
) -> str:
    if not manifest_found:
        return "manifestMissing"
    if parse_errors:
        return "parseFailed"
    if any(error.startswith("coordinateSpaceMissing") for error in coordinate_errors):
        return "coordinateSpaceMissing"
    if any(error.startswith("coordinateSpaceMismatch") for error in coordinate_errors):
        return "coordinateSpaceMismatch"
    if any(error.startswith("sourceImageMismatch") for error in coordinate_errors):
        return "sourceImageMismatch"
    if coordinate_errors:
        return "coordinateValidationFailed"
    if missing_artifacts:
        return "artifactFilesMissing"
    if not text_boxes:
        return "insufficientTextBoxCoverage"
    if not bubbles:
        return "insufficientBubbleCoverage"
    if segment_mask is None:
        return "segmentMaskMissing"
    if contract_example_only:
        return "contractExampleOnly"
    return "readyForShadowOCR"


def next_action_for(verdict: str) -> str:
    if verdict == "readyForShadowOCR":
        return "continueWithExternalTextBoxesShadowOCR"
    if verdict == "parseFailed":
        return "stopUntilParserFixed"
    if verdict == "contractExampleOnly":
        return "stopBecauseFixtureIsNotDetectorOutput"
    if verdict in {
        "coordinateSpaceMissing",
        "coordinateSpaceMismatch",
        "sourceImageMismatch",
        "coordinateValidationFailed",
    }:
        return "stopUntilArtifactContractFixed"
    return "stopUntilArtifactsProvided"


def readiness_blockers(
    verdict: str,
    missing_artifacts: list[str],
    parse_errors: list[str],
    coordinate_errors: list[str],
    contract_example_only: bool,
    active_artifacts_directory: bool,
) -> list[str]:
    blockers: list[str] = []
    if verdict == "readyForShadowOCR":
        return blockers
    if not active_artifacts_directory:
        blockers.append("activeArtifactsDirectoryMissing")
    if contract_example_only:
        blockers.append("contractExampleOnly")
    blockers.extend(f"missing:{item}" for item in missing_artifacts)
    blockers.extend(f"parse:{item}" for item in parse_errors)
    blockers.extend(f"coordinate:{item}" for item in coordinate_errors)
    if not blockers:
        blockers.append(verdict)
    return blockers


def validate(root: Path, allow_missing: bool, image_path: Path) -> dict[str, Any]:
    parse_errors: list[str] = []
    coordinate_errors: list[str] = []
    image_width, image_height = read_image_size(image_path)
    manifest_path = root / "1.manifest.json"
    manifest_raw = load_json(manifest_path, "manifest", parse_errors)
    manifest = manifest_raw if isinstance(manifest_raw, dict) else None
    if manifest_raw is not None and manifest is None:
        parse_errors.append("manifest: expected object")

    textboxes_path = resolve_path(root, manifest, "textBoxesPath", "1.textboxes.json")
    bubbles_path = resolve_path(root, manifest, "bubbleMaskPath", "1.bubbles.json")
    segment_path = resolve_path(root, manifest, "segmentMaskPath", "1.segment_mask.json")

    missing_artifacts = []
    if not manifest_path.is_file():
        missing_artifacts.append("manifest")
    if not textboxes_path.is_file():
        missing_artifacts.append("TextBoxes")
    if not bubbles_path.is_file():
        missing_artifacts.append("BubbleMask")
    if not segment_path.is_file():
        missing_artifacts.append("SegmentMask")

    textboxes_data = load_json(textboxes_path, "textBoxes", parse_errors)
    bubbles_data = load_json(bubbles_path, "bubbleMask", parse_errors)
    segment_raw = load_json(segment_path, "segmentMask", parse_errors)
    segment_mask = segment_raw if isinstance(segment_raw, dict) else None
    if segment_raw is not None and segment_mask is None:
        parse_errors.append("segmentMask: expected object")

    text_boxes = list_payload(textboxes_data, ["textBoxes", "textboxes", "items"], "textBoxes", parse_errors)
    bubbles = list_payload(
        bubbles_data,
        ["bubbleInstances", "bubbles", "instances", "items"],
        "bubbleMask",
        parse_errors,
    )

    coordinate_space = manifest.get("coordinateSpace") if manifest else None
    if coordinate_space is None:
        coordinate_errors.append("coordinateSpaceMissing")
    elif coordinate_space != EXPECTED_COORDINATE_SPACE:
        coordinate_errors.append(f"coordinateSpaceMismatch:{coordinate_space}")

    source_image = manifest.get("sourceImage") if manifest else None
    if source_image not in (None, EXPECTED_SOURCE_IMAGE):
        coordinate_errors.append(f"sourceImageMismatch:{source_image}")

    contract_example_only = bool(manifest.get("contractExampleOnly")) if manifest else False
    invalid_text_box_ids = validate_boxes(text_boxes, "textBox", image_width, image_height, coordinate_errors)
    invalid_bubble_ids = validate_boxes(bubbles, "bubble", image_width, image_height, coordinate_errors)

    segment_size_matches = None
    if segment_mask is not None:
        width = segment_mask.get("width")
        height = segment_mask.get("height")
        if isinstance(width, int) and isinstance(height, int):
            segment_size_matches = width == image_width and height == image_height
            if not segment_size_matches:
                coordinate_errors.append(f"segmentMaskSizeMismatch:{width}x{height}")
        else:
            coordinate_errors.append("segmentMaskSizeMissing")

    if allow_missing and not root.exists():
        missing_artifacts = ["manifest", "TextBoxes", "BubbleMask", "SegmentMask"]

    verdict = verdict_for(
        manifest_found=manifest is not None,
        missing_artifacts=missing_artifacts,
        parse_errors=parse_errors,
        coordinate_errors=coordinate_errors,
        text_boxes=text_boxes,
        bubbles=bubbles,
        segment_mask=segment_mask,
        contract_example_only=contract_example_only,
    )
    active_artifacts_directory = is_active_artifacts_root(root) and root.exists()
    shadow_allowed = verdict == "readyForShadowOCR" and active_artifacts_directory and not contract_example_only
    blockers = readiness_blockers(
        verdict,
        missing_artifacts,
        parse_errors,
        coordinate_errors,
        contract_example_only,
        active_artifacts_directory,
    )
    return {
        "root": str(root),
        "activeArtifactsDirectory": active_artifacts_directory,
        "manifestFound": manifest is not None,
        "contractExampleOnly": contract_example_only,
        "verdict": verdict,
        "readyForShadowOCR": verdict == "readyForShadowOCR",
        "validationPassed": verdict in {"readyForShadowOCR", "contractExampleOnly"},
        "externalTextBoxesShadowOCRAllowed": shadow_allowed,
        "nextAction": next_action_for(verdict),
        "readinessBlockers": blockers,
        "requiredFiles": REQUIRED_ARTIFACT_FILES,
        "activeArtifactPolicy": {
            "activeInputDirectory": str(ACTIVE_ARTIFACT_ROOT),
            "examplesDirectory": "md/koharu研究/artifact_contract/examples",
            "examplesMayEnableShadowOCR": False,
            "forbiddenActiveSources": [
                "contract examples",
                "Vision OCR blocks",
                "pre-crop plan",
                "line plan",
                "BubbleMask proxy",
                "SegmentMask proxy",
                "ground truth",
                "handwritten ideal boxes",
            ],
        },
        "missingArtifacts": missing_artifacts,
        "parseErrors": parse_errors,
        "coordinateErrors": coordinate_errors,
        "sourceImage": source_image,
        "coordinateSpace": coordinate_space,
        "imageWidth": image_width,
        "imageHeight": image_height,
        "manifestPath": str(manifest_path),
        "textBoxesPath": str(textboxes_path),
        "bubbleMaskPath": str(bubbles_path),
        "segmentMaskPath": str(segment_path),
        "textBoxCount": len(text_boxes),
        "bubbleInstanceCount": len(bubbles),
        "segmentMaskSizeMatches": segment_size_matches,
        "invalidTextBoxIDs": invalid_text_box_ids,
        "invalidBubbleInstanceIDs": invalid_bubble_ids,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, help="Artifact root containing 1.manifest.json or fallback files.")
    parser.add_argument("--allow-missing", action="store_true", help="Return success when the root is missing, with a blocking verdict.")
    parser.add_argument("--expect-fail", action="store_true", help="Return success only when validation fails.")
    parser.add_argument("--print-required-files", action="store_true", help="Print the required active artifact file checklist and exit.")
    parser.add_argument("--image", default=str(DEFAULT_IMAGE_PATH), help="Probe source image used for coordinate bounds.")
    args = parser.parse_args()

    root = Path(args.root)
    if args.print_required_files:
        summary = {
            "activeInputDirectory": str(ACTIVE_ARTIFACT_ROOT),
            "sourceImage": EXPECTED_SOURCE_IMAGE,
            "coordinateSpace": EXPECTED_COORDINATE_SPACE,
            "requiredFiles": REQUIRED_ARTIFACT_FILES,
            "readyForShadowOCRRequires": [
                "verdict == readyForShadowOCR",
                "activeArtifactsDirectory == true",
                "contractExampleOnly == false",
                "externalTextBoxesShadowOCRAllowed == true",
            ],
            "forbiddenActiveSources": [
                "contract examples",
                "Vision OCR blocks",
                "pre-crop plan",
                "line plan",
                "BubbleMask proxy",
                "SegmentMask proxy",
                "ground truth",
                "handwritten ideal boxes",
            ],
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        print()
        return 0

    image_path = Path(args.image)
    if not root.exists() and not args.allow_missing:
        active_artifacts_directory = is_active_artifacts_root(root) and root.exists()
        summary = {
            "root": str(root),
            "activeArtifactsDirectory": active_artifacts_directory,
            "manifestFound": False,
            "contractExampleOnly": False,
            "verdict": "manifestMissing",
            "readyForShadowOCR": False,
            "validationPassed": False,
            "externalTextBoxesShadowOCRAllowed": False,
            "nextAction": "stopUntilArtifactsProvided",
            "readinessBlockers": [
                "activeArtifactsDirectoryMissing",
                "missing:manifest",
                "missing:TextBoxes",
                "missing:BubbleMask",
                "missing:SegmentMask",
            ],
            "requiredFiles": REQUIRED_ARTIFACT_FILES,
            "missingArtifacts": ["manifest", "TextBoxes", "BubbleMask", "SegmentMask"],
            "parseErrors": [],
            "coordinateErrors": [],
            "textBoxCount": 0,
            "bubbleInstanceCount": 0,
            "segmentMaskSizeMatches": None,
        }
    else:
        summary = validate(root, args.allow_missing, image_path)

    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print()
    failed = not bool(summary.get("validationPassed"))
    if args.expect_fail:
        return 0 if failed else 1
    if args.allow_missing and summary["verdict"] in {"manifestMissing", "artifactFilesMissing"}:
        return 0
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
