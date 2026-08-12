#!/usr/bin/env bash
set -euo pipefail

# This script deliberately refuses to compile or download the GPL model on a
# developer machine.  The dedicated GitHub Actions workflow is the only
# execution boundary for the reference MIT48 runtime.
if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
  echo "MIT48 cloud smoke is cloud-only; set GITHUB_ACTIONS=true in GitHub Actions" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_ROOT="${KOHARU_MIT48_OUTPUT_ROOT:-${RUNNER_TEMP:?RUNNER_TEMP is required}/koharu-mit48-output}"
MODEL_ROOT="${KOHARU_MIT48_ARTIFACT_ROOT:-${RUNNER_TEMP:?RUNNER_TEMP is required}/koharu-mit48-model}"
CARGO_TARGET_DIR="${KOHARU_MIT48_CARGO_TARGET_DIR:-${RUNNER_TEMP:?RUNNER_TEMP is required}/koharu-mit48-cargo}"
KOHARU_DATA_ROOT="${KOHARU_DATA_ROOT:-${RUNNER_TEMP:?RUNNER_TEMP is required}/koharu-mit48-runtime}"
KOHARU_SOURCE_ROOT="${KOHARU_SOURCE_ROOT:-$REPO_ROOT/reference/koharu-main}"
KOHARU_SOURCE_REVISION="35f3e6d1a418d9617fd922e2bc865fe5b8fff818"
LLAMA_CPP_TAG="${LLAMA_CPP_TAG:-b8935}"
MIT48_RUNTIME_DOWNLOAD_MAX_ATTEMPTS=3

test -f "$KOHARU_SOURCE_ROOT/LICENSE"
test -f "$KOHARU_SOURCE_ROOT/koharu-ml/Cargo.toml"
test "$(git -C "$KOHARU_SOURCE_ROOT" rev-parse HEAD)" = "$KOHARU_SOURCE_REVISION"
export KOHARU_DATA_ROOT KOHARU_SOURCE_ROOT LLAMA_CPP_TAG

mkdir -p "$OUTPUT_ROOT/crops" "$OUTPUT_ROOT/predictions" "$MODEL_ROOT" "$CARGO_TARGET_DIR"

python3 "$REPO_ROOT/scripts/validate-koharu-mit48px-artifact.py" \
  --root "$MODEL_ROOT" \
  --download \
  --json-output "$OUTPUT_ROOT/artifact-validation.json"

python3 - "$REPO_ROOT/test/jap.jpg" "$OUTPUT_ROOT" <<'PY'
from __future__ import annotations

import json
from pathlib import Path
import sys

from PIL import Image, ImageOps

source = Path(sys.argv[1])
output = Path(sys.argv[2])
image = ImageOps.exif_transpose(Image.open(source)).convert("RGB")

# These are deliberately bounded, human-auditable line crops from test/jap.jpg.
# Koharu's image-rs rotate270 is a 270-degree clockwise rotation; Pillow's
# positive angles are counter-clockwise, so rotate(90) is the equivalent
# vertical-to-horizontal canvas orientation used by warp_line_region.
specs = [
    ("left-column-a", (238, 86, 322, 448)),
    ("left-column-b", (322, 86, 405, 448)),
    # Connected-component bounds for 今度こそ are approximately x=393..448;
    # keep a small measured margin instead of clipping the first glyph at x=405.
    ("left-column-c", (388, 86, 452, 448)),
    ("right-column-a", (864, 136, 908, 298)),
    ("right-column-b", (904, 116, 970, 432)),
    ("right-column-c", (968, 116, 1030, 432)),
    ("compact-niko", (532, 1050, 578, 1142)),
]

manifest = []
for name, box in specs:
    crop = image.crop(box).rotate(90, expand=True)
    path = output / "crops" / f"{name}.png"
    crop.save(path, format="PNG")
    manifest.append({"id": name, "box": list(box), "path": str(path), "size": list(crop.size)})

(output / "crop-manifest.json").write_text(
    json.dumps({"source": str(source), "sourceSize": list(image.size), "crops": manifest}, indent=2) + "\n",
    encoding="utf-8",
)
PY

export CARGO_TARGET_DIR
cargo build \
  --manifest-path "$KOHARU_SOURCE_ROOT/koharu-ml/Cargo.toml" \
  --bin mit48px-ocr \
  --release \
  --locked \
  2>&1 | tee "$OUTPUT_ROOT/cargo-build.log"

BINARY="$CARGO_TARGET_DIR/release/mit48px-ocr"
test -x "$BINARY"

is_transient_llama_runtime_download_failure() {
  local log="$1"
  grep -Fq 'failed to prepare package `runtime:llama`' "$log" || return 1
  grep -Fq "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_CPP_TAG/" "$log" || return 1
  grep -Eqi 'HTTP status server error \(5[0-9][0-9]|HTTP status client error \(429|http2 error|refused stream|timed out|timeout|connection reset|connection closed|error sending request' "$log"
}

