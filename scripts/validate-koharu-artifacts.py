#!/usr/bin/env python3
"""Validate AITRANS Koharu external artifact contract files."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shlex
import shutil
import struct
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path
from typing import Any


EXPECTED_COORDINATE_SPACE = "originalImageTopLeftPixels"
EXPECTED_SOURCE_IMAGE = "test/1.png"
EXPECTED_SCHEMA_VERSION = "aitrans.koharu_artifact_contract.v1"
DEFAULT_IMAGE_PATH = Path("test/1.png")
ACTIVE_ARTIFACT_ROOT = Path("test/koharu_artifacts")
FORBIDDEN_GENERATED_BY_TERMS = [
    "contract example",
    "fixture",
    "manual",
    "vision ocr",
    "visionocr",
    "pre-crop",
    "precrop",
    "line plan",
    "bubblemask proxy",
    "bubble mask proxy",
    "segmentmask proxy",
    "segment mask proxy",
    "ground truth",
    "handwritten",
]
ALLOWED_SOURCE_DIRECTIONS = {
    "horizontal",
    "horizontal-lr",
    "vertical",
    "vertical-rl",
    "vertical-lr",
    "unknown",
}
REQUIRED_ARTIFACT_FILES = [
    {
        "path": "test/koharu_artifacts/1.manifest.json",
        "kind": "manifest",
        "required": True,
        "notes": [
            "schemaVersion must be aitrans.koharu_artifact_contract.v1",
            "sourceImage must be test/1.png",
            "sourceImageSHA256 must match the current repository test/1.png",
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
            "sourceDirection, when present, must be horizontal/vertical/vertical-rl/vertical-lr/unknown",
            "rotationDegrees or rotationDeg, when present, must be finite and within [-360, 360]",
            "linePolygons, when present, must contain point pairs within source image bounds",
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
CANONICAL_ARTIFACT_FILENAMES = {
    "manifest": "1.manifest.json",
    "TextBoxes": "1.textboxes.json",
    "BubbleMask": "1.bubbles.json",
    "SegmentMask": "1.segment_mask.json",
}
CANONICAL_ARTIFACT_FILE_LIST = [
    "1.manifest.json",
    "1.textboxes.json",
    "1.bubbles.json",
    "1.segment_mask.json",
]


def count_strings(values: list[str]) -> dict[str, int]:
    result: dict[str, int] = {}
    for value in values:
        result[value] = result.get(value, 0) + 1
    return dict(sorted(result.items()))


def file_identity(path: Path) -> dict[str, Any]:
    summary: dict[str, Any] = {
        "path": str(path),
        "exists": path.is_file(),
        "sizeBytes": None,
        "sha256": None,
    }
    if not path.is_file():
        return summary
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            size += len(chunk)
            digest.update(chunk)
    summary["sizeBytes"] = size
    summary["sha256"] = digest.hexdigest()
    return summary


def stable_archive_dir_name(root: Path, archive_path: Path) -> str:
    raw = archive_path.stem or root.name or "koharu_artifacts"
    normalized = "".join(char if char.isalnum() or char in "._-" else "-" for char in raw)
    normalized = normalized.strip(".-_")
    return normalized or "koharu_artifacts"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_archive_target(root: Path, member_name: str) -> Path:
    if member_name.startswith("/") or member_name.startswith("\\"):
        raise SystemExit(f"Refusing to inspect archive with absolute member path: {member_name}")
    target = (root / member_name).resolve(strict=False)
    root_resolved = root.resolve(strict=False)
    try:
        target.relative_to(root_resolved)
    except ValueError:
        raise SystemExit(f"Refusing to inspect archive with path escape member: {member_name}")
    return target


def extract_release_archive(archive_path: Path, extract_dir: Path) -> list[str]:
    archive_name = archive_path.name
    if archive_name.endswith(".zip"):
        with zipfile.ZipFile(archive_path, "r") as archive:
            members = archive.namelist()
            for member in members:
                safe_archive_target(extract_dir, member)
            archive.extractall(extract_dir)
            return members
    if archive_name.endswith(".tar.gz") or archive_name.endswith(".tgz") or archive_name.endswith(".tar"):
        mode = "r:gz" if archive_name.endswith((".tar.gz", ".tgz")) else "r:"
        with tarfile.open(archive_path, mode) as archive:
            members_info = archive.getmembers()
            for member in members_info:
                if member.issym() or member.islnk():
                    raise SystemExit(f"Refusing to inspect archive with link member: {member.name}")
                safe_archive_target(extract_dir, member.name)
            archive.extractall(extract_dir)
            return [member.name for member in members_info]
    raise SystemExit(f"Unsupported Koharu archive type: {archive_path}")


def koharu_candidate_dirs(extract_dir: Path) -> list[Path]:
    candidate_dirs = []
    for candidate in sorted({path.parent for path in extract_dir.rglob("1.manifest.json") if path.is_file()}):
        if all((candidate / name).is_file() for name in CANONICAL_ARTIFACT_FILE_LIST):
            candidate_dirs.append(candidate)
    return candidate_dirs


def inspect_release_archive(archive_path: Path, image_path: Path) -> dict[str, Any]:
    if not archive_path.is_file():
        return {
            "archive": file_identity(archive_path),
            "validationPassed": False,
            "verdict": "archiveMissing",
            "candidateDirectoryCount": 0,
            "candidateDirectories": [],
            "validation": None,
        }
    temp_dir = Path(tempfile.mkdtemp(prefix="aitrans-koharu-archive-"))
    try:
        extract_dir = temp_dir / "extract"
        extract_dir.mkdir(parents=True, exist_ok=True)
        members = extract_release_archive(archive_path, extract_dir)
        candidates = koharu_candidate_dirs(extract_dir)
        archive_identity = file_identity(archive_path)
        archive_identity["members"] = members
        archive_identity["memberCount"] = len(members)
        candidate_names = [str(path.relative_to(extract_dir)) for path in candidates]
        if len(candidates) != 1:
            return {
                "archive": archive_identity,
                "validationPassed": False,
                "verdict": "archiveCandidateDirectoryCountMismatch",
                "candidateDirectoryCount": len(candidates),
                "candidateDirectories": candidate_names,
                "expectedCanonicalFiles": CANONICAL_ARTIFACT_FILE_LIST,
                "validation": None,
            }
        validation = validate(candidates[0], False, image_path)
        return {
            "archive": archive_identity,
            "validationPassed": bool(validation.get("validationPassed")),
            "verdict": validation.get("verdict"),
            "readyForShadowOCR": validation.get("readyForShadowOCR"),
            "externalTextBoxesShadowOCRAllowedAfterCIInjection": validation.get("verdict") == "readyForShadowOCR",
            "candidateDirectoryCount": 1,
            "candidateDirectory": candidate_names[0],
            "candidateDirectories": candidate_names,
            "expectedCanonicalFiles": CANONICAL_ARTIFACT_FILE_LIST,
            "validation": validation,
        }
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def package_release_archive(
    summary: dict[str, Any],
    archive_path: Path,
    root: Path,
    *,
    allow_fixture_package: bool,
    image_path: Path,
) -> dict[str, Any]:
    verdict = summary.get("verdict")
    if verdict != "readyForShadowOCR" and not (allow_fixture_package and verdict == "contractExampleOnly"):
        raise SystemExit(
            "Refusing to package Koharu handoff archive because verdict is "
            f"{verdict!r}; expected readyForShadowOCR."
        )

    source_paths = {
        "manifest": Path(str(summary.get("manifestPath") or root / "1.manifest.json")),
        "TextBoxes": Path(str(summary.get("textBoxesPath") or root / "1.textboxes.json")),
        "BubbleMask": Path(str(summary.get("bubbleMaskPath") or root / "1.bubbles.json")),
        "SegmentMask": Path(str(summary.get("segmentMaskPath") or root / "1.segment_mask.json")),
    }
    missing = [kind for kind, path in source_paths.items() if not path.is_file()]
    if missing:
        raise SystemExit(f"Refusing to package Koharu handoff archive; missing files: {missing}")

    archive_resolved = archive_path.resolve(strict=False)
    source_collisions = [
        str(path)
        for path in source_paths.values()
        if archive_resolved == path.resolve(strict=False)
    ]
    if source_collisions:
        raise SystemExit(
            "Refusing to package Koharu handoff archive because archive path would overwrite source artifact file: "
            f"{source_collisions[0]}"
        )

    archive_path.parent.mkdir(parents=True, exist_ok=True)
    archive_dir = stable_archive_dir_name(root, archive_path)
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for kind, filename in CANONICAL_ARTIFACT_FILENAMES.items():
            archive.write(source_paths[kind], f"{archive_dir}/{filename}")

    archive_members = []
    with zipfile.ZipFile(archive_path, "r") as archive:
        archive_members = archive.namelist()
    archive_sha = sha256_file(archive_path)
    inspection = inspect_release_archive(archive_path, image_path)
    return {
        "path": str(archive_path),
        "exists": archive_path.is_file(),
        "sizeBytes": archive_path.stat().st_size,
        "sha256": archive_sha,
        "inspection": {
            "validationPassed": inspection.get("validationPassed"),
            "verdict": inspection.get("verdict"),
            "candidateDirectoryCount": inspection.get("candidateDirectoryCount"),
            "candidateDirectory": inspection.get("candidateDirectory"),
            "archive": {
                "memberCount": ((inspection.get("archive") or {}).get("memberCount")),
                "members": ((inspection.get("archive") or {}).get("members")),
            },
            "artifactIdentitySummary": ((inspection.get("validation") or {}).get("artifactIdentitySummary")),
            "orientationMetadataSummary": ((inspection.get("validation") or {}).get("orientationMetadataSummary")),
        },
        "layout": {
            "singleDirectory": archive_dir,
            "canonicalFiles": [
                f"{archive_dir}/{CANONICAL_ARTIFACT_FILENAMES[kind]}"
                for kind in ["manifest", "TextBoxes", "BubbleMask", "SegmentMask"]
            ],
            "members": archive_members,
            "uniqueDirectoryCheckExpected": True,
        },
        "sourceFiles": {
            kind: file_identity(path)
            for kind, path in source_paths.items()
        },
    }


def handoff_packet(
    summary: dict[str, Any],
    *,
    repo: str,
    probe_mode: str,
    release_tag: str,
    release_asset: str | None,
    archive_identity: dict[str, Any] | None,
) -> dict[str, Any]:
    archive_sha = (archive_identity or {}).get("sha256")
    archive_asset = release_asset or Path(str((archive_identity or {}).get("path") or "koharu-artifacts.zip")).name
    archive_path = str((archive_identity or {}).get("path") or "<archive-path>")
    archive_inspection = (archive_identity or {}).get("inspection") or {}
    archive_inspection_passed = bool(archive_inspection.get("validationPassed"))
    release_upload_args = [
        "gh",
        "release",
        "upload",
        release_tag,
        archive_path,
        "--repo",
        repo,
    ]
    workflow_args = [
        "gh",
        "workflow",
        "run",
        "ci-results.yml",
        "--repo",
        repo,
        "--ref",
        "smalldata_test",
        "-f",
        f"probe_mode={probe_mode}",
        "-f",
        f"koharu_artifact_release_tag={release_tag}",
        "-f",
        f"koharu_artifact_asset={archive_asset}",
        "-f",
        f"koharu_artifact_sha256={archive_sha or '<archive-sha256>'}",
        "-f",
        "koharu_artifact_required=true",
    ]
    inspect_args = [
        "python3",
        "scripts/validate-koharu-artifacts.py",
        "--inspect-release-archive",
        archive_path,
    ]
    handoff_ready = (
        summary.get("verdict") == "readyForShadowOCR"
        and bool(archive_sha)
        and archive_inspection_passed
    )
    return {
        "handoffReadyForReleaseUpload": handoff_ready,
        "handoffReadyForWorkflowDispatch": handoff_ready,
        "validationVerdict": summary.get("verdict"),
        "readyForShadowOCR": summary.get("readyForShadowOCR"),
        "externalTextBoxesShadowOCRAllowed": summary.get("externalTextBoxesShadowOCRAllowed"),
        "afterCIInjectionExpectedExternalTextBoxesShadowOCRAllowed": summary.get("verdict") == "readyForShadowOCR",
        "readinessBlockers": summary.get("readinessBlockers"),
        "sourceImage": summary.get("sourceImage"),
        "sourceImageSHA256": summary.get("sourceImageSHA256"),
        "expectedSourceImageSHA256": summary.get("expectedSourceImageSHA256"),
        "sourceImageSHA256Matches": summary.get("sourceImageSHA256Matches"),
        "artifactCounts": {
            "textBoxCount": summary.get("textBoxCount"),
            "bubbleInstanceCount": summary.get("bubbleInstanceCount"),
            "segmentMaskSizeMatches": summary.get("segmentMaskSizeMatches"),
        },
        "artifactIdentitySummary": summary.get("artifactIdentitySummary"),
        "orientationMetadataSummary": summary.get("orientationMetadataSummary"),
        "releaseArchive": archive_identity,
        "releaseArchiveInspectionPassed": archive_inspection_passed,
        "releaseArchiveInspectionVerdict": archive_inspection.get("verdict"),
        "inspectReleaseArchiveCommand": shlex.join(inspect_args),
        "workflowDispatchInputs": {
            "probe_mode": probe_mode,
            "koharu_artifact_release_tag": release_tag,
            "koharu_artifact_asset": archive_asset,
            "koharu_artifact_sha256": archive_sha or "<archive-sha256>",
            "koharu_artifact_required": "true",
        },
        "releaseUpload": {
            "repo": repo,
            "tag": release_tag,
            "assetPath": archive_path,
            "assetName": archive_asset,
            "requiresExistingRelease": True,
            "clobberByDefault": False,
        },
        "expectedCIManifestEcho": {
            "koharuArtifactReleaseTag": release_tag,
            "koharuArtifactAsset": archive_asset,
            "koharuArtifactSha256": archive_sha or "<archive-sha256>",
            "koharuArtifactValidationIdentitySummary": "must match releaseArchive.inspection.artifactIdentitySummary after CI injection",
            "koharuArtifactValidationOrientationSummary": "must match releaseArchive.inspection.orientationMetadataSummary after CI injection",
            "koharuArtifactIdentityReconciliationMatch.matchVerdict": "matched",
        },
        "ghReleaseUploadCommand": shlex.join(release_upload_args),
        "ghWorkflowDispatchCommand": shlex.join(workflow_args),
        "ghRunListCommand": shlex.join([
            "gh",
            "run",
            "list",
            "--workflow",
            "ci-results.yml",
            "--branch",
            "smalldata_test",
            "--limit",
            "1",
            "--repo",
            repo,
        ]),
        "notes": [
            "ghReleaseUploadCommand requires the named GitHub Release tag to already exist.",
            "Do not add --clobber unless a human intentionally wants to replace an existing asset.",
            "CI will reject archives that do not contain exactly one directory with the four canonical JSON files.",
            "releaseArchive.inspection is a local preflight proof; Agent C must still verify the cloud manifest and App runtime reports.",
            "Agent C must still verify App runtime readiness, identity reconciliation, shadow OCR coverage, and orientation gates from the CI result artifact.",
        ],
    }


def declared_source_image_sha256(manifest: dict[str, Any] | None) -> Any:
    if manifest is None:
        return None
    for key in ["sourceImageSHA256", "sourceImageSha256", "sourceImageSha"]:
        if key in manifest:
            return manifest.get(key)
    identity = manifest.get("sourceImageIdentity")
    if isinstance(identity, dict):
        return identity.get("sha256")
    return None


def normalized_sha256(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip().lower()
    if len(normalized) != 64:
        return None
    if any(char not in "0123456789abcdef" for char in normalized):
        return None
    return normalized


def is_active_artifacts_root(root: Path) -> bool:
    return root.resolve() == ACTIVE_ARTIFACT_ROOT.resolve()


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


def resolve_path(
    root: Path,
    manifest: dict[str, Any] | None,
    key: str,
    fallback: str,
    parse_errors: list[str],
) -> Path:
    value = manifest.get(key) if isinstance(manifest, dict) else None
    if isinstance(value, str) and value.strip():
        candidate = Path(value)
        if candidate.is_absolute() or ".." in candidate.parts:
            parse_errors.append(f"manifest:{key}:pathEscapesActiveArtifactRoot")
            return root / fallback
        return root / candidate
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


def normalized_source_direction(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip().lower().replace("_", "-").replace(" ", "-")
    while "--" in normalized:
        normalized = normalized.replace("--", "-")
    return normalized


def rotation_degrees_for(item: dict[str, Any]) -> float | None:
    value = item.get("rotationDegrees")
    if value is None:
        value = item.get("rotationDeg")
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return math.nan


def nearest_supported_rotation(value: float) -> int | None:
    normalized = math.fmod(value, 360)
    positive = normalized + 360 if normalized < 0 else normalized
    supported = [0, 90, 180, 270, 360]
    nearest = min(supported, key=lambda candidate: abs(candidate - positive))
    if abs(nearest - positive) > 7.5:
        return None
    return 0 if nearest == 360 else nearest


def orientation_category_for(item: dict[str, Any]) -> str:
    if "sourceDirection" not in item:
        return "unspecified"
    normalized = normalized_source_direction(item.get("sourceDirection"))
    if normalized is None:
        return "invalid"
    if normalized.startswith("vertical"):
        return "vertical"
    if normalized.startswith("horizontal"):
        return "horizontal"
    if normalized == "unknown":
        return "unknown"
    return "invalid"


def orientation_shadow_plan_for(item: dict[str, Any]) -> tuple[list[int], list[str]]:
    rotation_angles = [0]
    unsupported_reasons: list[str] = []
    normalized_direction = normalized_source_direction(item.get("sourceDirection"))
    orientation_category = orientation_category_for(item)
    if orientation_category == "vertical":
        rotation_angles.append(270 if normalized_direction == "vertical-lr" else 90)

    rotation = rotation_degrees_for(item)
    if rotation is not None and math.isfinite(rotation) and abs(rotation) > 0.001:
        supported_rotation = nearest_supported_rotation(rotation)
        if supported_rotation is None:
            unsupported_reasons.append("arbitraryRotationUnsupported")
        elif supported_rotation != 0:
            rotation_angles.append(supported_rotation)

    line_polygons = item.get("linePolygons")
    if isinstance(line_polygons, list) and line_polygons:
        unsupported_reasons.append("linePolygonWarpUnsupported")

    unique_angles: list[int] = []
    seen: set[int] = set()
    for angle in rotation_angles:
        if angle not in seen:
            unique_angles.append(angle)
            seen.add(angle)
    return unique_angles, sorted(set(unsupported_reasons))


def summarize_orientation_metadata(text_boxes: list[dict[str, Any]]) -> dict[str, Any]:
    text_box_count = len(text_boxes)
    source_directions: list[str] = []
    orientation_categories: list[str] = []
    line_polygon_ids: list[str] = []
    rotation_ids: list[str] = []
    vertical_ids: list[str] = []
    right_angle_rotation_ids: list[str] = []
    arbitrary_rotation_ids: list[str] = []
    orientation_needed_ids: list[str] = []
    rotation_shadow_supported_ids: list[str] = []
    orientation_partial_ids: list[str] = []
    unsupported_ids: list[str] = []
    unsupported_reasons: list[str] = []
    rotation_plan_values: list[str] = []

    for index, item in enumerate(text_boxes):
        item_id = str(item.get("id") or f"textBox-{index}")
        normalized_direction = normalized_source_direction(item.get("sourceDirection")) if "sourceDirection" in item else None
        source_directions.append(normalized_direction or "unspecified")
        orientation_category = orientation_category_for(item)
        orientation_categories.append(orientation_category)
        if orientation_category == "vertical":
            vertical_ids.append(item_id)

        line_polygons = item.get("linePolygons")
        line_polygons_present = isinstance(line_polygons, list) and bool(line_polygons)
        if line_polygons_present:
            line_polygon_ids.append(item_id)

        rotation = rotation_degrees_for(item)
        has_nonzero_rotation = rotation is not None and math.isfinite(rotation) and abs(rotation) > 0.001
        supported_rotation = nearest_supported_rotation(rotation) if has_nonzero_rotation else None
        if has_nonzero_rotation:
            rotation_ids.append(item_id)
            if supported_rotation is None:
                arbitrary_rotation_ids.append(item_id)
            else:
                right_angle_rotation_ids.append(item_id)

        orientation_needed = orientation_category == "vertical" or line_polygons_present or has_nonzero_rotation
        rotation_angles, reasons = orientation_shadow_plan_for(item)
        rotation_plan_values.append(",".join(str(angle) for angle in rotation_angles))
        if orientation_needed:
            orientation_needed_ids.append(item_id)
        if orientation_needed and any(abs(angle) > 0 for angle in rotation_angles):
            rotation_shadow_supported_ids.append(item_id)
        if reasons:
            unsupported_ids.append(item_id)
            unsupported_reasons.extend(reasons)
        if reasons and any(abs(angle) > 0 for angle in rotation_angles):
            orientation_partial_ids.append(item_id)

    return {
        "textBoxCount": text_box_count,
        "sourceDirectionBreakdown": count_strings(source_directions),
        "orientationCategoryBreakdown": count_strings(orientation_categories),
        "rotationPlanBreakdown": count_strings(rotation_plan_values),
        "linePolygonTextBoxIDs": sorted(set(line_polygon_ids)),
        "rotationTextBoxIDs": sorted(set(rotation_ids)),
        "verticalTextBoxIDs": sorted(set(vertical_ids)),
        "rightAngleRotationTextBoxIDs": sorted(set(right_angle_rotation_ids)),
        "arbitraryRotationTextBoxIDs": sorted(set(arbitrary_rotation_ids)),
        "orientationShadowPathNeededTextBoxIDs": sorted(set(orientation_needed_ids)),
        "orientationRotationShadowSupportedTextBoxIDs": sorted(set(rotation_shadow_supported_ids)),
        "orientationPartialTextBoxIDs": sorted(set(orientation_partial_ids)),
        "orientationUnsupportedTextBoxIDs": sorted(set(unsupported_ids)),
        "orientationUnsupportedReasonBreakdown": count_strings(unsupported_reasons),
        "currentShadowOCRSupport": {
            "boundedRightAngleRotationOCR": True,
            "verticalRotationOCR": True,
            "linePolygonWarp": False,
            "arbitraryAngleDeskew": False,
        },
    }


def summarize_artifact_identity(
    root: Path,
    image_path: Path,
    manifest_path: Path,
    textboxes_path: Path,
    bubbles_path: Path,
    segment_path: Path,
    manifest: dict[str, Any] | None,
    active_artifacts_directory: bool,
) -> dict[str, Any]:
    source_image_identity = file_identity(image_path)
    source_image_sha_declared = declared_source_image_sha256(manifest)
    source_image_sha_normalized = normalized_sha256(source_image_sha_declared)
    source_image_sha_expected = source_image_identity.get("sha256")
    return {
        "root": str(root),
        "activeArtifactsDirectory": active_artifacts_directory,
        "sourceImageExpected": EXPECTED_SOURCE_IMAGE,
        "sourceImageDeclared": manifest.get("sourceImage") if manifest else None,
        "sourceImageSHA256Expected": source_image_sha_expected,
        "sourceImageSHA256Declared": source_image_sha_declared,
        "sourceImageSHA256Matches": (
            source_image_sha_normalized == source_image_sha_expected
            if source_image_sha_normalized is not None and source_image_sha_expected is not None
            else False
        ),
        "schemaVersionDeclared": manifest.get("schemaVersion") if manifest else None,
        "coordinateSpaceDeclared": manifest.get("coordinateSpace") if manifest else None,
        "contractExampleOnly": bool(manifest.get("contractExampleOnly")) if manifest else False,
        "generatedBy": manifest.get("generatedBy") if manifest else None,
        "generatedAt": manifest.get("generatedAt") if manifest else None,
        "sourceImage": source_image_identity,
        "artifactFiles": {
            "manifest": file_identity(manifest_path),
            "TextBoxes": file_identity(textboxes_path),
            "BubbleMask": file_identity(bubbles_path),
            "SegmentMask": file_identity(segment_path),
        },
    }


def validate_textbox_metadata(
    item: dict[str, Any],
    item_id: str,
    image_width: int,
    image_height: int,
    coordinate_errors: list[str],
) -> bool:
    valid = True
    if "sourceDirection" in item:
        source_direction = normalized_source_direction(item.get("sourceDirection"))
        if source_direction not in ALLOWED_SOURCE_DIRECTIONS:
            coordinate_errors.append(f"textBox:{item_id}:sourceDirectionInvalid")
            valid = False
    rotation = rotation_degrees_for(item)
    if rotation is not None:
        if not math.isfinite(rotation):
            coordinate_errors.append(f"textBox:{item_id}:rotationDegreesInvalid")
            valid = False
        elif rotation < -360 or rotation > 360:
            coordinate_errors.append(f"textBox:{item_id}:rotationDegreesOutOfRange")
            valid = False
    line_polygons = item.get("linePolygons")
    if line_polygons is not None:
        if not isinstance(line_polygons, list) or not line_polygons:
            coordinate_errors.append(f"textBox:{item_id}:linePolygonsInvalid")
            return False
        for polygon_index, polygon in enumerate(line_polygons):
            if not isinstance(polygon, list) or len(polygon) < 4:
                coordinate_errors.append(f"textBox:{item_id}:linePolygonInvalid:{polygon_index}")
                valid = False
                continue
            for point_index, point in enumerate(polygon):
                if not isinstance(point, list) or len(point) != 2:
                    coordinate_errors.append(f"textBox:{item_id}:linePolygonPointInvalid:{polygon_index}:{point_index}")
                    valid = False
                    continue
                try:
                    x = float(point[0])
                    y = float(point[1])
                except (TypeError, ValueError):
                    coordinate_errors.append(f"textBox:{item_id}:linePolygonPointInvalid:{polygon_index}:{point_index}")
                    valid = False
                    continue
                if not math.isfinite(x) or not math.isfinite(y):
                    coordinate_errors.append(f"textBox:{item_id}:linePolygonPointInvalid:{polygon_index}:{point_index}")
                    valid = False
                elif x < 0 or y < 0 or x > image_width or y > image_height:
                    coordinate_errors.append(f"textBox:{item_id}:linePolygonPointOutOfBounds:{polygon_index}:{point_index}")
                    valid = False
    return valid


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
        if label == "textBox" and not validate_textbox_metadata(
            item,
            item_id,
            image_width,
            image_height,
            coordinate_errors,
        ):
            invalid_ids.append(item_id)
    return sorted(set(invalid_ids))


def generated_by_policy_errors(manifest: dict[str, Any] | None, contract_example_only: bool) -> list[str]:
    if manifest is None or contract_example_only:
        return []
    generated_by = manifest.get("generatedBy")
    if not isinstance(generated_by, str) or not generated_by.strip():
        return ["generatedByMissing"]
    normalized = generated_by.strip().lower().replace("_", "-")
    errors = []
    for term in FORBIDDEN_GENERATED_BY_TERMS:
        if term in normalized:
            errors.append(f"forbiddenGeneratedBy:{term}")
    return errors


def verdict_for(
    manifest_found: bool,
    missing_artifacts: list[str],
    parse_errors: list[str],
    coordinate_errors: list[str],
    source_policy_errors: list[str],
    text_boxes: list[dict[str, Any]],
    bubbles: list[dict[str, Any]],
    segment_mask: dict[str, Any] | None,
    contract_example_only: bool,
) -> str:
    if not manifest_found:
        return "manifestMissing"
    if parse_errors:
        return "parseFailed"
    if any(error.startswith("schemaVersionMissing") for error in coordinate_errors):
        return "schemaVersionMissing"
    if any(error.startswith("schemaVersionMismatch") for error in coordinate_errors):
        return "schemaVersionMismatch"
    if any(error.startswith("coordinateSpaceMissing") for error in coordinate_errors):
        return "coordinateSpaceMissing"
    if any(error.startswith("coordinateSpaceMismatch") for error in coordinate_errors):
        return "coordinateSpaceMismatch"
    if any(error.startswith("sourceImageMissing") for error in coordinate_errors):
        return "sourceImageMissing"
    if any(error.startswith("sourceImageMismatch") for error in coordinate_errors):
        return "sourceImageMismatch"
    if any(error.startswith("sourceImageSHA256Missing") for error in coordinate_errors):
        return "sourceImageSHA256Missing"
    if any(error.startswith("sourceImageSHA256Invalid") for error in coordinate_errors):
        return "sourceImageSHA256Invalid"
    if any(error.startswith("sourceImageSHA256Mismatch") for error in coordinate_errors):
        return "sourceImageSHA256Mismatch"
    if coordinate_errors:
        return "coordinateValidationFailed"
    if any(error.startswith("contractExampleOnlyMissing") for error in source_policy_errors):
        return "contractExampleOnlyMissing"
    if any(error.startswith("contractExampleOnlyInvalid") for error in source_policy_errors):
        return "contractExampleOnlyInvalid"
    if any(error.startswith("generatedByMissing") for error in source_policy_errors):
        return "generatedByMissing"
    if any(error.startswith("forbiddenGeneratedBy") for error in source_policy_errors):
        return "forbiddenGeneratedBy"
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
        "contractExampleOnlyMissing",
        "contractExampleOnlyInvalid",
        "generatedByMissing",
        "forbiddenGeneratedBy",
    }:
        return "stopUntilRealDetectorSourceDeclared"
    if verdict in {
        "schemaVersionMissing",
        "schemaVersionMismatch",
        "coordinateSpaceMissing",
        "coordinateSpaceMismatch",
        "sourceImageMissing",
        "sourceImageMismatch",
        "sourceImageSHA256Missing",
        "sourceImageSHA256Invalid",
        "sourceImageSHA256Mismatch",
        "coordinateValidationFailed",
    }:
        return "stopUntilArtifactContractFixed"
    return "stopUntilArtifactsProvided"


def readiness_blockers(
    verdict: str,
    missing_artifacts: list[str],
    parse_errors: list[str],
    coordinate_errors: list[str],
    source_policy_errors: list[str],
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
    blockers.extend(f"sourcePolicy:{item}" for item in source_policy_errors)
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

    textboxes_path = resolve_path(root, manifest, "textBoxesPath", "1.textboxes.json", parse_errors)
    bubbles_path = resolve_path(root, manifest, "bubbleMaskPath", "1.bubbles.json", parse_errors)
    segment_path = resolve_path(root, manifest, "segmentMaskPath", "1.segment_mask.json", parse_errors)

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
    schema_version = manifest.get("schemaVersion") if manifest else None
    if manifest is not None:
        if schema_version is None:
            coordinate_errors.append("schemaVersionMissing")
        elif schema_version != EXPECTED_SCHEMA_VERSION:
            coordinate_errors.append(f"schemaVersionMismatch:{schema_version}")

        if coordinate_space is None:
            coordinate_errors.append("coordinateSpaceMissing")
        elif coordinate_space != EXPECTED_COORDINATE_SPACE:
            coordinate_errors.append(f"coordinateSpaceMismatch:{coordinate_space}")

    source_image = manifest.get("sourceImage") if manifest else None
    source_image_sha = declared_source_image_sha256(manifest)
    source_image_identity = file_identity(image_path)
    expected_source_image_sha = source_image_identity.get("sha256")
    if manifest is not None:
        if source_image is None:
            coordinate_errors.append("sourceImageMissing")
        elif source_image != EXPECTED_SOURCE_IMAGE:
            coordinate_errors.append(f"sourceImageMismatch:{source_image}")
        source_image_sha_normalized = normalized_sha256(source_image_sha)
        if source_image_sha is None:
            coordinate_errors.append("sourceImageSHA256Missing")
        elif source_image_sha_normalized is None:
            coordinate_errors.append(f"sourceImageSHA256Invalid:{source_image_sha}")
        elif expected_source_image_sha is not None and source_image_sha_normalized != expected_source_image_sha:
            coordinate_errors.append(f"sourceImageSHA256Mismatch:{source_image_sha}")

    source_policy_errors: list[str] = []
    contract_example_only_raw = manifest.get("contractExampleOnly") if manifest else None
    if manifest is not None:
        if "contractExampleOnly" not in manifest:
            source_policy_errors.append("contractExampleOnlyMissing")
        elif not isinstance(contract_example_only_raw, bool):
            source_policy_errors.append(f"contractExampleOnlyInvalid:{contract_example_only_raw}")
    contract_example_only = contract_example_only_raw if isinstance(contract_example_only_raw, bool) else False
    source_policy_errors.extend(generated_by_policy_errors(manifest, contract_example_only))
    invalid_text_box_ids = validate_boxes(text_boxes, "textBox", image_width, image_height, coordinate_errors)
    invalid_bubble_ids = validate_boxes(bubbles, "bubble", image_width, image_height, coordinate_errors)
    orientation_metadata_summary = summarize_orientation_metadata(text_boxes)

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

    active_artifacts_directory = is_active_artifacts_root(root) and root.exists()
    artifact_identity_summary = summarize_artifact_identity(
        root,
        image_path,
        manifest_path,
        textboxes_path,
        bubbles_path,
        segment_path,
        manifest,
        active_artifacts_directory,
    )

    verdict = verdict_for(
        manifest_found=manifest is not None,
        missing_artifacts=missing_artifacts,
        parse_errors=parse_errors,
        coordinate_errors=coordinate_errors,
        source_policy_errors=source_policy_errors,
        text_boxes=text_boxes,
        bubbles=bubbles,
        segment_mask=segment_mask,
        contract_example_only=contract_example_only,
    )
    shadow_allowed = verdict == "readyForShadowOCR" and active_artifacts_directory and not contract_example_only
    blockers = readiness_blockers(
        verdict,
        missing_artifacts,
        parse_errors,
        coordinate_errors,
        source_policy_errors,
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
        "sourcePolicyErrors": source_policy_errors,
        "sourceImage": source_image,
        "sourceImageSHA256": source_image_sha,
        "expectedSourceImageSHA256": expected_source_image_sha,
        "sourceImageSHA256Matches": (
            normalized_sha256(source_image_sha) == expected_source_image_sha
            if normalized_sha256(source_image_sha) is not None and expected_source_image_sha is not None
            else False
        ),
        "schemaVersion": schema_version,
        "expectedSchemaVersion": EXPECTED_SCHEMA_VERSION,
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
        "artifactIdentitySummary": artifact_identity_summary,
        "orientationMetadataSummary": orientation_metadata_summary,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", help="Artifact root containing 1.manifest.json or fallback files.")
    parser.add_argument("--allow-missing", action="store_true", help="Return success when the root is missing, with a blocking verdict.")
    parser.add_argument("--expect-fail", action="store_true", help="Return success only when validation fails.")
    parser.add_argument("--print-required-files", action="store_true", help="Print the required active artifact file checklist and exit.")
    parser.add_argument("--emit-handoff-packet", action="store_true", help="Print Release upload and workflow_dispatch handoff guidance.")
    parser.add_argument("--package-release-archive", help="Write a zip archive with exactly one directory containing the four canonical artifact JSON files.")
    parser.add_argument("--inspect-release-archive", help="Inspect a zip/tar Release archive with the same unique four-file directory contract used by CI.")
    parser.add_argument("--repo", default="Altman-sam114/x113451", help="GitHub repository used in emitted gh handoff commands.")
    parser.add_argument("--probe-mode", default="ci-fast", choices=["ci-fast", "full"], help="Probe mode to include in emitted workflow_dispatch inputs.")
    parser.add_argument("--release-tag", default="<release-tag>", help="Release tag to include in the emitted workflow_dispatch inputs.")
    parser.add_argument("--release-asset", help="Release asset name to include in the emitted workflow_dispatch inputs.")
    parser.add_argument("--allow-fixture-package", action="store_true", help="Allow packaging contractExampleOnly examples for local smoke tests only.")
    parser.add_argument("--image", default=str(DEFAULT_IMAGE_PATH), help="Probe source image used for coordinate bounds.")
    args = parser.parse_args()

    image_path = Path(args.image)
    if args.inspect_release_archive:
        summary = inspect_release_archive(Path(args.inspect_release_archive), image_path)
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        print()
        failed = not bool(summary.get("validationPassed"))
        if args.expect_fail:
            return 0 if failed else 1
        return 1 if failed else 0

    if not args.root:
        parser.error("--root is required unless --inspect-release-archive is used")

    root = Path(args.root)
    if args.print_required_files:
        source_image_identity = file_identity(image_path)
        summary = {
            "activeInputDirectory": str(ACTIVE_ARTIFACT_ROOT),
            "sourceImage": EXPECTED_SOURCE_IMAGE,
            "sourceImageSHA256": source_image_identity.get("sha256"),
            "schemaVersion": EXPECTED_SCHEMA_VERSION,
            "coordinateSpace": EXPECTED_COORDINATE_SPACE,
            "requiredFiles": REQUIRED_ARTIFACT_FILES,
            "readyForShadowOCRRequires": [
                "verdict == readyForShadowOCR",
                "activeArtifactsDirectory == true",
                "contractExampleOnly == false",
                "externalTextBoxesShadowOCRAllowed == true",
                "manifest sourceImageSHA256 matches the current repository test/1.png SHA256",
                "artifactIdentitySummary source image and artifact SHA256 values match the reviewed archive",
                "TextBox optional direction metadata is valid when present",
                "orientationMetadataSummary unsupported line polygon / arbitrary rotation risks are reviewed before treating shadow OCR as closed",
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
            "sourcePolicyErrors": [],
            "sourceImage": None,
            "sourceImageSHA256": None,
            "expectedSourceImageSHA256": file_identity(image_path).get("sha256"),
            "sourceImageSHA256Matches": False,
            "textBoxCount": 0,
            "bubbleInstanceCount": 0,
            "segmentMaskSizeMatches": None,
            "artifactIdentitySummary": summarize_artifact_identity(
                root,
                image_path,
                root / "1.manifest.json",
                root / "1.textboxes.json",
                root / "1.bubbles.json",
                root / "1.segment_mask.json",
                None,
                active_artifacts_directory,
            ),
            "orientationMetadataSummary": summarize_orientation_metadata([]),
        }
    else:
        summary = validate(root, args.allow_missing, image_path)

    archive_identity = None
    if args.package_release_archive:
        archive_identity = package_release_archive(
            summary,
            Path(args.package_release_archive),
            root,
            allow_fixture_package=args.allow_fixture_package,
            image_path=image_path,
        )

    output = summary
    if args.emit_handoff_packet or archive_identity is not None:
        output = {
            "validation": summary,
            "handoffPacket": handoff_packet(
                summary,
                repo=args.repo,
                probe_mode=args.probe_mode,
                release_tag=args.release_tag,
                release_asset=args.release_asset,
                archive_identity=archive_identity,
            ),
        }

    print(json.dumps(output, ensure_ascii=False, indent=2))
    print()
    failed = not bool(summary.get("validationPassed"))
    if args.expect_fail:
        return 0 if failed else 1
    if args.allow_missing and summary["verdict"] in {"manifestMissing", "artifactFilesMissing"}:
        return 0
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
