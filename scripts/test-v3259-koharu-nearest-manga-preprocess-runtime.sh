#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3259-preprocess.XXXXXX")
executable="$runtime_root/KoharuNearestMangaPreprocessHarness"

xcrun swiftc -parse-as-library \
  "$repo_root/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$repo_root/AITRANS/Services/MangaOCRService.swift" \
  "$repo_root/scripts/fixtures/v3259-koharu-nearest-manga-preprocess-harness.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" | tee "$output"
python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
if "preprocess=nearest" not in text:
    raise SystemExit(f"missing nearest preprocessing marker: {text}")
if "source=3x2 target=224x224" not in text:
    raise SystemExit(f"missing source/target dimensions: {text}")
match = re.search(r"^checksum=([0-9a-f]+)$", text, re.MULTILINE)
if match is None or len(match.group(1)) < 8:
    raise SystemExit(f"missing stable plane checksum: {text}")
if "samples=1,1,2,2,2,3,1,4,6" not in text:
    raise SystemExit(f"nearest floor mapping samples changed: {text}")
if "quadrants=16,32,64,128" not in text:
    raise SystemExit(f"quadrant orientation samples changed: {text}")
PY
