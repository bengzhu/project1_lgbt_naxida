#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3238-quad-fallback.XXXXXX")
cleanup() {
  if command -v trash >/dev/null 2>&1 && [ -d "$runtime_root" ]; then
    trash "$runtime_root"
  fi
}
trap cleanup EXIT HUP INT TERM

bundle="$runtime_root/AITRANSQuadFallbackHarness.app"
resources="$bundle/Contents/Resources"
executable="$bundle/Contents/MacOS/AITRANSQuadFallbackHarness"

mkdir -p "$resources" "$(dirname "$executable")"
plutil -create xml1 "$bundle/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.local.aitrans.quad-fallback-harness "$bundle/Contents/Info.plist"
plutil -insert CFBundleExecutable -string AITRANSQuadFallbackHarness "$bundle/Contents/Info.plist"
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
  "$repo_root/AITRANS/Models/ImageOCRProvenance.swift" \
  "$repo_root/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$repo_root/AITRANS/Services/MangaOCRService.swift" \
  "$repo_root/AITRANS/Services/ComicTextBubbleDetectorService.swift" \
  "$repo_root/AITRANS/Services/VisionOCRService.swift" \
  "$repo_root/scripts/fixtures/v3238-manga-ocr-quad-bbox-fallback-runtime-harness.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" "$repo_root/test/jap.jpg" | tee "$output"
python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys


text = Path(sys.argv[1]).read_text(encoding="utf-8")
for marker in [
    "batchInference=true",
    "blankResults=1",
    "blankConfidence=",
    "blankText=",
    "fallbackResults=1",
    "fallbackConfidence=",
    "fallbackText=",
]:
    if marker not in text:
        raise SystemExit(f"missing quad-to-bbox fallback evidence {marker}: {text}")
match = re.search(r"^detectorRegions=(\d+)$", text, re.MULTILINE)
if match is None or int(match.group(1)) < 1:
    raise SystemExit(f"expected a real RT-DETR text region: {text}")
blank_confidence = re.search(r"^blankConfidence=([0-9.]+)$", text, re.MULTILINE)
fallback_confidence = re.search(r"^fallbackConfidence=([0-9.]+)$", text, re.MULTILINE)
blank = re.search(r"^blankText=(.+)$", text, re.MULTILINE)
fallback = re.search(r"^fallbackText=(.+)$", text, re.MULTILINE)
if blank_confidence is None or float(blank_confidence.group(1)) >= 0.55:
    raise SystemExit(f"blank bbox must produce a weak primary result: {text}")
if fallback_confidence is None or float(fallback_confidence.group(1)) < 0.55:
    raise SystemExit(f"line quad retry must produce a reliable result: {text}")
if blank is None or fallback is None or blank.group(1) == fallback.group(1):
    raise SystemExit(f"line quad retry did not replace the weak bbox text: {text}")
if not re.search(r"[\u3041-\u30ff\u3400-\u9fff]", fallback.group(1)):
    raise SystemExit(f"line quad retry did not recover Japanese Manga OCR text: {text}")
PY
