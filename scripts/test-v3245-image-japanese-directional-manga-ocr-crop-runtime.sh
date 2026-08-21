#!/bin/sh
set -eu

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/aitrans-v3245-directional-crop.XXXXXX")
cleanup() {
  if command -v trash >/dev/null 2>&1 && [ -d "$runtime_root" ]; then
    trash "$runtime_root"
  fi
}
trap cleanup EXIT HUP INT TERM

bundle="$runtime_root/AITRANSDirectionalCropHarness.app"
resources="$bundle/Contents/Resources"
executable="$bundle/Contents/MacOS/AITRANSDirectionalCropHarness"

mkdir -p "$resources" "$(dirname "$executable")"
plutil -create xml1 "$bundle/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.local.aitrans.directional-crop-harness "$bundle/Contents/Info.plist"
plutil -insert CFBundleExecutable -string AITRANSDirectionalCropHarness "$bundle/Contents/Info.plist"
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
  "$repo_root/AITRANS/Models/TranslationContextQuality.swift" \
  "$repo_root/AITRANS/Models/JapaneseOCRTextNormalizer.swift" \
  "$repo_root/AITRANS/Services/ImageOCRLayoutEngine.swift" \
  "$repo_root/AITRANS/Services/MangaOCRService.swift" \
  "$repo_root/AITRANS/Services/ComicTextBubbleDetectorService.swift" \
  "$repo_root/AITRANS/Services/VisionOCRService.swift" \
  "$repo_root/scripts/fixtures/v3245-directional-manga-ocr-crop-runtime-harness.swift" \
  -o "$executable"

output="$runtime_root/output.txt"
"$executable" "$repo_root/test/jap.jpg" | tee "$output"
python3 - "$output" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
if "batchInference=true" not in text:
    raise SystemExit(f"expected bundled Manga OCR runtime: {text}")
if "effectiveDirection=vertical" not in text:
    raise SystemExit(f"vertical direction override was not consumed: {text}")
match = re.search(r"^detectorRegions=(\d+)$", text, re.MULTILINE)
if match is None or int(match.group(1)) < 4:
    raise SystemExit(f"expected detector regions for directional crop runtime: {text}")
result = re.search(r"^text=(.+)$", text, re.MULTILINE)
if result is None or "爆乳" not in result.group(1):
    raise SystemExit(f"vertical Manga OCR crop did not recover the fixture text: {text}")
confidence = re.search(r"^confidence=([-0-9.eE]+)$", text, re.MULTILINE)
if confidence is None or float(confidence.group(1)) < 0.55:
    raise SystemExit(f"directional Manga OCR result is not reliable: {text}")
if "horizontalDirection=horizontal" not in text:
    raise SystemExit(f"horizontal direction override was not consumed: {text}")
horizontal = re.search(r"^horizontalText=(.+)$", text, re.MULTILINE)
if horizontal is None or "爆乳" not in horizontal.group(1):
    raise SystemExit(f"horizontal Manga OCR crop did not recover the fixture text: {text}")
horizontal_confidence = re.search(
    r"^horizontalConfidence=([-0-9.eE]+)$", text, re.MULTILINE
)
if horizontal_confidence is None or float(horizontal_confidence.group(1)) < 0.55:
    raise SystemExit(f"horizontal Manga OCR result is not reliable: {text}")
PY
