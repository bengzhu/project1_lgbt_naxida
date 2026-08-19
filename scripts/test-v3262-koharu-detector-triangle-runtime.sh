#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3262-triangle.XXXXXX")
bundle="$runtime_root/KoharuDetectorTriangleHarness.app"
resources="$bundle/Contents/Resources"
executable="$bundle/Contents/MacOS/KoharuDetectorTriangleHarness"

cleanup() {
  if command -v trash >/dev/null 2>&1 && [ -d "$runtime_root" ]; then
    trash "$runtime_root"
  fi
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$resources" "$(dirname "$executable")"
plutil -create xml1 "$bundle/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.local.aitrans.koharu-detector-triangle "$bundle/Contents/Info.plist"
plutil -insert CFBundleExecutable -string KoharuDetectorTriangleHarness "$bundle/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$bundle/Contents/Info.plist"

xcrun coremlcompiler compile \
  "$repo_root/AITRANS/Resources/ComicTextDetector/ComicTextBubbleDetectorINT8.mlpackage" \
  "$resources"

xcrun swiftc -parse-as-library \
  "$repo_root/AITRANS/Models/ImageOCRProvenance.swift" \
  "$repo_root/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$repo_root/AITRANS/Services/ComicTextBubbleDetectorService.swift" \
  "$repo_root/scripts/fixtures/v3262-koharu-detector-triangle-harness.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" | tee "$output"
python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
for marker in [
    "preprocess=triangle+device-rgb",
    "source=2x2 rgba target=640x640",
    "corners=",
    "center=",
]:
    if marker not in text:
        raise SystemExit(f"missing {marker}: {text}")
match = re.search(r"^checksum=([0-9a-f]+)$", text, re.MULTILINE)
if match is None or match.group(1) != "e7e9d1fe4bb47c45":
    raise SystemExit(f"missing stable Triangle checksum: {text}")
if "corners=255,0,0;0,255,0;0,0,255;255,255,255" not in text:
    raise SystemExit(f"triangle corner orientation changed: {text}")
if "center=128,128,128" not in text:
    raise SystemExit(f"triangle center sampling changed: {text}")
PY

if [ ! -f "$repo_root/test/jap.jpg" ]; then
  echo "missing fixed Japanese fixture test/jap.jpg" >&2
  exit 1
fi

detector_output="$runtime_root/detector-output.txt"
"$executable" "$repo_root/test/jap.jpg" | tee "$detector_output"
python3 - "$detector_output" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"^detectorRegions=(\d+)$", text, re.MULTILINE)
if match is None or int(match.group(1)) != 5:
    raise SystemExit(f"expected five detector regions for test/jap.jpg after Triangle parity: {text}")
PY
