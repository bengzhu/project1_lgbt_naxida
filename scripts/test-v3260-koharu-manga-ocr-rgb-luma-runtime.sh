#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3260-rgb-luma.XXXXXX")
executable="$runtime_root/KoharuMangaOCRRGBLumaHarness"

xcrun swiftc -parse-as-library \
  "$repo_root/AITRANS/Models/ImageOCRProvenance.swift" \
  "$repo_root/AITRANS/Models/JapaneseOCRTextNormalizer.swift" \
  "$repo_root/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$repo_root/AITRANS/Services/MangaOCRService.swift" \
  "$repo_root/scripts/fixtures/v3260-koharu-manga-ocr-rgb-luma-harness.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" | tee "$output"
python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
if "preprocess=nearest+luma-floor" not in text:
    raise SystemExit(f"missing RGB/luma preprocessing marker: {text}")
if "source=2x2 rgba target=224x224" not in text:
    raise SystemExit(f"missing RGB fixture dimensions: {text}")
if "rgbLuma=54,182,18,255" not in text:
    raise SystemExit(f"RGB luma values changed: {text}")
if "floorProbe=0" not in text:
    raise SystemExit(f"luma floor probe changed: {text}")
match = re.search(r"^checksum=([0-9a-f]+)$", text, re.MULTILINE)
if match is None or len(match.group(1)) < 8:
    raise SystemExit(f"missing stable RGB plane checksum: {text}")
PY
