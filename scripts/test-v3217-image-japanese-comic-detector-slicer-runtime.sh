#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3217-slicer.XXXXXX")
cleanup() {
  if command -v trash >/dev/null 2>&1 && [ -d "$runtime_root" ]; then
    trash "$runtime_root"
  fi
}
trap cleanup EXIT HUP INT TERM

bundle="$runtime_root/AITRANSComicDetectorHarness.app"
resources="$bundle/Contents/Resources"
executable="$bundle/Contents/MacOS/AITRANSComicDetectorHarness"

mkdir -p "$resources" "$(dirname "$executable")"
plutil -create xml1 "$bundle/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.local.aitrans.comic-detector-harness "$bundle/Contents/Info.plist"
plutil -insert CFBundleExecutable -string AITRANSComicDetectorHarness "$bundle/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$bundle/Contents/Info.plist"

xcrun coremlcompiler compile \
  "$repo_root/AITRANS/Resources/ComicTextDetector/ComicTextBubbleDetectorINT8.mlpackage" \
  "$resources"
xcrun swiftc -parse-as-library \
  "$repo_root/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$repo_root/AITRANS/Services/ComicTextBubbleDetectorService.swift" \
  "$repo_root/scripts/fixtures/v3217-comic-detector-slicer-runtime-harness.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" "$repo_root/test/jap.jpg" | tee "$output"
python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys


text = Path(sys.argv[1]).read_text(encoding="utf-8")
if "copies=4" not in text or "image=1136x6400" not in text:
    raise SystemExit(f"unexpected tall fixture geometry: {text}")
match = re.search(r"^regions=(\d+)$", text, re.MULTILINE)
if match is None or not 16 <= int(match.group(1)) <= 18:
    raise SystemExit(f"expected detector regions across the tall page: {text}")

rects = []
for values in re.findall(
    r"^region=([0-9.]+),([0-9.]+),([0-9.]+),([0-9.]+) confidence=([0-9.]+)$",
    text,
    re.MULTILINE,
):
    rects.append(tuple(float(value) for value in values))
if len(rects) != int(match.group(1)):
    raise SystemExit(f"region ledger count mismatch: {text}")
if not any(y < 0.20 for _, y, _, _, _ in rects):
    raise SystemExit(f"missing detector coverage near the tall-page top: {text}")
if not any(y > 0.75 for _, y, _, _, _ in rects):
    raise SystemExit(f"missing detector coverage near the tall-page bottom: {text}")
for quarter in range(4):
    lower = quarter * 0.25
    upper = lower + 0.25
    if sum(lower <= y < upper for _, y, _, _, _ in rects) < 4:
        raise SystemExit(f"insufficient detector coverage in quarter {quarter}: {text}")
if any(width <= 0 or height <= 0 or width > 1 or height > 0.30 for _, _, width, height, _ in rects):
    raise SystemExit(f"invalid or page-spanning detector region: {text}")
PY
