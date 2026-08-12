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
KOHARU_SOURCE_ROOT="${KOHARU_SOURCE_ROOT:-$REPO_ROOT/reference/koharu-main}"
KOHARU_SOURCE_REVISION="35f3e6d1a418d9617fd922e2bc865fe5b8fff818"
LLAMA_CPP_TAG="${LLAMA_CPP_TAG:-b8935}"

test -f "$KOHARU_SOURCE_ROOT/LICENSE"
test -f "$KOHARU_SOURCE_ROOT/koharu-ml/Cargo.toml"
test "$(git -C "$KOHARU_SOURCE_ROOT" rev-parse HEAD)" = "$KOHARU_SOURCE_REVISION"
export KOHARU_SOURCE_ROOT LLAMA_CPP_TAG

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
# The source columns are vertical; rotate270 produces the horizontal MIT48 line
# canvas used by Koharu's warp_line_region path.
specs = [
    ("left-column-a", (238, 86, 322, 448)),
    ("left-column-b", (322, 86, 405, 448)),
    ("left-column-c", (405, 86, 491, 448)),
    ("right-column-a", (846, 116, 906, 432)),
    ("right-column-b", (904, 116, 970, 432)),
    ("right-column-c", (968, 116, 1030, 432)),
    ("compact-niko", (523, 900, 650, 1178)),
]

manifest = []
for name, box in specs:
    crop = image.crop(box).rotate(270, expand=True)
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

while IFS= read -r crop; do
  id="$(basename "$crop" .png)"
  "$BINARY" \
    --input "$crop" \
    --model-dir "$MODEL_ROOT" \
    --json-output "$OUTPUT_ROOT/predictions/$id.json" \
    --cpu \
    >"$OUTPUT_ROOT/predictions/$id.stdout.log" \
    2>&1
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

report = {
    "status": "success",
    "runtime": "koharu-ml/bin/mit48px-ocr",
    "source": "test/jap.jpg",
    "cropCount": len(rows),
    "acceptedJapanesePredictions": len(accepted),
    "predictions": rows,
    "qualityClaim": "cloud reference smoke only; no general OCR quality claim",
}
(output / "mit48px-smoke-report.json").write_text(
    json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
)
print(json.dumps(report, ensure_ascii=False))
PY
