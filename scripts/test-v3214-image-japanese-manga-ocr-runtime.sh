#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3214-runtime.XXXXXX")
bundle="$runtime_root/AITRANSMangaHarness.app"
resources="$bundle/Contents/Resources"
executable="$bundle/Contents/MacOS/AITRANSMangaHarness"

mkdir -p "$resources" "$(dirname "$executable")"
plutil -create xml1 "$bundle/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.local.aitrans.manga-harness "$bundle/Contents/Info.plist"
plutil -insert CFBundleExecutable -string AITRANSMangaHarness "$bundle/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$bundle/Contents/Info.plist"

cp "$repo_root/AITRANS/Resources/MangaOCR/MangaOCRVocab.txt" "$resources/"
xcrun coremlcompiler compile \
  "$repo_root/AITRANS/Resources/MangaOCR/MangaOCREncoderINT8.mlpackage" \
  "$resources"
xcrun coremlcompiler compile \
  "$repo_root/AITRANS/Resources/MangaOCR/MangaOCRDecoderINT8.mlpackage" \
  "$resources"
xcrun swiftc -parse-as-library \
  "$repo_root/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$repo_root/AITRANS/Services/MangaOCRService.swift" \
  "$repo_root/AITRANS/Services/VisionOCRService.swift" \
  "$repo_root/scripts/fixtures/v3214-manga-ocr-runtime-harness.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" "$repo_root/test/jap.jpg" | tee "$output"
python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"^blocks=(\d+)$", text, re.MULTILINE)
if match is None or int(match.group(1)) < 10:
    raise SystemExit(f"expected at least 10 OCR blocks, got: {text}")
for expected in ["前は生意気に", "持ち帰る", "監督より挨拶を"]:
    if expected not in text:
        raise SystemExit(f"missing expected Manga OCR text: {expected}")
if not all(line.startswith("vertical\t") for line in text.splitlines()[1:] if line):
    raise SystemExit(f"expected vertical provenance for every sample block: {text}")
PY