run_mit48_crop() {
  local crop="$1"
  local id="$2"
  local output_log="$OUTPUT_ROOT/predictions/$id.stdout.log"
  local runtime_attempt=1
  : >"$output_log"

  while (( runtime_attempt <= MIT48_RUNTIME_DOWNLOAD_MAX_ATTEMPTS )); do
    local attempt_log="$OUTPUT_ROOT/predictions/$id.runtime-attempt-$runtime_attempt.log"
    local status
    if "$BINARY" \
      --input "$crop" \
      --model-dir "$MODEL_ROOT" \
      --json-output "$OUTPUT_ROOT/predictions/$id.json" \
      --cpu \
      >"$attempt_log" \
      2>&1; then
      cat "$attempt_log" >>"$output_log"
      return 0
    else
      status=$?
    fi

    cat "$attempt_log" >>"$output_log"
    if (( runtime_attempt >= MIT48_RUNTIME_DOWNLOAD_MAX_ATTEMPTS )) \
      || ! is_transient_llama_runtime_download_failure "$attempt_log"; then
      cat "$output_log" >&2
      return "$status"
    fi

    echo "Retrying pinned llama runtime download after transient failure ($runtime_attempt/$MIT48_RUNTIME_DOWNLOAD_MAX_ATTEMPTS)" \
      | tee -a "$output_log" >&2
    sleep "$((runtime_attempt * 5))"
    runtime_attempt=$((runtime_attempt + 1))
  done
}

while IFS= read -r crop; do
  id="$(basename "$crop" .png)"
  run_mit48_crop "$crop" "$id"
done < <(find "$OUTPUT_ROOT/crops" -maxdepth 1 -type f -name '*.png' -print | sort)

python3 - "$OUTPUT_ROOT" <<'PY'
from __future__ import annotations

import json
import math
from pathlib import Path
import sys

output = Path(sys.argv[1])


def japanese_density(text: str) -> float:
    if not text:
        return 0.0
    japanese = sum(
        1
        for char in text
        if (
            "\u3040" <= char <= "\u30ff"
            or "\u3400" <= char <= "\u4dbf"
            or "\u4e00" <= char <= "\u9fff"
            or "\uff66" <= char <= "\uff9f"
        )
    )
    return japanese / len(text)


rows = []
accepted = []
for path in sorted((output / "predictions").glob("*.json")):
    payload = json.loads(path.read_text(encoding="utf-8"))
    regions = payload.get("regions")
    if not isinstance(regions, list) or len(regions) != 1:
        raise AssertionError(f"{path.name}: expected one MIT48 region prediction")
    prediction = regions[0]
    text = str(prediction.get("text", ""))
    confidence = float(prediction.get("confidence", 0.0))
    density = japanese_density(text)
    row = {
        "id": path.stem,
        "text": text,
        "confidence": confidence,
        "japaneseScriptDensity": density,
        "textLength": len(text),
    }
    rows.append(row)
    if text.strip() and math.isfinite(confidence) and density >= 0.5:
        accepted.append(row)

if not accepted:
    raise AssertionError("MIT48 reference runtime produced no nonempty Japanese crop output")

if len(accepted) < 7:
    raise AssertionError(
        f"MIT48 reference runtime accepted only {len(accepted)}/7 Japanese crops"
    )

compact = next((row for row in rows if row["id"] == "compact-niko"), None)
if compact is None or compact["text"] != "ニコッ":
    raise AssertionError(f"compact-niko did not recover ニコッ: {compact}")
if compact["confidence"] < 0.55:
    raise AssertionError(f"compact-niko confidence is below 0.55: {compact}")

left_column_c = next((row for row in rows if row["id"] == "left-column-c"), None)
if left_column_c is None or left_column_c["text"] != "今度こそ":
    raise AssertionError(f"left-column-c did not recover 今度こそ: {left_column_c}")
if left_column_c["confidence"] < 0.55:
    raise AssertionError(f"left-column-c confidence is below 0.55: {left_column_c}")

report = {
    "status": "success",
    "runtime": "koharu-ml/bin/mit48px-ocr",
    "source": "test/jap.jpg",
    "orientation": "Pillow rotate90 equivalent to Koharu image-rs rotate270",
    "cropCount": len(rows),
    "acceptedJapanesePredictions": len(accepted),
    "qualityGate": {
        "minimumAcceptedJapanesePredictions": 7,
        "compactNikoText": "ニコッ",
        "compactNikoMinimumConfidence": 0.55,
        "leftColumnCText": "今度こそ",
        "leftColumnCMinimumConfidence": 0.55,
    },
    "predictions": rows,
    "qualityClaim": "cloud reference smoke only; no general OCR quality claim",
}
(output / "mit48px-smoke-report.json").write_text(
    json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
)
print(json.dumps(report, ensure_ascii=False))
PY
