#!/usr/bin/env python3
"""Generate a non-active Koharu artifact draft from an AITRANS probe report.

The draft is intentionally contractExampleOnly=true. It gives later handoff and
validator work a concrete four-file shape without pretending AITRANS proxy
geometry is real Koharu detector output.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "aitrans.koharu_artifact_contract.v1"
SOURCE_IMAGE = "test/1.png"
COORDINATE_SPACE = "originalImageTopLeftPixels"
DRAFT_FILENAMES = (
    "1.manifest.json",
    "1.textboxes.json",
    "1.bubbles.json",
    "1.segment_mask.json",
)


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise SystemExit(f"Expected JSON object: {path}")
    return value


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def clean_draft_files(out_dir: Path) -> None:
    for filename in DRAFT_FILENAMES:
        path = out_dir / filename
        if path.exists():
            path.unlink()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
    except ValueError:
        return False
    return True


def image_dimensions(path: Path) -> tuple[int, int]:
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
    raise SystemExit(f"Unsupported source image header: {path}")


def bbox_from(value: Any) -> list[float] | None:
    if isinstance(value, list) and len(value) == 4:
        try:
            x, y, width, height = [float(item) for item in value]
        except (TypeError, ValueError):
            return None
        if width > 0 and height > 0:
            return [round(x, 3), round(y, 3), round(width, 3), round(height, 3)]
    return None


def rect_union(rects: list[list[float]]) -> list[float] | None:
    if not rects:
        return None
    min_x = min(rect[0] for rect in rects)
    min_y = min(rect[1] for rect in rects)
    max_x = max(rect[0] + rect[2] for rect in rects)
    max_y = max(rect[1] + rect[3] for rect in rects)
    return [round(min_x, 3), round(min_y, 3), round(max_x - min_x, 3), round(max_y - min_y, 3)]


def clamp_bbox(rect: list[float], image_width: int, image_height: int) -> list[float] | None:
    x, y, width, height = rect
    min_x = max(0.0, x)
    min_y = max(0.0, y)
    max_x = min(float(image_width), x + width)
    max_y = min(float(image_height), y + height)
    if max_x <= min_x or max_y <= min_y:
        return None
    return [round(min_x, 3), round(min_y, 3), round(max_x - min_x, 3), round(max_y - min_y, 3)]


def direction_for_bbox(rect: list[float], block: dict[str, Any] | None = None) -> str:
    if block:
        angle = block.get("rotationAngleUsed")
        if angle in (90, 270):
            return "vertical"
    width = max(1.0, rect[2])
    height = max(1.0, rect[3])
    return "vertical" if height / width >= 1.45 else "horizontal"


def polygon_for_bbox(rect: list[float]) -> list[list[float]]:
    x, y, width, height = rect
    return [
        [round(x, 3), round(y, 3)],
        [round(x + width, 3), round(y, 3)],
        [round(x + width, 3), round(y + height, 3)],
        [round(x, 3), round(y + height, 3)],
    ]


def detector_lite_textboxes(probe: dict[str, Any], image_width: int, image_height: int) -> list[dict[str, Any]]:
    report = probe.get("koharuNativeTextBoxDetectorLiteReport") or {}
    raw_candidates = report.get("candidates") if isinstance(report, dict) else None
    if not isinstance(raw_candidates, list):
        return []

    textboxes: list[dict[str, Any]] = []
    for index, candidate in enumerate(raw_candidates):
        if not isinstance(candidate, dict):
            continue
        bbox = clamp_bbox(bbox_from(candidate.get("bbox")) or [], image_width, image_height)
        if not bbox:
            continue
        textboxes.append(
            {
                "id": str(candidate.get("candidateID") or f"aitrans-native-draft-textbox-{index}"),
                "bbox": bbox,
                "confidence": float(candidate.get("score") or 0),
                "detector": "aitrans-native-draft-artifact-tool",
                "sourceDirection": str(candidate.get("directionHint") or direction_for_bbox(bbox)),
                "rotationDegrees": 90 if str(candidate.get("directionHint")) == "vertical" else 0,
                "linePolygons": [polygon_for_bbox(bbox)],
                "notes": [
                    "contractExampleOnly=true",
                    "draft converted from AITRANS native detector-lite report",
                    "not active Koharu detector output",
                ],
            }
        )
    return textboxes


def block_fallback_textboxes(probe: dict[str, Any], image_width: int, image_height: int) -> list[dict[str, Any]]:
    blocks = probe.get("blocks") if isinstance(probe.get("blocks"), list) else []
    textboxes: list[dict[str, Any]] = []
    for block in blocks:
        if not isinstance(block, dict):
            continue
        index = block.get("index", len(textboxes))
        bbox = clamp_bbox(bbox_from(block.get("bbox")) or [], image_width, image_height)
        if not bbox:
            continue
        confidence = block.get("ocrConfidence")
        textboxes.append(
            {
                "id": f"aitrans-native-draft-block-{index}",
                "bbox": bbox,
                "confidence": float(confidence) if isinstance(confidence, (int, float)) else 0.5,
                "detector": "aitrans-native-draft-artifact-tool",
                "sourceDirection": direction_for_bbox(bbox, block),
                "rotationDegrees": 90 if direction_for_bbox(bbox, block) == "vertical" else 0,
                "linePolygons": [polygon_for_bbox(bbox)],
                "notes": [
                    "contractExampleOnly=true",
                    "fallback converted from final probe block bbox",
                    "not active Koharu detector output",
                ],
            }
        )
    return textboxes


def build_textboxes(probe: dict[str, Any], image_width: int, image_height: int) -> tuple[list[dict[str, Any]], str]:
    textboxes = detector_lite_textboxes(probe, image_width, image_height)
    if textboxes:
        return textboxes, "nativeDetectorLiteReport"
    return block_fallback_textboxes(probe, image_width, image_height), "finalProbeBlocksFallback"


def build_bubbles(probe: dict[str, Any], image_width: int, image_height: int) -> tuple[list[dict[str, Any]], str]:
    diagnostics = probe.get("bubbleGeometryDiagnostics")
    bubbles = diagnostics.get("bubbles") if isinstance(diagnostics, dict) else None
    result: list[dict[str, Any]] = []
    if isinstance(bubbles, list):
        for index, bubble in enumerate(bubbles):
            if not isinstance(bubble, dict):
                continue
            bbox = clamp_bbox(bbox_from(bubble.get("bbox")) or [], image_width, image_height)
            if not bbox:
                continue
            result.append(
                {
                    "id": str(bubble.get("id", index)),
                    "bbox": bbox,
                    "confidence": float(bubble.get("confidence") or 0.5),
                    "maskValue": index + 1,
                    "pixelCount": int(round(bbox[2] * bbox[3])),
                    "notes": ["contractExampleOnly=true", "draft bubble summary from probe geometry"],
                }
            )
        if result:
            return result, "bubbleGeometryDiagnostics"

    blocks = probe.get("blocks") if isinstance(probe.get("blocks"), list) else []
    grouped: dict[str, list[list[float]]] = {}
    for block in blocks:
        if not isinstance(block, dict):
            continue
        bubble_id = block.get("bubbleID")
        key = f"bubble-{bubble_id}" if bubble_id is not None else f"unassigned-{block.get('index', len(grouped))}"
        bbox = clamp_bbox(bbox_from(block.get("safeLayoutRect")) or bbox_from(block.get("bbox")) or [], image_width, image_height)
        if bbox:
            grouped.setdefault(key, []).append(bbox)

    for index, (key, rects) in enumerate(sorted(grouped.items())):
        bbox = rect_union(rects)
        if not bbox:
            continue
        result.append(
            {
                "id": key,
                "bbox": bbox,
                "confidence": 0.45,
                "maskValue": index + 1,
                "pixelCount": int(round(bbox[2] * bbox[3])),
                "notes": ["contractExampleOnly=true", "fallback bubble summary from probe block grouping"],
            }
        )
    return result, "finalProbeBlocksFallback"


def build_segment_mask(probe: dict[str, Any], image_width: int, image_height: int, source: str) -> dict[str, Any]:
    blocks = probe.get("blocks") if isinstance(probe.get("blocks"), list) else []
    glyph_pixels = 0
    connected_components = 0
    block_summaries: list[dict[str, Any]] = []
    for block in blocks:
        if not isinstance(block, dict):
            continue
        fill_rects = block.get("glyphMaskFillRects")
        fill_rect_count = len(fill_rects) if isinstance(fill_rects, list) else 0
        pixel_count = int(block.get("glyphMaskPixelCount") or 0)
        glyph_pixels += pixel_count
        connected_components += fill_rect_count
        bbox = bbox_from(block.get("glyphMaskRect"))
        block_summaries.append(
            {
                "blockIndex": block.get("index"),
                "glyphPixelCount": pixel_count,
                "glyphMaskRect": bbox,
                "fillRectCount": fill_rect_count,
            }
        )

    return {
        "sourcePath": None,
        "width": image_width,
        "height": image_height,
        "glyphPixelCount": glyph_pixels,
        "connectedComponentCount": connected_components,
        "draftSource": source,
        "blockGlyphSummaries": block_summaries,
        "notes": [
            "contractExampleOnly=true",
            "draft segment-mask summary from AITRANS glyph-mask diagnostics",
            "no real mask PNG attached",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", default="output/probe_report.json", help="AITRANS probe_report.json path.")
    parser.add_argument("--image", default=SOURCE_IMAGE, help="Source image path, defaults to test/1.png.")
    parser.add_argument("--out", default="build/koharu_native_draft", help="Output directory for four draft artifact files.")
    args = parser.parse_args()

    probe_path = Path(args.probe)
    image_path = Path(args.image)
    out_dir = Path(args.out)
    active_artifact_dir = Path("test/koharu_artifacts")
    if not probe_path.is_file():
        raise SystemExit(f"Missing probe report: {probe_path}")
    if not image_path.is_file():
        raise SystemExit(f"Missing source image: {image_path}")
    if is_relative_to(out_dir, active_artifact_dir):
        raise SystemExit(
            "Refusing to write draft artifacts under test/koharu_artifacts; "
            "draft output must stay non-active."
        )

    probe = load_json(probe_path)
    image_width, image_height = image_dimensions(image_path)
    source_sha = sha256_file(image_path)
    textboxes, textbox_source = build_textboxes(probe, image_width, image_height)
    bubbles, bubble_source = build_bubbles(probe, image_width, image_height)
    segment_mask = build_segment_mask(probe, image_width, image_height, textbox_source)
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    clean_draft_files(out_dir)

    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "sourceImage": str(image_path),
        "sourceImageSHA256": source_sha,
        "coordinateSpace": COORDINATE_SPACE,
        "contractExampleOnly": True,
        "generatedBy": "aitrans-native-draft-artifact-tool",
        "generatedAt": generated_at,
        "textBoxesPath": "1.textboxes.json",
        "bubbleMaskPath": "1.bubbles.json",
        "segmentMaskPath": "1.segment_mask.json",
        "draftSource": {
            "probeReport": str(probe_path),
            "textBoxes": textbox_source,
            "bubbleMask": bubble_source,
            "segmentMask": "glyphMaskDiagnostics",
        },
        "counts": {
            "textBoxes": len(textboxes),
            "bubbleInstances": len(bubbles),
            "segmentGlyphPixelCount": segment_mask["glyphPixelCount"],
        },
        "notes": [
            "contractExampleOnly=true",
            "non-active draft generated outside test/koharu_artifacts",
            "not real Koharu detector output",
        ],
    }

    write_json(out_dir / "1.manifest.json", manifest)
    write_json(out_dir / "1.textboxes.json", {"textBoxes": textboxes})
    write_json(out_dir / "1.bubbles.json", {"bubbleInstances": bubbles})
    write_json(out_dir / "1.segment_mask.json", segment_mask)

    summary = {
        "outputDirectory": str(out_dir),
        "contractExampleOnly": True,
        "textBoxCount": len(textboxes),
        "bubbleInstanceCount": len(bubbles),
        "segmentGlyphPixelCount": segment_mask["glyphPixelCount"],
        "textBoxSource": textbox_source,
        "bubbleSource": bubble_source,
        "sourceImageSHA256": source_sha,
        "nextValidationCommand": f"python3 scripts/validate-koharu-artifacts.py --root {out_dir}",
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
