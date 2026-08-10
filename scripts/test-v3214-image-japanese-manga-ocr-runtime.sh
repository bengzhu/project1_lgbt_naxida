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
if [ -d "$repo_root/AITRANS/Resources/MangaOCR/MangaOCREncoderINT8Batch.mlpackage" ] \
  && [ -d "$repo_root/AITRANS/Resources/MangaOCR/MangaOCRDecoderINT8Batch.mlpackage" ]; then
  xcrun coremlcompiler compile \
    "$repo_root/AITRANS/Resources/MangaOCR/MangaOCREncoderINT8Batch.mlpackage" \
    "$resources"
  xcrun coremlcompiler compile \
    "$repo_root/AITRANS/Resources/MangaOCR/MangaOCRDecoderINT8Batch.mlpackage" \
    "$resources"
fi
xcrun coremlcompiler compile \
  "$repo_root/AITRANS/Resources/ComicTextDetector/ComicTextBubbleDetectorINT8.mlpackage" \
  "$resources"
xcrun swiftc -parse-as-library \
  "$repo_root/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$repo_root/AITRANS/Services/MangaOCRService.swift" \
  "$repo_root/AITRANS/Services/ComicTextBubbleDetectorService.swift" \
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
if "batchInference=true" not in text:
    raise SystemExit(f"expected bundled flexible-batch Manga OCR runtime: {text}")
match = re.search(r"^blocks=(\d+)$", text, re.MULTILINE)
if match is None or int(match.group(1)) != 5:
    raise SystemExit(f"expected exactly 5 detector-grouped OCR blocks, got: {text}")
for expected in [
    "前は生意気に俺の誘い断りやがって．．．",
    "今度こそこの爆乳を持ち帰る！",
    "そのせいでつまんねー女に絡まれるし．．．",
    "監督より挨拶をお願いします",
]:
    if expected not in text:
        raise SystemExit(f"missing expected Manga OCR text: {expected}")
for rejected in [
    "今度こそこの暴れ",
    "そのせいでつまりまーズ",
    "うまんねー女に",
    "vertical\tいします",
    "前は生意気に\n",
    "俺の誘い断り\n",
]:
    if rejected in text:
        raise SystemExit(f"retained cross-column or truncated Manga OCR text: {rejected}")
block_lines = [
    line
    for line in text.splitlines()
    if re.match(r"^(horizontal|vertical|unknown)\t", line)
]
if len(block_lines) != 5:
    raise SystemExit(f"expected five parsed sample blocks: {text}")
if not all(line.startswith("vertical\t") for line in block_lines):
    raise SystemExit(f"expected vertical provenance for every sample block: {text}")
PY
