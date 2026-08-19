#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3264-quad.XXXXXX")
executable="$runtime_root/KoharuVerticalQuadWarpHarness"

cleanup() {
  if command -v trash >/dev/null 2>&1 && [ -d "$runtime_root" ]; then
    trash "$runtime_root"
  fi
}
trap cleanup EXIT HUP INT TERM

xcrun swiftc -parse-as-library \
  "$repo_root/AITRANS/Models/ImageOCRProvenance.swift" \
  "$repo_root/AITRANS/Services/MangaOCRService.swift" \
  "$repo_root/scripts/fixtures/v3264-koharu-vertical-quad-warp-harness.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" | tee "$output"

python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
for marker in [
    "warp=projective+bilinear",
    "source=4x4 rgba target=5x7",
    "size=5x7",
    "pixels=",
    "center=",
]:
    if marker not in text:
        raise SystemExit(f"missing {marker}: {text}")
match = re.search(r"^checksum=([0-9a-f]+)$", text, re.MULTILINE)
if match is None or match.group(1) != "e0288a1c4c38d1f8":
    raise SystemExit(f"vertical quad bilinear checksum changed: {text}")
if "center=89,119,95,255" not in text:
    raise SystemExit(f"vertical quad center sample changed: {text}")
PY
